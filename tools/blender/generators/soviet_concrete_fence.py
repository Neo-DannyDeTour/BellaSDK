"""Procedural Blender generator for a single PO-2 Soviet precast concrete fence section.

Creates a modular 4.0m x 2.5m double-sided diamond-waffle PO-2 concrete fence
panel with lower plinth, two tapered concrete footing blocks, and rebar lifting
loops, with Godot 4 -colonly box collision and clean metric UVs.
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
from common.collisions import create_box_collision
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material


# Panel dimensions (meters)
PANEL_WIDTH = 4.0
PANEL_HEIGHT = 2.5
PANEL_THICK = 0.16

PLINTH_HEIGHT = 0.52
SILL_HEIGHT = 0.16
FRAME_SIDE_W = 0.14
FRAME_TOP_H = 0.12
BACKING_THICK = 0.06

WAFFLE_COLS = 6
WAFFLE_ROWS = 3
PYRAMID_DEPTH = 0.045  # protrudes from +/-0.03 to +/-0.075

FOOT_X_OFFSET = 1.80
FOOT_HEIGHT = 0.42
FOOT_BOT_X = 0.44
FOOT_BOT_Y = 0.60
FOOT_TOP_X = 0.32
FOOT_TOP_Y = 0.38


def _add_box(
    name: str,
    size: tuple[float, float, float],
    location: tuple[float, float, float],
    bevel_width: float = 0.008,
) -> bpy.types.Object:
    """Create a scaled cube with optional bevel."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel_width > 0.0:
        bev = obj.modifiers.new(name="Bevel", type="BEVEL")
        bev.width = bevel_width
        bev.segments = 1
        bev.limit_method = "ANGLE"
        bev.angle_limit = math.radians(30.0)
    return obj


def _add_trapezoid_footing(name: str, x_pos: float) -> bpy.types.Object:
    """Create a tapered trapezoidal concrete footing block grounded at z=0."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bx = FOOT_BOT_X * 0.5
    by = FOOT_BOT_Y * 0.5
    tx = FOOT_TOP_X * 0.5
    ty = FOOT_TOP_Y * 0.5
    h = FOOT_HEIGHT

    v0 = bm.verts.new((-bx, -by, 0.0))
    v1 = bm.verts.new((bx, -by, 0.0))
    v2 = bm.verts.new((bx, by, 0.0))
    v3 = bm.verts.new((-bx, by, 0.0))

    v4 = bm.verts.new((-tx, -ty, h))
    v5 = bm.verts.new((tx, -ty, h))
    v6 = bm.verts.new((tx, ty, h))
    v7 = bm.verts.new((-tx, ty, h))

    bm.faces.new((v3, v2, v1, v0))
    bm.faces.new((v4, v5, v6, v7))
    bm.faces.new((v0, v1, v5, v4))
    bm.faces.new((v1, v2, v6, v5))
    bm.faces.new((v2, v3, v7, v6))
    bm.faces.new((v3, v0, v4, v7))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    obj.location = (x_pos, 0.0, 0.0)
    bev = obj.modifiers.new(name="Bevel", type="BEVEL")
    bev.width = 0.012
    bev.segments = 1
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(25.0)
    return obj


def _add_waffle_grid(name: str) -> bpy.types.Object:
    """Build 3x6 double-sided truncated-pyramid waffle bosses in a single mesh."""
    mesh = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    field_w = PANEL_WIDTH - 2.0 * FRAME_SIDE_W
    field_z_min = PLINTH_HEIGHT + SILL_HEIGHT
    field_z_max = PANEL_HEIGHT - FRAME_TOP_H
    field_h = field_z_max - field_z_min

    cell_w = field_w / WAFFLE_COLS
    cell_h = field_h / WAFFLE_ROWS

    base_half_w = cell_w * 0.485
    base_half_h = cell_h * 0.485
    top_half_w = cell_w * 0.21
    top_half_h = cell_h * 0.21

    y_base = BACKING_THICK * 0.5
    y_top = y_base + PYRAMID_DEPTH

    bm = bmesh.new()

    for side in (1.0, -1.0):
        yb = side * y_base
        yt = side * y_top
        for row in range(WAFFLE_ROWS):
            cz = field_z_min + (row + 0.5) * cell_h
            for col in range(WAFFLE_COLS):
                cx = -field_w * 0.5 + (col + 0.5) * cell_w

                b0 = bm.verts.new((cx - base_half_w, yb, cz - base_half_h))
                b1 = bm.verts.new((cx + base_half_w, yb, cz - base_half_h))
                b2 = bm.verts.new((cx + base_half_w, yb, cz + base_half_h))
                b3 = bm.verts.new((cx - base_half_w, yb, cz + base_half_h))

                t0 = bm.verts.new((cx - top_half_w, yt, cz - top_half_h))
                t1 = bm.verts.new((cx + top_half_w, yt, cz - top_half_h))
                t2 = bm.verts.new((cx + top_half_w, yt, cz + top_half_h))
                t3 = bm.verts.new((cx - top_half_w, yt, cz + top_half_h))

                if side > 0.0:
                    # +Y face: outward normal points +Y
                    bm.faces.new((t3, t2, t1, t0))
                    bm.faces.new((b0, b1, t1, t0))
                    bm.faces.new((b1, b2, t2, t1))
                    bm.faces.new((b2, b3, t3, t2))
                    bm.faces.new((b3, b0, t0, t3))
                else:
                    # -Y face: outward normal points -Y
                    bm.faces.new((t0, t1, t2, t3))
                    bm.faces.new((t0, t1, b1, b0))
                    bm.faces.new((t1, t2, b2, b1))
                    bm.faces.new((t2, t3, b3, b2))
                    bm.faces.new((t3, t0, b0, b3))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    return obj


def _add_rebar_loop(
    name: str,
    location: tuple[float, float, float],
    width: float = 0.09,
    height: float = 0.055,
    radius: float = 0.008,
    rotate_z_deg: float = 0.0,
) -> bpy.types.Object:
    """Create a low-poly inverted-U rebar lifting loop."""
    curve_data = bpy.data.curves.new(name=f"{name}_Curve", type="CURVE")
    curve_data.dimensions = "3D"
    curve_data.bevel_depth = radius
    curve_data.bevel_resolution = 1

    spline = curve_data.splines.new("POLY")
    half_w = width * 0.5
    pts = [
        (-half_w, 0.0, -0.015),
        (-half_w, 0.0, height * 0.65),
        (-half_w * 0.55, 0.0, height),
        (half_w * 0.55, 0.0, height),
        (half_w, 0.0, height * 0.65),
        (half_w, 0.0, -0.015),
    ]
    spline.points.add(len(pts) - 1)
    for idx, (px, py, pz) in enumerate(pts):
        spline.points[idx].co = (px, py, pz, 1.0)

    curve_obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(curve_obj)
    curve_obj.location = location
    curve_obj.rotation_euler = (0.0, 0.0, math.radians(rotate_z_deg))

    bpy.ops.object.select_all(action="DESELECT")
    curve_obj.select_set(True)
    bpy.context.view_layer.objects.active = curve_obj
    bpy.ops.object.convert(target="MESH")
    return bpy.context.active_object


def _apply_box_uvs(obj: bpy.types.Object, tile_meters: float = 2.0) -> None:
    """Generate clean world-metric cubic box UVs so PBR concrete tiles seamlessly."""
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


def generate_soviet_concrete_fence(output_dir: Path) -> Path:
    """Build and export the PO-2 Soviet concrete fence GLB and .blend."""
    clean_scene()

    concrete_mat = create_pbr_material(
        name="Mat_PO2_Concrete",
        base_color=(0.45, 0.45, 0.44, 1.0),
        metallic=0.0,
        roughness=0.88,
    )
    rebar_mat = create_pbr_material(
        name="Mat_Rebar_Steel",
        base_color=(0.18, 0.12, 0.09, 1.0),
        metallic=0.75,
        roughness=0.65,
    )

    concrete_parts: list[bpy.types.Object] = []

    # 1. Lower base plinth (0.0 -> 0.52m)
    plinth = _add_box(
        "Fence_Plinth",
        (PANEL_WIDTH, PANEL_THICK * 0.94, PLINTH_HEIGHT),
        (0.0, 0.0, PLINTH_HEIGHT * 0.5),
        bevel_width=0.008,
    )
    concrete_parts.append(plinth)

    # 2. Horizontal sill above plinth
    sill = _add_box(
        "Fence_Sill",
        (PANEL_WIDTH - 2.0 * FRAME_SIDE_W, PANEL_THICK * 0.92, SILL_HEIGHT),
        (0.0, 0.0, PLINTH_HEIGHT + SILL_HEIGHT * 0.5),
        bevel_width=0.008,
    )
    concrete_parts.append(sill)

    # 3. Outer frame: left, right, top
    upper_h = PANEL_HEIGHT - PLINTH_HEIGHT
    upper_center_z = PLINTH_HEIGHT + upper_h * 0.5
    left_post = _add_box(
        "Fence_Frame_Left",
        (FRAME_SIDE_W, PANEL_THICK, upper_h),
        (-PANEL_WIDTH * 0.5 + FRAME_SIDE_W * 0.5, 0.0, upper_center_z),
        bevel_width=0.008,
    )
    right_post = _add_box(
        "Fence_Frame_Right",
        (FRAME_SIDE_W, PANEL_THICK, upper_h),
        (PANEL_WIDTH * 0.5 - FRAME_SIDE_W * 0.5, 0.0, upper_center_z),
        bevel_width=0.008,
    )
    top_beam = _add_box(
        "Fence_Frame_Top",
        (PANEL_WIDTH - 2.0 * FRAME_SIDE_W, PANEL_THICK, FRAME_TOP_H),
        (0.0, 0.0, PANEL_HEIGHT - FRAME_TOP_H * 0.5),
        bevel_width=0.008,
    )
    concrete_parts.extend([left_post, right_post, top_beam])

    # 4. Recessed backing slab inside upper frame
    field_w = PANEL_WIDTH - 2.0 * FRAME_SIDE_W
    field_z_min = PLINTH_HEIGHT + SILL_HEIGHT
    field_z_max = PANEL_HEIGHT - FRAME_TOP_H
    field_h = field_z_max - field_z_min
    backing = _add_box(
        "Fence_Backing",
        (field_w, BACKING_THICK, field_h),
        (0.0, 0.0, field_z_min + field_h * 0.5),
        bevel_width=0.0,
    )
    concrete_parts.append(backing)

    # 5. Double-sided 3x6 diamond waffle relief
    waffle = _add_waffle_grid("Fence_Waffle_Grid")
    concrete_parts.append(waffle)

    # 6. Two tapered end footing blocks
    foot_left = _add_trapezoid_footing("Fence_Footing_L", -FOOT_X_OFFSET)
    foot_right = _add_trapezoid_footing("Fence_Footing_R", FOOT_X_OFFSET)
    concrete_parts.extend([foot_left, foot_right])

    # Apply modifiers on concrete parts before joining
    for part in concrete_parts:
        bpy.context.view_layer.objects.active = part
        for mod in list(part.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        assign_material(part, concrete_mat)

    # 7. Rebar lifting loops (top corners + footing shoulders)
    rebar_parts: list[bpy.types.Object] = [
        _add_rebar_loop("Rebar_Top_L", (-PANEL_WIDTH * 0.5 + 0.16, 0.0, PANEL_HEIGHT)),
        _add_rebar_loop("Rebar_Top_R", (PANEL_WIDTH * 0.5 - 0.16, 0.0, PANEL_HEIGHT)),
        _add_rebar_loop(
            "Rebar_Foot_L_Front",
            (-FOOT_X_OFFSET, FOOT_TOP_Y * 0.36, FOOT_HEIGHT),
            width=0.07,
            height=0.045,
            radius=0.007,
            rotate_z_deg=90.0,
        ),
        _add_rebar_loop(
            "Rebar_Foot_L_Back",
            (-FOOT_X_OFFSET, -FOOT_TOP_Y * 0.36, FOOT_HEIGHT),
            width=0.07,
            height=0.045,
            radius=0.007,
            rotate_z_deg=90.0,
        ),
        _add_rebar_loop(
            "Rebar_Foot_R_Front",
            (FOOT_X_OFFSET, FOOT_TOP_Y * 0.36, FOOT_HEIGHT),
            width=0.07,
            height=0.045,
            radius=0.007,
            rotate_z_deg=90.0,
        ),
        _add_rebar_loop(
            "Rebar_Foot_R_Back",
            (FOOT_X_OFFSET, -FOOT_TOP_Y * 0.36, FOOT_HEIGHT),
            width=0.07,
            height=0.045,
            radius=0.007,
            rotate_z_deg=90.0,
        ),
    ]
    for r_part in rebar_parts:
        assign_material(r_part, rebar_mat)

    # Join all visual parts into a single multi-material mesh
    all_parts = concrete_parts + rebar_parts
    bpy.ops.object.select_all(action="DESELECT")
    for part in all_parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = concrete_parts[0]
    bpy.ops.object.join()

    fence_obj = bpy.context.active_object
    fence_obj.name = "soviet_concrete_fence"

    # Compute world-metric box UVs
    _apply_box_uvs(fence_obj, tile_meters=2.0)

    # Print triangle count for verification
    tri_count = sum(max(1, len(p.vertices) - 2) for p in fence_obj.data.polygons)
    print(f"[soviet_concrete_fence] Total triangles: {tri_count}")

    # Create Godot 4 -colonly bounding box collision
    create_box_collision(fence_obj, suffix="-colonly")

    output_path = output_dir / "soviet_concrete_fence.glb"
    export_godot_glb(
        filepath=output_path,
        export_animations=False,
        apply_modifiers=True,
        save_blend=True,
    )
    return output_path


def main() -> None:
    """Entry point for tools/blender/run.py."""
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        assets_dir = sdk_root / "assets" / "models" / "soviet_concrete_fence"
        generate_soviet_concrete_fence(assets_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
