"""Procedural Blender generator for workshop prop GLBs.

Generates two clean-room post-apocalyptic industrial workshop prop assets in
assets/models/props/factory_workshop/:
1. warehouse_shelf.glb - 2.4m x 2.2m x 0.9m 3-tier bolted steel pallet rack with timber decks
2. pallet_jack.glb     - ~1.55m x 0.55m x 1.2m manual industrial hydraulic transpallet

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Clean world-metric box UVs (1.0m tile).
- Explicit material slots for Godot ORM reassignment:
  - warehouse_shelf: 'steel', 'wood'
  - pallet_jack: 'painted_steel', 'steel', 'rubber'
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
from common.materials import create_pbr_material
from mathutils import Matrix, Vector


# ==============================================================================
# SHARED BMESH & UV HELPERS
# ==============================================================================
def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append an axis-aligned box (with optional edge chamfer) to a BMesh."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return []

    if chamfer <= 0.0:
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
        faces: list[bmesh.types.BMFace] = []
        for q in quads:
            f = bm.faces.new([verts[i] for i in q])
            f.material_index = mat_idx
            faces.append(f)
        return faces

    tmp = bmesh.new()
    cx = 0.5 * (x0 + x1)
    cy = 0.5 * (y0 + y1)
    cz = 0.5 * (z0 + z1)
    sx = x1 - x0
    sy = y1 - y0
    sz = z1 - z0
    xf = Matrix.Translation((cx, cy, cz)) @ Matrix.Diagonal((sx, sy, sz, 1.0))
    bmesh.ops.create_cube(tmp, size=1.0, matrix=xf)
    c_limit = min(chamfer, min(sx, sy, sz) * 0.25)
    if c_limit > 1e-5:
        bmesh.ops.bevel(
            tmp,
            geom=list(tmp.edges),
            offset=c_limit,
            segments=1,
            affect="EDGES",
        )
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _add_oriented_box_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    width_x: float,
    thickness: float,
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append a rectangular strut running from p0 to p1 with local X width and perpendicular thickness."""
    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return []
    z_axis = vec.normalized()
    ref_x = Vector((1.0, 0.0, 0.0))
    if abs(z_axis.dot(ref_x)) > 0.98:
        ref_x = Vector((0.0, 1.0, 0.0))
    y_axis = z_axis.cross(ref_x).normalized()
    x_axis = y_axis.cross(z_axis).normalized()

    rot = Matrix((x_axis, y_axis, z_axis)).transposed().to_4x4()
    mid = (p0 + p1) * 0.5
    xf = Matrix.Translation(mid) @ rot @ Matrix.Diagonal((width_x, thickness, length, 1.0))

    tmp = bmesh.new()
    bmesh.ops.create_cube(tmp, size=1.0, matrix=xf)
    c_limit = min(chamfer, min(width_x, thickness, length) * 0.25)
    if c_limit > 1e-5:
        bmesh.ops.bevel(
            tmp,
            geom=list(tmp.edges),
            offset=c_limit,
            segments=1,
            affect="EDGES",
        )
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _add_cylinder_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    r0: float,
    r1: float | None = None,
    segments: int = 12,
    cap_ends: bool = True,
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Append a cylinder or frustum between p0 and p1 with explicit material index."""
    if r1 is None:
        r1 = r0
    vec = p1 - p0
    length = vec.length
    if length < 1e-5:
        return []
    mid = (p0 + p1) * 0.5
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(vec.normalized()).to_matrix().to_4x4()
    xf = Matrix.Translation(mid) @ rot

    tmp = bmesh.new()
    bmesh.ops.create_cone(
        tmp,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=r0,
        radius2=r1,
        depth=length,
        matrix=xf,
    )
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _add_extruded_yz_profile_bm(
    bm: bmesh.types.BMesh,
    x0: float,
    x1: float,
    profile_yz: list[tuple[float, float]],
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Extrude a convex/simple 2D (y, z) polygon along X from x0 to x1."""
    n = len(profile_yz)
    v_left = [bm.verts.new((x0, y, z)) for (y, z) in profile_yz]
    v_right = [bm.verts.new((x1, y, z)) for (y, z) in profile_yz]

    faces: list[bmesh.types.BMFace] = []
    f_l = bm.faces.new(list(reversed(v_left)))
    f_l.material_index = mat_idx
    faces.append(f_l)

    f_r = bm.faces.new(v_right)
    f_r.material_index = mat_idx
    faces.append(f_r)

    for i in range(n):
        j = (i + 1) % n
        f_s = bm.faces.new((v_left[i], v_left[j], v_right[j], v_right[i]))
        f_s.material_index = mat_idx
        faces.append(f_s)
    return faces


def _merge_temp_bmesh(
    tmp: bmesh.types.BMesh,
    dst: bmesh.types.BMesh,
    mat_idx: int,
) -> list[bmesh.types.BMFace]:
    """Copy geometry from tmp BMesh into dst BMesh and assign mat_idx."""
    vert_map: dict[int, bmesh.types.BMVert] = {}
    tmp.verts.ensure_lookup_table()
    for idx, v in enumerate(tmp.verts):
        vert_map[idx] = dst.verts.new(v.co)

    created_faces: list[bmesh.types.BMFace] = []
    for f in tmp.faces:
        new_f = dst.faces.new([vert_map[v.index] for v in f.verts])
        new_f.material_index = mat_idx
        created_faces.append(new_f)

    tmp.free()
    return created_faces


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 1.0) -> None:
    """Generate world-metric cubic box UVs so PBR materials tile cleanly."""
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
    materials: list[bpy.types.Material],
    auto_smooth_deg: float = 35.0,
) -> bpy.types.Object:
    """Convert BMesh into scene Object with multi-material slots and angle-based smoothing."""
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

    for mat in materials:
        mesh.materials.append(mat)

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _report_mesh_stats(label: str, obj: bpy.types.Object) -> None:
    """Print triangle count, material slots, and Godot Y-up bounding box."""
    mesh = obj.data
    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    g_min = (min(xs), min(zs), -max(ys))
    g_max = (max(xs), max(zs), -min(ys))
    slot_names = [m.name for m in mesh.materials]
    print(
        f"[{label}] tris={tri_count} slots={slot_names} | "
        f"Godot BBox min=({g_min[0]:.3f}, {g_min[1]:.3f}, {g_min[2]:.3f}) "
        f"max=({g_max[0]:.3f}, {g_max[1]:.3f}, {g_max[2]:.3f}) "
        f"size=({g_max[0] - g_min[0]:.3f}, {g_max[1] - g_min[1]:.3f}, {g_max[2] - g_min[2]:.3f})"
    )


# ==============================================================================
# 1. WAREHOUSE SHELF (2.4m W x 2.2m H x 0.9m D)
# ==============================================================================
def _add_slotted_upright(
    bm: bmesh.types.BMesh,
    cx: float,
    cy: float,
    x_inward: float,
    y_inward: float,
    height: float,
    mat_steel: int,
) -> None:
    """Build a heavy C-channel slotted steel pallet-rack upright column with anchor footplate."""
    post_w = 0.070
    post_d = 0.065
    wall_t = 0.012
    base_h = 0.014

    # Outer boundaries clamped flush to the 2.4m x 0.9m envelope
    x_out = cx - x_inward * (post_w * 0.5)
    x_in = cx + x_inward * (post_w * 0.5)
    y_out = cy - y_inward * (post_d * 0.5)
    y_in = cy + y_inward * (post_d * 0.5)
    px0, px1 = min(x_out, x_in), max(x_out, x_in)
    py0, py1 = min(y_out, y_in), max(y_out, y_in)

    # Footplate (flushed to outer corner, extending inward) + 2 anchor bolts
    fx0 = px0 if x_inward > 0 else px0 - 0.035
    fx1 = px1 + 0.035 if x_inward > 0 else px1
    fy0 = py0 if y_inward > 0 else py0 - 0.025
    fy1 = py1 + 0.025 if y_inward > 0 else py1
    _add_box_bm(bm, (fx0, fy0, 0.0), (fx1, fy1, base_h), mat_idx=mat_steel)

    bolt_x = cx + x_inward * 0.038
    for by_off in (-0.022, 0.022):
        bolt_y = cy + by_off
        _add_cylinder_bm(
            bm,
            Vector((bolt_x, bolt_y, base_h)),
            Vector((bolt_x, bolt_y, base_h + 0.010)),
            r0=0.009,
            segments=6,
            mat_idx=mat_steel,
        )

    # C-channel spine (on outer X side)
    if x_inward > 0:
        _add_box_bm(bm, (px0, py0, base_h), (px0 + wall_t, py1, height), mat_idx=mat_steel)
    else:
        _add_box_bm(bm, (px1 - wall_t, py0, base_h), (px1, py1, height), mat_idx=mat_steel)

    # Front and back perforated flanges (slotted uprights)
    # Represent vertical teardrop/slot punches via alternating thickened flange ribs
    slot_step = 0.14
    z_cur = base_h
    slot_h = 0.036
    while z_cur < height - 0.01:
        z_next = min(height, z_cur + slot_step)
        rib_top = min(height, z_next - slot_h) if z_next < height - 0.04 else z_next

        # Core continuous inner lip so column remains solid
        core_x0 = px0 + wall_t if x_inward > 0 else px0 + 0.008
        core_x1 = px1 - 0.008 if x_inward > 0 else px1 - wall_t
        if rib_top > z_cur + 0.005:
            _add_box_bm(bm, (core_x0, py0, z_cur), (core_x1, py0 + wall_t, rib_top), mat_idx=mat_steel)
            _add_box_bm(bm, (core_x0, py1 - wall_t, z_cur), (core_x1, py1, rib_top), mat_idx=mat_steel)

        # Outer flange ears around slot opening
        if rib_top < z_next:
            ear_x0 = px0 + wall_t if x_inward > 0 else px1 - 0.022
            ear_x1 = px0 + 0.022 if x_inward > 0 else px1 - wall_t
            _add_box_bm(bm, (ear_x0, py0, rib_top), (ear_x1, py0 + wall_t, z_next), mat_idx=mat_steel)
            _add_box_bm(bm, (ear_x0, py1 - wall_t, rib_top), (ear_x1, py1, z_next), mat_idx=mat_steel)

            lip_x0 = px1 - 0.020 if x_inward > 0 else px0
            lip_x1 = px1 if x_inward > 0 else px0 + 0.020
            _add_box_bm(bm, (lip_x0, py0, rib_top), (lip_x1, py0 + wall_t, z_next), mat_idx=mat_steel)
            _add_box_bm(bm, (lip_x0, py1 - wall_t, rib_top), (lip_x1, py1, z_next), mat_idx=mat_steel)

        z_cur = z_next

    # Top post cap plate
    _add_box_bm(bm, (px0, py0, height - 0.008), (px1, py1, height), mat_idx=mat_steel)


def _add_end_frame_bracing(
    bm: bmesh.types.BMesh,
    frame_x: float,
    y_front: float,
    y_back: float,
    mat_steel: int,
) -> None:
    """Build horizontal ties and zig-zag diagonal side bracing between front and rear uprights."""
    tie_h = 0.036
    tie_w = 0.030

    # Bottom, mid, and top horizontal end struts
    for z_tie in (0.14, 1.10, 2.12):
        _add_box_bm(
            bm,
            (frame_x - tie_w * 0.5, y_front, z_tie - tie_h * 0.5),
            (frame_x + tie_w * 0.5, y_back, z_tie + tie_h * 0.5),
            mat_idx=mat_steel,
        )

    # Zig-zag Warren diagonal bracing across 4 vertical bays
    z_nodes = [0.14, 0.64, 1.12, 1.62, 2.12]
    for i in range(len(z_nodes) - 1):
        y0 = y_front if i % 2 == 0 else y_back
        y1 = y_back if i % 2 == 0 else y_front
        p0 = Vector((frame_x, y0, z_nodes[i]))
        p1 = Vector((frame_x, y1, z_nodes[i + 1]))
        _add_oriented_box_bm(
            bm,
            p0,
            p1,
            width_x=0.026,
            thickness=0.028,
            mat_idx=mat_steel,
        )

        # Bolted node gusset collar
        for yn, zn in ((y0, z_nodes[i]), (y1, z_nodes[i + 1])):
            _add_box_bm(
                bm,
                (frame_x - 0.022, yn - 0.022, zn - 0.022),
                (frame_x + 0.022, yn + 0.022, zn + 0.022),
                mat_idx=mat_steel,
            )


def _add_shelf_tier(
    bm: bmesh.types.BMesh,
    x_inner_left: float,
    x_inner_right: float,
    y_front_outer: float,
    y_back_outer: float,
    beam_top_z: float,
    mat_steel: int,
    mat_wood: int,
) -> None:
    """Build front/rear box beams, bolted end connectors, crossbars, and 5 weathered timber planks."""
    beam_h = 0.090
    beam_t = 0.044
    beam_bot_z = beam_top_z - beam_h

    # Front & rear horizontal stepped box beams (recessed 6mm from outer Y so brackets stay <= 0.90m)
    beam_y_pad = 0.006
    _add_box_bm(
        bm,
        (x_inner_left, y_front_outer + beam_y_pad, beam_bot_z),
        (x_inner_right, y_front_outer + beam_y_pad + beam_t, beam_top_z),
        mat_idx=mat_steel,
        chamfer=0.003,
    )
    _add_box_bm(
        bm,
        (x_inner_left, y_back_outer - beam_y_pad - beam_t, beam_bot_z),
        (x_inner_right, y_back_outer - beam_y_pad, beam_top_z),
        mat_idx=mat_steel,
        chamfer=0.003,
    )

    # Bolted end connector brackets + safety lock pins flush inside [-0.45, +0.45]
    bracket_w = 0.042
    bracket_h = 0.135
    bracket_z0 = beam_top_z - bracket_h + 0.020
    bracket_z1 = beam_top_z + 0.020
    for bx0, bx1 in (
        (x_inner_left - 0.006, x_inner_left + bracket_w),
        (x_inner_right - bracket_w, x_inner_right + 0.006),
    ):
        for by0, by1 in (
            (y_front_outer, y_front_outer + beam_y_pad + beam_t + 0.006),
            (y_back_outer - beam_y_pad - beam_t - 0.006, y_back_outer),
        ):
            _add_box_bm(bm, (bx0, by0, bracket_z0), (bx1, by1, bracket_z1), mat_idx=mat_steel)
            # 2 hex lock pins protruding inward (toward shelf center)
            b_cx = 0.5 * (bx0 + bx1)
            for bz in (bracket_z0 + 0.026, bracket_z1 - 0.026):
                face_y = by1 if by0 < 0.0 else by0
                in_dir = 1.0 if by0 < 0.0 else -1.0
                _add_cylinder_bm(
                    bm,
                    Vector((b_cx, face_y, bz)),
                    Vector((b_cx, face_y + in_dir * 0.008, bz)),
                    r0=0.007,
                    segments=6,
                    mat_idx=mat_steel,
                )

    # 5 transverse steel deck support crossbars spanning front-to-back beams
    crossbar_y0 = y_front_outer + beam_y_pad + beam_t
    crossbar_y1 = y_back_outer - beam_y_pad - beam_t
    crossbar_z1 = beam_top_z
    crossbar_z0 = beam_top_z - 0.036
    span_x = x_inner_right - x_inner_left
    for i in range(5):
        cx = x_inner_left + span_x * ((i + 0.5) / 5.0)
        _add_box_bm(
            bm,
            (cx - 0.018, crossbar_y0, crossbar_z0),
            (cx + 0.018, crossbar_y1, crossbar_z1),
            mat_idx=mat_steel,
        )

    # 5 weathered timber planks resting on the steel crossbars
    plank_thick = 0.035
    plank_z0 = beam_top_z
    plank_z1 = beam_top_z + plank_thick
    plank_x0 = x_inner_left + 0.004
    plank_x1 = x_inner_right - 0.004
    deck_y0 = y_front_outer + 0.014
    deck_y1 = y_back_outer - 0.014
    n_planks = 5
    gap = 0.009
    plank_depth = ((deck_y1 - deck_y0) - gap * (n_planks - 1)) / n_planks

    for p_idx in range(n_planks):
        py0 = deck_y0 + p_idx * (plank_depth + gap)
        py1 = py0 + plank_depth
        # Subtle 1.5mm organic height variation across weathered boards
        z_jitter = ((p_idx % 3) - 1) * 0.0015
        _add_box_bm(
            bm,
            (plank_x0, py0, plank_z0),
            (plank_x1, py1, plank_z1 + z_jitter),
            mat_idx=mat_wood,
            chamfer=0.003,
        )


def generate_warehouse_shelf(output_dir: Path) -> Path:
    """Build and export warehouse_shelf.glb (2.4m W x 2.2m H x 0.9m D pallet rack)."""
    clean_scene()

    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.24, 0.25, 0.26, 1.0),
        metallic=0.85,
        roughness=0.58,
    )
    wood_mat = create_pbr_material(
        name="wood",
        base_color=(0.35, 0.26, 0.18, 1.0),
        metallic=0.0,
        roughness=0.84,
    )

    bm = bmesh.new()

    width = 2.40
    depth = 0.90
    height = 2.20
    half_w = width * 0.5      # 1.20m
    half_d = depth * 0.5      # 0.45m

    post_w = 0.070
    post_d = 0.065
    post_cx = half_w - post_w * 0.5   # 1.165m
    post_cy = half_d - post_d * 0.5   # 0.4175m

    # 4 corner slotted uprights
    _add_slotted_upright(bm, -post_cx, -post_cy, 1.0, 1.0, height, mat_steel=0)
    _add_slotted_upright(bm, post_cx, -post_cy, -1.0, 1.0, height, mat_steel=0)
    _add_slotted_upright(bm, -post_cx, post_cy, 1.0, -1.0, height, mat_steel=0)
    _add_slotted_upright(bm, post_cx, post_cy, -1.0, -1.0, height, mat_steel=0)

    # Left & right end-frame diagonal bracing
    _add_end_frame_bracing(bm, -post_cx, -post_cy + post_d * 0.5, post_cy - post_d * 0.5, mat_steel=0)
    _add_end_frame_bracing(bm, post_cx, -post_cy + post_d * 0.5, post_cy - post_d * 0.5, mat_steel=0)

    # 3 heavy shelf tiers
    x_inner_left = -half_w + post_w
    x_inner_right = half_w - post_w
    for beam_top_z in (0.26, 1.14, 1.94):
        _add_shelf_tier(
            bm,
            x_inner_left=x_inner_left,
            x_inner_right=x_inner_right,
            y_front_outer=-half_d,
            y_back_outer=half_d,
            beam_top_z=beam_top_z,
            mat_steel=0,
            mat_wood=1,
        )

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)

    shelf_obj = _finalize_bmesh_to_object("warehouse_shelf", bm, [steel_mat, wood_mat])
    _apply_box_uvs(shelf_obj, tile_meters=1.0)
    _report_mesh_stats("warehouse_shelf", shelf_obj)

    output_path = output_dir / "warehouse_shelf.glb"
    return export_godot_glb(
        filepath=output_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )


# ==============================================================================
# 2. PALLET JACK (~1.55m L x 0.55m W x 1.2m H)
# ==============================================================================
def _add_wheel_with_hub(
    bm: bmesh.types.BMesh,
    center: Vector,
    width: float,
    radius: float,
    hub_radius: float,
    mat_rubber: int,
    mat_steel: int,
) -> None:
    """Append an X-axis wheel tire with recessed steel hub and axle boss."""
    half_w = width * 0.5
    # Rubber tire cylinder along X
    _add_cylinder_bm(
        bm,
        Vector((center.x - half_w, center.y, center.z)),
        Vector((center.x + half_w, center.y, center.z)),
        r0=radius,
        segments=16,
        mat_idx=mat_rubber,
    )
    # Steel center hub slightly protruding past tire faces
    _add_cylinder_bm(
        bm,
        Vector((center.x - half_w - 0.004, center.y, center.z)),
        Vector((center.x + half_w + 0.004, center.y, center.z)),
        r0=hub_radius,
        segments=12,
        mat_idx=mat_steel,
    )


def generate_pallet_jack(output_dir: Path) -> Path:
    """Build and export pallet_jack.glb (~1.55m L x 0.55m W x 1.2m H transpallet)."""
    clean_scene()

    painted_mat = create_pbr_material(
        name="painted_steel",
        base_color=(0.74, 0.34, 0.06, 1.0),
        metallic=0.35,
        roughness=0.50,
    )
    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.58, 0.60, 0.62, 1.0),
        metallic=0.90,
        roughness=0.30,
    )
    rubber_mat = create_pbr_material(
        name="rubber",
        base_color=(0.06, 0.06, 0.065, 1.0),
        metallic=0.0,
        roughness=0.86,
    )

    bm = bmesh.new()
    mat_paint = 0
    mat_steel = 1
    mat_rubber = 2

    # Overall bounds: X[-0.275, +0.275] (0.55m), Y[-0.775, +0.775] (1.55m), Z[0.00, 1.20] (1.20m)
    fork_outer_half = 0.275
    fork_w = 0.160
    fork_centers_x = (-fork_outer_half + fork_w * 0.5, fork_outer_half - fork_w * 0.5)  # ±0.195m

    y_tip = 0.775
    y_taper_start = 0.665
    y_carriage_front = -0.375
    z_fork_top = 0.086
    z_fork_bot = 0.036

    # 1. Twin tapered steel forks + front tandem load wheel bogies
    for fx in fork_centers_x:
        x0 = fx - fork_w * 0.5
        x1 = fx + fork_w * 0.5

        # Main fork body (extruded YZ profile with tapered entry tip)
        fork_profile = [
            (y_carriage_front, z_fork_bot),
            (y_taper_start, z_fork_bot),
            (y_tip, 0.044),
            (y_tip, 0.066),
            (y_taper_start, z_fork_top),
            (y_carriage_front, z_fork_top),
        ]
        _add_extruded_yz_profile_bm(bm, x0, x1, fork_profile, mat_idx=mat_paint)

        # Entry guide nose skid ramp underneath tip
        _add_box_bm(
            bm,
            (x0 + 0.025, y_taper_start - 0.02, 0.026),
            (x1 - 0.025, y_taper_start + 0.05, z_fork_bot),
            mat_idx=mat_steel,
            chamfer=0.003,
        )

        # Tandem front load wheel bogies (2 rollers per fork, touching Z=0.0)
        load_r = 0.038
        for wy in (0.535, 0.635):
            _add_wheel_with_hub(
                bm,
                center=Vector((fx, wy, load_r)),
                width=0.064,
                radius=load_r,
                hub_radius=0.016,
                mat_rubber=mat_rubber,
                mat_steel=mat_steel,
            )
            # Bogie side rocker plates flanking wheel
            for side in (-1.0, 1.0):
                px = fx + side * 0.042
                _add_box_bm(
                    bm,
                    (px - 0.006, wy - 0.030, 0.026),
                    (px + 0.006, wy + 0.030, z_fork_bot + 0.008),
                    mat_idx=mat_steel,
                )

        # Steel pushrod linkage bar under fork belly
        _add_box_bm(
            bm,
            (fx - 0.012, y_carriage_front + 0.05, 0.026),
            (fx + 0.012, 0.515, 0.038),
            mat_idx=mat_steel,
        )

    # 2. Rear fork shoulder / lift carriage apron
    _add_box_bm(
        bm,
        (-fork_outer_half, -0.455, 0.050),
        (fork_outer_half, y_carriage_front, 0.240),
        mat_idx=mat_paint,
        chamfer=0.005,
    )
    # Angled shoulder reinforcement gussets above each fork root
    for fx in fork_centers_x:
        _add_box_bm(
            bm,
            (fx - 0.045, y_carriage_front, z_fork_top),
            (fx + 0.045, y_carriage_front + 0.11, 0.145),
            mat_idx=mat_paint,
            chamfer=0.004,
        )

    # Top lift yoke shoulder connecting carriage to hydraulic piston head
    _add_box_bm(
        bm,
        (-0.115, -0.535, 0.455),
        (0.115, -0.435, 0.515),
        mat_idx=mat_paint,
        chamfer=0.005,
    )
    # Vertical carriage spine down from yoke to apron
    _add_box_bm(
        bm,
        (-0.075, -0.465, 0.235),
        (0.075, -0.405, 0.465),
        mat_idx=mat_paint,
        chamfer=0.004,
    )

    # 3. Rear steer wheel bogie (twin wheels touching Z=0.0)
    steer_r = 0.088
    steer_y = -0.585
    for sx in (-0.082, 0.082):
        _add_wheel_with_hub(
            bm,
            center=Vector((sx, steer_y, steer_r)),
            width=0.048,
            radius=steer_r,
            hub_radius=0.032,
            mat_rubber=mat_rubber,
            mat_steel=mat_steel,
        )
    # Steer axle shaft + caster swivel yoke
    _add_cylinder_bm(
        bm,
        Vector((-0.115, steer_y, steer_r)),
        Vector((0.115, steer_y, steer_r)),
        r0=0.015,
        segments=10,
        mat_idx=mat_steel,
    )
    _add_box_bm(
        bm,
        (-0.045, steer_y - 0.045, steer_r - 0.01),
        (0.045, steer_y + 0.045, 0.185),
        mat_idx=mat_steel,
        chamfer=0.004,
    )
    # Swivel thrust bearing collar
    _add_cylinder_bm(
        bm,
        Vector((0.0, steer_y, 0.185)),
        Vector((0.0, steer_y, 0.225)),
        r0=0.056,
        segments=16,
        mat_idx=mat_steel,
    )

    # 4. Hydraulic Pump Assembly (cast base, main cylinder, chrome piston ram, valve block)
    _add_box_bm(
        bm,
        (-0.072, -0.660, 0.220),
        (0.072, -0.480, 0.310),
        mat_idx=mat_paint,
        chamfer=0.006,
    )
    # Main hydraulic cylinder barrel
    _add_cylinder_bm(
        bm,
        Vector((0.0, -0.530, 0.250)),
        Vector((0.0, -0.530, 0.435)),
        r0=0.042,
        segments=16,
        mat_idx=mat_paint,
    )
    # Chrome piston rod extending up into yoke
    _add_cylinder_bm(
        bm,
        Vector((0.0, -0.530, 0.430)),
        Vector((0.0, -0.530, 0.500)),
        r0=0.022,
        segments=14,
        mat_idx=mat_steel,
    )
    # Hydraulic spring & plunger housing on pump rear
    _add_cylinder_bm(
        bm,
        Vector((0.0, -0.605, 0.285)),
        Vector((0.0, -0.625, 0.370)),
        r0=0.024,
        segments=12,
        mat_idx=mat_steel,
    )
    # Release foot-pedal / valve cam
    _add_box_bm(
        bm,
        (0.065, -0.630, 0.230),
        (0.105, -0.565, 0.260),
        mat_idx=mat_steel,
        chamfer=0.002,
    )

    # 5. Articulated Drawbar Handle with Closed Loop Grip (reaches Z = 1.20m)
    pivot_y = -0.625
    pivot_z = 0.295
    # Clevis bracket & steel pivot pin
    _add_box_bm(
        bm,
        (-0.058, -0.665, 0.270),
        (0.058, -0.595, 0.325),
        mat_idx=mat_steel,
        chamfer=0.003,
    )
    _add_cylinder_bm(
        bm,
        Vector((-0.072, pivot_y, pivot_z)),
        Vector((0.072, pivot_y, pivot_z)),
        r0=0.012,
        segments=10,
        mat_idx=mat_steel,
    )

    # Twin A-frame drawbar struts rising from clevis to stem junction
    junc_y = -0.680
    junc_z = 0.510
    for sx in (-0.044, 0.044):
        _add_cylinder_bm(
            bm,
            Vector((sx, pivot_y, pivot_z)),
            Vector((sx * 0.45, junc_y, junc_z)),
            r0=0.015,
            r1=0.013,
            segments=10,
            mat_idx=mat_paint,
        )
    # Junction collar
    _add_cylinder_bm(
        bm,
        Vector((0.0, junc_y, junc_z - 0.020)),
        Vector((0.0, junc_y - 0.006, junc_z + 0.035)),
        r0=0.026,
        segments=12,
        mat_idx=mat_paint,
    )

    # Main angled drawbar stem up to loop base
    loop_base = Vector((0.0, -0.745, 1.015))
    _add_cylinder_bm(
        bm,
        Vector((0.0, junc_y, junc_z)),
        loop_base,
        r0=0.020,
        r1=0.018,
        segments=12,
        mat_idx=mat_paint,
    )

    # Closed triangular / D-loop ergonomic grip handle (top at Z = 1.20m, Y = -0.775m)
    grip_z = 1.184
    grip_y = -0.759
    grip_r = 0.016  # top surface reaches Z = 1.200m, outer Y reaches -0.775m
    grip_half_w = 0.132

    # Left & right flared loop arms
    for side in (-1.0, 1.0):
        corner = Vector((side * grip_half_w, grip_y, grip_z))
        _add_cylinder_bm(
            bm,
            loop_base,
            corner,
            r0=0.016,
            r1=0.015,
            segments=10,
            mat_idx=mat_paint,
        )
        # End corner cap sphere-like joint
        _add_box_bm(
            bm,
            (corner.x - 0.016, corner.y - 0.016, corner.z - 0.016),
            (corner.x + 0.016, corner.y + 0.016, corner.z + 0.016),
            mat_idx=mat_paint,
            chamfer=0.005,
        )

    # Top horizontal rubberized grip bar
    _add_cylinder_bm(
        bm,
        Vector((-grip_half_w, grip_y, grip_z)),
        Vector((grip_half_w, grip_y, grip_z)),
        r0=grip_r,
        segments=14,
        mat_idx=mat_rubber,
    )

    # Inner articulated steel release trigger lever + linkage rod along stem
    trig_y = grip_y + 0.010
    trig_z = 1.125
    _add_cylinder_bm(
        bm,
        Vector((-0.075, trig_y, trig_z)),
        Vector((0.075, trig_y, trig_z)),
        r0=0.008,
        segments=8,
        mat_idx=mat_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((0.0, trig_y, trig_z)),
        Vector((0.0, loop_base.y + 0.015, loop_base.z)),
        r0=0.006,
        segments=8,
        mat_idx=mat_steel,
    )
    _add_cylinder_bm(
        bm,
        Vector((0.0, junc_y + 0.020, junc_z)),
        Vector((0.0, -0.615, 0.370)),
        r0=0.005,
        segments=8,
        mat_idx=mat_steel,
    )

    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)

    jack_obj = _finalize_bmesh_to_object("pallet_jack", bm, [painted_mat, steel_mat, rubber_mat])
    _apply_box_uvs(jack_obj, tile_meters=1.0)
    _report_mesh_stats("pallet_jack", jack_obj)

    output_path = output_dir / "pallet_jack.glb"
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
    """Generate both workshop prop GLBs."""
    sdk_root = Path(__file__).resolve().parent.parent.parent.parent
    output_dir = sdk_root / "assets" / "models" / "props" / "factory_workshop"
    output_dir.mkdir(parents=True, exist_ok=True)

    generate_warehouse_shelf(output_dir)
    generate_pallet_jack(output_dir)


if __name__ == "__main__":
    main()
