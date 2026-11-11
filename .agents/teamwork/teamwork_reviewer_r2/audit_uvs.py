import sys
import bpy
import bmesh

def audit_uvs(glb_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    obj = bpy.context.scene.objects[0]
    me = obj.data

    bm = bmesh.new()
    bm.from_mesh(me)
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
        # compute 2D polygon area of UV face
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
    print(f"UV AUDIT for {glb_path}:")
    print(f"  Faces: {len(bm.faces)}")
    print(f"  U range: [{u_min:.5f}, {u_max:.5f}]")
    print(f"  V range: [{v_min:.5f}, {v_max:.5f}]")
    print(f"  Zero-area UV faces: {zero_area_faces}")

    assert u_min >= -0.001 and u_max <= 1.001, f"UV out of bounds: U in [{u_min}, {u_max}]"
    assert v_min >= -0.001 and v_max <= 1.001, f"UV out of bounds: V in [{v_min}, {v_max}]"
    assert zero_area_faces == 0, f"Found {zero_area_faces} zero-area UV faces!"
    print("  PASS: UV layout is fully valid and contained within [0, 1] bounds!")
    bm.free()

if __name__ == "__main__":
    audit_uvs(sys.argv[-1])
