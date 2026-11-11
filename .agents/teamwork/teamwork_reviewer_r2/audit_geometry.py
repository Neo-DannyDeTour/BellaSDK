import sys
import bpy
import bmesh

def audit_mesh(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert len(meshes) == 1, f"Expected 1 mesh, got {len(meshes)}"
    obj = meshes[0]
    me = obj.data

    bm = bmesh.new()
    bm.from_mesh(me)
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()

    # 1. Non-manifold and boundary edges
    non_manifold_edges = [e for e in bm.edges if not e.is_manifold]
    boundary_edges = [e for e in bm.edges if e.is_boundary]
    wire_edges = [e for e in bm.edges if e.is_wire]

    # 2. Island count
    visited = set()
    islands = 0
    for v in bm.verts:
        if v not in visited:
            islands += 1
            queue = [v]
            visited.add(v)
            while queue:
                curr = queue.pop()
                for edge in curr.link_edges:
                    other = edge.other_vert(curr)
                    if other not in visited:
                        visited.add(other)
                        queue.append(other)

    # 3. Check for inverted normals (using face normals dot product with outward ray or volume)
    # For a closed manifold solid, volume should be positive
    # bmesh calc_volume:
    vol = 0.0
    # calculate signed volume of mesh: sum of det(v1, v2, v3)/6 for triangles
    bm.faces.ensure_lookup_table()
    tri_mesh = bm.copy()
    bmesh.ops.triangulate(tri_mesh, faces=tri_mesh.faces)
    tri_mesh.faces.ensure_lookup_table()
    signed_vol = 0.0
    for f in tri_mesh.faces:
        v1, v2, v3 = [v.co for v in f.verts]
        # signed volume of tetrahedron with origin
        signed_vol += v1.dot(v2.cross(v3)) / 6.0
    tri_mesh.free()

    # 4. Dimensions and bounding box
    bbox_min = [min(v.co[i] for v in bm.verts) for i in range(3)]
    bbox_max = [max(v.co[i] for v in bm.verts) for i in range(3)]
    dims = [bbox_max[i] - bbox_min[i] for i in range(3)]

    # 5. Pillar vs Vault connectivity
    # Check if there is a path through mesh edges from bottom of left pillar (X < -1.0, Z < 0.5)
    # to vault keystone (abs(X) < 0.2, Z > 3.4) and to bottom of right pillar (X > 1.0, Z < 0.5)
    left_verts = [v for v in bm.verts if v.co.x < -1.0 and v.co.z < 0.5]
    right_verts = [v for v in bm.verts if v.co.x > 1.0 and v.co.z < 0.5]
    top_verts = [v for v in bm.verts if abs(v.co.x) < 0.2 and v.co.z > 3.4]

    print(f"AUDIT RESULT for {path}:")
    print(f"  Verts: {len(bm.verts)}, Edges: {len(bm.edges)}, Faces: {len(bm.faces)}")
    print(f"  Non-manifold edges: {len(non_manifold_edges)}")
    print(f"  Boundary edges: {len(boundary_edges)}")
    print(f"  Wire edges: {len(wire_edges)}")
    print(f"  Connected components (islands): {islands}")
    print(f"  Signed volume: {signed_vol:.4f} m^3")
    print(f"  BBox min: {bbox_min}")
    print(f"  BBox max: {bbox_max}")
    print(f"  Dims: {dims}")
    print(f"  Left pillar base verts: {len(left_verts)}")
    print(f"  Right pillar base verts: {len(right_verts)}")
    print(f"  Top keystone verts: {len(top_verts)}")

    assert len(non_manifold_edges) == 0, f"Found {len(non_manifold_edges)} non-manifold edges!"
    assert len(boundary_edges) == 0, f"Found {len(boundary_edges)} boundary edges!"
    assert islands == 1, f"Found {islands} separate components!"
    assert signed_vol > 0.1, f"Volume non-positive or too small: {signed_vol} (normals inverted?)"
    assert len(left_verts) > 0 and len(right_verts) > 0 and len(top_verts) > 0

    bm.free()
    print("  PASS: Geometry is unbroken, manifold, watertight solid with correct outward normals!")

if __name__ == "__main__":
    audit_mesh(sys.argv[-1])
