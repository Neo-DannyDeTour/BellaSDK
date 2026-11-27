"""Headless Blender generator for Old Garage Fence, Wall & Floor Cable Clusters (PBR).

Exports to assets/models/garage_cables/:
  - cable_fence_draped_a.glb, cable_fence_draped_b.glb
  - cable_wall_bundle_2m.glb, cable_wall_bundle_4m.glb
  - cable_floor_coil_large.glb, cable_floor_coil_plug.glb
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

from common.garage_pbr import apply_metric_box_uv, load_project_pbr  # noqa: E402

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT_DIR: str = os.path.join(REPO_ROOT, "assets", "models", "garage_cables")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for blk in list(col):
            if blk.users == 0:
                col.remove(blk)


def add_tube_along_points(bm: bmesh.types.BMesh, pts: list[Vector], radius: float, segs: int = 8, mat_idx: int = 0) -> None:
    if len(pts) < 2:
        return
    rings: list[list[bmesh.types.BMVert]] = []
    for i, p in enumerate(pts):
        if i == 0:
            tangent = (pts[1] - pts[0]).normalized()
        elif i == len(pts) - 1:
            tangent = (pts[-1] - pts[-2]).normalized()
        else:
            tangent = (pts[i + 1] - pts[i - 1]).normalized()
        if tangent.length < 1e-6:
            tangent = Vector((0.0, 0.0, 1.0))
        up = Vector((0.0, 0.0, 1.0)) if abs(tangent.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        u = tangent.cross(up).normalized()
        v = tangent.cross(u).normalized()
        ring = []
        for s in range(segs):
            ang = s * (math.tau / segs)
            offset = (u * math.cos(ang) + v * math.sin(ang)) * radius
            ring.append(bm.verts.new(p + offset))
        rings.append(ring)

    for i in range(len(rings) - 1):
        r0 = rings[i]
        r1 = rings[i + 1]
        for s in range(segs):
            ns = (s + 1) % segs
            f = bm.faces.new((r0[s], r0[ns], r1[ns], r1[s]))
            f.material_index = mat_idx

    f_start = bm.faces.new(list(reversed(rings[0])))
    f_start.material_index = mat_idx
    f_end = bm.faces.new(rings[-1])
    f_end.material_index = mat_idx


def export_cable(name: str, bm: bmesh.types.BMesh, mats: list[bpy.types.Material], filename: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for m in mats:
        obj.data.materials.append(m)

    apply_metric_box_uv(obj, tiles_per_m=3.0)

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
    print(f"[garage_cables_kit] Exported: {out_path}")


def build_fence_draped(filename: str, strands: int) -> None:
    clear_scene()
    m_rubber = load_project_pbr("ribbed_black_cable_rubber", "M_Cable_BlackRubber", metallic_fallback=0.0)
    m_plug = load_project_pbr("tarnished_brass", "M_Cable_PlugMetal", metallic_fallback=0.85)
    bm = bmesh.new()

    for k in range(strands):
        x_off = (k - (strands - 1) * 0.5) * 0.055
        drop = 0.65 + (k % 3) * 0.14
        pts: list[Vector] = []
        steps = 28
        for i in range(steps + 1):
            t = i / steps
            if t < 0.35:
                u = t / 0.35
                y = -0.055 - 0.03 * math.sin(u * math.pi)
                z = -drop * (1.0 - u)
            elif t <= 0.65:
                u = (t - 0.35) / 0.30
                theta = math.pi * u
                y = -0.055 * math.cos(theta)
                z = 0.045 * math.sin(theta)
            else:
                u = (t - 0.65) / 0.35
                y = 0.055 + 0.03 * math.sin(u * math.pi)
                z = -drop * 0.92 * u
            sway_x = x_off + 0.025 * math.sin(t * math.tau + k)
            pts.append(Vector((sway_x, y, z)))
        add_tube_along_points(bm, pts, 0.011 + (k % 2) * 0.003, 8, 0)

    export_cable(filename.replace(".glb", ""), bm, [m_rubber, m_plug], filename)


def build_wall_bundle(span: float, strands: int, filename: str) -> None:
    clear_scene()
    m_rubber = load_project_pbr("ribbed_black_cable_rubber", "M_Cable_BlackRubber", metallic_fallback=0.0)
    bm = bmesh.new()
    hs = span * 0.5
    steps = 24
    for k in range(strands):
        sag = 0.22 + (k * 0.11) + (0.08 * (span / 2.0 - 1.0))
        z_start = (k - strands * 0.5) * 0.045
        y_off = -0.025 - (k % 3) * 0.016
        pts: list[Vector] = []
        for i in range(steps + 1):
            t = i / steps
            x = -hs + span * t
            z = z_start - sag * 4.0 * t * (1.0 - t)
            y = y_off - 0.02 * math.sin(t * math.pi)
            pts.append(Vector((x, y, z)))
        add_tube_along_points(bm, pts, 0.009 + (k % 2) * 0.004, 8, 0)
    export_cable(filename.replace(".glb", ""), bm, [m_rubber], filename)


def build_floor_coil(with_plug: bool, filename: str) -> None:
    clear_scene()
    m_rubber = load_project_pbr("ribbed_black_cable_rubber", "M_Cable_BlackRubber", metallic_fallback=0.0)
    m_metal = load_project_pbr("tarnished_brass", "M_Cable_PlugBrass", metallic_fallback=0.85)
    bm = bmesh.new()

    r_tube = 0.014
    turns = 5.5
    steps = 110
    pts: list[Vector] = []
    for i in range(steps + 1):
        t = i / steps
        ang = t * turns * math.tau
        rad = 0.24 + 0.18 * t + 0.015 * math.sin(ang * 2.0)
        layer_z = r_tube + (r_tube * 1.35) * ((i // 22) % 2) * 0.55
        pts.append(Vector((math.cos(ang) * rad, math.sin(ang) * rad, layer_z)))

    tail_start = pts[-1]
    for j in range(1, 10):
        u = j / 9.0
        pts.append(tail_start + Vector((u * 0.55, -0.18 * math.sin(u * math.pi), (r_tube - tail_start.z) * u)))

    add_tube_along_points(bm, pts, r_tube, 8, 0)

    if with_plug:
        end_p = pts[-1]
        m_plug = Matrix.Translation(end_p + Vector((0.06, 0.0, 0.01))) @ Matrix.Diagonal((0.12, 0.045, 0.045, 1.0))
        res = bmesh.ops.create_cube(bm, size=1.0, matrix=m_plug)
        for f in bm.faces:
            if all(v in set(res["verts"]) for v in f.verts):
                f.material_index = 1

    export_cable(filename.replace(".glb", ""), bm, [m_rubber, m_metal], filename)


def main() -> None:
    build_fence_draped("cable_fence_draped_a.glb", strands=3)
    build_fence_draped("cable_fence_draped_b.glb", strands=6)
    build_wall_bundle(2.0, 4, "cable_wall_bundle_2m.glb")
    build_wall_bundle(4.0, 6, "cable_wall_bundle_4m.glb")
    build_floor_coil(False, "cable_floor_coil_large.glb")
    build_floor_coil(True, "cable_floor_coil_plug.glb")


if __name__ == "__main__":
    main()
