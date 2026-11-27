"""Generates scissor_gate.glb with a 'Collapsed' shape key.

Run headless: blender -b -P tools/generate_scissor_gate.py
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

# Gate specs (meters)
BAY_COUNT = 6
BAY_W_CLOSED = 0.22
BAY_W_OPEN = 0.035
HEIGHT = 2.2
BAR_W = 0.018
BAR_D = 0.024
SLAT_W = 0.014
SLAT_D = 0.006
SCISSOR_LEN = 0.28
ROW_CENTERS = [0.35, 0.65, 1.55, 1.85]
EXPORT_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "interactables", "scissor_gate", "scissor_gate.glb",
)

BOX_FACES = [
    (0, 1, 2, 3), (4, 7, 6, 5),
    (0, 4, 5, 1), (1, 5, 6, 2),
    (2, 6, 7, 3), (3, 7, 4, 0),
]


def box_corners(min_c, max_c):
    return [
        Vector((min_c.x, min_c.y, min_c.z)),
        Vector((max_c.x, min_c.y, min_c.z)),
        Vector((max_c.x, max_c.y, min_c.z)),
        Vector((min_c.x, max_c.y, min_c.z)),
        Vector((min_c.x, min_c.y, max_c.z)),
        Vector((max_c.x, min_c.y, max_c.z)),
        Vector((max_c.x, max_c.y, max_c.z)),
        Vector((min_c.x, max_c.y, max_c.z)),
    ]


def add_box(bm, v_closed, v_open, min_c, max_c, offset_open=Vector((0, 0, 0))):
    verts = box_corners(min_c, max_c)
    bm_verts = [bm.verts.new(v) for v in verts]
    for f in BOX_FACES:
        bm.faces.new([bm_verts[i] for i in f])
    for v in verts:
        v_closed.append(v.copy())
        v_open.append(v + offset_open)


def add_slat(bm, v_closed, v_open, p0_c, p1_c, p0_o, p1_o, y_off):
    def make_8(p0, p1):
        d = p1 - p0
        angle = math.atan2(d.z, d.x)
        length = d.length
        c = (p0 + p1) * 0.5
        rot = Matrix.Rotation(-angle, 4, 'Y')
        hw = length * 0.5 + 0.01
        hh = SLAT_W * 0.5
        hd = SLAT_D * 0.5
        local = box_corners(Vector((-hw, y_off - hd, -hh)), Vector((hw, y_off + hd, hh)))
        return [c + (rot @ v) for v in local]

    vc = make_8(p0_c, p1_c)
    vo = make_8(p0_o, p1_o)
    bm_verts = [bm.verts.new(v) for v in vc]
    for f in BOX_FACES:
        bm.faces.new([bm_verts[i] for i in f])
    v_closed.extend(vc)
    v_open.extend(vo)


def build_gate():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = bpy.data.meshes.new("ScissorGateMesh")
    obj = bpy.data.objects.new("ScissorGate", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    v_closed = []
    v_open = []

    total_w_closed = BAY_COUNT * BAY_W_CLOSED
    total_w_open = BAY_COUNT * BAY_W_OPEN

    # shortcut: uniform X compression on horizontal bars, upgrade to telescoping rails
    for z_min, z_max in [(0.0, BAR_W), (HEIGHT - BAR_W, HEIGHT)]:
        verts_c = box_corners(
            Vector((-total_w_closed, -BAR_D * 0.5, z_min)),
            Vector((0.0, BAR_D * 0.5, z_max)),
        )
        bm_verts = [bm.verts.new(v) for v in verts_c]
        for f in BOX_FACES:
            bm.faces.new([bm_verts[i] for i in f])
        for v in verts_c:
            v_closed.append(v.copy())
            ox = -total_w_open if v.x < -0.001 else 0.0
            v_open.append(Vector((ox, v.y, v.z)))

    # Vertical bars: preserve exact BAR_W thickness while translating X
    for i in range(BAY_COUNT + 1):
        xc = -i * BAY_W_CLOSED
        xo = -i * BAY_W_OPEN
        add_box(
            bm, v_closed, v_open,
            Vector((xc - BAR_W * 0.5, -BAR_D * 0.5, 0.0)),
            Vector((xc + BAR_W * 0.5, BAR_D * 0.5, HEIGHT)),
            Vector((xo - xc, 0.0, 0.0)),
        )

    # Scissor X-lattices: constant length L, dynamic Z height via Pythagoras
    dz_c = math.sqrt(max(0.001, SCISSOR_LEN ** 2 - BAY_W_CLOSED ** 2)) * 0.5
    dz_o = math.sqrt(max(0.001, SCISSOR_LEN ** 2 - BAY_W_OPEN ** 2)) * 0.5

    for i in range(BAY_COUNT):
        x0_c = -i * BAY_W_CLOSED
        x1_c = -(i + 1) * BAY_W_CLOSED
        x0_o = -i * BAY_W_OPEN
        x1_o = -(i + 1) * BAY_W_OPEN

        for zc in ROW_CENTERS:
            add_slat(
                bm, v_closed, v_open,
                Vector((x0_c, 0.0, zc - dz_c)), Vector((x1_c, 0.0, zc + dz_c)),
                Vector((x0_o, 0.0, zc - dz_o)), Vector((x1_o, 0.0, zc + dz_o)),
                SLAT_D * 0.6,
            )
            add_slat(
                bm, v_closed, v_open,
                Vector((x0_c, 0.0, zc + dz_c)), Vector((x1_c, 0.0, zc - dz_c)),
                Vector((x0_o, 0.0, zc + dz_o)), Vector((x1_o, 0.0, zc - dz_o)),
                -SLAT_D * 0.6,
            )

    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(name="ScissorGateMetal")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.12, 0.14, 0.13, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.85
        bsdf.inputs["Roughness"].default_value = 0.65
    mesh.materials.append(mat)

    sk_basis = obj.shape_key_add(name="Basis", from_mix=False)
    for idx, co in enumerate(v_closed):
        sk_basis.data[idx].co = co

    sk_open = obj.shape_key_add(name="Collapsed", from_mix=False)
    for idx, co in enumerate(v_open):
        sk_open.data[idx].co = co

    path = os.path.normpath(EXPORT_PATH)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_morph=True,
        export_yup=True,
    )
    print(f"Exported: {path}")


if __name__ == "__main__":
    build_gate()
