"""Render a textured mesh from several angles (run inside Blender):

  blender --background --factory-startup --python render_mesh_preview.py -- model.obj out.png [--views 3] [--up NEGATIVE_Y]

Workbench, texture colour, flat studio light: shows geometry and texture as captured.
"""
import math
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
src, dst = argv[0], argv[1]
views = int(argv[argv.index("--views") + 1]) if "--views" in argv else 3

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
# v2m scans are gravity-aligned by COLMAP with +Y pointing DOWN (camera convention)
up = argv[argv.index("--up") + 1] if "--up" in argv else "NEGATIVE_Y"
bpy.ops.wm.obj_import(filepath=src, up_axis=up, forward_axis="Z" if up.endswith("Y") else "NEGATIVE_Z")
objs = [o for o in scene.objects if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
centre, radius = (lo + hi) / 2, (hi - lo).length / 2

scene.render.engine = "BLENDER_WORKBENCH"
sh = scene.display.shading
sh.light, sh.color_type = "FLAT", "TEXTURE"
scene.render.resolution_x, scene.render.resolution_y = 900, 700
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("w")
scene.world.color = (0.12, 0.12, 0.13)

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 35
cam_data.clip_end = radius * 50
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
target = bpy.data.objects.new("t", None)
target.location = centre
scene.collection.objects.link(target)
tt = cam.constraints.new("TRACK_TO")
tt.target, tt.track_axis, tt.up_axis = target, "TRACK_NEGATIVE_Z", "UP_Y"

paths = []
for k in range(views):
    a = 2 * math.pi * k / views - math.pi / 2
    # the reconstruction's "up" is arbitrary until the scan is aligned; orbit around Z and Y both look ok
    cam.location = centre + Vector((math.cos(a), math.sin(a), 0.35)) * radius * 2.4
    p = dst.replace(".png", f"_{k}.png")
    scene.render.filepath = p
    bpy.ops.render.render(write_still=True)
    paths.append(p)
print("[v2m] rendered", paths)
