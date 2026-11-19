#!/usr/bin/env python3
"""Headless Blender 5.x mocap retargeter for Godiva (1.64m humanoid NPC).

Imports existing assets/models/godiva/godiva_rigged.glb (preserving mesh, materials,
armature, and any existing NLA clips not overridden by files in --mocap-dir), scans
--mocap-dir for .fbx, .bvh, and .glb clips, retargets Mixamo / BVH / Godot humanoid
skeletons onto GodivaRig using rest-pose world-space delta quaternion retargeting,
pushes actions to NLA, and exports via tools/blender/common/exporter.py.

Usage:
    /snap/bin/blender --background --python tools/blender/retarget_godiva_mocap.py -- \\
        --mocap-dir assets/mocap/godiva \\
        --output assets/models/godiva/godiva_rigged.glb
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

_TOOL_DIR = Path(__file__).resolve().parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bpy
from mathutils import Quaternion, Vector
from common.exporter import clean_scene, export_godot_glb

DEFAULT_FPS: int = 60
SUPPORTED_EXTS: Tuple[str, ...] = (".fbx", ".bvh", ".glb", ".gltf")

# Clips where horizontal root translation (X/Y) is zeroed for in-place Godot locomotion & tweens.
DEFAULT_IN_PLACE_CLIPS: Set[str] = {
    "idle",
    "walk",
    "run",
    "crouch_idle",
    "crouch_walk",
    "prone_idle",
    "prone_crawl",
    "wall_hug_idle",
    "sidestep_left",
    "sidestep_right",
    "climb_mid",
    "pull_up_high",
    "shelf_climb_over",
    "shelf_crawl_through",
    "shelf_vault_through",
    "shelf_push_aside",
    "shelf_topple",
    "air_hump",
    "booty_slap",
}

# Traversal clips whose vertical climb/vault lift is driven by Godot Tween (detrend & clamp root Z).
VERTICAL_CLAMP_CLIPS: Set[str] = {
    "climb_mid",
    "pull_up_high",
    "shelf_climb_over",
    "shelf_vault_through",
}

# Grounded clips whose Hips Z is uniformly shifted so planted feet rest cleanly on Z = 0.0.
GROUNDED_CLIPS: Set[str] = {
    "idle",
    "walk",
    "run",
    "crouch_idle",
    "crouch_walk",
    "wall_hug_idle",
    "sidestep_left",
    "sidestep_right",
    "air_hump",
    "booty_slap",
    "shelf_push_aside",
    "shelf_topple",
}

# Foot/toe bones sampled for floor-contact grounding.
FOOT_GROUND_BONES: Tuple[str, ...] = (
    "LeftFoot",
    "RightFoot",
    "LeftToes",
    "RightToes",
)

# Max vertical body bob (meters) retained on Tween-driven vertical traversal clips.
VERTICAL_CLAMP_MAX_BOB: float = 0.18

# Cyclic clips that receive N-1 seam trimming to avoid duplicate wrap frames.
DEFAULT_LOOP_CLIPS: Set[str] = {
    "idle",
    "walk",
    "run",
    "crouch_idle",
    "crouch_walk",
    "prone_idle",
    "prone_crawl",
    "wall_hug_idle",
    "sidestep_left",
    "sidestep_right",
    "turn_left",
    "turn_right",
    "air_hump",
    "booty_slap",
}

# Godiva's 22 deform bones in strict parent-to-child order.
GODIVA_BONE_ORDER: Tuple[str, ...] = (
    "Hips",
    "Spine",
    "Chest",
    "UpperChest",
    "Neck",
    "Head",
    "LeftShoulder",
    "LeftUpperArm",
    "LeftLowerArm",
    "LeftHand",
    "RightShoulder",
    "RightUpperArm",
    "RightLowerArm",
    "RightHand",
    "LeftUpperLeg",
    "LeftLowerLeg",
    "LeftFoot",
    "LeftToes",
    "RightUpperLeg",
    "RightLowerLeg",
    "RightFoot",
    "RightToes",
)

# Arm/hand bones eligible for T-pose <-> A-pose world-space rest-direction compensation.
# World-space retargeting aligns each arm segment independently, so hands must be included
# alongside upper/lower arms to prevent A-pose wrists from bending ~44 deg inward.
ARM_REST_ALIGN_BONES: Set[str] = {
    "LeftUpperArm",
    "LeftLowerArm",
    "LeftHand",
    "RightUpperArm",
    "RightLowerArm",
    "RightHand",
}

# Normalized source bone alias -> Godiva target bone name.
# Covers Mixamo (mixamorig:*), standard BVH, Rokoko, CMU, and Godot Humanoid.
BONE_ALIASES: Dict[str, str] = {
    # Pelvis / Hips
    "hips": "Hips",
    "hip": "Hips",
    "pelvis": "Hips",
    "cog": "Hips",
    "root": "Hips",
    # Spine / Torso
    "spine": "Spine",
    "spine0": "Spine",
    "lowerback": "Spine",
    "abdomen": "Spine",
    "spine1": "Chest",
    "chest": "Chest",
    "torso": "Chest",
    "spine2": "UpperChest",
    "spine3": "UpperChest",
    "upperchest": "UpperChest",
    # Neck / Head
    "neck": "Neck",
    "neck1": "Neck",
    "head": "Head",
    # Left Arm
    "leftshoulder": "LeftShoulder",
    "lshoulder": "LeftShoulder",
    "shoulderl": "LeftShoulder",
    "leftclavicle": "LeftShoulder",
    "lclavicle": "LeftShoulder",
    "claviclel": "LeftShoulder",
    "leftcollar": "LeftShoulder",
    "lcollar": "LeftShoulder",
    "leftarm": "LeftUpperArm",
    "leftupperarm": "LeftUpperArm",
    "lupperarm": "LeftUpperArm",
    "upperarml": "LeftUpperArm",
    "larm": "LeftUpperArm",
    "arml": "LeftUpperArm",
    "leftshldr": "LeftUpperArm",
    "leftforearm": "LeftLowerArm",
    "leftlowerarm": "LeftLowerArm",
    "llowerarm": "LeftLowerArm",
    "lowerarml": "LeftLowerArm",
    "lforearm": "LeftLowerArm",
    "forearml": "LeftLowerArm",
    "lefthand": "LeftHand",
    "lhand": "LeftHand",
    "handl": "LeftHand",
    "leftwrist": "LeftHand",
    # Right Arm
    "rightshoulder": "RightShoulder",
    "rshoulder": "RightShoulder",
    "shoulderr": "RightShoulder",
    "rightclavicle": "RightShoulder",
    "rclavicle": "RightShoulder",
    "clavicler": "RightShoulder",
    "rightcollar": "RightShoulder",
    "rcollar": "RightShoulder",
    "rightarm": "RightUpperArm",
    "rightupperarm": "RightUpperArm",
    "rupperarm": "RightUpperArm",
    "upperarmr": "RightUpperArm",
    "rarm": "RightUpperArm",
    "armr": "RightUpperArm",
    "rightshldr": "RightUpperArm",
    "rightforearm": "RightLowerArm",
    "rightlowerarm": "RightLowerArm",
    "rlowerarm": "RightLowerArm",
    "lowerarmr": "RightLowerArm",
    "rforearm": "RightLowerArm",
    "forearmr": "RightLowerArm",
    "righthand": "RightHand",
    "rhand": "RightHand",
    "handr": "RightHand",
    "rightwrist": "RightHand",
    # Left Leg
    "leftupleg": "LeftUpperLeg",
    "leftupperleg": "LeftUpperLeg",
    "lupperleg": "LeftUpperLeg",
    "upperlegl": "LeftUpperLeg",
    "leftthigh": "LeftUpperLeg",
    "lthigh": "LeftUpperLeg",
    "thighl": "LeftUpperLeg",
    "leftleg": "LeftLowerLeg",
    "leftlowerleg": "LeftLowerLeg",
    "llowerleg": "LeftLowerLeg",
    "lowerlegl": "LeftLowerLeg",
    "leftshin": "LeftLowerLeg",
    "lshin": "LeftLowerLeg",
    "shinl": "LeftLowerLeg",
    "leftcalf": "LeftLowerLeg",
    "leftfoot": "LeftFoot",
    "lfoot": "LeftFoot",
    "footl": "LeftFoot",
    "leftankle": "LeftFoot",
    "lefttoebase": "LeftToes",
    "lefttoes": "LeftToes",
    "lefttoe": "LeftToes",
    "ltoes": "LeftToes",
    "toesl": "LeftToes",
    "ltoe": "LeftToes",
    "toel": "LeftToes",
    # Right Leg
    "rightupleg": "RightUpperLeg",
    "rightupperleg": "RightUpperLeg",
    "rupperleg": "RightUpperLeg",
    "upperlegr": "RightUpperLeg",
    "rightthigh": "RightUpperLeg",
    "rthigh": "RightUpperLeg",
    "thighr": "RightUpperLeg",
    "rightleg": "RightLowerLeg",
    "rightlowerleg": "RightLowerLeg",
    "rlowerleg": "RightLowerLeg",
    "lowerlegr": "RightLowerLeg",
    "rightshin": "RightLowerLeg",
    "rshin": "RightLowerLeg",
    "shinr": "RightLowerLeg",
    "rightcalf": "RightLowerLeg",
    "rightfoot": "RightFoot",
    "rfoot": "RightFoot",
    "footr": "RightFoot",
    "rightankle": "RightFoot",
    "righttoebase": "RightToes",
    "righttoes": "RightToes",
    "righttoe": "RightToes",
    "rtoes": "RightToes",
    "toesr": "RightToes",
    "rtoe": "RightToes",
    "toer": "RightToes",
}

_PREFIX_RE = re.compile(
    r"^(?:mixamorig\d*[:_]?|armature\||bip01[_ ]?|cc_base_|valvebiped\.bip01_|character1_)",
    re.IGNORECASE,
)


def _normalize_bone_name(raw_name: str) -> str:
    """Normalizes a source bone name for alias table lookup."""
    name = raw_name.strip()
    # Strip namespace prefixes before ':' if any remain (e.g. 'rig:Hips')
    if ":" in name:
        name = name.split(":")[-1]
    name = _PREFIX_RE.sub("", name)
    return re.sub(r"[^a-z0-9]", "", name.lower())


def _normalize_clip_name(stem: str) -> str:
    """Converts a mocap filename stem into a clean snake_case Godot clip name."""
    cleaned = re.sub(r"[^a-zA-Z0-9]+", "_", stem.strip()).strip("_").lower()
    return cleaned or "clip"


def _build_bone_map(src_arm: bpy.types.Object, tgt_arm: bpy.types.Object) -> Dict[str, str]:
    """Maps Godiva target bone names -> source bone names on src_arm."""
    tgt_bones = set(tgt_arm.data.bones.keys())
    mapping: Dict[str, str] = {}

    for sb in src_arm.data.bones:
        # Exact match first
        if sb.name in tgt_bones and sb.name not in mapping:
            mapping[sb.name] = sb.name
            continue
        norm = _normalize_bone_name(sb.name)
        tgt_name = BONE_ALIASES.get(norm)
        if tgt_name and tgt_name in tgt_bones and tgt_name not in mapping:
            # Prefer "hips" over generic "root" if both exist
            mapping[tgt_name] = sb.name
        elif norm == "hips" and "Hips" in tgt_bones:
            mapping["Hips"] = sb.name

    return mapping


def _get_action_fcurves(action: bpy.types.Action) -> List[bpy.types.FCurve]:
    """Collects all FCurves across Blender 5.x channelbags or legacy fcurves."""
    fcurves: List[bpy.types.FCurve] = []
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    fcurves.extend(bag.fcurves)
    elif hasattr(action, "fcurves"):
        fcurves.extend(action.fcurves)
    return fcurves


def _ensure_quaternion_continuity(action: bpy.types.Action) -> None:
    """Aligns consecutive quaternion keyframes to the same hemisphere to prevent 360-deg flips."""
    by_path: Dict[str, Dict[int, bpy.types.FCurve]] = {}
    for fc in _get_action_fcurves(action):
        if fc.data_path.endswith("rotation_quaternion"):
            by_path.setdefault(fc.data_path, {})[fc.array_index] = fc

    for idx_map in by_path.values():
        if len(idx_map) != 4:
            continue
        fc_w, fc_x, fc_y, fc_z = idx_map[0], idx_map[1], idx_map[2], idx_map[3]
        n = min(
            len(fc_w.keyframe_points),
            len(fc_x.keyframe_points),
            len(fc_y.keyframe_points),
            len(fc_z.keyframe_points),
        )
        if n < 2:
            continue
        prev = Quaternion((
            fc_w.keyframe_points[0].co.y,
            fc_x.keyframe_points[0].co.y,
            fc_y.keyframe_points[0].co.y,
            fc_z.keyframe_points[0].co.y,
        ))
        for i in range(1, n):
            curr = Quaternion((
                fc_w.keyframe_points[i].co.y,
                fc_x.keyframe_points[i].co.y,
                fc_y.keyframe_points[i].co.y,
                fc_z.keyframe_points[i].co.y,
            ))
            if prev.dot(curr) < 0.0:
                curr.negate()
                fc_w.keyframe_points[i].co.y = curr.w
                fc_x.keyframe_points[i].co.y = curr.x
                fc_y.keyframe_points[i].co.y = curr.y
                fc_z.keyframe_points[i].co.y = curr.z
            prev = curr
        for fc in (fc_w, fc_x, fc_y, fc_z):
            fc.update()


def _set_all_bezier_smooth(action: bpy.types.Action) -> None:
    """Ensures quaternion continuity and sets Bezier auto-clamped interpolation."""
    _ensure_quaternion_continuity(action)
    for fc in _get_action_fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"


def _reset_pose(arm_obj: bpy.types.Object) -> None:
    """Resets all pose bones on arm_obj to identity rotation and zero translation."""
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.location = Vector((0.0, 0.0, 0.0))


def _remove_existing_clip(arm_obj: bpy.types.Object, clip_name: str) -> None:
    """Removes any existing NLA track and action matching clip_name on arm_obj."""
    if arm_obj.animation_data:
        if arm_obj.animation_data.action and arm_obj.animation_data.action.name == clip_name:
            arm_obj.animation_data.action = None
        for track in list(arm_obj.animation_data.nla_tracks):
            matches = track.name == clip_name or any(
                (s.name == clip_name) or (s.action and s.action.name == clip_name)
                for s in track.strips
            )
            if matches:
                arm_obj.animation_data.nla_tracks.remove(track)

    old_action = bpy.data.actions.get(clip_name)
    if old_action is not None:
        bpy.data.actions.remove(old_action)


def _push_clip_to_nla(
    arm_obj: bpy.types.Object,
    action: bpy.types.Action,
    frame_count: int,
    is_loop: bool,
) -> None:
    """Pushes a 0-based retargeted action to an NLA track with N-1 loop trimming."""
    _set_all_bezier_smooth(action)
    end_frame = max(1, (frame_count - 2) if (is_loop and frame_count > 2) else (frame_count - 1))
    action.use_frame_range = True
    action.frame_start = 0.0
    action.frame_end = float(end_frame)

    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    track = arm_obj.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, 0, action)
    strip.action_frame_start = 0.0
    strip.action_frame_end = float(end_frame)
    strip.frame_start = 0.0
    strip.frame_end = float(end_frame)
    arm_obj.animation_data.action = None


def _compute_world_yaw_alignment(
    src_arm: bpy.types.Object,
    tgt_arm: bpy.types.Object,
    bone_map: Dict[str, str],
) -> Quaternion:
    """Computes pure Z-yaw quaternion aligning source rest facing to Godiva's -Y facing."""
    up = Vector((0.0, 0.0, 1.0))
    tgt_fwd = Vector((0.0, -1.0, 0.0))

    # Measure source left->right vector from hips/legs or shoulders
    pair_candidates = (
        ("LeftUpperLeg", "RightUpperLeg"),
        ("LeftUpperArm", "RightUpperArm"),
        ("LeftShoulder", "RightShoulder"),
    )
    src_mw = src_arm.matrix_world
    for l_key, r_key in pair_candidates:
        if l_key in bone_map and r_key in bone_map:
            l_pos = src_mw @ src_arm.data.bones[bone_map[l_key]].head_local
            r_pos = src_mw @ src_arm.data.bones[bone_map[r_key]].head_local
            left_vec = l_pos - r_pos
            left_vec.z = 0.0
            if left_vec.length_squared > 1e-6:
                left_vec.normalize()
                src_fwd = left_vec.cross(up)
                src_fwd.z = 0.0
                if src_fwd.length_squared > 1e-6:
                    src_fwd.normalize()
                    angle = math.atan2(
                        src_fwd.x * tgt_fwd.y - src_fwd.y * tgt_fwd.x,
                        src_fwd.x * tgt_fwd.x + src_fwd.y * tgt_fwd.y,
                    )
                    return Quaternion(up, angle)

    return Quaternion((1.0, 0.0, 0.0, 0.0))


def _measure_leg_length(arm_obj: bpy.types.Object, bone_map: Optional[Dict[str, str]] = None) -> float:
    """Measures world-space leg length (UpperLeg + LowerLeg) for hip translation scaling."""
    mw = arm_obj.matrix_world

    def _bname(canonical: str) -> Optional[str]:
        if bone_map is None:
            return canonical if canonical in arm_obj.data.bones else None
        return bone_map.get(canonical)

    lengths: List[float] = []
    for side in ("Left", "Right"):
        u_name = _bname(f"{side}UpperLeg")
        l_name = _bname(f"{side}LowerLeg")
        if u_name and l_name:
            ub = arm_obj.data.bones[u_name]
            lb = arm_obj.data.bones[l_name]
            u_len = ((mw @ ub.tail_local) - (mw @ ub.head_local)).length
            l_len = ((mw @ lb.tail_local) - (mw @ lb.head_local)).length
            if u_len + l_len > 1e-4:
                lengths.append(u_len + l_len)

    if lengths:
        return sum(lengths) / len(lengths)

    # Fallback: Hips Z height in world space
    hips_name = _bname("Hips")
    if hips_name:
        hz = abs((mw @ arm_obj.data.bones[hips_name].head_local).z)
        if hz > 1e-4:
            return hz
    return 0.85


def _detect_source_frame_range(src_arm: bpy.types.Object) -> Tuple[int, int]:
    """Determines [start_frame, end_frame] from the source armature's active action or NLA."""
    action: Optional[bpy.types.Action] = None
    if src_arm.animation_data:
        action = src_arm.animation_data.action
        if action is None:
            for tr in src_arm.animation_data.nla_tracks:
                for st in tr.strips:
                    if st.action is not None:
                        action = st.action
                        src_arm.animation_data.action = action
                        break
                if action is not None:
                    break

    if action is not None:
        f_start, f_end = action.frame_range
        start_i = int(round(f_start))
        end_i = int(round(f_end))
        if end_i >= start_i:
            return start_i, end_i

    return 1, 1


def _import_mocap_file(filepath: Path) -> Tuple[Optional[bpy.types.Object], List[bpy.types.Object], List[bpy.types.Action]]:
    """Imports a .fbx, .bvh, or .glb mocap file and returns (armature, new_objs, new_actions)."""
    before_objs = set(bpy.data.objects)
    before_actions = set(bpy.data.actions)

    ext = filepath.suffix.lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(
            filepath=str(filepath),
            automatic_bone_orientation=False,
            use_anim=True,
            ignore_leaf_bones=False,
        )
    elif ext == ".bvh":
        bpy.ops.import_anim.bvh(
            filepath=str(filepath),
            target="ARMATURE",
            global_scale=1.0,
            frame_start=1,
            use_fps_scale=True,
            update_scene_fps=False,
            update_scene_duration=False,
        )
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(filepath))
    else:
        raise ValueError(f"Unsupported mocap format: {filepath}")

    bpy.context.view_layer.update()
    new_objs = [o for o in bpy.data.objects if o not in before_objs]
    new_actions = [a for a in bpy.data.actions if a not in before_actions]
    # Prefix imported source actions so they never collide with target Godot clip names
    for idx, act in enumerate(new_actions):
        act.name = f"__mocap_src_{idx}_{act.name}"
    src_arm = next((o for o in new_objs if o.type == "ARMATURE"), None)
    return src_arm, new_objs, new_actions


def _cleanup_imported_mocap(
    new_objs: List[bpy.types.Object],
    new_actions: List[bpy.types.Action],
) -> None:
    """Removes temporary imported mocap objects, armatures, meshes, and actions."""
    for obj in list(new_objs):
        try:
            obj_name = obj.name
        except ReferenceError:
            continue
        if obj_name in bpy.data.objects:
            data_block = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if data_block is not None and data_block.users == 0:
                if isinstance(data_block, bpy.types.Armature):
                    bpy.data.armatures.remove(data_block)
                elif isinstance(data_block, bpy.types.Mesh):
                    bpy.data.meshes.remove(data_block)

    for act in list(new_actions):
        try:
            act_name = act.name
        except ReferenceError:
            continue
        if act_name in bpy.data.actions:
            bpy.data.actions.remove(act, do_unlink=True)


def _measure_rest_foot_clearance(tgt_arm: bpy.types.Object) -> float:
    """Returns lowest world Z of Godiva's foot/toe bones in rest pose (sole sits at Z=0)."""
    mw = tgt_arm.matrix_world
    min_z = float("inf")
    for bname in FOOT_GROUND_BONES:
        if bname in tgt_arm.data.bones:
            tb = tgt_arm.data.bones[bname]
            hz = (mw @ tb.head_local).z
            tz = (mw @ tb.tail_local).z
            min_z = min(min_z, hz, tz)
    return min_z if math.isfinite(min_z) else 0.025


def _shift_hips_location_world_z(
    action: bpy.types.Action,
    tgt_mw_rot_inv: Quaternion,
    tgt_hips_rest_rot_inv: Quaternion,
    z_shift_world: float,
) -> None:
    """Shifts all Hips location keyframes uniformly by z_shift_world in world space."""
    if abs(z_shift_world) < 1e-6:
        return
    delta_local = tgt_hips_rest_rot_inv @ (tgt_mw_rot_inv @ Vector((0.0, 0.0, z_shift_world)))
    for fc in _get_action_fcurves(action):
        if fc.data_path == 'pose.bones["Hips"].location' and 0 <= fc.array_index <= 2:
            offset = delta_local[fc.array_index]
            if abs(offset) < 1e-7:
                continue
            for kp in fc.keyframe_points:
                kp.co.y += offset
                kp.handle_left.y += offset
                kp.handle_right.y += offset
            fc.update()


def _retarget_clip(
    src_arm: bpy.types.Object,
    tgt_arm: bpy.types.Object,
    clip_name: str,
    in_place: bool,
    is_loop: bool,
) -> int:
    """Retargets src_arm's animation onto tgt_arm as clip_name; returns frame count."""
    bone_map = _build_bone_map(src_arm, tgt_arm)
    if "Hips" not in bone_map:
        raise RuntimeError(
            f"Clip '{clip_name}': could not map Hips on source armature '{src_arm.name}'. "
            f"Source bones: {[b.name for b in src_arm.data.bones]}"
        )

    f_start, f_end = _detect_source_frame_range(src_arm)
    frame_count = max(1, f_end - f_start + 1)

    q_align = _compute_world_yaw_alignment(src_arm, tgt_arm, bone_map)
    q_align_inv = q_align.inverted()

    src_leg_len = _measure_leg_length(src_arm, bone_map)
    tgt_leg_len = _measure_leg_length(tgt_arm, None)
    leg_scale = tgt_leg_len / max(src_leg_len, 1e-4)

    # Precompute rest world rotations for source & target
    src_mw = src_arm.matrix_world
    src_mw_rot = src_mw.to_3x3().normalized().to_quaternion()
    tgt_mw_rot = tgt_arm.matrix_world.to_3x3().normalized().to_quaternion()
    tgt_mw_rot_inv = tgt_mw_rot.inverted()

    src_rest_world_q: Dict[str, Quaternion] = {}
    tgt_rest_arm_q: Dict[str, Quaternion] = {}
    tgt_rest_world_q: Dict[str, Quaternion] = {}
    rest_pose_offset_q: Dict[str, Quaternion] = {}

    for tgt_bname in GODIVA_BONE_ORDER:
        if tgt_bname not in tgt_arm.data.bones:
            continue
        tb = tgt_arm.data.bones[tgt_bname]
        q_t_arm = tb.matrix_local.to_3x3().normalized().to_quaternion()
        q_t_world = tgt_mw_rot @ q_t_arm
        tgt_rest_arm_q[tgt_bname] = q_t_arm
        tgt_rest_world_q[tgt_bname] = q_t_world

        src_bname = bone_map.get(tgt_bname)
        if src_bname is not None:
            sb = src_arm.data.bones[src_bname]
            q_s_arm = sb.matrix_local.to_3x3().normalized().to_quaternion()
            src_rest_world_q[tgt_bname] = src_mw_rot @ q_s_arm

            # Compensate T-pose vs A-pose arm rest angle difference
            if tgt_bname in ARM_REST_ALIGN_BONES:
                src_dir = (src_mw @ sb.tail_local) - (src_mw @ sb.head_local)
                tgt_dir = (tgt_arm.matrix_world @ tb.tail_local) - (tgt_arm.matrix_world @ tb.head_local)
                if src_dir.length_squared > 1e-8 and tgt_dir.length_squared > 1e-8:
                    src_dir_aligned = (q_align @ src_dir).normalized()
                    tgt_dir_n = tgt_dir.normalized()
                    rest_pose_offset_q[tgt_bname] = tgt_dir_n.rotation_difference(src_dir_aligned)
                else:
                    rest_pose_offset_q[tgt_bname] = Quaternion((1.0, 0.0, 0.0, 0.0))
            else:
                rest_pose_offset_q[tgt_bname] = Quaternion((1.0, 0.0, 0.0, 0.0))

    # Source & target hip rest positions in world space
    src_hips_bname = bone_map["Hips"]
    src_hips_rest_world = src_mw @ src_arm.data.bones[src_hips_bname].head_local
    tgt_hips_rest_rot_inv = tgt_rest_arm_q["Hips"].inverted()

    # Prepare target action
    _remove_existing_clip(tgt_arm, clip_name)
    if not tgt_arm.animation_data:
        tgt_arm.animation_data_create()

    # Mute existing NLA tracks during baking so they cannot influence pose evaluation
    prev_mute = [tr.mute for tr in tgt_arm.animation_data.nla_tracks]
    for tr in tgt_arm.animation_data.nla_tracks:
        tr.mute = True

    action = bpy.data.actions.new(name=clip_name)
    tgt_arm.animation_data.action = action

    bpy.context.view_layer.objects.active = tgt_arm
    if bpy.context.object and bpy.context.object.mode != "POSE":
        bpy.ops.object.mode_set(mode="POSE")
    _reset_pose(tgt_arm)

    prev_basis_q: Dict[str, Quaternion] = {}
    hips_deltas_world: List[Vector] = []
    scene = bpy.context.scene

    for step_idx in range(frame_count):
        src_frame = f_start + step_idx
        dst_frame = step_idx
        scene.frame_set(src_frame)
        bpy.context.view_layer.update()

        # Track solved target armature-space world-equivalent orientation per bone
        solved_arm_q: Dict[str, Quaternion] = {}

        for tgt_bname in GODIVA_BONE_ORDER:
            if tgt_bname not in tgt_arm.pose.bones:
                continue
            pb = tgt_arm.pose.bones[tgt_bname]
            pb.rotation_mode = "QUATERNION"
            tb = tgt_arm.data.bones[tgt_bname]
            parent_name = tb.parent.name if tb.parent else None

            if parent_name and parent_name in solved_arm_q:
                parent_pose_q = solved_arm_q[parent_name]
                parent_rest_q = tgt_rest_arm_q[parent_name]
            else:
                parent_pose_q = Quaternion((1.0, 0.0, 0.0, 0.0))
                parent_rest_q = Quaternion((1.0, 0.0, 0.0, 0.0))

            local_rest_rel = parent_rest_q.inverted() @ tgt_rest_arm_q[tgt_bname]

            if tgt_bname in bone_map:
                src_pb = src_arm.pose.bones[bone_map[tgt_bname]]
                q_s_pose_world = (src_mw @ src_pb.matrix).to_3x3().normalized().to_quaternion()
                q_s_rest_world = src_rest_world_q[tgt_bname]

                # World-space delta from source rest, rotated into Godiva's world frame
                q_delta_src = q_s_pose_world @ q_s_rest_world.inverted()
                q_delta_world = q_align @ q_delta_src @ q_align_inv

                q_desired_world = (
                    q_delta_world
                    @ rest_pose_offset_q[tgt_bname]
                    @ tgt_rest_world_q[tgt_bname]
                )
                q_desired_arm = tgt_mw_rot_inv @ q_desired_world

                q_ref_arm = parent_pose_q @ local_rest_rel
                q_basis = q_ref_arm.inverted() @ q_desired_arm
                q_basis.normalize()

                # Enforce hemisphere continuity frame-to-frame
                if tgt_bname in prev_basis_q and prev_basis_q[tgt_bname].dot(q_basis) < 0.0:
                    q_basis.negate()
                prev_basis_q[tgt_bname] = q_basis.copy()

                pb.rotation_quaternion = q_basis
                solved_arm_q[tgt_bname] = q_ref_arm @ q_basis
            else:
                q_ident = Quaternion((1.0, 0.0, 0.0, 0.0))
                pb.rotation_quaternion = q_ident
                solved_arm_q[tgt_bname] = parent_pose_q @ local_rest_rel

            pb.keyframe_insert(data_path="rotation_quaternion", frame=dst_frame)

            # Collect Hips translation delta (keyframed in second pass for detrend/grounding)
            if tgt_bname == "Hips":
                src_hips_pb = src_arm.pose.bones[src_hips_bname]
                src_hips_pose_world = src_mw @ src_hips_pb.head
                src_delta_world = src_hips_pose_world - src_hips_rest_world
                tgt_delta_world = (q_align @ src_delta_world) * leg_scale
                if in_place:
                    tgt_delta_world.x = 0.0
                    tgt_delta_world.y = 0.0
                hips_deltas_world.append(tgt_delta_world)

    # Detrend & clamp vertical Z drift for Tween-driven vertical traversal clips
    if clip_name in VERTICAL_CLAMP_CLIPS and hips_deltas_world:
        z0 = hips_deltas_world[0].z
        z1 = hips_deltas_world[-1].z
        denom = max(1, len(hips_deltas_world) - 1)
        for idx, delta in enumerate(hips_deltas_world):
            linear_drift = z0 + (z1 - z0) * (idx / denom)
            z_bob = delta.z - linear_drift
            delta.z = max(-VERTICAL_CLAMP_MAX_BOB, min(VERTICAL_CLAMP_MAX_BOB, z_bob))

    # Write Hips location keyframes
    hips_pb = tgt_arm.pose.bones["Hips"]
    for dst_frame, tgt_delta_world in enumerate(hips_deltas_world):
        tgt_delta_arm = tgt_mw_rot_inv @ tgt_delta_world
        hips_pb.location = tgt_hips_rest_rot_inv @ tgt_delta_arm
        hips_pb.keyframe_insert(data_path="location", frame=dst_frame)

    # Uniformly ground planted feet to Z = 0.0 for grounded clips
    foot_z_shift = 0.0
    if clip_name in GROUNDED_CLIPS and frame_count > 0:
        rest_foot_clearance = _measure_rest_foot_clearance(tgt_arm)
        foot_min_zs: List[float] = []
        tgt_mw = tgt_arm.matrix_world
        for dst_frame in range(frame_count):
            scene.frame_set(dst_frame)
            bpy.context.view_layer.update()
            frame_min_z = float("inf")
            for bname in FOOT_GROUND_BONES:
                if bname in tgt_arm.pose.bones:
                    fpb = tgt_arm.pose.bones[bname]
                    frame_min_z = min(
                        frame_min_z,
                        (tgt_mw @ fpb.head).z,
                        (tgt_mw @ fpb.tail).z,
                    )
            if math.isfinite(frame_min_z):
                foot_min_zs.append(frame_min_z)

        if foot_min_zs:
            sorted_zs = sorted(foot_min_zs)
            p5_idx = int(0.05 * (len(sorted_zs) - 1))
            stance_z = sorted_zs[p5_idx]
            foot_z_shift = rest_foot_clearance - stance_z
            _shift_hips_location_world_z(
                action=action,
                tgt_mw_rot_inv=tgt_mw_rot_inv,
                tgt_hips_rest_rot_inv=tgt_hips_rest_rot_inv,
                z_shift_world=foot_z_shift,
            )

    _push_clip_to_nla(tgt_arm, action, frame_count=frame_count, is_loop=is_loop)
    _reset_pose(tgt_arm)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Restore NLA mute states (newly pushed track stays unmuted)
    for idx, was_muted in enumerate(prev_mute):
        if idx < len(tgt_arm.animation_data.nla_tracks):
            tgt_arm.animation_data.nla_tracks[idx].mute = was_muted

    print(
        f"[Retarget] '{clip_name}': {frame_count} frames, {len(bone_map)}/{len(GODIVA_BONE_ORDER)} bones, "
        f"leg_scale={leg_scale:.3f}, in_place={in_place}, loop={is_loop}, foot_z_shift={foot_z_shift:+.4f}m"
    )
    return frame_count


def _load_clip_map(clip_map_path: Optional[Path]) -> Dict[str, str]:
    """Loads optional JSON filename-stem -> Godot clip name mapping."""
    if clip_map_path is None:
        return {}
    if not clip_map_path.is_file():
        raise FileNotFoundError(f"Clip map JSON not found: {clip_map_path}")
    raw = json.loads(clip_map_path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError(f"Clip map JSON must be an object mapping stem -> clip_name: {clip_map_path}")
    return {str(k): str(v) for k, v in raw.items()}


def run_retarget_pipeline(
    base_glb: Path,
    mocap_dir: Path,
    output_glb: Path,
    clip_map_path: Optional[Path] = None,
    fps: int = DEFAULT_FPS,
    in_place_clips: Optional[Set[str]] = None,
    loop_clips: Optional[Set[str]] = None,
) -> List[str]:
    """Imports base Godiva GLB, retargets all clips in mocap_dir, exports output_glb."""
    if not base_glb.is_file():
        raise FileNotFoundError(f"Base rigged GLB not found: {base_glb}")
    if not mocap_dir.is_dir():
        raise FileNotFoundError(f"Mocap directory not found: {mocap_dir}")

    in_place_set = in_place_clips if in_place_clips is not None else DEFAULT_IN_PLACE_CLIPS
    loop_set = loop_clips if loop_clips is not None else DEFAULT_LOOP_CLIPS
    clip_map = _load_clip_map(clip_map_path)

    clean_scene()
    # Set target FPS BEFORE importing base GLB so existing NLA strips retain 60 FPS timing
    bpy.context.scene.render.fps = fps
    bpy.context.scene.render.fps_base = 1.0

    bpy.ops.import_scene.gltf(filepath=str(base_glb))
    bpy.context.view_layer.update()

    tgt_arm = bpy.data.objects.get("GodivaRig")
    if tgt_arm is None or tgt_arm.type != "ARMATURE":
        tgt_arm = next((o for o in bpy.context.scene.objects if o.type == "ARMATURE"), None)
    if tgt_arm is None:
        raise RuntimeError(f"No armature found in base GLB: {base_glb}")

    if tgt_arm.animation_data:
        tgt_arm.animation_data.action = None

    # Keep track of Godiva's own hierarchy so stray glTF bone-shape meshes are excluded on export
    export_objs = [tgt_arm] + [o for o in bpy.context.scene.objects if o.parent == tgt_arm]

    mocap_files = sorted(
        p for p in mocap_dir.iterdir()
        if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS
    )
    if not mocap_files:
        print(f"[Retarget] No mocap files ({', '.join(SUPPORTED_EXTS)}) found in {mocap_dir}")

    retargeted_names: List[str] = []
    for mocap_path in mocap_files:
        clip_name = clip_map.get(
            mocap_path.name,
            clip_map.get(mocap_path.stem, _normalize_clip_name(mocap_path.stem)),
        )
        src_arm, new_objs, new_actions = _import_mocap_file(mocap_path)
        try:
            if src_arm is None:
                print(f"[Retarget] WARNING: Skipping {mocap_path.name} (no armature found)")
                continue
            _retarget_clip(
                src_arm=src_arm,
                tgt_arm=tgt_arm,
                clip_name=clip_name,
                in_place=(clip_name in in_place_set),
                is_loop=(clip_name in loop_set),
            )
            retargeted_names.append(clip_name)
        finally:
            _cleanup_imported_mocap(new_objs, new_actions)

    # Select only GodivaRig and her child meshes for clean export
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in export_objs:
        if obj.name in bpy.data.objects:
            obj.select_set(True)
    bpy.context.view_layer.objects.active = tgt_arm

    export_godot_glb(
        filepath=output_glb,
        export_animations=True,
        apply_modifiers=False,
        only_selected=True,
        save_blend=False,
    )
    total_tracks = len(tgt_arm.animation_data.nla_tracks) if tgt_arm.animation_data else 0
    print(
        f"[Retarget] Done: retargeted {len(retargeted_names)} clip(s) {retargeted_names}; "
        f"total NLA clips exported: {total_tracks}"
    )
    return retargeted_names


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent.parent
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []

    parser = argparse.ArgumentParser(
        description="Retarget .fbx/.bvh/.glb mocap clips onto GodivaRig and export Godot GLB."
    )
    parser.add_argument(
        "--base-glb",
        type=Path,
        default=repo_root / "assets/models/godiva/godiva_rigged.glb",
        help="Existing rigged Godiva GLB to preserve mesh/materials/existing NLA clips.",
    )
    parser.add_argument(
        "--mocap-dir",
        type=Path,
        default=repo_root / "assets/mocap/godiva",
        help="Directory containing .fbx, .bvh, or .glb mocap files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "assets/models/godiva/godiva_rigged.glb",
        help="Output Godot-ready GLB path.",
    )
    parser.add_argument(
        "--clip-map",
        type=Path,
        default=None,
        help="Optional JSON mapping filename or stem -> target Godot clip name.",
    )
    parser.add_argument(
        "--fps",
        type=int,
        default=DEFAULT_FPS,
        help="Target animation frame rate (default: 60).",
    )
    parser.add_argument(
        "--in-place-clips",
        type=str,
        default=None,
        help="Comma-separated list of clips to zero horizontal root XY motion.",
    )
    parser.add_argument(
        "--loop-clips",
        type=str,
        default=None,
        help="Comma-separated list of cyclic clips for N-1 seam trimming.",
    )
    args = parser.parse_args(argv)

    in_place_set = (
        {c.strip() for c in args.in_place_clips.split(",") if c.strip()}
        if args.in_place_clips is not None
        else None
    )
    loop_set = (
        {c.strip() for c in args.loop_clips.split(",") if c.strip()}
        if args.loop_clips is not None
        else None
    )

    run_retarget_pipeline(
        base_glb=args.base_glb,
        mocap_dir=args.mocap_dir,
        output_glb=args.output,
        clip_map_path=args.clip_map,
        fps=args.fps,
        in_place_clips=in_place_set,
        loop_clips=loop_set,
    )


if __name__ == "__main__":
    main()
