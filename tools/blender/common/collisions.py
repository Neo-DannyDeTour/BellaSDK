"""Godot 4 physics collision generator utilities."""

from __future__ import annotations

import mathutils
import bpy


def create_box_collision(
    target_obj: bpy.types.Object,
    suffix: str = "-colonly",
    padding: float = 0.0,
) -> bpy.types.Object:
    """Create a box collision proxy matching the bounding box of target_obj.

    Godot automatically detects the '-colonly' suffix and converts it into a
    StaticBody3D + Box CollisionShape3D without rendering the proxy mesh.
    """
    matrix_world = target_obj.matrix_world
    bbox_corners = [matrix_world @ mathutils.Vector(corner) for corner in target_obj.bound_box]

    min_x = min(v.x for v in bbox_corners) - padding
    max_x = max(v.x for v in bbox_corners) + padding
    min_y = min(v.y for v in bbox_corners) - padding
    max_y = max(v.y for v in bbox_corners) + padding
    min_z = min(v.z for v in bbox_corners) - padding
    max_z = max(v.z for v in bbox_corners) + padding

    size_x = max_x - min_x
    size_y = max_y - min_y
    size_z = max_z - min_z
    center = mathutils.Vector(
        ((min_x + max_x) * 0.5, (min_y + max_y) * 0.5, (min_z + max_z) * 0.5)
    )

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    col_obj = bpy.context.active_object
    col_obj.name = f"{target_obj.name}{suffix}"
    col_obj.scale = (size_x, size_y, size_z)

    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Display as wireframe in Blender viewport so it never obscures the visual mesh
    col_obj.display_type = "WIRE"
    col_obj.hide_render = True
    return col_obj


def create_convex_collision(
    target_obj: bpy.types.Object,
    suffix: str = "-convcolonly",
) -> bpy.types.Object:
    """Create a convex hull collision mesh from target_obj."""
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="DESELECT")
    target_obj.select_set(True)
    bpy.context.view_layer.objects.active = target_obj

    bpy.ops.object.duplicate(linked=False)
    dup = bpy.context.active_object
    dup.name = f"{target_obj.name}{suffix}"

    dup.data.materials.clear()

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.convex_hull()
    bpy.ops.object.mode_set(mode="OBJECT")

    # Display as wireframe in Blender viewport so it never obscures the visual mesh
    dup.display_type = "WIRE"
    dup.hide_render = True
    return dup
