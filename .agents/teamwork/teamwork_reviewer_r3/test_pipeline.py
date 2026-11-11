import bpy
import bmesh
import math

def make_pointed_arch_cutter(name, half_w, apex_z, y_min, y_max, base_z):
    c_x = half_w * 0.667
    term1 = (half_w + c_x) ** 2 - c_x**2 + 2.8**2 - apex_z**2
    c_z = term1 / (2.0 * (2.8 - apex_z))
    radius = math.sqrt(c_x**2 + (apex_z - c_z) ** 2)

    pts = []
    pts.append((half_w, base_z))
    pts.append((-half_w, base_z))
    pts.append((-half_w, 2.8))

    ang_start = math.atan2(2.8 - c_z, -half_w - c_x)
    ang_end = math.atan2(apex_z - c_z, 0.0 - c_x)
    segs = 24
    for i in range(1, segs):
        t = i / float(segs)
        a = ang_start + t * (ang_end - ang_start)
        pts.append((c_x + radius * math.cos(a), c_z + radius * math.sin(a)))
    pts.append((0.0, apex_z))

    ang_r_start = math.atan2(apex_z - c_z, 0.0 - (-c_x))
    ang_r_end = math.atan2(2.8 - c_z, half_w - (-c_x))
    for i in range(1, segs):
        t = i / float(segs)
        a = ang_r_start + t * (ang_r_end - ang_r_start)
        pts.append((-c_x + radius * math.cos(a), c_z + radius * math.sin(a)))
    pts.append((half_w, 2.8))

    bm = bmesh.new()
    verts_front = [bm.verts.new((x, y_max, z)) for x, z in pts]
    verts_back = [bm.verts.new((x, y_min, z)) for x, z in pts]
    bm.faces.new(verts_front)
    bm.faces.new(reversed(verts_back))
    n = len(pts)
    for i in range(n):
        next_i = (i + 1) % n
        bm.faces.new([verts_front[i], verts_back[i], verts_back[next_i], verts_front[next_i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj

def test_pipeline():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # 1. Main block
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 2.0))
    arch = bpy.context.active_object
    arch.name = "Arch_HighPoly"
    arch.scale = (3.0, 0.8, 4.0)
    bpy.ops.object.transform_apply(scale=True, location=True)

    def union_part(part):
        bpy.context.view_layer.objects.active = arch
        arch.select_set(True)
        mod = arch.modifiers.new(name="Union", type="BOOLEAN")
        mod.operation = "UNION"
        mod.object = part
        mod.solver = "EXACT"
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(part, do_unlink=True)

    def diff_part(cutter):
        bpy.context.view_layer.objects.active = arch
        arch.select_set(True)
        mod = arch.modifiers.new(name="Diff", type="BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        mod.solver = "EXACT"
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter, do_unlink=True)

    # 2. Plinths
    for s in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(s * 1.2, 0.0, 0.2))
        p = bpy.context.active_object
        p.scale = (0.7, 0.9, 0.4)
        bpy.ops.object.transform_apply(scale=True, location=True)
        union_part(p)

    # 3. Capitals (Z: 2.45 to 2.75)
    for s in (-1.0, 1.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(s * 1.2, 0.0, 2.60))
        c = bpy.context.active_object
        c.scale = (0.70, 0.92, 0.30)
        bpy.ops.object.transform_apply(scale=True, location=True)
        union_part(c)

    # 4. Column shafts (Z: 0.35 to 2.45, depth = 2.1, center = 1.40)
    for s in (-1.0, 1.0):
        for y_off in (-0.37, 0.37):
            bpy.ops.mesh.primitive_cylinder_add(
                radius=0.08, depth=2.1, vertices=16, location=(s * 1.2, y_off, 1.40)
            )
            sh = bpy.context.active_object
            bpy.ops.object.transform_apply(scale=True, location=True)
            union_part(sh)

    # 5. Cutters: inner doorway all the way down, archivolts only above capitals (Z >= 2.75)
    c_inner = make_pointed_arch_cutter("CutterInner", 0.90, 3.55, -0.50, 0.50, -0.1)
    c_front = make_pointed_arch_cutter("CutterFront", 0.96, 3.62, 0.28, 0.50, 2.75)
    c_back = make_pointed_arch_cutter("CutterBack", 0.96, 3.62, -0.50, -0.28, 2.75)

    diff_part(c_inner)
    diff_part(c_front)
    diff_part(c_back)

    # 6. Keystone at vault apex (Z: 3.55 to 3.85) - added AFTER cutters
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, 3.70))
    ks = bpy.context.active_object
    ks.scale = (0.36, 0.92, 0.30)
    bpy.ops.object.transform_apply(scale=True, location=True)
    union_part(ks)

    # 7. Bevel
    bpy.context.view_layer.objects.active = arch
    arch.select_set(True)
    bev = arch.modifiers.new("Bevel", "BEVEL")
    bev.width = 0.015
    bev.segments = 2
    bev.limit_method = "ANGLE"
    bev.angle_limit = math.radians(40.0)
    bpy.ops.object.modifier_apply(modifier=bev.name)

    # 8. Subdivision Surface (SIMPLE)
    sub = arch.modifiers.new("Subdiv", "SUBSURF")
    sub.subdivision_type = "SIMPLE"
    sub.levels = 1
    sub.render_levels = 1
    bpy.ops.object.modifier_apply(modifier=sub.name)

    # 9. Displace (excluding bottom floor Z <= 0.01)
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

    bpy.ops.object.shade_smooth()

    return arch
