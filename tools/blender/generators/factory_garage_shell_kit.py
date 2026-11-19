"""Procedural Blender generator for modular post-apocalyptic factory garage & roof shell GLBs.

Generates 4 modular shell GLBs in assets/models/factory_shells/:
1. factory_roof_4m.glb         - 4.0m x 4.0m corrugated roof deck with underside Warren trusses & purlins.
2. garage_shutter_4m.glb       - 4.0m x 4.0m x 0.35m bay wall with closed 3.0m x 3.1m rolling shutter.
3. garage_shutter_open_4m.glb  - Same 4.0m bay with shutter rolled up (3.0m x 3.1m clear opening).
4. factory_pillar_4m.glb       - 0.45m concrete pedestal base (0..0.8m) + steel H-beam column (0.8..4.0m).

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Clean world-metric UVs (2.0m tile).
- Separate material slots ('concrete', 'steel', 'corrugated_metal') for Godot ORM assignment.
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

# Shared modular dimensions (meters) matching factory_wall_kit.py
WALL_WIDTH = 4.0
WALL_HEIGHT = 4.0
WALL_THICK = 0.35
PANEL_RECESS_THICK = 0.29
PILASTER_WIDTH = 0.22

PLINTH_HEIGHT = 0.45
BEAM_HEIGHT = 0.24
BEAM_Z_MIN = WALL_HEIGHT - BEAM_HEIGHT  # 3.76m

# Garage shutter opening dimensions (clear opening 3.0m x 3.1m)
GARAGE_CLEAR_W = 3.0
GARAGE_CLEAR_H = 3.1
JAMB_WIDTH = 0.08
DRUM_BOX_H = 0.48

# Roof dimensions
ROOF_SIZE = 4.0
TRUSS_TOP_Z = 0.45
ROOF_TOP_Z = 0.55

# Pillar dimensions
PILLAR_BASE_SIZE = 0.45
PILLAR_BASE_H = 0.80
PILLAR_HEIGHT = 4.00


def _add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    bevel_width: float = 0.008,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a scaled cube with applied transform and optional bevel."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
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


def _add_strut(
    name: str,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    width_y: float,
    thick_perp: float,
    bevel_width: float = 0.002,
) -> bpy.types.Object:
    """Create a rectangular steel strut spanning from p0 to p1."""
    v0 = Vector(p0)
    v1 = Vector(p1)
    diff = v1 - v0
    length = diff.length
    mid = (v0 + v1) * 0.5
    quat = diff.normalized().to_track_quat("X", "Z")

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=tuple(mid))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (length, width_y, thick_perp)
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
    obj.rotation_euler = tuple(math.radians(a) for a in rotation_deg)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
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


def _apply_planar_uvs(
    obj: bpy.types.Object,
    plane: str,
    tile_meters: float = 2.0,
) -> None:
    """Generate continuous planar UVs ('XY' for roof deck, 'XZ' for shutter slats)."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data

    inv_tile = 1.0 / tile_meters
    for poly in mesh.polygons:
        for loop_idx in poly.loop_indices:
            vert = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            if plane == "XY":
                if abs(poly.normal.y) > 0.85:
                    u, v = vert.x * inv_tile, vert.z * inv_tile
                else:
                    u, v = vert.x * inv_tile, vert.y * inv_tile
            else:  # "XZ"
                if abs(poly.normal.x) > 0.85:
                    u, v = vert.y * inv_tile, vert.z * inv_tile
                else:
                    u, v = vert.x * inv_tile, vert.z * inv_tile
            uv_layer[loop_idx].uv = (u, v)


def _create_kit_materials() -> dict[str, bpy.types.Material]:
    """Create material slots matching BellaSDK factory shell conventions."""
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
    corrugated_mat = create_pbr_material(
        name="corrugated_metal",
        base_color=(0.30, 0.25, 0.22, 1.0),
        metallic=0.75,
        roughness=0.58,
    )
    return {
        "concrete": concrete_mat,
        "steel": steel_mat,
        "corrugated_metal": corrugated_mat,
    }


def _finalize_and_export(
    name: str,
    material_groups: list[tuple[bpy.types.Material, list[bpy.types.Object], str]],
    output_dir: Path,
) -> dict[str, object]:
    """Apply modifiers, assign materials & UVs, join into one mesh, and export GLB."""
    all_parts: list[bpy.types.Object] = []
    for mat, parts, uv_mode in material_groups:
        for part in parts:
            bpy.context.view_layer.objects.active = part
            for mod in list(part.modifiers):
                bpy.ops.object.modifier_apply(modifier=mod.name)
            assign_material(part, mat)
            if uv_mode == "XY":
                _apply_planar_uvs(part, "XY", tile_meters=2.0)
            elif uv_mode == "XZ":
                _apply_planar_uvs(part, "XZ", tile_meters=2.0)
            else:
                _apply_box_uvs(part, tile_meters=2.0)
            all_parts.append(part)

    bpy.ops.object.select_all(action="DESELECT")
    for part in all_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = all_parts[0]
    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
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
        f"[{name}] tris={tri_count} godot_bbox={bbox_godot} "
        f"blender_bbox={bbox_blender} path={out_path}"
    )
    return {
        "name": name,
        "path": out_path,
        "tris": tri_count,
        "bbox_godot": bbox_godot,
        "bbox_blender": bbox_blender,
    }


def _build_top_steel_beam(prefix: str) -> list[bpy.types.Object]:
    """Build the shared 4.0m top steel I-beam lip matching factory_wall_kit.py."""
    parts: list[bpy.types.Object] = []
    flange_h = 0.035
    web_h = BEAM_HEIGHT - 2.0 * flange_h
    web_thick = 0.14

    parts.append(
        _add_box(
            f"{prefix}_Beam_BotFlange",
            (WALL_WIDTH, WALL_THICK, flange_h),
            (0.0, 0.0, BEAM_Z_MIN + flange_h * 0.5),
            bevel_width=0.005,
        )
    )
    parts.append(
        _add_box(
            f"{prefix}_Beam_Web",
            (WALL_WIDTH, web_thick, web_h),
            (0.0, 0.0, BEAM_Z_MIN + flange_h + web_h * 0.5),
            bevel_width=0.0,
        )
    )
    parts.append(
        _add_box(
            f"{prefix}_Beam_TopFlange",
            (WALL_WIDTH, WALL_THICK, flange_h),
            (0.0, 0.0, WALL_HEIGHT - flange_h * 0.5),
            bevel_width=0.005,
        )
    )

    gusset_thick = 0.025
    gusset_depth = (WALL_THICK - web_thick) * 0.5 - 0.005
    gusset_z = BEAM_Z_MIN + flange_h + web_h * 0.5
    for gx in (-1.5, -0.5, 0.5, 1.5):
        for side in (-1.0, 1.0):
            parts.append(
                _add_box(
                    f"{prefix}_Beam_Gusset",
                    (gusset_thick, gusset_depth, web_h),
                    (gx, side * (web_thick * 0.5 + gusset_depth * 0.5), gusset_z),
                    bevel_width=0.003,
                )
            )
    return parts


def _build_corrugated_roof_deck(
    name: str,
    width_x: float = ROOF_SIZE,
    depth_y: float = ROOF_SIZE,
    z_min: float = TRUSS_TOP_Z,
    z_max: float = ROOF_TOP_Z,
    waves: int = 16,
) -> bpy.types.Object:
    """Build a solid manifold trapezoidal corrugated roof sheet spanning X/Y and Z[z_min, z_max]."""
    sheet_t = 0.016
    wave_pitch = width_x / float(waves)
    half_x = width_x * 0.5
    half_y = depth_y * 0.5
    z_low_bot = z_min
    z_high_bot = z_max - sheet_t

    # Build 2D cross-section points (x, z_bot) across X[-half_x, +half_x]
    # Symmetric trapezoidal profile per wave, starting and ending at flat valley for clean tiling
    profile_xz: list[tuple[float, float]] = []
    for i in range(waves):
        x0 = -half_x + i * wave_pitch
        pts = [
            (x0 + 0.00 * wave_pitch, z_low_bot),
            (x0 + 0.16 * wave_pitch, z_low_bot),
            (x0 + 0.34 * wave_pitch, z_high_bot),
            (x0 + 0.66 * wave_pitch, z_high_bot),
            (x0 + 0.84 * wave_pitch, z_low_bot),
        ]
        profile_xz.extend(pts)
    profile_xz.append((half_x, z_low_bot))

    bm = bmesh.new()
    n_pts = len(profile_xz)

    # Create front (Y=-half_y) and back (Y=+half_y) vertex rings (bottom then top)
    bot_front = [bm.verts.new((px, -half_y, pz)) for px, pz in profile_xz]
    top_front = [bm.verts.new((px, -half_y, pz + sheet_t)) for px, pz in profile_xz]
    bot_back = [bm.verts.new((px, half_y, pz)) for px, pz in profile_xz]
    top_back = [bm.verts.new((px, half_y, pz + sheet_t)) for px, pz in profile_xz]

    for i in range(n_pts - 1):
        # Top skin
        bm.faces.new((top_front[i], top_front[i + 1], top_back[i + 1], top_back[i]))
        # Bottom skin
        bm.faces.new((bot_front[i + 1], bot_front[i], bot_back[i], bot_back[i + 1]))
        # Front edge cap (Y=-half_y)
        bm.faces.new((bot_front[i], bot_front[i + 1], top_front[i + 1], top_front[i]))
        # Back edge cap (Y=+half_y)
        bm.faces.new((bot_back[i + 1], bot_back[i], top_back[i], top_back[i + 1]))

    # Left & right edge caps (X=-half_x and X=+half_x)
    bm.faces.new((bot_back[0], bot_front[0], top_front[0], top_back[0]))
    bm.faces.new((bot_front[-1], bot_back[-1], top_back[-1], top_front[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def generate_factory_roof_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 4.0m corrugated roof deck (Z[0.45, 0.55]) with steel trusses & purlins (Z[0, 0.45])."""
    clean_scene()
    mats = _create_kit_materials()

    steel_parts: list[bpy.types.Object] = []

    # Two primary Warren trusses along X at Y = -1.25 and Y = +1.25
    chord_h = 0.045
    chord_w = 0.08
    bot_chord_z = chord_h * 0.5  # 0.0225 -> bottom at Z=0.0
    top_chord_z = 0.355  # top chord Z[0.3325, 0.3775]
    truss_ys = (-1.25, 1.25)

    for tag, ty in (("Front", truss_ys[0]), ("Back", truss_ys[1])):
        # Bottom and top chords
        steel_parts.append(
            _add_box(
                f"Roof_Truss_{tag}_BotChord",
                (ROOF_SIZE, chord_w, chord_h),
                (0.0, ty, bot_chord_z),
                bevel_width=0.003,
            )
        )
        steel_parts.append(
            _add_box(
                f"Roof_Truss_{tag}_TopChord",
                (ROOF_SIZE, chord_w, chord_h),
                (0.0, ty, top_chord_z),
                bevel_width=0.003,
            )
        )
        # End verticals + mid vertical strut
        for vx, vw in ((-1.965, 0.07), (0.0, 0.05), (1.965, 0.07)):
            steel_parts.append(
                _add_box(
                    f"Roof_Truss_{tag}_Vert",
                    (vw, 0.065, top_chord_z + chord_h * 0.5),
                    (vx, ty, (top_chord_z + chord_h * 0.5) * 0.5),
                    bevel_width=0.002,
                )
            )
        # Warren diagonal web members across 6 bays (-1.95 -> +1.95)
        nodes_x = [-1.95, -1.30, -0.65, 0.0, 0.65, 1.30, 1.95]
        for idx in range(len(nodes_x) - 1):
            x_a = nodes_x[idx]
            x_b = nodes_x[idx + 1]
            z_a = bot_chord_z if idx % 2 == 0 else top_chord_z
            z_b = top_chord_z if idx % 2 == 0 else bot_chord_z
            steel_parts.append(
                _add_strut(
                    f"Roof_Truss_{tag}_Diag_{idx}",
                    (x_a, ty, z_a),
                    (x_b, ty, z_b),
                    width_y=0.048,
                    thick_perp=0.048,
                    bevel_width=0.002,
                )
            )

    # Secondary transverse tie beams at bottom chord level connecting the two trusses
    for tx in (-1.96, 0.0, 1.96):
        steel_parts.append(
            _add_box(
                "Roof_TieBeam",
                (0.06, 2.50, 0.045),
                (tx, 0.0, bot_chord_z),
                bevel_width=0.002,
            )
        )

    # Purlins spanning Y[-2.0, 2.0] on top of truss top chords (Z[0.3775, 0.45])
    purlin_z_bot = top_chord_z + chord_h * 0.5  # 0.3775
    purlin_h = TRUSS_TOP_Z - purlin_z_bot  # 0.0725
    purlin_cz = purlin_z_bot + purlin_h * 0.5
    for px in (-1.96, -0.98, 0.0, 0.98, 1.96):
        steel_parts.append(
            _add_box(
                "Roof_Purlin",
                (0.065, ROOF_SIZE, purlin_h),
                (px, 0.0, purlin_cz),
                bevel_width=0.003,
            )
        )

    # Perimeter eave fascia angles along Y = ±1.965 (Z[0.3775, 0.45])
    for ey in (-1.965, 1.965):
        steel_parts.append(
            _add_box(
                "Roof_Eave_Beam",
                (ROOF_SIZE - 0.13, 0.07, purlin_h),
                (0.0, ey, purlin_cz),
                bevel_width=0.003,
            )
        )

    corrugated_parts = [_build_corrugated_roof_deck("Roof_Corrugated_Deck")]

    return _finalize_and_export(
        "factory_roof_4m",
        [
            (mats["steel"], steel_parts, "BOX"),
            (mats["corrugated_metal"], corrugated_parts, "XY"),
        ],
        output_dir,
    )


def _build_shutter_curtain(
    name: str,
    width_x: float,
    z_min: float,
    z_max: float,
    slat_count: int = 28,
) -> bpy.types.Object:
    """Build a ribbed horizontal rolling shutter curtain with continuous interlocking slat profiles."""
    bm = bmesh.new()
    half_x = width_x * 0.5
    slat_h = (z_max - z_min) / float(slat_count)
    y_back = -0.022
    y_front_flat = 0.012
    y_front_rib = 0.032

    # Build continuous vertical profile of interlocking ribbed slats
    profile_yz: list[tuple[float, float]] = []
    for i in range(slat_count):
        z0 = z_min + i * slat_h
        z1 = z0 + 0.18 * slat_h
        z2 = z0 + 0.45 * slat_h
        z3 = z0 + 0.72 * slat_h
        z4 = z0 + 0.92 * slat_h
        profile_yz.extend(
            [
                (y_front_flat, z0),
                (y_front_rib, z1),
                (y_front_rib, z2),
                (y_front_flat, z3),
                (y_front_flat, z4),
            ]
        )
    profile_yz.append((y_front_flat, z_max))

    front_left = [bm.verts.new((-half_x, py, pz)) for py, pz in profile_yz]
    front_right = [bm.verts.new((half_x, py, pz)) for py, pz in profile_yz]
    back_left = [bm.verts.new((-half_x, y_back, pz)) for _, pz in profile_yz]
    back_right = [bm.verts.new((half_x, y_back, pz)) for _, pz in profile_yz]

    n_pts = len(profile_yz)
    for i in range(n_pts - 1):
        bm.faces.new((front_left[i], front_right[i], front_right[i + 1], front_left[i + 1]))
        bm.faces.new((back_right[i], back_left[i], back_left[i + 1], back_right[i + 1]))
        bm.faces.new((back_left[i], front_left[i], front_left[i + 1], back_left[i + 1]))
        bm.faces.new((front_right[i], back_right[i], back_right[i + 1], front_right[i + 1]))

    # Bottom and top caps
    bm.faces.new((back_left[0], back_right[0], front_right[0], front_left[0]))
    bm.faces.new((front_left[-1], front_right[-1], back_right[-1], back_left[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _build_garage_bay_shell(
    name: str,
    is_open: bool,
    output_dir: Path,
) -> dict[str, object]:
    """Build 4.0m x 4.0m x 0.35m concrete garage bay with 3.0m x 3.1m rolling shutter (open or closed)."""
    clean_scene()
    mats = _create_kit_materials()

    half_clear_w = GARAGE_CLEAR_W * 0.5  # 1.50m
    jamb_outer_x = half_clear_w + JAMB_WIDTH  # 1.58m
    pier_total_w = WALL_WIDTH * 0.5 - jamb_outer_x  # 0.42m
    inner_pier_w = pier_total_w - PILASTER_WIDTH  # 0.20m
    pier_cx = jamb_outer_x + pier_total_w * 0.5  # 1.79m
    inner_pier_cx = jamb_outer_x + inner_pier_w * 0.5  # 1.68m

    concrete_parts: list[bpy.types.Object] = []
    upper_h = BEAM_Z_MIN - PLINTH_HEIGHT
    upper_z = PLINTH_HEIGHT + upper_h * 0.5

    for tag, sign in (("L", -1.0), ("R", 1.0)):
        concrete_parts.append(
            _add_box(
                f"Bay_Plinth_{tag}",
                (pier_total_w, WALL_THICK, PLINTH_HEIGHT),
                (sign * pier_cx, 0.0, PLINTH_HEIGHT * 0.5),
                bevel_width=0.010,
            )
        )
        concrete_parts.append(
            _add_box(
                f"Bay_Pilaster_{tag}",
                (PILASTER_WIDTH, WALL_THICK, upper_h),
                (sign * (WALL_WIDTH * 0.5 - PILASTER_WIDTH * 0.5), 0.0, upper_z),
                bevel_width=0.008,
            )
        )
        concrete_parts.append(
            _add_box(
                f"Bay_InnerPier_{tag}",
                (inner_pier_w, PANEL_RECESS_THICK, upper_h),
                (sign * inner_pier_cx, 0.0, upper_z),
                bevel_width=0.006,
            )
        )

    # Concrete header above doorway (Z[3.22, 3.76])
    lintel_top_z = GARAGE_CLEAR_H + 0.12  # 3.22m
    header_h = BEAM_Z_MIN - lintel_top_z
    concrete_parts.append(
        _add_box(
            "Bay_Header_Concrete",
            (jamb_outer_x * 2.0, PANEL_RECESS_THICK, header_h),
            (0.0, 0.0, lintel_top_z + header_h * 0.5),
            bevel_width=0.006,
        )
    )

    steel_parts = _build_top_steel_beam("Bay")

    # Steel jamb frames & U-channel guide tracks (clear opening X[-1.50, 1.50], Z[0.0, 3.10])
    track_depth = WALL_THICK
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        # Main steel jamb column
        steel_parts.append(
            _add_box(
                f"Bay_Jamb_{tag}",
                (JAMB_WIDTH, track_depth, GARAGE_CLEAR_H),
                (sign * (half_clear_w + JAMB_WIDTH * 0.5), 0.0, GARAGE_CLEAR_H * 0.5),
                bevel_width=0.005,
            )
        )
        # Front & rear guide-rail lips flanking the shutter channel
        for side_tag, y_off in (("F", 0.068), ("B", -0.068)):
            steel_parts.append(
                _add_box(
                    f"Bay_GuideLip_{tag}_{side_tag}",
                    (0.032, 0.028, GARAGE_CLEAR_H),
                    (sign * (half_clear_w + 0.016), y_off, GARAGE_CLEAR_H * 0.5),
                    bevel_width=0.002,
                )
            )

    # Steel lintel angle beams (front & back of shutter slot, keeping throat open for shutter)
    for side_tag, y_off in (("F", 0.115), ("B", -0.115)):
        steel_parts.append(
            _add_box(
                f"Bay_Lintel_{side_tag}",
                (GARAGE_CLEAR_W + 0.28, 0.13, 0.12),
                (0.0, y_off, GARAGE_CLEAR_H + 0.06),
                bevel_width=0.005,
            )
        )

    # Top shutter drum housing hood (Z[3.22, 3.70]) + bolted end plates
    drum_z_min = lintel_top_z
    drum_cz = drum_z_min + DRUM_BOX_H * 0.5
    drum_w = GARAGE_CLEAR_W + 0.24
    drum_d = WALL_THICK + 0.12  # 0.47m
    # Front and rear hood panels + top cap leaving bottom throat open at Z=3.22
    for side_tag, y_off in (("F", drum_d * 0.5 - 0.035), ("B", -drum_d * 0.5 + 0.035)):
        steel_parts.append(
            _add_box(
                f"Bay_DrumHood_{side_tag}",
                (drum_w, 0.07, DRUM_BOX_H),
                (0.0, y_off, drum_cz),
                bevel_width=0.010,
            )
        )
    steel_parts.append(
        _add_box(
            "Bay_DrumHood_Top",
            (drum_w, drum_d, 0.06),
            (0.0, 0.0, drum_z_min + DRUM_BOX_H - 0.03),
            bevel_width=0.008,
        )
    )
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Bay_DrumEndPlate_{tag}",
                (0.05, drum_d + 0.02, DRUM_BOX_H + 0.04),
                (sign * (drum_w * 0.5 - 0.01), 0.0, drum_cz),
                bevel_width=0.006,
            )
        )

    corrugated_parts: list[bpy.types.Object] = []
    if is_open:
        # Coiled shutter drum inside housing throat + bottom slat strip above Z=3.10 clear opening
        corrugated_parts.append(
            _add_cylinder(
                "Bay_Shutter_RolledCoil",
                radius=0.145,
                depth=GARAGE_CLEAR_W + 0.04,
                location=(0.0, 0.0, drum_z_min + 0.15),
                vertices=18,
                rotation_deg=(0.0, 90.0, 0.0),
            )
        )
        corrugated_parts.append(
            _build_shutter_curtain(
                "Bay_Shutter_TopTail",
                width_x=GARAGE_CLEAR_W + 0.03,
                z_min=GARAGE_CLEAR_H + 0.02,
                z_max=GARAGE_CLEAR_H + 0.18,
                slat_count=2,
            )
        )
        # Heavy bottom T-bar resting just above 3.10m clear height
        steel_parts.append(
            _add_box(
                "Bay_Shutter_BottomBar",
                (GARAGE_CLEAR_W + 0.04, 0.075, 0.045),
                (0.0, 0.0, GARAGE_CLEAR_H + 0.025),
                bevel_width=0.004,
            )
        )
    else:
        # Closed ribbed shutter slats from Z[0.055, 3.22] tucked into tracks and drum throat
        corrugated_parts.append(
            _build_shutter_curtain(
                "Bay_Shutter_Curtain",
                width_x=GARAGE_CLEAR_W + 0.03,
                z_min=0.055,
                z_max=lintel_top_z + 0.04,
                slat_count=30,
            )
        )
        # Bottom steel reinforcement T-bar + lock handle
        steel_parts.append(
            _add_box(
                "Bay_Shutter_BottomBar",
                (GARAGE_CLEAR_W + 0.04, 0.08, 0.055),
                (0.0, 0.0, 0.0275),
                bevel_width=0.004,
            )
        )
        for side in (-1.0, 1.0):
            steel_parts.append(
                _add_box(
                    "Bay_Shutter_LiftHandle",
                    (0.22, 0.035, 0.04),
                    (0.0, side * 0.045, 0.35),
                    bevel_width=0.003,
                )
            )

    return _finalize_and_export(
        name,
        [
            (mats["concrete"], concrete_parts, "BOX"),
            (mats["steel"], steel_parts, "BOX"),
            (mats["corrugated_metal"], corrugated_parts, "XZ"),
        ],
        output_dir,
    )


def generate_garage_shutter_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 4.0m x 0.35m concrete garage bay wall with closed 3.0m x 3.1m rolling shutter."""
    return _build_garage_bay_shell("garage_shutter_4m", is_open=False, output_dir=output_dir)


def generate_garage_shutter_open_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 4.0m x 0.35m concrete garage bay wall with open 3.0m x 3.1m doorway."""
    return _build_garage_bay_shell("garage_shutter_open_4m", is_open=True, output_dir=output_dir)


def generate_factory_pillar_4m(output_dir: Path) -> dict[str, object]:
    """Build 0.45m concrete pedestal (Z[0, 0.8]) + steel H-beam column (Z[0.8, 4.0])."""
    clean_scene()
    mats = _create_kit_materials()

    # Concrete pedestal base Z[0.0, 0.80]
    concrete_parts: list[bpy.types.Object] = []
    ped_lower_h = 0.72
    concrete_parts.append(
        _add_box(
            "Pillar_Concrete_Base",
            (PILLAR_BASE_SIZE, PILLAR_BASE_SIZE, ped_lower_h),
            (0.0, 0.0, ped_lower_h * 0.5),
            bevel_width=0.012,
        )
    )
    ped_cap_h = PILLAR_BASE_H - ped_lower_h  # 0.08m
    concrete_parts.append(
        _add_box(
            "Pillar_Concrete_Collar",
            (PILLAR_BASE_SIZE - 0.03, PILLAR_BASE_SIZE - 0.03, ped_cap_h),
            (0.0, 0.0, ped_lower_h + ped_cap_h * 0.5),
            bevel_width=0.018,
        )
    )

    steel_parts: list[bpy.types.Object] = []
    # Steel baseplate Z[0.80, 0.83]
    baseplate_h = 0.03
    baseplate_w = 0.38
    steel_parts.append(
        _add_box(
            "Pillar_Baseplate",
            (baseplate_w, baseplate_w, baseplate_h),
            (0.0, 0.0, PILLAR_BASE_H + baseplate_h * 0.5),
            bevel_width=0.004,
        )
    )
    # 4 corner anchor bolts
    bolt_z = PILLAR_BASE_H + baseplate_h + 0.018
    for bx in (-0.145, 0.145):
        for by in (-0.145, 0.145):
            steel_parts.append(
                _add_cylinder(
                    "Pillar_AnchorBolt",
                    radius=0.016,
                    depth=0.036,
                    location=(bx, by, bolt_z),
                    vertices=6,
                )
            )

    # H-beam column Z[0.83, 3.97]
    cap_h = 0.03
    col_z_min = PILLAR_BASE_H + baseplate_h  # 0.83
    col_z_max = PILLAR_HEIGHT - cap_h  # 3.97
    col_h = col_z_max - col_z_min
    col_cz = col_z_min + col_h * 0.5

    beam_w = 0.26
    flange_t = 0.026
    web_t = 0.022
    flange_y = beam_w * 0.5 - flange_t * 0.5

    for tag, sign in (("F", 1.0), ("B", -1.0)):
        steel_parts.append(
            _add_box(
                f"Pillar_HBeam_Flange_{tag}",
                (beam_w, flange_t, col_h),
                (0.0, sign * flange_y, col_cz),
                bevel_width=0.004,
            )
        )
    steel_parts.append(
        _add_box(
            "Pillar_HBeam_Web",
            (web_t, beam_w - 2.0 * flange_t, col_h),
            (0.0, 0.0, col_cz),
            bevel_width=0.0,
        )
    )

    # Bolted base gusset plates (4 vertical triangular/chamfered ribs on flanges & web)
    gusset_h = 0.22
    gusset_z = col_z_min + gusset_h * 0.5
    for sign in (-1.0, 1.0):
        # Flange gussets (along Y)
        steel_parts.append(
            _add_box(
                "Pillar_BaseGusset_Y",
                (0.022, 0.055, gusset_h),
                (0.0, sign * (beam_w * 0.5 + 0.027), gusset_z),
                bevel_width=0.008,
            )
        )
        # Web gussets (along X)
        steel_parts.append(
            _add_box(
                "Pillar_BaseGusset_X",
                (0.095, 0.022, gusset_h),
                (sign * (web_t * 0.5 + 0.047), 0.0, gusset_z),
                bevel_width=0.008,
            )
        )

    # Mid-height horizontal web stiffeners at Z=2.40m
    for sign in (-1.0, 1.0):
        steel_parts.append(
            _add_box(
                "Pillar_MidStiffener",
                ((beam_w - web_t) * 0.5, beam_w - 2.0 * flange_t, 0.022),
                (sign * (web_t * 0.5 + (beam_w - web_t) * 0.25), 0.0, 2.40),
                bevel_width=0.002,
            )
        )

    # Top cap plate Z[3.97, 4.00] + under-cap stiffener gussets
    steel_parts.append(
        _add_box(
            "Pillar_TopCap",
            (0.38, 0.38, cap_h),
            (0.0, 0.0, PILLAR_HEIGHT - cap_h * 0.5),
            bevel_width=0.004,
        )
    )
    for sign in (-1.0, 1.0):
        steel_parts.append(
            _add_box(
                "Pillar_TopGusset",
                (0.09, 0.022, 0.14),
                (sign * (web_t * 0.5 + 0.045), 0.0, col_z_max - 0.07),
                bevel_width=0.006,
            )
        )

    return _finalize_and_export(
        "factory_pillar_4m",
        [
            (mats["concrete"], concrete_parts, "BOX"),
            (mats["steel"], steel_parts, "BOX"),
        ],
        output_dir,
    )


def main() -> None:
    """Entry point for tools/blender/run.py or direct blender --background --python."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "factory_shells"
        generate_factory_roof_4m(output_dir)
        generate_garage_shutter_4m(output_dir)
        generate_garage_shutter_open_4m(output_dir)
        generate_factory_pillar_4m(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
