#!/usr/bin/env python3
"""Headless Blender 5.x rigger and 60 FPS animator for Godiva (1.64m humanoid NPC).

Imports the static unrigged assets/models/godiva/godiva.glb (leaving the original
untouched), uniformly scales her to exactly 1.64m height with feet planted at Z=0,
builds a 23-bone SkeletonProfileHumanoid-compatible armature, applies unified
anatomical spatial skinning across all 10 garment/body meshes (zero cloth poke-through
and zero cross-limb sticking), bakes 60 FPS Bezier NLA clips ('idle' and 'air_hump'
with 2-bone IK foot lock), exports assets/models/godiva/godiva_rigged.glb, and
renders optional verification frames.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Dict, List, Tuple

_TOOL_DIR = Path(__file__).resolve().parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bpy
from mathutils import Matrix, Quaternion, Vector
from common.exporter import clean_scene, export_godot_glb

TARGET_HEIGHT_M: float = 1.64
FPS: int = 60

# Measured raw anatomical landmarks on assets/models/godiva/godiva.glb
# Raw bounds: Z in [-0.005, +2.023], facing -Y (Blender), +X = character Left.
RAW_Z_MIN: float = -0.0050
RAW_Z_MAX: float = 2.0232
SCALE_FACTOR: float = TARGET_HEIGHT_M / (RAW_Z_MAX - RAW_Z_MIN)


def _s(x: float, y: float, z: float) -> Tuple[float, float, float]:
    """Converts a raw godiva.glb Blender point into 1.64m floor-grounded space."""
    return (x * SCALE_FACTOR, y * SCALE_FACTOR, (z - RAW_Z_MIN) * SCALE_FACTOR)


# 23-bone SkeletonProfileHumanoid rig (matches dark_man.py naming + Godot humanoid map)
BONE_SPECS: List[
    Tuple[str, str | None, Tuple[float, float, float], Tuple[float, float, float], bool]
] = [
    ("Root", None, _s(0.0, 0.0, RAW_Z_MIN), _s(0.0, 0.0, 0.18), False),
    ("Hips", "Root", _s(0.0, -0.008, 1.010), _s(0.0, -0.016, 1.145), True),
    ("Spine", "Hips", _s(0.0, -0.016, 1.145), _s(0.0, -0.022, 1.310), True),
    ("Chest", "Spine", _s(0.0, -0.022, 1.310), _s(0.0, -0.016, 1.460), True),
    ("UpperChest", "Chest", _s(0.0, -0.016, 1.460), _s(0.0, -0.004, 1.610), True),
    ("Neck", "UpperChest", _s(0.0, -0.004, 1.610), _s(0.0, -0.004, 1.715), True),
    ("Head", "Neck", _s(0.0, -0.004, 1.715), _s(0.0, -0.004, 1.965), True),
    # Left Arm (+X in Blender, character's left when facing -Y)
    ("LeftShoulder", "UpperChest", _s(0.042, 0.004, 1.555), _s(0.175, 0.016, 1.525), True),
    ("LeftUpperArm", "LeftShoulder", _s(0.175, 0.016, 1.525), _s(0.358, 0.012, 1.355), True),
    ("LeftLowerArm", "LeftUpperArm", _s(0.358, 0.012, 1.355), _s(0.515, -0.021, 1.215), True),
    ("LeftHand", "LeftLowerArm", _s(0.515, -0.021, 1.215), _s(0.640, -0.040, 1.095), True),
    # Right Arm (-X in Blender)
    ("RightShoulder", "UpperChest", _s(-0.042, 0.004, 1.555), _s(-0.175, 0.016, 1.525), True),
    ("RightUpperArm", "RightShoulder", _s(-0.175, 0.016, 1.525), _s(-0.358, 0.012, 1.355), True),
    ("RightLowerArm", "RightUpperArm", _s(-0.358, 0.012, 1.355), _s(-0.515, -0.021, 1.215), True),
    ("RightHand", "RightLowerArm", _s(-0.515, -0.021, 1.215), _s(-0.640, -0.040, 1.095), True),
    # Left Leg (+X in Blender)
    ("LeftUpperLeg", "Hips", _s(0.103, -0.006, 0.990), _s(0.129, 0.024, 0.520), True),
    ("LeftLowerLeg", "LeftUpperLeg", _s(0.129, 0.024, 0.520), _s(0.152, 0.018, 0.115), True),
    ("LeftFoot", "LeftLowerLeg", _s(0.152, 0.018, 0.115), _s(0.165, -0.105, 0.032), True),
    ("LeftToes", "LeftFoot", _s(0.165, -0.105, 0.032), _s(0.170, -0.185, 0.028), True),
    # Right Leg (-X in Blender)
    ("RightUpperLeg", "Hips", _s(-0.103, -0.006, 0.990), _s(-0.129, 0.024, 0.520), True),
    ("RightLowerLeg", "RightUpperLeg", _s(-0.129, 0.024, 0.520), _s(-0.152, 0.018, 0.115), True),
    ("RightFoot", "RightLowerLeg", _s(-0.152, 0.018, 0.115), _s(-0.165, -0.105, 0.032), True),
    ("RightToes", "RightFoot", _s(-0.165, -0.105, 0.032), _s(-0.170, -0.185, 0.028), True),
]


def _smoothstep(edge0: float, edge1: float, x: float) -> float:
    if edge1 == edge0:
        return 1.0 if x >= edge1 else 0.0
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _point_seg_dist_and_t(p: Vector, a: Vector, b: Vector) -> Tuple[float, float]:
    ab = b - a
    len_sq = ab.length_squared
    if len_sq < 1e-10:
        return (p - a).length, 0.0
    t = max(0.0, min(1.0, (p - a).dot(ab) / len_sq))
    closest = a + ab * t
    return (p - closest).length, t


def _import_and_normalize_godiva(src_glb: Path) -> List[bpy.types.Object]:
    """Imports godiva.glb, scales uniformly to 1.64m with Z_min=0, applies transforms."""
    bpy.ops.import_scene.gltf(filepath=str(src_glb))
    bpy.context.view_layer.update()

    mesh_objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not mesh_objs:
        raise RuntimeError(f"No mesh objects found in {src_glb}")

    # Measure exact world bounds across all meshes
    z_min = float("inf")
    z_max = float("-inf")
    x_min = float("inf")
    x_max = float("-inf")
    for obj in mesh_objs:
        mw = obj.matrix_world
        for v in obj.data.vertices:
            wp = mw @ v.co
            z_min = min(z_min, wp.z)
            z_max = max(z_max, wp.z)
            x_min = min(x_min, wp.x)
            x_max = max(x_max, wp.x)

    raw_height = z_max - z_min
    scale = TARGET_HEIGHT_M / raw_height
    x_center = 0.5 * (x_min + x_max)

    # Bake world transform + uniform 1.64m scale + floor grounding directly into each mesh
    xform = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-x_center, 0.0, -z_min)))
    for obj in mesh_objs:
        mw = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data.transform(xform @ mw)
        obj.data.update()

    # Delete any leftover empty parent nodes from glTF import
    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.context.view_layer.update()
    # Verify exact height
    nz_min = min(v.co.z for o in mesh_objs for v in o.data.vertices)
    nz_max = max(v.co.z for o in mesh_objs for v in o.data.vertices)
    print(
        f"[Godiva] Normalized {len(mesh_objs)} meshes: "
        f"raw_h={raw_height:.4f}m -> Z=[{nz_min:.4f}, {nz_max:.4f}] (h={nz_max - nz_min:.4f}m)"
    )
    return mesh_objs


def _build_armature() -> bpy.types.Object:
    """Creates 23-bone SkeletonProfileHumanoid rig with clean forward-Z bone rolls."""
    arm_data = bpy.data.armatures.new("GodivaSkeleton")
    arm_obj = bpy.data.objects.new("GodivaRig", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    created: Dict[str, bpy.types.EditBone] = {}
    for b_name, parent_name, head, tail, use_def in BONE_SPECS:
        eb = arm_data.edit_bones.new(b_name)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        eb.use_deform = use_def
        if parent_name:
            eb.parent = created[parent_name]
            eb.use_connect = (eb.head - created[parent_name].tail).length < 0.002
        created[b_name] = eb

    # Align torso/head/leg bones so local +Z points character-forward (-Y in Blender)
    # -> In Godot (Y-up glTF), local +Z = +Z forward, local +Y = +Y up (ideal for LookAtModifier3D)
    for b_name, eb in created.items():
        if "Arm" in b_name or "Hand" in b_name or "Shoulder" in b_name:
            eb.align_roll(Vector((0.0, -1.0, 0.0)))
        elif "Foot" in b_name or "Toes" in b_name:
            eb.align_roll(Vector((0.0, 0.0, 1.0)))
        else:
            eb.align_roll(Vector((0.0, -1.0, 0.0)))

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def _compute_unified_weights(
    mesh_name: str,
    p: Vector,
    bone_segs: Dict[str, Tuple[Vector, Vector]],
) -> Dict[str, float]:
    """Computes smooth, anatomically separated skin weights shared across body & clothes.

    Using one spatial field guarantees T-shirt, Short, and Socks deform identically
    with the Godiva body surface underneath (zero cloth poke-through, zero leg sticking).
    """
    s = SCALE_FACTOR
    # Anatomical Z landmarks in 1.64m space
    z_ankle = (0.115 - RAW_Z_MIN) * s
    z_knee = (0.520 - RAW_Z_MIN) * s
    z_crotch = (0.915 - RAW_Z_MIN) * s
    z_hips = (1.010 - RAW_Z_MIN) * s
    z_spine = (1.145 - RAW_Z_MIN) * s
    z_chest = (1.310 - RAW_Z_MIN) * s
    z_upper_chest = (1.460 - RAW_Z_MIN) * s
    z_neck = (1.610 - RAW_Z_MIN) * s
    z_head = (1.715 - RAW_Z_MIN) * s

    # 1. Accessory-specific clean bindings
    if mesh_name == "Hair":
        # Hair follows Head firmly; lower back tips blend softly with Neck/UpperChest
        t_head = _smoothstep(z_neck + 0.02, z_head + 0.03, p.z)
        t_neck = (1.0 - t_head) * _smoothstep(z_upper_chest, z_neck + 0.02, p.z)
        t_uc = max(0.0, 1.0 - t_head - t_neck)
        return {"Head": t_head, "Neck": t_neck, "UpperChest": t_uc}

    if mesh_name in ("Necklace", "Staples"):
        t_neck = _smoothstep(z_neck - 0.03, z_neck + 0.05, p.z)
        return {"Neck": t_neck, "UpperChest": 1.0 - t_neck}

    if mesh_name == "Sneakers":
        side = "Left" if p.x >= 0.0 else "Right"
        t_toe = _smoothstep(-0.085 * s, -0.125 * s, p.y)
        t_ankle = _smoothstep(z_ankle - 0.02, z_ankle + 0.035, p.z)
        w_foot = (1.0 - t_toe) * (1.0 - t_ankle)
        return {f"{side}Foot": w_foot, f"{side}Toes": t_toe * (1.0 - t_ankle), f"{side}LowerLeg": t_ankle}

    if mesh_name in ("Glove", "Glove_Decorative"):
        side = "Left" if p.x >= 0.0 else "Right"
        wrist_pt = bone_segs[f"{side}Hand"][0]
        elbow_pt = bone_segs[f"{side}LowerArm"][0]
        arm_vec = (wrist_pt - elbow_pt)
        arm_len = arm_vec.length
        proj = (p - elbow_pt).dot(arm_vec.normalized()) / max(arm_len, 1e-4)
        t_hand = _smoothstep(0.86, 1.04, proj)
        return {f"{side}Hand": t_hand, f"{side}LowerArm": 1.0 - t_hand}

    # 2. Check if vertex lies on left/right arm (above waist, outside torso silhouette)
    # Shoulder joint starts at |x| ~= 0.175*s; torso ribcage max |x| ~= 0.16*s below armpit
    abs_x = abs(p.x)
    arm_side = "Left" if p.x >= 0.0 else "Right"
    sh_head = bone_segs[f"{arm_side}UpperArm"][0]
    arm_z_expected = sh_head.z - max(0.0, abs_x - abs(sh_head.x)) * 0.92
    # Armpit line separates hanging A-pose arm from torso side
    in_arm_band = (p.z > z_hips + 0.05) and (abs_x > 0.145 * s) and (abs(p.z - arm_z_expected) < 0.19 * s)
    # Stronger outer arm region
    if abs_x > 0.215 * s and p.z > z_hips:
        in_arm_band = True

    if in_arm_band:
        sh_a, sh_b = bone_segs[f"{arm_side}Shoulder"]
        ua_a, ua_b = bone_segs[f"{arm_side}UpperArm"]
        la_a, la_b = bone_segs[f"{arm_side}LowerArm"]
        ha_a, ha_b = bone_segs[f"{arm_side}Hand"]

        # Blend smoothly from UpperChest/Shoulder into UpperArm across armpit X
        w_arm_total = _smoothstep(0.145 * s, 0.225 * s, abs_x)
        # Arm chain local weights by distance along Shoulder->UpperArm->LowerArm->Hand
        d_sh, _ = _point_seg_dist_and_t(p, sh_a, sh_b)
        d_ua, t_ua = _point_seg_dist_and_t(p, ua_a, ua_b)
        d_la, t_la = _point_seg_dist_and_t(p, la_a, la_b)
        d_ha, _ = _point_seg_dist_and_t(p, ha_a, ha_b)

        # Piecewise smooth blend along arm bones
        sigma = 0.048 * s
        raw_arm = {
            f"{arm_side}Shoulder": math.exp(-((d_sh / sigma) ** 2)) * (1.0 - _smoothstep(0.25, 0.65, t_ua)),
            f"{arm_side}UpperArm": math.exp(-((d_ua / sigma) ** 2)),
            f"{arm_side}LowerArm": math.exp(-((d_la / sigma) ** 2)),
            f"{arm_side}Hand": math.exp(-((d_ha / sigma) ** 2)) * (1.0 if abs_x > 0.45 * s else 0.0),
        }
        arm_sum = sum(raw_arm.values())
        if arm_sum < 1e-8:
            raw_arm[f"{arm_side}UpperArm"] = 1.0
            arm_sum = 1.0
        arm_w = {k: (v / arm_sum) * w_arm_total for k, v in raw_arm.items() if v > 1e-6}

        # Remaining (1 - w_arm_total) goes to torso at this height
        w_torso = 1.0 - w_arm_total
        if w_torso > 1e-4:
            t_uc = _smoothstep(z_chest, z_upper_chest, p.z)
            arm_w["UpperChest"] = arm_w.get("UpperChest", 0.0) + w_torso * t_uc
            arm_w["Chest"] = arm_w.get("Chest", 0.0) + w_torso * (1.0 - t_uc)
        return arm_w

    # 3. Legs (below pelvis/hip crease — strictly side-separated so legs NEVER stick together!)
    if p.z < z_hips + 0.045 * s:
        leg_side = "Left" if p.x >= 0.0 else "Right"
        # Transition from legs into Hips across crotch -> hips band
        t_hips = _smoothstep(z_crotch - 0.025 * s, z_hips + 0.040 * s, p.z)
        # Keep center pelvis slightly more Hips-weighted at crotch
        center_boost = (1.0 - _smoothstep(0.02 * s, 0.09 * s, abs_x)) * _smoothstep(z_crotch - 0.06 * s, z_crotch + 0.02 * s, p.z)
        w_hips = min(1.0, max(t_hips, center_boost * 0.85))
        w_leg = 1.0 - w_hips

        w: Dict[str, float] = {}
        if w_hips > 1e-5:
            t_sp = _smoothstep(z_hips, z_spine, p.z)
            w["Hips"] = w_hips * (1.0 - t_sp * 0.35)
            if t_sp > 1e-5:
                w["Spine"] = w_hips * (t_sp * 0.35)

        if w_leg > 1e-5:
            # Smooth blend along UpperLeg -> LowerLeg -> Foot
            t_lower = 1.0 - _smoothstep(z_knee - 0.075 * s, z_knee + 0.075 * s, p.z)
            t_foot = 1.0 - _smoothstep(z_ankle - 0.035 * s, z_ankle + 0.045 * s, p.z)
            w_u = w_leg * (1.0 - t_lower)
            w_l = w_leg * t_lower * (1.0 - t_foot)
            w_f = w_leg * t_lower * t_foot
            if w_u > 1e-5:
                w[f"{leg_side}UpperLeg"] = w_u
            if w_l > 1e-5:
                w[f"{leg_side}LowerLeg"] = w_l
            if w_f > 1e-5:
                w[f"{leg_side}Foot"] = w_f
        return w

    # 4. Central Torso -> Neck -> Head chain (smooth overlapping Gaussian/linear bands by Z)
    chain_knots: List[Tuple[str, float]] = [
        ("Hips", z_hips),
        ("Spine", z_spine),
        ("Chest", z_chest),
        ("UpperChest", z_upper_chest),
        ("Neck", z_neck + 0.03 * s),
        ("Head", z_head + 0.04 * s),
    ]
    if p.z >= chain_knots[-1][1]:
        return {"Head": 1.0}
    if p.z <= chain_knots[0][1]:
        return {"Hips": 1.0}

    for idx in range(len(chain_knots) - 1):
        b0, z0 = chain_knots[idx]
        b1, z1 = chain_knots[idx + 1]
        if z0 <= p.z <= z1:
            t = _smoothstep(z0, z1, p.z)
            return {b0: 1.0 - t, b1: t}
    return {"UpperChest": 1.0}


def _skin_all_meshes(mesh_objs: List[bpy.types.Object], arm_obj: bpy.types.Object) -> None:
    """Binds all 10 Godiva meshes to the armature using unified anatomical weights."""
    bone_segs: Dict[str, Tuple[Vector, Vector]] = {
        b.name: (b.head_local.copy(), b.tail_local.copy())
        for b in arm_obj.data.bones
        if b.use_deform
    }
    deform_names = list(bone_segs.keys())

    for obj in mesh_objs:
        obj.vertex_groups.clear()
        vgs = {name: obj.vertex_groups.new(name=name) for name in deform_names}

        for v in obj.data.vertices:
            weights = _compute_unified_weights(obj.name, v.co, bone_segs)
            # Keep top 4 influences and normalize
            top = sorted(
                ((k, val) for k, val in weights.items() if val > 1e-5 and k in vgs),
                key=lambda item: item[1],
                reverse=True,
            )[:4]
            total = sum(val for _, val in top)
            if total < 1e-6:
                vgs["UpperChest"].add([v.index], 1.0, "REPLACE")
            else:
                for b_name, val in top:
                    vgs[b_name].add([v.index], val / total, "REPLACE")

        # Parent mesh to armature with ARMATURE modifier (preserving exact vertices)
        obj.parent = arm_obj
        mod = obj.modifiers.new(name="Armature", type="ARMATURE")
        mod.object = arm_obj

    print(f"[Godiva] Unified anatomical skinning applied to {len(mesh_objs)} meshes.")


# ---------------------------------------------------------------------------
# Procedural IK & Pose Helpers
# ---------------------------------------------------------------------------

def _solve_two_bone_ik(
    root: Vector,
    target: Vector,
    len1: float,
    len2: float,
    pole_dir: Vector,
) -> Vector:
    """Solves 2-bone analytical IK joint position (knee or elbow) with stretch clamp."""
    delta = target - root
    dist = max(0.03, min(delta.length, len1 + len2 - 0.003))
    fwd = delta.normalized()
    cos_a = max(-0.995, min(0.995, (len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist)))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    ortho = pole_dir - fwd * pole_dir.dot(fwd)
    if ortho.length_squared < 1e-8:
        ortho = Vector((0.0, -1.0, 0.0))
    ortho.normalize()
    return root + fwd * (len1 * cos_a) + ortho * (len1 * sin_a)


def _aim_pose_bone(arm_obj: bpy.types.Object, bone_name: str, target_dir: Vector, twist_rad: float = 0.0) -> None:
    """Rotates PoseBone in armature space so head->tail aligns with target_dir."""
    bpy.context.view_layer.update()
    pb = arm_obj.pose.bones[bone_name]
    pb.rotation_mode = "QUATERNION"
    cur_dir = (pb.tail - pb.head)
    if cur_dir.length_squared < 1e-10 or target_dir.length_squared < 1e-10:
        return
    cur_n = cur_dir.normalized()
    tgt_n = target_dir.normalized()
    dq = cur_n.rotation_difference(tgt_n)
    if abs(twist_rad) > 1e-5:
        dq = Quaternion(tgt_n, twist_rad) @ dq
    pivot = pb.head.copy()
    pb.matrix = Matrix.Translation(pivot) @ dq.to_matrix().to_4x4() @ Matrix.Translation(-pivot) @ pb.matrix
    bpy.context.view_layer.update()


def _reset_pose(arm_obj: bpy.types.Object) -> None:
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.location = Vector((0.0, 0.0, 0.0))
    bpy.context.view_layer.update()


def _solve_planted_leg(
    arm_obj: bpy.types.Object,
    side: str,
    ankle_target: Vector,
    knee_pole: Vector,
    foot_fwd: Vector,
) -> None:
    """Locks leg foot flat on floor using 2-bone IK from current Hips socket to ankle_target."""
    bpy.context.view_layer.update()
    u_name = f"{side}UpperLeg"
    l_name = f"{side}LowerLeg"
    f_name = f"{side}Foot"
    u_pb = arm_obj.pose.bones[u_name]
    l_pb = arm_obj.pose.bones[l_name]

    hip_pos = u_pb.head.copy()
    l1 = (u_pb.tail - u_pb.head).length
    l2 = (l_pb.tail - l_pb.head).length
    knee_pos = _solve_two_bone_ik(hip_pos, ankle_target, l1, l2, knee_pole)
    _aim_pose_bone(arm_obj, u_name, knee_pos - hip_pos)
    _aim_pose_bone(arm_obj, l_name, ankle_target - knee_pos)
    _aim_pose_bone(arm_obj, f_name, foot_fwd)


def _solve_arm_target(
    arm_obj: bpy.types.Object,
    side: str,
    wrist_target: Vector,
    elbow_pole: Vector,
    hand_dir: Vector,
) -> None:
    """Places arm via 2-bone IK from shoulder to wrist_target."""
    bpy.context.view_layer.update()
    u_name = f"{side}UpperArm"
    l_name = f"{side}LowerArm"
    h_name = f"{side}Hand"
    u_pb = arm_obj.pose.bones[u_name]
    l_pb = arm_obj.pose.bones[l_name]

    sh_pos = u_pb.head.copy()
    l1 = (u_pb.tail - u_pb.head).length
    l2 = (l_pb.tail - l_pb.head).length
    elbow_pos = _solve_two_bone_ik(sh_pos, wrist_target, l1, l2, elbow_pole)
    _aim_pose_bone(arm_obj, u_name, elbow_pos - sh_pos)
    _aim_pose_bone(arm_obj, l_name, wrist_target - elbow_pos)
    _aim_pose_bone(arm_obj, h_name, hand_dir)


def _set_all_bezier_smooth(action: bpy.types.Action) -> None:
    """Sets Bezier auto-clamped interpolation across Blender 5.x channelbags or legacy fcurves."""
    fcurves = []
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    fcurves.extend(bag.fcurves)
    elif hasattr(action, "fcurves"):
        fcurves.extend(action.fcurves)

    for fc in fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"


def _set_bone_euler_local(arm_obj: bpy.types.Object, bone_name: str, rx_deg: float, ry_deg: float, rz_deg: float) -> None:
    """Applies local XYZ Euler rotation (degrees) onto a PoseBone quaternion."""
    pb = arm_obj.pose.bones[bone_name]
    qx = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(rx_deg))
    qy = Quaternion(Vector((0.0, 1.0, 0.0)), math.radians(ry_deg))
    qz = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(rz_deg))
    pb.rotation_quaternion = qy @ qx @ qz


def _push_clip_to_nla(arm_obj: bpy.types.Object, action: bpy.types.Action, end_frame: int) -> None:
    """Pushes baked action into an NLA track trimmed cleanly to [1..end_frame]."""
    _set_all_bezier_smooth(action)
    track = arm_obj.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, 1, action)
    strip.action_frame_start = 1.0
    strip.action_frame_end = float(end_frame)
    strip.frame_start = 1.0
    strip.frame_end = float(end_frame)
    arm_obj.animation_data.action = None


def _push_clip_zero_based(
    arm_obj: bpy.types.Object,
    action: bpy.types.Action,
    total_frames: int,
    is_loop: bool,
) -> None:
    """Pushes 0-based Bezier action to NLA; loops trim duplicate end frame (N-1)."""
    _set_all_bezier_smooth(action)
    end_frame = (total_frames - 1) if is_loop else total_frames
    action.use_frame_range = True
    action.frame_start = 0.0
    action.frame_end = float(end_frame)
    track = arm_obj.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, 0, action)
    strip.action_frame_start = 0.0
    strip.action_frame_end = float(end_frame)
    strip.frame_start = 0.0
    strip.frame_end = float(end_frame)
    arm_obj.animation_data.action = None


def _insert_all_bone_keys(arm_obj: bpy.types.Object, frame: int) -> None:
    """Inserts rotation_quaternion for all pose bones and location for Hips."""
    for pb in arm_obj.pose.bones:
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if pb.name == "Hips":
            pb.keyframe_insert(data_path="location", frame=frame)


# ---------------------------------------------------------------------------
# Clip 1: 'idle' (3.0s @ 60 FPS, natural relaxed contrapposto breathing loop)
# ---------------------------------------------------------------------------

def _bake_idle_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes natural relaxed 60 FPS breathing idle loop (180 frames = 3.00s)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    action = bpy.data.actions.new(name="idle")
    arm_obj.animation_data.action = action

    s = SCALE_FACTOR
    l_ankle_rest = arm_obj.data.bones["LeftFoot"].head_local.copy()
    r_ankle_rest = arm_obj.data.bones["RightFoot"].head_local.copy()
    l_rest_dir = (
        arm_obj.data.bones["LeftFoot"].tail_local - l_ankle_rest
    ).normalized()
    r_rest_dir = (
        arm_obj.data.bones["RightFoot"].tail_local - r_ankle_rest
    ).normalized()
    # Slight relaxed natural foot turnout
    l_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(6.0)) @ l_rest_dir
    r_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(-8.0)) @ r_rest_dir
    # Relaxed contrapposto stance: left foot slightly forward & relaxed
    l_ankle_pos = l_ankle_rest + Vector((0.010 * s, -0.045 * s, 0.0))
    r_ankle_pos = r_ankle_rest + Vector((-0.008 * s, 0.015 * s, 0.0))

    # 180 frames = 3.0s calm breathing + weight sway (frame 181 matches 1; trim NLA to 180)
    key_frames = [1, 31, 61, 91, 121, 151, 181]
    for frame in key_frames:
        phase = ((frame - 1) / 180.0) * math.tau
        breath = 0.5 - 0.5 * math.cos(phase)        # smooth inhale/exhale
        sway = math.sin(phase)                      # slow subtle weight shift
        overlap = math.sin(phase - 0.45)            # delayed shoulder/head follow-through

        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        # Contrapposto hip settle toward right leg + subtle breathing dip
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((
            (-0.018 + 0.008 * sway) * s,
            (-0.014 - 0.005 * breath) * s,
            (0.004 * breath) * s,
        ))
        _set_bone_euler_local(arm_obj, "Hips", -1.5, -3.5 + 1.4 * sway, 2.2 - 1.0 * sway)

        # Spine & Chest counter-tilt + natural ribcage breathing expansion
        _set_bone_euler_local(arm_obj, "Spine", 1.2 - 1.5 * breath, 1.5 - 0.6 * sway, -1.2 + 0.5 * sway)
        _set_bone_euler_local(arm_obj, "Chest", -2.2 * breath, 1.2 - 0.5 * sway, -0.8 + 0.4 * sway)
        _set_bone_euler_local(arm_obj, "UpperChest", -1.4 * breath, 0.6, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", 1.4 * breath, 0.5 * overlap, 0.4 * overlap)
        _set_bone_euler_local(arm_obj, "Head", 1.8 * breath, 1.4 * overlap, -0.6 * overlap)

        # Relaxed dropped shoulders (breaks stiff A-pose collar line)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -5.5 + 1.8 * breath)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 5.5 - 1.8 * breath)
        bpy.context.view_layer.update()

        # Planted feet with soft knee relaxation
        _solve_planted_leg(arm_obj, "Left", l_ankle_pos, Vector((0.18, -1.0, 0.0)), l_foot_dir)
        _solve_planted_leg(arm_obj, "Right", r_ankle_pos, Vector((-0.14, -1.0, 0.0)), r_foot_dir)

        # Natural relaxed arms hanging down near outer thighs with gentle elbow curve
        l_wrist = Vector((
            (0.220 + 0.007 * sway) * s,
            (-0.065 - 0.008 * breath) * s,
            (0.955 + 0.007 * breath) * s,
        ))
        r_wrist = Vector((
            (-0.228 + 0.006 * sway) * s,
            (-0.048 - 0.007 * breath) * s,
            (0.950 + 0.007 * breath) * s,
        ))
        _solve_arm_target(arm_obj, "Left", l_wrist, Vector((0.50, 0.80, -0.20)), Vector((-0.14, -0.22, -0.96)))
        _solve_arm_target(arm_obj, "Right", r_wrist, Vector((-0.50, 0.80, -0.20)), Vector((0.14, -0.22, -0.96)))

        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=frame)

    _push_clip_to_nla(arm_obj, action, end_frame=180)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'idle' NLA clip (180 frames = 3.00s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 2: 'a_pose' (0.5s @ 60 FPS, clean reference A-pose)
# ---------------------------------------------------------------------------

def _bake_a_pose_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes clean reference A-pose clip (30 frames = 0.50s @ 60 FPS)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    action = bpy.data.actions.new(name="a_pose")
    arm_obj.animation_data.action = action

    for frame in (1, 31):
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)
        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=frame)

    _push_clip_to_nla(arm_obj, action, end_frame=30)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'a_pose' NLA clip (30 frames = 0.50s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 3: 't_pose' (0.5s @ 60 FPS, canonical horizontal-arms T-pose)
# ---------------------------------------------------------------------------

def _bake_t_pose_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes canonical T-pose clip with horizontal arms along +/-X (30 frames = 0.50s)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    action = bpy.data.actions.new(name="t_pose")
    arm_obj.animation_data.action = action

    for frame in (1, 31):
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)
        # Level clavicles and extend arms horizontally straight out along +X / -X
        _aim_pose_bone(arm_obj, "LeftShoulder", Vector((1.0, 0.0, 0.0)))
        _aim_pose_bone(arm_obj, "LeftUpperArm", Vector((1.0, 0.0, 0.0)))
        _aim_pose_bone(arm_obj, "LeftLowerArm", Vector((1.0, 0.0, 0.0)))
        _aim_pose_bone(arm_obj, "LeftHand", Vector((1.0, 0.0, 0.0)))

        _aim_pose_bone(arm_obj, "RightShoulder", Vector((-1.0, 0.0, 0.0)))
        _aim_pose_bone(arm_obj, "RightUpperArm", Vector((-1.0, 0.0, 0.0)))
        _aim_pose_bone(arm_obj, "RightLowerArm", Vector((-1.0, 0.0, 0.0)))
        _aim_pose_bone(arm_obj, "RightHand", Vector((-1.0, 0.0, 0.0)))

        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=frame)

    _push_clip_to_nla(arm_obj, action, end_frame=30)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 't_pose' NLA clip (30 frames = 0.50s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clips 4 & 5: 'turn_left' and 'turn_right' (0.80s @ 60 FPS, stepping pivot turns)
# ---------------------------------------------------------------------------

def _bake_turn_clip(arm_obj: bpy.types.Object, direction: int) -> None:
    """Bakes stepping turn-in-place loop (direction=+1 for turn_left, -1 for turn_right).

    Alternates clear foot lifts, knee bends, weight shifts, pelvic/shoulder twist lead,
    and natural arm counter-swing so feet step properly instead of sliding like a statue.
    """
    clip_name = "turn_left" if direction > 0 else "turn_right"
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    action = bpy.data.actions.new(name=clip_name)
    arm_obj.animation_data.action = action

    s = SCALE_FACTOR
    l_ankle_rest = arm_obj.data.bones["LeftFoot"].head_local.copy()
    r_ankle_rest = arm_obj.data.bones["RightFoot"].head_local.copy()
    l_rest_dir = (
        arm_obj.data.bones["LeftFoot"].tail_local - l_ankle_rest
    ).normalized()
    r_rest_dir = (
        arm_obj.data.bones["RightFoot"].tail_local - r_ankle_rest
    ).normalized()

    # 48 frames (0.80s @ 60 FPS): 2 crisp alternating pivot steps per cycle
    # Half 1 (frames 1..24): lead foot lifts & pivots; Half 2 (frames 25..48): trail foot lifts & catches up
    d = float(direction)
    # (frame, l_lift, r_lift, l_arc, r_arc, hip_x_shift, hip_drop, hip_yaw_deg, chest_yaw_deg)
    step_keys: List[Tuple[int, float, float, float, float, float, float, float, float]] = [
        (1,  0.00, 0.00,  0.00,  0.00, -0.032 * d, 0.022,  -4.0 * d,  +6.0 * d),
        (7,  0.75, 0.00, +0.45, -0.15, -0.048 * d, 0.010,  +2.0 * d, +12.0 * d),
        (13, 1.00, 0.00, +1.00, -0.25, -0.045 * d, 0.006,  +8.0 * d, +14.0 * d),
        (19, 0.35, 0.00, +0.55, -0.10, -0.015 * d, 0.028,  +6.0 * d, +10.0 * d),
        (25, 0.00, 0.00,  0.00,  0.00, +0.032 * d, 0.022,  +4.0 * d,  +8.0 * d),
        (31, 0.00, 0.75, -0.15, +0.45, +0.048 * d, 0.010,  +0.0 * d,  +6.0 * d),
        (37, 0.00, 1.00, -0.25, +1.00, +0.045 * d, 0.006,  -5.0 * d,  +4.0 * d),
        (43, 0.00, 0.35, -0.10, +0.55, +0.015 * d, 0.028,  -6.0 * d,  +5.0 * d),
        (49, 0.00, 0.00,  0.00,  0.00, -0.032 * d, 0.022,  -4.0 * d,  +6.0 * d),
    ]

    # When turning right (d < 0), swap lead/trail foot so Right foot steps first!
    for frame, a_lift, b_lift, a_arc, b_arc, hip_x, hip_drop, hip_yaw, chest_yaw in step_keys:
        if direction > 0:
            l_lift, r_lift = a_lift, b_lift
            l_arc, r_arc = a_arc, b_arc
        else:
            l_lift, r_lift = b_lift, a_lift
            l_arc, r_arc = b_arc, a_arc

        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        # Weight shift onto planted foot + vertical step bounce + pelvic yaw anticipation
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((hip_x * s, -hip_drop * s, 0.008 * s))
        _set_bone_euler_local(arm_obj, "Hips", 2.0, hip_yaw, -2.5 * (hip_x / 0.048))

        # Torso leads turn direction smoothly; head looks into turn
        _set_bone_euler_local(arm_obj, "Spine", 1.5, chest_yaw * 0.40, 0.0)
        _set_bone_euler_local(arm_obj, "Chest", 1.0, chest_yaw * 0.35, 0.0)
        _set_bone_euler_local(arm_obj, "UpperChest", 0.0, chest_yaw * 0.25, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", 0.0, 5.0 * d, 0.0)
        _set_bone_euler_local(arm_obj, "Head", 0.0, 8.0 * d, 0.0)

        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -4.5)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 4.5)
        bpy.context.view_layer.update()

        # Compute lifted & pivoting ankle targets in 1.64m Blender space (-Y forward, +Z up)
        lift_h = 0.085 * s
        step_fwd = 0.065 * s
        l_ankle = l_ankle_rest + Vector((
            0.015 * l_arc * s,
            (-step_fwd * l_arc if direction > 0 else step_fwd * l_arc),
            lift_h * l_lift,
        ))
        r_ankle = r_ankle_rest + Vector((
            -0.015 * r_arc * s,
            (step_fwd * r_arc if direction > 0 else -step_fwd * r_arc),
            lift_h * r_lift,
        ))

        # Foot pitches slightly toe-down when lifted, flat when planted; pivots outward in turn
        l_rot_z = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(14.0 * d * max(0.0, l_arc) + 5.0))
        r_rot_z = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(14.0 * d * max(0.0, r_arc) - 5.0))
        l_foot_dir = l_rot_z @ (l_rest_dir + Vector((0.0, 0.0, -0.25 * l_lift))).normalized()
        r_foot_dir = r_rot_z @ (r_rest_dir + Vector((0.0, 0.0, -0.25 * r_lift))).normalized()

        _solve_planted_leg(arm_obj, "Left", l_ankle, Vector((0.20, -1.0, 0.0)), l_foot_dir)
        _solve_planted_leg(arm_obj, "Right", r_ankle, Vector((-0.20, -1.0, 0.0)), r_foot_dir)

        # Arms counter-swing naturally with stepping legs for believable balance
        arm_swing = (l_lift - r_lift) * 0.055 * s
        l_wrist = Vector((
            0.245 * s,
            (-0.070 + arm_swing) * s,
            (0.975 - 0.015 * hip_drop / 0.028) * s,
        ))
        r_wrist = Vector((
            -0.245 * s,
            (-0.070 - arm_swing) * s,
            (0.975 - 0.015 * hip_drop / 0.028) * s,
        ))
        _solve_arm_target(arm_obj, "Left", l_wrist, Vector((0.55, 0.78, -0.18)), Vector((-0.14, -0.26, -0.95)))
        _solve_arm_target(arm_obj, "Right", r_wrist, Vector((-0.55, 0.78, -0.18)), Vector((0.14, -0.26, -0.95)))

        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=frame)

    _push_clip_to_nla(arm_obj, action, end_frame=48)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"[Godiva] Baked '{clip_name}' NLA clip (48 frames = 0.80s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 2: 'air_hump' (0.60s @ 60 FPS, Stormtrooper air-hump loop)
# ---------------------------------------------------------------------------

def _bake_air_hump_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes Stormtrooper air-hump gag loop (36 frames = 0.60s @ 60 FPS, IK-locked feet).

    Signature silhouette & rhythm:
    - Wide planted squat-bounce stance (feet locked cleanly to floor via 2-bone IK).
    - Snappy forward pelvic thrust with slight upward scoop + torso counter-lean back.
    - Bent elbows pumping rhythmically at hip/side height in counter-beat to hips.
    - Head stays level & stabilizes gaze with 2-frame overlap so Godot's LookAtModifier3D
      holds comedic deadpan eye contact on the player throughout the loop!
    """
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    action = bpy.data.actions.new(name="air_hump")
    arm_obj.animation_data.action = action

    s = SCALE_FACTOR
    # Slightly wider athletic stance than rest, soles dead-flat on floor
    l_ankle = arm_obj.data.bones["LeftFoot"].head_local.copy() + Vector((0.045 * s, 0.0, 0.0))
    r_ankle = arm_obj.data.bones["RightFoot"].head_local.copy() + Vector((-0.045 * s, 0.0, 0.0))
    l_rest_dir = (
        arm_obj.data.bones["LeftFoot"].tail_local - arm_obj.data.bones["LeftFoot"].head_local
    ).normalized()
    r_rest_dir = (
        arm_obj.data.bones["RightFoot"].tail_local - arm_obj.data.bones["RightFoot"].head_local
    ).normalized()
    l_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(10.0)) @ l_rest_dir
    r_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(-10.0)) @ r_rest_dir

    # Asymmetric snappy timing over 36 frames (0.60s @ 60 FPS):
    # frame 1: windup/back recoil
    # frame 8: rapid lunge acceleration
    # frame 15: PEAK FORWARD THRUST (snap + upward pelvic scoop + back lean)
    # frame 21: slight peak hang/overshoot settle
    # frame 29: pull back + deeper knee dip
    # frame 37: exact match of frame 1 (trimmed at 36 in NLA -> zero loop hitch!)
    pose_keys: List[Tuple[int, float, float, float]] = [
        # (frame, thrust [-1..+1], knee_dip [0..1], overlap_chest [-1..+1])
        (1,  -0.90, 0.72, -0.65),
        (8,  +0.18, 0.94, -0.18),
        (15, +1.00, 0.34, +0.95),
        (21, +0.74, 0.46, +0.86),
        (29, -0.64, 0.88, -0.48),
        (37, -0.90, 0.72, -0.65),
    ]

    for frame, thrust, dip, chest_lag in pose_keys:
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        # Hips local axes: X=left, Y=up (+Z world), Z=forward (-Y world)
        # Forward pelvic snap (+Z local = -Y world) + squat dip (-Y local)
        hip_fwd = (0.120 * thrust + 0.012) * s
        hip_drop = -(0.055 + 0.075 * dip) * s
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((0.0, hip_drop, hip_fwd))

        # Pelvic tilt: on forward thrust, tuck pelvis upward (-X local drives groin forward)
        _set_bone_euler_local(arm_obj, "Hips", -21.0 * thrust - 3.0, 0.0, 0.0)

        # Upper body counter-leans backward on forward thrust (classic Stormtrooper balance arc)
        _set_bone_euler_local(arm_obj, "Spine", 12.0 * chest_lag + 3.0, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Chest", 11.0 * chest_lag + 2.0, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "UpperChest", 6.0 * chest_lag, 0.0, 0.0)

        # Neck & Head counter-pitch (+X local pitches chin down) to hold dead-level forward gaze
        _set_bone_euler_local(arm_obj, "Neck", 5.0 * chest_lag, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Head", 8.0 * chest_lag, 0.0, 0.0)

        # Shoulders roll back on peak thrust
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, -9.0 * thrust, -4.0)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, 9.0 * thrust, 4.0)
        bpy.context.view_layer.update()

        # Lock feet cleanly flat on floor with knees flaring outward slightly on squat
        _solve_planted_leg(arm_obj, "Left", l_ankle, Vector((0.35, -1.0, 0.0)), l_foot_dir)
        _solve_planted_leg(arm_obj, "Right", r_ankle, Vector((-0.35, -1.0, 0.0)), r_foot_dir)

        # Classic Stormtrooper air-hump arms: bent elbows pumping at hip height in counter-beat
        hand_y = (-0.135 + 0.065 * thrust) * s
        hand_z = (1.035 - 0.065 * dip + 0.035 * thrust) * s
        hand_x = (0.245 + 0.030 * thrust) * s
        l_wrist = Vector((hand_x, hand_y, hand_z))
        r_wrist = Vector((-hand_x, hand_y, hand_z))
        _solve_arm_target(arm_obj, "Left", l_wrist, Vector((0.88, 0.50, -0.15)), Vector((-0.35, -0.82, -0.45)))
        _solve_arm_target(arm_obj, "Right", r_wrist, Vector((-0.88, 0.50, -0.15)), Vector((0.35, -0.82, -0.45)))

        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=frame)

    _push_clip_to_nla(arm_obj, action, end_frame=36)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'air_hump' NLA clip (36 frames = 0.60s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 7: 'booty_slap' (1.20s @ 60 FPS, Our World Moves hip-pop booty slap loop)
# ---------------------------------------------------------------------------

def _bake_booty_slap_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes rhythmic 2-beat partner booty-slap loop (72 frames = 1.20s @ 60 FPS).

    Faces imaginary partner in front (-Y Blender), plants feet flat on Z=0, thrusts
    hips forward on impact, holds partner hip with off-hand, and swings active hand
    from wide windup to forward slap contact in front of pelvis.
    """
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()

    action = bpy.data.actions.new(name="booty_slap")
    arm_obj.animation_data.action = action

    s = SCALE_FACTOR
    # Playful wide dance stance with flat planted sneakers
    l_ankle = arm_obj.data.bones["LeftFoot"].head_local.copy() + Vector((0.055 * s, -0.025 * s, 0.0))
    r_ankle = arm_obj.data.bones["RightFoot"].head_local.copy() + Vector((-0.055 * s, -0.025 * s, 0.0))
    l_rest_dir = (
        arm_obj.data.bones["LeftFoot"].tail_local - arm_obj.data.bones["LeftFoot"].head_local
    ).normalized()
    r_rest_dir = (
        arm_obj.data.bones["RightFoot"].tail_local - arm_obj.data.bones["RightFoot"].head_local
    ).normalized()
    l_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(12.0)) @ l_rest_dir
    r_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(-12.0)) @ r_rest_dir

    # 72 frames (1.20s @ 60 FPS), 2 alternating beats (Beat 1: Right slap, Beat 2: Left slap)
    # side_sign: -1 = Right hand slaps partner left cheek, +1 = Left hand slaps partner right cheek
    # slap_phase: 0.0 = neutral/groove, -1.0 = windup high/wide, +1.0 = SHARP SLAP CONTACT
    # (frame, side_sign, slap_phase, bounce_dip, hip_jolt)
    slap_keys: List[Tuple[int, float, float, float, float]] = [
        (1,  -1.0, -0.25, 0.45,  0.00),
        (10, -1.0, -1.00, 0.80, -0.15),  # Right hand windup peak
        (16, -1.0, +1.00, 0.25, +1.00),  # Right hand slap contact + hip thrust
        (21, -1.0, +0.85, 0.40, +0.55),  # Brief contact stick / follow-through
        (28, -1.0, +0.15, 0.72, -0.10),  # Rebound & bounce dip into transition
        (37, +1.0, -0.25, 0.45,  0.00),  # Shift weight to left slap beat
        (46, +1.0, -1.00, 0.80, -0.15),  # Left hand windup peak
        (52, +1.0, +1.00, 0.25, +1.00),  # Left hand slap contact + hip thrust
        (57, +1.0, +0.85, 0.40, +0.55),  # Brief contact stick / follow-through
        (64, +1.0, +0.15, 0.72, -0.10),  # Rebound & bounce dip back to right
        (73, -1.0, -0.25, 0.45,  0.00),  # Exact loop match with frame 1 (trimmed at 72)
    ]

    for frame, side_sign, slap_phase, dip, jolt in slap_keys:
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        # In Hips local axes: +X = left, +Y = up, +Z = forward (-Y Blender)
        hip_x = (0.025 * side_sign) * s
        hip_y = -(0.045 + 0.055 * dip - 0.012 * jolt) * s
        hip_z = (0.025 + 0.055 * jolt) * s
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((hip_x, hip_y, hip_z))

        _set_bone_euler_local(arm_obj, "Hips", 6.0 - 4.0 * jolt, -8.0 * side_sign, -3.0 * side_sign)
        _set_bone_euler_local(arm_obj, "Spine", 10.0 + 3.0 * dip, 4.0 * side_sign, 0.0)
        _set_bone_euler_local(arm_obj, "Chest", 8.0 + 2.0 * dip, 5.0 * side_sign, 0.0)
        _set_bone_euler_local(arm_obj, "UpperChest", 5.0, 4.0 * side_sign, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -13.0, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -17.0, 0.0, 0.0)

        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 8.0, -5.0)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -8.0, 5.0)
        bpy.context.view_layer.update()

        # Lock sneakers flat on floor with playful bent dance knees
        _solve_planted_leg(arm_obj, "Left", l_ankle, Vector((0.30, -1.0, 0.0)), l_foot_dir)
        _solve_planted_leg(arm_obj, "Right", r_ankle, Vector((-0.30, -1.0, 0.0)), r_foot_dir)

        # Partner booty target in front of Godiva (-Y in Blender world space)
        partner_cheek = Vector((0.09 * side_sign * s, -0.32 * s, (1.15 - 0.02 * dip) * s))
        if slap_phase < 0.0:
            t_wind = -slap_phase
            wind_pos = Vector((0.36 * side_sign * s, -0.14 * s, 1.16 * s))
            active_wrist = partner_cheek.lerp(wind_pos, t_wind)
            active_hand_dir = Vector((-0.35 * side_sign, -0.90, -0.25)).normalized()
        else:
            rebound = 1.0 - slap_phase
            active_wrist = partner_cheek.lerp(
                Vector((0.22 * side_sign * s, -0.27 * s, 1.18 * s)),
                rebound,
            )
            active_hand_dir = Vector((-0.75 * side_sign, -0.60, -0.28)).normalized()

        # Off-hand holds partner's opposite outer hip in front
        off_sign = -side_sign
        off_wrist = Vector((0.23 * off_sign * s, -0.31 * s, (1.16 - 0.02 * dip) * s))
        off_hand_dir = Vector((-0.35 * off_sign, -0.90, -0.20)).normalized()

        active_elbow_pole = Vector((0.35 * side_sign, 0.55, -0.76)).normalized()
        off_elbow_pole = Vector((0.20 * off_sign, 0.45, -0.87)).normalized()

        if side_sign < 0.0:
            _solve_arm_target(arm_obj, "Right", active_wrist, active_elbow_pole, active_hand_dir)
            _solve_arm_target(arm_obj, "Left", off_wrist, off_elbow_pole, off_hand_dir)
        else:
            _solve_arm_target(arm_obj, "Left", active_wrist, active_elbow_pole, active_hand_dir)
            _solve_arm_target(arm_obj, "Right", off_wrist, off_elbow_pole, off_hand_dir)

        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=frame)

    _push_clip_to_nla(arm_obj, action, end_frame=72)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'booty_slap' NLA clip (72 frames = 1.20s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Shared Pose & Gait Helpers for Locomotion / Stance / Traversal Clips
# ---------------------------------------------------------------------------

def _get_rest_foot_info(arm_obj: bpy.types.Object) -> Tuple[Vector, Vector, Vector, Vector]:
    """Returns (l_ankle_rest, r_ankle_rest, l_foot_dir, r_foot_dir) in 1.64m space."""
    l_ankle = arm_obj.data.bones["LeftFoot"].head_local.copy()
    r_ankle = arm_obj.data.bones["RightFoot"].head_local.copy()
    l_dir = (arm_obj.data.bones["LeftFoot"].tail_local - l_ankle).normalized()
    r_dir = (arm_obj.data.bones["RightFoot"].tail_local - r_ankle).normalized()
    return l_ankle, r_ankle, l_dir, r_dir


def _pose_stand_ready(arm_obj: bpy.types.Object) -> None:
    """Applies balanced athletic ready stance matching transition endpoints."""
    _reset_pose(arm_obj)
    l_ankle, r_ankle, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    l_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(5.0)) @ l_dir
    r_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(-5.0)) @ r_dir

    hips = arm_obj.pose.bones["Hips"]
    hips.location = Vector((0.0, -0.025, 0.0))
    _set_bone_euler_local(arm_obj, "Hips", 2.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Spine", 3.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Chest", 2.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Neck", -2.5, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Head", -2.5, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -4.5)
    _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 4.5)
    bpy.context.view_layer.update()

    _solve_planted_leg(arm_obj, "Left", l_ankle, Vector((0.16, -1.0, 0.0)), l_foot_dir)
    _solve_planted_leg(arm_obj, "Right", r_ankle, Vector((-0.16, -1.0, 0.0)), r_foot_dir)
    _solve_arm_target(
        arm_obj, "Left", Vector((0.20, -0.06, 0.78)), Vector((0.45, 0.85, -0.20)), Vector((-0.12, -0.24, -0.96))
    )
    _solve_arm_target(
        arm_obj, "Right", Vector((-0.20, -0.06, 0.78)), Vector((-0.45, 0.85, -0.20)), Vector((0.12, -0.24, -0.96))
    )


def _pose_crouch(
    arm_obj: bpy.types.Object,
    hip_drop: float = -0.45,
    hip_x: float = 0.0,
    hip_yaw: float = 0.0,
    torso_lean: float = 1.0,
    l_ankle_pos: Vector | None = None,
    r_ankle_pos: Vector | None = None,
    l_foot_dir: Vector | None = None,
    r_foot_dir: Vector | None = None,
    l_wrist: Vector | None = None,
    r_wrist: Vector | None = None,
) -> None:
    """Applies balanced crouched pose with hips lowered ~0.45m (<1.30m height)."""
    _reset_pose(arm_obj)
    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)

    hips = arm_obj.pose.bones["Hips"]
    hips.location = Vector((hip_x, hip_drop, -0.04))
    _set_bone_euler_local(arm_obj, "Hips", 8.0 * torso_lean, hip_yaw, 0.0)
    _set_bone_euler_local(arm_obj, "Spine", 14.0 * torso_lean, -hip_yaw * 0.45, 0.0)
    _set_bone_euler_local(arm_obj, "Chest", 10.0 * torso_lean, -hip_yaw * 0.35, 0.0)
    _set_bone_euler_local(arm_obj, "UpperChest", 4.0 * torso_lean, -hip_yaw * 0.20, 0.0)
    _set_bone_euler_local(arm_obj, "Neck", -16.0 * torso_lean, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Head", -18.0 * torso_lean, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 4.0, -5.0)
    _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -4.0, 5.0)
    bpy.context.view_layer.update()

    la = l_ankle_pos if l_ankle_pos is not None else (l_rest + Vector((0.025, -0.09, 0.0)))
    ra = r_ankle_pos if r_ankle_pos is not None else (r_rest + Vector((-0.025, 0.11, 0.0)))
    lfd = l_foot_dir if l_foot_dir is not None else (Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(8.0)) @ l_dir)
    rfd = r_foot_dir if r_foot_dir is not None else (Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(-10.0)) @ r_dir)

    _solve_planted_leg(arm_obj, "Left", la, Vector((0.32, -1.0, 0.25)), lfd)
    _solve_planted_leg(arm_obj, "Right", ra, Vector((-0.32, -1.0, 0.25)), rfd)

    lw = l_wrist if l_wrist is not None else Vector((0.20, -0.22, 0.44))
    rw = r_wrist if r_wrist is not None else Vector((-0.20, -0.22, 0.44))
    _solve_arm_target(arm_obj, "Left", lw, Vector((0.55, 0.78, -0.20)), Vector((-0.10, -0.75, -0.65)))
    _solve_arm_target(arm_obj, "Right", rw, Vector((-0.55, 0.78, -0.20)), Vector((0.10, -0.75, -0.65)))


def _pose_prone(
    arm_obj: bpy.types.Object,
    hip_z: float = 0.135,
    hip_y_shift: float = 0.0,
    hip_roll: float = 0.0,
    spine_yaw: float = 0.0,
    breath_arch: float = 0.0,
    l_ankle_pos: Vector | None = None,
    r_ankle_pos: Vector | None = None,
    l_knee_pole: Vector | None = None,
    r_knee_pole: Vector | None = None,
    l_wrist: Vector | None = None,
    r_wrist: Vector | None = None,
) -> None:
    """Applies belly-down prone pose on Z=0 floor (<0.45m idle / <0.50m crawl)."""
    _reset_pose(arm_obj)
    hip_rest_z = arm_obj.data.bones["Hips"].head_local.z
    hips = arm_obj.pose.bones["Hips"]
    hips.location = Vector((0.0, hip_z - hip_rest_z, hip_y_shift))
    _set_bone_euler_local(arm_obj, "Hips", 90.0, hip_roll, 0.0)
    _set_bone_euler_local(arm_obj, "Spine", -1.0 - breath_arch * 0.4, spine_yaw * 0.4, -hip_roll * 0.4)
    _set_bone_euler_local(arm_obj, "Chest", -1.5 - breath_arch * 0.4, spine_yaw * 0.4, -hip_roll * 0.4)
    _set_bone_euler_local(arm_obj, "UpperChest", -2.0, spine_yaw * 0.2, 0.0)
    _set_bone_euler_local(arm_obj, "Neck", -12.0, -spine_yaw * 0.4, 0.0)
    _set_bone_euler_local(arm_obj, "Head", -16.0, -spine_yaw * 0.5, 0.0)
    _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 10.0, 6.0)
    _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -10.0, -6.0)
    bpy.context.view_layer.update()

    la = l_ankle_pos if l_ankle_pos is not None else Vector((0.15, 0.72, 0.155))
    ra = r_ankle_pos if r_ankle_pos is not None else Vector((-0.15, 0.72, 0.155))
    lkp = l_knee_pole if l_knee_pole is not None else Vector((0.65, 0.0, -0.35))
    rkp = r_knee_pole if r_knee_pole is not None else Vector((-0.65, 0.0, -0.35))
    _solve_planted_leg(arm_obj, "Left", la, lkp, Vector((0.05, 0.72, -0.69)))
    _solve_planted_leg(arm_obj, "Right", ra, rkp, Vector((-0.05, 0.72, -0.69)))

    lw = l_wrist if l_wrist is not None else Vector((0.13, -0.56, 0.075))
    rw = r_wrist if r_wrist is not None else Vector((-0.13, -0.56, 0.075))
    _solve_arm_target(
        arm_obj, "Left", lw, Vector((0.85, 0.35, -0.10)), Vector((-0.30, -0.95, 0.0))
    )
    _solve_arm_target(
        arm_obj, "Right", rw, Vector((-0.85, 0.35, -0.10)), Vector((0.30, -0.95, 0.0))
    )


# ---------------------------------------------------------------------------
# Clip 8: 'walk' (64 frames, 1.05s trimmed loop, ~1.4 m/s in-place stride)
# ---------------------------------------------------------------------------

def _bake_walk_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes smooth 60 FPS Bezier walk loop (64 frames, trimmed 0..63)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="walk")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    stride_half = 0.29

    # Bake every 4 frames over 0..64 (64 matches 0; trimmed to 0..63)
    for frame in range(0, 65, 4):
        u = frame / 64.0
        phase = u * math.tau
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        # Double-frequency vertical bob (lowest at contact, highest at mid-stance)
        bob = -0.062 - 0.024 * math.cos(2.0 * phase)
        lat = -0.024 * math.cos(phase)
        hip_yaw = 6.5 * math.cos(phase)
        hip_roll = 3.2 * math.sin(phase)

        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((lat, bob, 0.0))
        _set_bone_euler_local(arm_obj, "Hips", 3.5, hip_yaw, hip_roll)
        _set_bone_euler_local(arm_obj, "Spine", 3.0, -hip_yaw * 0.55, -hip_roll * 0.5)
        _set_bone_euler_local(arm_obj, "Chest", 2.0, -hip_yaw * 0.55, -hip_roll * 0.4)
        _set_bone_euler_local(arm_obj, "UpperChest", 1.0, -hip_yaw * 0.30, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -3.0, hip_yaw * 0.20, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -3.0, hip_yaw * 0.20, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -4.5)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 4.5)
        bpy.context.view_layer.update()

        for side_idx, (side, rest_a, rest_d, off_x) in enumerate([
            ("Left", l_rest, l_dir, 0.005),
            ("Right", r_rest, r_dir, -0.005),
        ]):
            su = (u + 0.5 * side_idx) % 1.0
            if su <= 0.52:
                # Stance: planted cleanly on Z=0 moving backward from -stride_half to +stride_half
                st = su / 0.52
                y_off = -stride_half + (2.0 * stride_half) * st
                z_off = 0.014 * max(0.0, 1.0 - st / 0.12) + 0.025 * _smoothstep(0.84, 1.0, st)
                pitch = 16.0 * max(0.0, 1.0 - st / 0.14) - 24.0 * _smoothstep(0.82, 1.0, st)
            else:
                # Swing: lifts smoothly forward
                sw = (su - 0.52) / 0.48
                y_off = stride_half - (2.0 * stride_half) * _smoothstep(0.0, 1.0, sw)
                z_off = 0.095 * math.sin(sw * math.pi)
                pitch = -20.0 * math.sin(sw * math.pi) + 14.0 * _smoothstep(0.70, 1.0, sw)

            ankle_tgt = rest_a + Vector((off_x, y_off, z_off))
            foot_rot = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(pitch))
            foot_dir = (foot_rot @ rest_d).normalized()
            pole_x = 0.18 if side == "Left" else -0.18
            _solve_planted_leg(arm_obj, side, ankle_tgt, Vector((pole_x, -1.0, 0.05)), foot_dir)

        # Counter-swinging arms
        l_arm_y = -0.05 + 0.22 * math.cos(phase)
        r_arm_y = -0.05 - 0.22 * math.cos(phase)
        l_arm_z = 0.78 + 0.05 * abs(math.cos(phase))
        r_arm_z = 0.78 + 0.05 * abs(math.cos(phase))
        _solve_arm_target(
            arm_obj, "Left", Vector((0.21, l_arm_y, l_arm_z)), Vector((0.40, 0.88, -0.15)), Vector((-0.08, -0.35, -0.93))
        )
        _solve_arm_target(
            arm_obj, "Right", Vector((-0.21, r_arm_y, r_arm_z)), Vector((-0.40, 0.88, -0.15)), Vector((0.08, -0.35, -0.93))
        )

        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=64, is_loop=True)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'walk' NLA clip (64 frames, trimmed 0..63 = 1.05s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 9: 'run' (40 frames, 0.65s trimmed loop, ~4.0 m/s in-place sprint)
# ---------------------------------------------------------------------------

def _bake_run_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes athletic 60 FPS Bezier sprint loop (40 frames, trimmed 0..39)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="run")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    stride_half = 0.36

    for frame in range(0, 41, 2):
        u = frame / 40.0
        phase = u * math.tau
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        # Spring bounce with brief flight apex
        bob = -0.075 - 0.055 * math.cos(2.0 * phase)
        lat = -0.022 * math.cos(phase)
        hip_yaw = 9.0 * math.cos(phase)

        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((lat, bob, -0.02))
        _set_bone_euler_local(arm_obj, "Hips", 8.0, hip_yaw, 4.0 * math.sin(phase))
        _set_bone_euler_local(arm_obj, "Spine", 9.0, -hip_yaw * 0.6, -2.0 * math.sin(phase))
        _set_bone_euler_local(arm_obj, "Chest", 7.0, -hip_yaw * 0.6, 0.0)
        _set_bone_euler_local(arm_obj, "UpperChest", 4.0, -hip_yaw * 0.3, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -11.0, hip_yaw * 0.3, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -12.0, hip_yaw * 0.3, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 4.0, -4.0)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -4.0, 4.0)
        bpy.context.view_layer.update()

        for side_idx, (side, rest_a, rest_d) in enumerate([
            ("Left", l_rest, l_dir),
            ("Right", r_rest, r_dir),
        ]):
            su = (u + 0.5 * side_idx) % 1.0
            if su <= 0.38:
                # Short explosive stance push
                st = su / 0.38
                y_off = -stride_half * 0.75 + (1.75 * stride_half) * st
                z_off = 0.02 * _smoothstep(0.75, 1.0, st)
                pitch = 8.0 * (1.0 - st) - 28.0 * _smoothstep(0.65, 1.0, st)
            else:
                # High knee recovery swing
                sw = (su - 0.38) / 0.62
                y_off = stride_half - (1.75 * stride_half) * _smoothstep(0.0, 1.0, sw)
                z_off = 0.25 * math.sin(sw * math.pi)
                pitch = -28.0 * (1.0 - sw) + 12.0 * sw

            ankle_tgt = rest_a + Vector((0.0, y_off, z_off))
            foot_rot = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(pitch))
            foot_dir = (foot_rot @ rest_d).normalized()
            pole_x = 0.18 if side == "Left" else -0.18
            _solve_planted_leg(arm_obj, side, ankle_tgt, Vector((pole_x, -1.0, 0.15)), foot_dir)

        # Compact 90-deg bent arm sprint pump
        l_fwd = math.cos(phase)
        r_fwd = -l_fwd
        l_wrist = Vector((0.21, -0.16 + 0.24 * l_fwd, 0.94 - 0.14 * l_fwd))
        r_wrist = Vector((-0.21, -0.16 + 0.24 * r_fwd, 0.94 - 0.14 * r_fwd))
        _solve_arm_target(
            arm_obj, "Left", l_wrist, Vector((0.40, 0.85, -0.25)), Vector((-0.08, -0.85, 0.50))
        )
        _solve_arm_target(
            arm_obj, "Right", r_wrist, Vector((-0.40, 0.85, -0.25)), Vector((0.08, -0.85, 0.50))
        )

        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=40, is_loop=True)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'run' NLA clip (40 frames, trimmed 0..39 = 0.65s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 10: 'crouch_idle' (120 frames, 1.983s trimmed loop, hips -0.45m)
# ---------------------------------------------------------------------------

def _bake_crouch_idle_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes balanced crouched idle breathing loop (120 frames, trimmed 0..119)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="crouch_idle")
    arm_obj.animation_data.action = action

    for frame in [0, 20, 40, 60, 80, 100, 120]:
        phase = (frame / 120.0) * math.tau
        breath = 0.5 - 0.5 * math.cos(phase)
        sway = math.sin(phase)
        bpy.context.scene.frame_set(frame)
        _pose_crouch(
            arm_obj,
            hip_drop=-0.45 + 0.008 * breath,
            hip_x=0.008 * sway,
            hip_yaw=1.5 * sway,
            torso_lean=1.0 - 0.05 * breath,
            l_wrist=Vector((0.20, -0.22 - 0.006 * breath, 0.44 + 0.008 * breath)),
            r_wrist=Vector((-0.20, -0.22 - 0.006 * breath, 0.44 + 0.008 * breath)),
        )
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=120, is_loop=True)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'crouch_idle' NLA clip (120 frames, trimmed 0..119 = 1.983s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 11: 'crouch_walk' (72 frames, 1.183s trimmed loop, <1.30m clearance)
# ---------------------------------------------------------------------------

def _bake_crouch_walk_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes stealth crouched walk loop fitting <1.30m clearance (72 frames, 0..71)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="crouch_walk")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    stride_half = 0.19

    for frame in range(0, 73, 4):
        u = frame / 72.0
        phase = u * math.tau
        bpy.context.scene.frame_set(frame)

        bob = -0.465 - 0.018 * math.cos(2.0 * phase)
        lat = -0.025 * math.cos(phase)
        hip_yaw = 6.0 * math.cos(phase)

        la = Vector()
        ra = Vector()
        lfd = Vector()
        rfd = Vector()
        for side_idx, (rest_a, rest_d, off_x) in enumerate([
            (l_rest, l_dir, 0.02),
            (r_rest, r_dir, -0.02),
        ]):
            su = (u + 0.5 * side_idx) % 1.0
            if su <= 0.54:
                st = su / 0.54
                y_off = -stride_half + (2.0 * stride_half) * st
                z_off = 0.015 * _smoothstep(0.84, 1.0, st)
                pitch = -18.0 * _smoothstep(0.80, 1.0, st)
            else:
                sw = (su - 0.54) / 0.46
                y_off = stride_half - (2.0 * stride_half) * _smoothstep(0.0, 1.0, sw)
                z_off = 0.068 * math.sin(sw * math.pi)
                pitch = -15.0 * math.sin(sw * math.pi) + 10.0 * _smoothstep(0.70, 1.0, sw)
            pos = rest_a + Vector((off_x, y_off, z_off))
            fdir = (Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(pitch)) @ rest_d).normalized()
            if side_idx == 0:
                la, lfd = pos, fdir
            else:
                ra, rfd = pos, fdir

        arm_swing = 0.10 * math.cos(phase)
        _pose_crouch(
            arm_obj,
            hip_drop=bob,
            hip_x=lat,
            hip_yaw=hip_yaw,
            torso_lean=1.15,
            l_ankle_pos=la,
            r_ankle_pos=ra,
            l_foot_dir=lfd,
            r_foot_dir=rfd,
            l_wrist=Vector((0.21, -0.18 + arm_swing, 0.45)),
            r_wrist=Vector((-0.21, -0.18 - arm_swing, 0.45)),
        )
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=72, is_loop=True)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'crouch_walk' NLA clip (72 frames, trimmed 0..71 = 1.183s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 12: 'prone_idle' (120 frames, 1.983s trimmed loop, <0.45m height)
# ---------------------------------------------------------------------------

def _bake_prone_idle_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes belly-down prone breathing loop (<0.45m height, 120 frames, 0..119)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="prone_idle")
    arm_obj.animation_data.action = action

    for frame in [0, 20, 40, 60, 80, 100, 120]:
        phase = (frame / 120.0) * math.tau
        breath = 0.5 - 0.5 * math.cos(phase)
        bpy.context.scene.frame_set(frame)
        _pose_prone(
            arm_obj,
            hip_z=0.135 + 0.004 * breath,
            breath_arch=2.0 * breath,
            l_wrist=Vector((0.13, -0.56, 0.075 + 0.004 * breath)),
            r_wrist=Vector((-0.13, -0.56, 0.075 + 0.004 * breath)),
        )
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=120, is_loop=True)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'prone_idle' NLA clip (120 frames, trimmed 0..119 = 1.983s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 13: 'prone_crawl' (90 frames, 1.483s trimmed loop, <0.50m clearance)
# ---------------------------------------------------------------------------

def _bake_prone_crawl_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes commando belly-crawl loop (<0.50m clearance, 90 frames, 0..89)."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="prone_crawl")
    arm_obj.animation_data.action = action

    for frame in range(0, 91, 5):
        u = frame / 90.0
        phase = u * math.tau
        bpy.context.scene.frame_set(frame)

        # Left arm pulls when Right knee drives forward (cross-crawl coordination)
        c_val = math.cos(phase)
        s_val = math.sin(phase)

        hip_roll = 6.5 * c_val
        spine_yaw = -6.0 * c_val

        # Left arm: forward reach (-0.70m) -> pull back (-0.36m); Right arm opposite
        l_arm_y = -0.53 - 0.16 * c_val
        l_arm_z = 0.085 + 0.045 * max(0.0, s_val)
        r_arm_y = -0.53 + 0.16 * c_val
        r_arm_z = 0.085 + 0.045 * max(0.0, -s_val)

        # Opposite leg kicks/tucks knee out horizontally along floor
        l_leg_t = max(0.0, -c_val)
        r_leg_t = max(0.0, c_val)
        la = Vector((0.15 + 0.14 * l_leg_t, 0.72 - 0.24 * l_leg_t, 0.155))
        ra = Vector((-0.15 - 0.14 * r_leg_t, 0.72 - 0.24 * r_leg_t, 0.155))
        lkp = Vector((0.65 + 0.35 * l_leg_t, 0.0, -0.25 + 0.35 * l_leg_t)).normalized()
        rkp = Vector((-0.65 - 0.35 * r_leg_t, 0.0, -0.25 + 0.35 * r_leg_t)).normalized()

        _pose_prone(
            arm_obj,
            hip_z=0.135,
            hip_y_shift=-0.025 * abs(s_val),
            hip_roll=hip_roll,
            spine_yaw=spine_yaw,
            breath_arch=1.5,
            l_ankle_pos=la,
            r_ankle_pos=ra,
            l_knee_pole=lkp,
            r_knee_pole=rkp,
            l_wrist=Vector((0.18, l_arm_y, l_arm_z)),
            r_wrist=Vector((-0.18, r_arm_y, r_arm_z)),
        )
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=90, is_loop=True)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'prone_crawl' NLA clip (90 frames, trimmed 0..89 = 1.483s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clips 14 & 15: 'crouch_to_prone' & 'prone_to_crouch' (30 frames each, 0.50s)
# ---------------------------------------------------------------------------

def _bake_crouch_to_prone_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes smooth 30-frame one-shot transition from crouch_idle to prone_idle."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="crouch_to_prone")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    hip_rest_z = arm_obj.data.bones["Hips"].head_local.z

    # Frame 0: crouch_idle
    bpy.context.scene.frame_set(0)
    _pose_crouch(arm_obj)
    _insert_all_bone_keys(arm_obj, 0)

    # Frame 9: reach hands forward toward floor, weight drops forward
    bpy.context.scene.frame_set(9)
    _pose_crouch(
        arm_obj,
        hip_drop=-0.52,
        torso_lean=1.45,
        l_ankle_pos=l_rest + Vector((0.03, 0.04, 0.02)),
        r_ankle_pos=r_rest + Vector((-0.03, 0.16, 0.02)),
        l_wrist=Vector((0.16, -0.44, 0.14)),
        r_wrist=Vector((-0.16, -0.44, 0.14)),
    )
    _insert_all_bone_keys(arm_obj, 9)

    # Frame 19: hands planted, legs extending backward
    bpy.context.scene.frame_set(19)
    _reset_pose(arm_obj)
    hips = arm_obj.pose.bones["Hips"]
    hips.location = Vector((0.0, 0.25 - hip_rest_z, 0.02))
    _set_bone_euler_local(arm_obj, "Hips", 64.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Spine", 4.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Chest", -4.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Neck", -22.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Head", -26.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    _solve_planted_leg(arm_obj, "Left", Vector((0.15, 0.56, 0.14)), Vector((0.30, -0.2, -0.95)), Vector((0.05, 0.72, -0.69)))
    _solve_planted_leg(arm_obj, "Right", Vector((-0.15, 0.56, 0.14)), Vector((-0.30, -0.2, -0.95)), Vector((-0.05, 0.72, -0.69)))
    _solve_arm_target(arm_obj, "Left", Vector((0.15, -0.52, 0.07)), Vector((0.80, 0.40, -0.25)), Vector((-0.25, -0.95, 0.0)))
    _solve_arm_target(arm_obj, "Right", Vector((-0.15, -0.52, 0.07)), Vector((-0.80, 0.40, -0.25)), Vector((0.25, -0.95, 0.0)))
    _insert_all_bone_keys(arm_obj, 19)

    # Frame 30: exact prone_idle
    bpy.context.scene.frame_set(30)
    _pose_prone(arm_obj)
    _insert_all_bone_keys(arm_obj, 30)

    _push_clip_zero_based(arm_obj, action, total_frames=30, is_loop=False)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'crouch_to_prone' NLA clip (30 frames = 0.50s @ 60 FPS)")


def _bake_prone_to_crouch_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes smooth 30-frame one-shot transition from prone_idle to crouch_idle."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="prone_to_crouch")
    arm_obj.animation_data.action = action

    l_rest, r_rest, _, _ = _get_rest_foot_info(arm_obj)
    hip_rest_z = arm_obj.data.bones["Hips"].head_local.z

    # Frame 0: prone_idle
    bpy.context.scene.frame_set(0)
    _pose_prone(arm_obj)
    _insert_all_bone_keys(arm_obj, 0)

    # Frame 10: push chest off floor, tuck knees forward
    bpy.context.scene.frame_set(10)
    _reset_pose(arm_obj)
    hips = arm_obj.pose.bones["Hips"]
    hips.location = Vector((0.0, 0.26 - hip_rest_z, 0.02))
    _set_bone_euler_local(arm_obj, "Hips", 60.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Spine", 5.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Chest", -2.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Neck", -20.0, 0.0, 0.0)
    _set_bone_euler_local(arm_obj, "Head", -24.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    _solve_planted_leg(arm_obj, "Left", Vector((0.15, 0.44, 0.14)), Vector((0.32, -0.4, -0.85)), Vector((0.05, 0.72, -0.69)))
    _solve_planted_leg(arm_obj, "Right", Vector((-0.15, 0.50, 0.14)), Vector((-0.32, -0.4, -0.85)), Vector((-0.05, 0.72, -0.69)))
    _solve_arm_target(arm_obj, "Left", Vector((0.17, -0.46, 0.07)), Vector((0.75, 0.45, -0.25)), Vector((-0.25, -0.95, 0.0)))
    _solve_arm_target(arm_obj, "Right", Vector((-0.17, -0.46, 0.07)), Vector((-0.75, 0.45, -0.25)), Vector((0.25, -0.95, 0.0)))
    _insert_all_bone_keys(arm_obj, 10)

    # Frame 21: feet planted, rising to crouch
    bpy.context.scene.frame_set(21)
    _pose_crouch(
        arm_obj,
        hip_drop=-0.50,
        torso_lean=1.35,
        l_ankle_pos=l_rest + Vector((0.025, -0.04, 0.0)),
        r_ankle_pos=r_rest + Vector((-0.025, 0.14, 0.0)),
        l_wrist=Vector((0.19, -0.34, 0.24)),
        r_wrist=Vector((-0.19, -0.34, 0.24)),
    )
    _insert_all_bone_keys(arm_obj, 21)

    # Frame 30: exact crouch_idle
    bpy.context.scene.frame_set(30)
    _pose_crouch(arm_obj)
    _insert_all_bone_keys(arm_obj, 30)

    _push_clip_zero_based(arm_obj, action, total_frames=30, is_loop=False)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'prone_to_crouch' NLA clip (30 frames = 0.50s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 16: 'step_up' (40 frames, 0.667s one-shot, <=1.1m step/low block)
# ---------------------------------------------------------------------------

def _bake_step_up_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes in-place 40-frame step-up traversal clip synced to Godot root tween."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="step_up")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)

    # (frame, hip_x, hip_z, hip_y, spine_x, l_ankle_off, r_ankle_off, l_pitch, r_pitch, l_w, r_w)
    keys = [
        (0,   0.00, -0.025,  0.00,  3.0, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00),   0.0,   0.0, (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78)),
        (6,  -0.04, -0.110,  0.02, 12.0, (0.00,  0.02, 0.04), ( 0.00,  0.02, 0.00), -12.0,   0.0, (0.21,  0.04, 0.76), (-0.21, -0.10, 0.78)),
        (15, -0.03, -0.050, -0.04, 18.0, (0.01, -0.24, 0.34), ( 0.00,  0.08, 0.00), -10.0, -14.0, (0.22, -0.22, 0.94), (-0.22,  0.06, 0.80)),
        (26,  0.02,  0.020, -0.02, 10.0, (0.00, -0.08, 0.06), ( 0.00, -0.16, 0.24),  -4.0, -18.0, (0.21,  0.02, 0.88), (-0.21, -0.18, 0.92)),
        (33,  0.00, -0.070,  0.00,  8.0, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00),   0.0,   0.0, (0.20, -0.08, 0.78), (-0.20, -0.08, 0.78)),
        (40,  0.00, -0.025,  0.00,  3.0, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00),   0.0,   0.0, (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78)),
    ]

    for frame, hx, hz, hy, spx, la_off, ra_off, lp, rp, lw, rw in keys:
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((hx, hz, hy))
        _set_bone_euler_local(arm_obj, "Hips", spx * 0.4, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Spine", spx * 0.6, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Chest", spx * 0.4, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -spx * 0.5, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -spx * 0.6, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -4.5)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 4.5)
        bpy.context.view_layer.update()

        lfd = (Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(lp)) @ l_dir).normalized()
        rfd = (Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(rp)) @ r_dir).normalized()
        _solve_planted_leg(arm_obj, "Left", l_rest + Vector(la_off), Vector((0.22, -1.0, 0.25)), lfd)
        _solve_planted_leg(arm_obj, "Right", r_rest + Vector(ra_off), Vector((-0.22, -1.0, 0.25)), rfd)
        _solve_arm_target(arm_obj, "Left", Vector(lw), Vector((0.45, 0.85, -0.20)), Vector((-0.10, -0.35, -0.93)))
        _solve_arm_target(arm_obj, "Right", Vector(rw), Vector((-0.45, 0.85, -0.20)), Vector((0.10, -0.35, -0.93)))
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=40, is_loop=False)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'step_up' NLA clip (40 frames = 0.667s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 17: 'climb_mid' (70 frames, 1.167s one-shot, 1.1-1.8m block climb)
# ---------------------------------------------------------------------------

def _bake_climb_mid_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes in-place 70-frame mid-wall climb: reach up, pull chest, knee/foot mantle."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="climb_mid")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)

    # (frame, hip_z, hip_y, spine_x, sh_lift, l_ankle_off, r_ankle_off, l_w, r_w, elbow_pole_y)
    keys = [
        (0,  -0.025,  0.00,  3.0,  -4.5, (0.00,  0.00, 0.00), (0.00,  0.00, 0.00), (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78),  0.85),
        (9,  -0.160,  0.03, 15.0,  -2.0, (0.00,  0.02, 0.00), (0.00,  0.02, 0.00), (0.22, -0.20, 0.82), (-0.22, -0.20, 0.82),  0.65),
        (19, -0.020, -0.03, -8.0, +24.0, (0.00,  0.06, 0.10), (0.00,  0.06, 0.04), (0.20, -0.34, 1.56), (-0.20, -0.34, 1.56), -0.65),
        (33,  0.040,  0.00, 12.0, +10.0, (0.02,  0.08, 0.24), (-0.02, -0.18, 0.42), (0.21, -0.28, 1.12), (-0.21, -0.28, 1.12),  0.50),
        (46, -0.120, -0.04, 28.0,  -6.0, (0.02,  0.04, 0.14), (-0.02, -0.24, 0.34), (0.23, -0.24, 0.74), (-0.23, -0.24, 0.74),  0.75),
        (59, -0.100, -0.01, 10.0,  -4.5, (0.00, -0.02, 0.00), (0.00, -0.02, 0.00), (0.21, -0.10, 0.78), (-0.21, -0.10, 0.78),  0.85),
        (70, -0.025,  0.00,  3.0,  -4.5, (0.00,  0.00, 0.00), (0.00,  0.00, 0.00), (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78),  0.85),
    ]

    for frame, hz, hy, spx, sh_lift, la_off, ra_off, lw, rw, ep_y in keys:
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((0.0, hz, hy))
        _set_bone_euler_local(arm_obj, "Hips", spx * 0.35, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Spine", spx * 0.45, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Chest", spx * 0.35, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -spx * 0.45, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -spx * 0.50, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 4.0, sh_lift)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -4.0, -sh_lift)
        bpy.context.view_layer.update()

        _solve_planted_leg(arm_obj, "Left", l_rest + Vector(la_off), Vector((0.24, -1.0, 0.25)), l_dir)
        _solve_planted_leg(arm_obj, "Right", r_rest + Vector(ra_off), Vector((-0.24, -1.0, 0.25)), r_dir)
        _solve_arm_target(arm_obj, "Left", Vector(lw), Vector((0.55, ep_y, -0.30)), Vector((-0.10, -0.85, 0.50)))
        _solve_arm_target(arm_obj, "Right", Vector(rw), Vector((-0.55, ep_y, -0.30)), Vector((0.10, -0.85, 0.50)))
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=70, is_loop=False)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'climb_mid' NLA clip (70 frames = 1.167s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 18: 'pull_up_high' (110 frames, 1.833s one-shot, 1.8-2.8m high mantle)
# ---------------------------------------------------------------------------

def _bake_pull_up_high_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes in-place 110-frame jump-grab, hang, pull-up, and mantle clip."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="pull_up_high")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)

    # (frame, hip_z, hip_y, spine_x, sh_lift, l_ankle_off, r_ankle_off, l_w, r_w, ep_y)
    keys = [
        (0,   -0.025,  0.00,  3.0,  -4.5, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00), (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78),  0.85),
        (11,  -0.220,  0.04, 18.0,  -4.0, (0.00,  0.02, 0.00), ( 0.00,  0.02, 0.00), (0.22,  0.18, 0.72), (-0.22,  0.18, 0.72),  0.80),
        (21,   0.040, -0.04, -6.0, +28.0, (0.00,  0.10, 0.04), ( 0.00,  0.14, 0.08), (0.19, -0.22, 1.82), (-0.19, -0.22, 1.82), -0.60),
        (35,  -0.040,  0.02, -4.0, +24.0, (0.00,  0.16, 0.14), ( 0.00,  0.18, 0.16), (0.19, -0.18, 1.72), (-0.19, -0.18, 1.72), -0.60),
        (55,   0.030,  0.00, 12.0, +10.0, (0.02, -0.12, 0.28), (-0.02, -0.04, 0.22), (0.22, -0.24, 1.18), (-0.22, -0.24, 1.18),  0.55),
        (74,  -0.110, -0.05, 30.0,  -6.0, (0.02,  0.04, 0.16), (-0.02, -0.24, 0.36), (0.23, -0.24, 0.74), (-0.23, -0.24, 0.74),  0.75),
        (92,  -0.140, -0.02, 14.0,  -4.5, (0.00, -0.04, 0.02), ( 0.00, -0.06, 0.02), (0.21, -0.14, 0.76), (-0.21, -0.14, 0.76),  0.85),
        (102, -0.070,  0.00,  6.0,  -4.5, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00), (0.20, -0.08, 0.78), (-0.20, -0.08, 0.78),  0.85),
        (110, -0.025,  0.00,  3.0,  -4.5, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00), (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78),  0.85),
    ]

    for frame, hz, hy, spx, sh_lift, la_off, ra_off, lw, rw, ep_y in keys:
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((0.0, hz, hy))
        _set_bone_euler_local(arm_obj, "Hips", spx * 0.35, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Spine", spx * 0.45, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Chest", spx * 0.35, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -spx * 0.45, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -spx * 0.50, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 4.0, sh_lift)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -4.0, -sh_lift)
        bpy.context.view_layer.update()

        _solve_planted_leg(arm_obj, "Left", l_rest + Vector(la_off), Vector((0.24, -1.0, 0.25)), l_dir)
        _solve_planted_leg(arm_obj, "Right", r_rest + Vector(ra_off), Vector((-0.24, -1.0, 0.25)), r_dir)
        _solve_arm_target(arm_obj, "Left", Vector(lw), Vector((0.55, ep_y, -0.25)), Vector((-0.10, -0.75, 0.65)))
        _solve_arm_target(arm_obj, "Right", Vector(rw), Vector((-0.55, ep_y, -0.25)), Vector((0.10, -0.75, 0.65)))
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=110, is_loop=False)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'pull_up_high' NLA clip (110 frames = 1.833s @ 60 FPS)")


# ---------------------------------------------------------------------------
# Clip 19: 'drop_down' (45 frames, 0.75s one-shot, step off ledge & land)
# ---------------------------------------------------------------------------

def _bake_drop_down_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes in-place 45-frame drop-down step off ledge and crouch-absorb landing."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = bpy.data.actions.new(name="drop_down")
    arm_obj.animation_data.action = action

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)

    # (frame, hip_z, hip_y, spine_x, l_ankle_off, r_ankle_off, lp, rp, l_w, r_w)
    keys = [
        (0,  -0.025,  0.00,  3.0, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00),   0.0,   0.0, (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78)),
        (8,  -0.040, -0.02,  8.0, (0.01, -0.18, 0.02), ( 0.00,  0.04, 0.02), -14.0,  -6.0, (0.26, -0.12, 0.88), (-0.26, -0.08, 0.88)),
        (19, -0.060,  0.00, 10.0, (0.02, -0.08, 0.06), (-0.02,  0.06, 0.08), -22.0, -22.0, (0.34, -0.16, 1.05), (-0.34, -0.16, 1.05)),
        (29, -0.300, -0.02, 22.0, (0.02, -0.05, 0.00), (-0.02,  0.04, 0.00),   0.0,   0.0, (0.24, -0.26, 0.62), (-0.24, -0.26, 0.62)),
        (37, -0.110,  0.00,  9.0, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00),   0.0,   0.0, (0.21, -0.12, 0.76), (-0.21, -0.12, 0.76)),
        (45, -0.025,  0.00,  3.0, (0.00,  0.00, 0.00), ( 0.00,  0.00, 0.00),   0.0,   0.0, (0.20, -0.06, 0.78), (-0.20, -0.06, 0.78)),
    ]

    for frame, hz, hy, spx, la_off, ra_off, lp, rp, lw, rw in keys:
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)
        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((0.0, hz, hy))
        _set_bone_euler_local(arm_obj, "Hips", spx * 0.35, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Spine", spx * 0.45, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Chest", spx * 0.35, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -spx * 0.45, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -spx * 0.55, 0.0, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -4.5)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 4.5)
        bpy.context.view_layer.update()

        lfd = (Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(lp)) @ l_dir).normalized()
        rfd = (Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(rp)) @ r_dir).normalized()
        _solve_planted_leg(arm_obj, "Left", l_rest + Vector(la_off), Vector((0.24, -1.0, 0.25)), lfd)
        _solve_planted_leg(arm_obj, "Right", r_rest + Vector(ra_off), Vector((-0.24, -1.0, 0.25)), rfd)
        _solve_arm_target(arm_obj, "Left", Vector(lw), Vector((0.55, 0.75, -0.25)), Vector((-0.15, -0.45, -0.88)))
        _solve_arm_target(arm_obj, "Right", Vector(rw), Vector((-0.55, 0.75, -0.25)), Vector((0.15, -0.45, -0.88)))
        _insert_all_bone_keys(arm_obj, frame)

    _push_clip_zero_based(arm_obj, action, total_frames=45, is_loop=False)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[Godiva] Baked 'drop_down' NLA clip (45 frames = 0.750s @ 60 FPS)")


def _verify_stance_clearances(
    arm_obj: bpy.types.Object,
    mesh_objs: List[bpy.types.Object],
) -> None:
    """Verifies deformed Z height bounds for crouch/prone clips against clearance targets."""
    limits = {
        "crouch_idle": (0.0, 1.30, [0, 60]),
        "crouch_walk": (0.0, 1.30, [0, 18, 36, 54]),
        "prone_idle": (0.0, 0.45, [0, 60]),
        "prone_crawl": (0.0, 0.50, [0, 20, 45, 70]),
    }
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    for clip_name, (min_ok, max_ok, sample_frames) in limits.items():
        act = bpy.data.actions.get(clip_name)
        arm_obj.animation_data.action = act
        z_min = float("inf")
        z_max = float("-inf")
        for f in sample_frames:
            bpy.context.scene.frame_set(f)
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            for obj in mesh_objs:
                ev = obj.evaluated_get(dg)
                me = ev.to_mesh()
                mw = ev.matrix_world
                for v in me.vertices:
                    wz = (mw @ v.co).z
                    z_min = min(z_min, wz)
                    z_max = max(z_max, wz)
                ev.to_mesh_clear()
        print(f"[Godiva] Clearance '{clip_name}': Z=[{z_min:.3f}m, {z_max:.3f}m] (limit <={max_ok:.2f}m)")
        if z_max > max_ok:
            raise RuntimeError(f"{clip_name} height {z_max:.3f}m exceeds clearance {max_ok:.2f}m")
        if z_min < min_ok - 0.04:
            raise RuntimeError(f"{clip_name} clips floor: z_min={z_min:.3f}m")
    arm_obj.animation_data.action = None
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False
    _reset_pose(arm_obj)


# ---------------------------------------------------------------------------
# Verification Preview Renderer
# ---------------------------------------------------------------------------

def _render_previews(arm_obj: bpy.types.Object, out_dir: Path) -> None:
    """Renders 4 verification views (side + front-3/4 at frame 10 windup and frame 16 contact)."""
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 640

    world = bpy.data.worlds.get("PrevWorld") or bpy.data.worlds.new("PrevWorld")
    scene.world = world
    if world.node_tree:
        bg = world.node_tree.nodes.get("Background")
        if bg:
            bg.inputs["Color"].default_value = (0.28, 0.30, 0.34, 1.0)
            bg.inputs["Strength"].default_value = 1.0

    focus = Vector((0.0, 0.0, 0.82))
    lights = []
    for i, (off, energy) in enumerate([
        ((2.0, -2.6, 2.0), 180.0),
        ((-2.2, -1.8, 1.4), 120.0),
        ((0.0, 2.6, 1.8), 140.0),
    ]):
        ld = bpy.data.lights.new(f"PrevL_{i}", "AREA")
        ld.energy = energy
        ld.size = 2.0
        lo = bpy.data.objects.new(f"PrevL_{i}", ld)
        scene.collection.objects.link(lo)
        lo.location = focus + Vector(off)
        lo.rotation_euler = (focus - lo.location).to_track_quat("-Z", "Y").to_euler()
        lights.append(lo)

    cd = bpy.data.cameras.new("PrevCam")
    cam = bpy.data.objects.new("PrevCam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam

    shots = [
        ("booty_slap", 10, "booty_slap_windup_side", Vector((2.3, -0.3, 0.08))),
        ("booty_slap", 10, "booty_slap_windup_front34", Vector((-1.8, -1.8, 0.12))),
        ("booty_slap", 16, "booty_slap_contact_side", Vector((2.3, -0.3, 0.08))),
        ("booty_slap", 16, "booty_slap_contact_front34", Vector((-1.8, -1.8, 0.12))),
    ]
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = True
    for clip_name, frame, tag, offset in shots:
        act = bpy.data.actions.get(clip_name)
        arm_obj.animation_data.action = act
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        cam.location = focus + offset
        cam.rotation_euler = (focus - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(out_dir / f"godiva_{tag}.png")
        bpy.ops.render.render(write_still=True)
    for tr in arm_obj.animation_data.nla_tracks:
        tr.mute = False

    # Clean up preview camera/lights and restore rest pose
    arm_obj.animation_data.action = None
    _reset_pose(arm_obj)
    for lo in lights:
        bpy.data.objects.remove(lo, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def run_pipeline(src_glb: Path, out_glb: Path, preview_dir: Path | None = None) -> None:
    clean_scene()
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    bpy.context.scene.frame_start = 0
    bpy.context.scene.frame_end = 250

    mesh_objs = _import_and_normalize_godiva(src_glb)
    arm_obj = _build_armature()
    _skin_all_meshes(mesh_objs, arm_obj)

    _bake_idle_clip(arm_obj)
    _bake_a_pose_clip(arm_obj)
    _bake_t_pose_clip(arm_obj)
    _bake_turn_clip(arm_obj, direction=1)
    _bake_turn_clip(arm_obj, direction=-1)
    _bake_air_hump_clip(arm_obj)
    _bake_booty_slap_clip(arm_obj)

    _bake_walk_clip(arm_obj)
    _bake_run_clip(arm_obj)
    _bake_crouch_idle_clip(arm_obj)
    _bake_crouch_walk_clip(arm_obj)
    _bake_prone_idle_clip(arm_obj)
    _bake_prone_crawl_clip(arm_obj)
    _bake_crouch_to_prone_clip(arm_obj)
    _bake_prone_to_crouch_clip(arm_obj)
    _bake_step_up_clip(arm_obj)
    _bake_climb_mid_clip(arm_obj)
    _bake_pull_up_high_clip(arm_obj)
    _bake_drop_down_clip(arm_obj)

    _verify_stance_clearances(arm_obj, mesh_objs)

    if preview_dir is not None:
        _render_previews(arm_obj, preview_dir)

    export_godot_glb(
        filepath=out_glb,
        export_animations=True,
        apply_modifiers=False,
        save_blend=False,
    )


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent.parent
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description="Rig and animate Godiva at 1.64m height.")
    parser.add_argument(
        "--src",
        type=Path,
        default=repo_root / "assets/models/godiva/godiva.glb",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=repo_root / "assets/models/godiva/godiva_rigged.glb",
    )
    parser.add_argument(
        "--preview-dir",
        type=Path,
        default=None,
    )
    args = parser.parse_args(argv)
    run_pipeline(args.src, args.out, args.preview_dir)


if __name__ == "__main__":
    main()
