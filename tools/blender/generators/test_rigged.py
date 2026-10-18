"""Generator for a rigged, animated asset with multiple Godot 4 action tracks."""

from __future__ import annotations

import math
import sys
from pathlib import Path

# Add tools/blender to sys.path so common utilities are importable
_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bpy
from common.armature import (
    add_bone,
    create_action,
    create_armature,
    push_action_to_nla,
)
from common.collisions import create_box_collision
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material


def generate_dev_totem(output_dir: Path) -> Path:
    clean_scene()

    # ---------------------------------------------------------
    # 1. Geometry & Materials
    # ---------------------------------------------------------
    # Base pedestal
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=8,
        radius=0.6,
        depth=0.4,
        location=(0, 0, 0.2),
    )
    pedestal = bpy.context.active_object
    pedestal.name = "Totem_Pedestal"
    mat_stone = create_pbr_material(
        name="Mat_Totem_Stone",
        base_color=(0.1, 0.1, 0.12, 1.0),
        metallic=0.2,
        roughness=0.8,
    )
    assign_material(pedestal, mat_stone)

    # Floating crystal (Octahedron / Ico-sphere)
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=1,
        radius=0.35,
        location=(0, 0, 1.5),
    )
    crystal = bpy.context.active_object
    crystal.name = "Totem_Crystal"
    crystal.scale = (0.7, 0.7, 1.2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    mat_crystal = create_pbr_material(
        name="Mat_Totem_Crystal",
        base_color=(0.1, 0.8, 1.0, 1.0),
        metallic=0.0,
        roughness=0.1,
        emission_color=(0.0, 0.8, 1.0, 1.0),
        emission_strength=5.0,
    )
    assign_material(crystal, mat_crystal)

    # Orbit ring (Torus)
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.55,
        minor_radius=0.04,
        location=(0, 0, 1.5),
    )
    ring = bpy.context.active_object
    ring.name = "Totem_Ring"
    mat_gold = create_pbr_material(
        name="Mat_Totem_Gold",
        base_color=(1.0, 0.75, 0.15, 1.0),
        metallic=0.9,
        roughness=0.25,
    )
    assign_material(ring, mat_gold)

    # Join meshes into one combined visual mesh
    bpy.ops.object.select_all(action="DESELECT")
    pedestal.select_set(True)
    crystal.select_set(True)
    ring.select_set(True)
    bpy.context.view_layer.objects.active = pedestal
    bpy.ops.object.join()
    totem_mesh = bpy.context.active_object
    totem_mesh.name = "dev_totem"

    # Add collision proxy for base
    create_box_collision(pedestal, suffix="-colonly")

    # ---------------------------------------------------------
    # 2. Armature Rigging
    # ---------------------------------------------------------
    arm_obj = create_armature("Totem_Armature")
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    # Root Bone
    add_bone(arm_obj, "Root", (0, 0, 0), (0, 0, 0.3))
    # Pedestal Bone
    add_bone(arm_obj, "Pedestal", (0, 0, 0), (0, 0, 0.4), parent_name="Root")
    # Crystal Bone
    add_bone(arm_obj, "Crystal", (0, 0, 1.2), (0, 0, 1.8), parent_name="Root")
    # Ring Bone
    add_bone(arm_obj, "Ring", (0, 0, 1.4), (0, 0, 1.6), parent_name="Root")

    bpy.ops.object.mode_set(mode="OBJECT")

    # Parent mesh to armature using vertex groups
    # Create vertex groups corresponding to bone names
    for bone_name in ["Root", "Pedestal", "Crystal", "Ring"]:
        totem_mesh.vertex_groups.new(name=bone_name)

    # Assign vertices by height/proximity
    mesh_data = totem_mesh.data
    vg_pedestal = totem_mesh.vertex_groups["Pedestal"]
    vg_crystal = totem_mesh.vertex_groups["Crystal"]
    vg_ring = totem_mesh.vertex_groups["Ring"]

    for i, v in enumerate(mesh_data.vertices):
        z = v.co.z
        dist_xy = math.sqrt(v.co.x**2 + v.co.y**2)
        if z < 0.6:
            vg_pedestal.add([i], 1.0, "REPLACE")
        elif dist_xy > 0.4:
            vg_ring.add([i], 1.0, "REPLACE")
        else:
            vg_crystal.add([i], 1.0, "REPLACE")

    # Add Armature Modifier
    arm_mod = totem_mesh.modifiers.new(name="Armature", type="ARMATURE")
    arm_mod.object = arm_obj
    totem_mesh.parent = arm_obj

    # ---------------------------------------------------------
    # 3. Animation Actions (Idle and Activate)
    # ---------------------------------------------------------
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pose_bones = arm_obj.pose.bones

    # --- ACTION 1: Idle (60 frames loop @ 30fps) ---
    idle_action = create_action(arm_obj, "Idle")
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 60

    for frame in [1, 30, 60]:
        bpy.context.scene.frame_set(frame)
        # Crystal bobbing
        z_offset = 0.08 if frame == 30 else 0.0
        pose_bones["Crystal"].location = (0, 0, z_offset)
        pose_bones["Crystal"].keyframe_insert(data_path="location", frame=frame)

        # Ring rotation (360 degrees over 60 frames)
        rot_angle = (frame - 1) / 59.0 * (math.pi * 2.0)
        pose_bones["Ring"].rotation_mode = "XYZ"
        pose_bones["Ring"].rotation_euler = (0, 0, rot_angle)
        pose_bones["Ring"].keyframe_insert(data_path="rotation_euler", frame=frame)

    push_action_to_nla(arm_obj, idle_action, track_name="NLA_Idle")

    # --- ACTION 2: Activate (30 frames burst) ---
    activate_action = create_action(arm_obj, "Activate")
    for frame in [1, 15, 30]:
        bpy.context.scene.frame_set(frame)
        # Crystal rises and scales up
        z_offset = 0.25 if frame == 15 else 0.0
        scale = 1.3 if frame == 15 else 1.0
        pose_bones["Crystal"].location = (0, 0, z_offset)
        pose_bones["Crystal"].scale = (scale, scale, scale)
        pose_bones["Crystal"].keyframe_insert(data_path="location", frame=frame)
        pose_bones["Crystal"].keyframe_insert(data_path="scale", frame=frame)

        # Ring spins fast (720 degrees)
        rot_angle = (frame - 1) / 29.0 * (math.pi * 4.0)
        pose_bones["Ring"].rotation_mode = "XYZ"
        pose_bones["Ring"].rotation_euler = (0, 0, rot_angle)
        pose_bones["Ring"].keyframe_insert(data_path="rotation_euler", frame=frame)

    push_action_to_nla(arm_obj, activate_action, track_name="NLA_Activate")

    # Reset pose and mode
    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode="OBJECT")

    # ---------------------------------------------------------
    # 4. Export
    # ---------------------------------------------------------
    output_path = output_dir / "dev_totem.glb"
    export_godot_glb(
        filepath=output_path,
        export_animations=True,
        apply_modifiers=False,  # Keep armature modifier intact for skinning
        save_blend=True,
    )
    return output_path


def main() -> None:
    try:
        sdk_root = Path(__file__).resolve().parent.parent.parent.parent
        assets_dir = sdk_root / "assets" / "models" / "dev_totem"
        generate_dev_totem(assets_dir)
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
