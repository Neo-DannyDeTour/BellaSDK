"""Procedural Blender generator for modular factory perimeter walls and beams.

Generates 3 modular factory shell GLBs in assets/models/factory_shells/:
1. boundary_wall.glb - 4.0m W x 3.0m H x 0.35m D precast perimeter wall with flared plinth,
                       buttress pilasters, sloped coping cap (z=2.85..3.00m), 3x 45-deg security
                       outrigger brackets, and horizontal steel rail bar.
2. wall_3m.glb       - 3.0m W x 4.0m H x 0.35m D narrow modular filler wall bay matching
                       factory_wall_4m elevation with mid vertical rib & top steel I-beam.
3. steel_beam_4m.glb - 4.0m L x 0.30m H x 0.22m W structural steel H/I-beam with bevelled
                       flanges, 5 stiffener gusset pairs, welded end plates & 6 hex bolts/end.

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered X and Y).
- Clean world-metric 2.0m cubic box UVs.
- Deterministic material slot ordering logged at export time.
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
from mathutils import Vector

# Shared dimensions matching factory_wall_kit.py (meters)
WALL_HEIGHT_4M = 4.0
WALL_THICK = 0.35
PANEL_RECESS_THICK = 0.29
PILASTER_WIDTH = 0.22
PLINTH_HEIGHT = 0.45
BEAM_HEIGHT = 0.24
BEAM_Z_MIN = WALL_HEIGHT_4M - BEAM_HEIGHT  # 3.76m


def _add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    bevel_width: float = 0.008,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a scaled cube with applied rotation/scale and optional bevel."""
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
    vertices: int = 8,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a closed polygon cylinder (e.g., hex bolt or steel bar) with applied transforms."""
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


def _add_tapered_prism_y(
    name: str,
    x_span: tuple[float, float],
    sections_yz: list[tuple[float, float]],
    bevel_width: float = 0.006,
) -> bpy.types.Object:
    """Create a symmetric manifold prism along X from (z, half_width_y) cross-section pairs."""
    x0, x1 = x_span
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    # Build closed ring on each X end: traverse -Y side bottom->top, then +Y side top->bottom
    ring_pts: list[tuple[float, float]] = []
    for z_val, hy in sections_yz:
        ring_pts.append((-hy, z_val))
    for z_val, hy in reversed(sections_yz):
        ring_pts.append((hy, z_val))

    n = len(ring_pts)
    left_verts = [bm.verts.new((x0, py, pz)) for py, pz in ring_pts]
    right_verts = [bm.verts.new((x1, py, pz)) for py, pz in ring_pts]

    bm.faces.new(list(reversed(left_verts)))
    bm.faces.new(right_verts)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((left_verts[i], right_verts[i], right_verts[j], left_verts[j]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.loops.layers.uv.verify()
    bm.to_mesh(mesh)
    bm.free()

    if bevel_width > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = 1
        bev.limit_method = "ANGLE"
        bev.angle_limit = math.radians(20.0)
    return obj


def _add_strut(
    name: str,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    width_x: float,
    thick_perp: float,
    bevel_width: float = 0.003,
) -> bpy.types.Object:
    """Create a rectangular bar spanning p0->p1 with width aligned to world X."""
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
        uv_layer_obj = mesh.uv_layers.new(name="UVMap")
    else:
        uv_layer_obj = mesh.uv_layers.active or mesh.uv_layers[0]
    mesh.uv_layers.active = uv_layer_obj
    uv_layer = uv_layer_obj.data

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


def _create_kit_materials() -> tuple[bpy.types.Material, bpy.types.Material]:
    """Create 'concrete' and 'steel' material slots matching BellaSDK factory shells."""
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
    return concrete_mat, steel_mat


def _finalize_and_export(
    name: str,
    slot_groups: list[tuple[bpy.types.Material, list[bpy.types.Object]]],
    output_dir: Path,
) -> dict[str, object]:
    """Apply modifiers, join parts in exact slot order, UV-map, verify slots, and export GLB."""
    all_parts: list[bpy.types.Object] = []
    expected_slot_names: list[str] = []

    for mat, parts in slot_groups:
        if not parts:
            continue
        expected_slot_names.append(mat.name)
        for part in parts:
            bpy.context.view_layer.objects.active = part
            for mod in list(part.modifiers):
                bpy.ops.object.modifier_apply(modifier=mod.name)
            assign_material(part, mat)
            all_parts.append(part)

    bpy.ops.object.select_all(action="DESELECT")
    for part in all_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = all_parts[0]
    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name

    # Apply all object transforms before UV assignment & export
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    _apply_box_uvs(obj, tile_meters=2.0)

    slots = [(i, m.name) for i, m in enumerate(obj.data.materials)]
    actual_slot_names = [m.name for m in obj.data.materials]
    if actual_slot_names != expected_slot_names:
        raise RuntimeError(
            f"[{name}] Material slot mismatch: expected {expected_slot_names}, got {actual_slot_names}"
        )

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

    out_path = output_dir / f"{name}.glb"
    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    print(f"[{name}] slots={slots} tris={tri_count} blender_bbox={bbox_blender} path={out_path}")
    return {
        "name": name,
        "path": out_path,
        "slots": slots,
        "tris": tri_count,
        "bbox": bbox_blender,
    }


def generate_boundary_wall(output_dir: Path) -> dict[str, object]:
    """Build 4.0m W x 3.0m H x 0.35m D boundary wall with sloped coping & 45-deg security outriggers."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    wall_w = 4.0
    pilaster_w = 0.28
    pilaster_d_base = 0.42  # Y in [-0.21, 0.21]
    pilaster_d_top = 0.36   # tapered buttress silhouette meeting coping cleanly
    panel_d = 0.28
    coping_z0 = 2.85
    coping_z1 = 3.00

    concrete_parts: list[bpy.types.Object] = []

    # 1. Twin buttress pilasters at wall ends (0.28m W x 0.42m D base tapering to 0.36m D under coping)
    inner_x = wall_w * 0.5 - pilaster_w  # 1.72m
    pilaster_sections = [
        (0.0, pilaster_d_base * 0.5),
        (PLINTH_HEIGHT, pilaster_d_base * 0.5),
        (coping_z0, pilaster_d_top * 0.5),
    ]
    concrete_parts.append(
        _add_tapered_prism_y("BWall_Pilaster_L", (-wall_w * 0.5, -inner_x), pilaster_sections, 0.008)
    )
    concrete_parts.append(
        _add_tapered_prism_y("BWall_Pilaster_R", (inner_x, wall_w * 0.5), pilaster_sections, 0.008)
    )

    # 2. Flared 0.45m concrete base plinth between pilasters (0.40m D base -> 0.32m D at z=0.45m)
    plinth_sections = [
        (0.0, 0.20),
        (0.10, 0.20),
        (PLINTH_HEIGHT, 0.16),
    ]
    concrete_parts.append(
        _add_tapered_prism_y("BWall_Flared_Plinth", (-inner_x, inner_x), plinth_sections, 0.008)
    )

    # 3. Recessed weathered concrete panel (0.28m D, z=0.45..2.85m)
    panel_h = coping_z0 - PLINTH_HEIGHT
    concrete_parts.append(
        _add_box(
            "BWall_Recessed_Panel",
            (2.0 * inner_x, panel_d, panel_h),
            (0.0, 0.0, PLINTH_HEIGHT + panel_h * 0.5),
            bevel_width=0.006,
        )
    )

    # 4. Sloped precast coping cap (z=2.85..3.00m, full 4.0m width)
    coping_sections = [
        (coping_z0, 0.195),
        (2.91, 0.195),
        (coping_z1, 0.055),
    ]
    concrete_parts.append(
        _add_tapered_prism_y("BWall_Coping_Cap", (-wall_w * 0.5, wall_w * 0.5), coping_sections, 0.004)
    )

    # 5. Steel: 3 angled 45-deg security outrigger brackets at top + chunky horizontal rail bar
    steel_parts: list[bpy.types.Object] = []
    bracket_xs = (-1.333, 0.0, 1.333)
    arm_start_y = -0.02
    arm_start_z = 2.985
    arm_reach = 0.27  # 45 deg outward (-Y) and upward (+Z)
    tip_y = arm_start_y - arm_reach  # -0.290
    tip_z = arm_start_z + arm_reach  # 3.255

    for idx, bx in enumerate(bracket_xs):
        # Mounting saddle bolted onto top coping crest (embedded 5mm into concrete for zero gap)
        steel_parts.append(
            _add_box(
                f"BWall_Outrigger_Plate_{idx}",
                (0.11, 0.13, 0.026),
                (bx, -0.015, 2.995),
                bevel_width=0.003,
            )
        )
        # Chunky 45-deg angled square steel outrigger arm
        steel_parts.append(
            _add_strut(
                f"BWall_Outrigger_Arm_{idx}",
                (bx, arm_start_y, arm_start_z),
                (bx, tip_y, tip_z),
                width_x=0.044,
                thick_perp=0.044,
                bevel_width=0.003,
            )
        )
        # Diagonal knee brace supporting underside of arm from front coping shoulder
        steel_parts.append(
            _add_strut(
                f"BWall_Outrigger_Brace_{idx}",
                (bx, -0.155, 2.915),
                (bx, -0.185, 3.135),
                width_x=0.030,
                thick_perp=0.030,
                bevel_width=0.002,
            )
        )
        # Tip cradle bracket holding the horizontal rail bar
        steel_parts.append(
            _add_box(
                f"BWall_Outrigger_Tip_{idx}",
                (0.068, 0.064, 0.064),
                (bx, tip_y, tip_z),
                bevel_width=0.003,
            )
        )

    # Chunky horizontal steel rail bar spanning entire 4.0m bay (manifold square-bevel bar)
    steel_parts.append(
        _add_box(
            "BWall_Security_Rail_Bar",
            (wall_w, 0.046, 0.046),
            (0.0, tip_y, tip_z),
            bevel_width=0.004,
        )
    )

    return _finalize_and_export(
        "boundary_wall",
        [(concrete_mat, concrete_parts), (steel_mat, steel_parts)],
        output_dir,
    )


def generate_wall_3m(output_dir: Path) -> dict[str, object]:
    """Build 3.0m W x 4.0m H x 0.35m D modular filler wall bay matching factory_wall_4m."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    wall_w = 3.0
    upper_h = BEAM_Z_MIN - PLINTH_HEIGHT  # 3.31m
    upper_z = PLINTH_HEIGHT + upper_h * 0.5  # 2.105m
    center_w = wall_w - 2.0 * PILASTER_WIDTH  # 2.56m

    concrete_parts: list[bpy.types.Object] = []

    # 1. Base plinth (0.45m H x 0.35m D)
    concrete_parts.append(
        _add_box(
            "Wall3m_Plinth",
            (wall_w, WALL_THICK, PLINTH_HEIGHT),
            (0.0, 0.0, PLINTH_HEIGHT * 0.5),
            bevel_width=0.012,
        )
    )

    # 2. Left & right 0.22m end pilasters
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        concrete_parts.append(
            _add_box(
                f"Wall3m_Pilaster_{tag}",
                (PILASTER_WIDTH, WALL_THICK, upper_h),
                (sign * (wall_w * 0.5 - PILASTER_WIDTH * 0.5), 0.0, upper_z),
                bevel_width=0.008,
            )
        )

    # 3. Recessed 0.29m center concrete panel
    concrete_parts.append(
        _add_box(
            "Wall3m_Center_Panel",
            (center_w, PANEL_RECESS_THICK, upper_h),
            (0.0, 0.0, upper_z),
            bevel_width=0.006,
        )
    )

    # 4. Mid vertical reveal rib (0.16m W x 0.34m D) + split horizontal tie rib (z=2.15m matching factory_wall_4m)
    vert_rib_w = 0.16
    concrete_parts.append(
        _add_box(
            "Wall3m_Mid_Vert_Rib",
            (vert_rib_w, WALL_THICK - 0.01, upper_h),
            (0.0, 0.0, upper_z),
            bevel_width=0.006,
        )
    )
    half_tie_w = (center_w - vert_rib_w) * 0.5
    tie_cx = vert_rib_w * 0.5 + half_tie_w * 0.5
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        concrete_parts.append(
            _add_box(
                f"Wall3m_Mid_Horiz_Rib_{tag}",
                (half_tie_w, WALL_THICK - 0.02, 0.14),
                (sign * tie_cx, 0.0, 2.15),
                bevel_width=0.006,
            )
        )

    # 5. Top steel I-beam (z=3.76..4.00m) with stiffener gussets matching factory_wall_4m
    steel_parts: list[bpy.types.Object] = []
    flange_h = 0.035
    web_h = BEAM_HEIGHT - 2.0 * flange_h  # 0.17m
    web_thick = 0.14

    steel_parts.append(
        _add_box(
            "Wall3m_Beam_BotFlange",
            (wall_w, WALL_THICK, flange_h),
            (0.0, 0.0, BEAM_Z_MIN + flange_h * 0.5),
            bevel_width=0.005,
        )
    )
    steel_parts.append(
        _add_box(
            "Wall3m_Beam_Web",
            (wall_w, web_thick, web_h),
            (0.0, 0.0, BEAM_Z_MIN + flange_h + web_h * 0.5),
            bevel_width=0.0,
        )
    )
    steel_parts.append(
        _add_box(
            "Wall3m_Beam_TopFlange",
            (wall_w, WALL_THICK, flange_h),
            (0.0, 0.0, WALL_HEIGHT_4M - flange_h * 0.5),
            bevel_width=0.005,
        )
    )

    gusset_thick = 0.025
    gusset_depth = (WALL_THICK - web_thick) * 0.5 - 0.005
    gusset_z = BEAM_Z_MIN + flange_h + web_h * 0.5
    for gx in (-1.0, 0.0, 1.0):
        for side in (-1.0, 1.0):
            steel_parts.append(
                _add_box(
                    "Wall3m_Beam_Gusset",
                    (gusset_thick, gusset_depth, web_h),
                    (gx, side * (web_thick * 0.5 + gusset_depth * 0.5), gusset_z),
                    bevel_width=0.003,
                )
            )

    return _finalize_and_export(
        "wall_3m",
        [(concrete_mat, concrete_parts), (steel_mat, steel_parts)],
        output_dir,
    )


def generate_steel_beam_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m L x 0.30m H x 0.22m W structural steel H/I-beam with gussets & bolted end plates."""
    clean_scene()
    _, steel_mat = _create_kit_materials()

    beam_l = 4.0
    beam_h = 0.30
    beam_w = 0.22
    flange_t = 0.028
    web_t = 0.022
    web_h = beam_h - 2.0 * flange_t  # 0.244m

    end_plate_t = 0.022
    bolt_head_h = 0.018
    # Place end plates slightly inset so outer hex bolt heads sit flush at X = +/-2.000m
    inner_span = beam_l - 2.0 * (end_plate_t + bolt_head_h)  # 3.920m
    plate_cx = beam_l * 0.5 - bolt_head_h - end_plate_t * 0.5  # 1.971m
    bolt_cx = beam_l * 0.5 - bolt_head_h * 0.5  # 1.991m

    steel_parts: list[bpy.types.Object] = []

    # 1. Bottom and top bevelled flanges (0.028m thick)
    steel_parts.append(
        _add_box(
            "Beam_BotFlange",
            (inner_span, beam_w, flange_t),
            (0.0, 0.0, flange_t * 0.5),
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box(
            "Beam_TopFlange",
            (inner_span, beam_w, flange_t),
            (0.0, 0.0, beam_h - flange_t * 0.5),
            bevel_width=0.004,
        )
    )

    # 2. Central web (0.022m thick)
    steel_parts.append(
        _add_box(
            "Beam_Web",
            (inner_span, web_t, web_h),
            (0.0, 0.0, beam_h * 0.5),
            bevel_width=0.0,
        )
    )

    # 3. Five vertical stiffener gusset pairs along web
    gusset_t = 0.018
    gusset_d = (beam_w - web_t) * 0.5 - 0.004  # 0.095m
    gusset_y = web_t * 0.5 + gusset_d * 0.5
    gusset_z = beam_h * 0.5
    for idx, gx in enumerate((-1.32, -0.66, 0.0, 0.66, 1.32)):
        for side_tag, sign in (("Front", -1.0), ("Back", 1.0)):
            steel_parts.append(
                _add_box(
                    f"Beam_Gusset_{idx}_{side_tag}",
                    (gusset_t, gusset_d, web_h),
                    (gx, sign * gusset_y, gusset_z),
                    bevel_width=0.002,
                )
            )

    # 4. Welded end bolt-plates + 6 chunky hex bolts per end (3 rows x 2 columns)
    bolt_ys = (-0.062, 0.062)
    bolt_zs = (0.065, 0.150, 0.235)
    for end_tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Beam_EndPlate_{end_tag}",
                (end_plate_t, beam_w, beam_h),
                (sign * plate_cx, 0.0, beam_h * 0.5),
                bevel_width=0.003,
            )
        )
        for by in bolt_ys:
            for bz in bolt_zs:
                steel_parts.append(
                    _add_cylinder(
                        f"Beam_HexBolt_{end_tag}",
                        radius=0.023,
                        depth=bolt_head_h,
                        location=(sign * bolt_cx, by, bz),
                        vertices=6,
                        rotation_deg=(0.0, 90.0, 0.0),
                    )
                )

    return _finalize_and_export(
        "steel_beam_4m",
        [(steel_mat, steel_parts)],
        output_dir,
    )


def main() -> None:
    """Generate all 3 factory perimeter shell GLB assets."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "factory_shells"
        generate_boundary_wall(output_dir)
        generate_wall_3m(output_dir)
        generate_steel_beam_4m(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
