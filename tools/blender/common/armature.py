"""Armature and animation utilities for glTF and Godot 4."""

from __future__ import annotations

import mathutils
import bpy


def create_armature(name: str = "Armature") -> bpy.types.Object:
    """Create a new empty armature object in the scene."""
    arm_data = bpy.data.armatures.new(f"{name}_Data")
    arm_obj = bpy.data.objects.new(name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    return arm_obj


def add_bone(
    arm_obj: bpy.types.Object,
    bone_name: str,
    head: tuple[float, float, float] | mathutils.Vector,
    tail: tuple[float, float, float] | mathutils.Vector,
    parent_name: str | None = None,
    use_deform: bool = True,
) -> bpy.types.EditBone:
    """Add a bone to the armature in EDIT mode. Armature must be active."""
    if bpy.context.object != arm_obj or bpy.context.mode != "EDIT_ARMATURE":
        bpy.context.view_layer.objects.active = arm_obj
        bpy.ops.object.mode_set(mode="EDIT")

    edit_bones = arm_obj.data.edit_bones
    bone = edit_bones.new(bone_name)
    bone.head = head
    bone.tail = tail
    bone.use_deform = use_deform

    if parent_name and parent_name in edit_bones:
        bone.parent = edit_bones[parent_name]

    return bone


def parent_mesh_to_armature(
    mesh_obj: bpy.types.Object,
    arm_obj: bpy.types.Object,
    auto_weights: bool = True,
) -> None:
    """Parent a mesh to an armature with vertex weights."""
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="DESELECT")
    mesh_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj

    if auto_weights:
        bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    else:
        bpy.ops.object.parent_set(type="ARMATURE")


def create_action(arm_obj: bpy.types.Object, name: str) -> bpy.types.Action:
    """Create a fresh Action and set it as active on the armature."""
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    action = bpy.data.actions.new(name=name)
    arm_obj.animation_data.action = action
    return action


def push_action_to_nla(
    arm_obj: bpy.types.Object,
    action: bpy.types.Action,
    track_name: str | None = None,
) -> None:
    """Push an action to an NLA track so glTF exporter bakes all actions."""
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    anim_data = arm_obj.animation_data
    track = anim_data.nla_tracks.new()
    track.name = track_name or action.name

    start_frame = int(action.frame_range[0])
    track.strips.new(action.name, start_frame, action)
