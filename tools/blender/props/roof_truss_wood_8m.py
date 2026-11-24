"""Procedural 8m weathered wooden king-post roof truss.

Generates a single-mesh pitched timber roof truss (8.0m x 2.2m x 0.22m) with
bottom tie beam, sloped top rafters, central king post, diagonal braces,
timber bevels, beam-aligned wood grain UVs, and rusted hex bolt/washer hardware.

Run:
    python3 tools/blender/run.py tools/blender/props/roof_truss_wood_8m.py
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

SLUG: str = "roof_truss_wood_8m"
OBJ_NAME: str = "RoofTrussWood8m"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / SLUG
EXPORT_PATH: Path = ASSET_DIR / f"{SLUG}.glb"

MAT_WOOD_DIR: Path = (
    REPO_ROOT / "assets" / "materials" / "roof_truss_timber" / "textures"
)
MAT_STEEL_DIR: Path = (
    REPO_ROOT / "assets" / "materials" / "rusted_steel" / "textures"
)

# Dimensions (meters)
SPAN: float = 8.0
HALF_SPAN: float = SPAN * 0.5
HEIGHT: float = 2.2

TIE_H: float = 0.22
TIE_D: float = 0.18
RAFTER_H: float = 0.20
RAFTER_D: float = 0.175
KING_W: float = 0.19
KING_D: float = 0.19
STRUT_W: float = 0.15
STRUT_D: float = 0.14
BEVEL_OFFSET: float = 0.009
UV_TILE_METERS: float = 2.0

Z_TIE_CENTER: float = TIE_H * 0.5
Z_EAVE: float = Z_TIE_CENTER + 0.02
Z_APEX: float = HEIGHT - RAFTER_H * 0.5


def z_rafter_center(x: float) -> float:
    """Return top-rafter centerline Z at horizontal coordinate x."""
    ratio: float = max(0.0, 1.0 - abs(x) / HALF_SPAN)
    return Z_EAVE + (Z_APEX - Z_EAVE) * ratio


def add_wood_beam(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    width: float,
    depth: float,
    extend: float = 0.0,
    uv_offset: tuple[float, float] = (0.0, 0.0),
) -> None:
    """Create oriented beveled timber beam with grain-aligned UVs along p0->p1."""
    delta: Vector = p1 - p0
    length: float = delta.length + extend * 2.0
    if length <= 1e-5:
        return

    axis_x: Vector = delta.normalized()
    axis_y: Vector = Vector((0.0, 1.0, 0.0))
    axis_z: Vector = axis_x.cross(axis_y).normalized()

    rot: Matrix = Matrix((
        (axis_x.x, axis_y.x, axis_z.x, 0.0),
        (axis_x.y, axis_y.y, axis_z.y, 0.0),
        (axis_x.z, axis_y.z, axis_z.z, 0.0),
        (0.0, 0.0, 0.0, 1.0),
    ))
    mid: Vector = (p0 + p1) * 0.5

    # Build in local space so bevel and grain-aligned UVs are exact
    sub: bmesh.types.BMesh = bmesh.new()
    scale: Matrix = Matrix.Diagonal((length, depth, width, 1.0))
    bmesh.ops.create_cube(sub, size=1.0, matrix=scale)
    bmesh.ops.bevel(
        sub,
        geom=list(sub.edges),
        offset=BEVEL_OFFSET,
        segments=1,
        affect="EDGES",
        clamp_overlap=True,
    )
    bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))

    # Assign beam-aligned UVs (U runs along beam length X, V wraps cross-section)
    uv_layer = sub.loops.layers.uv.verify()
    inv_tile: float = 1.0 / UV_TILE_METERS
    u_off, v_off = uv_offset
    for face in sub.faces:
        face.material_index = 0
        n: Vector = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co: Vector = loop.vert.co
            if ax >= ay and ax >= az:
                # End-grain cap
                u = co.y * inv_tile + u_off
                v = co.z * inv_tile + v_off
            elif ay >= az:
                # Front/back wide face: U along beam length, V across height
                u = co.x * inv_tile + u_off
                v = co.z * inv_tile + v_off
            else:
                # Top/bottom face: U along beam length, V across depth
                u = co.x * inv_tile + u_off
                v = co.y * inv_tile + v_off
            loop[uv_layer].uv = (u, v)

    # Transform to world position and merge into main BMesh
    world_mat: Matrix = Matrix.Translation(mid) @ rot
    bmesh.ops.transform(sub, matrix=world_mat, verts=list(sub.verts))
    merge_bmesh(bm, sub)
    sub.free()


def add_bolt_pair(
    bm: bmesh.types.BMesh,
    x: float,
    z: float,
    half_thickness: float,
    washer_r: float = 0.028,
    washer_t: float = 0.008,
    head_r: float = 0.017,
    head_t: float = 0.014,
) -> None:
    """Create washer + hex bolt head on both +Y and -Y faces at (x, z)."""
    for sign in (-1.0, 1.0):
        sub: bmesh.types.BMesh = bmesh.new()

        # Circular washer (8-sided)
        w_y: float = sign * (half_thickness + washer_t * 0.5)
        w_mat: Matrix = (
            Matrix.Translation(Vector((x, w_y, z)))
            @ Matrix.Rotation(math.radians(90.0), 4, "X")
        )
        bmesh.ops.create_cone(
            sub,
            cap_ends=True,
            cap_tris=False,
            segments=8,
            radius1=washer_r,
            radius2=washer_r,
            depth=washer_t,
            matrix=w_mat,
        )

        # Hex bolt head (6-sided)
        h_y: float = sign * (half_thickness + washer_t + head_t * 0.5)
        h_mat: Matrix = (
            Matrix.Translation(Vector((x, h_y, z)))
            @ Matrix.Rotation(math.radians(90.0), 4, "X")
        )
        bmesh.ops.create_cone(
            sub,
            cap_ends=True,
            cap_tris=False,
            segments=6,
            radius1=head_r,
            radius2=head_r * 0.92,
            depth=head_t,
            matrix=h_mat,
        )

        bmesh.ops.recalc_face_normals(sub, faces=list(sub.faces))
        uv_layer = sub.loops.layers.uv.verify()
        for face in sub.faces:
            face.material_index = 1
            for loop in face.loops:
                co: Vector = loop.vert.co
                loop[uv_layer].uv = (co.x * 2.0, co.z * 2.0)

        merge_bmesh(bm, sub)
        sub.free()


def merge_bmesh(dst: bmesh.types.BMesh, src: bmesh.types.BMesh) -> None:
    """Copy all geometry, UVs, and material indices from src into dst."""
    src_uv = src.loops.layers.uv.verify()
    dst_uv = dst.loops.layers.uv.verify()

    vert_map: dict[int, bmesh.types.BMVert] = {}
    for v in src.verts:
        vert_map[v.index] = dst.verts.new(v.co)
    dst.verts.ensure_lookup_table()

    for f in src.faces:
        new_verts = [vert_map[v.index] for v in f.verts]
        new_face = dst.faces.new(new_verts)
        new_face.material_index = f.material_index
        for src_loop, dst_loop in zip(f.loops, new_face.loops):
            dst_loop[dst_uv].uv = src_loop[src_uv].uv


def _wire_pbr_material(
    name: str,
    base_color: tuple[float, float, float, float],
    metallic: float,
    roughness: float,
    tex_dir: Path,
    slug: str,
    normal_strength: float,
    embed_textures: bool,
) -> bpy.types.Material:
    """Create Principled BSDF material optionally wired with ORM PBR textures."""
    mat: bpy.types.Material = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)

    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (180, 0)
    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if not embed_textures:
        return mat

    albedo_path: Path = tex_dir / f"{slug}_albedo.png"
    orm_path: Path = tex_dir / f"{slug}_orm.png"
    normal_path: Path = tex_dir / f"{slug}_normal.png"

    if albedo_path.is_file():
        tex_alb = nt.nodes.new("ShaderNodeTexImage")
        tex_alb.location = (-400, 300)
        img_alb = bpy.data.images.load(str(albedo_path), check_existing=True)
        img_alb.colorspace_settings.name = "sRGB"
        tex_alb.image = img_alb
        nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    if orm_path.is_file():
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

    if normal_path.is_file():
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


def build_truss(embed_textures: bool = False) -> bpy.types.Object:
    """Build merged wooden king-post roof truss with bolt hardware."""
    bm: bmesh.types.BMesh = bmesh.new()

    # 1. Bottom horizontal tie beam (flush on Z = 0.0)
    add_wood_beam(
        bm,
        Vector((-HALF_SPAN, 0.0, Z_TIE_CENTER)),
        Vector((HALF_SPAN, 0.0, Z_TIE_CENTER)),
        TIE_H,
        TIE_D,
        uv_offset=(0.0, 0.0),
    )

    # 2. Left & right sloped top rafters
    apex: Vector = Vector((0.0, 0.0, Z_APEX))
    add_wood_beam(
        bm,
        Vector((-HALF_SPAN + 0.05, 0.0, Z_EAVE)),
        apex,
        RAFTER_H,
        RAFTER_D,
        extend=0.05,
        uv_offset=(0.37, 0.19),
    )
    add_wood_beam(
        bm,
        Vector((HALF_SPAN - 0.05, 0.0, Z_EAVE)),
        apex,
        RAFTER_H,
        RAFTER_D,
        extend=0.05,
        uv_offset=(0.71, 0.43),
    )

    # 3. Central vertical king post (full height from tie beam base to apex)
    add_wood_beam(
        bm,
        Vector((0.0, 0.0, 0.01)),
        Vector((0.0, 0.0, Z_APEX + 0.02)),
        KING_W,
        KING_D,
        uv_offset=(0.15, 0.62),
    )

    # 4. Left & right diagonal compression struts (king post base -> mid-rafter)
    strut_top_x: float = 1.95
    strut_bot_z: float = Z_TIE_CENTER + 0.04
    for idx, sign in enumerate((-1.0, 1.0)):
        p_bot: Vector = Vector((sign * 0.06, 0.0, strut_bot_z))
        p_top: Vector = Vector(
            (sign * strut_top_x, 0.0, z_rafter_center(strut_top_x) - 0.03)
        )
        add_wood_beam(
            bm,
            p_bot,
            p_top,
            STRUT_W,
            STRUT_D,
            extend=0.04,
            uv_offset=(0.25 + idx * 0.41, 0.31),
        )

    # 5. Rusted hex bolts & washers at structural timber joints
    # Center king-post to tie-beam bolted lap joint (4 bolts)
    king_half: float = KING_D * 0.5
    for bx in (-0.055, 0.055):
        for bz in (Z_TIE_CENTER - 0.055, Z_TIE_CENTER + 0.055):
            add_bolt_pair(bm, bx, bz, king_half)

    # Strut lower flange bolts on tie beam
    tie_half: float = TIE_D * 0.5
    for sign in (-1.0, 1.0):
        add_bolt_pair(bm, sign * 0.36, Z_TIE_CENTER + 0.04, tie_half)

    # Strut upper joint bolts on rafters
    rafter_half: float = RAFTER_D * 0.5
    for sign in (-1.0, 1.0):
        add_bolt_pair(
            bm,
            sign * strut_top_x,
            z_rafter_center(strut_top_x) - 0.01,
            rafter_half,
        )

    # Apex ridge bolts where rafters meet king post
    for sign in (-1.0, 1.0):
        add_bolt_pair(bm, sign * 0.055, Z_APEX - 0.14, king_half)

    # Heel / eave joint bolts securing rafters to tie beam ends
    for sign in (-1.0, 1.0):
        add_bolt_pair(bm, sign * (HALF_SPAN - 0.55), Z_TIE_CENTER + 0.03, tie_half)
        add_bolt_pair(bm, sign * (HALF_SPAN - 0.85), Z_TIE_CENTER + 0.03, tie_half)

    mesh: bpy.types.Mesh = bpy.data.meshes.new(OBJ_NAME)
    bm.to_mesh(mesh)
    bm.free()

    obj: bpy.types.Object = bpy.data.objects.new(OBJ_NAME, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Smooth shading + weighted normals for crisp timber bevels
    for poly in mesh.polygons:
        poly.use_smooth = True
    wn_mod: bpy.types.Modifier = obj.modifiers.new(
        name="WeightedNormal", type="WEIGHTED_NORMAL"
    )
    wn_mod.weight = 50
    wn_mod.keep_sharp = False
    bpy.ops.object.modifier_apply(modifier=wn_mod.name)

    mat_wood: bpy.types.Material = _wire_pbr_material(
        name="Mat_RoofTrussTimber",
        base_color=(0.18, 0.14, 0.10, 1.0),
        metallic=0.0,
        roughness=0.85,
        tex_dir=MAT_WOOD_DIR,
        slug="roof_truss_timber",
        normal_strength=0.65,
        embed_textures=embed_textures,
    )
    mat_bolts: bpy.types.Material = _wire_pbr_material(
        name="Mat_RustedBolts",
        base_color=(0.12, 0.09, 0.07, 1.0),
        metallic=0.75,
        roughness=0.68,
        tex_dir=MAT_STEEL_DIR,
        slug="rusted_steel",
        normal_strength=0.45,
        embed_textures=embed_textures,
    )
    obj.data.materials.append(mat_wood)
    obj.data.materials.append(mat_bolts)
    return obj


def main() -> None:
    """Run clean build, export GLB, and write asset_manifest.json."""
    embed_textures: bool = "--embed-textures" in sys.argv
    clean_scene()
    obj: bpy.types.Object = build_truss(embed_textures=embed_textures)
    mesh: bpy.types.Mesh = obj.data

    tri_count: int = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs: list[float] = [v.co.x for v in mesh.vertices]
    ys: list[float] = [v.co.y for v in mesh.vertices]
    zs: list[float] = [v.co.z for v in mesh.vertices]
    # Report dimensions in Godot Y-up (X=width, Y=height, Z=depth)
    dims_godot: list[float] = [
        round(max(xs) - min(xs), 3),
        round(max(zs) - min(zs), 3),
        round(max(ys) - min(ys), 3),
    ]

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    export_godot_glb(EXPORT_PATH, export_animations=False)

    manifest: dict[str, object] = {
        "slug": SLUG,
        "layer": "Layer 1 Environment",
        "source": "blender_headless",
        "tri_budget": 2000,
        "tri_count": tri_count,
        "uv_layers": len(mesh.uv_layers),
        "dimensions_m": dims_godot,
        "collision_hint": "BoxShape3D",
        "materials": [
            "res://assets/materials/roof_truss_timber/roof_truss_timber.tres",
            "res://assets/materials/rusted_steel/rusted_steel.tres",
        ],
        "mesh": f"res://assets/models/{SLUG}/{SLUG}.glb",
        "scene": f"res://assets/models/{SLUG}/{SLUG}.tscn",
    }
    manifest_path: Path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_TRUSS:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
