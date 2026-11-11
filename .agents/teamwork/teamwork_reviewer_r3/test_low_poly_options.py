import bpy
import bmesh
import math
import sys
sys.path.append(".agents/teamwork/teamwork_reviewer_r3")
import test_pipeline

# Build high poly
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

bev = arch.modifiers.new("Bevel", "BEVEL")
bev.width = 0.015
bev.segments = 2
bev.limit_method = "ANGLE"
bev.angle_limit = math.radians(40.0)
bpy.ops.object.modifier_apply(modifier=bev.name)

# Displace
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

# High poly is ready. Now let's test decimation and UV unwrapping
def test_low_poly_unwrap(name, target_tris, unwrap_fn):
    low = arch.copy()
    low.data = arch.data.copy()
    bpy.context.collection.objects.link(low)
    bpy.ops.object.select_all(action="DESELECT")
    low.select_set(True)
    bpy.context.view_layer.objects.active = low

    current_tris = sum(len(p.vertices) - 2 for p in low.data.polygons)
    if current_tris > target_tris:
        dec = low.modifiers.new("Decimate", "DECIMATE")
        dec.decimate_type = "COLLAPSE"
        dec.ratio = float(target_tris) / float(current_tris)
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier=dec.name)

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(2.0))
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")

    # Run unwrap function
    unwrap_fn()
    bpy.ops.uv.pack_islands(margin=0.015)

    # Check overlaps
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_overlap()
    bpy.ops.object.mode_set(mode="OBJECT")

    bm = bmesh.new()
    bm.from_mesh(low.data)
    sel = [f for f in bm.faces if f.select]
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    uv_lay = bm.loops.layers.uv.active
    u_coords = [l[uv_lay].uv.x for f in bm.faces for l in f.loops]
    v_coords = [l[uv_lay].uv.y for f in bm.faces for l in f.loops]
    print(f"[{name}] Tris: {tris}, Overlapping faces: {len(sel)}, U: [{min(u_coords):.4f}, {max(u_coords):.4f}], V: [{min(v_coords):.4f}, {max(v_coords):.4f}]")
    bm.free()
    bpy.data.objects.remove(low, do_unlink=True)

# Test various strategies
def smart(angle):
    return lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=0.015)

def sharp_unwrap(angle, method="ANGLE_BASED"):
    def fn():
        bpy.ops.mesh.select_mode(type="EDGE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.mesh.edges_select_sharp(sharpness=math.radians(angle))
        bpy.ops.mesh.mark_seam(clear=False)
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.unwrap(method=method, margin=0.015)
    return fn

for tris in [1400, 1600, 1800]:
    for a in [25, 30, 35, 40, 45, 50, 66]:
        test_low_poly_unwrap(f"tris{tris}_smart{a}", tris, smart(a))
    for a in [25, 30, 35, 40]:
        test_low_poly_unwrap(f"tris{tris}_sharp{a}", tris, sharp_unwrap(a))
