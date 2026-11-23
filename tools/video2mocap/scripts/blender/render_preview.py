"""Render a v2m FBX as a 3D preview video (run inside Blender):

  blender --background --factory-startup --python render_preview.py -- in.fbx out_frames_dir [--size 720x1280] [--fps 30]

The armature is turned into a renderable "tube" figure (one vertex per joint, skin modifier, armature
deform), left side blue / right side red, on a checker floor, with a camera that follows the hips.
Workbench engine: fast, deterministic, no GPU needed.
"""
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1 :]
src, dst = argv[0], argv[1]
W, H = (int(x) for x in (argv[argv.index("--size") + 1] if "--size" in argv else "720x1280").split("x"))
fps = int(argv[argv.index("--fps") + 1]) if "--fps" in argv else None

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.scale_length = 0.01
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False)
arm = next(o for o in scene.objects if o.type == "ARMATURE")
act = arm.animation_data.action
f0, f1 = (int(round(x)) for x in act.frame_range)
scene.frame_start, scene.frame_end = f0, f1
if fps:
    scene.render.fps = fps

# ---------------------------------------------------------------- tube figure
bones = arm.data.bones
mw = arm.matrix_world
verts = [mw @ b.head_local for b in bones]
index = {b.name: i for i, b in enumerate(bones)}
edges = [(index[b.parent.name], index[b.name]) for b in bones if b.parent]
mesh = bpy.data.meshes.new("figure")
mesh.from_pydata([tuple(v) for v in verts], edges, [])
fig = bpy.data.objects.new("figure", mesh)
scene.collection.objects.link(fig)
for b in bones:
    vg = fig.vertex_groups.new(name=b.name)
    vg.add([index[b.name]], 1.0, "REPLACE")

skin = fig.modifiers.new("skin", "SKIN")
skin.use_smooth_shade = True
for i, b in enumerate(bones):
    n = b.name.lower()
    r = 2.2  # cm
    if any(k in n for k in ("thumb", "index", "middle", "ring", "pinky")):
        r = 0.45
    elif "head" in n and "end" not in n:
        r = 6.0
    elif any(k in n for k in ("eye", "jaw", "end")):
        r = 0.8
    elif any(k in n for k in ("spine", "chest", "hips")):
        r = 5.0
    mesh.skin_vertices[0].data[i].radius = (r, r)
mesh.skin_vertices[0].data[0].use_root = True
fig.modifiers.new("subd", "SUBSURF").levels = 1
fig.modifiers.new("arm", "ARMATURE").object = arm

def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1.0)
    return m

m_l, m_r, m_c = mat("left", (0.18, 0.44, 0.84)), mat("right", (0.84, 0.23, 0.18)), mat("centre", (0.75, 0.75, 0.72))
for m in (m_l, m_r, m_c):
    fig.data.materials.append(m)
# material per face is assigned after the skin is applied; workbench uses OBJECT colour instead:
fig.color = (0.8, 0.8, 0.78, 1.0)

# split colours: duplicate figure into three objects masked by vertex group side (simple and robust)
def side(name):
    n = name.lower()
    return "l" if n.startswith("left") else "r" if n.startswith("right") else "c"

for tag, rgb in (("l", (0.18, 0.44, 0.84)), ("r", (0.84, 0.23, 0.18)), ("c", (0.78, 0.78, 0.75))):
    o = fig.copy()
    o.data = fig.data
    o.name = f"figure_{tag}"
    scene.collection.objects.link(o)
    grp = o.vertex_groups.new(name=f"mask_{tag}")
    ids = [index[b.name] for b in bones if side(b.name) == tag or
           (b.parent is not None and side(b.name) == "c" and False)]
    grp.add(ids, 1.0, "REPLACE")
    mask = o.modifiers.new("mask", "MASK")
    mask.vertex_group = grp.name
    o.modifiers.move(len(o.modifiers) - 1, 0)
    o.color = (*rgb, 1.0)
fig.hide_render = True
fig.hide_viewport = True

# ---------------------------------------------------------------- floor
bpy.ops.mesh.primitive_grid_add(x_subdivisions=60, y_subdivisions=60, size=6000)
floor = bpy.context.active_object
floor.color = (0.42, 0.42, 0.40, 1.0)
wire = floor.modifiers.new("wire", "WIREFRAME")
wire.thickness = 1.2
wire.use_replace = False

# ---------------------------------------------------------------- camera following the hips
hips = arm.pose.bones[0]
target = bpy.data.objects.new("target", None)
scene.collection.objects.link(target)
c = target.constraints.new("COPY_LOCATION")
c.target, c.subtarget = arm, hips.name
c.use_z = False
target.location.z = 90.0

cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 35
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
cl = cam.constraints.new("CHILD_OF")
cl.target = target
cl.use_rotation_x = cl.use_rotation_y = cl.use_rotation_z = False
cam.location = Vector((260.0, -330.0, 60.0))  # 3/4 view, cm
tt = cam.constraints.new("TRACK_TO")
tt.target = target
tt.track_axis, tt.up_axis = "TRACK_NEGATIVE_Z", "UP_Y"
scene.camera = cam
cam_data.clip_end = 20000

# ---------------------------------------------------------------- render settings
scene.render.engine = "BLENDER_WORKBENCH"
shading = scene.display.shading
shading.light = "STUDIO"
shading.color_type = "OBJECT"
shading.show_shadows = True
shading.show_cavity = True
scene.world = bpy.data.worlds.new("w")
scene.world.color = (0.93, 0.93, 0.91)
scene.render.resolution_x, scene.render.resolution_y = W, H
scene.render.resolution_percentage = 100
# PNG frames (Blender 5.x reorganised movie output); dst is a folder, encode with ffmpeg afterwards
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = dst.rstrip("/\\") + "/f_"
bpy.ops.render.render(animation=True)
print(f"[v2m] rendered {dst} frames {f0}-{f1}")
