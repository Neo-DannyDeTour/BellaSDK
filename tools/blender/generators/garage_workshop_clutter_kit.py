"""Headless Blender generator for Old Garage Workshop Clutter & Extras (PBR + 2.5mm Bevels).

Exports:
  - assets/models/garage_tables/: workbench_steel_1_8m.glb, garage_table_rusty_1_2m.glb
  - assets/models/garage_gears/: gear_large.glb, gear_medium.glb, gear_small.glb, gear_cluster_a.glb
  - assets/models/little_boxes/: parts_bin_metal.glb, small_steel_box.glb, small_wood_box.glb
  - assets/models/toolbox/: toolbox_portable.glb, tool_cabinet_rolling.glb
  - assets/models/garage_tools/: wrench_adjustable.glb, spanner_open.glb, screwdriver.glb, broom_old.glb
  - assets/models/garage_debris/: collapsed_rack_pile.glb, steel_bollard.glb,
                                  red_door_indicator.glb, green_industrial_socket.glb

Run:
  /snap/bin/blender --background --python tools/blender/generators/garage_workshop_clutter_kit.py
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
from common.materials import create_pbr_material  # noqa: E402

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MODELS_ROOT: str = os.path.join(REPO_ROOT, "assets", "models")


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for col in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for blk in list(col):
            if blk.users == 0:
                col.remove(blk)


def add_box(
    bm: bmesh.types.BMesh,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    mat_idx: int = 0,
    xform: Matrix | None = None,
) -> None:
    x0, y0, z0 = p0
    x1, y1, z1 = p1
    cx, cy, cz = (x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5
    sx, sy, sz = max(abs(x1 - x0), 1e-4), max(abs(y1 - y0), 1e-4), max(abs(z1 - z0), 1e-4)
    m = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    if xform is not None:
        m = xform @ m
    res = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def add_cyl(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r0: float,
    r1: float | None = None,
    segs: int = 16,
    mat_idx: int = 0,
) -> None:
    if r1 is None:
        r1 = r0
    v = p1 - p0
    ln = v.length
    if ln < 1e-5:
        return
    rot = v.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    xf = Matrix.Translation((p0 + p1) * 0.5) @ rot
    res = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r0, radius2=r1, depth=ln, matrix=xf
    )
    vset = set(res["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mat_idx


def export_mesh(
    subdir: str,
    filename: str,
    bm: bmesh.types.BMesh,
    mats: list[bpy.types.Material],
    smooth: bool = False,
    bevel_offset: float = 0.0025,
    tiles_per_m: float = 1.2,
) -> None:
    out_dir = os.path.join(MODELS_ROOT, subdir)
    os.makedirs(out_dir, exist_ok=True)
    name = filename.replace(".glb", "")

    if bevel_offset > 0.0:
        bevel_sharp_edges(bm, offset=bevel_offset, angle_deg=35.0)

    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = smooth
    if not smooth:
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

    apply_metric_box_uv(obj, tiles_per_m=tiles_per_m)

    out_path = os.path.join(out_dir, filename)
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
    print(f"[garage_workshop_clutter_kit] Exported: {out_path}")


# ------------------------------------------------------------------------------
# TABLES
# ------------------------------------------------------------------------------
def build_tables() -> None:
    # 1. Heavy steel workbench 1.8m x 0.78m x 0.88m
    clear_scene()
    m_steel = load_project_pbr("pillar_rusted_truss_steel", "M_Workbench_Steel", metallic_fallback=0.75)
    m_top = load_project_pbr("weathered_deck_planks", "M_Workbench_WoodTop", metallic_fallback=0.0)
    bm = bmesh.new()
    w, d, h = 1.80, 0.78, 0.88
    hw, hd = w * 0.5, d * 0.5
    add_box(bm, (-hw, -hd, h - 0.045), (hw, hd, h), 1)
    add_box(bm, (-hw, hd - 0.02, h), (hw, hd, h + 0.14), 0)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            lx = sx * (hw - 0.04)
            ly = sy * (hd - 0.04)
            add_box(bm, (lx - 0.028, ly - 0.028, 0.0), (lx + 0.028, ly + 0.028, h - 0.045), 0)
    add_box(bm, (-hw + 0.03, -hd + 0.03, 0.22), (hw - 0.03, hd - 0.03, 0.25), 0)
    add_box(bm, (0.20, -hd + 0.04, h - 0.22), (hw - 0.06, hd - 0.06, h - 0.045), 0)
    export_mesh("garage_tables", "workbench_steel_1_8m.glb", bm, [m_steel, m_top], tiles_per_m=0.85)

    # 2. Rusty garage side table 1.2m x 0.65m x 0.78m
    clear_scene()
    m_rust = load_project_pbr("rusted_steel", "M_Table_RustySteel", metallic_fallback=0.75)
    bm = bmesh.new()
    w, d, h = 1.20, 0.65, 0.78
    hw, hd = w * 0.5, d * 0.5
    add_box(bm, (-hw, -hd, h - 0.035), (hw, hd, h), 0)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            lx = sx * (hw - 0.035)
            ly = sy * (hd - 0.035)
            add_box(bm, (lx - 0.022, ly - 0.022, 0.0), (lx + 0.022, ly + 0.022, h - 0.035), 0)
    add_box(bm, (-hw + 0.03, -hd + 0.03, 0.18), (hw - 0.03, -hd + 0.06, 0.21), 0)
    add_box(bm, (-hw + 0.03, hd - 0.06, 0.18), (hw - 0.03, hd - 0.03, 0.21), 0)
    export_mesh("garage_tables", "garage_table_rusty_1_2m.glb", bm, [m_rust], tiles_per_m=1.1)


# ------------------------------------------------------------------------------
# GEARS
# ------------------------------------------------------------------------------
def add_gear(bm: bmesh.types.BMesh, center: Vector, outer_r: float, thick: float, teeth: int, mat_idx: int = 0) -> None:
    inner_r = outer_r * 0.78
    hub_r = outer_r * 0.36
    add_cyl(bm, center, center + Vector((0.0, 0.0, thick)), inner_r, inner_r, max(16, teeth), mat_idx)
    add_cyl(bm, center - Vector((0.0, 0.0, thick * 0.12)), center + Vector((0.0, 0.0, thick * 1.12)), hub_r, hub_r, 14, mat_idx)
    tooth_w = (math.tau * inner_r / teeth) * 0.44
    tooth_l = outer_r - inner_r + 0.008
    for i in range(teeth):
        ang = i * (math.tau / teeth)
        r_mid = inner_r + (outer_r - inner_r) * 0.5
        pos = center + Vector((math.cos(ang) * r_mid, math.sin(ang) * r_mid, thick * 0.5))
        xf = Matrix.Translation(pos) @ Matrix.Rotation(ang, 4, "Z")
        add_box(bm, (-tooth_l * 0.5, -tooth_w * 0.5, -thick * 0.48), (tooth_l * 0.5, tooth_w * 0.5, thick * 0.48), mat_idx, xf)


def build_gears() -> None:
    specs = [
        ("gear_large.glb", 0.16, 0.038, 22),
        ("gear_medium.glb", 0.105, 0.030, 16),
        ("gear_small.glb", 0.065, 0.024, 12),
    ]
    for fname, r, th, teeth in specs:
        clear_scene()
        m_iron = load_project_pbr("crane_iron", "M_Gear_GreasyIron", metallic_fallback=0.82)
        bm = bmesh.new()
        add_gear(bm, Vector((0.0, 0.0, 0.0)), r, th, teeth, 0)
        export_mesh("garage_gears", fname, bm, [m_iron], bevel_offset=0.0012, tiles_per_m=2.5)

    clear_scene()
    m_iron = load_project_pbr("crane_iron", "M_Gear_GreasyIron", metallic_fallback=0.82)
    bm = bmesh.new()
    add_gear(bm, Vector((0.0, 0.0, 0.0)), 0.16, 0.038, 22, 0)
    add_gear(bm, Vector((0.18, 0.12, 0.0)), 0.105, 0.030, 16, 0)
    add_gear(bm, Vector((-0.14, 0.15, 0.0)), 0.08, 0.026, 14, 0)
    add_gear(bm, Vector((0.04, -0.02, 0.038)), 0.065, 0.024, 12, 0)
    export_mesh("garage_gears", "gear_cluster_a.glb", bm, [m_iron], bevel_offset=0.0012, tiles_per_m=2.5)


# ------------------------------------------------------------------------------
# LITTLE BOXES & TOOLBOXES
# ------------------------------------------------------------------------------
def build_little_boxes_and_toolboxes() -> None:
    # 1. Open metal parts bin
    clear_scene()
    m_bin = load_project_pbr("olive_drab_ammo_metal", "M_PartsBin_Metal", metallic_fallback=0.45)
    bm = bmesh.new()
    w, d, h, t = 0.34, 0.24, 0.16, 0.008
    hw, hd = w * 0.5, d * 0.5
    add_box(bm, (-hw, -hd, 0.0), (hw, hd, t), 0)
    add_box(bm, (-hw, hd - t, 0.0), (hw, hd, h), 0)
    add_box(bm, (-hw, -hd, 0.0), (-hw + t, hd, h), 0)
    add_box(bm, (hw - t, -hd, 0.0), (hw, hd, h), 0)
    add_box(bm, (-hw, -hd, 0.0), (hw, -hd + t, h * 0.55), 0)
    export_mesh("little_boxes", "parts_bin_metal.glb", bm, [m_bin], bevel_offset=0.0012, tiles_per_m=2.2)

    # 2. Small latched steel box
    clear_scene()
    m_box = load_project_pbr("fence_door_metal", "M_SmallSteelBox", metallic_fallback=0.5)
    bm = bmesh.new()
    add_box(bm, (-0.16, -0.11, 0.0), (0.16, 0.11, 0.12), 0)
    add_box(bm, (-0.165, -0.115, 0.115), (0.165, 0.115, 0.145), 0)
    add_box(bm, (-0.02, -0.125, 0.09), (0.02, -0.11, 0.13), 0)
    export_mesh("little_boxes", "small_steel_box.glb", bm, [m_box], bevel_offset=0.0018, tiles_per_m=2.2)

    # 3. Small wooden storage box
    clear_scene()
    m_wood = load_project_pbr("weathered_olive_crate_wood", "M_SmallWoodBox", metallic_fallback=0.0)
    bm = bmesh.new()
    add_box(bm, (-0.18, -0.14, 0.0), (0.18, 0.14, 0.18), 0)
    add_box(bm, (-0.19, -0.15, 0.0), (0.19, 0.15, 0.025), 0)
    add_box(bm, (-0.19, -0.15, 0.155), (0.19, 0.15, 0.18), 0)
    export_mesh("little_boxes", "small_wood_box.glb", bm, [m_wood], bevel_offset=0.002, tiles_per_m=1.8)

    # 4. Portable cantilever red metal toolbox
    clear_scene()
    m_red = load_project_pbr("chipped_red_enamel_metal", "M_Toolbox_RedEnamel", metallic_fallback=0.35)
    m_dark = load_project_pbr("crane_iron", "M_Toolbox_Handle", metallic_fallback=0.82)
    bm = bmesh.new()
    add_box(bm, (-0.24, -0.11, 0.0), (0.24, 0.11, 0.15), 0)
    add_box(bm, (-0.245, -0.112, 0.15), (0.245, 0.112, 0.21), 0)
    add_box(bm, (-0.23, -0.075, 0.21), (0.23, 0.075, 0.24), 0)
    add_cyl(bm, Vector((-0.09, 0.0, 0.275)), Vector((0.09, 0.0, 0.275)), 0.011, 0.011, 10, 1)
    add_box(bm, (-0.10, -0.01, 0.24), (-0.08, 0.01, 0.28), 1)
    add_box(bm, (0.08, -0.01, 0.24), (0.10, 0.01, 0.28), 1)
    add_box(bm, (-0.14, -0.122, 0.12), (-0.10, -0.11, 0.17), 1)
    add_box(bm, (0.10, -0.122, 0.12), (0.14, -0.11, 0.17), 1)
    export_mesh("toolbox", "toolbox_portable.glb", bm, [m_red, m_dark], bevel_offset=0.002, tiles_per_m=2.0)

    # 5. Red rolling mechanic's tool cabinet
    clear_scene()
    m_red = load_project_pbr("chipped_red_enamel_metal", "M_Cabinet_RedRust", metallic_fallback=0.35)
    m_trim = load_project_pbr("fence_door_metal", "M_Cabinet_SteelTrim", metallic_fallback=0.65)
    m_wheel = load_project_pbr("ribbed_black_cable_rubber", "M_Cabinet_Caster", metallic_fallback=0.0)
    bm = bmesh.new()
    w, d, h = 0.92, 0.48, 0.96
    hw, hd = w * 0.5, d * 0.5
    wheel_h = 0.10
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            wx, wy = sx * (hw - 0.07), sy * (hd - 0.07)
            add_cyl(bm, Vector((wx - 0.018, wy, 0.045)), Vector((wx + 0.018, wy, 0.045)), 0.045, 0.045, 12, 2)
            add_box(bm, (wx - 0.025, wy - 0.025, 0.06), (wx + 0.025, wy + 0.025, wheel_h), 1)
    add_box(bm, (-hw, -hd, wheel_h), (hw, hd, h), 0)
    add_box(bm, (-hw, -hd, h), (hw, hd, h + 0.025), 1)
    drawer_heights = [0.11, 0.11, 0.13, 0.16, 0.22]
    z_cur = h - 0.04
    for dh in drawer_heights:
        z_bot = z_cur - dh
        add_box(bm, (-hw + 0.035, -hd - 0.014, z_bot + 0.008), (hw - 0.035, -hd, z_cur - 0.008), 0)
        add_box(bm, (-hw + 0.08, -hd - 0.030, z_cur - 0.034), (hw - 0.08, -hd - 0.014, z_cur - 0.018), 1)
        z_cur = z_bot
    add_cyl(bm, Vector((hw + 0.06, -hd + 0.07, h - 0.08)), Vector((hw + 0.06, hd - 0.07, h - 0.08)), 0.014, 0.014, 10, 1)
    add_box(bm, (hw, -hd + 0.06, h - 0.095), (hw + 0.06, -hd + 0.08, h - 0.065), 1)
    add_box(bm, (hw, hd - 0.08, h - 0.095), (hw + 0.06, hd - 0.06, h - 0.065), 1)
    export_mesh("toolbox", "tool_cabinet_rolling.glb", bm, [m_red, m_trim, m_wheel], bevel_offset=0.0025, tiles_per_m=1.15)


# ------------------------------------------------------------------------------
# GARAGE HAND TOOLS
# ------------------------------------------------------------------------------
def build_tools() -> None:
    clear_scene()
    m_steel = load_project_pbr("crane_iron", "M_Tool_RustSteel", metallic_fallback=0.82)
    bm = bmesh.new()
    add_box(bm, (-0.14, -0.014, 0.0), (0.08, 0.014, 0.012), 0)
    add_box(bm, (0.08, -0.028, 0.0), (0.145, 0.026, 0.016), 0)
    add_box(bm, (0.115, 0.008, 0.0), (0.165, 0.032, 0.016), 0)
    add_box(bm, (0.115, -0.032, 0.0), (0.160, -0.012, 0.016), 0)
    export_mesh("garage_tools", "wrench_adjustable.glb", bm, [m_steel], bevel_offset=0.001, tiles_per_m=3.0)

    clear_scene()
    m_steel = load_project_pbr("crane_iron", "M_Tool_ChromeWorn", metallic_fallback=0.85)
    bm = bmesh.new()
    add_box(bm, (-0.11, -0.009, 0.0), (0.11, 0.009, 0.007), 0)
    for sx in (-1.0, 1.0):
        add_box(bm, (sx * 0.11, -0.022, 0.0), (sx * 0.145, 0.022, 0.008), 0)
    export_mesh("garage_tools", "spanner_open.glb", bm, [m_steel], bevel_offset=0.0008, tiles_per_m=3.0)

    clear_scene()
    m_handle = load_project_pbr("weathered_olive_crate_wood", "M_Tool_WoodHandle", metallic_fallback=0.0)
    m_shaft = load_project_pbr("crane_iron", "M_Tool_SteelShaft", metallic_fallback=0.88)
    bm = bmesh.new()
    add_cyl(bm, Vector((-0.10, 0.0, 0.014)), Vector((0.0, 0.0, 0.014)), 0.014, 0.012, 10, 0)
    add_cyl(bm, Vector((0.0, 0.0, 0.014)), Vector((0.14, 0.0, 0.014)), 0.0035, 0.0035, 8, 1)
    export_mesh("garage_tools", "screwdriver.glb", bm, [m_handle, m_shaft], bevel_offset=0.0, tiles_per_m=3.0)

    clear_scene()
    m_wood = load_project_pbr("weathered_deck_planks", "M_Broom_Wood", metallic_fallback=0.0)
    m_bristle = load_project_pbr("stained_mattress_ticking", "M_Broom_Bristle", metallic_fallback=0.0)
    bm = bmesh.new()
    add_cyl(bm, Vector((0.0, 0.0, 0.14)), Vector((0.0, 0.0, 1.42)), 0.014, 0.014, 10, 0)
    add_box(bm, (-0.17, -0.028, 0.10), (0.17, 0.028, 0.15), 0)
    add_box(bm, (-0.19, -0.032, 0.0), (0.19, 0.032, 0.10), 1)
    export_mesh("garage_tools", "broom_old.glb", bm, [m_wood, m_bristle], bevel_offset=0.002, tiles_per_m=1.6)


# ------------------------------------------------------------------------------
# IMAGE-MISSING EXTRAS
# ------------------------------------------------------------------------------
def build_extras() -> None:
    clear_scene()
    m_box = load_project_pbr("fence_door_metal", "M_ControlBox_Steel", metallic_fallback=0.65)
    m_glow = create_pbr_material(
        "M_ControlBox_RedLens",
        base_color=(0.95, 0.08, 0.05, 1.0),
        metallic=0.1,
        roughness=0.2,
        emission_color=(1.0, 0.06, 0.03, 1.0),
        emission_strength=6.0,
    )
    bm = bmesh.new()
    add_box(bm, (-0.075, -0.07, -0.11), (0.075, 0.0, 0.11), 0)
    add_cyl(bm, Vector((0.0, -0.095, 0.02)), Vector((0.0, -0.07, 0.02)), 0.028, 0.032, 14, 1)
    add_cyl(bm, Vector((0.0, -0.035, 0.11)), Vector((0.0, -0.035, 0.35)), 0.014, 0.014, 10, 0)
    add_cyl(bm, Vector((0.0, -0.035, -0.35)), Vector((0.0, -0.035, -0.11)), 0.014, 0.014, 10, 0)
    export_mesh("garage_debris", "red_door_indicator.glb", bm, [m_box, m_glow], bevel_offset=0.002, tiles_per_m=2.0)

    clear_scene()
    m_body = load_project_pbr("fence_door_metal", "M_Socket_Industrial", metallic_fallback=0.65)
    m_green = create_pbr_material(
        "M_Socket_GreenGlow",
        base_color=(0.25, 0.85, 0.38, 1.0),
        metallic=0.1,
        roughness=0.25,
        emission_color=(0.25, 0.95, 0.40, 1.0),
        emission_strength=3.5,
    )
    bm = bmesh.new()
    add_box(bm, (-0.16, -0.09, -0.18), (0.16, 0.0, 0.18), 0)
    add_cyl(bm, Vector((0.0, -0.13, 0.0)), Vector((0.0, -0.09, 0.0)), 0.095, 0.105, 18, 1)
    add_box(bm, (-0.06, -0.145, 0.08), (0.06, -0.09, 0.14), 0)
    export_mesh("garage_debris", "green_industrial_socket.glb", bm, [m_body, m_green], bevel_offset=0.002, tiles_per_m=2.0)

    clear_scene()
    m_rust = load_project_pbr("pillar_rusted_truss_steel", "M_Debris_RackSteel", metallic_fallback=0.75)
    bm = bmesh.new()
    panels = [
        (Vector((0.0, 0.0, 0.42)), (22.0, 8.0, 14.0)),
        (Vector((0.12, -0.15, 0.26)), (-16.0, -12.0, -20.0)),
        (Vector((-0.14, 0.10, 0.12)), (6.0, 18.0, 32.0)),
    ]
    for pos, (rx, ry, rz) in panels:
        xf = (
            Matrix.Translation(pos)
            @ Matrix.Rotation(math.radians(rz), 4, "Z")
            @ Matrix.Rotation(math.radians(ry), 4, "Y")
            @ Matrix.Rotation(math.radians(rx), 4, "X")
        )
        add_box(bm, (-0.65, -0.30, -0.025), (0.65, -0.26, 0.025), 0, xf)
        add_box(bm, (-0.65, 0.26, -0.025), (0.65, 0.30, 0.025), 0, xf)
        add_box(bm, (-0.65, -0.30, -0.025), (-0.61, 0.30, 0.025), 0, xf)
        add_box(bm, (0.61, -0.30, -0.025), (0.65, 0.30, 0.025), 0, xf)
        add_box(bm, (-0.63, -0.28, -0.012), (0.63, 0.28, 0.008), 0, xf)
    min_z = min(v.co.z for v in bm.verts)
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0.0, 0.0, -min_z))
    export_mesh("garage_debris", "collapsed_rack_pile.glb", bm, [m_rust], bevel_offset=0.002, tiles_per_m=1.2)

    clear_scene()
    m_bollard = load_project_pbr("weathered_concrete", "M_Bollard_Concrete", metallic_fallback=0.0)
    bm = bmesh.new()
    add_cyl(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, 0.03)), 0.14, 0.14, 16, 0)
    add_cyl(bm, Vector((0.0, 0.0, 0.03)), Vector((0.0, 0.0, 0.92)), 0.09, 0.088, 16, 0)
    add_cyl(bm, Vector((0.0, 0.0, 0.92)), Vector((0.0, 0.0, 0.96)), 0.088, 0.055, 16, 0)
    export_mesh("garage_debris", "steel_bollard.glb", bm, [m_bollard], smooth=True, bevel_offset=0.0, tiles_per_m=1.2)


def main() -> None:
    build_tables()
    build_gears()
    build_little_boxes_and_toolboxes()
    build_tools()
    build_extras()


if __name__ == "__main__":
    main()
