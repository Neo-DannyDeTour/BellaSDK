"""Generate 3 chipwood industrial sheets + 1 braced crate (.glb, Z=0, -Y fwd, 1m UV)."""

from __future__ import annotations

import math
from pathlib import Path
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene, export_godot_glb


def _apply_metric_box_uv(bm: bmesh.types.BMesh, uv_scale: float = 1.0) -> None:
    """Project exact 1m x 1m world-space box UVs (no uv1_triplanar needed)."""
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x, co.y
            elif ax >= ay and ax >= az:
                u, v = co.y, co.z
            else:
                u, v = co.x, co.z
            loop[uv_layer].uv = (u / uv_scale, v / uv_scale)


def _assign_material(obj: bpy.types.Object, mat_name: str) -> None:
    mat = bpy.data.materials.get(mat_name)
    if mat is None:
        mat = bpy.data.materials.new(name=mat_name)
        mat.use_nodes = True
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def _add_beveled_box(
    bm: bmesh.types.BMesh,
    size: tuple[float, float, float],
    center: tuple[float, float, float],
    bevel_offset: float,
    segments: int = 2,
) -> None:
    sx, sy, sz = size
    mat = Matrix.Translation(Vector(center)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    ret = bmesh.ops.create_cube(bm, size=1.0, matrix=mat)
    verts = ret["verts"]
    edges = list({e for v in verts for e in v.link_edges})
    bmesh.ops.bevel(
        bm,
        geom=edges,
        offset=bevel_offset,
        segments=segments,
        affect="EDGES",
        clamp_overlap=True,
    )


def _export_sheet(slug: str, mat_name: str) -> None:
    clean_scene()
    w, t, h = 1.22, 0.018, 2.44
    bm = bmesh.new()
    _add_beveled_box(bm, (w, t, h), (0.0, 0.0, h * 0.5), bevel_offset=0.0025, segments=2)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_metric_box_uv(bm, uv_scale=1.0)

    mesh = bpy.data.meshes.new("SheetMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("SheetMesh", mesh)
    bpy.context.collection.objects.link(obj)
    _assign_material(obj, mat_name)

    out_path = Path(f"assets/models/{slug}/{slug}.glb")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    export_godot_glb(str(out_path), export_animations=False)


def _export_crate(slug: str, mat_name: str) -> None:
    clean_scene()
    bm = bmesh.new()

    # Recessed chipwood inner body (0.94m cube, resting at Z=0.03m)
    _add_beveled_box(bm, (0.94, 0.94, 0.94), (0.0, 0.0, 0.50), bevel_offset=0.004, segments=1)

    # 12 perimeter frame battens (1.0m outer envelope, Z=0 base)
    b = 0.06  # batten width
    d = 0.03  # batten thickness
    # 4 vertical corner posts
    for sx in (-0.47, 0.47):
        for sy in (-0.47, 0.47):
            _add_beveled_box(bm, (b, b, 1.00), (sx, sy, 0.50), bevel_offset=0.004, segments=1)
    # 4 horizontal X rails (front/back, bottom/top)
    for sy in (-0.485, 0.485):
        for sz in (0.03, 0.97):
            _add_beveled_box(bm, (0.88, d, b), (0.0, sy, sz), bevel_offset=0.004, segments=1)
    # 4 horizontal Y rails (left/right, bottom/top)
    for sx in (-0.485, 0.485):
        for sz in (0.03, 0.97):
            _add_beveled_box(bm, (d, 0.88, b), (sx, 0.0, sz), bevel_offset=0.004, segments=1)

    # 2 angled front/back diagonal braces
    diag_len = math.hypot(0.84, 0.84)
    for sy in (-0.485, 0.485):
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        scale_m = Matrix.Diagonal((diag_len, d, 0.055, 1.0))
        rot_m = Matrix.Rotation(math.radians(45.0), 4, "Y")
        trans_m = Matrix.Translation(Vector((0.0, sy, 0.50)))
        bmesh.ops.transform(bm, matrix=trans_m @ rot_m @ scale_m, verts=verts)
        edges = list({e for v in verts for e in v.link_edges})
        bmesh.ops.bevel(bm, geom=edges, offset=0.003, segments=1, affect="EDGES", clamp_overlap=True)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_metric_box_uv(bm, uv_scale=1.0)

    mesh = bpy.data.meshes.new("CrateMesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("CrateMesh", mesh)
    bpy.context.collection.objects.link(obj)
    _assign_material(obj, mat_name)

    out_path = Path(f"assets/models/{slug}/{slug}.glb")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    export_godot_glb(str(out_path), export_animations=False)


def main() -> None:
    _export_sheet("chipwood_sheet_osb_raw", "chipwood_osb_raw")
    _export_sheet("chipwood_sheet_osb_aged", "chipwood_osb_aged")
    _export_sheet("chipwood_sheet_particle_fine", "chipwood_particle_fine")
    _export_crate("chipwood_crate", "chipwood_osb_aged")


if __name__ == "__main__":
    main()
