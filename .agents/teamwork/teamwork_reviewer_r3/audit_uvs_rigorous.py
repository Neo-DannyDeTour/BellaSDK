import sys
import bpy
import bmesh

def audit_uvs_rigorous(glb_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    obj = bpy.context.scene.objects[0]
    me = obj.data

    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    uv_lay = bm.loops.layers.uv.active
    assert uv_lay is not None, "No active UV layer!"

    u_coords = []
    v_coords = []
    zero_area_faces = 0

    for f in bm.faces:
        uvs = [l[uv_lay].uv for l in f.loops]
        for uv in uvs:
            u_coords.append(uv.x)
            v_coords.append(uv.y)
        area = 0.0
        n = len(uvs)
        for i in range(n):
            j = (i + 1) % n
            area += uvs[i].x * uvs[j].y - uvs[j].x * uvs[i].y
        area = abs(area) * 0.5
        if area < 1e-12:
            zero_area_faces += 1

    u_min, u_max = min(u_coords), max(u_coords)
    v_min, v_max = min(v_coords), max(v_coords)
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    print(f"RIGOROUS UV AUDIT for {glb_path}:")
    print(f"  Faces: {len(bm.faces)}, Triangles: {tris}")
    print(f"  U range: [{u_min:.5f}, {u_max:.5f}]")
    print(f"  V range: [{v_min:.5f}, {v_max:.5f}]")
    print(f"  Zero-area UV faces: {zero_area_faces}")

    assert u_min >= 0.0 and u_max <= 1.0, f"UV out of bounds: U in [{u_min}, {u_max}]"
    assert v_min >= 0.0 and v_max <= 1.0, f"UV out of bounds: V in [{v_min}, {v_max}]"
    assert zero_area_faces == 0, f"Found {zero_area_faces} zero-area UV faces!"

    # 1. Blender native overlap check:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_overlap()
    bpy.ops.object.mode_set(mode="OBJECT")
    bm_edit = bmesh.new()
    bm_edit.from_mesh(obj.data)
    overlapping_faces = [f.index for f in bm_edit.faces if f.select]
    print(f"  Blender uv.select_overlap() count: {len(overlapping_faces)}")
    assert len(overlapping_faces) == 0, f"Blender detected {len(overlapping_faces)} overlapping UV faces!"

    # 2. Exact 2D SAT triangle intersection check across all triangle pairs:
    def cross2d(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    def seg_intersect(p1, p2, p3, p4):
        d1 = cross2d(p3, p4, p1)
        d2 = cross2d(p3, p4, p2)
        d3 = cross2d(p1, p2, p3)
        d4 = cross2d(p1, p2, p4)
        if ((d1 > 1e-7 and d2 < -1e-7) or (d1 < -1e-7 and d2 > 1e-7)) and \
           ((d3 > 1e-7 and d4 < -1e-7) or (d3 < -1e-7 and d4 > 1e-7)):
            return True
        return False

    def pt_in_tri(p, a, b, c):
        c1 = cross2d(a, b, p)
        c2 = cross2d(b, c, p)
        c3 = cross2d(c, a, p)
        return (c1 > 1e-7 and c2 > 1e-7 and c3 > 1e-7) or (c1 < -1e-7 and c2 < -1e-7 and c3 < -1e-7)

    def tri_overlap(t1, t2):
        for i in range(3):
            for j in range(3):
                if seg_intersect(t1[i], t1[(i+1)%3], t2[j], t2[(j+1)%3]):
                    return True
        for i in range(3):
            if pt_in_tri(t1[i], t2[0], t2[1], t2[2]):
                return True
            if pt_in_tri(t2[i], t1[0], t1[1], t1[2]):
                return True
        return False

    all_faces = list(bm.faces)
    all_overlaps = []
    for i in range(len(all_faces)):
        f1 = all_faces[i]
        t1 = [(l[uv_lay].uv.x, l[uv_lay].uv.y) for l in f1.loops]
        min_x1, max_x1 = min(p[0] for p in t1), max(p[0] for p in t1)
        min_y1, max_y1 = min(p[1] for p in t1), max(p[1] for p in t1)
        for j in range(i + 1, len(all_faces)):
            f2 = all_faces[j]
            t2 = [(l[uv_lay].uv.x, l[uv_lay].uv.y) for l in f2.loops]
            min_x2, max_x2 = min(p[0] for p in t2), max(p[0] for p in t2)
            min_y2, max_y2 = min(p[1] for p in t2), max(p[1] for p in t2)
            if max_x1 < min_x2 or min_x1 > max_x2 or max_y1 < min_y2 or min_y1 > max_y2:
                continue
            if tri_overlap(t1, t2):
                all_overlaps.append((f1.index, f2.index))

    print(f"  Exact 2D SAT triangle overlap pairs: {len(all_overlaps)}")
    assert len(all_overlaps) == 0, f"Found {len(all_overlaps)} overlapping triangle pairs!"

    print("  PASS: UV layout is 100% non-overlapping and bounded within [0, 1]!")
    bm_edit.free()
    bm.free()

if __name__ == "__main__":
    audit_uvs_rigorous(sys.argv[-1])
