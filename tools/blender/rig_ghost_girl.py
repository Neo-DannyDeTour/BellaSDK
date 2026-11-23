#!/usr/bin/env python3
"""Headless Blender 5.x rigger and 60 FPS animator for Ghost Girl (1.58m humanoid + cape bones).

Imports assets/models/ghost_girl/ghost_girl.glb (16 modular meshes), builds a
SkeletonProfileHumanoid-compatible 27-bone armature + 3 chest-parented cape drape bones
(Cape_L, Cape_C, Cape_R), skins all 16 meshes with zero unweighted vertices while preserving
all 52 head + 6 eyelash ARKit shape keys, bakes 60 FPS Bezier in-place NLA clips ('idle',
'walk', 'run') with N-1 loop seam trimming, and exports assets/models/ghost_girl/ghost_girl_rigged.glb.
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
from mathutils import Matrix, Quaternion, Vector, kdtree
from common.armature import (
    add_bone,
    create_action,
    create_armature,
    parent_mesh_to_armature,
    push_action_to_nla,
)
from common.exporter import clean_scene, export_godot_glb

FPS: int = 60
TARGET_HEIGHT_M: float = 1.58
FACIAL_BONE_NAMES: Tuple[str, ...] = (
    "LeftEye",
    "RightEye",
    "Jaw",
    "Tongue_01",
    "Tongue_02",
)
CAPE_BONE_NAMES: Tuple[str, ...] = ("Cape_L", "Cape_C", "Cape_R")
EXCLUDED_AUTO_KEY_BONES: set[str] = set(FACIAL_BONE_NAMES)


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


def _slice_centroid(
    verts: List[Vector],
    z_min: float,
    z_max: float,
    x_min: float = -10.0,
    x_max: float = 10.0,
) -> Vector | None:
    pts = [v for v in verts if z_min <= v.z <= z_max and x_min <= v.x <= x_max]
    if not pts:
        return None
    acc = Vector((0.0, 0.0, 0.0))
    for p in pts:
        acc += p
    return acc / float(len(pts))


def _bake_world_transform_safe(obj: bpy.types.Object) -> None:
    """Bake non-identity world transform into mesh & shape keys without corrupting morphs."""
    mw = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = Matrix.Identity(4)

    ident = Matrix.Identity(4)
    delta = sum(abs(mw[r][c] - ident[r][c]) for r in range(4) for c in range(4))
    if delta <= 1e-6:
        return

    obj.data.transform(mw)
    if obj.data.shape_keys is not None:
        for kb in obj.data.shape_keys.key_blocks:
            for item in kb.data:
                item.co = mw @ item.co
    obj.data.update()


def _import_ghost_girl_meshes(src_glb: Path) -> Dict[str, List[bpy.types.Object]]:
    """Import ghost_girl.glb, bake transforms safely, and classify all 16 modular meshes."""
    bpy.ops.import_scene.gltf(filepath=str(src_glb))
    bpy.context.view_layer.update()

    all_meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not all_meshes:
        raise RuntimeError(f"No mesh objects found in {src_glb}")

    for obj in all_meshes:
        _bake_world_transform_safe(obj)

    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH" or not obj.name.lower().startswith("ghostgirl_"):
            bpy.data.objects.remove(obj, do_unlink=True)

    bpy.context.view_layer.update()
    all_meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

    classified: Dict[str, List[bpy.types.Object]] = {
        "body": [],
        "head": [],
        "eye_l": [],
        "eye_r": [],
        "eyelashes": [],
        "teeth_upper": [],
        "teeth_lower": [],
        "tongue": [],
        "hair_cap": [],
        "hair_cards": [],
        "hood": [],
        "cape": [],
        "croptop": [],
        "skirt": [],
        "gloves": [],
        "boots": [],
    }
    for obj in all_meshes:
        n = obj.name.lower()
        if n == "ghostgirl_head":
            classified["head"].append(obj)
        elif n == "ghostgirl_eye_l":
            classified["eye_l"].append(obj)
        elif n == "ghostgirl_eye_r":
            classified["eye_r"].append(obj)
        elif "lash" in n:
            classified["eyelashes"].append(obj)
        elif "teeth_upper" in n:
            classified["teeth_upper"].append(obj)
        elif "teeth_lower" in n:
            classified["teeth_lower"].append(obj)
        elif "tongue" in n:
            classified["tongue"].append(obj)
        elif "hair_cap" in n:
            classified["hair_cap"].append(obj)
        elif "hair_card" in n:
            classified["hair_cards"].append(obj)
        elif "hood" in n:
            classified["hood"].append(obj)
        elif "cape" in n:
            classified["cape"].append(obj)
        elif "croptop" in n:
            classified["croptop"].append(obj)
        elif "skirt" in n:
            classified["skirt"].append(obj)
        elif "glove" in n:
            classified["gloves"].append(obj)
        elif "boot" in n:
            classified["boots"].append(obj)
        else:
            classified["body"].append(obj)

    if not classified["body"] or len(all_meshes) != 16:
        raise RuntimeError(f"Expected 16 GhostGirl meshes, got {len(all_meshes)}: {[o.name for o in all_meshes]}")

    z_min = min(v.co.z for o in all_meshes for v in o.data.vertices)
    z_max = max(v.co.z for o in all_meshes for v in o.data.vertices)
    print(f"[rig_ghost_girl] Imported {len(all_meshes)} meshes | Z=[{z_min:.4f}, {z_max:.4f}]m")
    return classified


def _mesh_center(objs: List[bpy.types.Object], fallback: Vector) -> Vector:
    if not objs:
        return fallback
    pts = [v.co for o in objs for v in o.data.vertices]
    if not pts:
        return fallback
    mins = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    maxs = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return (mins + maxs) * 0.5


def _measure_landmarks(classified: Dict[str, List[bpy.types.Object]]) -> Dict[str, Vector]:
    """Measure T-pose anatomical, facial, and cape landmarks from Ghost Girl's 16 meshes."""
    body_objs = classified["body"]
    boot_objs = classified["boots"]
    head_objs = classified["head"]
    all_objs = [o for lst in classified.values() for o in lst]
    verts = [v.co.copy() for o in body_objs for v in o.data.vertices]
    boot_verts = [v.co.copy() for o in boot_objs for v in o.data.vertices]
    head_verts = [v.co.copy() for o in head_objs for v in o.data.vertices]
    all_verts = [v.co.copy() for o in all_objs for v in o.data.vertices]

    z_min = min(v.z for v in all_verts)
    # Use head crown (ignoring hood height above crown) for anatomical joint proportions
    z_head_max = max((v.z for v in head_verts), default=TARGET_HEIGHT_M)
    h = max(TARGET_HEIGHT_M, z_head_max - z_min)

    c_hips = _slice_centroid(verts, z_min + 0.50 * h, z_min + 0.56 * h, -0.18, 0.18)
    chest_pts = [v for v in verts if (z_min + 0.65 * h) <= v.z <= (z_min + 0.78 * h) and -0.14 <= v.x <= 0.14]
    c_neck = _slice_centroid(head_verts + verts, z_min + 0.81 * h, z_min + 0.85 * h, -0.09, 0.09)
    c_head = _slice_centroid(head_verts, z_min + 0.86 * h, z_min + 0.96 * h, -0.13, 0.13)

    y_hips = c_hips.y if c_hips else 0.0
    y_chest = 0.5 * (min(v.y for v in chest_pts) + max(v.y for v in chest_pts)) if chest_pts else y_hips
    y_neck = c_neck.y if c_neck else y_chest
    y_head = c_head.y if c_head else y_neck

    c_l_knee = _slice_centroid(verts, z_min + 0.26 * h, z_min + 0.32 * h, 0.01, 0.35)
    c_r_knee = _slice_centroid(verts, z_min + 0.26 * h, z_min + 0.32 * h, -0.35, -0.01)
    c_l_ank = _slice_centroid(boot_verts or verts, z_min + 0.04 * h, z_min + 0.10 * h, 0.01, 0.35)
    c_r_ank = _slice_centroid(boot_verts or verts, z_min + 0.04 * h, z_min + 0.10 * h, -0.35, -0.01)

    x_leg_knee = 0.5 * ((abs(c_l_knee.x) if c_l_knee else 0.090) + (abs(c_r_knee.x) if c_r_knee else 0.090))
    x_leg_ank = 0.5 * ((abs(c_l_ank.x) if c_l_ank else 0.095) + (abs(c_r_ank.x) if c_r_ank else 0.095))
    x_hip_socket = max(0.072, min(0.110, x_leg_knee * 0.92))
    y_knee = 0.5 * ((c_l_knee.y if c_l_knee else y_hips) + (c_r_knee.y if c_r_knee else y_hips))
    y_ank = 0.5 * ((c_l_ank.y if c_l_ank else y_hips) + (c_r_ank.y if c_r_ank else y_hips))

    foot_verts = [v for v in (boot_verts or verts) if v.z <= z_min + 0.06 * h]
    y_foot_front = min((v.y for v in foot_verts), default=y_ank - 0.16)
    y_ball = y_ank + 0.65 * (y_foot_front - y_ank)
    y_toes = y_foot_front + 0.012

    arm_verts = [v for v in verts if abs(v.x) > 0.20 and v.z > z_min + 0.62 * h]
    max_arm_x = max((abs(v.x) for v in arm_verts), default=0.74)
    x_sh_head = 0.032
    x_sh_tail = 0.145
    arm_span = max(0.32, max_arm_x - x_sh_tail)
    x_elbow = x_sh_tail + 0.40 * arm_span
    x_wrist = x_sh_tail + 0.77 * arm_span
    x_hand_tip = x_sh_tail + 0.94 * arm_span

    def _arm_yz(x_target: float, default_y: float, default_z: float) -> Tuple[float, float]:
        band = [v for v in arm_verts if abs(abs(v.x) - x_target) < 0.045]
        if not band:
            return default_y, default_z
        return sum(v.y for v in band) / float(len(band)), sum(v.z for v in band) / float(len(band))

    y_arm_sh, z_arm_sh = _arm_yz(x_sh_tail + 0.05, y_chest + 0.01, z_min + 0.805 * h)
    y_arm_el, z_arm_el = _arm_yz(x_elbow, y_arm_sh + 0.01, z_arm_sh - 0.01)
    y_arm_wr, z_arm_wr = _arm_yz(x_wrist, y_arm_el - 0.005, z_arm_el - 0.005)
    y_arm_hd, z_arm_hd = _arm_yz(x_hand_tip, y_arm_wr, z_arm_wr)

    z_hips = z_min + 0.520 * h
    z_spine_top = z_min + 0.650 * h
    z_chest_top = z_min + 0.818 * h
    z_neck_top = z_min + 0.865 * h
    z_head_top = z_head_max - 0.025
    z_knee = z_min + 0.285 * h
    z_ankle = z_min + 0.055 * h
    z_ball = z_min + 0.022
    z_toes = z_min + 0.018

    l_eye_c = _mesh_center(classified["eye_l"], Vector((0.032, -0.080, z_min + 0.915 * h)))
    r_eye_c = _mesh_center(classified["eye_r"], Vector((-0.032, -0.080, z_min + 0.915 * h)))
    eye_x = 0.5 * (abs(l_eye_c.x) + abs(r_eye_c.x))
    eye_y = 0.5 * (l_eye_c.y + r_eye_c.y)
    eye_z = 0.5 * (l_eye_c.z + r_eye_c.z)
    l_eye_head = Vector((eye_x, eye_y, eye_z))
    r_eye_head = Vector((-eye_x, eye_y, eye_z))

    # Jaw pivot matched to build_ghost_girl.py
    chin_z = min((v.z for v in head_verts if abs(v.x) < 0.025 and v.y < y_head), default=z_neck_top + 0.015)
    jaw_head = Vector((0.0, y_head - 0.016, eye_z - 0.035))
    jaw_tail = Vector((0.0, y_head - 0.082, chin_z + 0.015))

    tongue_objs = classified["tongue"]
    if tongue_objs:
        t_pts = [v.co for o in tongue_objs for v in o.data.vertices]
        y_t_back = max(p.y for p in t_pts)
        y_t_tip = min(p.y for p in t_pts)
        z_t_mid = sum(p.z for p in t_pts) / len(t_pts)
        y_t_mid = 0.5 * (y_t_back + y_t_tip)
        t01_head = Vector((0.0, y_t_back, z_t_mid))
        t01_tail = Vector((0.0, y_t_mid, z_t_mid + 0.001))
        t02_tail = Vector((0.0, y_t_tip, z_t_mid))
    else:
        t01_head = Vector((0.0, -0.045, jaw_tail.z + 0.012))
        t01_tail = Vector((0.0, -0.062, jaw_tail.z + 0.013))
        t02_tail = Vector((0.0, -0.078, jaw_tail.z + 0.012))

    # Cape drape bone landmarks
    cape_verts = [v.co for o in classified["cape"] for v in o.data.vertices]
    y_cape_back = max((v.y for v in cape_verts if v.z > z_hips and abs(v.x) < 0.14), default=0.14)
    cape_c_head = Vector((0.0, y_cape_back * 0.72, z_chest_top - 0.03))
    cape_c_tail = Vector((0.0, y_cape_back + 0.03, z_hips - 0.28))
    cape_l_head = Vector((0.15, y_cape_back * 0.65, z_chest_top - 0.03))
    cape_l_tail = Vector((0.28, y_cape_back + 0.02, z_hips - 0.20))
    cape_r_head = Vector((-0.15, y_cape_back * 0.65, z_chest_top - 0.03))
    cape_r_tail = Vector((-0.28, y_cape_back + 0.02, z_hips - 0.20))

    lm: Dict[str, Vector] = {
        "root_head": Vector((0.0, 0.0, z_min)),
        "root_tail": Vector((0.0, 0.0, z_min + 0.14)),
        "hips_head": Vector((0.0, y_hips, z_hips)),
        "hips_tail": Vector((0.0, y_hips, z_hips + 0.080)),
        "spine_tail": Vector((0.0, 0.5 * (y_hips + y_chest), z_spine_top)),
        "chest_tail": Vector((0.0, y_neck, z_chest_top)),
        "neck_tail": Vector((0.0, y_head, z_neck_top)),
        "head_tail": Vector((0.0, y_head, z_head_top)),
        "l_eye_head": l_eye_head,
        "l_eye_tail": l_eye_head + Vector((0.0, 0.0, 0.024)),
        "r_eye_head": r_eye_head,
        "r_eye_tail": r_eye_head + Vector((0.0, 0.0, 0.024)),
        "jaw_head": jaw_head,
        "jaw_tail": jaw_tail,
        "t01_head": t01_head,
        "t01_tail": t01_tail,
        "t02_tail": t02_tail,
        "l_sh_head": Vector((x_sh_head, y_chest, z_arm_sh + 0.01)),
        "l_sh_tail": Vector((x_sh_tail, y_arm_sh, z_arm_sh)),
        "l_el": Vector((x_elbow, y_arm_el, z_arm_el)),
        "l_wr": Vector((x_wrist, y_arm_wr, z_arm_wr)),
        "l_hd": Vector((x_hand_tip, y_arm_hd, z_arm_hd)),
        "l_hip": Vector((x_hip_socket, y_hips, z_hips)),
        "l_knee": Vector((x_leg_knee, y_knee - 0.008, z_knee)),
        "l_ank": Vector((x_leg_ank, y_ank, z_ankle)),
        "l_ball": Vector((x_leg_ank, y_ball, z_ball)),
        "l_toe": Vector((x_leg_ank, y_toes, z_toes)),
        "r_sh_head": Vector((-x_sh_head, y_chest, z_arm_sh + 0.01)),
        "r_sh_tail": Vector((-x_sh_tail, y_arm_sh, z_arm_sh)),
        "r_el": Vector((-x_elbow, y_arm_el, z_arm_el)),
        "r_wr": Vector((-x_wrist, y_arm_wr, z_arm_wr)),
        "r_hd": Vector((-x_hand_tip, y_arm_hd, z_arm_hd)),
        "r_hip": Vector((-x_hip_socket, y_hips, z_hips)),
        "r_knee": Vector((-x_leg_knee, y_knee - 0.008, z_knee)),
        "r_ank": Vector((-x_leg_ank, y_ank, z_ankle)),
        "r_ball": Vector((-x_leg_ank, y_ball, z_ball)),
        "r_toe": Vector((-x_leg_ank, y_toes, z_toes)),
        "cape_l_head": cape_l_head,
        "cape_l_tail": cape_l_tail,
        "cape_c_head": cape_c_head,
        "cape_c_tail": cape_c_tail,
        "cape_r_head": cape_r_head,
        "cape_r_tail": cape_r_tail,
    }
    return lm


def _build_armature(lm: Dict[str, Vector]) -> bpy.types.Object:
    """Create 27-bone SkeletonProfileHumanoid-compatible armature + 3 chest-parented cape bones."""
    arm_obj = create_armature("GhostGirl_Armature")
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    bone_specs: List[Tuple[str, str | None, Vector, Vector, bool]] = [
        ("Root", None, lm["root_head"], lm["root_tail"], False),
        ("Hips", "Root", lm["hips_head"], lm["hips_tail"], True),
        ("Spine", "Hips", lm["hips_tail"], lm["spine_tail"], True),
        ("Chest", "Spine", lm["spine_tail"], lm["chest_tail"], True),
        ("Neck", "Chest", lm["chest_tail"], lm["neck_tail"], True),
        ("Head", "Neck", lm["neck_tail"], lm["head_tail"], True),
        ("LeftEye", "Head", lm["l_eye_head"], lm["l_eye_tail"], False),
        ("RightEye", "Head", lm["r_eye_head"], lm["r_eye_tail"], False),
        ("Jaw", "Head", lm["jaw_head"], lm["jaw_tail"], False),
        ("Tongue_01", "Jaw", lm["t01_head"], lm["t01_tail"], False),
        ("Tongue_02", "Tongue_01", lm["t01_tail"], lm["t02_tail"], False),
        ("LeftShoulder", "Chest", lm["l_sh_head"], lm["l_sh_tail"], True),
        ("LeftUpperArm", "LeftShoulder", lm["l_sh_tail"], lm["l_el"], True),
        ("LeftLowerArm", "LeftUpperArm", lm["l_el"], lm["l_wr"], True),
        ("LeftHand", "LeftLowerArm", lm["l_wr"], lm["l_hd"], True),
        ("RightShoulder", "Chest", lm["r_sh_head"], lm["r_sh_tail"], True),
        ("RightUpperArm", "RightShoulder", lm["r_sh_tail"], lm["r_el"], True),
        ("RightLowerArm", "RightUpperArm", lm["r_el"], lm["r_wr"], True),
        ("RightHand", "RightLowerArm", lm["r_wr"], lm["r_hd"], True),
        ("LeftUpperLeg", "Hips", lm["l_hip"], lm["l_knee"], True),
        ("LeftLowerLeg", "LeftUpperLeg", lm["l_knee"], lm["l_ank"], True),
        ("LeftFoot", "LeftLowerLeg", lm["l_ank"], lm["l_ball"], True),
        ("LeftToes", "LeftFoot", lm["l_ball"], lm["l_toe"], True),
        ("RightUpperLeg", "Hips", lm["r_hip"], lm["r_knee"], True),
        ("RightLowerLeg", "RightUpperLeg", lm["r_knee"], lm["r_ank"], True),
        ("RightFoot", "RightLowerLeg", lm["r_ank"], lm["r_ball"], True),
        ("RightToes", "RightFoot", lm["r_ball"], lm["r_toe"], True),
        # 3 cape drape bones (parented to Chest, deform disabled during body skinning)
        ("Cape_L", "Chest", lm["cape_l_head"], lm["cape_l_tail"], False),
        ("Cape_C", "Chest", lm["cape_c_head"], lm["cape_c_tail"], False),
        ("Cape_R", "Chest", lm["cape_r_head"], lm["cape_r_tail"], False),
    ]

    for b_name, parent_name, head, tail, use_def in bone_specs:
        eb = add_bone(arm_obj, b_name, head, tail, parent_name=parent_name, use_deform=use_def)
        if parent_name and parent_name in arm_obj.data.edit_bones:
            parent_eb = arm_obj.data.edit_bones[parent_name]
            eb.use_connect = (eb.head - parent_eb.tail).length < 0.002

    for eb in arm_obj.data.edit_bones:
        if "Foot" in eb.name or "Toes" in eb.name or eb.name in ("Jaw", "Tongue_01", "Tongue_02"):
            eb.align_roll(Vector((0.0, 0.0, 1.0)))
        else:
            eb.align_roll(Vector((0.0, -1.0, 0.0)))

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def _apply_spatial_body_weights(
    mesh_obj: bpy.types.Object,
    arm_obj: bpy.types.Object,
    lm: Dict[str, Vector],
) -> None:
    """Deterministic anatomical spatial skinning (zero cross-limb heat bleed)."""
    mesh_obj.vertex_groups.clear()
    deform_bones = [b for b in arm_obj.data.bones if b.use_deform]
    vgroups = {b.name: mesh_obj.vertex_groups.new(name=b.name) for b in deform_bones}
    segs: Dict[str, Tuple[Vector, Vector]] = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in deform_bones}

    z_hips = lm["hips_head"].z
    z_hip_floor = z_hips - 0.072
    z_arm_min = lm["l_sh_tail"].z - 0.100
    x_arm_split = lm["l_sh_tail"].x - 0.010

    for v in mesh_obj.data.vertices:
        p = v.co
        abs_x = abs(p.x)
        side = "Left" if p.x >= 0.0 else "Right"

        if abs_x > x_arm_split and p.z > z_arm_min:
            candidates = ["Chest", f"{side}Shoulder", f"{side}UpperArm", f"{side}LowerArm", f"{side}Hand"]
            sigma = 0.070
            raw: Dict[str, float] = {}
            for bname in candidates:
                a, b = segs[bname]
                d, _ = _point_seg_dist_and_t(p, a, b)
                raw[bname] = math.exp(-((d / sigma) ** 2))
            if abs_x > x_arm_split + 0.04:
                raw.pop("Chest", None)
        elif p.z < z_hip_floor:
            candidates = [f"{side}UpperLeg", f"{side}LowerLeg", f"{side}Foot", f"{side}Toes"]
            sigma = 0.060
            raw = {}
            for bname in candidates:
                a, b = segs[bname]
                d, _ = _point_seg_dist_and_t(p, a, b)
                raw[bname] = math.exp(-((d / sigma) ** 2))
        elif p.z < z_hips + 0.03:
            lr_blend = _smoothstep(-0.042, 0.042, p.x)
            t_hips = _smoothstep(z_hip_floor, z_hips + 0.02, p.z)
            d_hips, _ = _point_seg_dist_and_t(p, *segs["Hips"])
            d_lleg, _ = _point_seg_dist_and_t(p, *segs["LeftUpperLeg"])
            d_rleg, _ = _point_seg_dist_and_t(p, *segs["RightUpperLeg"])
            sigma = 0.072
            raw = {
                "Hips": (math.exp(-((d_hips / sigma) ** 2)) + 1.4) * t_hips,
                "LeftUpperLeg": lr_blend * math.exp(-((d_lleg / sigma) ** 2)) * (1.0 - 0.85 * t_hips),
                "RightUpperLeg": (1.0 - lr_blend) * math.exp(-((d_rleg / sigma) ** 2)) * (1.0 - 0.85 * t_hips),
            }
        else:
            candidates = ["Hips", "Spine", "Chest", "Neck", "LeftShoulder", "RightShoulder"]
            sigma = 0.062
            raw = {}
            for bname in candidates:
                a, b = segs[bname]
                d, _ = _point_seg_dist_and_t(p, a, b)
                raw[bname] = math.exp(-((d / sigma) ** 2))
            if abs_x < 0.055 or p.x < 0.0:
                raw.pop("LeftShoulder", None)
            if abs_x < 0.055 or p.x > 0.0:
                raw.pop("RightShoulder", None)
            if abs_x > 0.085 or p.z < lm["chest_tail"].z - 0.03:
                raw.pop("Neck", None)

        top4 = sorted(raw.items(), key=lambda kv: kv[1], reverse=True)[:4]
        total = sum(w for _, w in top4)
        if total < 1e-8:
            fallback_bone = f"{side}LowerLeg" if p.z < z_hip_floor else "Hips"
            vgroups[fallback_bone].add([v.index], 1.0, "REPLACE")
        else:
            for bname, w in top4:
                nw = w / total
                if nw > 1e-4:
                    vgroups[bname].add([v.index], nw, "REPLACE")


def _bind_armature_modifier(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object) -> None:
    parent_mesh_to_armature(mesh_obj, arm_obj, auto_weights=False)


def _assign_rigid_weight(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object, bone_name: str) -> None:
    mesh_obj.vertex_groups.clear()
    vg = mesh_obj.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(mesh_obj.data.vertices))), 1.0, "REPLACE")
    _bind_armature_modifier(mesh_obj, arm_obj)


def _assign_head_weights(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object, lm: Dict[str, Vector]) -> None:
    """Assign smooth Neck/Head collar blend to GhostGirl_Head."""
    mesh_obj.vertex_groups.clear()
    vg_neck = mesh_obj.vertex_groups.new(name="Neck")
    vg_head = mesh_obj.vertex_groups.new(name="Head")
    z_split = lm["neck_tail"].z
    for v in mesh_obj.data.vertices:
        z = v.co.z
        chin_bias = 0.015 * _smoothstep(-0.02, -0.06, v.co.y) if z > z_split - 0.015 else 0.0
        w_head = _smoothstep(z_split - 0.035, z_split + 0.020, z + chin_bias)
        w_neck = 1.0 - w_head
        if w_head > 1e-4:
            vg_head.add([v.index], w_head, "REPLACE")
        if w_neck > 1e-4:
            vg_neck.add([v.index], w_neck, "REPLACE")
    _bind_armature_modifier(mesh_obj, arm_obj)


def _assign_hood_weights(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object, lm: Dict[str, Vector]) -> None:
    """Weight GhostGirl_Hood firmly to Head with gentle Neck follow only on low back nape hem."""
    mesh_obj.vertex_groups.clear()
    vg_head = mesh_obj.vertex_groups.new(name="Head")
    vg_neck = mesh_obj.vertex_groups.new(name="Neck")
    z_neck_top = lm["neck_tail"].z
    for v in mesh_obj.data.vertices:
        w_neck = 0.0
        if v.co.y > 0.02 and v.co.z < z_neck_top + 0.02:
            w_neck = 0.25 * _smoothstep(z_neck_top + 0.02, z_neck_top - 0.04, v.co.z)
        w_head = 1.0 - w_neck
        vg_head.add([v.index], w_head, "REPLACE")
        if w_neck > 1e-4:
            vg_neck.add([v.index], w_neck, "REPLACE")
    _bind_armature_modifier(mesh_obj, arm_obj)


def _assign_hair_cards_weights(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object, lm: Dict[str, Vector]) -> None:
    mesh_obj.vertex_groups.clear()
    vg_head = mesh_obj.vertex_groups.new(name="Head")
    vg_neck = mesh_obj.vertex_groups.new(name="Neck")
    z_neck_top = lm["neck_tail"].z
    for v in mesh_obj.data.vertices:
        w_neck = 0.0
        if v.co.y > 0.025 and v.co.z < z_neck_top + 0.03:
            w_neck = 0.22 * _smoothstep(z_neck_top + 0.03, z_neck_top - 0.03, v.co.z)
        w_head = 1.0 - w_neck
        vg_head.add([v.index], w_head, "REPLACE")
        if w_neck > 1e-4:
            vg_neck.add([v.index], w_neck, "REPLACE")
    _bind_armature_modifier(mesh_obj, arm_obj)


def _assign_tongue_weights(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object, lm: Dict[str, Vector]) -> None:
    mesh_obj.vertex_groups.clear()
    vg_01 = mesh_obj.vertex_groups.new(name="Tongue_01")
    vg_02 = mesh_obj.vertex_groups.new(name="Tongue_02")
    vg_head = mesh_obj.vertex_groups.new(name="Head")
    y_mid = lm["t01_tail"].y
    for v in mesh_obj.data.vertices:
        w2 = _smoothstep(y_mid + 0.010, y_mid - 0.010, v.co.y) * 0.45
        w1 = (1.0 - _smoothstep(y_mid + 0.010, y_mid - 0.010, v.co.y)) * 0.45
        if w1 > 1e-4:
            vg_01.add([v.index], w1, "REPLACE")
        if w2 > 1e-4:
            vg_02.add([v.index], w2, "REPLACE")
        vg_head.add([v.index], 0.55, "REPLACE")
    _bind_armature_modifier(mesh_obj, arm_obj)


def _assign_lower_teeth_weights(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object) -> None:
    """Blend GhostGirl_Teeth_Lower across Jaw (40%) + Head (60%) so +19deg Jaw rotation frames lower teeth inside open mouth."""
    mesh_obj.vertex_groups.clear()
    vg_jaw = mesh_obj.vertex_groups.new(name="Jaw")
    vg_head = mesh_obj.vertex_groups.new(name="Head")
    all_idx = [v.index for v in mesh_obj.data.vertices]
    if all_idx:
        vg_jaw.add(all_idx, 0.40, "REPLACE")
        vg_head.add(all_idx, 0.60, "REPLACE")
    _bind_armature_modifier(mesh_obj, arm_obj)


def _assign_boots_weights(mesh_obj: bpy.types.Object, arm_obj: bpy.types.Object, lm: Dict[str, Vector]) -> None:
    """Skin GhostGirl_Boots directly to LowerLeg/Foot/Toes so ankle & toe roll deform cleanly."""
    mesh_obj.vertex_groups.clear()
    z_ank = lm["l_ank"].z
    y_ball = lm["l_ball"].y
    b_names = ("LeftLowerLeg", "LeftFoot", "LeftToes", "RightLowerLeg", "RightFoot", "RightToes")
    vgs = {bn: mesh_obj.vertex_groups.new(name=bn) for bn in b_names}
    for v in mesh_obj.data.vertices:
        side = "Left" if v.co.x >= 0.0 else "Right"
        w_leg = _smoothstep(z_ank - 0.015, z_ank + 0.055, v.co.z)
        w_toe = (1.0 - w_leg) * _smoothstep(y_ball + 0.025, y_ball - 0.025, v.co.y)
        w_foot = max(0.0, 1.0 - w_leg - w_toe)
        if w_leg > 1e-4:
            vgs[f"{side}LowerLeg"].add([v.index], w_leg, "REPLACE")
        if w_foot > 1e-4:
            vgs[f"{side}Foot"].add([v.index], w_foot, "REPLACE")
        if w_toe > 1e-4:
            vgs[f"{side}Toes"].add([v.index], w_toe, "REPLACE")
    _bind_armature_modifier(mesh_obj, arm_obj)


def _assign_cape_weights(
    mesh_obj: bpy.types.Object,
    arm_obj: bpy.types.Object,
    lm: Dict[str, Vector],
    body_obj: bpy.types.Object,
) -> None:
    """Lock upper mantle cowl 1:1 to nearest body shoulder/arm skin weights; blend lower skirt to Cape_L/C/R."""
    mesh_obj.vertex_groups.clear()
    vgs: Dict[str, bpy.types.VertexGroup] = {}
    for vg in body_obj.vertex_groups:
        vgs[vg.name] = mesh_obj.vertex_groups.new(name=vg.name)
    for bn in ("Chest", "Cape_L", "Cape_C", "Cape_R"):
        if bn not in vgs:
            vgs[bn] = mesh_obj.vertex_groups.new(name=bn)

    z_sh = lm["l_sh_tail"].z
    x_el = lm["l_el"].x
    x_sh = lm["l_sh_tail"].x

    # Separate KDTrees: collar/torso vs strictly arm/shoulder (|x| >= x_sh - 0.025) so back wings NEVER grab ribcage!
    collar_pts = [
        (v.index, v.co)
        for v in body_obj.data.vertices
        if z_sh - 0.14 <= v.co.z <= lm["neck_tail"].z + 0.02 and abs(v.co.x) < x_sh
    ]
    arm_pts = [
        (v.index, v.co)
        for v in body_obj.data.vertices
        if abs(v.co.x) >= x_sh - 0.04
        and (z_sh - 0.12 if abs(v.co.x) < x_sh + 0.02 else z_sh - 0.16) <= v.co.z <= lm["neck_tail"].z + 0.02
    ]
    kd_col = kdtree.KDTree(max(len(collar_pts), 1))
    for i, (_, co) in enumerate(collar_pts):
        kd_col.insert(co, i)
    kd_col.balance()
    kd_arm = kdtree.KDTree(max(len(arm_pts), 1))
    for i, (_, co) in enumerate(arm_pts):
        kd_arm.insert(co, i)
    kd_arm.balance()
    body_vg_names = {vg.index: vg.name for vg in body_obj.vertex_groups}

    for v in mesh_obj.data.vertices:
        p = v.co
        ax = abs(p.x)
        if ax <= x_sh:
            arm_z = lm["l_sh_tail"].z
        elif ax <= x_el:
            t_a = (ax - x_sh) / max(x_el - x_sh, 1e-4)
            arm_z = lm["l_sh_tail"].z * (1.0 - t_a) + lm["l_el"].z * t_a
        else:
            t_a = min(1.0, (ax - x_el) / max(lm["l_wr"].x - x_el, 1e-4))
            arm_z = lm["l_el"].z * (1.0 - t_a) + lm["l_wr"].z * t_a
        drop = max(0.0, arm_z - p.z)

        # Lock top shoulder/upper-arm cowl to body skin; keep hanging back curtain & forearm drape flowing behind torso
        t_fa = 0.0 if ax <= x_el else min(1.0, (ax - x_el) / max(lm["l_wr"].x - x_el, 1e-4))
        drop_max = 0.22 * (1.0 - t_fa) + 0.07 * t_fa
        drop_min = 0.05 * (1.0 - t_fa) + 0.015 * t_fa
        back_fade = 1.0 - 0.78 * _smoothstep(0.050, 0.105, p.y - lm["l_sh_tail"].y) * _smoothstep(0.02, 0.10, drop)
        w_arm_z = _smoothstep(drop_max, drop_min, drop) * back_fade
        w_arm_follow = w_arm_z * _smoothstep(0.04, 0.12, ax)
        w_collar = _smoothstep(z_sh - 0.12, z_sh - 0.01, p.z) * _smoothstep(0.16, 0.04, ax)
        w_body_follow = min(1.0, w_arm_follow + w_collar)

        raw: Dict[str, float] = {}
        if w_body_follow > 1e-3:
            use_arm = ax >= x_sh - 0.02 and arm_pts
            pts_src = arm_pts if use_arm else collar_pts
            kd_src = kd_arm if use_arm else kd_col
            if pts_src:
                _, near_idx, _ = kd_src.find(p)
                b_vi = pts_src[near_idx][0]
                b_tot = sum(g.weight for g in body_obj.data.vertices[b_vi].groups)
                if b_tot > 1e-6:
                    for g in body_obj.data.vertices[b_vi].groups:
                        bn = body_vg_names.get(g.group)
                        if bn and bn in vgs:
                            raw[bn] = raw.get(bn, 0.0) + w_body_follow * (g.weight / b_tot)

        # Lower hanging cloak skirt blends onto Cape_L / Cape_C / Cape_R (+ gentle Chest support near upper back)
        w_rem = max(0.0, 1.0 - sum(raw.values()))
        w_chest_zone = _smoothstep(0.20, 0.06, ax)
        w_drape = _smoothstep(z_sh + 0.02, z_sh - 0.24, p.z)
        w_chest = w_rem * (1.0 - 0.92 * w_drape) * w_chest_zone
        w_cape = max(0.0, w_rem - w_chest)
        if w_chest > 1e-4:
            raw["Chest"] = raw.get("Chest", 0.0) + w_chest
        if w_cape > 1e-4:
            wl = _smoothstep(0.04, 0.22, p.x)
            wr = _smoothstep(-0.04, -0.22, p.x)
            wc = max(0.0, 1.0 - wl - wr)
            if wl > 1e-4:
                raw["Cape_L"] = raw.get("Cape_L", 0.0) + wl * w_cape
            if wc > 1e-4:
                raw["Cape_C"] = raw.get("Cape_C", 0.0) + wc * w_cape
            if wr > 1e-4:
                raw["Cape_R"] = raw.get("Cape_R", 0.0) + wr * w_cape

        top4 = sorted(raw.items(), key=lambda kv: kv[1], reverse=True)[:4]
        tot = sum(w for _, w in top4)
        if tot < 1e-6:
            vgs["Chest"].add([v.index], 1.0, "REPLACE")
        else:
            for bn, w in top4:
                nw = w / tot
                if nw > 1e-4:
                    vgs[bn].add([v.index], nw, "REPLACE")

    _bind_armature_modifier(mesh_obj, arm_obj)


def _fill_unweighted_vertices_kdtree(mesh_obj: bpy.types.Object) -> int:
    verts = mesh_obj.data.vertices
    weighted_indices = [v.index for v in verts if sum(g.weight for g in v.groups) > 1e-4]
    unweighted_indices = [v.index for v in verts if sum(g.weight for g in v.groups) <= 1e-4]
    if not unweighted_indices or not weighted_indices:
        return 0
    kd = kdtree.KDTree(len(weighted_indices))
    for vi in weighted_indices:
        kd.insert(verts[vi].co, vi)
    kd.balance()
    vgroups = mesh_obj.vertex_groups
    for ui in unweighted_indices:
        _, src_idx, _ = kd.find(verts[ui].co)
        total = sum(g.weight for g in verts[src_idx].groups)
        if total > 1e-8:
            for g in verts[src_idx].groups:
                nw = g.weight / total
                if nw > 1e-4:
                    vgroups[g.group].add([ui], nw, "REPLACE")
    return len(unweighted_indices)


def _transfer_garment_weights(
    garment_obj: bpy.types.Object,
    body_obj: bpy.types.Object,
    arm_obj: bpy.types.Object,
    smooth_repeat: int = 2,
) -> None:
    garment_obj.vertex_groups.clear()
    for vg in body_obj.vertex_groups:
        garment_obj.vertex_groups.new(name=vg.name)

    dt_mod = garment_obj.modifiers.new(name="WeightTransfer", type="DATA_TRANSFER")
    dt_mod.object = body_obj
    dt_mod.use_vert_data = True
    dt_mod.data_types_verts = {"VGROUP_WEIGHTS"}
    dt_mod.vert_mapping = "POLYINTERP_NEAREST"

    bpy.ops.object.select_all(action="DESELECT")
    garment_obj.select_set(True)
    bpy.context.view_layer.objects.active = garment_obj
    bpy.ops.object.datalayout_transfer(modifier=dt_mod.name)
    bpy.ops.object.modifier_apply(modifier=dt_mod.name)

    if garment_obj.vertex_groups:
        garment_obj.vertex_groups.active_index = 0
        bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
        if smooth_repeat > 0:
            bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.40, repeat=smooth_repeat, expand=0.0)
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
        bpy.ops.object.mode_set(mode="OBJECT")

    _fill_unweighted_vertices_kdtree(garment_obj)
    _bind_armature_modifier(garment_obj, arm_obj)


def _skin_all_meshes(
    classified: Dict[str, List[bpy.types.Object]],
    arm_obj: bpy.types.Object,
    lm: Dict[str, Vector],
) -> None:
    body_primary = classified["body"][0]
    for obj in classified["body"]:
        _bind_armature_modifier(obj, arm_obj)
        _apply_spatial_body_weights(obj, arm_obj, lm)
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        if obj.vertex_groups:
            obj.vertex_groups.active_index = 0
            bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
            bpy.ops.object.vertex_group_smooth(group_select_mode="ALL", factor=0.35, repeat=2, expand=0.0)
            bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
            bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
            bpy.ops.object.mode_set(mode="OBJECT")
        _fill_unweighted_vertices_kdtree(obj)

    for g_key, s_rep in (("croptop", 2), ("skirt", 3), ("gloves", 1)):
        for g_obj in classified[g_key]:
            _transfer_garment_weights(g_obj, body_primary, arm_obj, smooth_repeat=s_rep)

    # Enable deform on Root, facial bones, and cape drape bones before skinning them / exporting GLB
    for b_name in ("Root",) + FACIAL_BONE_NAMES + CAPE_BONE_NAMES:
        if b_name in arm_obj.data.bones:
            arm_obj.data.bones[b_name].use_deform = True

    for obj in classified["boots"]:
        _assign_boots_weights(obj, arm_obj, lm)
    for obj in classified["cape"]:
        _assign_cape_weights(obj, arm_obj, lm, body_primary)
    for obj in classified["head"]:
        _assign_head_weights(obj, arm_obj, lm)
    for obj in classified["eye_l"]:
        _assign_rigid_weight(obj, arm_obj, "LeftEye")
    for obj in classified["eye_r"]:
        _assign_rigid_weight(obj, arm_obj, "RightEye")
    for obj in classified["eyelashes"]:
        _assign_rigid_weight(obj, arm_obj, "Head")
    for obj in classified["teeth_upper"]:
        _assign_rigid_weight(obj, arm_obj, "Head")
    for obj in classified["teeth_lower"]:
        _assign_lower_teeth_weights(obj, arm_obj)
    for obj in classified["tongue"]:
        _assign_tongue_weights(obj, arm_obj, lm)
    for obj in classified["hair_cap"]:
        _assign_rigid_weight(obj, arm_obj, "Head")
    for obj in classified["hair_cards"]:
        _assign_hair_cards_weights(obj, arm_obj, lm)
    for obj in classified["hood"]:
        _assign_hood_weights(obj, arm_obj, lm)

    for key, objs in classified.items():
        for obj in objs:
            unweighted = sum(1 for v in obj.data.vertices if sum(g.weight for g in v.groups) < 1e-4)
            assert unweighted == 0, f"{obj.name} ({key}) still has {unweighted} unweighted vertices"
    print("[rig_ghost_girl] All 16 meshes skinned with 0 unweighted vertices.")


# ---------------------------------------------------------------------------
# 60 FPS IK & Looping Bezier NLA Clips (idle, walk, run)
# ---------------------------------------------------------------------------

def _solve_two_bone_ik(root: Vector, target: Vector, len1: float, len2: float, pole_dir: Vector) -> Vector:
    delta = target - root
    raw_len = delta.length
    min_dist = max(0.03, abs(len1 - len2) + 0.005)
    max_dist = max(min_dist + 0.005, len1 + len2 - 0.004)
    dist = max(min_dist, min(raw_len, max_dist))
    fwd = Vector((0.0, 0.0, -1.0)) if raw_len < 1e-6 else (delta / raw_len)
    cos_a = max(-0.995, min(0.995, (len1 * len1 + dist * dist - len2 * len2) / (2.0 * len1 * dist)))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    ortho = pole_dir - fwd * pole_dir.dot(fwd)
    if ortho.length_squared < 1e-6:
        fb = Vector((0.0, 0.0, 1.0)) if abs(fwd.z) < 0.9 else Vector((1.0, 0.0, 0.0))
        ortho = fb - fwd * fb.dot(fwd)
    ortho.normalize()
    return root + fwd * (len1 * cos_a) + ortho * (len1 * sin_a)


def _aim_pose_bone(arm_obj: bpy.types.Object, bone_name: str, target_dir: Vector, roll_hint: Vector | None = None) -> None:
    bpy.context.view_layer.update()
    pb = arm_obj.pose.bones[bone_name]
    pb.rotation_mode = "QUATERNION"
    cur_dir = pb.tail - pb.head
    if cur_dir.length_squared < 1e-10 or target_dir.length_squared < 1e-10:
        return
    tgt_n = target_dir.normalized()
    pivot = pb.head.copy()
    if roll_hint is not None and roll_hint.length_squared > 1e-8:
        z_axis = roll_hint - tgt_n * roll_hint.dot(tgt_n)
        if z_axis.length_squared > 1e-6:
            z_axis.normalize()
            x_axis = tgt_n.cross(z_axis).normalized()
            z_axis = x_axis.cross(tgt_n).normalized()
            rot_mat = Matrix((
                (x_axis.x, tgt_n.x, z_axis.x, 0.0),
                (x_axis.y, tgt_n.y, z_axis.y, 0.0),
                (x_axis.z, tgt_n.z, z_axis.z, 0.0),
                (0.0, 0.0, 0.0, 1.0),
            ))
            pb.matrix = Matrix.Translation(pivot) @ rot_mat
            bpy.context.view_layer.update()
            return
    dq = cur_dir.normalized().rotation_difference(tgt_n)
    pb.matrix = Matrix.Translation(pivot) @ dq.to_matrix().to_4x4() @ Matrix.Translation(-pivot) @ pb.matrix
    bpy.context.view_layer.update()


def _reset_pose(arm_obj: bpy.types.Object) -> None:
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.location = Vector((0.0, 0.0, 0.0))
    bpy.context.view_layer.update()


def _set_bone_euler_local(arm_obj: bpy.types.Object, bone_name: str, rx_deg: float, ry_deg: float, rz_deg: float) -> None:
    if bone_name not in arm_obj.pose.bones:
        return
    pb = arm_obj.pose.bones[bone_name]
    pb.rotation_mode = "QUATERNION"
    qx = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(rx_deg))
    qy = Quaternion(Vector((0.0, 1.0, 0.0)), math.radians(ry_deg))
    qz = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(rz_deg))
    pb.rotation_quaternion = qy @ qx @ qz


def _solve_planted_leg(arm_obj: bpy.types.Object, side: str, ankle_target: Vector, knee_pole: Vector, foot_fwd: Vector) -> None:
    bpy.context.view_layer.update()
    u_name, l_name, f_name = f"{side}UpperLeg", f"{side}LowerLeg", f"{side}Foot"
    u_pb = arm_obj.pose.bones[u_name]
    l_pb = arm_obj.pose.bones[l_name]
    hip_pos = u_pb.head.copy()
    l1 = (u_pb.tail - u_pb.head).length
    l2 = (l_pb.tail - l_pb.head).length
    knee_pos = _solve_two_bone_ik(hip_pos, ankle_target, l1, l2, knee_pole)
    _aim_pose_bone(arm_obj, u_name, knee_pos - hip_pos, roll_hint=knee_pole)
    _aim_pose_bone(arm_obj, l_name, ankle_target - knee_pos, roll_hint=knee_pole)
    _aim_pose_bone(arm_obj, f_name, foot_fwd, roll_hint=Vector((0.0, 0.0, 1.0)))


def _solve_arm_target(arm_obj: bpy.types.Object, side: str, wrist_target: Vector, elbow_pole: Vector, hand_dir: Vector | None = None) -> None:
    bpy.context.view_layer.update()
    u_name, l_name, h_name = f"{side}UpperArm", f"{side}LowerArm", f"{side}Hand"
    u_pb = arm_obj.pose.bones[u_name]
    l_pb = arm_obj.pose.bones[l_name]
    sh_pos = u_pb.head.copy()
    l1 = (u_pb.tail - u_pb.head).length
    l2 = (l_pb.tail - l_pb.head).length
    elbow_pos = _solve_two_bone_ik(sh_pos, wrist_target, l1, l2, elbow_pole)
    u_dir = (elbow_pos - sh_pos).normalized()
    f_dir = (wrist_target - elbow_pos).normalized()
    perp_u = f_dir - u_dir * f_dir.dot(u_dir)
    roll_u = perp_u.normalized() if perp_u.length_squared > 1e-4 else -elbow_pole
    perp_f = -u_dir + f_dir * u_dir.dot(f_dir)
    roll_f = perp_f.normalized() if perp_f.length_squared > 1e-4 else -elbow_pole
    _aim_pose_bone(arm_obj, u_name, u_dir, roll_hint=roll_u)
    _aim_pose_bone(arm_obj, l_name, f_dir, roll_hint=roll_f)
    if hand_dir is None:
        inward_x = -0.08 if side == "Left" else 0.08
        resolved_hand = (f_dir + roll_f * 0.12 + Vector((inward_x, 0.0, 0.0))).normalized()
    else:
        resolved_hand = hand_dir
    _aim_pose_bone(arm_obj, h_name, resolved_hand, roll_hint=roll_f)


def _get_action_fcurves(action: bpy.types.Action) -> List[bpy.types.FCurve]:
    fcurves: List[bpy.types.FCurve] = []
    if hasattr(action, "layers"):
        for layer in action.layers:
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    fcurves.extend(bag.fcurves)
    elif hasattr(action, "fcurves"):
        fcurves.extend(action.fcurves)
    return fcurves


def _finalize_loop_action(arm_obj: bpy.types.Object, action: bpy.types.Action, total_frames: int) -> None:
    fcurves = _get_action_fcurves(action)
    by_path: Dict[str, Dict[int, bpy.types.FCurve]] = {}
    for fc in fcurves:
        if fc.data_path.endswith("rotation_quaternion"):
            by_path.setdefault(fc.data_path, {})[fc.array_index] = fc

    for idx_map in by_path.values():
        if len(idx_map) != 4:
            continue
        fc_w, fc_x, fc_y, fc_z = idx_map[0], idx_map[1], idx_map[2], idx_map[3]
        n = min(len(fc.keyframe_points) for fc in (fc_w, fc_x, fc_y, fc_z))
        if n < 2:
            continue
        prev = Quaternion((fc_w.keyframe_points[0].co.y, fc_x.keyframe_points[0].co.y, fc_y.keyframe_points[0].co.y, fc_z.keyframe_points[0].co.y))
        for i in range(1, n):
            curr = Quaternion((fc_w.keyframe_points[i].co.y, fc_x.keyframe_points[i].co.y, fc_y.keyframe_points[i].co.y, fc_z.keyframe_points[i].co.y))
            if prev.dot(curr) < 0.0:
                curr.negate()
                fc_w.keyframe_points[i].co.y = curr.w
                fc_x.keyframe_points[i].co.y = curr.x
                fc_y.keyframe_points[i].co.y = curr.y
                fc_z.keyframe_points[i].co.y = curr.z
            prev = curr
        for fc in (fc_w, fc_x, fc_y, fc_z):
            fc.update()

    for fc in fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"

    end_frame = total_frames - 1
    action.use_frame_range = True
    action.frame_start = 0.0
    action.frame_end = float(end_frame)

    push_action_to_nla(arm_obj, action, track_name=action.name)
    track = arm_obj.animation_data.nla_tracks[-1]
    strip = track.strips[-1]
    strip.action_frame_start = 0.0
    strip.action_frame_end = float(end_frame)
    strip.frame_start = 0.0
    strip.frame_end = float(end_frame)
    arm_obj.animation_data.action = None


def _insert_keys(arm_obj: bpy.types.Object, frame: int) -> None:
    for pb in arm_obj.pose.bones:
        if pb.name in EXCLUDED_AUTO_KEY_BONES:
            continue
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        if pb.name == "Hips":
            pb.keyframe_insert(data_path="location", frame=frame)


def _get_rest_foot_info(arm_obj: bpy.types.Object) -> Tuple[Vector, Vector, Vector, Vector]:
    l_ank = arm_obj.data.bones["LeftFoot"].head_local.copy()
    r_ank = arm_obj.data.bones["RightFoot"].head_local.copy()
    l_dir = (arm_obj.data.bones["LeftFoot"].tail_local - l_ank).normalized()
    r_dir = (arm_obj.data.bones["RightFoot"].tail_local - r_ank).normalized()
    return l_ank, r_ank, l_dir, r_dir


def _bake_idle(arm_obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = create_action(arm_obj, "idle")

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    l_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(5.0)) @ l_dir
    r_foot_dir = Quaternion(Vector((0.0, 0.0, 1.0)), math.radians(-6.0)) @ r_dir
    l_ank = l_rest + Vector((0.006, -0.012, 0.0))
    r_ank = r_rest + Vector((-0.006, 0.008, 0.0))

    hips_z = arm_obj.data.bones["Hips"].head_local.z
    u_arm_len = (arm_obj.data.bones["LeftUpperArm"].tail_local - arm_obj.data.bones["LeftUpperArm"].head_local).length
    f_arm_len = (arm_obj.data.bones["LeftLowerArm"].tail_local - arm_obj.data.bones["LeftLowerArm"].head_local).length
    sh_z = arm_obj.data.bones["LeftUpperArm"].head_local.z
    # Keep wrists well inside natural 91% arm reach so elbows bend gently and NEVER lock/twist!
    wrist_z_base = max(hips_z - 0.015, sh_z - 0.91 * (u_arm_len + f_arm_len))

    for frame in range(0, 181, 15):
        phase = (frame / 180.0) * math.tau
        breath = 0.5 - 0.5 * math.cos(phase * 2.0)
        sway = math.sin(phase)
        overlap = math.sin(phase - 0.45)

        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        hips = arm_obj.pose.bones["Hips"]
        # Relaxed natural standing hips with readable gentle breath, weight shift, and flowing cape across all 5 QA frames
        hips.location = Vector((-0.032 * sway, -0.004 - 0.006 * breath, 0.003 * sway))
        _set_bone_euler_local(arm_obj, "Hips", -0.5, -3.5 * sway, 2.8 * sway)
        _set_bone_euler_local(arm_obj, "Spine", 1.5 - 3.2 * breath, 2.4 * sway, -2.0 * sway)
        _set_bone_euler_local(arm_obj, "Chest", -4.2 * breath, 2.8 * overlap, -2.2 * overlap)
        _set_bone_euler_local(arm_obj, "Neck", 2.5 * breath, -1.6 * overlap, 1.4 * overlap)
        _set_bone_euler_local(arm_obj, "Head", 3.2 * breath, -3.8 * overlap, 1.8 * overlap)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -9.5 + 3.8 * breath)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 9.5 - 3.8 * breath)
        _set_bone_euler_local(arm_obj, "Cape_C", -3.0 + 5.5 * breath, 0.0, 6.5 * overlap)
        _set_bone_euler_local(arm_obj, "Cape_L", -2.0 + 4.5 * breath, 0.0, -34.0 + 7.5 * overlap)
        _set_bone_euler_local(arm_obj, "Cape_R", -2.0 + 4.5 * breath, 0.0, 34.0 + 7.5 * overlap)
        bpy.context.view_layer.update()

        _solve_planted_leg(arm_obj, "Left", l_ank, Vector((0.15, -1.0, 0.0)), l_foot_dir)
        _solve_planted_leg(arm_obj, "Right", r_ank, Vector((-0.14, -1.0, 0.0)), r_foot_dir)

        l_wrist = Vector((0.245 + 0.030 * sway, -0.052 - 0.022 * breath + 0.020 * overlap, wrist_z_base + 0.026 * breath))
        r_wrist = Vector((-0.245 + 0.030 * sway, -0.044 - 0.022 * breath - 0.020 * overlap, wrist_z_base + 0.026 * breath))
        _solve_arm_target(arm_obj, "Left", l_wrist, Vector((0.55, 0.80, -0.15)), Vector((-0.10, -0.20, -0.97)))
        _solve_arm_target(arm_obj, "Right", r_wrist, Vector((-0.55, 0.80, -0.15)), Vector((0.10, -0.20, -0.97)))

        _insert_keys(arm_obj, frame)

    _finalize_loop_action(arm_obj, action, total_frames=180)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[rig_ghost_girl] Baked 'idle' (0..179 @ 60 FPS)")


def _bake_walk(arm_obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = create_action(arm_obj, "walk")

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    hips_z = arm_obj.data.bones["Hips"].head_local.z
    u_arm_len = (arm_obj.data.bones["LeftUpperArm"].tail_local - arm_obj.data.bones["LeftUpperArm"].head_local).length
    f_arm_len = (arm_obj.data.bones["LeftLowerArm"].tail_local - arm_obj.data.bones["LeftLowerArm"].head_local).length
    sh_z = arm_obj.data.bones["LeftUpperArm"].head_local.z
    wrist_z_base = max(hips_z - 0.010, sh_z - 0.90 * (u_arm_len + f_arm_len))
    stride_half = 0.25

    for frame in range(0, 65, 4):
        u = frame / 64.0
        phase = u * math.tau
        chest_phase = phase - 0.22
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        bob = -0.048 - 0.020 * math.cos(2.0 * phase)
        lat = -0.018 * math.cos(phase)
        hip_yaw = 6.0 * math.cos(phase)
        hip_roll = 2.8 * math.sin(phase)
        chest_yaw = -6.0 * math.cos(chest_phase)

        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((lat, bob, 0.0))
        _set_bone_euler_local(arm_obj, "Hips", 2.8, hip_yaw, hip_roll)
        _set_bone_euler_local(arm_obj, "Spine", 2.2, chest_yaw * 0.45, -hip_roll * 0.5)
        _set_bone_euler_local(arm_obj, "Chest", 2.0, chest_yaw * 0.55, -hip_roll * 0.4)
        _set_bone_euler_local(arm_obj, "Neck", -2.2, -chest_yaw * 0.35, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -1.8, -chest_yaw * 0.35, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 2.0, -9.5)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -2.0, 9.5)
        _set_bone_euler_local(arm_obj, "Cape_C", -4.5 + 2.0 * math.cos(2.0 * phase), 0.0, 2.5 * math.sin(phase))
        _set_bone_euler_local(arm_obj, "Cape_L", -3.5, 0.0, -32.0 + 3.0 * math.cos(chest_phase))
        _set_bone_euler_local(arm_obj, "Cape_R", -3.5, 0.0, 32.0 + 3.0 * math.cos(chest_phase))
        bpy.context.view_layer.update()

        for side_idx, (side, rest_a, rest_d, off_x) in enumerate([
            ("Left", l_rest, l_dir, 0.005),
            ("Right", r_rest, r_dir, -0.005),
        ]):
            su = (u + 0.5 * side_idx) % 1.0
            if su <= 0.52:
                st = su / 0.52
                y_off = -stride_half + (2.0 * stride_half) * st
                z_off = 0.022 * max(0.0, 1.0 - st / 0.16) + 0.034 * _smoothstep(0.76, 1.0, st)
                pitch = 12.0 * max(0.0, 1.0 - st / 0.14) - 20.0 * _smoothstep(0.82, 1.0, st)
            else:
                sw = (su - 0.52) / 0.48
                y_off = stride_half - (2.0 * stride_half) * _smoothstep(0.0, 1.0, sw)
                z_off = 0.034 * (1.0 - sw) + 0.080 * math.sin(sw * math.pi)
                pitch = -18.0 * math.sin(sw * math.pi) + 12.0 * _smoothstep(0.70, 1.0, sw)
            ankle_tgt = rest_a + Vector((off_x, y_off, z_off))
            foot_dir = (Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(pitch)) @ rest_d).normalized()
            pole_x = 0.15 if side == "Left" else -0.15
            _solve_planted_leg(arm_obj, side, ankle_tgt, Vector((pole_x, -1.0, 0.05)), foot_dir)

        l_arm_y = -0.04 + 0.17 * math.cos(chest_phase)
        r_arm_y = -0.04 - 0.17 * math.cos(chest_phase)
        l_arm_z = wrist_z_base + 0.035 * abs(math.cos(chest_phase))
        r_arm_z = wrist_z_base + 0.035 * abs(math.cos(chest_phase))
        _solve_arm_target(arm_obj, "Left", Vector((0.23, l_arm_y, l_arm_z)), Vector((0.35, 0.92, -0.10)))
        _solve_arm_target(arm_obj, "Right", Vector((-0.23, r_arm_y, r_arm_z)), Vector((-0.35, 0.92, -0.10)))

        _insert_keys(arm_obj, frame)

    _finalize_loop_action(arm_obj, action, total_frames=64)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[rig_ghost_girl] Baked 'walk' (0..63 @ 60 FPS)")


def _bake_run(arm_obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    action = create_action(arm_obj, "run")

    l_rest, r_rest, l_dir, r_dir = _get_rest_foot_info(arm_obj)
    hips_z = arm_obj.data.bones["Hips"].head_local.z
    stride_half = 0.32

    for frame in range(0, 41, 2):
        u = frame / 40.0
        phase = u * math.tau
        chest_phase = phase - 0.24
        bpy.context.scene.frame_set(frame)
        _reset_pose(arm_obj)

        bob = -0.064 - 0.044 * math.cos(2.0 * phase)
        lat = -0.016 * math.cos(phase)
        hip_yaw = 8.0 * math.cos(phase)
        chest_yaw = -8.0 * math.cos(chest_phase)

        hips = arm_obj.pose.bones["Hips"]
        hips.location = Vector((lat, bob, -0.016))
        _set_bone_euler_local(arm_obj, "Hips", 7.0, hip_yaw, 3.5 * math.sin(phase))
        _set_bone_euler_local(arm_obj, "Spine", 8.0, chest_yaw * 0.45, -1.8 * math.sin(phase))
        _set_bone_euler_local(arm_obj, "Chest", 7.0, chest_yaw * 0.55, 0.0)
        _set_bone_euler_local(arm_obj, "Neck", -9.5, -chest_yaw * 0.35, 0.0)
        _set_bone_euler_local(arm_obj, "Head", -10.5, -chest_yaw * 0.35, 0.0)
        _set_bone_euler_local(arm_obj, "LeftShoulder", 0.0, 3.5, -8.5)
        _set_bone_euler_local(arm_obj, "RightShoulder", 0.0, -3.5, 8.5)
        _set_bone_euler_local(arm_obj, "Cape_C", -12.0 + 3.5 * math.cos(2.0 * phase), 0.0, 3.5 * math.sin(phase))
        _set_bone_euler_local(arm_obj, "Cape_L", -9.0, 0.0, -32.0 + 4.0 * math.cos(chest_phase))
        _set_bone_euler_local(arm_obj, "Cape_R", -9.0, 0.0, 32.0 + 4.0 * math.cos(chest_phase))
        bpy.context.view_layer.update()

        for side_idx, (side, rest_a, rest_d) in enumerate([("Left", l_rest, l_dir), ("Right", r_rest, r_dir)]):
            su = (u + 0.5 * side_idx) % 1.0
            if su <= 0.38:
                st = su / 0.38
                y_off = -stride_half * 0.75 + (1.75 * stride_half) * st
                z_off = 0.016 * max(0.0, 1.0 - st / 0.25) + 0.040 * _smoothstep(0.60, 1.0, st)
                pitch = 8.0 * (1.0 - st) - 24.0 * _smoothstep(0.65, 1.0, st)
            else:
                sw = (su - 0.38) / 0.62
                y_off = stride_half - (1.75 * stride_half) * _smoothstep(0.0, 1.0, sw)
                z_off = 0.040 * (1.0 - sw) + 0.19 * math.sin(sw * math.pi)
                pitch = -24.0 * (1.0 - sw) + 12.0 * sw
            ankle_tgt = rest_a + Vector((0.0, y_off, z_off))
            foot_dir = (Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(pitch)) @ rest_d).normalized()
            pole_x = 0.15 if side == "Left" else -0.15
            _solve_planted_leg(arm_obj, side, ankle_tgt, Vector((pole_x, -1.0, 0.15)), foot_dir)

        l_fwd = math.cos(chest_phase)
        r_fwd = -l_fwd
        _solve_arm_target(arm_obj, "Left", Vector((0.225, -0.115 + 0.145 * l_fwd, hips_z + 0.095 - 0.040 * l_fwd)), Vector((0.36, 0.90, -0.10)))
        _solve_arm_target(arm_obj, "Right", Vector((-0.225, -0.115 + 0.145 * r_fwd, hips_z + 0.095 - 0.040 * r_fwd)), Vector((-0.36, 0.90, -0.10)))

        _insert_keys(arm_obj, frame)

    _finalize_loop_action(arm_obj, action, total_frames=40)
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[rig_ghost_girl] Baked 'run' (0..39 @ 60 FPS)")


def run_pipeline(src_glb: Path, out_glb: Path) -> None:
    clean_scene()
    bpy.context.scene.render.fps = FPS

    classified = _import_ghost_girl_meshes(src_glb)
    lm = _measure_landmarks(classified)
    arm_obj = _build_armature(lm)
    _skin_all_meshes(classified, arm_obj, lm)

    _bake_idle(arm_obj)
    _bake_walk(arm_obj)
    _bake_run(arm_obj)

    bpy.context.scene.frame_set(0)
    _reset_pose(arm_obj)

    for obj in bpy.data.objects:
        if obj.type == "MESH" and obj.data.shape_keys:
            for kb in obj.data.shape_keys.key_blocks[1:]:
                kb.value = 0.0
    bpy.context.view_layer.update()

    export_godot_glb(
        filepath=out_glb,
        export_animations=True,
        apply_modifiers=False,
        export_morph=True,
        export_morph_normal=True,
        save_blend=False,
    )
    print(f"[rig_ghost_girl] Exported rigged GLB -> {out_glb} ({len(arm_obj.data.bones)} bones)")


def _parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    sdk_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description="Rig and animate Ghost Girl")
    parser.add_argument("--input", type=Path, default=sdk_root / "assets" / "models" / "ghost_girl" / "ghost_girl.glb")
    parser.add_argument("--output", type=Path, default=sdk_root / "assets" / "models" / "ghost_girl" / "ghost_girl_rigged.glb")
    return parser.parse_args(argv)


def main() -> int:
    args = _parse_args()
    run_pipeline(args.input, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
