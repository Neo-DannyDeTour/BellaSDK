import bpy
import bmesh
import math
import sys
sys.path.append(".agents/teamwork/teamwork_reviewer_r3")
import test_pipeline

arch = test_pipeline.test_pipeline()

bm = bmesh.new()
bm.from_mesh(arch.data)
bm.faces.ensure_lookup_table()

print(f"Total faces: {len(bm.faces)}")
# Check all faces for inverted normals or strange orientation
# Recalculate face normals and see if any face changes direction!
normals_before = [f.normal.copy() for f in bm.faces]
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
flipped = []
for i, f in enumerate(bm.faces):
    if f.normal.dot(normals_before[i]) < 0.5:
        flipped.append((i, bm.faces[i].calc_center_median(), normals_before[i], f.normal))
print(f"Faces that were flipped by recalc_face_normals: {len(flipped)}")
for fl in flipped[:10]:
    print(f"  Face {fl[0]} at {fl[1]}: before={fl[2]}, after={fl[3]}")
bm.free()
