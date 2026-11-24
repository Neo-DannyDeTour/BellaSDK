"""Procedural Czech Hedgehog (Post-Soviet Industrial L-Angle Barricade).

Run:
    python3 tools/blender/run.py tools/blender/props/czech_hedgehog.py
"""

import json
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.exporter import clean_scene, export_godot_glb

ASSET_DIR: Path = Path("assets/models/czech_hedgehog")
OUTPUT_PATH: str = str(ASSET_DIR / "czech_hedgehog.glb")
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
TEXTURE_DIR: Path = ASSET_DIR / "textures"

# Dimensions (meters) -> 2.25m beams tilted on 3 tips yield ~1.40m total height
BEAM_LENGTH: float = 2.25
FLANGE_WIDTH: float = 0.14
FLANGE_THICK: float = 0.016
BEAM_OFFSET: float = 0.048
GUSSET_SIZE: float = 0.24
GUSSET_THICK: float = 0.014
RIVET_RADIUS: float = 0.015
RIVET_HEIGHT: float = 0.012
BEVEL_WIDTH: float = 0.004


def _build_l_beam_bm(length: float, width: float, thick: float) -> bmesh.types.BMesh:
    """Create L-angle steel beam centered on local X axis."""
    bm = bmesh.new()
    half_l = length * 0.5
    half_w = width * 0.5

    # L-profile in YZ plane (6 vertices, CCW)
    profile = [
        (-half_w, -half_w),
        (half_w, -half_w),
        (half_w, -half_w + thick),
        (-half_w + thick, -half_w + thick),
        (-half_w + thick, half_w),
        (-half_w, half_w),
    ]

    v_neg = [bm.verts.new((-half_l, y, z)) for (y, z) in profile]
    v_pos = [bm.verts.new((half_l, y, z)) for (y, z) in profile]

    # End caps (outward normals)
    bm.faces.new(list(reversed(v_neg)))
    bm.faces.new(v_pos)

    # Side walls
    count = len(profile)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((v_neg[i], v_neg[j], v_pos[j], v_pos[i]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=BEVEL_WIDTH,
        segments=1,
        affect="EDGES",
        clamp_overlap=True,
    )
    return bm


def _build_gusset_bm(size: float, thick: float) -> bmesh.types.BMesh:
    """Create octagonal-cut steel reinforcement plate in XY plane."""
    bm = bmesh.new()
    h = size * 0.5
    c = size * 0.22
    ht = thick * 0.5

    pts = [
        (-h + c, -h),
        (h - c, -h),
        (h, -h + c),
        (h, h - c),
        (h - c, h),
        (-h + c, h),
        (-h, h - c),
        (-h, -h + c),
    ]
    v_bot = [bm.verts.new((x, y, -ht)) for (x, y) in pts]
    v_top = [bm.verts.new((x, y, ht)) for (x, y) in pts]

    bm.faces.new(list(reversed(v_bot)))
    bm.faces.new(v_top)
    count = len(pts)
    for i in range(count):
        j = (i + 1) % count
        bm.faces.new((v_bot[i], v_bot[j], v_top[j], v_top[i]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.bevel(
        bm,
        geom=list(bm.edges),
        offset=BEVEL_WIDTH * 0.75,
        segments=1,
        affect="EDGES",
        clamp_overlap=True,
    )
    return bm


def _add_rivet(
    target_bm: bmesh.types.BMesh,
    location: Vector,
    normal: Vector,
) -> None:
    """Append chunky 6-sided industrial rivet head along normal."""
    rot = Vector((0.0, 0.0, 1.0)).rotation_difference(normal.normalized()).to_matrix().to_4x4()
    mat = Matrix.Translation(location + normal.normalized() * (RIVET_HEIGHT * 0.5)) @ rot
    bmesh.ops.create_cone(
        target_bm,
        cap_ends=True,
        cap_tris=False,
        segments=6,
        radius1=RIVET_RADIUS,
        radius2=RIVET_RADIUS * 0.75,
        depth=RIVET_HEIGHT,
        matrix=mat,
    )


def _merge_bm(dst: bmesh.types.BMesh, src: bmesh.types.BMesh, xform: Matrix) -> None:
    """Transform and merge src BMesh into dst BMesh."""
    bmesh.ops.transform(src, matrix=xform, verts=src.verts)
    vert_map = {}
    for v in src.verts:
        vert_map[v.index] = dst.verts.new(v.co)
    for f in src.faces:
        dst.faces.new([vert_map[v.index] for v in f.verts])
    src.free()


def _create_weathered_steel_material(embed_textures: bool = False) -> bpy.types.Material:
    """Create PBR oxidized steel material; embed ORM textures only when requested."""
    mat = bpy.data.materials.new(name="M_CzechHedgehog_Steel")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    bsdf = nodes.get("Principled BSDF")
    if bsdf is None:
        return mat

    albedo_path = (TEXTURE_DIR / "czech_hedgehog_albedo.png").resolve()
    orm_path = (TEXTURE_DIR / "czech_hedgehog_orm.png").resolve()
    normal_path = (TEXTURE_DIR / "czech_hedgehog_normal.png").resolve()

    if embed_textures and albedo_path.exists() and orm_path.exists() and normal_path.exists():
        tex_coord = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (2.5, 2.5, 2.5)
        links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

        albedo_tex = nodes.new("ShaderNodeTexImage")
        albedo_tex.image = bpy.data.images.load(str(albedo_path))
        albedo_tex.image.colorspace_settings.name = "sRGB"
        links.new(mapping.outputs["Vector"], albedo_tex.inputs["Vector"])
        links.new(albedo_tex.outputs["Color"], bsdf.inputs["Base Color"])

        orm_tex = nodes.new("ShaderNodeTexImage")
        orm_tex.image = bpy.data.images.load(str(orm_path))
        orm_tex.image.colorspace_settings.name = "Non-Color"
        links.new(mapping.outputs["Vector"], orm_tex.inputs["Vector"])

        sep = nodes.new("ShaderNodeSeparateColor")
        links.new(orm_tex.outputs["Color"], sep.inputs["Color"])
        links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

        normal_tex = nodes.new("ShaderNodeTexImage")
        normal_tex.image = bpy.data.images.load(str(normal_path))
        normal_tex.image.colorspace_settings.name = "Non-Color"
        links.new(mapping.outputs["Vector"], normal_tex.inputs["Vector"])

        normal_map = nodes.new("ShaderNodeNormalMap")
        normal_map.inputs["Strength"].default_value = 0.65
        links.new(normal_tex.outputs["Color"], normal_map.inputs["Color"])
        links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        bsdf.inputs["Base Color"].default_value = (0.14, 0.135, 0.13, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.85
        bsdf.inputs["Roughness"].default_value = 0.72

    return mat


def _tripod_rotation_matrix() -> Matrix:
    """Rotate (1,1,1)/sqrt(3) to +Z so 3 beam tips rest flat on Z=0."""
    inv_s2 = 1.0 / math.sqrt(2.0)
    inv_s6 = 1.0 / math.sqrt(6.0)
    inv_s3 = 1.0 / math.sqrt(3.0)
    return Matrix(
        (
            (inv_s2, -inv_s2, 0.0, 0.0),
            (inv_s6, inv_s6, -2.0 * inv_s6, 0.0),
            (inv_s3, inv_s3, inv_s3, 0.0),
            (0.0, 0.0, 0.0, 1.0),
        )
    )


def build_czech_hedgehog(embed_textures: bool = False) -> tuple[bpy.types.Object, float]:
    """Assemble beams, gussets, rivets, align to Z=0, UV unwrap."""
    master_bm = bmesh.new()

    # 3 orthogonal L-beams slightly offset to interlock cleanly at core
    beam_transforms = [
        Matrix.Translation((0.0, BEAM_OFFSET, -BEAM_OFFSET)),
        Matrix.Translation((-BEAM_OFFSET, 0.0, BEAM_OFFSET))
        @ Matrix.Rotation(math.radians(90.0), 4, "Z"),
        Matrix.Translation((BEAM_OFFSET, -BEAM_OFFSET, 0.0))
        @ Matrix.Rotation(math.radians(-90.0), 4, "Y"),
    ]
    for xf in beam_transforms:
        beam_bm = _build_l_beam_bm(BEAM_LENGTH, FLANGE_WIDTH, FLANGE_THICK)
        _merge_bm(master_bm, beam_bm, xf)

    # 3 central gusset plates + hex rivets on both faces
    plate_offset = FLANGE_WIDTH * 0.5 + BEAM_OFFSET + GUSSET_THICK * 0.5
    gusset_configs = [
        (Matrix.Translation((0.0, 0.0, plate_offset)), Vector((0.0, 0.0, 1.0))),
        (
            Matrix.Translation((0.0, plate_offset, 0.0))
            @ Matrix.Rotation(math.radians(90.0), 4, "X"),
            Vector((0.0, 1.0, 0.0)),
        ),
        (
            Matrix.Translation((plate_offset, 0.0, 0.0))
            @ Matrix.Rotation(math.radians(90.0), 4, "Y"),
            Vector((1.0, 0.0, 0.0)),
        ),
    ]
    rivet_offsets = [(-0.07, -0.07), (0.07, -0.07), (0.07, 0.07), (-0.07, 0.07)]

    for g_xf, normal in gusset_configs:
        g_bm = _build_gusset_bm(GUSSET_SIZE, GUSSET_THICK)
        _merge_bm(master_bm, g_bm, g_xf)
        for rx, ry in rivet_offsets:
            local_pt = Vector((rx, ry, GUSSET_THICK * 0.5))
            world_pt = g_xf @ local_pt
            _add_rivet(master_bm, world_pt, normal)

    # Tilt assembly onto 3 ground tips
    bmesh.ops.transform(master_bm, matrix=_tripod_rotation_matrix(), verts=master_bm.verts)

    # Shift pivot so lowest tip rests exactly at Z=0, centered in XY
    coords = [v.co for v in master_bm.verts]
    min_z = min(c.z for c in coords)
    cx = (min(c.x for c in coords) + max(c.x for c in coords)) * 0.5
    cy = (min(c.y for c in coords) + max(c.y for c in coords)) * 0.5
    bmesh.ops.transform(
        master_bm,
        matrix=Matrix.Translation((-cx, -cy, -min_z)),
        verts=master_bm.verts,
    )

    bmesh.ops.recalc_face_normals(master_bm, faces=master_bm.faces)

    mesh = bpy.data.meshes.new("CzechHedgehog_Mesh")
    master_bm.to_mesh(mesh)
    master_bm.free()

    obj = bpy.data.objects.new("CzechHedgehog", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(_create_weathered_steel_material(embed_textures=embed_textures))

    # Smooth + weighted normals for crisp industrial bevels (Blender 5.x safe)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    wn = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    wn.weight = 50
    bpy.ops.object.modifier_apply(modifier=wn.name)

    # Smart UV unwrap
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Apply transforms
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return obj, -min_z


def main() -> None:
    embed_textures = "--embed-textures" in sys.argv
    clean_scene()
    obj, center_height = build_czech_hedgehog(embed_textures=embed_textures)

    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    export_godot_glb(OUTPUT_PATH, export_animations=False)

    tri_count = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dims = obj.dimensions
    manifest = {
        "slug": "czech_hedgehog",
        "source": "procedural_bpy",
        "layer": "Layer 1 Environment",
        "tri_count": tri_count,
        "uv_layers": len(obj.data.uv_layers),
        "dimensions_m": {
            "x": round(dims.x, 4),
            "y": round(dims.z, 4),
            "z": round(dims.y, 4),
        },
        "center_y_m": round(center_height, 4),
        "collision_hint": "3x BoxShape3D aligned to tripod beams (StaticBody3D)",
        "material": "res://assets/models/czech_hedgehog/czech_hedgehog.tres",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(
        f"[OK] Exported {OUTPUT_PATH} | Tris: {tri_count} | "
        f"Dims Godot (X,Y,Z m): {dims.x:.3f} x {dims.z:.3f} x {dims.y:.3f} | "
        f"CenterY: {center_height:.4f}"
    )


if __name__ == "__main__":
    main()
