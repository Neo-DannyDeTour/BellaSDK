import bpy
import bmesh
import math
import os

# Test generating high poly and building low poly with various UV unwrap strategies
exec(open("props/gothic_arch/generate_high_poly.py").read())

# Check the generated raw_arch.glb
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="props/gothic_arch/raw_arch.glb")
obj = bpy.context.scene.objects[0]
print("Imported raw_arch:", obj.name)

# Now test unwrapping methods
def test_unwrap_method(obj, method_name):
    me = obj.data.copy()
    test_obj = bpy.data.objects.new("Test", me)
    bpy.context.collection.objects.link(test_obj)
    bpy.ops.object.select_all(action="DESELECT")
    test_obj.select_set(True)
    bpy.context.view_layer.objects.active = test_obj

    # Decimate to 1400
    dec = test_obj.modifiers.new("Dec", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = 1400.0 / sum(len(p.vertices) - 2 for p in test_obj.data.polygons)
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="Dec")

    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(2.0))
    bpy.ops.mesh.quads_convert_to_tris(quad_method="BEAUTY", ngon_method="BEAUTY")

    # Try unwrap
    if method_name == "current":
        bpy.ops.mesh.select_mode(type="EDGE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.mesh.edges_select_sharp(sharpness=math.radians(50.0))
        bpy.ops.mesh.mark_seam(clear=False)
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.01)
        bpy.ops.uv.pack_islands(margin=0.01)
    elif method_name == "smart_project_35":
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(35.0), island_margin=0.015)
        bpy.ops.uv.pack_islands(margin=0.015)
    elif method_name == "smart_project_45":
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(45.0), island_margin=0.015)
        bpy.ops.uv.pack_islands(margin=0.015)
    elif method_name == "smart_project_66":
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
        bpy.ops.uv.pack_islands(margin=0.015)

    bpy.ops.object.mode_set(mode="OBJECT")

    # Check overlap
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_overlap()
    bpy.ops.object.mode_set(mode="OBJECT")
    bm = bmesh.new()
    bm.from_mesh(test_obj.data)
    overlapping = [f.index for f in bm.faces if f.select]

    uv_lay = bm.loops.layers.uv.active
    u_coords = [l[uv_lay].uv.x for f in bm.faces for l in f.loops]
    v_coords = [l[uv_lay].uv.y for f in bm.faces for l in f.loops]

    print(f"Method {method_name}: overlapping faces = {len(overlapping)}, U=[{min(u_coords):.4f}, {max(u_coords):.4f}], V=[{min(v_coords):.4f}, {max(v_coords):.4f}]")
    bm.free()
    bpy.data.objects.remove(test_obj, do_unlink=True)
    bpy.data.meshes.remove(me, do_unlink=True)

test_unwrap_method(obj, "current")
test_unwrap_method(obj, "smart_project_35")
test_unwrap_method(obj, "smart_project_45")
test_unwrap_method(obj, "smart_project_66")
