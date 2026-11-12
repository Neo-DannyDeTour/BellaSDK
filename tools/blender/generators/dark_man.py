"""Blender 5.x pipeline for Dark Man (TRELLIS body retopo/bake/rig) and 1.20m Tactical Fire Axe.

Produces:
- dark_man.glb: 2.00m solid manifold humanoid mesh (~15k tris) rigged to 23-bone
  SkeletonProfileHumanoid armature with T-pose rest and baked 'Idle_Hold_Axe' NLA clip.
- fire_axe.glb: 1.20m tactical fire axe (~1.9k tris) with pivot at upper ribbed grip collar.
- Raw 2048x2048 Cycles-baked texture maps (albedo, AO, roughness, metallic, OpenGL +Y normal)
  ready for delighting and ORM channel packing.
- Visual verification turnaround renders (dark_man_preview.png, fire_axe_preview.png).
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent.parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector
from common.exporter import clean_scene, export_godot_glb
from common.materials import assign_material, create_pbr_material


# ---------------------------------------------------------------------------
# Measured 2.00m Anatomical Landmarks for TRELLIS dark_man (Blender: -Y Front, +Z Up)
# ---------------------------------------------------------------------------

BONE_SPECS: list[tuple[str, str | None, tuple[float, float, float], tuple[float, float, float], bool]] = [
    ("Root", None, (0.0, 0.0, 0.0), (0.0, 0.0, 0.16), False),
    ("Hips", "Root", (0.0, 0.042, 0.96), (0.0, 0.046, 1.12), True),
    ("Spine", "Hips", (0.0, 0.046, 1.12), (0.0, 0.018, 1.30), True),
    ("Chest", "Spine", (0.0, 0.018, 1.30), (0.0, -0.010, 1.46), True),
    ("UpperChest", "Chest", (0.0, -0.010, 1.46), (0.0, 0.035, 1.60), True),
    ("Neck", "UpperChest", (0.0, 0.035, 1.60), (0.0, 0.005, 1.70), True),
    ("Head", "Neck", (0.0, 0.005, 1.70), (0.0, -0.040, 1.98), True),
    # Left Arm (+X in Blender)
    ("LeftShoulder", "UpperChest", (0.05, 0.025, 1.54), (0.218, 0.047, 1.531), True),
    ("LeftUpperArm", "LeftShoulder", (0.218, 0.047, 1.531), (0.515, 0.050, 1.553), True),
    ("LeftLowerArm", "LeftUpperArm", (0.515, 0.050, 1.553), (0.799, -0.072, 1.527), True),
    ("LeftHand", "LeftLowerArm", (0.799, -0.072, 1.527), (0.935, -0.084, 1.517), True),
    # Right Arm (-X in Blender)
    ("RightShoulder", "UpperChest", (-0.05, 0.025, 1.54), (-0.218, 0.047, 1.531), True),
    ("RightUpperArm", "RightShoulder", (-0.218, 0.047, 1.531), (-0.515, 0.050, 1.553), True),
    ("RightLowerArm", "RightUpperArm", (-0.515, 0.050, 1.553), (-0.799, -0.072, 1.527), True),
    ("RightHand", "RightLowerArm", (-0.799, -0.072, 1.527), (-0.935, -0.084, 1.517), True),
    # Left Leg (+X in Blender)
    ("LeftUpperLeg", "Hips", (0.137, 0.028, 0.958), (0.169, 0.057, 0.524), True),
    ("LeftLowerLeg", "LeftUpperLeg", (0.169, 0.057, 0.524), (0.214, 0.044, 0.097), True),
    ("LeftFoot", "LeftLowerLeg", (0.214, 0.044, 0.097), (0.232, -0.095, 0.024), True),
    ("LeftToes", "LeftFoot", (0.232, -0.095, 0.024), (0.236, -0.168, 0.020), True),
    # Right Leg (-X in Blender)
    ("RightUpperLeg", "Hips", (-0.137, 0.028, 0.958), (-0.169, 0.057, 0.524), True),
    ("RightLowerLeg", "RightUpperLeg", (-0.169, 0.057, 0.524), (-0.214, 0.044, 0.097), True),
    ("RightFoot", "RightLowerLeg", (-0.214, 0.044, 0.097), (-0.232, -0.095, 0.024), True),
    ("RightToes", "RightFoot", (-0.232, -0.095, 0.024), (-0.236, -0.168, 0.020), True),
]


# ---------------------------------------------------------------------------
# Cycles Bake Helpers
# ---------------------------------------------------------------------------

def _configure_cycles(samples: int = 16) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    scene.render.bake.margin = 16
    scene.render.bake.margin_type = "EXTEND"
    scene.render.bake.use_clear = True


def _save_blender_image(img: bpy.types.Image, out_path: Path, colorspace: str = "sRGB") -> None:
    """Saves an in-memory baked Blender Image without resetting its colorspace buffer."""
    _ = colorspace  # Already configured before baking; resetting post-bake clears Blender 5.3 buffer
    img.filepath_raw = str(out_path)
    img.file_format = "PNG"
    img.save()


def _bake_selected_to_active_pass(
    high_obj: bpy.types.Object,
    low_obj: bpy.types.Object,
    bake_type: str,
    width: int,
    height: int,
    out_path: Path,
    colorspace: str = "sRGB",
    cage_extrusion: float = 0.04,
) -> bpy.types.Image:
    """Bakes EMIT or NORMAL from high_obj onto low_obj at (width, height)."""
    img = bpy.data.images.new(out_path.stem, width=width, height=height, alpha=False, is_data=(colorspace != "sRGB"))
    img.colorspace_settings.name = colorspace

    mat = bpy.data.materials.new(f"BakeTarget_{out_path.stem}")
    mat.use_nodes = True
    tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex_node.image = img
    mat.node_tree.nodes.active = tex_node

    orig_mats = list(low_obj.data.materials)
    low_obj.data.materials.clear()
    low_obj.data.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    high_obj.select_set(True)
    low_obj.select_set(True)
    bpy.context.view_layer.objects.active = low_obj

    scene = bpy.context.scene
    scene.render.bake.use_selected_to_active = True
    scene.render.bake.cage_extrusion = cage_extrusion
    scene.render.bake.max_ray_distance = cage_extrusion * 2.0
    if bake_type == "NORMAL":
        scene.render.bake.normal_space = "TANGENT"
        scene.render.bake.normal_r = "POS_X"
        scene.render.bake.normal_g = "POS_Y"
        scene.render.bake.normal_b = "POS_Z"

    bpy.ops.object.bake(type=bake_type)
    _save_blender_image(img, out_path, colorspace=colorspace)

    low_obj.data.materials.clear()
    for m in orig_mats:
        low_obj.data.materials.append(m)
    bpy.data.materials.remove(mat)
    return img


def _bake_single_object_ao(
    obj: bpy.types.Object,
    width: int,
    height: int,
    out_path: Path,
) -> bpy.types.Image:
    """Bakes ambient occlusion directly onto obj's UV layout."""
    img = bpy.data.images.new(out_path.stem, width=width, height=height, alpha=False, is_data=True)
    img.colorspace_settings.name = "Non-Color"

    mat = bpy.data.materials.new(f"BakeAO_{out_path.stem}")
    mat.use_nodes = True
    tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex_node.image = img
    mat.node_tree.nodes.active = tex_node

    orig_mats = list(obj.data.materials)
    obj.data.materials.clear()
    obj.data.materials.append(mat)

    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    scene = bpy.context.scene
    scene.render.bake.use_selected_to_active = False
    bpy.ops.object.bake(type="AO")
    _save_blender_image(img, out_path, colorspace="Non-Color")

    obj.data.materials.clear()
    for m in orig_mats:
        obj.data.materials.append(m)
    bpy.data.materials.remove(mat)
    return img


# ---------------------------------------------------------------------------
# Dark Man Body Processing, Rigging & Pose Baking
# ---------------------------------------------------------------------------

def _import_welded_body(raw_glb: Path) -> bpy.types.Object:
    bpy.ops.import_scene.gltf(filepath=str(raw_glb))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise RuntimeError(f"No meshes in {raw_glb}")

    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()

    obj = bpy.context.view_layer.objects.active
    obj.name = "DarkManBody"
    obj.data.name = "DarkManBodyMesh"
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)

    # Weld glTF UV-split seams to make solid watertight manifold mesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.dissolve_degenerate(bm, dist=0.0001, edges=bm.edges)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    non_man = sum(1 for e in bm.edges if not e.is_manifold)
    bm.to_mesh(obj.data)
    bm.free()

    # Scale to exact 2.00m height, bottom Z=0, centered X/Y
    zs = [v.co.z for v in obj.data.vertices]
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    scale = 2.0 / (max(zs) - min(zs))
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    min_z = min(zs)
    for v in obj.data.vertices:
        v.co = Vector(((v.co.x - cx) * scale, (v.co.y - cy) * scale, (v.co.z - min_z) * scale))
    obj.data.update()
    print(f"[DarkMan] Welded manifold mesh: non_manifold_edges={non_man}, height=2.00m")
    return obj


def _make_emission_source_material(src_obj: bpy.types.Object) -> None:
    """Rewires source material image into Emission so Cycles EMIT bake reads pure Base Color."""
    tex_img = None
    for mat in src_obj.data.materials:
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    tex_img = node.image
                    break
        if tex_img:
            break

    emit_mat = bpy.data.materials.new("DarkMan_EmitSrc")
    emit_mat.use_nodes = True
    nodes = emit_mat.node_tree.nodes
    links = emit_mat.node_tree.links
    nodes.clear()
    out_node = nodes.new("ShaderNodeOutputMaterial")
    emit_node = nodes.new("ShaderNodeEmission")
    emit_node.inputs["Strength"].default_value = 1.0
    if tex_img is not None:
        tex_node = nodes.new("ShaderNodeTexImage")
        tex_node.image = tex_img
        links.new(tex_node.outputs["Color"], emit_node.inputs["Color"])
    else:
        emit_node.inputs["Color"].default_value = (0.08, 0.08, 0.09, 1.0)
    links.new(emit_node.outputs["Emission"], out_node.inputs["Surface"])

    src_obj.data.materials.clear()
    src_obj.data.materials.append(emit_mat)


def _retopo_and_bake_body(raw_body: bpy.types.Object, out_dir: Path, tex_size: int = 2048) -> bpy.types.Object:
    """Refines body topology to ~15k tris, unwraps non-overlapping UVs, and bakes maps."""
    # High-poly smoothed source for Selected-to-Active baking
    high_obj = raw_body.copy()
    high_obj.data = raw_body.data.copy()
    high_obj.name = "DarkMan_HighSrc"
    bpy.context.scene.collection.objects.link(high_obj)

    bpy.context.view_layer.objects.active = high_obj
    sub_hi = high_obj.modifiers.new("SubHi", "SUBSURF")
    sub_hi.levels = 2
    sub_hi.render_levels = 2
    bpy.ops.object.modifier_apply(modifier=sub_hi.name)
    _make_emission_source_material(high_obj)

    # Low/target deformable mesh (~15k tris)
    bpy.context.view_layer.objects.active = raw_body
    sub_lo = raw_body.modifiers.new("SubLo", "SUBSURF")
    sub_lo.levels = 1
    sub_lo.render_levels = 1
    bpy.ops.object.modifier_apply(modifier=sub_lo.name)

    tri_now = sum(len(p.vertices) - 2 for p in raw_body.data.polygons)
    target_tris = 15000
    if tri_now > target_tris:
        dec = raw_body.modifiers.new("Decimate", "DECIMATE")
        dec.decimate_type = "COLLAPSE"
        dec.ratio = max(0.05, float(target_tris) / float(tri_now))
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=dec.name)

    bpy.ops.object.shade_smooth()

    # Clean non-overlapping UV unwrap
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.008)
    bpy.ops.object.mode_set(mode="OBJECT")

    _configure_cycles(samples=16)
    _bake_selected_to_active_pass(
        high_obj, raw_body, "EMIT", tex_size, tex_size,
        out_dir / "_raw_dark_man_albedo.png", colorspace="sRGB", cage_extrusion=0.015,
    )
    _bake_selected_to_active_pass(
        high_obj, raw_body, "NORMAL", tex_size, tex_size,
        out_dir / "dark_man_normal.png", colorspace="Non-Color", cage_extrusion=0.015,
    )
    high_obj.hide_render = True
    bpy.data.objects.remove(high_obj, do_unlink=True)

    _bake_single_object_ao(raw_body, tex_size, tex_size, out_dir / "_raw_dark_man_ao.png")

    final_tris = sum(len(p.vertices) - 2 for p in raw_body.data.polygons)
    print(f"[DarkMan] Retopo & Cycles bake done: {final_tris} tris")
    return raw_body


def _build_skeleton_and_skin(body_obj: bpy.types.Object) -> bpy.types.Object:
    """Builds 23-bone SkeletonProfileHumanoid rig and binds body with zero-weight fallback."""
    arm_data = bpy.data.armatures.new("DarkManSkeleton")
    arm_obj = bpy.data.objects.new("DarkManRig", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    created: dict[str, bpy.types.EditBone] = {}
    for b_name, parent_name, head, tail, use_def in BONE_SPECS:
        eb = arm_data.edit_bones.new(b_name)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        eb.use_deform = use_def
        if parent_name:
            eb.parent = created[parent_name]
            eb.use_connect = (eb.head - created[parent_name].tail).length < 0.002
        created[b_name] = eb

    bpy.ops.armature.select_all(action="SELECT")
    bpy.ops.armature.calculate_roll(type="GLOBAL_POS_Z")
    bpy.ops.object.mode_set(mode="OBJECT")

    bpy.ops.object.select_all(action="DESELECT")
    body_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")

    # Fallback: ensure every vertex has >=1 non-zero deform group weight & <=4 influences
    mesh = body_obj.data
    deform_bones = [b for b in arm_data.bones if b.use_deform]
    vg_by_name = {vg.name: vg for vg in body_obj.vertex_groups}
    for b in deform_bones:
        if b.name not in vg_by_name:
            vg_by_name[b.name] = body_obj.vertex_groups.new(name=b.name)

    repaired = 0
    for v in mesh.vertices:
        total = sum(g.weight for g in v.groups)
        if total < 1e-4:
            best_bone = min(
                deform_bones,
                key=lambda b: (v.co - ((b.head_local + b.tail_local) * 0.5)).length_squared,
            )
            vg_by_name[best_bone.name].add([v.index], 1.0, "REPLACE")
            repaired += 1

    bpy.context.view_layer.objects.active = body_obj
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    print(f"[DarkMan] Skinned to 23-bone SkeletonProfileHumanoid rig (repaired_verts={repaired})")
    return arm_obj


def _solve_two_bone_elbow(
    shoulder: Vector,
    wrist: Vector,
    l1: float,
    l2: float,
    pole_hint: Vector,
) -> Vector:
    """Computes world-space elbow position via law of cosines without stretching limbs."""
    delta = wrist - shoulder
    dist = max(0.05, min(delta.length, l1 + l2 - 0.004))
    fwd = delta.normalized()
    cos_a = max(-0.99, min(0.99, (l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist)))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    ortho = (pole_hint - fwd * pole_hint.dot(fwd)).normalized()
    return shoulder + fwd * (l1 * cos_a) + ortho * (l1 * sin_a)


def _aim_pose_bone(arm_obj: bpy.types.Object, bone_name: str, target_dir: Vector, twist_rad: float = 0.0) -> None:
    """Rotates PoseBone in world space so its head->tail matches target_dir."""
    bpy.context.view_layer.update()
    pb = arm_obj.pose.bones[bone_name]
    pb.rotation_mode = "QUATERNION"
    cur_dir = (pb.tail - pb.head).normalized()
    dq = cur_dir.rotation_difference(target_dir.normalized())
    if abs(twist_rad) > 1e-5:
        dq = Quaternion(target_dir.normalized(), twist_rad) @ dq
    pivot = pb.head.copy()
    pb.matrix = Matrix.Translation(pivot) @ dq.to_matrix().to_4x4() @ Matrix.Translation(-pivot) @ pb.matrix
    bpy.context.view_layer.update()


def _create_idle_hold_axe_clip(arm_obj: bpy.types.Object) -> None:
    """Bakes 'Idle_Hold_Axe' two-handed diagonal pose into NLA track while keeping T-pose rest."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")

    arm_obj.animation_data_create()
    action = bpy.data.actions.new(name="Idle_Hold_Axe")
    arm_obj.animation_data.action = action

    # Target palm grips matching front/side/back reference pose (Images 3 & 4)
    # RightHand (viewer left) sits high by right chest; LeftHand (viewer right) sits low by left hip.
    # Offset wrists back slightly from palm center so fingers wrap onto shaft instead of poking past.
    r_palm_tgt = Vector((-0.190, -0.240, 1.455))
    l_palm_tgt = Vector((0.185, -0.205, 1.080))
    shaft_dir = (r_palm_tgt - l_palm_tgt).normalized()

    frames = [1, 31, 61]
    for f_idx, frame in enumerate(frames):
        bpy.context.scene.frame_set(frame)
        # Reset all pose bones before evaluating frame
        for pb in arm_obj.pose.bones:
            pb.rotation_mode = "QUATERNION"
            pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
            pb.location = Vector((0.0, 0.0, 0.0))
        bpy.context.view_layer.update()

        breath = 0.0 if f_idx in (0, 2) else 1.0

        # Subtle upper-body lean & breath
        arm_obj.pose.bones["Spine"].rotation_quaternion = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(2.5 + 0.8 * breath))
        arm_obj.pose.bones["Chest"].rotation_quaternion = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(2.0 + 0.8 * breath))
        arm_obj.pose.bones["Head"].rotation_quaternion = Quaternion(Vector((1.0, 0.0, 0.0)), math.radians(3.0 - 0.6 * breath))
        bpy.context.view_layer.update()

        # Right Arm (upper collar grip): hand curls inward-down around handle
        r_hand_dir = Vector((0.68, -0.20, -0.70)).normalized()
        r_sh = arm_obj.pose.bones["RightUpperArm"].head.copy()
        l1_r = (arm_obj.pose.bones["RightUpperArm"].tail - r_sh).length
        l2_r = (arm_obj.pose.bones["RightLowerArm"].tail - arm_obj.pose.bones["RightLowerArm"].head).length
        r_palm_frame = r_palm_tgt + Vector((0.0, 0.0, 0.008 * breath))
        r_wrist_frame = r_palm_frame - r_hand_dir * 0.055
        r_elbow = _solve_two_bone_elbow(r_sh, r_wrist_frame, l1_r, l2_r, Vector((-0.88, 0.28, -0.38)))
        _aim_pose_bone(arm_obj, "RightUpperArm", r_elbow - r_sh)
        _aim_pose_bone(arm_obj, "RightLowerArm", r_wrist_frame - r_elbow)
        _aim_pose_bone(arm_obj, "RightHand", r_hand_dir)

        # Left Arm (lower pommel grip): hand wraps down-inward along lower shaft (no forward paddle)
        l_hand_dir = (Vector((-0.62, 0.22, -0.75)) + shaft_dir * 0.15).normalized()
        l_sh = arm_obj.pose.bones["LeftUpperArm"].head.copy()
        l1_l = (arm_obj.pose.bones["LeftUpperArm"].tail - l_sh).length
        l2_l = (arm_obj.pose.bones["LeftLowerArm"].tail - arm_obj.pose.bones["LeftLowerArm"].head).length
        l_palm_frame = l_palm_tgt + Vector((0.0, 0.0, 0.004 * breath))
        l_wrist_frame = l_palm_frame - l_hand_dir * 0.055
        l_elbow = _solve_two_bone_elbow(l_sh, l_wrist_frame, l1_l, l2_l, Vector((0.88, 0.36, -0.28)))
        _aim_pose_bone(arm_obj, "LeftUpperArm", l_elbow - l_sh)
        _aim_pose_bone(arm_obj, "LeftLowerArm", l_wrist_frame - l_elbow)
        _aim_pose_bone(arm_obj, "LeftHand", l_hand_dir)

        for pb in arm_obj.pose.bones:
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
            if pb.name == "Hips":
                pb.keyframe_insert(data_path="location", frame=frame)

    # Push to NLA and clear active action so rest pose remains clean T-pose
    nla = arm_obj.animation_data.nla_tracks.new()
    nla.name = "Idle_Hold_Axe"
    nla.strips.new("Idle_Hold_Axe", 1, action)
    arm_obj.animation_data.action = None
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 61

    # Reset pose back to rest T-pose for clean glTF export
    for pb in arm_obj.pose.bones:
        pb.rotation_quaternion = Quaternion((1.0, 0.0, 0.0, 0.0))
        pb.location = Vector((0.0, 0.0, 0.0))
    bpy.ops.object.mode_set(mode="OBJECT")
    print("[DarkMan] Baked Idle_Hold_Axe NLA clip (frames 1..61 @ 30fps)")


# ---------------------------------------------------------------------------
# Tactical 1.20m Fire Axe Geometry & Cycles PBR Bake
# ---------------------------------------------------------------------------

def _build_fire_axe_geometry(high_detail: bool = True) -> tuple[bpy.types.Object, list[bpy.types.Material]]:
    """Constructs 1.20m tactical fire axe matching reference sheet (pivot at upper grip collar).

    Coordinates: +Y along shaft (pommel y=-0.84m, grip pivot y=0.0, head top y=+0.36m).
    Blade faces +Z, top spike poll faces -Z, thickness along X.
    """
    mesh = bpy.data.meshes.new("FireAxeMesh_Data" if not high_detail else "FireAxeHigh_Data")
    obj = bpy.data.objects.new("FireAxeMesh" if not high_detail else "FireAxeHigh", mesh)
    bpy.context.scene.collection.objects.link(obj)

    prefix = "High" if high_detail else "Low"
    mat_steel = create_pbr_material(f"{prefix}_Axe_Steel", base_color=(0.048, 0.052, 0.056, 1.0), metallic=0.90, roughness=0.34)
    mat_edge = create_pbr_material(f"{prefix}_Axe_Edge", base_color=(0.145, 0.155, 0.165, 1.0), metallic=0.94, roughness=0.22)
    mat_rubber = create_pbr_material(f"{prefix}_Axe_Rubber", base_color=(0.011, 0.011, 0.012, 1.0), metallic=0.0, roughness=0.80)
    mat_shaft = create_pbr_material(f"{prefix}_Axe_Polymer", base_color=(0.018, 0.018, 0.020, 1.0), metallic=0.0, roughness=0.52)
    mats = [mat_shaft, mat_rubber, mat_steel, mat_edge]
    for m in mats:
        obj.data.materials.append(m)

    bm = bmesh.new()

    # 1. Curved Fluted Polymer Haft (y in [-0.84, +0.125], terminates cleanly inside eye collar)
    segs_y = 64 if high_detail else 48
    segs_ring = 24 if high_detail else 16
    rings = []
    for iy in range(segs_y + 1):
        t = iy / float(segs_y)
        y = -0.84 + t * 0.965
        # Ergonomic S-curve along Z matching fire_axe.png (normalized to total shaft span)
        z_off = (
            -0.018 * math.sin(t * math.pi * 1.25)
            + (0.022 * ((0.22 - t) / 0.22) ** 2 if t < 0.22 else 0.0)
        )
        rx = 0.0145
        rz = 0.022
        # Flared pommel
        if t < 0.085:
            flare = 1.0 + 0.42 * (1.0 - t / 0.085) ** 1.5
            rz *= flare
            rx *= 1.0 + 0.18 * (1.0 - t / 0.085)
        # Upper ribbed rubber grip collar (y in [-0.10, +0.10])
        in_collar = -0.10 <= y <= 0.10
        if in_collar:
            rib = 0.0018 * math.sin((y + 0.10) / 0.20 * math.pi * 24.0) if high_detail else 0.0
            rx = 0.0185 + rib
            rz = 0.0265 + rib
        elif y > 0.10:
            # Taper neatly into eye collar bottom
            rx = 0.0185
            rz = 0.0265

        ring_verts = []
        for ir in range(segs_ring):
            ang = (ir / float(segs_ring)) * math.tau
            # Subtle spiral grip fluting on lower polymer shaft
            flute = 0.0
            if high_detail and -0.80 <= y <= -0.14:
                spiral = math.sin(ang * 4.0 + y * 24.0)
                flute = 0.0010 * max(0.0, spiral)
            vx = (rx + flute) * math.cos(ang)
            vz = z_off + (rz + flute) * math.sin(ang)
            ring_verts.append(bm.verts.new((vx, y, vz)))
        rings.append((ring_verts, 1 if in_collar else 0))

    for i in range(len(rings) - 1):
        r0, mat_i = rings[i]
        r1, _ = rings[i + 1]
        for j in range(segs_ring):
            jn = (j + 1) % segs_ring
            f = bm.faces.new((r0[j], r0[jn], r1[jn], r1[j]))
            f.material_index = mat_i
    # Cap pommel & eye-socket top
    f_bot = bm.faces.new(list(reversed(rings[0][0])))
    f_bot.material_index = 0
    f_top = bm.faces.new(rings[-1][0])
    f_top.material_index = 2

    # 2. Steel Head Construction Helpers
    def add_box_prism(pts_yz: list[tuple[float, float]], half_x_fn, mat_idx: int, edge_mat_idx: int) -> None:
        n = len(pts_yz)
        front_v = []
        back_v = []
        for py, pz in pts_yz:
            hx = half_x_fn(py, pz)
            front_v.append(bm.verts.new((hx, py, pz)))
            back_v.append(bm.verts.new((-hx, py, pz)))
        f_pos = bm.faces.new(front_v)
        f_pos.material_index = mat_idx
        f_neg = bm.faces.new(list(reversed(back_v)))
        f_neg.material_index = mat_idx
        for k in range(n):
            kn = (k + 1) % n
            f_rim = bm.faces.new((front_v[k], back_v[k], back_v[kn], front_v[kn]))
            # Honed steel cutting edge / spike rim
            is_bit = pts_yz[k][1] > 0.14 and pts_yz[kn][1] > 0.14
            is_spike = pts_yz[k][1] < -0.075 and pts_yz[kn][1] < -0.075
            f_rim.material_index = edge_mat_idx if (is_bit or is_spike) else mat_idx

    # Bearded Curved Blade Profile (y, z)
    blade_profile = [
        (0.285, 0.029),   # top eye front (butted outside eye block to prevent coplanar overlap)
        (0.282, 0.085),
        (0.277, 0.165),
        (0.265, 0.232),   # upper toe tip
        (0.232, 0.240),
        (0.195, 0.244),
        (0.155, 0.246),
        (0.115, 0.245),
        (0.075, 0.240),
        (0.035, 0.230),
        (-0.015, 0.212),  # lower bearded heel
        (0.025, 0.165),
        (0.060, 0.122),   # curved beard throat
        (0.095, 0.085),
        (0.118, 0.052),
        (0.125, 0.029),   # lower eye front
    ]

    def blade_half_x(py: float, pz: float) -> float:
        # Taper cleanly from 23mm socket cheek down to 2.2mm honed edge
        t_z = max(0.0, min(1.0, (pz - 0.029) / 0.215))
        hx = 0.023 * (1.0 - 0.88 * (t_z ** 0.85))
        # Subtle recessed cheek fuller flutes on mid blade (matching fire_axe.png)
        if high_detail and 0.07 <= pz <= 0.18 and 0.08 <= py <= 0.23:
            slot_val = math.sin((py - 0.08) / 0.15 * math.pi * 6.0)
            if slot_val > 0.45:
                hx *= 0.72
        return max(0.0022, hx)

    add_box_prism(blade_profile, blade_half_x, mat_idx=2, edge_mat_idx=3)

    # Eye Block Wrapper (y in [+0.115, +0.295], z in [-0.038, +0.030])
    eye_profile = [
        (0.295, -0.038),
        (0.295, 0.030),
        (0.115, 0.030),
        (0.115, -0.038),
    ]
    add_box_prism(eye_profile, lambda _y, _z: 0.0245, mat_idx=2, edge_mat_idx=2)

    # Tang Cap on top of Eye (y in [+0.295, +0.360] -> exact 1.20m total y in [-0.84, +0.36])
    tang_profile = [
        (0.360, -0.028),
        (0.360, 0.022),
        (0.295, 0.028),
        (0.295, -0.034),
    ]
    add_box_prism(tang_profile, lambda _y, _z: 0.019, mat_idx=2, edge_mat_idx=2)

    # Top Rear Spike Poll (y in [+0.215, +0.345], z in [-0.118, -0.037])
    spike_profile = [
        (0.295, -0.037),
        (0.345, -0.055),
        (0.320, -0.118),  # spike tip
        (0.255, -0.102),
        (0.220, -0.037),
    ]

    def spike_half_x(_py: float, pz: float) -> float:
        t_back = max(0.0, min(1.0, (-pz - 0.030) / 0.088))
        return max(0.0025, 0.020 * (1.0 - 0.86 * t_back))

    add_box_prism(spike_profile, spike_half_x, mat_idx=2, edge_mat_idx=3)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_smooth()
    if not high_detail:
        # Mark sharp edges on blade/spike > 45 deg
        bm_s = bmesh.new()
        bm_s.from_mesh(mesh)
        ang_lim = math.radians(45.0)
        for e in bm_s.edges:
            if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > ang_lim:
                e.seam = True
                e.smooth = False
        bmesh.ops.triangulate(bm_s, faces=bm_s.faces)
        bm_s.to_mesh(mesh)
        bm_s.free()
    else:
        bm_h = bmesh.new()
        bm_h.from_mesh(mesh)
        bmesh.ops.triangulate(bm_h, faces=bm_h.faces)
        bm_h.to_mesh(mesh)
        bm_h.free()

    return obj, mats


def _bake_fire_axe(out_dir: Path, tex_size: int = 2048) -> bpy.types.Object:
    """Builds ~1,900-tri FireAxeMesh and bakes 2048 PBR maps from high-detail geometry."""
    high_axe, _ = _build_fire_axe_geometry(high_detail=True)
    low_axe, _ = _build_fire_axe_geometry(high_detail=False)

    # Decimate low_axe only if > 2000 tris
    tri_now = sum(len(p.vertices) - 2 for p in low_axe.data.polygons)
    if tri_now > 2000:
        bpy.context.view_layer.objects.active = low_axe
        dec = low_axe.modifiers.new("DecimateAxe", "DECIMATE")
        dec.ratio = 1900.0 / float(tri_now)
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=dec.name)

    bpy.context.view_layer.objects.active = low_axe
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(55.0), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")

    _configure_cycles(samples=16)

    # Bake Albedo, Roughness, and Metallic via temporary Emission rewire on high_axe
    def bake_channel_from_materials(channel: str, out_name: str, colorspace: str) -> None:
        orig_mats = list(high_axe.data.materials)
        temp_mats = []
        for m in orig_mats:
            bsdf = m.node_tree.nodes.get("Principled BSDF")
            val_col = bsdf.inputs["Base Color"].default_value[:]
            val_rough = bsdf.inputs["Roughness"].default_value
            val_metal = bsdf.inputs["Metallic"].default_value

            tm = bpy.data.materials.new(f"Tmp_{m.name}_{channel}")
            tm.use_nodes = True
            tm.node_tree.nodes.clear()
            out_n = tm.node_tree.nodes.new("ShaderNodeOutputMaterial")
            em_n = tm.node_tree.nodes.new("ShaderNodeEmission")
            if channel == "ALBEDO":
                em_n.inputs["Color"].default_value = val_col
            elif channel == "ROUGHNESS":
                em_n.inputs["Color"].default_value = (val_rough, val_rough, val_rough, 1.0)
            else:
                em_n.inputs["Color"].default_value = (val_metal, val_metal, val_metal, 1.0)
            tm.node_tree.links.new(em_n.outputs["Emission"], out_n.inputs["Surface"])
            temp_mats.append(tm)

        # Swap slots IN-PLACE so face.material_index assignments on high_axe stay intact!
        for idx, tm in enumerate(temp_mats):
            high_axe.data.materials[idx] = tm
        _bake_selected_to_active_pass(
            high_obj=high_axe, low_obj=low_axe, bake_type="EMIT",
            width=tex_size, height=tex_size, out_path=out_dir / out_name,
            colorspace=colorspace, cage_extrusion=0.015,
        )
        for idx, m in enumerate(orig_mats):
            high_axe.data.materials[idx] = m
        for tm in temp_mats:
            bpy.data.materials.remove(tm)

    bake_channel_from_materials("ALBEDO", "fire_axe_albedo.png", "sRGB")
    bake_channel_from_materials("ROUGHNESS", "_raw_fire_axe_rough.png", "Non-Color")
    bake_channel_from_materials("METALLIC", "_raw_fire_axe_metal.png", "Non-Color")
    _bake_selected_to_active_pass(
        high_axe, low_axe, "NORMAL", tex_size, tex_size,
        out_dir / "fire_axe_normal.png", colorspace="Non-Color", cage_extrusion=0.015,
    )
    high_axe.hide_render = True
    bpy.data.objects.remove(high_axe, do_unlink=True)

    _bake_single_object_ao(low_axe, tex_size, tex_size, out_dir / "_raw_fire_axe_ao.png")

    # Collapse low_axe to single unified material slot for Godot ShaderMaterial
    alb_img = bpy.data.images.load(str(out_dir / "fire_axe_albedo.png"))
    single_mat = create_pbr_material(
        "Mat_FireAxe", base_color=(1.0, 1.0, 1.0, 1.0), metallic=0.2, roughness=0.45, base_color_image=alb_img,
    )
    low_axe.data.materials.clear()
    low_axe.data.materials.append(single_mat)

    tris = sum(len(p.vertices) - 2 for p in low_axe.data.polygons)
    print(f"[FireAxe] Built & baked FireAxeMesh: {tris} tris, length=1.20m")
    return low_axe


# ---------------------------------------------------------------------------
# Preview Render Helper
# ---------------------------------------------------------------------------

def _render_verification_views(
    focus_center: Vector,
    dist: float,
    out_dir: Path,
    prefix: str,
) -> list[Path]:
    world = bpy.data.worlds.get("Studio") or bpy.data.worlds.new("Studio")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.38, 0.38, 0.40, 1.0)
        bg.inputs["Strength"].default_value = 1.0

    lights = []
    for idx, (offset, energy) in enumerate([
        ((2.2, -2.8, 2.2), 180.0),
        ((-2.4, -2.0, 1.4), 120.0),
        ((0.0, 3.0, 2.0), 150.0),
    ]):
        ld = bpy.data.lights.new(f"PrevL_{idx}", "AREA")
        ld.energy = energy
        ld.size = 2.0
        lo = bpy.data.objects.new(f"PrevL_{idx}", ld)
        bpy.context.scene.collection.objects.link(lo)
        lo.location = focus_center + Vector(offset)
        lo.rotation_euler = (focus_center - lo.location).to_track_quat("-Z", "Y").to_euler()
        lights.append(lo)

    cd = bpy.data.cameras.new("PrevCam")
    cam = bpy.data.objects.new("PrevCam", cd)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512

    views = [
        ("front", Vector((0.0, -dist, 0.0))),
        ("side", Vector((dist, 0.0, 0.0))),
        ("back", Vector((0.0, dist, 0.0))),
        ("iso", Vector((dist * 0.7, -dist * 0.7, dist * 0.35))),
    ]
    paths = []
    for v_name, offset in views:
        cam.location = focus_center + offset
        cam.rotation_euler = (focus_center - cam.location).to_track_quat("-Z", "Y").to_euler()
        p = out_dir / f"_{prefix}_{v_name}.png"
        scene.render.filepath = str(p)
        bpy.ops.render.render(write_still=True)
        paths.append(p)

    for lo in lights:
        bpy.data.objects.remove(lo, do_unlink=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    return paths


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

def run_blender_pipeline(raw_body_glb: Path, out_dir: Path, tex_size: int = 2048) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Dark Man GLB + Bakes
    clean_scene()
    body_obj = _import_welded_body(raw_body_glb)
    _retopo_and_bake_body(body_obj, out_dir, tex_size=tex_size)

    raw_alb_img = bpy.data.images.load(str(out_dir / "_raw_dark_man_albedo.png"))
    body_mat = create_pbr_material(
        "Mat_DarkMan", base_color=(1.0, 1.0, 1.0, 1.0), metallic=0.0, roughness=0.45, base_color_image=raw_alb_img,
    )
    assign_material(body_obj, body_mat)

    arm_obj = _build_skeleton_and_skin(body_obj)
    _create_idle_hold_axe_clip(arm_obj)

    export_godot_glb(
        filepath=out_dir / "dark_man.glb",
        export_animations=True,
        apply_modifiers=False,
        save_blend=False,
    )

    # 2. Fire Axe GLB + Bakes
    clean_scene()
    axe_obj = _bake_fire_axe(out_dir, tex_size=tex_size)
    export_godot_glb(
        filepath=out_dir / "fire_axe.glb",
        export_animations=False,
        apply_modifiers=True,
        save_blend=False,
    )

    # 3. Composite Verification Preview (DarkMan in Idle_Hold_Axe + FireAxe in two-handed grip)
    clean_scene()
    bpy.ops.import_scene.gltf(filepath=str(out_dir / "dark_man.glb"))
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    bpy.ops.import_scene.gltf(filepath=str(out_dir / "fire_axe.glb"))
    axe = next(o for o in bpy.context.scene.objects if o.name.startswith("FireAxe"))

    # Evaluate Idle_Hold_Axe frame 1
    if arm.animation_data and arm.animation_data.nla_tracks:
        track = arm.animation_data.nla_tracks[0]
        arm.animation_data.action = track.strips[0].action
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()

    rh_head = arm.matrix_world @ arm.pose.bones["RightHand"].head
    rh_tail = arm.matrix_world @ arm.pose.bones["RightHand"].tail
    lh_head = arm.matrix_world @ arm.pose.bones["LeftHand"].head
    lh_tail = arm.matrix_world @ arm.pose.bones["LeftHand"].tail
    rh_palm = rh_head.lerp(rh_tail, 0.42)
    lh_palm = lh_head.lerp(lh_tail, 0.42)

    shaft_world = (rh_palm - lh_palm).normalized()
    blade_hint = Vector((-0.68, -0.35, -0.64)).normalized()
    blade_world = (blade_hint - shaft_world * blade_hint.dot(shaft_world)).normalized()
    side_world = shaft_world.cross(blade_world).normalized()
    # Blender fire_axe has +Y = shaft, +Z = blade, +X = side
    rot_m = Matrix((side_world, shaft_world, blade_world)).transposed().to_4x4()
    axe.matrix_world = Matrix.Translation(rh_palm) @ rot_m
    bpy.context.view_layer.update()

    _render_verification_views(Vector((0.0, 0.0, 1.0)), 3.2, out_dir, "prev_dark_man")

    # Save exact Blender-space target transform metadata for cross-check
    meta = {
        "dark_man_tris": sum(len(p.vertices) - 2 for p in next(o for o in bpy.context.scene.objects if o.type == "MESH" and o != axe).data.polygons),
        "fire_axe_tris": sum(len(p.vertices) - 2 for p in axe.data.polygons),
        "right_hand_world_blender": [round(c, 5) for c in rh_head],
        "right_palm_world_blender": [round(c, 5) for c in rh_palm],
        "left_hand_world_blender": [round(c, 5) for c in lh_head],
        "left_palm_world_blender": [round(c, 5) for c in lh_palm],
    }
    (out_dir / "_bake_stats.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-body", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--tex-size", type=int, default=2048)
    args = parser.parse_args(argv)
    run_blender_pipeline(args.raw_body, args.out_dir, tex_size=args.tex_size)


if __name__ == "__main__":
    main()
