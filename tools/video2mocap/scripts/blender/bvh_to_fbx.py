"""Run inside Blender:  blender --background --factory-startup --python bvh_to_fbx.py -- in.bvh out.fbx [--fps 30]

Imports a v2m BVH (centimetres, Y-up) and exports an FBX armature animation for Unreal:
- scene unit scale 0.01 so 1 Blender unit = 1 cm and Unreal imports at scale 1.0
- Y-up BVH converted to Blender Z-up on import; FBX exported -Y forward / Z up (Unreal's import default)
- one action, every frame baked, no keyframe reduction (fidelity first: simplify in Unreal if wanted)
"""
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
src, dst = argv[0], argv[1]
fps = float(argv[argv.index("--fps") + 1]) if "--fps" in argv else None

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 0.01

bpy.ops.import_anim.bvh(
    filepath=src,
    global_scale=1.0,  # BVH is already in centimetres == Blender units with scale_length 0.01
    frame_start=1,
    use_fps_scale=False,
    update_scene_fps=True,
    update_scene_duration=True,
    rotate_mode="NATIVE",
    axis_forward="-Z",
    axis_up="Y",
)
if fps:
    scene.render.fps = int(round(fps))

arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
# Blender 5.x does not always update the scene duration on BVH import: set it from the action so the
# export bakes exactly the source frames (no padding, no truncation).
a0, a1 = arm.animation_data.action.frame_range
scene.frame_start, scene.frame_end = int(round(a0)), int(round(a1))
print(f"[v2m] action frames {a0}..{a1}, fps {scene.render.fps}")
arm.name = "Armature"  # Unreal treats an armature called "Armature" as the skeleton root, not a bone
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm

bpy.ops.export_scene.fbx(
    filepath=dst,
    use_selection=True,
    object_types={"ARMATURE"},
    add_leaf_bones=False,
    bake_anim=True,
    bake_anim_use_all_bones=True,
    bake_anim_use_nla_strips=False,
    bake_anim_use_all_actions=False,
    bake_anim_force_startend_keying=True,
    bake_anim_simplify_factor=0.0,
    axis_forward="-Y",
    axis_up="Z",
    apply_unit_scale=True,
    global_scale=1.0,
)
print(f"[v2m] exported {dst}")
