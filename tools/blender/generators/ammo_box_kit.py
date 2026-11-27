"""Headless Blender generator for Military Steel Ammo Boxes (.30 cal & .50 cal) with PBR & 2mm Bevels.

Exports to assets/models/ammo_box/:
  - ammo_box_30cal.glb (0.28m x 0.10m x 0.18m)
  - ammo_box_50cal.glb (0.30m x 0.15m x 0.21m)
"""

from __future__ import annotations

import math
import os
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector

_BLENDER_DIR: str = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if _BLENDER_DIR not in sys.path:
    sys.path.insert(0, _BLENDER_DIR)

from common.garage_pbr import apply_metric_box_uv, bevel_sharp_edges, load_project_pbr  # noqa: E402

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT_DIR: str = os.path.join(REPO_ROOT, "assets", "models", "ammo_box")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for blk in list(col):
            if blk.users == 0:
                col.remove(blk)


def add_box(bm: bmesh.types.BMesh, p0: tuple[float, float, float], p1: tuple[float, float, float], mat_idx: int = 0) -> None:
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    cx, cy, cz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    sx, sy, sz = abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_cyl(bm: bmesh.types.BMesh, p0: Vector, p1: Vector, r: float, segs: int = 10, mat_idx: int = 1) -> None:
    v = p1 - p0
    ln = v.length
    if ln < 1e-5:
        return
    rot = v.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    xf = Matrix.Translation((p0 + p1) * 0.5) @ rot
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r, radius2=r, depth=ln, matrix=xf)
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def build_ammo_box(length: float, width: float, height: float, filename: str) -> None:
    clear_scene()
    m_olive = load_project_pbr("olive_drab_ammo_metal", "M_AmmoBox_OliveSteel", metallic_fallback=0.45)
    m_latch = load_project_pbr("crane_iron", "M_AmmoBox_DarkSteel", metallic_fallback=0.82)
    bm = bmesh.new()

    hl = length * 0.5
    hw = width * 0.5
    lid_h = 0.026

    add_box(bm, (-hl, -hw, 0.0), (hl, hw, height - lid_h), 0)
    add_box(bm, (-hl + 0.006, -hw + 0.006, 0.0), (hl - 0.006, hw - 0.006, 0.012), 1)
    add_box(bm, (-hl - 0.005, -hw - 0.005, height - lid_h), (hl + 0.005, hw + 0.005, height), 0)
    add_box(bm, (-hl + 0.03, -hw + 0.018, height), (hl - 0.03, hw - 0.018, height + 0.005), 0)

    add_box(bm, (hl, -0.024, height - 0.085), (hl + 0.014, 0.024, height - 0.012), 1)
    add_box(bm, (hl + 0.010, -0.018, height - 0.095), (hl + 0.020, 0.018, height - 0.045), 1)
    add_box(bm, (-hl - 0.010, -0.028, height - 0.036), (-hl, 0.028, height - 0.008), 1)

    handle_z = height + 0.008
    add_cyl(bm, Vector((-0.055, -0.026, handle_z)), Vector((0.055, -0.026, handle_z)), 0.004, 8, 1)
    add_cyl(bm, Vector((-0.055, 0.026, handle_z)), Vector((0.055, 0.026, handle_z)), 0.004, 8, 1)
    add_cyl(bm, Vector((0.055, -0.026, handle_z)), Vector((0.055, 0.026, handle_z)), 0.004, 8, 1)
    add_cyl(bm, Vector((-0.055, -0.026, handle_z)), Vector((-0.055, 0.026, handle_z)), 0.004, 8, 1)

    for rx in (-hl * 0.55, 0.0, hl * 0.55):
        add_box(bm, (rx - 0.008, -hw - 0.003, 0.025), (rx + 0.008, -hw, height - lid_h - 0.015), 0)
        add_box(bm, (rx - 0.008, hw, 0.025), (rx + 0.008, hw + 0.003, height - lid_h - 0.015), 0)

    bevel_sharp_edges(bm, offset=0.0018, angle_deg=38.0)

    os.makedirs(OUT_DIR, exist_ok=True)
    mesh = bpy.data.meshes.new(filename)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = False
    thresh = math.radians(38.0)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) <= thresh:
            e.smooth = True
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(filename, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(m_olive)
    obj.data.materials.append(m_latch)

    apply_metric_box_uv(obj, tiles_per_m=2.2)

    out_path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=True,
    )
    print(f"[ammo_box_kit] Exported: {out_path}")


def main() -> None:
    build_ammo_box(0.28, 0.10, 0.18, "ammo_box_30cal.glb")
    build_ammo_box(0.30, 0.15, 0.21, "ammo_box_50cal.glb")


if __name__ == "__main__":
    main()
