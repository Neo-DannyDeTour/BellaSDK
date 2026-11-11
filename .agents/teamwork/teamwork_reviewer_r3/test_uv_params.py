import bpy
import bmesh
import math
import sys
sys.path.append(".agents/teamwork/teamwork_reviewer_r3")
from test_pipeline import *

test_pipeline()
low = [obj for obj in bpy.context.scene.objects if "HighPoly" in obj.name and obj != bpy.context.scene.objects["Arch_HighPoly"]][0]

def count_overlaps(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_overlap()
    bpy.ops.object.mode_set(mode="OBJECT")
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    sel = [f.index for f in bm.faces if f.select]
    bm.free()
    return len(sel)

# Test various methods
methods = [
    ("smart_20", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(20.0), island_margin=0.015)),
    ("smart_25", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(25.0), island_margin=0.015)),
    ("smart_30", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(30.0), island_margin=0.015)),
    ("smart_35", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(35.0), island_margin=0.015)),
    ("smart_40", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(40.0), island_margin=0.015)),
    ("smart_25_area", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(25.0), island_margin=0.015, area_weight=0.5)),
    ("smart_20_area", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(20.0), island_margin=0.015, area_weight=0.5)),
    ("smart_15", lambda: bpy.ops.uv.smart_project(angle_limit=math.radians(15.0), island_margin=0.015)),
]

for name, fn in methods:
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    fn()
    bpy.ops.uv.pack_islands(margin=0.015)
    bpy.ops.object.mode_set(mode="OBJECT")
    ov = count_overlaps(low)
    print(f"Method {name}: overlaps = {ov}")
