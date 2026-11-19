"""Procedural Blender generator for modular factory floor and stair shell GLBs.

Generates two clean-room post-apocalyptic industrial shell assets in
assets/models/factory_shells/:
1. factory_floor_4m.glb  - 4.0m x 4.0m x 0.25m poured concrete floor slab
2. factory_stairs_4m.glb - 4.0m rise / 4.0m run steel stringer staircase
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material
from mathutils import Matrix, Vector


# ==============================================================================
# SHARED HELPERS
# ==============================================================================
def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 2.0) -> None:
    """Generate world-metric cubic box UVs so PBR textures tile cleanly."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data

    inv_tile = 1.0 / tile_meters
    for poly in mesh.polygons:
        nx = abs(poly.normal.x)
        ny = abs(poly.normal.y)
        nz = abs(poly.normal.z)
        for loop_idx in poly.loop_indices:
            vert = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            if nx >= ny and nx >= nz:
                u, v = vert.y * inv_tile, vert.z * inv_tile
            elif ny >= nx and ny >= nz:
                u, v = vert.x * inv_tile, vert.z * inv_tile
            else:
                u, v = vert.x * inv_tile, vert.y * inv_tile
            uv_layer[loop_idx].uv = (u, v)


def _finalize_bmesh_to_object(
    name: str,
    bm: bmesh.types.BMesh,
    material: bpy.types.Material,
    auto_smooth_deg: float = 35.0,
) -> bpy.types.Object:
    """Convert a BMesh into a scene Object with angle-based smooth normals."""
    mesh = bpy.data.meshes.new(name)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    thresh_rad = math.radians(auto_smooth_deg)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) <= thresh_rad
        else:
            edge.smooth = False

    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    assign_material(obj, material)
    return obj


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
) -> list[bmesh.types.BMFace]:
    """Append an axis-aligned box to a BMesh."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    coords = [
        (x0, y0, z0),
        (x1, y0, z0),
        (x1, y1, z0),
        (x0, y1, z0),
        (x0, y0, z1),
        (x1, y0, z1),
        (x1, y1, z1),
        (x0, y1, z1),
    ]
    verts = [bm.verts.new(c) for c in coords]
    quads = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (2, 3, 7, 6),
        (0, 4, 7, 3),
        (1, 2, 6, 5),
    ]
    return [bm.faces.new([verts[i] for i in q]) for q in quads]


def _add_pipe_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    radius: float,
    segments: int = 10,
    cap_ends: bool = True,
) -> None:
    """Append a cylindrical pipe segment between p0 and p1."""
    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return
    mid = (p0 + p1) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    xf = Matrix.Translation(mid) @ rot
    bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=length,
        matrix=xf,
    )


def _add_extruded_yz_profile_bm(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    profile_yz: list[tuple[float, float]],
) -> None:
    """Extrude a 2D (y, z) polygon along X from x0 to x1."""
    n = len(profile_yz)
    v_left = [bm.verts.new((x0, y, z)) for (y, z) in profile_yz]
    v_right = [bm.verts.new((x1, y, z)) for (y, z) in profile_yz]

    bm.faces.new(list(reversed(v_left)))
    bm.faces.new(v_right)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((v_left[i], v_left[j], v_right[j], v_right[i]))


def _report_mesh_stats(label: str, obj: bpy.types.Object) -> None:
    """Print triangle count and Blender/Godot bounding box for verification."""
    mesh = obj.data
    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    # Blender (X, Y, Z) -> Godot Y-up (X, Z, -Y)
    g_min = (min(xs), min(zs), -max(ys))
    g_max = (max(xs), max(zs), -min(ys))
    print(
        f"[{label}] tris={tri_count} | "
        f"Godot BBox min=({g_min[0]:.3f}, {g_min[1]:.3f}, {g_min[2]:.3f}) "
        f"max=({g_max[0]:.3f}, {g_max[1]:.3f}, {g_max[2]:.3f})"
    )


# ==============================================================================
# 1. FACTORY FLOOR 4M
# ==============================================================================
def generate_factory_floor_4m(output_dir: Path) -> Path:
    """Build and export factory_floor_4m.glb (4.0m x 4.0m x 0.25m concrete slab)."""
    clean_scene()

    concrete_mat = create_pbr_material(
        name="concrete",
        base_color=(0.34, 0.34, 0.32, 1.0),
        metallic=0.0,
        roughness=0.88,
    )

    bm = bmesh.new()

    # Base monolithic slab (0.00 -> 0.22m) with subtle bottom perimeter bevel
    slab_half = 2.0
    slab_h = 0.25
    joint_half = 0.006   # 12mm expansion joint gap between 2m x 2m bays
    bevel_w = 0.010      # 10mm chamfer on outer edges and expansion joints
    base_top_z = 0.220

    _add_box_bm(
        bm,
        (-slab_half, -slab_half, 0.0),
        (slab_half, slab_half, base_top_z),
    )

    # 4 poured concrete bays (2m x 2m quadrants) on top (0.22 -> 0.25m)
    # creating subtle expansion-joint grooves at X=0 and Y=0 plus outer bevels.
    quadrants = [
        (-slab_half, -joint_half, -slab_half, -joint_half),
        (joint_half, slab_half, -slab_half, -joint_half),
        (-slab_half, -joint_half, joint_half, slab_half),
        (joint_half, slab_half, joint_half, slab_half),
    ]
    for x0, x1, y0, y1 in quadrants:
        # Lower vertical rim of bay (z: 0.220 -> 0.240)
        _add_box_bm(bm, (x0, y0, base_top_z), (x1, y1, slab_h - bevel_w))
        # Chamfered top cap (z: 0.240 -> 0.250)
        b_x0 = x0 + bevel_w
        b_x1 = x1 - bevel_w
        b_y0 = y0 + bevel_w
        b_y1 = y1 - bevel_w
        v_bot = [
            bm.verts.new((x0, y0, slab_h - bevel_w)),
            bm.verts.new((x1, y0, slab_h - bevel_w)),
            bm.verts.new((x1, y1, slab_h - bevel_w)),
            bm.verts.new((x0, y1, slab_h - bevel_w)),
        ]
        v_top = [
            bm.verts.new((b_x0, b_y0, slab_h)),
            bm.verts.new((b_x1, b_y0, slab_h)),
            bm.verts.new((b_x1, b_y1, slab_h)),
            bm.verts.new((b_x0, b_y1, slab_h)),
        ]
        bm.faces.new(v_top)
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((v_bot[i], v_bot[j], v_top[j], v_top[i]))

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)

    floor_obj = _finalize_bmesh_to_object("factory_floor_4m", bm, concrete_mat)
    _apply_box_uvs(floor_obj, tile_meters=2.0)
    _report_mesh_stats("factory_floor_4m", floor_obj)

    output_path = output_dir / "factory_floor_4m.glb"
    return export_godot_glb(
        filepath=output_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )


# ==============================================================================
# 2. FACTORY STAIRS 4M
# ==============================================================================
def _add_stringer_c_channel(
    bm: bmesh.types.BMesh,
    x_outer: float,
    inward_dir: float,
) -> None:
    """Build a 45-deg C-channel steel stringer with plumb-cut ends at Z=0 and Y=2."""
    web_thick = 0.020
    flange_w = 0.080
    flange_thick = 0.018

    # Nosing line: z = y + 2.0 for y in [-2.0, +2.0]
    # Plumb-cut web profile in (y, z), clamped to z >= 0.0 and y <= 2.0
    web_profile = [
        (-2.00, 0.00),
        (-1.66, 0.00),
        (2.00, 3.66),
        (2.00, 4.00),
        (1.94, 4.00),
        (-2.00, 0.06),
    ]
    x_web_in = x_outer + inward_dir * web_thick
    _add_extruded_yz_profile_bm(
        bm,
        min(x_outer, x_web_in),
        max(x_outer, x_web_in),
        web_profile,
    )

    # Top flange (facing inward from web)
    top_flange_profile = [
        (-2.00, 0.06 - flange_thick),
        (1.94 + flange_thick, 4.00 - flange_thick),
        (1.94, 4.00),
        (-2.00, 0.06),
    ]
    x_flg_in = x_outer + inward_dir * flange_w
    _add_extruded_yz_profile_bm(
        bm,
        min(x_web_in, x_flg_in),
        max(x_web_in, x_flg_in),
        top_flange_profile,
    )

    # Bottom flange (facing inward from web)
    bot_flange_profile = [
        (-1.66, 0.00),
        (-1.66 + flange_thick, 0.00),
        (2.00, 3.66 + flange_thick),
        (2.00, 3.66),
    ]
    _add_extruded_yz_profile_bm(
        bm,
        min(x_web_in, x_flg_in),
        max(x_web_in, x_flg_in),
        bot_flange_profile,
    )


def _add_grated_treads(bm: bmesh.types.BMesh, tread_half_w: float) -> None:
    """Build 16 steel grated/ribbed treads rising 4.0m over 4.0m run."""
    n_steps = 16
    step_run = 4.0 / n_steps
    step_rise = 4.0 / n_steps

    for i in range(n_steps):
        y_front = -2.0 + i * step_run
        y_back = min(2.0, y_front + step_run + 0.015)
        z_top = (i + 1) * step_rise
        z_bot = z_top - 0.036

        # Front nosing channel bar (anti-slip lip)
        _add_box_bm(
            bm,
            (-tread_half_w, y_front, z_bot),
            (tread_half_w, y_front + 0.032, z_top),
        )
        # Rear channel bar
        _add_box_bm(
            bm,
            (-tread_half_w, y_back - 0.024, z_bot),
            (tread_half_w, y_back, z_top),
        )
        # Left & right tread end-plates
        _add_box_bm(
            bm,
            (-tread_half_w, y_front + 0.032, z_bot),
            (-tread_half_w + 0.016, y_back - 0.024, z_top),
        )
        _add_box_bm(
            bm,
            (tread_half_w - 0.016, y_front + 0.032, z_bot),
            (tread_half_w, y_back - 0.024, z_top),
        )

        # 3 interior grated/ribbed longitudinal tread bars
        inner_y0 = y_front + 0.032
        inner_y1 = y_back - 0.024
        span_y = inner_y1 - inner_y0
        for b_idx in range(1, 4):
            yc = inner_y0 + span_y * (b_idx / 4.0)
            _add_box_bm(
                bm,
                (-tread_half_w + 0.016, yc - 0.010, z_top - 0.024),
                (tread_half_w - 0.016, yc + 0.010, z_top),
            )

        # 3 transverse underside tie-bars locking the grate together
        for tx in (-0.45, 0.0, 0.45):
            _add_box_bm(
                bm,
                (tx - 0.010, inner_y0, z_bot),
                (tx + 0.010, inner_y1, z_top - 0.016),
            )


def _add_mounting_plates(bm: bmesh.types.BMesh, stringer_x: float) -> None:
    """Add bottom floor anchor plate and top header mounting plate with bolts."""
    for side in (-1.0, 1.0):
        xc = side * stringer_x
        # Bottom base plate resting at Z=0.0
        px0 = max(-1.0, xc - 0.08)
        px1 = min(1.0, xc + 0.08)
        _add_box_bm(bm, (px0, -2.00, 0.00), (px1, -1.64, 0.020))
        for bx in (px0 + 0.025, px1 - 0.025):
            for by in (-1.95, -1.69):
                _add_box_bm(bm, (bx - 0.011, by - 0.011, 0.020), (bx + 0.011, by + 0.011, 0.034))

        # Top vertical header plate at Y=2.00 and top horizontal flange at Z=4.00
        _add_box_bm(bm, (px0, 1.98, 3.66), (px1, 2.00, 4.00))
        _add_box_bm(bm, (px0, 1.84, 3.98), (px1, 2.00, 4.00))
        for bx in (px0 + 0.025, px1 - 0.025):
            _add_box_bm(bm, (bx - 0.011, 1.87, 4.00), (bx + 0.011, 1.90, 4.012))


def _add_tubular_railings(bm: bmesh.types.BMesh, rail_x: float) -> None:
    """Add tubular steel side railings with stanchion posts and mid-rails."""
    post_y_positions = (-1.90, -0.95, 0.00, 0.95, 1.90)
    rail_height = 1.00
    mid_offset = 0.50

    for side in (-1.0, 1.0):
        rx = side * rail_x
        # Vertical stanchions + weld gussets
        for py in post_y_positions:
            z_base = py + 2.0 + 0.02
            z_top = z_base + rail_height
            _add_pipe_bm(
                bm,
                Vector((rx, py, z_base)),
                Vector((rx, py, z_top)),
                radius=0.018,
                segments=10,
                cap_ends=True,
            )
            _add_box_bm(
                bm,
                (rx - 0.026, py - 0.026, z_base - 0.03),
                (rx + 0.026, py + 0.026, z_base + 0.04),
            )

        # Top handrail with short horizontal end returns
        p_bot_ret = Vector((rx, -2.00, -1.90 + 2.0 + 0.02 + rail_height))
        p_bot = Vector((rx, -1.90, -1.90 + 2.0 + 0.02 + rail_height))
        p_top = Vector((rx, 1.90, 1.90 + 2.0 + 0.02 + rail_height))
        p_top_ret = Vector((rx, 2.00, 1.90 + 2.0 + 0.02 + rail_height))

        _add_pipe_bm(bm, p_bot_ret, p_bot, radius=0.022, segments=10, cap_ends=True)
        _add_pipe_bm(bm, p_bot, p_top, radius=0.022, segments=10, cap_ends=True)
        _add_pipe_bm(bm, p_top, p_top_ret, radius=0.022, segments=10, cap_ends=True)

        # Mid-rail
        m_bot = Vector((rx, -1.90, -1.90 + 2.0 + 0.02 + mid_offset))
        m_top = Vector((rx, 1.90, 1.90 + 2.0 + 0.02 + mid_offset))
        _add_pipe_bm(bm, m_bot, m_top, radius=0.015, segments=8, cap_ends=True)


def generate_factory_stairs_4m(output_dir: Path) -> Path:
    """Build and export factory_stairs_4m.glb (4m rise / 4m run steel staircase)."""
    clean_scene()

    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.20, 0.22, 0.21, 1.0),
        metallic=0.85,
        roughness=0.62,
    )

    bm = bmesh.new()

    stringer_outer_x = 0.94
    tread_half_w = 0.92
    rail_x = 0.96

    _add_stringer_c_channel(bm, -stringer_outer_x, 1.0)
    _add_stringer_c_channel(bm, stringer_outer_x, -1.0)
    _add_grated_treads(bm, tread_half_w)
    _add_mounting_plates(bm, stringer_outer_x)
    _add_tubular_railings(bm, rail_x)

    # Mid-span underside stiffening angle-iron tie beam across stringers
    _add_box_bm(bm, (-tread_half_w, -0.05, 1.66), (tread_half_w, 0.05, 1.72))

    stairs_obj = _finalize_bmesh_to_object("factory_stairs_4m", bm, steel_mat)
    _apply_box_uvs(stairs_obj, tile_meters=1.0)
    _report_mesh_stats("factory_stairs_4m", stairs_obj)

    output_path = output_dir / "factory_stairs_4m.glb"
    return export_godot_glb(
        filepath=output_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )


# ==============================================================================
# ENTRY POINT
# ==============================================================================
def main() -> None:
    """Generate both modular factory floor and stair GLBs."""
    sdk_root = Path(__file__).resolve().parent.parent.parent.parent
    output_dir = sdk_root / "assets" / "models" / "factory_shells"
    output_dir.mkdir(parents=True, exist_ok=True)

    generate_factory_floor_4m(output_dir)
    generate_factory_stairs_4m(output_dir)


if __name__ == "__main__":
    main()
