"""Headless Blender generator for Tall Breakable Wooden Crate + 8 plank gibs with PBR & Bevels.

Exports to assets/models/breakable_tall_crate/:
  - tall_crate_intact.glb (0.65m x 0.65m x 1.35m tall slatted shipping crate)
  - tall_crate_gib_0.glb .. tall_crate_gib_7.glb (8 centered plank/slat debris gibs)
"""

from __future__ import annotations

import math
import os
import sys
import bpy
import bmesh
from mathutils import Matrix

_BLENDER_DIR: str = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if _BLENDER_DIR not in sys.path:
    sys.path.insert(0, _BLENDER_DIR)

from common.garage_pbr import apply_metric_box_uv, bevel_sharp_edges, load_project_pbr  # noqa: E402

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT_DIR: str = os.path.join(REPO_ROOT, "assets", "models", "breakable_tall_crate")

W: float = 0.65
D: float = 0.65
H: float = 1.35
BATTEN_T: float = 0.032


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


def finalize_and_export(name: str, bm: bmesh.types.BMesh, mats: list[bpy.types.Material], filename: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    bevel_sharp_edges(bm, offset=0.0025, angle_deg=35.0)
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = False
    thresh = math.radians(38.0)
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) <= thresh:
            e.smooth = True
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for m in mats:
        obj.data.materials.append(m)
    apply_metric_box_uv(obj, tiles_per_m=1.2)
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
    print(f"[tall_breakable_crate] Exported: {out_path}")


def build_intact() -> None:
    clear_scene()
    m_plank = load_project_pbr("weathered_olive_crate_wood", "M_TallCrate_Plank", metallic_fallback=0.0)
    m_frame = load_project_pbr("weathered_deck_planks", "M_TallCrate_Frame", metallic_fallback=0.0)
    bm = bmesh.new()
    hw, hd = W * 0.5, D * 0.5

    add_box(bm, (-hw + BATTEN_T, -hd + BATTEN_T, BATTEN_T), (hw - BATTEN_T, hd - BATTEN_T, H - BATTEN_T), 0)

    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            x0 = sx * hw - (0.07 if sx > 0 else 0.0)
            x1 = sx * hw + (0.0 if sx > 0 else 0.07)
            y0 = sy * hd - (0.07 if sy > 0 else 0.0)
            y1 = sy * hd + (0.0 if sy > 0 else 0.07)
            add_box(bm, (min(x0, x1), min(y0, y1), 0.0), (max(x0, x1), max(y0, y1), H), 1)

    for z_bot in (0.0, 0.42, 0.86, H - 0.08):
        z_top = z_bot + 0.08
        # Span cleanly between corner posts (no coplanar overlap)
        add_box(bm, (-hw + 0.07, -hd, z_bot), (hw - 0.07, -hd + BATTEN_T, z_top), 1)
        add_box(bm, (-hw + 0.07, hd - BATTEN_T, z_bot), (hw - 0.07, hd, z_top), 1)
        add_box(bm, (-hw, -hd + 0.07, z_bot), (-hw + BATTEN_T, hd - 0.07, z_top), 1)
        add_box(bm, (hw - BATTEN_T, -hd + 0.07, z_bot), (hw, hd - 0.07, z_top), 1)

    add_box(bm, (-hw, -hd, H - 0.03), (hw, hd, H), 0)
    finalize_and_export("TallCrateIntact", bm, [m_plank, m_frame], "tall_crate_intact.glb")


def build_gibs() -> None:
    gib_specs: list[tuple[float, float, float]] = [
        (0.58, 0.032, 0.62),
        (0.58, 0.032, 0.62),
        (0.58, 0.032, 0.64),
        (0.032, 0.58, 0.64),
        (0.032, 0.58, 0.64),
        (0.62, 0.62, 0.035),
        (0.07, 0.07, 1.28),
        (0.07, 0.07, 1.15),
    ]
    for idx, (sx, sy, sz) in enumerate(gib_specs):
        clear_scene()
        m_plank = load_project_pbr("weathered_olive_crate_wood", "M_TallCrate_Gib", metallic_fallback=0.0)
        bm = bmesh.new()
        add_box(bm, (-sx * 0.5, -sy * 0.5, -sz * 0.5), (sx * 0.5, sy * 0.5, sz * 0.5), 0)
        finalize_and_export(f"TallCrateGib{idx}", bm, [m_plank], f"tall_crate_gib_{idx}.glb")


def main() -> None:
    build_intact()
    build_gibs()


if __name__ == "__main__":
    main()
