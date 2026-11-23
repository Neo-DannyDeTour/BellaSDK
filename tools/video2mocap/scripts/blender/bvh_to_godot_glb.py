"""Run inside Blender 5.3+:
  blender --background --factory-startup --python bvh_to_godot_glb.py -- in.bvh out.glb [--fps 60] [--remap-godot]

Imports a v2m BVH (centimetres, Y-up) with global_scale=0.01 (1 Blender unit = 1.0 meter in Godot 4.7+),
optionally renames bones to Godot 4.7 SkeletonProfileHumanoid convention, pushes the action to an NLA track,
and exports a clean GLB.
"""
import sys

import bpy

GODOT_HUMANOID_REMAP = [
    ("LeftUpLeg", "LeftUpperLeg"),
    ("RightUpLeg", "RightUpperLeg"),
    ("LeftLeg", "LeftLowerLeg"),
    ("LeftShin", "LeftLowerLeg"),
    ("RightLeg", "RightLowerLeg"),
    ("RightShin", "RightLowerLeg"),
    ("LeftToeBase", "LeftToes"),
    ("RightToeBase", "RightToes"),
    ("LeftArm", "LeftUpperArm"),
    ("RightArm", "RightUpperArm"),
    ("LeftForeArm", "LeftLowerArm"),
    ("RightForeArm", "RightLowerArm"),
    ("Pelvis", "Hips"),
]

argv = sys.argv[sys.argv.index("--") + 1 :]
src, dst = argv[0], argv[1]
fps = float(argv[argv.index("--fps") + 1]) if "--fps" in argv else None
remap_godot = "--remap-godot" in argv or True  # default remap for Godot SkeletonProfileHumanoid

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

bpy.ops.import_anim.bvh(
    filepath=src,
    global_scale=0.01,  # BVH is in centimetres -> 1.0 meter in Blender/Godot 4.7
    frame_start=1,
    use_fps_scale=False,
    update_scene_fps=True,
    update_scene_duration=True,
    rotate_mode="NATIVE",
    axis_forward="-Z",
    axis_up="Y",
)
if fps:
    scene.render.fps = round(fps)

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
act = arm.animation_data.action
a0, a1 = act.frame_range
scene.frame_start, scene.frame_end = round(a0), round(a1)

if remap_godot:
    bone_names = {b.name for b in arm.data.bones}
    is_soma = "LeftShin" in bone_names or "RightShin" in bone_names
    for old_name, new_name in GODOT_HUMANOID_REMAP:
        if is_soma and old_name in ("LeftLeg", "RightLeg"):
            new_name = "LeftUpperLeg" if old_name == "LeftLeg" else "RightUpperLeg"
        if old_name in arm.data.bones and new_name not in arm.data.bones:
            arm.data.bones[old_name].name = new_name

arm.name = "GeneralSkeleton"
act.name = "mocap_clip"

track = arm.animation_data.nla_tracks.new()
track.name = act.name
strip = track.strips.new(act.name, round(a0), act)
strip.name = act.name

bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm

bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format="GLB",
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_yup=True,
)
print(f"[v2m] exported Godot GLB {dst} (frames {scene.frame_start}..{scene.frame_end}, fps {scene.render.fps})")
