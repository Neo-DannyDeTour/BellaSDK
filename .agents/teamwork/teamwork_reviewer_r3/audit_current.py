import sys
import bpy
import bmesh
import math

def audit_high_poly(glb_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    obj = bpy.context.scene.objects[0]
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()

    non_manifold_edges = [e for e in bm.edges if not e.is_manifold]
    boundary_edges = [e for e in bm.edges if e.is_boundary]
    wire_edges = [e for e in bm.edges if e.is_wire]

    # Check for inverted normals or negative face dot products with center vector or local orientation
    inverted_faces = []
    for f in bm.faces:
        if f.normal.length < 0.5:
            inverted_faces.append(f.index)

    print(f"HIGH POLY AUDIT ({glb_path}):")
    print(f"  Verts: {len(bm.verts)}, Faces: {len(bm.faces)}")
    print(f"  Non-manifold edges: {len(non_manifold_edges)}")
    print(f"  Boundary edges: {len(boundary_edges)}")
    print(f"  Wire edges: {len(wire_edges)}")
    print(f"  Degenerate normal faces: {len(inverted_faces)}")

    # Check opening dimensions:
    z2_verts = [v for v in bm.verts if abs(v.co.z - 2.0) < 0.1 and abs(v.co.y) < 0.3]
    inner_xs = [abs(v.co.x) for v in z2_verts if abs(v.co.x) < 1.0]
    if inner_xs:
        min_inner_x = min(inner_xs)
        print(f"  Opening half-width at Z=2.0: {min_inner_x:.3f}m (opening width = {2*min_inner_x:.3f}m)")

    bm.free()

def audit_low_poly(glb_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    obj = bpy.context.scene.objects[0]
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    uv_lay = bm.loops.layers.uv.active

    tris = sum(len(f.verts) - 2 for f in bm.faces)
    print(f"LOW POLY AUDIT ({glb_path}):")
    print(f"  Faces: {len(bm.faces)}, Triangles: {tris}")

    # Check UVs
    u_coords, v_coords = [], []
    zero_area_faces = 0
    tri_uvs = []

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
        if len(uvs) == 3:
            tri_uvs.append((f.index, [(uv.x, uv.y) for uv in uvs]))

    u_min, u_max = min(u_coords), max(u_coords)
    v_min, v_max = min(v_coords), max(v_coords)
    print(f"  U range: [{u_min:.5f}, {u_max:.5f}], V range: [{v_min:.5f}, {v_max:.5f}]")
    print(f"  Zero-area UV faces: {zero_area_faces}")

    # Blender native overlap check:
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
    bm_edit.free()
    bm.free()

if __name__ == "__main__":
    audit_high_poly("props/gothic_arch/raw_arch.glb")
    audit_low_poly("props/gothic_arch/gothic_arch.glb")
