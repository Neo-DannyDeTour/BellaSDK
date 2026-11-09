import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

# Reset scene
bpy.ops.wm.read_factory_settings(use_empty=True)

# 1. Generate Procedural 512x512 Texture (3 UV Zones: 0-0.45 Panel, 0.45-0.85 Batten, 0.85-1.0 Metal)
IMG_SIZE = 512
img = bpy.data.images.new("CrateAlbedo", width=IMG_SIZE, height=IMG_SIZE, alpha=False)
pixels = [0.0] * (IMG_SIZE * IMG_SIZE * 4)


def hash2d(x, y):
    n = math.sin(x * 12.9898 + y * 78.233) * 43758.5453
    return n - math.floor(n)


for y in range(IMG_SIZE):
    v = y / IMG_SIZE
    for x in range(IMG_SIZE):
        u = x / IMG_SIZE
        idx = (y * IMG_SIZE + x) * 4
        grain = hash2d(int(u * 64), int(v * 8)) * 0.08 + hash2d(x, y) * 0.04
        edge_dirt = (1.0 - math.sin(v * math.pi)) * 0.08
        if u < 0.45:
            # Dark dirty plywood
            r, g, b = (
                0.28 - edge_dirt + grain,
                0.22 - edge_dirt + grain,
                0.14 - edge_dirt + grain * 0.5,
            )
        elif u < 0.85:
            # Lighter wood battens
            r, g, b = (
                0.44 - edge_dirt + grain,
                0.36 - edge_dirt + grain,
                0.23 - edge_dirt + grain * 0.5,
            )
        else:
            # Dark iron corner brackets
            r, g, b = 0.16 + grain * 0.5, 0.16 + grain * 0.5, 0.15 + grain * 0.5
        pixels[idx] = max(0.0, min(1.0, r))
        pixels[idx + 1] = max(0.0, min(1.0, g))
        pixels[idx + 2] = max(0.0, min(1.0, b))
        pixels[idx + 3] = 1.0

img.pixels = pixels
img.pack()

# Material setup
mat = bpy.data.materials.new(name="CrateMaterial")
mat.use_nodes = True
nodes = mat.node_tree.nodes
links = mat.node_tree.links
bsdf = nodes.get("Principled BSDF")
bsdf.inputs["Roughness"].default_value = 0.85

tex_node = nodes.new("ShaderNodeTexImage")
tex_node.image = img
links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])


def add_box_to_bm(bm, center, size, uv_zone):
    bmesh.ops.create_cube(
        bm,
        size=1.0,
        matrix=Matrix.Translation(center) @ Matrix.Diagonal(size).to_4x4(),
    )
    uv_layer = bm.loops.layers.uv.verify()
    u_min, u_max = uv_zone
    for face in bm.faces:
        if all(loop[uv_layer].uv.length_squared == 0.0 for loop in face.loops):
            for i, loop in enumerate(face.loops):
                u = u_min if i in (0, 3) else u_max
                v = 0.0 if i in (0, 1) else 1.0
                loop[uv_layer].uv = (u, v)


def build_mesh_obj(name, boxes, collection):
    bm = bmesh.new()
    bm.loops.layers.uv.verify()
    avg_center = sum((Vector(b[0]) for b in boxes), Vector((0, 0, 0))) / len(boxes)
    for center, size, zone in boxes:
        local_c = Vector(center) - avg_center
        add_box_to_bm(bm, local_c, Vector(size), zone)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)

    obj = bpy.data.objects.new(name, mesh)
    obj.location = avg_center
    collection.objects.link(obj)
    return obj, boxes


# Zones
Z_PANEL = (0.02, 0.43)
Z_BATTEN = (0.47, 0.83)
Z_METAL = (0.87, 0.98)

# Dimensions: Crate sits on Z=[0..1.05], X=[-0.5..0.5], Y=[-0.5..0.5]
# Skids: Z=[0..0.05] (height 0.05)
# Main box: Z=[0.05..1.05] (center Z=0.55)
chunks = {}

# 6 Inner Recessed Panels
chunks["Debris_Panel_Front"] = [((0.0, -0.45, 0.55), (0.88, 0.02, 0.88), Z_PANEL)]
chunks["Debris_Panel_Back"] = [((0.0, 0.45, 0.55), (0.88, 0.02, 0.88), Z_PANEL)]
chunks["Debris_Panel_Left"] = [((-0.45, 0.0, 0.55), (0.02, 0.88, 0.88), Z_PANEL)]
chunks["Debris_Panel_Right"] = [((0.45, 0.0, 0.55), (0.02, 0.88, 0.88), Z_PANEL)]
chunks["Debris_Panel_Bottom"] = [((0.0, 0.0, 0.09), (0.88, 0.88, 0.02), Z_PANEL)]
chunks["Debris_Panel_Top"] = [((0.0, 0.0, 1.01), (0.88, 0.88, 0.02), Z_PANEL)]

# 4 Structural Frame & Skid Clusters
chunks["Debris_Frame_Front"] = [
    ((0.0, -0.48, 1.01), (1.0, 0.04, 0.08), Z_BATTEN),
    ((0.0, -0.48, 0.09), (1.0, 0.04, 0.08), Z_BATTEN),
    ((-0.46, -0.48, 0.55), (0.08, 0.04, 0.84), Z_BATTEN),
    ((0.46, -0.48, 0.55), (0.08, 0.04, 0.84), Z_BATTEN),
    ((0.0, -0.475, 0.55), (0.07, 0.03, 0.84), Z_BATTEN),
    ((-0.485, -0.485, 0.99), (0.05, 0.05, 0.05), Z_METAL),
    ((0.485, -0.485, 0.99), (0.05, 0.05, 0.05), Z_METAL),
]

chunks["Debris_Frame_Back"] = [
    ((0.0, 0.48, 1.01), (1.0, 0.04, 0.08), Z_BATTEN),
    ((0.0, 0.48, 0.09), (1.0, 0.04, 0.08), Z_BATTEN),
    ((-0.46, 0.48, 0.55), (0.08, 0.04, 0.84), Z_BATTEN),
    ((0.46, 0.48, 0.55), (0.08, 0.04, 0.84), Z_BATTEN),
    ((0.0, 0.475, 0.55), (0.07, 0.03, 0.84), Z_BATTEN),
    ((-0.485, 0.485, 0.99), (0.05, 0.05, 0.05), Z_METAL),
    ((0.485, 0.485, 0.99), (0.05, 0.05, 0.05), Z_METAL),
]

chunks["Debris_Frame_Sides_Top"] = [
    ((-0.48, 0.0, 1.01), (0.04, 0.84, 0.08), Z_BATTEN),
    ((-0.48, 0.0, 0.09), (0.04, 0.84, 0.08), Z_BATTEN),
    ((-0.475, 0.0, 0.55), (0.03, 0.07, 0.84), Z_BATTEN),
    ((0.48, 0.0, 1.01), (0.04, 0.84, 0.08), Z_BATTEN),
    ((0.48, 0.0, 0.09), (0.04, 0.84, 0.08), Z_BATTEN),
    ((0.475, 0.0, 0.55), (0.03, 0.07, 0.84), Z_BATTEN),
    ((-0.46, 0.0, 1.035), (0.08, 0.92, 0.03), Z_BATTEN),
    ((0.46, 0.0, 1.035), (0.08, 0.92, 0.03), Z_BATTEN),
    ((0.0, 0.0, 1.035), (0.08, 0.92, 0.03), Z_BATTEN),
]

chunks["Debris_Skids_Base"] = [
    ((-0.44, 0.0, 0.025), (0.10, 1.0, 0.05), Z_BATTEN),
    ((0.0, 0.0, 0.025), (0.10, 1.0, 0.05), Z_BATTEN),
    ((0.44, 0.0, 0.025), (0.10, 1.0, 0.05), Z_BATTEN),
]

scene_col = bpy.context.scene.collection

debris_root = bpy.data.objects.new("Crate_Debris", None)
scene_col.objects.link(debris_root)

all_boxes = []
for chunk_name, box_list in chunks.items():
    obj, _ = build_mesh_obj(chunk_name, box_list, scene_col)
    obj.parent = debris_root
    all_boxes.extend(box_list)

bm_intact = bmesh.new()
bm_intact.loops.layers.uv.verify()
for center, size, zone in all_boxes:
    add_box_to_bm(bm_intact, Vector(center), Vector(size), zone)

mesh_intact = bpy.data.meshes.new("Crate_Intact")
bm_intact.to_mesh(mesh_intact)
bm_intact.free()
mesh_intact.materials.append(mat)
obj_intact = bpy.data.objects.new("Crate_Intact", mesh_intact)
scene_col.objects.link(obj_intact)

# Export GLB to assets/props/crates/wooden_crate.glb
out_dir = os.path.join(os.getcwd(), "assets", "props", "crates")
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "wooden_crate.glb")

bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format="GLB",
    export_apply=True,
    export_yup=True,
    export_materials="EXPORT",
)
print(f"Exported crate to: {out_path}")

# Also copy/export to current dir if requested directly as fallback
root_out_path = os.path.join(os.getcwd(), "wooden_crate.glb")
if out_path != root_out_path:
    import shutil
    shutil.copyfile(out_path, root_out_path)
