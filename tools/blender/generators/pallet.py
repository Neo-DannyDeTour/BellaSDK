"""Procedural weathered wooden pallet generator for BellaSDK (Godot 4.7).

Builds a 1.1 x 1.0 x 0.14 m stringer pallet: 7 top slats (3-1-3 pattern, jittered),
3 notched stringers, 3 bottom slats, 42 nail-head caps. Single joined mesh with
plank-local box UVs + float "Col" vertex color (R seed, G AO, B edge wear), plus a
"Pallet-colonly" box collider child. Exports GLB + asset_manifest.json.

Usage:
    python3 tools/blender/run.py pallet
"""

from __future__ import annotations

import json
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene  # noqa: E402

# --- CONFIG (meters, Blender Z-up) ---
SLUG = "pallet"
OUT_DIR = REPO_ROOT / "assets" / "models" / SLUG
TRI_BUDGET = 2000
SEED = 42

WIDTH = 1.10  # X: across top slats, stringer length
LENGTH = 1.00  # Y: along slats
HEIGHT = 0.14  # Z: total height

SLAT_THICK = 0.022
SLAT_WIDTH = 0.115
STRINGER_WIDTH = 0.045
STRINGER_HEIGHT = HEIGHT - SLAT_THICK * 2.0
BEVEL = 0.003

# Stringer forklift notches (4-way entry between bottom slats)
NOTCH_DEPTH = 0.035
FOOT_HALF = 0.075  # Half-width of stringer foot over each bottom slat

NAIL_R_BOT = 0.0055
NAIL_R_TOP = 0.0045
NAIL_DEPTH = 0.002
NAIL_PROUD = 0.0003  # Cap top above slat surface; avoids z-fight with slat top face
NAIL_X_OFF = 0.026

TOP_SLAT_X = [-0.48, -0.355, -0.23, 0.0, 0.23, 0.355, 0.48]
STRINGER_Y = [-0.44, 0.0, 0.44]
BOT_SLAT_X = [-0.48, 0.0, 0.48]

MAT_NAME = "M_Pallet_Weathered"


# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------
def _bevel_new(bm: bmesh.types.BMesh, before: set) -> None:
    """Chamfer every edge of geometry created after snapshot `before`."""
    faces = [f for f in bm.faces if f not in before]
    edges = list({e for f in faces for e in f.edges})
    bmesh.ops.bevel(
        bm,
        geom=edges,
        offset=BEVEL,
        offset_type="OFFSET",
        segments=1,
        profile=0.5,
        affect="EDGES",
        clamp_overlap=True,
    )


def _finish_part(
    bm: bmesh.types.BMesh,
    layers: tuple,
    rng: random.Random,
    before: set,
    size: Vector,
    xform: Matrix,
    ao_mult: float,
) -> None:
    """Assign plank-local UVs + Col to new faces, then move part into place.

    UV U axis always follows the plank long axis so wood grain stays consistent.
    """
    uv_layer, col_layer = layers
    faces = [f for f in bm.faces if f not in before]
    verts = list({v for f in faces for v in f.verts})
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    for f in faces:
        f.normal_update()

    long_ax = max(range(3), key=lambda i: size[i])
    plank_id = rng.random()
    uv_off = Vector((rng.random(), rng.random()))

    for f in faces:
        n = f.normal
        k = max(range(3), key=lambda i: abs(n[i]))
        others = [i for i in range(3) if i != k]
        if long_ax in others:
            u_ax = long_ax
            v_ax = others[1] if others[0] == long_ax else others[0]
        else:
            u_ax, v_ax = sorted(others, key=lambda i: -size[i])
        edge_mask = 1.0 if max(abs(n.x), abs(n.y), abs(n.z)) < 0.9 else 0.0
        face_ao = ao_mult * (0.55 if n.z < -0.5 else 1.0)
        for loop in f.loops:
            co = loop.vert.co
            loop[uv_layer].uv = Vector((co[u_ax], co[v_ax])) + uv_off
            loop[col_layer] = (plank_id, face_ao, edge_mask, 1.0)

    bmesh.ops.transform(bm, matrix=xform, verts=verts)


def add_plank(
    bm: bmesh.types.BMesh,
    layers: tuple,
    rng: random.Random,
    size: Vector,
    xform: Matrix,
    ao_mult: float,
) -> None:
    """Beveled box plank centered on `xform` origin."""
    before = set(bm.faces)
    ret = bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=ret["verts"])
    _bevel_new(bm, before)
    _finish_part(bm, layers, rng, before, size, xform, ao_mult)


def add_stringer(
    bm: bmesh.types.BMesh,
    layers: tuple,
    rng: random.Random,
    xform: Matrix,
) -> None:
    """Notched stringer: XZ profile extruded along Y, feet over bottom slats."""
    before = set(bm.faces)
    hx = WIDTH * 0.5
    hz = STRINGER_HEIGHT * 0.5
    nz = -hz + NOTCH_DEPTH
    hy = STRINGER_WIDTH * 0.5
    profile = [(-hx, -hz)]
    for bx in BOT_SLAT_X[:-1]:
        nxt = BOT_SLAT_X[BOT_SLAT_X.index(bx) + 1]
        a = bx + FOOT_HALF
        b = nxt - FOOT_HALF
        profile += [(a, -hz), (a, nz), (b, nz), (b, -hz)]
    profile += [(hx, -hz), (hx, hz), (-hx, hz)]

    verts = [bm.verts.new((x, -hy, z)) for x, z in profile]
    face = bm.faces.new(verts)
    ret = bmesh.ops.extrude_face_region(bm, geom=[face])
    ext_verts = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0.0, STRINGER_WIDTH, 0.0)), verts=ext_verts)
    _bevel_new(bm, before)
    size = Vector((WIDTH, STRINGER_WIDTH, STRINGER_HEIGHT))
    _finish_part(bm, layers, rng, before, size, xform, 0.7)


def add_nail(bm: bmesh.types.BMesh, layers: tuple, xform: Matrix) -> None:
    """Dark nail-head cap, oriented with its slat via `xform`."""
    uv_layer, col_layer = layers
    before = set(bm.faces)
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=True,
        segments=6,
        radius1=NAIL_R_BOT,
        radius2=NAIL_R_TOP,
        depth=NAIL_DEPTH,
    )
    faces = [f for f in bm.faces if f not in before]
    verts = list({v for f in faces for v in f.verts})
    bmesh.ops.transform(bm, matrix=xform, verts=verts)
    for f in faces:
        for loop in f.loops:
            loop[uv_layer].uv = Vector((0.0, 0.0))
            loop[col_layer] = (0.0, 0.05, 1.0, 1.0)


# ---------------------------------------------------------------------------
# Material (Blender preview only; procedural nodes do not export to glTF)
# ---------------------------------------------------------------------------
def _sock(sockets: bpy.types.bpy_prop_collection, name: str, typ: str) -> bpy.types.NodeSocket:
    """Pick socket by name + type (ShaderNodeMix repeats names per data type)."""
    return next(s for s in sockets if s.name == name and s.type == typ)


def build_material() -> bpy.types.Material:
    mat = bpy.data.materials.new(name=MAT_NAME)  # Blender 5.x: node tree always on
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()

    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.88

    attr = nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    sep = nodes.new("ShaderNodeSeparateColor")

    tex_coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (2.0, 18.0, 2.0)  # U = along grain

    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 12.0
    noise.inputs["Detail"].default_value = 8.0
    noise.inputs["Roughness"].default_value = 0.65

    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.25
    ramp.color_ramp.elements[0].color = (0.12, 0.11, 0.09, 1.0)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.32, 0.30, 0.25, 1.0)

    mix_ao = nodes.new("ShaderNodeMix")
    mix_ao.data_type = "RGBA"
    mix_ao.blend_type = "MULTIPLY"
    mix_ao.inputs["Factor"].default_value = 0.85

    links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(attr.outputs["Color"], sep.inputs["Color"])
    links.new(ramp.outputs["Color"], _sock(mix_ao.inputs, "A", "RGBA"))
    links.new(sep.outputs["Green"], _sock(mix_ao.inputs, "B", "RGBA"))
    links.new(_sock(mix_ao.outputs, "Result", "RGBA"), bsdf.inputs["Base Color"])
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
def _xf(pos: Vector, rot: Euler) -> Matrix:
    return Matrix.Translation(pos) @ rot.to_matrix().to_4x4()


def generate_pallet() -> tuple[bpy.types.Object, bpy.types.Object]:
    rng = random.Random(SEED)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    col_layer = bm.loops.layers.float_color.new("Col")  # Linear: masks stay exact
    layers = (uv_layer, col_layer)

    # 1. Bottom slats (yaw-only jitter keeps flat floor contact at Z = 0)
    z_bot = SLAT_THICK * 0.5
    for x in BOT_SLAT_X:
        rot = Euler((0.0, 0.0, rng.uniform(-0.008, 0.008)))
        pos = Vector((x + rng.uniform(-0.002, 0.002), 0.0, z_bot))
        size = Vector((SLAT_WIDTH, LENGTH, SLAT_THICK))
        add_plank(bm, layers, rng, size, _xf(pos, rot), 0.6)

    # 2. Notched stringers
    z_mid = SLAT_THICK + STRINGER_HEIGHT * 0.5
    for y in STRINGER_Y:
        rot = Euler((0.0, 0.0, rng.uniform(-0.004, 0.004)))
        add_stringer(bm, layers, rng, _xf(Vector((0.0, y, z_mid)), rot))

    # 3. Top slats + nails (nails ride slat transform -> sit on tilted surface)
    z_top = HEIGHT - SLAT_THICK * 0.5
    nail_z = SLAT_THICK * 0.5 + NAIL_PROUD - NAIL_DEPTH * 0.5
    for x in TOP_SLAT_X:
        yaw = rng.uniform(-0.012, 0.012)
        pitch = rng.uniform(-0.005, 0.005)
        dx = rng.uniform(-0.003, 0.003)
        dy = rng.uniform(-0.006, 0.006)
        w_var = SLAT_WIDTH + rng.uniform(-0.006, 0.006)
        slat_xf = _xf(Vector((x + dx, dy, z_top)), Euler((pitch, 0.0, yaw)))
        add_plank(bm, layers, rng, Vector((w_var, LENGTH, SLAT_THICK)), slat_xf, 1.0)

        for sy in STRINGER_Y:
            for nx_off in (-NAIL_X_OFF, NAIL_X_OFF):
                local = Vector((nx_off, sy - dy + rng.uniform(-0.008, 0.008), nail_z))
                add_nail(bm, layers, slat_xf @ Matrix.Translation(local))

    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="EAR_CLIP")

    mesh = bpy.data.meshes.new("Pallet")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    mesh.color_attributes.active_color_name = "Col"
    mesh.color_attributes.render_color_index = mesh.color_attributes.find("Col")
    mesh.validate()

    pallet = bpy.data.objects.new("Pallet", mesh)
    bpy.context.collection.objects.link(pallet)
    mesh.materials.append(build_material())

    # 4. Godot box collider (-colonly)
    bm_col = bmesh.new()
    ret = bmesh.ops.create_cube(bm_col, size=1.0)
    bmesh.ops.scale(bm_col, vec=Vector((WIDTH, LENGTH, HEIGHT)), verts=ret["verts"])
    bmesh.ops.translate(bm_col, vec=Vector((0.0, 0.0, HEIGHT * 0.5)), verts=ret["verts"])
    col_mesh = bpy.data.meshes.new("Pallet-colonly")
    bm_col.to_mesh(col_mesh)
    bm_col.free()
    col_obj = bpy.data.objects.new("Pallet-colonly", col_mesh)
    col_obj.parent = pallet
    col_obj.display_type = "WIRE"
    bpy.context.collection.objects.link(col_obj)
    return pallet, col_obj


def export(pallet: bpy.types.Object, col_obj: bpy.types.Object) -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    glb = OUT_DIR / f"{SLUG}.glb"
    bpy.ops.object.select_all(action="DESELECT")
    pallet.select_set(True)
    col_obj.select_set(True)
    bpy.context.view_layer.objects.active = pallet
    bpy.ops.export_scene.gltf(
        filepath=str(glb),
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_attributes=True,
        export_vertex_color="ACTIVE",
        export_animations=False,
        use_selection=True,
    )

    tris = len(pallet.data.polygons)
    co = [v.co for v in pallet.data.vertices]
    mn = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
    mx = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
    dim = mx - mn
    manifest = {
        "slug": SLUG,
        "layer": "Layer 1 Environment",
        "source": "blender_procedural_bpy",
        "tri_count": tris,
        "tri_budget": TRI_BUDGET,
        "uv_layers": len(pallet.data.uv_layers),
        "dimensions_m": {
            "width_x": round(dim.x, 4),
            "height_y": round(dim.z, 4),
            "depth_z": round(dim.y, 4),
        },
        "min_z_blender": round(mn.z, 5),
        "collision_hint": "box_shape (Pallet-colonly)",
        "vertex_color": "COLOR_0: R plank seed, G AO, B edge wear (linear)",
        "mesh": f"res://assets/models/{SLUG}/{SLUG}.glb",
    }
    (OUT_DIR / "asset_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"[pallet] tris={tris} bounds_min={tuple(mn)} bounds_max={tuple(mx)}")
    print(f"[pallet] exported {glb}")


if __name__ == "__main__":
    clean_scene()
    obj, col = generate_pallet()
    export(obj, col)
