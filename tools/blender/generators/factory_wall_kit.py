"""Procedural Blender generator for modular post-apocalyptic factory wall shells.

Generates 3 modular 4.0m x 4.0m x 0.35m wall shell GLBs in assets/models/factory_shells/:
- factory_wall_4m.glb: Solid precast concrete wall panel with base plinth & top steel I-beam lip.
- factory_doorway_4m.glb: Wall with 2.2m x 2.8m doorway opening, steel frame, lintel & shutter box.
- factory_window_4m.glb: Wall with 2.6m x 1.8m multi-pane steel window, sill & broken/open panes.

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Clean world-metric box UVs (2.0m tile).
- Separate material slots named 'concrete' and 'steel' for Godot ORM material assignment.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bpy
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material

# Shared modular dimensions (meters)
WALL_WIDTH = 4.0
WALL_HEIGHT = 4.0
WALL_THICK = 0.35
PANEL_RECESS_THICK = 0.29
PILASTER_WIDTH = 0.22

PLINTH_HEIGHT = 0.45
BEAM_HEIGHT = 0.24
BEAM_Z_MIN = WALL_HEIGHT - BEAM_HEIGHT  # 3.76m

# Doorway dimensions
DOOR_WIDTH = 2.2
DOOR_HEIGHT = 2.8
SHUTTER_BOX_H = 0.40

# Window dimensions
WIN_WIDTH = 2.6
WIN_HEIGHT = 1.8
WIN_Z_MIN = 1.10
WIN_Z_MAX = WIN_Z_MIN + WIN_HEIGHT  # 2.90m
SILL_HEIGHT = 0.10


def _add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    bevel_width: float = 0.008,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a scaled cube with applied scale and optional bevel."""
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


def _create_kit_materials() -> tuple[bpy.types.Material, bpy.types.Material]:
    """Create 'concrete' and 'steel' material slots for Godot ORM reassignment."""
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


def _build_top_steel_beam(prefix: str) -> list[bpy.types.Object]:
    """Build the shared 4.0m top steel I-beam lip with vertical stiffener gussets."""
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


def _finalize_and_export(
    name: str,
    concrete_parts: list[bpy.types.Object],
    steel_parts: list[bpy.types.Object],
    concrete_mat: bpy.types.Material,
    steel_mat: bpy.types.Material,
    output_dir: Path,
) -> dict[str, object]:
    """Apply modifiers, assign materials, join into one mesh, UV-map, and export GLB."""
    for part in concrete_parts:
        bpy.context.view_layer.objects.active = part
        for mod in list(part.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        assign_material(part, concrete_mat)

    for part in steel_parts:
        bpy.context.view_layer.objects.active = part
        for mod in list(part.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        assign_material(part, steel_mat)

    all_parts = concrete_parts + steel_parts
    bpy.ops.object.select_all(action="DESELECT")
    for part in all_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = concrete_parts[0]
    bpy.ops.object.join()

    obj = bpy.context.active_object
    obj.name = name

    # Apply object location/rotation/scale so origin is at (0, 0, 0) bottom-center
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    _apply_box_uvs(obj, tile_meters=2.0)

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
    print(f"[{name}] tris={tri_count} blender_bbox={bbox_blender} path={out_path}")
    return {"name": name, "path": out_path, "tris": tri_count, "bbox": bbox_blender}


def generate_factory_wall_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 4.0m x 0.35m solid concrete wall panel with plinth and top steel beam."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    concrete_parts: list[bpy.types.Object] = []
    # Base plinth
    concrete_parts.append(
        _add_box(
            "Wall_Plinth",
            (WALL_WIDTH, WALL_THICK, PLINTH_HEIGHT),
            (0.0, 0.0, PLINTH_HEIGHT * 0.5),
            bevel_width=0.012,
        )
    )
    # Left and right full-thickness pilasters
    upper_h = BEAM_Z_MIN - PLINTH_HEIGHT
    upper_z = PLINTH_HEIGHT + upper_h * 0.5
    concrete_parts.append(
        _add_box(
            "Wall_Pilaster_L",
            (PILASTER_WIDTH, WALL_THICK, upper_h),
            (-WALL_WIDTH * 0.5 + PILASTER_WIDTH * 0.5, 0.0, upper_z),
            bevel_width=0.008,
        )
    )
    concrete_parts.append(
        _add_box(
            "Wall_Pilaster_R",
            (PILASTER_WIDTH, WALL_THICK, upper_h),
            (WALL_WIDTH * 0.5 - PILASTER_WIDTH * 0.5, 0.0, upper_z),
            bevel_width=0.008,
        )
    )
    # Recessed center concrete slab
    center_w = WALL_WIDTH - 2.0 * PILASTER_WIDTH
    concrete_parts.append(
        _add_box(
            "Wall_Center_Slab",
            (center_w, PANEL_RECESS_THICK, upper_h),
            (0.0, 0.0, upper_z),
            bevel_width=0.006,
        )
    )
    # Mid-height concrete horizontal tie rib
    concrete_parts.append(
        _add_box(
            "Wall_Mid_Rib",
            (center_w, WALL_THICK - 0.02, 0.14),
            (0.0, 0.0, 2.15),
            bevel_width=0.008,
        )
    )

    steel_parts = _build_top_steel_beam("Wall")
    return _finalize_and_export(
        "factory_wall_4m", concrete_parts, steel_parts, concrete_mat, steel_mat, output_dir
    )


def generate_factory_doorway_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 4.0m x 0.35m wall with 2.2m x 2.8m doorway, steel frame & shutter box."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    concrete_parts: list[bpy.types.Object] = []
    half_door = DOOR_WIDTH * 0.5  # 1.1m
    pier_w = (WALL_WIDTH - DOOR_WIDTH) * 0.5  # 0.9m
    pier_cx = half_door + pier_w * 0.5  # 1.55m

    # Left and right plinths & upper piers
    upper_h = BEAM_Z_MIN - PLINTH_HEIGHT
    upper_z = PLINTH_HEIGHT + upper_h * 0.5
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        concrete_parts.append(
            _add_box(
                f"Door_Plinth_{tag}",
                (pier_w, WALL_THICK, PLINTH_HEIGHT),
                (sign * pier_cx, 0.0, PLINTH_HEIGHT * 0.5),
                bevel_width=0.012,
            )
        )
        # Outer pilaster
        concrete_parts.append(
            _add_box(
                f"Door_Pilaster_{tag}",
                (PILASTER_WIDTH, WALL_THICK, upper_h),
                (sign * (WALL_WIDTH * 0.5 - PILASTER_WIDTH * 0.5), 0.0, upper_z),
                bevel_width=0.008,
            )
        )
        # Inner pier section
        inner_w = pier_w - PILASTER_WIDTH
        inner_cx = half_door + inner_w * 0.5
        concrete_parts.append(
            _add_box(
                f"Door_Pier_{tag}",
                (inner_w, PANEL_RECESS_THICK, upper_h),
                (sign * inner_cx, 0.0, upper_z),
                bevel_width=0.006,
            )
        )

    # Header concrete panel above doorway (Z: 2.80 -> 3.76)
    header_h = BEAM_Z_MIN - DOOR_HEIGHT
    concrete_parts.append(
        _add_box(
            "Door_Header_Concrete",
            (DOOR_WIDTH, PANEL_RECESS_THICK, header_h),
            (0.0, 0.0, DOOR_HEIGHT + header_h * 0.5),
            bevel_width=0.006,
        )
    )

    steel_parts = _build_top_steel_beam("Door")

    # Steel doorway jambs (left & right)
    jamb_w = 0.075
    jamb_thick = WALL_THICK + 0.02
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Door_Jamb_{tag}",
                (jamb_w, jamb_thick, DOOR_HEIGHT),
                (sign * (half_door - jamb_w * 0.5), 0.0, DOOR_HEIGHT * 0.5),
                bevel_width=0.005,
            )
        )

    # Steel lintel beam across doorway top
    lintel_h = 0.14
    steel_parts.append(
        _add_box(
            "Door_Lintel",
            (DOOR_WIDTH + 0.24, jamb_thick + 0.02, lintel_h),
            (0.0, 0.0, DOOR_HEIGHT + lintel_h * 0.5),
            bevel_width=0.006,
        )
    )

    # Rolled shutter housing box above lintel
    shutter_z = DOOR_HEIGHT + lintel_h + SHUTTER_BOX_H * 0.5
    steel_parts.append(
        _add_box(
            "Door_Shutter_Box",
            (DOOR_WIDTH + 0.16, WALL_THICK + 0.10, SHUTTER_BOX_H),
            (0.0, 0.0, shutter_z),
            bevel_width=0.015,
        )
    )
    # Rolled shutter bottom lip / partially jammed slat edge
    steel_parts.append(
        _add_box(
            "Door_Shutter_Lip",
            (DOOR_WIDTH - 0.15, 0.04, 0.06),
            (0.0, 0.0, DOOR_HEIGHT - 0.03),
            bevel_width=0.004,
        )
    )

    return _finalize_and_export(
        "factory_doorway_4m", concrete_parts, steel_parts, concrete_mat, steel_mat, output_dir
    )


def generate_factory_window_4m(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 4.0m x 0.35m wall with 2.6m x 1.8m multi-pane steel window & broken panes."""
    clean_scene()
    concrete_mat, steel_mat = _create_kit_materials()

    concrete_parts: list[bpy.types.Object] = []
    half_win = WIN_WIDTH * 0.5  # 1.3m
    pier_w = (WALL_WIDTH - WIN_WIDTH) * 0.5  # 0.7m

    # Base plinth
    concrete_parts.append(
        _add_box(
            "Win_Plinth",
            (WALL_WIDTH, WALL_THICK, PLINTH_HEIGHT),
            (0.0, 0.0, PLINTH_HEIGHT * 0.5),
            bevel_width=0.012,
        )
    )

    # Outer pilasters
    upper_h = BEAM_Z_MIN - PLINTH_HEIGHT
    upper_z = PLINTH_HEIGHT + upper_h * 0.5
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        concrete_parts.append(
            _add_box(
                f"Win_Pilaster_{tag}",
                (PILASTER_WIDTH, WALL_THICK, upper_h),
                (sign * (WALL_WIDTH * 0.5 - PILASTER_WIDTH * 0.5), 0.0, upper_z),
                bevel_width=0.008,
            )
        )

    # Lower concrete knee-wall under sill (Z: 0.45 -> 1.00)
    sill_z_min = WIN_Z_MIN - SILL_HEIGHT  # 1.00m
    knee_h = sill_z_min - PLINTH_HEIGHT
    concrete_parts.append(
        _add_box(
            "Win_Knee_Wall",
            (WALL_WIDTH - 2.0 * PILASTER_WIDTH, PANEL_RECESS_THICK, knee_h),
            (0.0, 0.0, PLINTH_HEIGHT + knee_h * 0.5),
            bevel_width=0.006,
        )
    )

    # Concrete window sill (proud drip edge)
    concrete_parts.append(
        _add_box(
            "Win_Sill",
            (WIN_WIDTH + 0.20, WALL_THICK + 0.05, SILL_HEIGHT),
            (0.0, 0.0, sill_z_min + SILL_HEIGHT * 0.5),
            bevel_width=0.010,
        )
    )

    # Left & right piers beside window (Z: 1.00 -> 3.76)
    side_h = BEAM_Z_MIN - sill_z_min
    side_z = sill_z_min + side_h * 0.5
    inner_pier_w = pier_w - PILASTER_WIDTH
    inner_pier_cx = half_win + inner_pier_w * 0.5
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        concrete_parts.append(
            _add_box(
                f"Win_Pier_{tag}",
                (inner_pier_w, PANEL_RECESS_THICK, side_h),
                (sign * inner_pier_cx, 0.0, side_z),
                bevel_width=0.006,
            )
        )

    # Upper concrete header above window (Z: 2.90 -> 3.76)
    header_h = BEAM_Z_MIN - WIN_Z_MAX
    concrete_parts.append(
        _add_box(
            "Win_Header",
            (WIN_WIDTH, PANEL_RECESS_THICK, header_h),
            (0.0, 0.0, WIN_Z_MAX + header_h * 0.5),
            bevel_width=0.006,
        )
    )

    steel_parts = _build_top_steel_beam("Win")

    # Outer steel window frame
    frame_w = 0.06
    frame_d = 0.14
    win_cz = (WIN_Z_MIN + WIN_Z_MAX) * 0.5
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Win_Frame_{tag}",
                (frame_w, frame_d, WIN_HEIGHT),
                (sign * (half_win - frame_w * 0.5), 0.0, win_cz),
                bevel_width=0.004,
            )
        )
    for tag, z_pos in (("Bot", WIN_Z_MIN + frame_w * 0.5), ("Top", WIN_Z_MAX - frame_w * 0.5)):
        steel_parts.append(
            _add_box(
                f"Win_Frame_{tag}",
                (WIN_WIDTH - 2.0 * frame_w, frame_d, frame_w),
                (0.0, 0.0, z_pos),
                bevel_width=0.004,
            )
        )

    # Multi-pane steel mullions (4 cols x 3 rows) with broken/missing sections
    mullion_w = 0.032
    mullion_d = 0.06
    inner_w = WIN_WIDTH - 2.0 * frame_w
    inner_h = WIN_HEIGHT - 2.0 * frame_w
    col_step = inner_w / 4.0
    row_step = inner_h / 3.0

    # Vertical mullions (center mullion has a broken upper segment)
    for idx, mx in enumerate((-col_step, 0.0, col_step)):
        if idx == 1:
            # Broken center mullion: lower intact, upper snapped/missing
            seg_h = inner_h * 0.58
            steel_parts.append(
                _add_box(
                    "Win_Mullion_V_BrokenLow",
                    (mullion_w, mullion_d, seg_h),
                    (mx, 0.0, WIN_Z_MIN + frame_w + seg_h * 0.5),
                    bevel_width=0.002,
                )
            )
            # Bent/snapped top stub
            steel_parts.append(
                _add_box(
                    "Win_Mullion_V_BentStub",
                    (mullion_w, mullion_d, 0.24),
                    (mx + 0.03, 0.02, WIN_Z_MAX - frame_w - 0.11),
                    bevel_width=0.002,
                    rotation_deg=(8.0, -14.0, 0.0),
                )
            )
        else:
            steel_parts.append(
                _add_box(
                    f"Win_Mullion_V_{idx}",
                    (mullion_w, mullion_d, inner_h),
                    (mx, 0.0, win_cz),
                    bevel_width=0.002,
                )
            )

    # Horizontal transoms (upper transom missing on right-center pane for broken opening)
    for row_idx in (1, 2):
        mz = WIN_Z_MIN + frame_w + row_idx * row_step
        if row_idx == 2:
            # Left segment intact, right-center broken out
            left_len = inner_w * 0.50
            steel_parts.append(
                _add_box(
                    "Win_Transom_Upper_L",
                    (left_len, mullion_d, mullion_w),
                    (-inner_w * 0.5 + left_len * 0.5, 0.0, mz),
                    bevel_width=0.002,
                )
            )
            right_len = inner_w * 0.25
            steel_parts.append(
                _add_box(
                    "Win_Transom_Upper_R",
                    (right_len, mullion_d, mullion_w),
                    (inner_w * 0.5 - right_len * 0.5, 0.0, mz),
                    bevel_width=0.002,
                )
            )
        else:
            steel_parts.append(
                _add_box(
                    "Win_Transom_Lower",
                    (inner_w, mullion_d, mullion_w),
                    (0.0, 0.0, mz),
                    bevel_width=0.002,
                )
            )

    # A few rusted steel blackout louver plates in 2 intact panes; remaining 10 panes open
    plate_w = col_step - mullion_w
    plate_h = row_step - mullion_w
    for col_i, row_i in ((0, 0), (3, 2)):
        px = -inner_w * 0.5 + (col_i + 0.5) * col_step
        pz = WIN_Z_MIN + frame_w + (row_i + 0.5) * row_step
        steel_parts.append(
            _add_box(
                f"Win_Blackout_Plate_{col_i}_{row_i}",
                (plate_w, 0.02, plate_h),
                (px, 0.0, pz),
                bevel_width=0.002,
            )
        )

    return _finalize_and_export(
        "factory_window_4m", concrete_parts, steel_parts, concrete_mat, steel_mat, output_dir
    )


def main() -> None:
    """Entry point for tools/blender/run.py or direct blender --background --python."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "factory_shells"
        generate_factory_wall_4m(output_dir)
        generate_factory_doorway_4m(output_dir)
        generate_factory_window_4m(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
