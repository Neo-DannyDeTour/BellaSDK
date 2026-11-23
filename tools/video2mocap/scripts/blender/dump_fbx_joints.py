"""Verification helper (run in Blender): import an FBX and dump world joint positions per frame as JSON.
blender --background --factory-startup --python dump_fbx_joints.py -- in.fbx out.json"""
import json
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1 :]
bpy.context.scene.unit_settings.scale_length = 0.01
bpy.ops.import_scene.fbx(filepath=argv[0], automatic_bone_orientation=False)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
act = arm.animation_data.action
f0, f1 = (int(round(x)) for x in act.frame_range)
out = {"frame_start": f0, "names": [b.name for b in arm.pose.bones], "frames": []}
for f in range(f0, f1 + 1):
    bpy.context.scene.frame_set(f)
    out["frames"].append([list(arm.matrix_world @ b.head) for b in arm.pose.bones])
json.dump(out, open(argv[1], "w"))
