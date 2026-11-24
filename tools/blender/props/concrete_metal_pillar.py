"""Procedural Concrete & Rusted Steel Lattice Pillar (Standard 4.04m + Tall 8.0m).

Generates both variants with identical 0.64m x 0.64m x 1.30m tapered concrete
plinths, bolted steel baseplates/gussets, clean repeating X-brace steel truss
bays (zero Z-stretch), uniform world-scale cubic UVs, and wired PBR textures.

Run:
    python3 tools/blender/run.py tools/blender/props/concrete_metal_pillar.py
"""

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene, export_godot_glb

ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "concrete_metal_pillar"
MAT_CONCRETE_DIR: Path = REPO_ROOT / "assets" / "materials" / "pillar_weathered_concrete" / "textures"
MAT_STEEL_DIR: Path = REPO_ROOT / "assets" / "materials" / "pillar_rusted_truss_steel" / "textures"

# Shared base footprint & truss cross-section (meters)
PLINTH_BOT_W: float = 0.64
PLINTH_TOP_W: float = 0.50
PLINTH_H: float = 1.30

PLATE_W: float = 0.46
PLATE_THICK: float = 0.04

TRUSS_W: float = 0.42
POST_SIZE: float = 0.048
BRACE_W: float = 0.028
BRACE_T: float = 0.016
GUSSET_H: float = 0.14
GUSSET_W: float = 0.08
GUSSET_T: float = 0.018

UV_TILE_METERS: float = 2.0


def _create_pbr_material(
    name: str,
    albedo_path: Path,
    orm_path: Path,
    normal_path: Path,
    normal_strength: float = 0.75,
    embed_textures: bool = False,
    fallback_color: tuple[float, float, float, float] = (0.5, 0.5, 0.5, 1.0),
    fallback_roughness: float = 0.8,
    fallback_metallic: float = 0.0,
) -> bpy.types.Material:
    """Create Principled BSDF material (optionally wired with packed PBR maps)."""
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)

    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (180, 0)
    bsdf.inputs["Base Color"].default_value = fallback_color
    bsdf.inputs["Roughness"].default_value = fallback_roughness
    bsdf.inputs["Metallic"].default_value = fallback_metallic
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if not embed_textures:
        return mat

    # Albedo
    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.location = (-400, 300)
    img_alb = bpy.data.images.load(str(albedo_path), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    # ORM (R=AO, G=Roughness, B=Metallic)
    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-400, 0)
    img_orm = bpy.data.images.load(str(orm_path), check_existing=True)
    img_orm.colorspace_settings.name = "Non-Color"
    tex_orm.image = img_orm

    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-120, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    # Normal map
    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-400, -300)
    img_nrm = bpy.data.images.load(str(normal_path), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm

    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -300)
    nrm_node.inputs["Strength"].default_value = normal_strength
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def _add_box(bm: bmesh.types.BMesh, center: Vector, size: Vector, mat_idx: int) -> None:
    """Add an axis-aligned box into bmesh with assigned material index."""
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    scale_mat = Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    trans_mat = Matrix.Translation(center)
    bmesh.ops.transform(bm, matrix=trans_mat @ scale_mat, verts=verts)
    vert_set = set(verts)
    for f in bm.faces:
        if all(v in vert_set for v in f.verts):
            f.material_index = mat_idx


def _add_tapered_plinth(bm: bmesh.types.BMesh, mat_idx: int) -> None:
    """Add tapered concrete plinth from Z=0.0 to Z=PLINTH_H."""
    hb = PLINTH_BOT_W * 0.5
    ht = PLINTH_TOP_W * 0.5
    v_bot = [
        bm.verts.new((-hb, -hb, 0.0)),
        bm.verts.new((hb, -hb, 0.0)),
        bm.verts.new((hb, hb, 0.0)),
        bm.verts.new((-hb, hb, 0.0)),
    ]
    v_top = [
        bm.verts.new((-ht, -ht, PLINTH_H)),
        bm.verts.new((ht, -ht, PLINTH_H)),
        bm.verts.new((ht, ht, PLINTH_H)),
        bm.verts.new((-ht, ht, PLINTH_H)),
    ]
    faces = [
        bm.faces.new(list(reversed(v_bot))),
        bm.faces.new(v_top),
    ]
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((v_bot[i], v_bot[j], v_top[j], v_top[i])))
    for f in faces:
        f.material_index = mat_idx


def _add_diagonal_strut(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    outward_normal: Vector,
    width: float,
    thick: float,
    mat_idx: int,
) -> None:
    """Add an oriented rectangular steel flat bar between p0 and p1."""
    axis = p1 - p0
    length = axis.length
    if length < 1e-5:
        return
    x_dir = axis.normalized()
    z_dir = outward_normal.normalized()
    y_dir = z_dir.cross(x_dir).normalized()
    z_dir = x_dir.cross(y_dir).normalized()

    rot = Matrix((
        (x_dir.x, y_dir.x, z_dir.x, 0.0),
        (x_dir.y, y_dir.y, z_dir.y, 0.0),
        (x_dir.z, y_dir.z, z_dir.z, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    ))
    mid = (p0 + p1) * 0.5
    scale_mat = Matrix.Diagonal((length, width, thick, 1.0))
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Translation(mid) @ rot @ scale_mat, verts=verts)
    vert_set = set(verts)
    for f in bm.faces:
        if all(v in vert_set for v in f.verts):
            f.material_index = mat_idx


def _apply_box_uvs(bm: bmesh.types.BMesh, tile_m: float = UV_TILE_METERS) -> None:
    """Assign distortion-free cubic world-scale UVs to all faces."""
    uv_layer = bm.loops.layers.uv.verify()
    inv_tile = 1.0 / tile_m
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * inv_tile, co.y * inv_tile
            elif ax >= ay:
                u, v = co.y * inv_tile, co.z * inv_tile
            else:
                u, v = co.x * inv_tile, co.z * inv_tile
            loop[uv_layer].uv = (u, v)


def build_pillar(
    obj_name: str,
    total_height: float,
    num_bays: int,
    output_glb: Path,
    embed_textures: bool = False,
) -> dict:
    """Build a single concrete+steel pillar variant and export GLB."""
    clean_scene()

    mat_concrete = _create_pbr_material(
        "Mat_Concrete",
        MAT_CONCRETE_DIR / "pillar_weathered_concrete_albedo.png",
        MAT_CONCRETE_DIR / "pillar_weathered_concrete_orm.png",
        MAT_CONCRETE_DIR / "pillar_weathered_concrete_normal.png",
        normal_strength=0.80,
        embed_textures=embed_textures,
        fallback_color=(0.45, 0.45, 0.43, 1.0),
        fallback_roughness=0.88,
        fallback_metallic=0.0,
    )
    mat_steel = _create_pbr_material(
        "Mat_Steel",
        MAT_STEEL_DIR / "pillar_rusted_truss_steel_albedo.png",
        MAT_STEEL_DIR / "pillar_rusted_truss_steel_orm.png",
        MAT_STEEL_DIR / "pillar_rusted_truss_steel_normal.png",
        normal_strength=0.70,
        embed_textures=embed_textures,
        fallback_color=(0.18, 0.14, 0.12, 1.0),
        fallback_roughness=0.58,
        fallback_metallic=0.65,
    )

    bm = bmesh.new()

    # 1. Tapered concrete plinth (Z: 0.0 -> 1.30m)
    _add_tapered_plinth(bm, mat_idx=0)

    # 2. Steel base plate (Z: 1.30 -> 1.34m)
    z_truss_bot = PLINTH_H + PLATE_THICK
    z_truss_top = total_height - PLATE_THICK
    truss_h = z_truss_top - z_truss_bot

    _add_box(
        bm,
        Vector((0.0, 0.0, PLINTH_H + PLATE_THICK * 0.5)),
        Vector((PLATE_W, PLATE_W, PLATE_THICK)),
        mat_idx=1,
    )

    # 3. Four corner vertical steel posts (Z: z_truss_bot -> z_truss_top)
    half_span = TRUSS_W * 0.5 - POST_SIZE * 0.5
    corners = [
        (-half_span, -half_span),
        (half_span, -half_span),
        (half_span, half_span),
        (-half_span, half_span),
    ]
    z_post_mid = z_truss_bot + truss_h * 0.5
    for cx, cy in corners:
        _add_box(
            bm,
            Vector((cx, cy, z_post_mid)),
            Vector((POST_SIZE, POST_SIZE, truss_h)),
            mat_idx=1,
        )

    # 4. Base reinforcement gussets on all 4 sides (matches concept plate silhouette)
    gusset_z = z_truss_bot + GUSSET_H * 0.5
    face_offset = TRUSS_W * 0.5 - GUSSET_T * 0.5
    for sign in (-1.0, 1.0):
        # X-facing gussets
        _add_box(
            bm,
            Vector((sign * face_offset, 0.0, gusset_z)),
            Vector((GUSSET_T, PLATE_W * 0.88, GUSSET_H)),
            mat_idx=1,
        )
        # Y-facing gussets
        _add_box(
            bm,
            Vector((0.0, sign * face_offset, gusset_z)),
            Vector((PLATE_W * 0.88, GUSSET_T, GUSSET_H)),
            mat_idx=1,
        )

    # 5. Repeating X-brace lattice bays on all 4 faces
    bay_h = truss_h / float(num_bays)
    face_r = TRUSS_W * 0.5 - BRACE_T * 0.5
    span_x = half_span - POST_SIZE * 0.35

    faces_spec = [
        # (axis_u, axis_n) for +Y, -Y, +X, -X sides
        (Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0))),
        (Vector((1.0, 0.0, 0.0)), Vector((0.0, -1.0, 0.0))),
        (Vector((0.0, 1.0, 0.0)), Vector((1.0, 0.0, 0.0))),
        (Vector((0.0, 1.0, 0.0)), Vector((-1.0, 0.0, 0.0))),
    ]
    for b_idx in range(num_bays):
        z0 = z_truss_bot + b_idx * bay_h
        z1 = z0 + bay_h
        for u_dir, n_dir in faces_spec:
            base_off = n_dir * face_r
            a0 = base_off - u_dir * span_x + Vector((0.0, 0.0, z0))
            a1 = base_off + u_dir * span_x + Vector((0.0, 0.0, z1))
            b0 = base_off + u_dir * span_x + Vector((0.0, 0.0, z0))
            b1 = base_off - u_dir * span_x + Vector((0.0, 0.0, z1))
            _add_diagonal_strut(bm, a0, a1, n_dir, BRACE_W, BRACE_T, mat_idx=1)
            _add_diagonal_strut(bm, b0, b1, n_dir, BRACE_W, BRACE_T, mat_idx=1)

    # 6. Top steel cap plate (Z: z_truss_top -> total_height)
    _add_box(
        bm,
        Vector((0.0, 0.0, z_truss_top + PLATE_THICK * 0.5)),
        Vector((PLATE_W, PLATE_W, PLATE_THICK)),
        mat_idx=1,
    )

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uvs(bm, tile_m=UV_TILE_METERS)

    mesh = bpy.data.meshes.new(obj_name)
    bm.to_mesh(mesh)
    bm.free()

    mesh.materials.append(mat_concrete)
    mesh.materials.append(mat_steel)

    obj = bpy.data.objects.new(obj_name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Flat shading for crisp hard-surface industrial concrete & steel edges
    for poly in mesh.polygons:
        poly.use_smooth = False

    # Tri count & bounding box report
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    dims = [
        round(max(xs) - min(xs), 3),
        round(max(ys) - min(ys), 3),
        round(max(zs) - min(zs), 3),
    ]

    output_glb.parent.mkdir(parents=True, exist_ok=True)
    export_godot_glb(str(output_glb))

    return {
        "name": obj_name,
        "glb": str(output_glb.relative_to(REPO_ROOT)),
        "tri_count": tri_count,
        "uv_layers": len(mesh.uv_layers),
        "dimensions_m": dims,
        "num_bays": num_bays,
    }


def main() -> None:
    embed_textures = "--embed-textures" in sys.argv
    std_info = build_pillar(
        obj_name="ConcreteMetalPillar",
        total_height=4.04,
        num_bays=5,
        output_glb=ASSET_DIR / "concrete_metal_pillar.glb",
        embed_textures=embed_textures,
    )
    tall_info = build_pillar(
        obj_name="ConcreteMetalPillarTall",
        total_height=8.00,
        num_bays=12,
        output_glb=ASSET_DIR / "concrete_metal_pillar_tall.glb",
        embed_textures=embed_textures,
    )

    manifest = {
        "slug": "concrete_metal_pillar",
        "layer": "Layer 1 Environment",
        "source": "blender_headless",
        "tri_budget": 2000,
        "tri_count": std_info["tri_count"],
        "uv_layers": std_info["uv_layers"],
        "dimensions_m": std_info["dimensions_m"],
        "collision_hint": "BoxShape3D",
        "materials": [
            "res://assets/materials/pillar_weathered_concrete/pillar_weathered_concrete.tres",
            "res://assets/materials/pillar_rusted_truss_steel/pillar_rusted_truss_steel.tres",
        ],
        "mesh": "res://assets/models/concrete_metal_pillar/concrete_metal_pillar.glb",
        "scene": "res://assets/models/concrete_metal_pillar/concrete_metal_pillar.tscn",
        "variants": {
            "standard": std_info,
            "tall": tall_info,
        },
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_PILLARS:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
