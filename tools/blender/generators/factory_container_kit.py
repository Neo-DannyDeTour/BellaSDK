"""Procedural Blender generator for 20ft ISO shipping container GLBs.

Generates 2 clean-room 20ft ISO shipping container assets in
assets/models/props/factory_yard/:
1. shipping_container.glb      - Closed 20ft ISO container (~2.44m W x 2.59m H x 6.06m L).
2. shipping_container_open.glb - Open 20ft ISO container with rear doors swung ~115 deg outward
                                 and hollow walkable interior (corrugated walls + wood floor deck).

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Z).
- Godot Y-up export via tools/blender/common/exporter.py.
- Clean 2.0m world-metric cubic box UVs.
- Explicit material slots:
  - shipping_container.glb:      ['painted_steel', 'steel']
  - shipping_container_open.glb: ['painted_steel', 'steel', 'wood']
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

# Standard 20ft ISO 1CC shipping container dimensions (meters)
CONT_W = 2.438
CONT_L = 6.058
CONT_H = 2.591
HALF_W = CONT_W * 0.5  # 1.219m
HALF_L = CONT_L * 0.5  # 3.029m

# Corner castings & structural posts
CAST_X = 0.180
CAST_Y = 0.170
CAST_Z = 0.125

FRONT_POST_X = 0.110
REAR_POST_X = 0.095

# Rails & floor heights
RAIL_W = 0.070
BOT_RAIL_Z0 = 0.012
BOT_RAIL_Z1 = 0.160
TOP_RAIL_Z0 = 2.466
TOP_RAIL_Z1 = CONT_H

DOOR_SILL_Z1 = 0.145
DOOR_HEAD_Z0 = 2.445
FLOOR_SUB_Z0 = 0.095
FLOOR_SUB_Z1 = 0.115
FLOOR_TOP_Z = DOOR_SILL_Z1

# Door hinge pivot & open angle (doors located at rear Y = -HALF_L)
HINGE_X = HALF_W - REAR_POST_X + 0.008  # 1.132m (slightly proud of inner post edge)
HINGE_Y = -HALF_L + 0.001               # -3.028m
OPEN_ANGLE_DEG = 115.0

# UV tiling
UV_TILE_METERS = 2.0


# ==============================================================================
# SHARED BMESH & UV HELPERS
# ==============================================================================
def _merge_temp_bmesh(
    tmp: bmesh.types.BMesh,
    dst: bmesh.types.BMesh,
    mat_idx: int,
) -> list[bmesh.types.BMFace]:
    """Copy vertices and faces from a temporary BMesh into dst with mat_idx."""
    v_map: dict[bmesh.types.BMVert, bmesh.types.BMVert] = {}
    for v in tmp.verts:
        v_map[v] = dst.verts.new(v.co)

    added: list[bmesh.types.BMFace] = []
    for f in tmp.faces:
        nf = dst.faces.new([v_map[v] for v in f.verts])
        nf.material_index = mat_idx
        added.append(nf)
    tmp.free()
    return added


def _add_box_bm(
    bm: bmesh.types.BMesh,
    p_min: tuple[float, float, float],
    p_max: tuple[float, float, float],
    mat_idx: int = 0,
    chamfer: float = 0.0,
) -> list[bmesh.types.BMFace]:
    """Append an axis-aligned box (with optional edge chamfer) to bm."""
    x0, y0, z0 = p_min
    x1, y1, z1 = p_max
    if x1 <= x0 or y1 <= y0 or z1 <= z0:
        return []

    if chamfer <= 0.0:
        coords = (
            (x0, y0, z0),
            (x1, y0, z0),
            (x1, y1, z0),
            (x0, y1, z0),
            (x0, y0, z1),
            (x1, y0, z1),
            (x1, y1, z1),
            (x0, y1, z1),
        )
        verts = [bm.verts.new(c) for c in coords]
        quads = (
            (0, 3, 2, 1),
            (4, 5, 6, 7),
            (0, 1, 5, 4),
            (2, 3, 7, 6),
            (0, 4, 7, 3),
            (1, 2, 6, 5),
        )
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


def _add_cylinder_bm(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    radius: float,
    segments: int = 10,
    mat_idx: int = 0,
) -> list[bmesh.types.BMFace]:
    """Append a capped cylinder spanning p0 to p1."""
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
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=length,
        matrix=xf,
    )
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _add_corrugated_panel_bm(
    bm: bmesh.types.BMesh,
    axis_u: Vector,
    axis_v: Vector,
    axis_n: Vector,
    origin: Vector,
    len_u: float,
    len_v: float,
    wave_depth: float,
    sheet_thick: float,
    waves: int,
    mat_idx: int,
    slope_frac: float = 0.18,
) -> list[bmesh.types.BMFace]:
    """Build a solid manifold trapezoidal corrugated sheet in local (u, v, n) frame.

    u = direction across corrugation waves [0 .. len_u]
    v = direction along corrugation ribs [0 .. len_v]
    n = outward wave displacement direction [0 .. wave_depth]
    """
    pitch = len_u / float(waves)
    n_low = 0.0
    n_high = max(0.002, wave_depth - sheet_thick)

    t1 = 0.16
    t2 = t1 + slope_frac
    t3 = 1.0 - t1 - slope_frac
    t4 = 1.0 - t1

    profile_un: list[tuple[float, float]] = []
    for i in range(waves):
        u0 = i * pitch
        profile_un.extend(
            (
                (u0 + 0.00 * pitch, n_low),
                (u0 + t1 * pitch, n_low),
                (u0 + t2 * pitch, n_high),
                (u0 + t3 * pitch, n_high),
                (u0 + t4 * pitch, n_low),
            )
        )
    profile_un.append((len_u, n_low))

    tmp = bmesh.new()
    v_off = axis_v * len_v

    bot_a = [tmp.verts.new(origin + axis_u * pu + axis_n * pn) for pu, pn in profile_un]
    top_a = [
        tmp.verts.new(origin + axis_u * pu + axis_n * (pn + sheet_thick))
        for pu, pn in profile_un
    ]
    bot_b = [tmp.verts.new(origin + axis_u * pu + axis_n * pn + v_off) for pu, pn in profile_un]
    top_b = [
        tmp.verts.new(origin + axis_u * pu + axis_n * (pn + sheet_thick) + v_off)
        for pu, pn in profile_un
    ]

    n_pts = len(profile_un)
    for i in range(n_pts - 1):
        tmp.faces.new((top_a[i], top_a[i + 1], top_b[i + 1], top_b[i]))
        tmp.faces.new((bot_a[i + 1], bot_a[i], bot_b[i], bot_b[i + 1]))
        tmp.faces.new((bot_a[i], bot_a[i + 1], top_a[i + 1], top_a[i]))
        tmp.faces.new((bot_b[i + 1], bot_b[i], top_b[i], top_b[i + 1]))

    tmp.faces.new((bot_b[0], bot_a[0], top_a[0], top_b[0]))
    tmp.faces.new((bot_a[-1], bot_b[-1], top_b[-1], top_a[-1]))

    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    return _merge_temp_bmesh(tmp, bm, mat_idx)


def _apply_box_uvs_bm(
    bm: bmesh.types.BMesh,
    uv_layer: bmesh.types.BMLayerItem,
    faces: list[bmesh.types.BMFace],
    tile_meters: float = UV_TILE_METERS,
) -> None:
    """Assign world-metric cubic box UVs directly on the given BMesh faces."""
    inv_tile = 1.0 / tile_meters
    for face in faces:
        face.normal_update()
        nx = abs(face.normal.x)
        ny = abs(face.normal.y)
        nz = abs(face.normal.z)
        for loop in face.loops:
            co = loop.vert.co
            if nx >= ny and nx >= nz:
                u, v = co.y * inv_tile, co.z * inv_tile
            elif ny >= nx and ny >= nz:
                u, v = co.x * inv_tile, co.z * inv_tile
            else:
                u, v = co.x * inv_tile, co.y * inv_tile
            loop[uv_layer].uv = (u, v)


def _rotate_faces_z(
    bm: bmesh.types.BMesh,
    faces: list[bmesh.types.BMFace],
    pivot: tuple[float, float, float],
    angle_deg: float,
) -> None:
    """Rotate a disjoint subset of faces around a vertical Z axis at pivot."""
    verts = list({v for f in faces for v in f.verts})
    rot = Matrix.Rotation(math.radians(angle_deg), 3, "Z")
    bmesh.ops.rotate(bm, cent=pivot, matrix=rot, verts=verts)


def _finalize_bmesh_to_object(
    name: str,
    bm: bmesh.types.BMesh,
    materials: list[bpy.types.Material],
    auto_smooth_deg: float = 35.0,
) -> bpy.types.Object:
    """Convert BMesh into a clean scene Object with ordered material slots and edge smoothing."""
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


# ==============================================================================
# CONTAINER SUB-ASSEMBLIES
# ==============================================================================
def _add_corner_casting(
    bm: bmesh.types.BMesh,
    x_sign: float,
    y_sign: float,
    z0: float,
    z1: float,
    mat_steel: int,
) -> list[bmesh.types.BMFace]:
    """Build an ISO corner casting with recessed lifting/stacking pocket rims."""
    faces: list[bmesh.types.BMFace] = []
    x_out = x_sign * HALF_W
    x_in = x_sign * (HALF_W - CAST_X)
    y_out = y_sign * HALF_L
    y_in = y_sign * (HALF_L - CAST_Y)

    px0, px1 = min(x_out, x_in), max(x_out, x_in)
    py0, py1 = min(y_out, y_in), max(y_out, y_in)

    # Slightly inset core so outer faces read as framed casting pockets
    inset = 0.014
    cx0 = px0 + (inset if x_sign < 0 else 0.0)
    cx1 = px1 - (inset if x_sign > 0 else 0.0)
    cy0 = py0 + (inset if y_sign < 0 else 0.0)
    cy1 = py1 - (inset if y_sign > 0 else 0.0)
    faces.extend(_add_box_bm(bm, (cx0, cy0, z0), (cx1, cy1, z1), mat_idx=mat_steel, chamfer=0.005))

    # Perimeter rim strips on outer side face (X = x_out) & outer end face (Y = y_out)
    rim_t = 0.026
    rim_z = 0.024
    # Top & bottom rim bands flush to full envelope
    faces.extend(
        _add_box_bm(bm, (px0, py0, z0), (px1, py1, z0 + rim_z), mat_idx=mat_steel, chamfer=0.004)
    )
    faces.extend(
        _add_box_bm(bm, (px0, py0, z1 - rim_z), (px1, py1, z1), mat_idx=mat_steel, chamfer=0.004)
    )
    # Corner vertical pillar lip + inner vertical lip framing side/end apertures
    vx0 = x_out - rim_t if x_sign > 0 else x_out
    vx1 = x_out if x_sign > 0 else x_out + rim_t
    vy0 = y_out - rim_t if y_sign > 0 else y_out
    vy1 = y_out if y_sign > 0 else y_out + rim_t
    faces.extend(
        _add_box_bm(
            bm,
            (vx0, py0, z0 + rim_z),
            (vx1, py1, z1 - rim_z),
            mat_idx=mat_steel,
            chamfer=0.003,
        )
    )
    faces.extend(
        _add_box_bm(
            bm,
            (px0, vy0, z0 + rim_z),
            (px1, vy1, z1 - rim_z),
            mat_idx=mat_steel,
            chamfer=0.003,
        )
    )
    return faces


def _add_side_rail_with_pockets(
    bm: bmesh.types.BMesh,
    x_sign: float,
    mat_paint: int,
    mat_steel: int,
) -> list[bmesh.types.BMFace]:
    """Build a bottom longitudinal side rail with 2 hollow forklift pockets."""
    faces: list[bmesh.types.BMFace] = []
    x_out = x_sign * HALF_W
    x_in = x_sign * (HALF_W - RAIL_W)
    rx0, rx1 = min(x_out, x_in), max(x_out, x_in)

    y_start = -(HALF_L - CAST_Y)  # -2.859
    y_end = HALF_L - CAST_Y       # +2.859
    pocket_centers = (-1.025, 1.025)
    pocket_half_w = 0.180         # 0.36m wide forklift pocket
    pocket_z0 = 0.028
    pocket_z1 = 0.128

    # Solid rail segments between corner castings and pockets
    segments_y = (
        (y_start, pocket_centers[0] - pocket_half_w),
        (pocket_centers[0] + pocket_half_w, pocket_centers[1] - pocket_half_w),
        (pocket_centers[1] + pocket_half_w, y_end),
    )
    for sy0, sy1 in segments_y:
        faces.extend(
            _add_box_bm(
                bm,
                (rx0, sy0, BOT_RAIL_Z0),
                (rx1, sy1, BOT_RAIL_Z1),
                mat_idx=mat_paint,
                chamfer=0.004,
            )
        )

    # Top and bottom bridges + recessed inner steel pocket sleeve at each forklift pocket
    sleeve_depth = 0.28
    for py_c in pocket_centers:
        py0 = py_c - pocket_half_w
        py1 = py_c + pocket_half_w
        faces.extend(
            _add_box_bm(
                bm,
                (rx0, py0, BOT_RAIL_Z0),
                (rx1, py1, pocket_z0),
                mat_idx=mat_paint,
                chamfer=0.003,
            )
        )
        faces.extend(
            _add_box_bm(
                bm,
                (rx0, py0, pocket_z1),
                (rx1, py1, BOT_RAIL_Z1),
                mat_idx=mat_paint,
                chamfer=0.003,
            )
        )

        # Recessed steel forklift pocket tunnel extending inward
        sx_outer = x_in
        sx_inner = x_in - x_sign * sleeve_depth
        sx0, sx1 = min(sx_outer, sx_inner), max(sx_outer, sx_inner)
        wall_t = 0.012
        faces.extend(
            _add_box_bm(bm, (sx0, py0, pocket_z0 - wall_t), (sx1, py1, pocket_z0), mat_idx=mat_steel)
        )
        faces.extend(
            _add_box_bm(bm, (sx0, py0, pocket_z1), (sx1, py1, pocket_z1 + wall_t), mat_idx=mat_steel)
        )
        faces.extend(
            _add_box_bm(bm, (sx0, py0 - wall_t, pocket_z0), (sx1, py0, pocket_z1), mat_idx=mat_steel)
        )
        faces.extend(
            _add_box_bm(bm, (sx0, py1, pocket_z0), (sx1, py1 + wall_t, pocket_z1), mat_idx=mat_steel)
        )
        # Back plate closing tunnel interior
        bx0 = sx_inner if x_sign > 0 else sx_inner - wall_t
        bx1 = sx_inner + wall_t if x_sign > 0 else sx_inner
        faces.extend(
            _add_box_bm(bm, (bx0, py0, pocket_z0), (bx1, py1, pocket_z1), mat_idx=mat_steel)
        )

    return faces


def _add_container_shell(
    bm: bmesh.types.BMesh,
    is_open: bool,
    mat_paint: int,
    mat_steel: int,
    mat_wood: int,
) -> list[bmesh.types.BMFace]:
    """Build the main 20ft ISO container structural frame, corrugated shell, and interior floor."""
    faces: list[bmesh.types.BMFace] = []

    # 1. 8 ISO Corner Castings
    for xs in (-1.0, 1.0):
        for ys in (-1.0, 1.0):
            faces.extend(_add_corner_casting(bm, xs, ys, 0.0, CAST_Z, mat_steel))
            faces.extend(_add_corner_casting(bm, xs, ys, TOP_RAIL_Z0, CONT_H, mat_steel))

    # 2. 4 Corner Posts
    for xs in (-1.0, 1.0):
        # Front corner posts (Y = +HALF_L)
        fx_out = xs * HALF_W
        fx_in = xs * (HALF_W - FRONT_POST_X)
        faces.extend(
            _add_box_bm(
                bm,
                (min(fx_out, fx_in), HALF_L - CAST_Y, CAST_Z),
                (max(fx_out, fx_in), HALF_L, TOP_RAIL_Z0),
                mat_idx=mat_paint,
                chamfer=0.005,
            )
        )
        # Rear door corner posts (Y = -HALF_L)
        rx_out = xs * HALF_W
        rx_in = xs * (HALF_W - REAR_POST_X)
        faces.extend(
            _add_box_bm(
                bm,
                (min(rx_out, rx_in), -HALF_L, CAST_Z),
                (max(rx_out, rx_in), -HALF_L + CAST_Y, TOP_RAIL_Z0),
                mat_idx=mat_paint,
                chamfer=0.005,
            )
        )

    # 3. Top & Bottom Longitudinal Side Rails
    y_span0 = -(HALF_L - CAST_Y)
    y_span1 = HALF_L - CAST_Y
    for xs in (-1.0, 1.0):
        faces.extend(_add_side_rail_with_pockets(bm, xs, mat_paint, mat_steel))
        x_out = xs * HALF_W
        x_in = xs * (HALF_W - RAIL_W)
        faces.extend(
            _add_box_bm(
                bm,
                (min(x_out, x_in), y_span0, TOP_RAIL_Z0),
                (max(x_out, x_in), y_span1, TOP_RAIL_Z1),
                mat_idx=mat_paint,
                chamfer=0.005,
            )
        )

    # 4. Front End Header & Sill (Y = +HALF_L), fitted cleanly between corner castings
    cast_x_span = HALF_W - CAST_X  # 1.039m
    faces.extend(
        _add_box_bm(
            bm,
            (-cast_x_span, HALF_L - CAST_Y, BOT_RAIL_Z0),
            (cast_x_span, HALF_L, FLOOR_SUB_Z1),
            mat_idx=mat_paint,
            chamfer=0.004,
        )
    )
    faces.extend(
        _add_box_bm(
            bm,
            (-cast_x_span, HALF_L - CAST_Y, TOP_RAIL_Z0),
            (cast_x_span, HALF_L, CONT_H),
            mat_idx=mat_paint,
            chamfer=0.005,
        )
    )

    # 5. Rear Door Header & Threshold Sill (Y = -HALF_L), non-overlapping with corner castings
    rear_x_span = HALF_W - REAR_POST_X  # 1.124m -> 2.248m clear opening
    # Sill lower section between castings + upper threshold lip between rear posts
    faces.extend(
        _add_box_bm(
            bm,
            (-cast_x_span, -HALF_L, BOT_RAIL_Z0),
            (cast_x_span, -HALF_L + CAST_Y, CAST_Z),
            mat_idx=mat_paint,
            chamfer=0.004,
        )
    )
    faces.extend(
        _add_box_bm(
            bm,
            (-rear_x_span, -HALF_L, CAST_Z),
            (rear_x_span, -HALF_L + CAST_Y, DOOR_SILL_Z1),
            mat_idx=mat_paint,
            chamfer=0.004,
        )
    )
    # Header upper section between castings + lower lintel lip between rear posts
    faces.extend(
        _add_box_bm(
            bm,
            (-cast_x_span, -HALF_L, TOP_RAIL_Z0),
            (cast_x_span, -HALF_L + CAST_Y, CONT_H),
            mat_idx=mat_paint,
            chamfer=0.004,
        )
    )
    faces.extend(
        _add_box_bm(
            bm,
            (-rear_x_span, -HALF_L, DOOR_HEAD_Z0),
            (rear_x_span, -HALF_L + CAST_Y, TOP_RAIL_Z0),
            mat_idx=mat_paint,
            chamfer=0.004,
        )
    )

    # 4 upper & 4 lower steel cam keepers on rear header/sill
    for kx in (-0.80, -0.24, 0.24, 0.80):
        faces.extend(
            _add_box_bm(
                bm,
                (kx - 0.032, -HALF_L - 0.018, DOOR_HEAD_Z0 + 0.010),
                (kx + 0.032, -HALF_L + 0.004, DOOR_HEAD_Z0 + 0.065),
                mat_idx=mat_steel,
                chamfer=0.003,
            )
        )
        faces.extend(
            _add_box_bm(
                bm,
                (kx - 0.032, -HALF_L - 0.018, DOOR_SILL_Z1 - 0.065),
                (kx + 0.032, -HALF_L + 0.004, DOOR_SILL_Z1 - 0.010),
                mat_idx=mat_steel,
                chamfer=0.003,
            )
        )

    # 6. Corrugated Side Walls (36 vertical waves each, solid manifold sheet)
    wall_len_y = y_span1 - y_span0  # 5.718m
    wall_h = TOP_RAIL_Z0 - BOT_RAIL_Z1
    wave_depth = 0.038
    sheet_t = 0.012
    # Left side wall (X < 0, outward crest at -1.202)
    faces.extend(
        _add_corrugated_panel_bm(
            bm,
            axis_u=Vector((0.0, 1.0, 0.0)),
            axis_v=Vector((0.0, 0.0, 1.0)),
            axis_n=Vector((-1.0, 0.0, 0.0)),
            origin=Vector((-HALF_W + RAIL_W - 0.015, y_span0, BOT_RAIL_Z1)),
            len_u=wall_len_y,
            len_v=wall_h,
            wave_depth=wave_depth,
            sheet_thick=sheet_t,
            waves=36,
            mat_idx=mat_paint,
        )
    )
    # Right side wall (X > 0, outward crest at +1.202)
    faces.extend(
        _add_corrugated_panel_bm(
            bm,
            axis_u=Vector((0.0, 1.0, 0.0)),
            axis_v=Vector((0.0, 0.0, 1.0)),
            axis_n=Vector((1.0, 0.0, 0.0)),
            origin=Vector((HALF_W - RAIL_W + 0.015, y_span0, BOT_RAIL_Z1)),
            len_u=wall_len_y,
            len_v=wall_h,
            wave_depth=wave_depth,
            sheet_thick=sheet_t,
            waves=36,
            mat_idx=mat_paint,
        )
    )

    # 7. Corrugated Front Wall (14 vertical waves, Y = +HALF_L recessed)
    front_wall_x0 = -(HALF_W - RAIL_W)
    front_wall_w = 2.0 * (HALF_W - RAIL_W)
    faces.extend(
        _add_corrugated_panel_bm(
            bm,
            axis_u=Vector((1.0, 0.0, 0.0)),
            axis_v=Vector((0.0, 0.0, 1.0)),
            axis_n=Vector((0.0, 1.0, 0.0)),
            origin=Vector((front_wall_x0, HALF_L - 0.062, FLOOR_SUB_Z1)),
            len_u=front_wall_w,
            len_v=TOP_RAIL_Z0 - FLOOR_SUB_Z1,
            wave_depth=wave_depth,
            sheet_thick=sheet_t,
            waves=14,
            mat_idx=mat_paint,
        )
    )

    # 8. Corrugated Roof Deck (36 transverse waves along Y)
    roof_w = 2.0 * (HALF_W - RAIL_W)
    faces.extend(
        _add_corrugated_panel_bm(
            bm,
            axis_u=Vector((0.0, 1.0, 0.0)),
            axis_v=Vector((1.0, 0.0, 0.0)),
            axis_n=Vector((0.0, 0.0, 1.0)),
            origin=Vector((-(HALF_W - RAIL_W), y_span0, TOP_RAIL_Z0 + 0.068)),
            len_u=wall_len_y,
            len_v=roof_w,
            wave_depth=0.036,
            sheet_thick=sheet_t,
            waves=36,
            mat_idx=mat_paint,
        )
    )
    # Front and rear roof header inner soffit strip closing gap above front/rear header
    faces.extend(
        _add_box_bm(
            bm,
            (-(HALF_W - RAIL_W), HALF_L - CAST_Y, TOP_RAIL_Z0),
            (HALF_W - RAIL_W, HALF_L - 0.062, TOP_RAIL_Z0 + 0.104),
            mat_idx=mat_paint,
        )
    )

    # 9. Underframe Crossmembers & Interior Floor Deck
    cross_x = HALF_W - RAIL_W
    for cy in (-2.45, -1.85, -1.25, -0.625, 0.0, 0.625, 1.25, 1.85, 2.45):
        faces.extend(
            _add_box_bm(
                bm,
                (-cross_x, cy - 0.025, 0.050),
                (cross_x, cy + 0.025, FLOOR_SUB_Z0),
                mat_idx=mat_paint,
            )
        )

    if is_open:
        # Steel underframe subfloor pan
        faces.extend(
            _add_box_bm(
                bm,
                (-cross_x, y_span0, FLOOR_SUB_Z0),
                (cross_x, HALF_L - 0.062, FLOOR_SUB_Z1),
                mat_idx=mat_steel,
            )
        )
        # 8 longitudinal marine-plywood/plank floorboards (Z[0.115, 0.145], flush with rear sill)
        plank_count = 8
        total_w = 2.0 * cross_x
        gap = 0.004
        plank_w = (total_w - gap * (plank_count - 1)) / float(plank_count)
        for idx in range(plank_count):
            px0 = -cross_x + idx * (plank_w + gap)
            px1 = px0 + plank_w
            faces.extend(
                _add_box_bm(
                    bm,
                    (px0, y_span0, FLOOR_SUB_Z1),
                    (px1, HALF_L - 0.062, FLOOR_TOP_Z),
                    mat_idx=mat_wood,
                    chamfer=0.0025,
                )
            )
    else:
        # Closed container sealed belly plate
        faces.extend(
            _add_box_bm(
                bm,
                (-cross_x, y_span0, FLOOR_SUB_Z0),
                (cross_x, HALF_L - 0.062, FLOOR_TOP_Z),
                mat_idx=mat_paint,
            )
        )

    return faces


# ==============================================================================
# REAR DOUBLE DOORS, HINGES & 4 VERTICAL LOCKING BARS
# ==============================================================================
def _add_door_leaf(
    bm: bmesh.types.BMesh,
    side_sign: float,
    mat_paint: int,
    mat_steel: int,
) -> tuple[list[bmesh.types.BMFace], list[bmesh.types.BMFace]]:
    """Build one closed rear door leaf, its rotating straps, and 2 vertical locking bars.

    Returns (fixed_post_hinge_faces, rotating_leaf_faces).
    """
    fixed_faces: list[bmesh.types.BMFace] = []
    leaf_faces: list[bmesh.types.BMFace] = []

    rear_x_span = HALF_W - REAR_POST_X  # 1.124m
    x_outer = side_sign * (rear_x_span - 0.004)  # ±1.120m
    x_inner = side_sign * 0.004                  # ±0.004m
    lx0, lx1 = min(x_outer, x_inner), max(x_outer, x_inner)

    z0 = DOOR_SILL_Z1 + 0.005  # 0.150m
    z1 = DOOR_HEAD_Z0 - 0.005  # 2.440m
    y_front = -HALF_L + 0.017  # -3.012m (outer door face)
    y_back = y_front + 0.050   # -2.962m (inner door face)

    frame_w = 0.065

    # Door leaf perimeter steel box frame
    leaf_faces.extend(
        _add_box_bm(bm, (lx0, y_front, z0), (lx1, y_back, z0 + frame_w), mat_idx=mat_paint, chamfer=0.003)
    )
    leaf_faces.extend(
        _add_box_bm(bm, (lx0, y_front, z1 - frame_w), (lx1, y_back, z1), mat_idx=mat_paint, chamfer=0.003)
    )
    leaf_faces.extend(
        _add_box_bm(
            bm,
            (lx0, y_front, z0 + frame_w),
            (lx0 + frame_w, y_back, z1 - frame_w),
            mat_idx=mat_paint,
            chamfer=0.003,
        )
    )
    leaf_faces.extend(
        _add_box_bm(
            bm,
            (lx1 - frame_w, y_front, z0 + frame_w),
            (lx1, y_back, z1 - frame_w),
            mat_idx=mat_paint,
            chamfer=0.003,
        )
    )

    # Corrugated inner door panel (6 horizontal trapezoidal ribs)
    panel_x0 = lx0 + frame_w
    panel_x1 = lx1 - frame_w
    panel_z0 = z0 + frame_w
    panel_z1 = z1 - frame_w
    leaf_faces.extend(
        _add_corrugated_panel_bm(
            bm,
            axis_u=Vector((0.0, 0.0, 1.0)),
            axis_v=Vector((1.0, 0.0, 0.0)),
            axis_n=Vector((0.0, -1.0, 0.0)),
            origin=Vector((panel_x0, y_back - 0.006, panel_z0)),
            len_u=panel_z1 - panel_z0,
            len_v=panel_x1 - panel_x0,
            wave_depth=0.036,
            sheet_thick=0.010,
            waves=6,
            mat_idx=mat_paint,
            slope_frac=0.08,
        )
    )

    # Center weather-seal astragal bar on right door leaf
    if side_sign > 0.0:
        leaf_faces.extend(
            _add_box_bm(
                bm,
                (-0.016, y_front - 0.008, z0),
                (0.016, y_front, z1),
                mat_idx=mat_steel,
                chamfer=0.002,
            )
        )

    # 4 Hinges along outer edge (fixed post lug + hinge pin + rotating door strap)
    hx = side_sign * HINGE_X
    hy = HINGE_Y
    for hz in (0.38, 0.98, 1.58, 2.18):
        # Fixed lug anchored to rear corner post
        post_edge_x = side_sign * (HALF_W - REAR_POST_X * 0.5)
        fx0, fx1 = min(hx, post_edge_x), max(hx, post_edge_x)
        fixed_faces.extend(
            _add_box_bm(
                bm,
                (fx0, hy - 0.014, hz - 0.036),
                (fx1, hy + 0.022, hz + 0.036),
                mat_idx=mat_steel,
                chamfer=0.002,
            )
        )
        # Hinge pin cylinder at exact pivot axis
        fixed_faces.extend(
            _add_cylinder_bm(
                bm,
                Vector((hx, hy, hz - 0.044)),
                Vector((hx, hy, hz + 0.044)),
                radius=0.011,
                segments=10,
                mat_idx=mat_steel,
            )
        )
        # Rotating strap blade from hinge pin onto door leaf outer face
        sx_end = side_sign * (rear_x_span - 0.165)
        sx0, sx1 = min(hx, sx_end), max(hx, sx_end)
        leaf_faces.extend(
            _add_box_bm(
                bm,
                (sx0, hy - 0.008, hz - 0.022),
                (sx1, y_front + 0.002, hz + 0.022),
                mat_idx=mat_steel,
                chamfer=0.002,
            )
        )

    # 2 Vertical locking bars + guide brackets + cams + forged handles per leaf (4 total)
    bar_xs = (side_sign * 0.24, side_sign * 0.80)
    bar_y = y_front - 0.024  # -3.036m
    for bx in bar_xs:
        # Vertical steel pipe
        leaf_faces.extend(
            _add_cylinder_bm(
                bm,
                Vector((bx, bar_y, DOOR_SILL_Z1 - 0.015)),
                Vector((bx, bar_y, DOOR_HEAD_Z0 + 0.015)),
                radius=0.015,
                segments=10,
                mat_idx=mat_steel,
            )
        )
        # Top & bottom forged locking cams
        for cz0, cz1 in ((DOOR_SILL_Z1 - 0.048, DOOR_SILL_Z1 - 0.012), (DOOR_HEAD_Z0 + 0.012, DOOR_HEAD_Z0 + 0.048)):
            leaf_faces.extend(
                _add_box_bm(
                    bm,
                    (bx - 0.024, bar_y - 0.018, cz0),
                    (bx + 0.024, bar_y + 0.020, cz1),
                    mat_idx=mat_steel,
                    chamfer=0.003,
                )
            )
        # 4 pipe guide brackets attaching bar to door leaf
        for gz in (0.42, 0.96, 1.66, 2.16):
            leaf_faces.extend(
                _add_box_bm(
                    bm,
                    (bx - 0.024, bar_y - 0.016, gz - 0.022),
                    (bx + 0.024, y_front, gz + 0.022),
                    mat_idx=mat_steel,
                    chamfer=0.002,
                )
            )
        # Forged lever handle + retainer catch at ergonomic height Z=1.14m
        hz_handle = 1.14
        h_dir = -side_sign  # handle points inward toward door center when latched
        hx_end = bx + h_dir * 0.23
        hx0, hx1 = min(bx, hx_end), max(bx, hx_end)
        # Handle pivot collar
        leaf_faces.extend(
            _add_box_bm(
                bm,
                (bx - 0.024, bar_y - 0.022, hz_handle - 0.026),
                (bx + 0.024, bar_y + 0.016, hz_handle + 0.026),
                mat_idx=mat_steel,
                chamfer=0.003,
            )
        )
        # Handle arm + ergonomic grip blade
        leaf_faces.extend(
            _add_box_bm(
                bm,
                (hx0, bar_y - 0.024, hz_handle - 0.014),
                (hx1, bar_y - 0.004, hz_handle + 0.014),
                mat_idx=mat_steel,
                chamfer=0.003,
            )
        )
        # Door-mounted retainer catch plate at handle tip
        catch_x = bx + h_dir * 0.19
        leaf_faces.extend(
            _add_box_bm(
                bm,
                (catch_x - 0.022, bar_y - 0.004, hz_handle - 0.032),
                (catch_x + 0.022, y_front, hz_handle + 0.032),
                mat_idx=mat_steel,
                chamfer=0.002,
            )
        )

    return fixed_faces, leaf_faces


# ==============================================================================
# ASSET BUILDERS & ENTRY POINT
# ==============================================================================
def _create_container_materials(include_wood: bool) -> list[bpy.types.Material]:
    """Create ordered container material slots: ['painted_steel', 'steel', ('wood')]."""
    painted_mat = create_pbr_material(
        name="painted_steel",
        base_color=(0.16, 0.28, 0.34, 1.0),
        metallic=0.35,
        roughness=0.58,
    )
    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.38, 0.40, 0.42, 1.0),
        metallic=0.88,
        roughness=0.38,
    )
    materials = [painted_mat, steel_mat]
    if include_wood:
        wood_mat = create_pbr_material(
            name="wood",
            base_color=(0.34, 0.25, 0.17, 1.0),
            metallic=0.0,
            roughness=0.85,
        )
        materials.append(wood_mat)
    return materials


def _build_container_glb(name: str, is_open: bool, output_dir: Path) -> Path:
    """Construct, UV-map, verify bounds, and export a 20ft ISO shipping container GLB."""
    clean_scene()
    materials = _create_container_materials(include_wood=is_open)

    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.verify()

    mat_paint = 0
    mat_steel = 1
    mat_wood = 2 if is_open else 1

    shell_faces = _add_container_shell(bm, is_open, mat_paint, mat_steel, mat_wood)
    fixed_l, leaf_l = _add_door_leaf(bm, -1.0, mat_paint, mat_steel)
    fixed_r, leaf_r = _add_door_leaf(bm, 1.0, mat_paint, mat_steel)

    # Apply 2.0m world-metric box UVs before swinging open doors so door texture stays aligned
    _apply_box_uvs_bm(bm, uv_layer, shell_faces + fixed_l + fixed_r, tile_meters=UV_TILE_METERS)
    _apply_box_uvs_bm(bm, uv_layer, leaf_l, tile_meters=UV_TILE_METERS)
    _apply_box_uvs_bm(bm, uv_layer, leaf_r, tile_meters=UV_TILE_METERS)

    if is_open:
        _rotate_faces_z(bm, leaf_l, (-HINGE_X, HINGE_Y, 0.0), -OPEN_ANGLE_DEG)
        _rotate_faces_z(bm, leaf_r, (HINGE_X, HINGE_Y, 0.0), OPEN_ANGLE_DEG)

    obj = _finalize_bmesh_to_object(name, bm, materials, auto_smooth_deg=35.0)
    mesh = obj.data
    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    # Godot Y-up bbox: (X, Z -> Y, -Y -> Z)
    g_min = (min(xs), min(zs), -max(ys))
    g_max = (max(xs), max(zs), -min(ys))
    slot_names = [m.name for m in mesh.materials]
    out_path = output_dir / f"{name}.glb"

    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    print(
        f"[{name}] tris={tri_count} slots={slot_names} "
        f"godot_min=({g_min[0]:.4f}, {g_min[1]:.4f}, {g_min[2]:.4f}) "
        f"godot_max=({g_max[0]:.4f}, {g_max[1]:.4f}, {g_max[2]:.4f}) "
        f"size=({g_max[0] - g_min[0]:.4f}, {g_max[1] - g_min[1]:.4f}, {g_max[2] - g_min[2]:.4f}) "
        f"path={out_path}"
    )
    return out_path


def main() -> None:
    """Generate shipping_container.glb and shipping_container_open.glb."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "props" / "factory_yard"
        output_dir.mkdir(parents=True, exist_ok=True)
        _build_container_glb("shipping_container", is_open=False, output_dir=output_dir)
        _build_container_glb("shipping_container_open", is_open=True, output_dir=output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
