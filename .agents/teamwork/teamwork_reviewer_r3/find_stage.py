import bpy
import bmesh
import math
import sys
sys.path.append(".agents/teamwork/teamwork_reviewer_r3")
import test_pipeline

def find_inverted(obj, msg):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    inv = []
    for f in bm.faces:
        c = f.calc_center_median()
        if -0.92 < c.x < -0.88 and -0.4 < c.y < 0.4 and 0.4 < c.z < 2.7:
            if f.normal.x < 0.0:
                inv.append((f.index, c, f.normal))
    print(f"{msg}: {len(inv)} inverted faces")
    for item in inv:
        print("  ", item)
    bm.free()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 2.0))
arch = bpy.context.active_object
arch.scale = (3.0, 0.8, 4.0)
bpy.ops.object.transform_apply(scale=True, location=True)

def union_part(part):
    bpy.context.view_layer.objects.active = arch
    arch.select_set(True)
    mod = arch.modifiers.new(name="Union", type="BOOLEAN")
    mod.operation = "UNION"; mod.object = part; mod.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(part, do_unlink=True)

def diff_part(cutter):
    bpy.context.view_layer.objects.active = arch
    arch.select_set(True)
    mod = arch.modifiers.new(name="Diff", type="BOOLEAN")
    mod.operation = "DIFFERENCE"; mod.object = cutter; mod.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)

for s in (-1.0, 1.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(s * 1.2, 0.0, 0.2))
    p = bpy.context.active_object; p.scale = (0.7, 0.9, 0.4); bpy.ops.object.transform_apply(scale=True, location=True); union_part(p)
for s in (-1.0, 1.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(s * 1.2, 0.0, 2.60))
    c = bpy.context.active_object; c.scale = (0.70, 0.92, 0.30); bpy.ops.object.transform_apply(scale=True, location=True); union_part(c)
for s in (-1.0, 1.0):
    for y_off in (-0.37, 0.37):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=2.1, vertices=16, location=(s * 1.2, y_off, 1.40))
        sh = bpy.context.active_object; bpy.ops.object.transform_apply(scale=True, location=True); union_part(sh)

c_inner = test_pipeline.make_pointed_arch_cutter("CutterInner", 0.90, 3.55, -0.50, 0.50, -0.1)
c_front = test_pipeline.make_pointed_arch_cutter("CutterFront", 0.96, 3.62, 0.28, 0.50, 2.75)
c_back = test_pipeline.make_pointed_arch_cutter("CutterBack", 0.96, 3.62, -0.50, -0.28, 2.75)
diff_part(c_inner)
diff_part(c_front)
diff_part(c_back)

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 3.70))
ks = bpy.context.active_object
ks.scale = (0.36, 0.92, 0.30)
bpy.ops.object.transform_apply(scale=True, location=True)
union_part(ks)

find_inverted(arch, "After cuts & keystone")

bev = arch.modifiers.new("Bevel", "BEVEL")
bev.width = 0.015
bev.segments = 2
bev.limit_method = "ANGLE"
bev.angle_limit = math.radians(40.0)
bpy.ops.object.modifier_apply(modifier=bev.name)

find_inverted(arch, "After Bevel")

sub = arch.modifiers.new("Subdiv", "SUBSURF")
sub.subdivision_type = "SIMPLE"
sub.levels = 1
bpy.ops.object.modifier_apply(modifier=sub.name)

find_inverted(arch, "After Subdiv")

vgroup = arch.vertex_groups.new(name="DisplaceGroup")
displace_indices = [v.index for v in arch.data.vertices if v.co.z > 0.01]
vgroup.add(displace_indices, 1.0, "REPLACE")
tex = bpy.data.textures.new("StoneNoise", type="CLOUDS")
tex.noise_scale = 0.15
disp = arch.modifiers.new("StoneRelief", type="DISPLACE")
disp.texture = tex
disp.vertex_group = "DisplaceGroup"
disp.strength = 0.005
bpy.ops.object.modifier_apply(modifier=disp.name)

find_inverted(arch, "After Displace")
