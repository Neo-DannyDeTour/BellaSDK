"""Procedural Blender generator for factory exit door & broken perforated shutter kits.

Generates 3 modular shell/prop GLBs in assets/models/factory_shells/:
1. door_exit_frame.glb           - 1.20m W x 2.30m H x 0.35m D welded steel rebate door frame.
2. door_exit.glb                 - 1.00m W x 2.15m H x 0.06m D fire-exit door leaf with wire-glass & panic bar.
3. shutter_perforated_broken.glb - 4.0m W x 4.0m H x 0.35m D garage bay with pried perforated shutter.

Conventions:
- Origin at bottom-center (Blender Z=0 -> Godot min_y=0, centered on X and Y).
- Godot Y-up export: Godot +X = Blender +X, Godot +Y = Blender +Z, Godot +Z = Blender -Y.
- Clean world-metric 2.0m cubic box UVs (planar XZ for shutter slats).
- Deterministic material slot ordering matching BellaSDK Godot .tres overrides.
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

# Shared modular 4m x 4m garage bay dimensions matching factory_garage_shell_kit.py
WALL_WIDTH = 4.0
WALL_HEIGHT = 4.0
WALL_THICK = 0.35
PANEL_RECESS_THICK = 0.29
PILASTER_WIDTH = 0.22

PLINTH_HEIGHT = 0.45
BEAM_HEIGHT = 0.24
BEAM_Z_MIN = WALL_HEIGHT - BEAM_HEIGHT  # 3.76m

GARAGE_CLEAR_W = 3.0
GARAGE_CLEAR_H = 3.1
JAMB_WIDTH = 0.08
DRUM_BOX_H = 0.48

# Exit door frame & leaf dimensions
FRAME_W = 1.20
FRAME_H = 2.30
FRAME_D = 0.35
FRAME_JAMB_W = 0.09
FRAME_HEADER_H = 0.14
DOOR_LEAF_W = 1.00
DOOR_LEAF_H = 2.15
DOOR_LEAF_D = 0.06
HINGE_ZS = (0.30, 1.08, 1.86)


def _add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    bevel_width: float = 0.005,
    rotation_deg: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    """Create a scaled cube with applied transform and optional edge bevel."""
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


def _add_box_bounds(
    name: str,
    x0: float,
    x1: float,
    y0: float,
    y1: float,
    z0: float,
    z1: float,
    bevel_width: float = 0.004,
) -> bpy.types.Object:
    """Create an axis-aligned box from explicit min/max bounds."""
    return _add_box(
        name=name,
        size=(x1 - x0, y1 - y0, z1 - z0),
        location=((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5),
        bevel_width=bevel_width,
    )


def _add_cylinder(
    name: str,
    radius: float,
    depth: float,
    location: tuple[float, float, float],
    vertices: int = 10,
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


def _add_strut(
    name: str,
    p0: tuple[float, float, float],
    p1: tuple[float, float, float],
    width_y: float,
    thick_z: float,
    bevel_width: float = 0.0,
) -> bpy.types.Object:
    """Create a rectangular bar oriented along segment p0 -> p1."""
    v0 = Vector(p0)
    v1 = Vector(p1)
    diff = v1 - v0
    length = diff.length
    mid = (v0 + v1) * 0.5
    quat = diff.normalized().to_track_quat("X", "Z")

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=tuple(mid))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (length, width_y, thick_z)
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


def _add_swept_profile(
    name: str,
    stations: list[tuple[Vector, Vector, Vector]],
    profile_yz: list[tuple[float, float]],
) -> bpy.types.Object:
    """Sweep a closed 2D cross-section (local Y, Z) across 3D stations (center, y_dir, z_dir)."""
    bm = bmesh.new()
    rings: list[list[bmesh.types.BMVert]] = []
    for center, y_dir, z_dir in stations:
        ring = [bm.verts.new(center + y_dir * py + z_dir * pz) for py, pz in profile_yz]
        rings.append(ring)

    n_prof = len(profile_yz)
    for r_idx in range(len(rings) - 1):
        r0 = rings[r_idx]
        r1 = rings[r_idx + 1]
        for p_idx in range(n_prof):
            p_next = (p_idx + 1) % n_prof
            bm.faces.new((r0[p_idx], r1[p_idx], r1[p_next], r0[p_next]))

    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(list(rings[-1]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 2.0) -> None:
    """Generate clean world-metric cubic box UVs."""
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


def _apply_planar_xz_uvs(obj: bpy.types.Object, tile_meters: float = 2.0) -> None:
    """Generate continuous planar XZ UVs for horizontal shutter slats without degenerate Z caps."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv_layer = mesh.uv_layers.active.data

    inv_tile = 1.0 / tile_meters
    for poly in mesh.polygons:
        nx, nz = abs(poly.normal.x), abs(poly.normal.z)
        for loop_idx in poly.loop_indices:
            vert = mesh.vertices[mesh.loops[loop_idx].vertex_index].co
            if nx > 0.85:
                u, v = vert.y * inv_tile, vert.z * inv_tile
            elif nz > 0.85:
                u, v = vert.x * inv_tile, vert.y * inv_tile
            else:
                u, v = vert.x * inv_tile, vert.z * inv_tile
            uv_layer[loop_idx].uv = (u, v)


def _create_materials() -> dict[str, bpy.types.Material]:
    """Create PBR preview materials matching BellaSDK Godot slot names."""
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
    painted_mat = create_pbr_material(
        name="painted_metal",
        base_color=(0.18, 0.30, 0.24, 1.0),
        metallic=0.35,
        roughness=0.52,
    )
    glass_mat = create_pbr_material(
        name="glass",
        base_color=(0.46, 0.54, 0.60, 0.38),
        metallic=0.05,
        roughness=0.24,
    )
    if glass_mat.node_tree:
        bsdf = glass_mat.node_tree.nodes.get("Principled BSDF")
        if bsdf and "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = 0.38
    return {
        "concrete": concrete_mat,
        "steel": steel_mat,
        "corrugated_metal": corrugated_mat,
        "painted_metal": painted_mat,
        "glass": glass_mat,
    }


def _finalize_and_export(
    name: str,
    material_groups: list[tuple[bpy.types.Material, list[bpy.types.Object], str]],
    output_dir: Path,
) -> dict[str, object]:
    """Apply modifiers, assign materials in deterministic slot order, apply UVs, join, and export."""
    all_parts: list[bpy.types.Object] = []
    expected_slot_names: list[str] = []

    for mat, parts, uv_mode in material_groups:
        expected_slot_names.append(mat.name)
        for part in parts:
            bpy.context.view_layer.objects.active = part
            for mod in list(part.modifiers):
                bpy.ops.object.modifier_apply(modifier=mod.name)
            assign_material(part, mat)
            if uv_mode == "XZ":
                _apply_planar_xz_uvs(part, tile_meters=2.0)
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
    obj.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    actual_slots = [(i, m.name) for i, m in enumerate(obj.data.materials)]
    assert [m.name for m in obj.data.materials] == expected_slot_names, (
        f"Slot mismatch for {name}: got {actual_slots}, expected {expected_slot_names}"
    )

    tri_count = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    def _fmt(v: float) -> float:
        r = round(v, 4)
        return 0.0 if r == 0.0 else r

    bbox_blender = (
        _fmt(min(xs)),
        _fmt(max(xs)),
        _fmt(min(ys)),
        _fmt(max(ys)),
        _fmt(min(zs)),
        _fmt(max(zs)),
    )
    bbox_godot = (
        _fmt(min(xs)),
        _fmt(max(xs)),
        _fmt(min(zs)),
        _fmt(max(zs)),
        _fmt(-max(ys)),
        _fmt(-min(ys)),
    )

    out_path = output_dir / f"{name}.glb"
    export_godot_glb(
        filepath=out_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )
    print(
        f"[{name}] slots={actual_slots} tris={tri_count} "
        f"blender_bbox={bbox_blender} godot_bbox={bbox_godot} path={out_path}"
    )
    return {
        "name": name,
        "path": out_path,
        "slots": actual_slots,
        "tris": tri_count,
        "bbox_blender": bbox_blender,
        "bbox_godot": bbox_godot,
    }


def generate_door_exit_frame(output_dir: Path) -> dict[str, object]:
    """Build 1.20m W x 2.30m H x 0.35m D welded steel rebate door frame (clear 1.02m x 2.16m)."""
    clean_scene()
    mats = _create_materials()
    steel_parts: list[bpy.types.Object] = []

    half_w = FRAME_W * 0.5  # 0.60m
    half_d = FRAME_D * 0.5  # 0.175m
    clear_half_w = half_w - FRAME_JAMB_W  # 0.51m (clear 1.02m)
    pocket_x = clear_half_w + 0.022  # 0.532m rebate pocket
    spine_outer_x = half_w - 0.022  # 0.578m masonry groove wall
    clear_h = FRAME_H - FRAME_HEADER_H  # 2.16m

    # Left & Right welded rebate jambs (front/rear casing flanges, masonry-grip web, door-stop step)
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        x_in = sign * clear_half_w
        x_poc = sign * pocket_x
        x_sp = sign * spine_outer_x
        x_out = sign * half_w

        def _xpair(a: float, b: float) -> tuple[float, float]:
            return (min(a, b), max(a, b))

        # Front face casing flange (-Y exterior side)
        fx0, fx1 = _xpair(x_poc, x_out)
        steel_parts.append(
            _add_box_bounds(
                f"Frame_Jamb_{tag}_FrontCasing",
                fx0,
                fx1,
                -half_d,
                -0.125,
                0.0,
                FRAME_H,
                bevel_width=0.004,
            )
        )
        # Rear face casing + door-stop spine (+Y interior stop side, clear 1.02m opening)
        rx0, rx1 = _xpair(x_in, x_out)
        steel_parts.append(
            _add_box_bounds(
                f"Frame_Jamb_{tag}_RearStop",
                rx0,
                rx1,
                0.032,
                half_d,
                0.0,
                FRAME_H,
                bevel_width=0.004,
            )
        )
        # Central recessed masonry-grip web (creates rebate pocket + exterior masonry groove)
        wx0, wx1 = _xpair(x_poc, x_sp)
        steel_parts.append(
            _add_box_bounds(
                f"Frame_Jamb_{tag}_Web",
                wx0,
                wx1,
                -0.125,
                0.032,
                0.0,
                FRAME_H,
                bevel_width=0.0,
            )
        )

        # 3 masonry anchor tabs welded inside exterior groove (flush with |X|=0.60m)
        ax0, ax1 = _xpair(x_sp, x_out)
        for idx, az in enumerate((0.36, 1.15, 1.94)):
            steel_parts.append(
                _add_box_bounds(
                    f"Frame_AnchorTab_{tag}_{idx}",
                    ax0,
                    ax1,
                    -0.055,
                    0.055,
                    az - 0.045,
                    az + 0.045,
                    bevel_width=0.0,
                )
            )
            steel_parts.append(
                _add_cylinder(
                    f"Frame_AnchorBolt_{tag}_{idx}",
                    radius=0.011,
                    depth=0.018,
                    location=(sign * (spine_outer_x + 0.009), 0.0, az),
                    vertices=6,
                    rotation_deg=(0.0, 90.0, 0.0),
                )
            )

    # Welded header lintel spanning clear opening & pocket X[-0.532, 0.532] at Z[2.16, 2.30]
    steel_parts.append(
        _add_box_bounds(
            "Frame_Header_FrontCasing",
            -pocket_x,
            pocket_x,
            -half_d,
            -0.125,
            clear_h + 0.020,
            FRAME_H,
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Frame_Header_RearStop",
            -clear_half_w,
            clear_half_w,
            0.032,
            half_d,
            clear_h,
            FRAME_H,
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Frame_Header_Web",
            -pocket_x,
            pocket_x,
            -0.125,
            0.032,
            clear_h + 0.020,
            FRAME_H - 0.020,
            bevel_width=0.0,
        )
    )
    # Threshold pocket corner returns closing bottom jamb step at Z[0.0, 0.020]
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        px0 = min(sign * clear_half_w, sign * pocket_x)
        px1 = max(sign * clear_half_w, sign * pocket_x)
        steel_parts.append(
            _add_box_bounds(
                f"Frame_Threshold_Corner_{tag}",
                px0,
                px1,
                -half_d,
                0.032,
                0.0,
                0.020,
                bevel_width=0.0,
            )
        )
    # Top header masonry anchor tabs
    for idx, hx in enumerate((-0.30, 0.30)):
        steel_parts.append(
            _add_box_bounds(
                f"Frame_Header_AnchorTab_{idx}",
                hx - 0.05,
                hx + 0.05,
                -0.055,
                0.055,
                FRAME_H - 0.020,
                FRAME_H,
                bevel_width=0.0,
            )
        )

    # Low bevelled steel threshold plate at Z=0..0.02m across clear opening
    thresh_profile = [
        (-half_d, 0.0),
        (half_d, 0.0),
        (0.135, 0.020),
        (-0.135, 0.020),
    ]
    thresh_stations = [
        (Vector((-clear_half_w, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, 1.0))),
        (Vector((clear_half_w, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, 1.0))),
    ]
    steel_parts.append(_add_swept_profile("Frame_Threshold_Plate", thresh_stations, thresh_profile))
    for r_idx, ry in enumerate((-0.075, 0.0, 0.075)):
        steel_parts.append(
            _add_box_bounds(
                f"Frame_Threshold_Rib_{r_idx}",
                -clear_half_w + 0.01,
                clear_half_w - 0.01,
                ry - 0.005,
                ry + 0.005,
                0.019,
                0.023,
                bevel_width=0.0,
            )
        )

    # 3 barrel hinge assemblies on left jamb (-X, matching door_exit hinge Zs)
    for idx, hz in enumerate(HINGE_ZS):
        # Hinge mounting leaf welded to left pocket jamb
        steel_parts.append(
            _add_box_bounds(
                f"Frame_HingePlate_{idx}",
                -pocket_x,
                -clear_half_w,
                -0.036,
                0.014,
                hz - 0.048,
                hz + 0.048,
                bevel_width=0.0,
            )
        )
        # Upper & lower barrel knuckles (leaving center gap for door leaf knuckle)
        for k_tag, dz in (("Bot", -0.032), ("Top", 0.032)):
            steel_parts.append(
                _add_cylinder(
                    f"Frame_HingeKnuckle_{idx}_{k_tag}",
                    radius=0.012,
                    depth=0.028,
                    location=(-clear_half_w + 0.002, -0.035, hz + dz),
                    vertices=8,
                )
            )
        # Hinge pin connecting knuckles
        steel_parts.append(
            _add_cylinder(
                f"Frame_HingePin_{idx}",
                radius=0.005,
                depth=0.096,
                location=(-clear_half_w + 0.002, -0.035, hz),
                vertices=6,
            )
        )

    # Striker pocket on right jamb (+X) at latch height Z=0.98m
    strike_z = 0.98
    steel_parts.append(
        _add_box_bounds(
            "Frame_Striker_PlateTop",
            clear_half_w,
            pocket_x,
            -0.030,
            0.030,
            strike_z + 0.032,
            strike_z + 0.085,
            bevel_width=0.0,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Frame_Striker_PlateBot",
            clear_half_w,
            pocket_x,
            -0.030,
            0.030,
            strike_z - 0.085,
            strike_z - 0.032,
            bevel_width=0.0,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Frame_Striker_PlateRear",
            clear_half_w,
            pocket_x,
            0.014,
            0.032,
            strike_z - 0.032,
            strike_z + 0.032,
            bevel_width=0.0,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Frame_Striker_Lip",
            clear_half_w - 0.006,
            pocket_x,
            -0.030,
            -0.014,
            strike_z - 0.032,
            strike_z + 0.032,
            bevel_width=0.0,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Frame_Striker_PocketBack",
            pocket_x - 0.008,
            pocket_x,
            -0.014,
            0.014,
            strike_z - 0.032,
            strike_z + 0.032,
            bevel_width=0.0,
        )
    )

    return _finalize_and_export(
        "door_exit_frame",
        [(mats["steel"], steel_parts, "BOX")],
        output_dir,
    )


def generate_door_exit(output_dir: Path) -> dict[str, object]:
    """Build 1.00m W x 2.15m H x 0.06m D industrial fire-exit leaf with wire-glass & panic bar."""
    clean_scene()
    mats = _create_materials()

    painted_parts: list[bpy.types.Object] = []
    steel_parts: list[bpy.types.Object] = []
    glass_parts: list[bpy.types.Object] = []

    half_w = DOOR_LEAF_W * 0.5  # 0.50m
    half_d = DOOR_LEAF_D * 0.5  # 0.03m
    stile_w = 0.08
    rail_h = 0.09
    inner_x = half_w - stile_w  # 0.42m
    top_rail_z0 = DOOR_LEAF_H - 0.10  # 2.05m

    # Vision slit bounds (0.16m W x 0.55m H at Z=1.35..1.90m, latch side +X)
    slit_x0, slit_x1 = 0.10, 0.26
    slit_z0, slit_z1 = 1.35, 1.90
    panel_half_d = 0.020  # Recessed 1cm relative to 0.06m perimeter frame

    # Slot 0: Recessed painted-steel panels framing the real vision slit cutout
    painted_parts.append(
        _add_box_bounds(
            "Door_Panel_Lower",
            -inner_x,
            inner_x,
            -panel_half_d,
            panel_half_d,
            rail_h,
            slit_z0,
            bevel_width=0.0,
        )
    )
    painted_parts.append(
        _add_box_bounds(
            "Door_Panel_TopStrip",
            -inner_x,
            inner_x,
            -panel_half_d,
            panel_half_d,
            slit_z1,
            top_rail_z0,
            bevel_width=0.0,
        )
    )
    painted_parts.append(
        _add_box_bounds(
            "Door_Panel_MidLeft",
            -inner_x,
            slit_x0,
            -panel_half_d,
            panel_half_d,
            slit_z0,
            slit_z1,
            bevel_width=0.0,
        )
    )
    painted_parts.append(
        _add_box_bounds(
            "Door_Panel_MidRight",
            slit_x1,
            inner_x,
            -panel_half_d,
            panel_half_d,
            slit_z0,
            slit_z1,
            bevel_width=0.0,
        )
    )

    # Slot 1: Steel perimeter frame stiles & rails (full 0.06m thickness)
    steel_parts.append(
        _add_box_bounds(
            "Door_Stile_Left",
            -half_w,
            -inner_x,
            -half_d,
            half_d,
            0.0,
            DOOR_LEAF_H,
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Door_Stile_Right",
            inner_x,
            half_w,
            -half_d,
            half_d,
            0.0,
            DOOR_LEAF_H,
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Door_Rail_Bottom",
            -inner_x,
            inner_x,
            -half_d,
            half_d,
            0.0,
            rail_h,
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Door_Rail_Top",
            -inner_x,
            inner_x,
            -half_d,
            half_d,
            top_rail_z0,
            DOOR_LEAF_H,
            bevel_width=0.004,
        )
    )

    # 0.25m steel kick-plate on both front & rear lower faces (Z=0.005..0.255m)
    for tag, y0, y1 in (("Front", -0.034, -0.020), ("Back", 0.020, 0.034)):
        steel_parts.append(
            _add_box_bounds(
                f"Door_KickPlate_{tag}",
                -0.46,
                0.46,
                y0,
                y1,
                0.005,
                0.255,
                bevel_width=0.002,
            )
        )

    # Bolted steel vision bezel around 0.16m x 0.55m cutout
    bezel_w = 0.026
    bez_x0, bez_x1 = slit_x0 - bezel_w, slit_x1 + bezel_w
    bez_z0, bez_z1 = slit_z0 - bezel_w, slit_z1 + bezel_w
    for tag, y0, y1 in (("Front", -0.032, -0.004), ("Back", 0.004, 0.032)):
        steel_parts.append(
            _add_box_bounds(f"Door_Bezel_{tag}_Top", bez_x0, bez_x1, y0, y1, slit_z1, bez_z1, 0.002)
        )
        steel_parts.append(
            _add_box_bounds(f"Door_Bezel_{tag}_Bot", bez_x0, bez_x1, y0, y1, bez_z0, slit_z0, 0.002)
        )
        steel_parts.append(
            _add_box_bounds(f"Door_Bezel_{tag}_Left", bez_x0, slit_x0, y0, y1, slit_z0, slit_z1, 0.002)
        )
        steel_parts.append(
            _add_box_bounds(f"Door_Bezel_{tag}_Right", slit_x1, bez_x1, y0, y1, slit_z0, slit_z1, 0.002)
        )
        bolt_y = y0 - 0.002 if y0 < 0.0 else y1 + 0.002
        for bx in (bez_x0 + 0.013, bez_x1 - 0.013):
            for bz in (bez_z0 + 0.013, 1.625, bez_z1 - 0.013):
                steel_parts.append(
                    _add_box(
                        f"Door_BezelBolt_{tag}",
                        (0.008, 0.004, 0.008),
                        (bx, bolt_y, bz),
                        bevel_width=0.0,
                    )
                )

    # Wire-glass internal steel mesh ribs inside vision slit
    steel_parts.append(
        _add_box_bounds(
            "Door_WireMesh_Vert",
            0.178,
            0.182,
            -0.005,
            0.005,
            slit_z0,
            slit_z1,
            bevel_width=0.0,
        )
    )
    for wz in (1.48, 1.625, 1.77):
        steel_parts.append(
            _add_box_bounds(
                "Door_WireMesh_Horiz",
                slit_x0,
                slit_x1,
                -0.005,
                0.005,
                wz - 0.002,
                wz + 0.002,
                bevel_width=0.0,
            )
        )

    # Interior horizontal panic crash-bar (+Y interior face at Z=0.98m)
    panic_z = 0.98
    steel_parts.append(
        _add_box_bounds(
            "Door_Panic_HingeMount",
            -0.425,
            -0.355,
            0.020,
            0.050,
            panic_z - 0.055,
            panic_z + 0.055,
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box_bounds(
            "Door_Panic_LatchBox",
            0.345,
            0.445,
            0.020,
            0.056,
            panic_z - 0.070,
            panic_z + 0.070,
            bevel_width=0.004,
        )
    )
    for sx in (-0.36, 0.36):
        steel_parts.append(
            _add_box_bounds(
                "Door_Panic_Arm",
                sx - 0.014,
                sx + 0.014,
                0.048,
                0.088,
                panic_z - 0.018,
                panic_z + 0.018,
                bevel_width=0.003,
            )
        )
    steel_parts.append(
        _add_box_bounds(
            "Door_Panic_CrashBar",
            -0.375,
            0.375,
            0.076,
            0.102,
            panic_z - 0.025,
            panic_z + 0.025,
            bevel_width=0.005,
        )
    )

    # Exterior pull handle + lock cylinder (-Y exterior face)
    pull_x = 0.39
    steel_parts.append(
        _add_box_bounds(
            "Door_Pull_Escutcheon",
            pull_x - 0.032,
            pull_x + 0.032,
            -0.036,
            -0.020,
            0.84,
            1.15,
            bevel_width=0.003,
        )
    )
    for sz in (0.89, 1.05):
        steel_parts.append(
            _add_box_bounds(
                "Door_Pull_Standoff",
                pull_x - 0.010,
                pull_x + 0.010,
                -0.082,
                -0.035,
                sz - 0.010,
                sz + 0.010,
                bevel_width=0.002,
            )
        )
    steel_parts.append(
        _add_box_bounds(
            "Door_Pull_Grip",
            pull_x - 0.012,
            pull_x + 0.012,
            -0.090,
            -0.068,
            0.875,
            1.065,
            bevel_width=0.005,
        )
    )
    steel_parts.append(
        _add_cylinder(
            "Door_Lock_Cylinder",
            radius=0.015,
            depth=0.014,
            location=(pull_x, -0.041, 1.105),
            vertices=10,
            rotation_deg=(90.0, 0.0, 0.0),
        )
    )

    # 3 left hinge knuckles (-X edge, interlocking with door_exit_frame knuckles)
    for idx, hz in enumerate(HINGE_ZS):
        steel_parts.append(
            _add_box_bounds(
                f"Door_HingeLeaf_{idx}",
                -half_w,
                -half_w + 0.012,
                -0.034,
                0.010,
                hz - 0.042,
                hz + 0.042,
                bevel_width=0.002,
            )
        )
        steel_parts.append(
            _add_cylinder(
                f"Door_HingeKnuckle_{idx}",
                radius=0.012,
                depth=0.032,
                location=(-half_w - 0.008, -0.035, hz),
                vertices=10,
            )
        )

    # Slot 2: Wire-glass vision slit pane (0.16m W x 0.55m H)
    glass_parts.append(
        _add_box_bounds(
            "Door_Vision_Glass",
            slit_x0,
            slit_x1,
            -0.003,
            0.003,
            slit_z0,
            slit_z1,
            bevel_width=0.0,
        )
    )

    return _finalize_and_export(
        "door_exit",
        [
            (mats["painted_metal"], painted_parts, "BOX"),
            (mats["steel"], steel_parts, "BOX"),
            (mats["glass"], glass_parts, "BOX"),
        ],
        output_dir,
    )


def _build_top_steel_beam(prefix: str) -> list[bpy.types.Object]:
    """Build shared 4.0m top steel I-beam lip matching factory_garage_shell_kit.py."""
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
                    bevel_width=0.0,
                )
            )
    return parts


def _slat_point(
    t: float,
    z_left: float,
    z_right: float,
    max_bow_y: float,
    x_pull_right: float,
    x_half_base: float = 1.515,
) -> Vector:
    """Compute deformed centerline point along a buckled/derailed lower shutter slat."""
    x_left = -x_half_base
    x_right = x_half_base - x_pull_right
    x = x_left + (x_right - x_left) * t
    z = z_left + (z_right - z_left) * t + 0.015 * math.sin(math.pi * t)
    y = -max_bow_y * (t ** 1.65) - 0.018 * math.sin(math.pi * t * 2.0) * t
    return Vector((x, y, z))


def _build_curved_slat(
    name: str,
    z_left: float,
    z_right: float,
    max_bow_y: float,
    x_pull_right: float,
    slat_h: float,
    slat_t: float,
    segments: int = 6,
    twist_right_deg: float = 0.0,
) -> bpy.types.Object:
    """Build a 6-segment bowed/skewed rectangular slat rail."""
    half_t = slat_t * 0.5
    half_h = slat_h * 0.5
    profile = [
        (-half_t, -half_h),
        (half_t, -half_h),
        (half_t, half_h),
        (-half_t, half_h),
    ]
    stations: list[tuple[Vector, Vector, Vector]] = []
    for i in range(segments + 1):
        t = float(i) / float(segments)
        pt = _slat_point(t, z_left, z_right, max_bow_y, x_pull_right)
        t_prev = max(0.0, t - 0.02)
        t_next = min(1.0, t + 0.02)
        tangent = (
            _slat_point(t_next, z_left, z_right, max_bow_y, x_pull_right)
            - _slat_point(t_prev, z_left, z_right, max_bow_y, x_pull_right)
        ).normalized()
        up = Vector((0.0, 0.0, 1.0))
        y_dir = up.cross(tangent).normalized()
        z_dir = tangent.cross(y_dir).normalized()
        if abs(twist_right_deg) > 1e-4:
            ang = math.radians(twist_right_deg * (t ** 1.4))
            ca, sa = math.cos(ang), math.sin(ang)
            y_rot = y_dir * ca + z_dir * sa
            z_rot = -y_dir * sa + z_dir * ca
            y_dir, z_dir = y_rot, z_rot
        stations.append((pt, y_dir, z_dir))
    return _add_swept_profile(name, stations, profile)


def generate_shutter_perforated_broken(output_dir: Path) -> dict[str, object]:
    """Build 4.0m x 4.0m x 0.35m garage bay with pried, real-geometry perforated rolling shutter."""
    clean_scene()
    mats = _create_materials()

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

    # Steel jamb frames & crisp U-channel guide tracks (Z[0.0, 3.10])
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Bay_Jamb_{tag}",
                (JAMB_WIDTH, WALL_THICK, GARAGE_CLEAR_H),
                (sign * (half_clear_w + JAMB_WIDTH * 0.5), 0.0, GARAGE_CLEAR_H * 0.5),
                bevel_width=0.005,
            )
        )
        for side_tag, y_off in (("F", 0.068), ("B", -0.068)):
            steel_parts.append(
                _add_box(
                    f"Bay_GuideLip_{tag}_{side_tag}",
                    (0.032, 0.028, GARAGE_CLEAR_H),
                    (sign * (half_clear_w + 0.016), y_off, GARAGE_CLEAR_H * 0.5),
                    bevel_width=0.0,
                )
            )

    # Steel lintel angle beams (Z[3.10, 3.22])
    for side_tag, y_off in (("F", 0.115), ("B", -0.115)):
        steel_parts.append(
            _add_box(
                f"Bay_Lintel_{side_tag}",
                (GARAGE_CLEAR_W + 0.28, 0.13, 0.12),
                (0.0, y_off, GARAGE_CLEAR_H + 0.06),
                bevel_width=0.005,
            )
        )

    # Roller drum housing hood (Z[3.22, 3.70]) + bolted end plates
    drum_z_min = lintel_top_z
    drum_top_h = 0.06
    drum_panel_h = DRUM_BOX_H - drum_top_h
    drum_panel_cz = drum_z_min + drum_panel_h * 0.5
    drum_cz = drum_z_min + DRUM_BOX_H * 0.5
    drum_w = GARAGE_CLEAR_W + 0.24
    drum_d = WALL_THICK + 0.12  # 0.47m
    for side_tag, y_off in (("F", drum_d * 0.5 - 0.035), ("B", -drum_d * 0.5 + 0.035)):
        steel_parts.append(
            _add_box(
                f"Bay_DrumHood_{side_tag}",
                (drum_w, 0.07, drum_panel_h),
                (0.0, y_off, drum_panel_cz),
                bevel_width=0.006,
            )
        )
    steel_parts.append(
        _add_box(
            "Bay_DrumHood_Top",
            (drum_w, drum_d, drum_top_h),
            (0.0, 0.0, drum_z_min + DRUM_BOX_H - drum_top_h * 0.5),
            bevel_width=0.006,
        )
    )
    for tag, sign in (("L", -1.0), ("R", 1.0)):
        steel_parts.append(
            _add_box(
                f"Bay_DrumEndPlate_{tag}",
                (0.05, drum_d + 0.02, DRUM_BOX_H + 0.04),
                (sign * (drum_w * 0.5 - 0.01), 0.0, drum_cz),
                bevel_width=0.005,
            )
        )

    # Hoist sprocket box + wall cleat + interlocking steel pull chain on left jamb
    chain_x, chain_y = -1.44, -0.105
    steel_parts.append(
        _add_box(
            "Bay_Hoist_SprocketBox",
            (0.11, 0.09, 0.14),
            (chain_x, chain_y, 3.19),
            bevel_width=0.004,
        )
    )
    steel_parts.append(
        _add_box(
            "Bay_Hoist_WallCleat",
            (0.08, 0.05, 0.05),
            (-1.48, -0.105, 1.38),
            bevel_width=0.002,
        )
    )
    for idx in range(16):
        lz = 3.07 - idx * 0.112
        rot_z = 0.0 if idx % 2 == 0 else 90.0
        steel_parts.append(
            _add_box(
                f"Bay_PullChain_Link_{idx}",
                (0.028, 0.016, 0.122),
                (chain_x, chain_y, lz),
                bevel_width=0.0,
                rotation_deg=(0.0, 0.0, rot_z),
            )
        )

    # Real-geometry perforated metal rolling shutter curtain (Slot 2: corrugated_metal)
    corrugated_parts: list[bpy.types.Object] = []
    # Coiled roller drum cylinder inside housing throat
    corrugated_parts.append(
        _add_cylinder(
            "Bay_Shutter_RolledCoil",
            radius=0.14,
            depth=GARAGE_CLEAR_W + 0.02,
            location=(0.0, 0.0, drum_z_min + 0.15),
            vertices=12,
            rotation_deg=(0.0, 90.0, 0.0),
        )
    )

    slat_w = GARAGE_CLEAR_W + 0.03  # 3.03m seated inside tracks
    slat_h = 0.064
    slot_h = 0.056
    pitch = slat_h + slot_h  # 0.12m
    slat_t = 0.022
    rib_w = 0.044
    rib_t = 0.016

    even_ribs_x = (-1.36, -0.91, -0.45, 0.0, 0.45, 0.91, 1.36)
    odd_ribs_x = (-1.48, -1.14, -0.68, -0.23, 0.23, 0.68, 1.14, 1.48)

    # Upper 11 intact straight perforated rows (Z=3.15 down to Z=1.95)
    upper_rows = 11
    z_top_start = 3.15
    upper_bot_cz = 0.0
    for r in range(upper_rows):
        cz = z_top_start - slat_h * 0.5 - r * pitch
        upper_bot_cz = cz
        corrugated_parts.append(
            _add_box(
                f"Shutter_UpperRail_{r}",
                (slat_w, slat_t, slat_h),
                (0.0, 0.0, cz),
                bevel_width=0.0,
            )
        )
        # Vertical bridge ribs spanning open perforation slot below this rail
        if r < upper_rows - 1:
            rib_cz = cz - pitch * 0.5
            rib_xs = even_ribs_x if r % 2 == 0 else odd_ribs_x
            for rx in rib_xs:
                corrugated_parts.append(
                    _add_box(
                        f"Shutter_UpperRib_{r}",
                        (rib_w, rib_t, slot_h + 0.008),
                        (rx, 0.0, rib_cz),
                        bevel_width=0.0,
                    )
                )

    # Lower 4 buckled/skewed/derailed slats (bowing forward toward -Y & pulled out of right track)
    # Row specs: (z_left, z_right, max_bow_y, x_pull_right)
    lower_specs = [
        (1.79, 1.83, 0.075, 0.018),
        (1.66, 1.75, 0.145, 0.040),
        (1.53, 1.67, 0.205, 0.060),
        (1.39, 1.59, 0.240, 0.080),
    ]
    prev_spec = (upper_bot_cz, upper_bot_cz, 0.0, 0.0)
    for r_idx, (zl, zr, bow, pull) in enumerate(lower_specs):
        corrugated_parts.append(
            _build_curved_slat(
                f"Shutter_BuckledRail_{r_idx}",
                z_left=zl,
                z_right=zr,
                max_bow_y=bow,
                x_pull_right=pull,
                slat_h=0.062,
                slat_t=slat_t,
                segments=6,
                twist_right_deg=3.5 * (r_idx + 1),
            )
        )
        # Bridge ribs connecting previous rail to this buckled rail across the open slot
        rib_xs = even_ribs_x if (upper_rows - 1 + r_idx) % 2 == 0 else odd_ribs_x
        p_zl, p_zr, p_bow, p_pull = prev_spec
        for rx in rib_xs:
            # Skip last right rib on lowest rows to show torn edge breakage
            if r_idx >= 2 and rx > 1.30:
                continue
            t_param = (rx + 1.515) / 3.03
            top_pt = _slat_point(t_param, p_zl - 0.025, p_zr - 0.025, p_bow, p_pull)
            bot_pt = _slat_point(t_param, zl + 0.025, zr + 0.025, bow, pull)
            mid_pt = (top_pt + bot_pt) * 0.5
            diff = top_pt - bot_pt
            seg_len = diff.length
            quat = diff.normalized().to_track_quat("Z", "Y")
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=tuple(mid_pt))
            rib_obj = bpy.context.active_object
            rib_obj.name = f"Shutter_BuckledRib_{r_idx}"
            rib_obj.scale = (rib_w, rib_t, seg_len)
            rib_obj.rotation_mode = "QUATERNION"
            rib_obj.rotation_quaternion = quat
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
            corrugated_parts.append(rib_obj)
        prev_spec = (zl, zr, bow, pull)

    # Twisted steel T-bar bottom edge (skewed Z=1.24m left -> Z=1.54m right, leaving >=1.10m gap)
    tbar_zl, tbar_zr, tbar_bow, tbar_pull = 1.24, 1.54, 0.250, 0.090
    steel_parts.append(
        _build_curved_slat(
            "Shutter_TwistedTBar_Web",
            z_left=tbar_zl + 0.015,
            z_right=tbar_zr + 0.015,
            max_bow_y=tbar_bow,
            x_pull_right=tbar_pull,
            slat_h=0.055,
            slat_t=0.024,
            segments=6,
            twist_right_deg=18.0,
        )
    )
    steel_parts.append(
        _build_curved_slat(
            "Shutter_TwistedTBar_Flange",
            z_left=tbar_zl - 0.012,
            z_right=tbar_zr - 0.012,
            max_bow_y=tbar_bow,
            x_pull_right=tbar_pull,
            slat_h=0.022,
            slat_t=0.068,
            segments=6,
            twist_right_deg=18.0,
        )
    )
    # Connect bottom buckled slat to twisted T-bar with surviving ribs
    for rx in (-1.36, -0.91, -0.45, 0.0, 0.45, 0.91):
        t_param = (rx + 1.515) / 3.03
        top_pt = _slat_point(t_param, 1.39 - 0.025, 1.59 - 0.025, 0.240, 0.080)
        bot_pt = _slat_point(t_param, tbar_zl + 0.03, tbar_zr + 0.03, tbar_bow, tbar_pull)
        mid_pt = (top_pt + bot_pt) * 0.5
        diff = top_pt - bot_pt
        quat = diff.normalized().to_track_quat("Z", "Y")
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=tuple(mid_pt))
        rib_obj = bpy.context.active_object
        rib_obj.name = "Shutter_TBar_BridgeRib"
        rib_obj.scale = (rib_w, rib_t, diff.length)
        rib_obj.rotation_mode = "QUATERNION"
        rib_obj.rotation_quaternion = quat
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        corrugated_parts.append(rib_obj)

    # Twisted T-bar lift handle near pry point on right half
    handle_pt = _slat_point(0.68, tbar_zl + 0.01, tbar_zr + 0.01, tbar_bow, tbar_pull)
    steel_parts.append(
        _add_box(
            "Shutter_Twisted_Handle",
            (0.22, 0.048, 0.032),
            (handle_pt.x, handle_pt.y - 0.038, handle_pt.z + 0.01),
            bevel_width=0.003,
            rotation_deg=(12.0, -9.0, 8.0),
        )
    )

    # 1 dangling bent slat hanging off right-side hinge/rib (tip stays >= 1.15m for crouch clearance)
    dangle_pts = [
        Vector((0.46, -0.175, 1.43)),
        Vector((0.76, -0.215, 1.33)),
        Vector((1.05, -0.250, 1.22)),
        Vector((1.35, -0.258, 1.17)),
    ]
    dangle_profile = [(-0.011, -0.030), (0.011, -0.030), (0.011, 0.030), (-0.011, 0.030)]
    dangle_stations: list[tuple[Vector, Vector, Vector]] = []
    for idx, pt in enumerate(dangle_pts):
        p_prev = dangle_pts[max(0, idx - 1)]
        p_next = dangle_pts[min(len(dangle_pts) - 1, idx + 1)]
        tang = (p_next - p_prev).normalized()
        up = Vector((0.0, 0.0, 1.0))
        y_dir = up.cross(tang).normalized()
        z_dir = tang.cross(y_dir).normalized()
        ang = math.radians(10.0 * idx)
        ca, sa = math.cos(ang), math.sin(ang)
        dangle_stations.append((pt, y_dir * ca + z_dir * sa, -y_dir * sa + z_dir * ca))
    corrugated_parts.append(
        _add_swept_profile("Shutter_Dangling_BentSlat", dangle_stations, dangle_profile)
    )
    corrugated_parts.append(
        _add_strut(
            "Shutter_Dangling_Tab",
            (0.47, -0.165, 1.49),
            (0.49, -0.175, 1.43),
            width_y=0.016,
            thick_z=0.040,
            bevel_width=0.0,
        )
    )

    return _finalize_and_export(
        "shutter_perforated_broken",
        [
            (mats["concrete"], concrete_parts, "BOX"),
            (mats["steel"], steel_parts, "BOX"),
            (mats["corrugated_metal"], corrugated_parts, "XZ"),
        ],
        output_dir,
    )


def main() -> None:
    """Entry point for Blender headless generation of all 3 entry & shutter assets."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        output_dir = sdk_root / "assets" / "models" / "factory_shells"
        generate_door_exit_frame(output_dir)
        generate_door_exit(output_dir)
        generate_shutter_perforated_broken(output_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
