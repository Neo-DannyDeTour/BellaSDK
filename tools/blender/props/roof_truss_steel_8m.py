"""Procedural 8m Post-Soviet industrial steel pitched roof truss.

Generates a single-mesh 6-bay pitched steel truss (8.0m x 2.2m x 0.15m) with
welded gusset plates, eave bearing foot plates, chunky bevels, weighted normals,
and world-scale cubic UVs for tiling rusted truss steel PBR materials.

Run:
    python3 tools/blender/run.py tools/blender/props/roof_truss_steel_8m.py
"""

import json
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene, export_godot_glb

SLUG: str = "roof_truss_steel_8m"
OBJ_NAME: str = "RoofTrussSteel8m"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / SLUG
EXPORT_PATH: Path = ASSET_DIR / f"{SLUG}.glb"
MAT_STEEL_DIR: Path = (
    REPO_ROOT / "assets" / "materials" / "pillar_rusted_truss_steel" / "textures"
)

# Dimensions (meters)
SPAN: float = 8.0
HALF_SPAN: float = SPAN * 0.5
HEIGHT: float = 2.2
FOOT_THICK: float = 0.03
CHORD_H: float = 0.14
CHORD_D: float = 0.15
WEB_W: float = 0.08
WEB_D: float = 0.09
DIAG_W: float = 0.075
DIAG_D: float = 0.085
GUSSET_D: float = 0.12
BEVEL_OFFSET: float = 0.008
UV_TILE_METERS: float = 1.0

Z_BOT: float = FOOT_THICK + CHORD_H * 0.5
Z_EAVE: float = Z_BOT
Z_APEX: float = HEIGHT - CHORD_H * 0.5


def z_top(x: float) -> float:
    """Return top-chord centerline Z at horizontal coordinate x."""
    ratio: float = max(0.0, 1.0 - abs(x) / HALF_SPAN)
    return Z_EAVE + (Z_APEX - Z_EAVE) * ratio


def add_beam(
    bm: bmesh.types.BMesh,
    p0: Vector,
    p1: Vector,
    width: float,
    depth: float,
    extend: float = 0.0,
) -> None:
    """Create oriented box beam between p0 and p1 in XZ plane."""
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
    scale: Matrix = Matrix.Diagonal((length, depth, width, 1.0))
    mat: Matrix = Matrix.Translation(mid) @ rot @ scale
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat)


def add_box(
    bm: bmesh.types.BMesh,
    center: Vector,
    size: Vector,
) -> None:
    """Create axis-aligned box for gussets and bearing plates."""
    scale: Matrix = Matrix.Diagonal((size.x, size.y, size.z, 1.0))
    mat: Matrix = Matrix.Translation(center) @ scale
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat)


def apply_box_uvs(bm: bmesh.types.BMesh, tile_m: float = UV_TILE_METERS) -> None:
    """Assign uniform world-scale cubic UVs for tiling PBR steel textures."""
    uv_layer = bm.loops.layers.uv.verify()
    inv_tile: float = 1.0 / tile_m
    for face in bm.faces:
        n: Vector = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co: Vector = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * inv_tile, co.y * inv_tile
            elif ax >= ay:
                u, v = co.y * inv_tile, co.z * inv_tile
            else:
                u, v = co.x * inv_tile, co.z * inv_tile
            loop[uv_layer].uv = (u, v)


def create_rusted_steel_material(embed_textures: bool = False) -> bpy.types.Material:
    """Create Principled BSDF steel material (optionally wired with PBR maps)."""
    mat: bpy.types.Material = bpy.data.materials.new(name="Mat_RustedTrussSteel")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)

    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (180, 0)
    bsdf.inputs["Base Color"].default_value = (0.14, 0.11, 0.09, 1.0)
    bsdf.inputs["Metallic"].default_value = 0.78
    bsdf.inputs["Roughness"].default_value = 0.68
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if not embed_textures:
        return mat

    albedo_path: Path = MAT_STEEL_DIR / "pillar_rusted_truss_steel_albedo.png"
    orm_path: Path = MAT_STEEL_DIR / "pillar_rusted_truss_steel_orm.png"
    normal_path: Path = MAT_STEEL_DIR / "pillar_rusted_truss_steel_normal.png"

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
        nrm_node.inputs["Strength"].default_value = 0.70
        nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
        nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def build_truss(embed_textures: bool = False) -> bpy.types.Object:
    """Build merged 6-bay industrial roof truss mesh."""
    bm: bmesh.types.BMesh = bmesh.new()

    # 1. Bottom horizontal chord
    add_beam(
        bm,
        Vector((-HALF_SPAN, 0.0, Z_BOT)),
        Vector((HALF_SPAN, 0.0, Z_BOT)),
        CHORD_H,
        CHORD_D,
    )

    # 2. Left & right sloped top chords
    apex: Vector = Vector((0.0, 0.0, Z_APEX))
    add_beam(bm, Vector((-HALF_SPAN, 0.0, Z_EAVE)), apex, CHORD_H, CHORD_D, extend=0.04)
    add_beam(bm, Vector((HALF_SPAN, 0.0, Z_EAVE)), apex, CHORD_H, CHORD_D, extend=0.04)

    # 3. 6-bay node X coordinates (3 bays per side)
    bay_count: int = 6
    xs: list[float] = [
        -HALF_SPAN + (SPAN * i / bay_count) for i in range(bay_count + 1)
    ]

    # 4. Vertical web struts (king post + 4 intermediate verticals)
    for x in xs[1:-1]:
        add_beam(
            bm,
            Vector((x, 0.0, Z_BOT)),
            Vector((x, 0.0, z_top(x))),
            WEB_W,
            WEB_D,
        )

    # 5. Diagonal web struts (mirrored Howe/Pratt triangulation)
    diagonals: list[tuple[Vector, Vector]] = [
        (Vector((xs[1], 0.0, Z_BOT)), Vector((xs[2], 0.0, z_top(xs[2])))),
        (Vector((xs[2], 0.0, Z_BOT)), Vector((xs[3], 0.0, z_top(xs[3])))),
        (Vector((xs[5], 0.0, Z_BOT)), Vector((xs[4], 0.0, z_top(xs[4])))),
        (Vector((xs[4], 0.0, Z_BOT)), Vector((xs[3], 0.0, z_top(xs[3])))),
    ]
    for p0, p1 in diagonals:
        add_beam(bm, p0, p1, DIAG_W, DIAG_D)

    # 6. Welded gusset plates at key joints (tiered depth prevents Z-fighting)
    add_box(bm, Vector((0.0, 0.0, Z_APEX - 0.08)), Vector((0.36, GUSSET_D, 0.24)))
    for x in xs[1:-1]:
        add_box(bm, Vector((x, 0.0, Z_BOT + 0.05)), Vector((0.28, GUSSET_D, 0.20)))
    for x in (xs[1], xs[2], xs[4], xs[5]):
        add_box(bm, Vector((x, 0.0, z_top(x) - 0.05)), Vector((0.26, GUSSET_D, 0.18)))

    # 7. Eave bearing foot plates (flush on Z=0.0)
    for sign in (-1.0, 1.0):
        add_box(
            bm,
            Vector((sign * (HALF_SPAN - 0.15), 0.0, FOOT_THICK * 0.5)),
            Vector((0.30, 0.22, FOOT_THICK)),
        )

    # Chunky industrial bevels across all edges
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=BEVEL_OFFSET,
        segments=1,
        affect="EDGES",
        clamp_overlap=True,
    )
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    apply_box_uvs(bm, tile_m=UV_TILE_METERS)

    mesh: bpy.types.Mesh = bpy.data.meshes.new(OBJ_NAME)
    bm.to_mesh(mesh)
    bm.free()

    obj: bpy.types.Object = bpy.data.objects.new(OBJ_NAME, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    # Smooth shading + weighted normals for crisp hard-surface bevels
    for poly in mesh.polygons:
        poly.use_smooth = True
    wn_mod: bpy.types.Modifier = obj.modifiers.new(
        name="WeightedNormal", type="WEIGHTED_NORMAL"
    )
    wn_mod.weight = 50
    wn_mod.keep_sharp = False
    bpy.ops.object.modifier_apply(modifier=wn_mod.name)

    obj.data.materials.append(create_rusted_steel_material(embed_textures=embed_textures))
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
            "res://assets/materials/pillar_rusted_truss_steel/pillar_rusted_truss_steel.tres",
        ],
        "mesh": f"res://assets/models/{SLUG}/{SLUG}.glb",
        "scene": f"res://assets/models/{SLUG}/{SLUG}.tscn",
    }
    manifest_path: Path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_TRUSS:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
