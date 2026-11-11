import bpy
import bmesh
import math
import sys

def test_unwraps_on_existing():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath="props/gothic_arch/gothic_arch.glb")
    obj = bpy.context.scene.objects[0]

    def test_method(name, func):
        me = obj.data.copy()
        t_obj = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(t_obj)
        bpy.ops.object.select_all(action="DESELECT")
        t_obj.select_set(True)
        bpy.context.view_layer.objects.active = t_obj

        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.mark_seam(clear=True)
        func()
        bpy.ops.uv.pack_islands(margin=0.015)

        # Check overlap
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_overlap()
        bpy.ops.object.mode_set(mode="OBJECT")

        bm = bmesh.new()
        bm.from_mesh(t_obj.data)
        ov = len([f for f in bm.faces if f.select])

        # Exact 2D overlap check
        uv_lay = bm.loops.layers.uv.active
        # Also check bounds
        u_coords = [l[uv_lay].uv.x for f in bm.faces for l in f.loops]
        v_coords = [l[uv_lay].uv.y for f in bm.faces for l in f.loops]
        u_min, u_max = min(u_coords), max(u_coords)
        v_min, v_max = min(v_coords), max(v_coords)

        print(f"[{name}] Blender overlap count: {ov}, U=[{u_min:.4f}, {u_max:.4f}], V=[{v_min:.4f}, {v_max:.4f}]")
        bm.free()
        bpy.data.objects.remove(t_obj, do_unlink=True)
        bpy.data.meshes.remove(me, do_unlink=True)

    # 1. Smart project with various angles and margins
    for angle in [20, 25, 30, 35, 40, 45, 50, 60, 66]:
        test_method(f"smart_{angle}", lambda a=angle: bpy.ops.uv.smart_project(angle_limit=math.radians(a), island_margin=0.015))

    # 2. Seams by sharpness + unwrap
    for sharp in [20, 25, 30, 35, 40, 45, 50]:
        def unwrap_sharp(s=sharp):
            bpy.ops.mesh.select_mode(type="EDGE")
            bpy.ops.mesh.select_all(action="DESELECT")
            bpy.ops.mesh.edges_select_sharp(sharpness=math.radians(s))
            bpy.ops.mesh.mark_seam(clear=False)
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.unwrap(method="CONFORMAL", margin=0.015)
        test_method(f"conformal_sharp_{sharp}", unwrap_sharp)

    # 3. Lightmap pack
    test_method("lightmap_pack", lambda: bpy.ops.uv.lightmap_pack(PREF_MARGIN=0.015))

test_unwraps_on_existing()
