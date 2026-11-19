"""Procedural Blender generator for modular exterior factory shell GLBs.

Generates 2 modular exterior shell GLBs in assets/models/factory_shells/:
1. catwalk_4m.glb        - 4.0m x 2.0m elevated industrial steel catwalk with C-channel beams,
                           cross-joists, raised ribbed/grated deck (Y[0, 0.12]), and 1.05m tall
                           tubular steel handrails + mid-rails + toe-kick plates.
2. loading_dock_ramp.glb - 4.0m x 6.0m concrete loading dock platform (Z[-3, -0.5], Y[0, 1.10]) +
                           sloped ramp (Z[-0.5, 3.0], Y=1.10 -> 0.0) + steel curb rails +
                           2 heavy black rubber dock bumpers on the dock face.

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Godot Y-up export: Godot +X = Blender +X, Godot +Y = Blender +Z, Godot +Z = Blender -Y.
- Clean 2.0m world-metric cubic box UVs.
- Material slots:
  - catwalk_4m.glb:        ['steel', 'grating']
  - loading_dock_ramp.glb: ['concrete', 'steel', 'rubber']
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

# Catwalk dimensions (meters)
CATWALK_LEN_X = 4.0
CATWALK_WID_Y = 2.0
CATWALK_DECK_H = 0.12
CATWALK_RAIL_Y = 0.95
CATWALK_RAIL_H = 1.05  # Above deck surface (Z=0.12 -> Z=1.17)

# Loading dock & ramp dimensions (meters)
DOCK_WID_X = 4.0
DOCK_Y_START = 0.50   # Godot Z = -0.50
DOCK_Y_END = 3.00     # Godot Z = -3.00 (dock face)
RAMP_Y_END = -3.00    # Godot Z = +3.00 (ground toe)
DOCK_HEIGHT = 1.10


def _add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    bevel_width: float = 0.006,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a scaled cube with applied transform and optional bevel."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.scale = size
    obj.rotation_euler = tuple(math.radians(a) for a in rotation_deg)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel_width > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = 1
        bev.limit_method = "ANGLE"
        bev.angle_limit = math.radians(30.0)
    return obj


def _add_cylinder(
    name: str,
    radius: float,
    depth: float,
    location: tuple[float, float, float],
    vertices: int = 12,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a cylinder with applied rotation/scale."""
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=depth,
        location=location,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.rotation_euler = tuple(math.radians(a) for a in rotation_deg)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj


def _add_strut(
    name: str,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    width_x: float,
    thick_perp: float,
    bevel_width: float = 0.004,
) -> bpy.types.Object:
    """Create a rectangular bar spanning from p0 to p1 aligned with world X laterally."""
    v0 = Vector(p0)
    v1 = Vector(p1)
    diff = v1 - v0
    length = diff.length
    mid = (v0 + v1) * 0.5
    quat = diff.normalized().to_track_quat("Y", "X")

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=tuple(mid))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.scale = (width_x, length, thick_perp)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = quat
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel_width > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = 1
        bev.limit_method = "ANGLE"
        bev.angle_limit = math.radians(30.0)
    return obj


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 2.0) -> None:
    """Generate clean world-metric cubic box UVs so PBR materials tile seamlessly."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data

    inv_tile = 1.0 / tile_meters
    for poly in mesh.polygons:
        nx, ny, nz = abs(poly.normal.x), abs(poly.normal.y), abs(poly.normal.z)
        for loop_idx in poly.loop_indices:
            vert = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            if nx >= ny and nx >= nz:
                u, v = vert.y * inv_tile, vert.z * inv_tile
            elif ny >= nx and ny >= nz:
                u, v = vert.x * inv_tile, vert.z * inv_tile
            else:
                u, v = vert.x * inv_tile, vert.y * inv_tile
            uv_layer[loop_idx].uv = (u, v)


def _create_kit_materials() -> dict[str, bpy.types.Material]:
    """Create material slots matching BellaSDK exterior shell conventions."""
    concrete_mat = create_pbr_material(
        name="concrete",
        base_color=(0.44, 0.43, 0.41, 1.0),
        metallic=0.0,
        roughness=0.88,
    )
    steel_mat = create_pbr_material(
        name="steel",
        base_color=(0.24, 0.16, 0.12, 1.0),
        metallic=0.82,
        roughness=0.62,
    )
    grating_mat = create_pbr_material(
        name="grating",
        base_color=(0.18, 0.19, 0.20, 1.0),
        metallic=0.86,
        roughness=0.52,
    )
    rubber_mat = create_pbr_material(
        name="rubber",
        base_color=(0.055, 0.055, 0.058, 1.0),
        metallic=0.0,
        roughness=0.88,
    )
    return {
        "concrete": concrete_mat,
        "steel": steel_mat,
        "grating": grating_mat,
        "rubber": rubber_mat,
    }


def _finalize_and_export(
    name: str,
    material_groups: list[tuple[bpy.types.Material, list[bpy.types.Object]]],
    output_dir: Path,
) -> dict[str, object]:
    """Apply modifiers, assign materials & 2m box UVs, join into one mesh, and export GLB."""
    all_parts: list[bpy.types.Object] = []
    for mat, parts in material_groups:
        for part in parts:
            bpy.context.view_layer.objects.active = part
            for mod in list(part.modifiers):
                bpy.ops.object.modifier_apply(modifier=mod.name)
            assign_material(part, mat)
            _apply_box_uvs(part, tile_meters=2.0)
            all_parts.append(part)

    bpy.ops.object.select_all(action="DESELECT")
    for part in all_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = all_parts[0]
    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Set smooth shading with sharp edge creases for clean bevels and cylinders
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    thresh_rad = math.radians(35.0)
    for face in bm.faces:
        face.smooth = True
    for edge in bm.edges:
        if len(edge.link_faces) == 2:
            edge.smooth = edge.calc_face_angle(0.0) <= thresh_rad
        else:
            edge.smooth = False
    bm.to_mesh(mesh)
    bm.free()

    tri_count = sum(max(1, len(p.vertices) - 2) for p in mesh.polygons)
    mat_slots = [m.name for m in mesh.materials if m is not None]
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    bbox_blender = (
        round(min(xs), 4),
        round(max(xs), 4),
        round(min(ys), 4),
        round(max(ys), 4),
        round(min(zs), 4),
        round(max(zs), 4),
    )
    # Godot Y-up bbox: (X, Z_as_Y, -Y_as_Z)
    bbox_godot = (
        round(min(xs), 4),
        round(max(xs), 4),
        round(min(zs), 4),
        round(max(zs), 4),
        round(-max(ys), 4),
        round(-min(ys), 4),
    )

    out_path = output_dir / f"{name}.glb"
    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    print(
        f"[{name}] tris={tri_count} slots={mat_slots} "
        f"godot_bbox={bbox_godot} blender_bbox={bbox_blender} path={out_path}"
    )
    return {
        "name": name,
        "path": out_path,
        "tris": tri_count,
        "slots": mat_slots,
        "bbox_godot": bbox_godot,
        "bbox_blender": bbox_blender,
    }


def _build_bmesh_object(name: str, bm: bmesh.types.BMesh) -> bpy.types.Object:
    """Convert a BMesh into a scene Object with recalculated outward normals."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def generate_catwalk_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 2.0m elevated industrial steel catwalk with handrails and grated deck."""
    clean_scene()
    mats = _create_kit_materials()

    steel_parts: list[bpy.types.Object] = []
    grating_parts: list[bpy.types.Object] = []

    half_x = CATWALK_LEN_X * 0.5  # 2.0m
    half_y = CATWALK_WID_Y * 0.5  # 1.0m

    # 1. Structural C-channel side beams along Y = +-1.0 (Z[0.0, 0.12])
    web_t = 0.016
    flange_w = 0.085
    flange_t = 0.018
    for tag, sign in (("Front", -1.0), ("Back", 1.0)):
        # Outer web flush at Y = +-1.0
        steel_parts.append(
            _add_box(
                f"Catwalk_CChannel_Web_{tag}",
                (CATWALK_LEN_X, web_t, CATWALK_DECK_H),
                (0.0, sign * (half_y - web_t * 0.5), CATWALK_DECK_H * 0.5),
                bevel_width=0.002,
            )
        )
        # Bottom flange (Z[0.0, 0.018]) & top flange (Z[0.102, 0.120]) pointing inward
        flange_cy = sign * (half_y - flange_w * 0.5)
        steel_parts.append(
            _add_box(
                f"Catwalk_CChannel_BotFlange_{tag}",
                (CATWALK_LEN_X, flange_w, flange_t),
                (0.0, flange_cy, flange_t * 0.5),
                bevel_width=0.002,
            )
        )
        steel_parts.append(
            _add_box(
                f"Catwalk_CChannel_TopFlange_{tag}",
                (CATWALK_LEN_X, flange_w, flange_t),
                (0.0, flange_cy, CATWALK_DECK_H - flange_t * 0.5),
                bevel_width=0.002,
            )
        )

    # 2. Cross-joists spanning Y[-0.98, 0.98] inside C-channels (Z[0.02, 0.095])
    joist_h = 0.075
    joist_cz = 0.020 + joist_h * 0.5
    joist_xs = (-1.96, -1.30, -0.65, 0.0, 0.65, 1.30, 1.96)
    for idx, jx in enumerate(joist_xs):
        joist_w = 0.055 if idx in (0, 3, 6) else 0.042
        steel_parts.append(
            _add_box(
                f"Catwalk_CrossJoist_{idx}",
                (joist_w, CATWALK_WID_Y - web_t * 2.0, joist_h),
                (jx, 0.0, joist_cz),
                bevel_width=0.002,
            )
        )

    # End splice plates & internal gusset bolts at X = +-1.99
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        for side_tag, sy in (("F", -0.95), ("B", 0.95)):
            steel_parts.append(
                _add_box(
                    f"Catwalk_EndPlate_{tag}_{side_tag}",
                    (0.020, 0.070, CATWALK_DECK_H - flange_t * 2.0),
                    (sign * (half_x - 0.010), sy, CATWALK_DECK_H * 0.5),
                    bevel_width=0.002,
                )
            )

    # 2 longitudinal inner stringer sub-beams supporting the grated deck (Y = +-0.45)
    for tag, sy in (("InnerF", -0.45), ("InnerB", 0.45)):
        steel_parts.append(
            _add_box(
                f"Catwalk_Stringer_{tag}",
                (CATWALK_LEN_X, 0.040, 0.068),
                (0.0, sy, 0.061),
                bevel_width=0.002,
            )
        )

    # 3. Raised ribbed/grated deck (Z[0.095, 0.120], Y[-0.915, 0.915])
    grate_y_half = half_y - flange_w  # 0.915m
    grate_z_min = 0.095
    grate_z_max = CATWALK_DECK_H  # 0.120m
    grate_h = grate_z_max - grate_z_min
    grate_cz = grate_z_min + grate_h * 0.5

    # Perimeter grating binding bars
    for tag, sy in (("F", -grate_y_half + 0.008), ("B", grate_y_half - 0.008)):
        grating_parts.append(
            _add_box(
                f"Catwalk_Grate_SideTrim_{tag}",
                (CATWALK_LEN_X, 0.016, grate_h),
                (0.0, sy, grate_cz),
                bevel_width=0.0,
            )
        )
    for tag, sx in (("L", -half_x + 0.008), ("R", half_x - 0.008)):
        grating_parts.append(
            _add_box(
                f"Catwalk_Grate_EndTrim_{tag}",
                (0.016, grate_y_half * 2.0 - 0.032, grate_h),
                (sx, 0.0, grate_cz),
                bevel_width=0.0,
            )
        )

    # 17 longitudinal ribbed bearing bars across Y[-0.80, +0.80]
    n_long_bars = 17
    for i in range(n_long_bars):
        by = -0.80 + (1.60 * i) / float(n_long_bars - 1)
        grating_parts.append(
            _add_box(
                f"Catwalk_Grate_LongBar_{i}",
                (CATWALK_LEN_X - 0.032, 0.012, grate_h),
                (0.0, by, grate_cz),
                bevel_width=0.0,
            )
        )

    # 31 transverse cross-rods spanning between the C-channels
    n_cross_bars = 31
    for i in range(n_cross_bars):
        bx = -1.875 + (3.75 * i) / float(n_cross_bars - 1)
        grating_parts.append(
            _add_box(
                f"Catwalk_Grate_CrossBar_{i}",
                (0.010, grate_y_half * 2.0 - 0.032, 0.016),
                (bx, 0.0, grate_z_max - 0.010),
                bevel_width=0.0,
            )
        )

    # 4. Tubular steel handrails (1.05m above deck -> Z[0.12, 1.17]), mid-rails, toe-kick plates
    deck_top = CATWALK_DECK_H  # 0.12m
    rail_top_z = deck_top + CATWALK_RAIL_H  # 1.17m
    top_rail_r = 0.020
    collar_r = 0.024
    top_rail_cz = rail_top_z - collar_r  # Top collar surface flush at Z=1.17m
    mid_rail_r = 0.015
    mid_rail_cz = deck_top + CATWALK_RAIL_H * 0.5  # 0.645m
    post_r = 0.018
    post_xs = (-1.94, -0.97, 0.0, 0.97, 1.94)

    for tag, sign in (("F", -1.0), ("B", 1.0)):
        ry = sign * CATWALK_RAIL_Y

        # Toe-kick plate (Z[0.12, 0.24])
        kick_h = 0.12
        steel_parts.append(
            _add_box(
                f"Catwalk_ToeKick_{tag}",
                (CATWALK_LEN_X, 0.012, kick_h),
                (0.0, ry, deck_top + kick_h * 0.5),
                bevel_width=0.002,
            )
        )

        # Top tubular handrail
        steel_parts.append(
            _add_cylinder(
                f"Catwalk_TopRail_{tag}",
                radius=top_rail_r,
                depth=CATWALK_LEN_X,
                location=(0.0, ry, top_rail_cz),
                vertices=12,
                rotation_deg=(0.0, 90.0, 0.0),
            )
        )

        # Mid tubular handrail
        steel_parts.append(
            _add_cylinder(
                f"Catwalk_MidRail_{tag}",
                radius=mid_rail_r,
                depth=CATWALK_LEN_X,
                location=(0.0, ry, mid_rail_cz),
                vertices=10,
                rotation_deg=(0.0, 90.0, 0.0),
            )
        )

        # Vertical tubular stanchion posts + base mounting plates + T-collars
        post_h = top_rail_cz - deck_top
        post_cz = deck_top + post_h * 0.5
        for p_idx, px in enumerate(post_xs):
            steel_parts.append(
                _add_cylinder(
                    f"Catwalk_Post_{tag}_{p_idx}",
                    radius=post_r,
                    depth=post_h,
                    location=(px, ry, post_cz),
                    vertices=10,
                )
            )
            # Welded mounting baseplate on C-channel top flange
            steel_parts.append(
                _add_box(
                    f"Catwalk_PostBase_{tag}_{p_idx}",
                    (0.075, 0.075, 0.012),
                    (px, ry, deck_top + 0.006),
                    bevel_width=0.002,
                )
            )
            # Top elbow/T-collar sleeve
            steel_parts.append(
                _add_cylinder(
                    f"Catwalk_PostTopCollar_{tag}_{p_idx}",
                    radius=collar_r,
                    depth=0.065,
                    location=(px, ry, top_rail_cz),
                    vertices=10,
                    rotation_deg=(0.0, 90.0, 0.0),
                )
            )

    return _finalize_and_export(
        "catwalk_4m",
        [
            (mats["steel"], steel_parts),
            (mats["grating"], grating_parts),
        ],
        output_dir,
    )


def _build_dock_ramp_monolith_bmesh() -> bmesh.types.BMesh:
    """Build solid concrete dock platform (Y[0.5, 3.0], Z[0, 1.10]) + ramp (Y[-3.0, 0.5])."""
    bm = bmesh.new()
    half_x = DOCK_WID_X * 0.5  # 2.0m
    toe_h = 0.025
    chamfer = 0.015

    # Extrude 2D YZ side profile across X[-half_x, +half_x]
    # Profile loops counter-clockwise in YZ plane:
    # bottom-front (-3.0, 0) -> bottom-rear (3.0, 0) -> dock rear top (3.0, 1.10) ->
    # dock crest (0.5, 1.10) -> ramp toe top (-3.0, 0.025)
    profile_yz = [
        (RAMP_Y_END, 0.0),
        (DOCK_Y_END, 0.0),
        (DOCK_Y_END, DOCK_HEIGHT),
        (DOCK_Y_START, DOCK_HEIGHT),
        (RAMP_Y_END, toe_h),
    ]
    n_pts = len(profile_yz)
    left_verts = [bm.verts.new((-half_x, py, pz)) for py, pz in profile_yz]
    right_verts = [bm.verts.new((half_x, py, pz)) for py, pz in profile_yz]

    bm.faces.new(list(reversed(left_verts)))
    bm.faces.new(right_verts)
    for i in range(n_pts):
        j = (i + 1) % n_pts
        bm.faces.new((left_verts[i], left_verts[j], right_verts[j], right_verts[i]))

    # Subtle concrete expansion ribs / traction cleats along the sloped ramp surface
    # Keeps overall silhouette true while giving crisp industrial surface relief
    ramp_len_y = DOCK_Y_START - RAMP_Y_END  # 3.5m
    ramp_rise = DOCK_HEIGHT - toe_h        # 1.075m
    ramp_slope_len = math.hypot(ramp_len_y, ramp_rise)
    slope_angle = math.atan2(ramp_rise, ramp_len_y)

    # Add poured concrete side edge haunch strips (chamfered curb bases) on X = +-1.92
    for sign in (-1.0, 1.0):
        cx = sign * (half_x - 0.08)
        # Dock platform curb base (Y[0.5, 3.0], Z[1.10, 1.13])
        bmesh.ops.create_cube(
            bm,
            size=1.0,
            matrix=(
                Matrix.Translation((cx, (DOCK_Y_START + DOCK_Y_END) * 0.5, DOCK_HEIGHT + 0.015))
                @ Matrix.Diagonal((0.16, DOCK_Y_END - DOCK_Y_START, 0.03, 1.0))
            ),
        )
        # Ramp edge curb base sloping along ramp (inset 0.02m at toe so Y stays >= -3.0)
        curb_ramp_start = RAMP_Y_END + 0.02
        curb_ramp_len_y = DOCK_Y_START - curb_ramp_start
        curb_ramp_rise = (curb_ramp_len_y / ramp_len_y) * ramp_rise
        curb_slope_len = math.hypot(curb_ramp_len_y, curb_ramp_rise)
        curb_z_start = DOCK_HEIGHT - curb_ramp_rise
        mid_y = (curb_ramp_start + DOCK_Y_START) * 0.5
        mid_z = (curb_z_start + DOCK_HEIGHT) * 0.5 + 0.015
        rot_x = Matrix.Rotation(slope_angle, 4, "X")
        bmesh.ops.create_cube(
            bm,
            size=1.0,
            matrix=(
                Matrix.Translation((cx, mid_y, mid_z))
                @ rot_x
                @ Matrix.Diagonal((0.16, curb_slope_len, 0.03, 1.0))
            ),
        )

    # Subtle top expansion joint plates on dock platform (2m x 1.25m bays)
    # Recessed 8mm joint strips simulated via twin 10mm raised slab caps
    bay_h = 0.012
    joint = 0.008
    for x0, x1 in ((-half_x + chamfer, -joint), (joint, half_x - chamfer)):
        for y0, y1 in ((DOCK_Y_START + joint, 1.75 - joint), (1.75 + joint, DOCK_Y_END - 0.04)):
            bx = (x0 + x1) * 0.5
            by = (y0 + y1) * 0.5
            bmesh.ops.create_cube(
                bm,
                size=1.0,
                matrix=(
                    Matrix.Translation((bx, by, DOCK_HEIGHT + bay_h * 0.5))
                    @ Matrix.Diagonal((x1 - x0, y1 - y0, bay_h, 1.0))
                ),
            )

    return bm


def generate_loading_dock_ramp(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 6.0m concrete loading dock + sloped ramp with steel curb rails & rubber bumpers."""
    clean_scene()
    mats = _create_kit_materials()

    half_x = DOCK_WID_X * 0.5  # 2.0m
    toe_h = 0.025

    # 1. Concrete dock & ramp monolith
    concrete_parts: list[bpy.types.Object] = [
        _build_bmesh_object("Dock_Concrete_Monolith", _build_dock_ramp_monolith_bmesh())
    ]

    # 2. Steel curb rails, transition plates, dock-edge angle iron & bumper backing plates
    steel_parts: list[bpy.types.Object] = []

    # Rear dock-edge steel angle coping at Y=3.0 (Godot Z=-3.0), Z=1.10
    steel_parts.append(
        _add_box(
            "Dock_RearEdge_AngleTop",
            (DOCK_WID_X, 0.09, 0.022),
            (0.0, DOCK_Y_END - 0.045, DOCK_HEIGHT + 0.011),
            bevel_width=0.003,
        )
    )
    steel_parts.append(
        _add_box(
            "Dock_RearEdge_AngleFace",
            (DOCK_WID_X, 0.022, 0.12),
            (0.0, DOCK_Y_END - 0.011, DOCK_HEIGHT - 0.049),
            bevel_width=0.003,
        )
    )

    # Steel crest transition tread plate at ramp/dock hinge (Y=0.50, Z=1.10)
    steel_parts.append(
        _add_box(
            "Dock_Crest_TreadPlate",
            (DOCK_WID_X - 0.34, 0.18, 0.014),
            (0.0, DOCK_Y_START, DOCK_HEIGHT + 0.007),
            bevel_width=0.003,
        )
    )

    # Steel curb rails along both X = +-1.92 edges (platform + sloped ramp)
    curb_x = half_x - 0.08  # 1.92m -> outer edge 1.97m
    curb_w = 0.09
    curb_h = 0.09
    curb_clearance = 0.06  # Riser height above concrete curb pad

    def _ramp_z(y_val: float) -> float:
        t = (y_val - RAMP_Y_END) / (DOCK_Y_START - RAMP_Y_END)
        return toe_h + t * (DOCK_HEIGHT - toe_h)

    for tag, sign in (("L", -1.0), ("R", 1.0)):
        cx = sign * curb_x

        # Platform horizontal steel curb rail (Y[0.50, 2.96])
        plat_rail_z = DOCK_HEIGHT + 0.03 + curb_clearance + curb_h * 0.5  # 1.235m
        steel_parts.append(
            _add_box(
                f"Dock_CurbRail_Plat_{tag}",
                (curb_w, DOCK_Y_END - DOCK_Y_START - 0.04, curb_h),
                (cx, (DOCK_Y_START + DOCK_Y_END - 0.04) * 0.5, plat_rail_z),
                bevel_width=0.005,
            )
        )
        # Platform riser stanchion blocks
        for ry in (0.58, 1.75, 2.90):
            steel_parts.append(
                _add_box(
                    f"Dock_CurbRiser_Plat_{tag}",
                    (0.065, 0.085, curb_clearance + 0.02),
                    (cx, ry, DOCK_HEIGHT + 0.03 + curb_clearance * 0.5),
                    bevel_width=0.003,
                )
            )

        # Sloped ramp steel curb rail (Y[-2.94, 0.50])
        rail_y0 = RAMP_Y_END + 0.06
        rail_y1 = DOCK_Y_START
        rail_z0 = _ramp_z(rail_y0) + 0.03 + curb_clearance + curb_h * 0.5
        rail_z1 = plat_rail_z
        steel_parts.append(
            _add_strut(
                f"Dock_CurbRail_Ramp_{tag}",
                (cx, rail_y0, rail_z0),
                (cx, rail_y1, rail_z1),
                width_x=curb_w,
                thick_perp=curb_h,
                bevel_width=0.005,
            )
        )
        # Ramp curb sloped down-turn end cap at toe
        steel_parts.append(
            _add_box(
                f"Dock_CurbEndCap_{tag}",
                (curb_w, 0.08, curb_clearance + curb_h),
                (cx, rail_y0, _ramp_z(rail_y0) + 0.03 + (curb_clearance + curb_h) * 0.5),
                bevel_width=0.005,
            )
        )
        # Ramp riser stanchion blocks along slope
        for ry in (-2.05, -1.15, -0.25):
            rz_base = _ramp_z(ry) + 0.025
            steel_parts.append(
                _add_box(
                    f"Dock_CurbRiser_Ramp_{tag}",
                    (0.065, 0.085, curb_clearance + 0.04),
                    (cx, ry, rz_base + (curb_clearance + 0.02) * 0.5),
                    bevel_width=0.003,
                )
            )

    # 3. 2 heavy black rubber dock bumpers on dock face (Blender Y = +3.0 -> Godot Z = -3.0)
    rubber_parts: list[bpy.types.Object] = []
    bumper_xs = (-1.18, 1.18)
    bumper_cz = 0.84  # Upper half of 1.10m dock face (Z[0.62, 1.06])
    plate_w = 0.56
    plate_h = 0.48
    plate_t = 0.018

    for idx, bx in enumerate(bumper_xs):
        # Steel backing mount plate bolted to concrete dock face
        steel_parts.append(
            _add_box(
                f"Dock_BumperMount_{idx}",
                (plate_w, plate_t, plate_h),
                (bx, DOCK_Y_END + plate_t * 0.5, bumper_cz),
                bevel_width=0.003,
            )
        )
        # 4 corner anchor bolts on steel backing plate
        for b_sx in (-0.23, 0.23):
            for b_sz in (-0.19, 0.19):
                steel_parts.append(
                    _add_cylinder(
                        f"Dock_BumperBolt_{idx}",
                        radius=0.012,
                        depth=0.024,
                        location=(bx + b_sx, DOCK_Y_END + plate_t + 0.008, bumper_cz + b_sz),
                        vertices=6,
                        rotation_deg=(90.0, 0.0, 0.0),
                    )
                )

        # Heavy laminated black rubber bumper block (3 vertical molded ribs)
        base_rub_t = 0.045
        base_rub_y = DOCK_Y_END + plate_t + base_rub_t * 0.5
        rubber_parts.append(
            _add_box(
                f"Dock_RubberBumper_Base_{idx}",
                (0.46, base_rub_t, 0.42),
                (bx, base_rub_y, bumper_cz),
                bevel_width=0.008,
            )
        )
        rib_t = 0.042
        rib_y = DOCK_Y_END + plate_t + base_rub_t + rib_t * 0.5 - 0.004
        for r_idx, rx_off in enumerate((-0.145, 0.0, 0.145)):
            rubber_parts.append(
                _add_box(
                    f"Dock_RubberBumper_Rib_{idx}_{r_idx}",
                    (0.125, rib_t, 0.40),
                    (bx + rx_off, rib_y, bumper_cz),
                    bevel_width=0.010,
                )
            )

    return _finalize_and_export(
        "loading_dock_ramp",
        [
            (mats["concrete"], concrete_parts),
            (mats["steel"], steel_parts),
            (mats["rubber"], rubber_parts),
        ],
        output_dir,
    )


def main() -> None:
    """Entry point for direct blender --background --python execution."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "factory_shells"
        generate_catwalk_4m(output_dir)
        generate_loading_dock_ramp(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
