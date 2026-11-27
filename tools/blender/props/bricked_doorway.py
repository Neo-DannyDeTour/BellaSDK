"""Procedural Bricked Doorway with Stepped Concrete Jamb & Uneven Clay Bricks (2.25m H).

Matches reference /home/dkd/Downloads/hl2_refs/bricked_entrance.png:
- Grounded min_y = 0.0 (bottom of door jamb & brick courses touch floor)
- 1.25m wide x 2.25m tall x ~0.26m deep
- Stepped aged concrete/stone door jamb surround + recessed bricked-up wall
- Proud staggered uneven red clay brick clusters & lower-left rough mortar patch
- 1024x1024 stone jamb + weathered red clay brick PBR atlas, single mesh, <= 1,200 tris

Usage:
    python3 tools/blender/props/bricked_doorway.py --textures
    python3 tools/blender/run.py tools/blender/props/bricked_doorway.py
"""

from __future__ import annotations

import json
import math
import random
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

SLUG: str = "bricked_doorway"
MESH_NAME: str = "BrickedDoorway"
ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / SLUG
GLB_PATH: Path = ASSET_DIR / f"{SLUG}.glb"
TRES_PATH: Path = ASSET_DIR / f"{SLUG}.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / f"{SLUG}_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / f"{SLUG}_normal.png"
ORM_PATH: Path = ASSET_DIR / f"{SLUG}_orm.png"
REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/bricked_entrance.png"

MAT_STONE: Path = REPO_ROOT / "assets" / "materials" / "weathered_concrete" / "textures"
MAT_AGG: Path = REPO_ROOT / "assets" / "materials" / "aggregate_concrete" / "textures"
MAT_BRICK: Path = REPO_ROOT / "assets" / "materials" / "weathered_clay_brick" / "textures"

TEX_SIZE: int = 1024
STONE_SPLIT_U: float = 0.44

TARGET_W: float = 1.25
TARGET_H: float = 2.25


def _generate_pbr_textures() -> None:
    """Build 1024x1024 aged concrete jamb + tiled red clay brick PBR atlas."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    split_px = int(round(TEX_SIZE * STONE_SPLIT_U))
    stone_w = split_px
    brick_w = TEX_SIZE - split_px

    def _load_tiled(path: Path, tiles_x: float, tiles_y: float, out_w: int, out_h: int, mode: str) -> np.ndarray:
        src = Image.open(path).convert(mode)
        sw, sh = src.size
        rep_x = max(1, int(math.ceil(tiles_x)))
        rep_y = max(1, int(math.ceil(tiles_y)))
        tiled = Image.new(mode, (sw * rep_x, sh * rep_y))
        for iy in range(rep_y):
            for ix in range(rep_x):
                tiled.paste(src, (ix * sw, iy * sh))
        cropped = tiled.crop((0, 0, max(1, int(round(sw * tiles_x))), max(1, int(round(sh * tiles_y)))))
        resized = cropped.resize((out_w, out_h), Image.Resampling.BICUBIC)
        return np.array(resized, dtype=np.float32)

    # 1. Aged dark brownish-grey concrete/stone jamb & mortar patch
    st_alb = _load_tiled(MAT_STONE / "weathered_concrete_albedo.png", 1.0, 2.0, stone_w, TEX_SIZE, "RGB")
    st_nrm = _load_tiled(MAT_STONE / "weathered_concrete_normal.png", 1.0, 2.0, stone_w, TEX_SIZE, "RGB")
    st_orm = _load_tiled(MAT_STONE / "weathered_concrete_orm.png", 1.0, 2.0, stone_w, TEX_SIZE, "RGB")

    ag_alb = _load_tiled(MAT_AGG / "aggregate_concrete_albedo.png", 2.0, 4.0, stone_w, TEX_SIZE, "RGB")
    ag_nrm = _load_tiled(MAT_AGG / "aggregate_concrete_normal.png", 2.0, 4.0, stone_w, TEX_SIZE, "RGB")
    ag_orm = _load_tiled(MAT_AGG / "aggregate_concrete_orm.png", 2.0, 4.0, stone_w, TEX_SIZE, "RGB")

    stone_alb = (0.7 * st_alb + 0.3 * ag_alb) * 0.65
    stone_alb[..., 0] *= 1.04
    stone_alb[..., 1] *= 0.98
    stone_alb[..., 2] *= 0.90
    stone_alb_img = Image.fromarray(np.clip(stone_alb, 30, 195).astype(np.uint8), mode="RGB")

    snrm = (0.7 * st_nrm + 0.3 * ag_nrm) / 255.0 * 2.0 - 1.0
    snrm[..., 2] = np.maximum(snrm[..., 2], 0.25)
    slen = np.sqrt(np.sum(snrm * snrm, axis=-1, keepdims=True))
    snrm = snrm / np.maximum(slen, 1e-6)
    stone_nrm_img = Image.fromarray(np.clip((snrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    stone_ao = np.clip(0.7 * st_orm[..., 0] + 0.3 * ag_orm[..., 0], 60, 255).astype(np.uint8)
    stone_rough = np.clip(0.7 * st_orm[..., 1] + 0.3 * ag_orm[..., 1], 185, 248).astype(np.uint8)

    # 2. Uneven mortared red clay bricks (tiled 2.0x3.5 to match real doorway brick scale)
    br_alb = _load_tiled(MAT_BRICK / "weathered_clay_brick_albedo.png", 2.0, 3.5, brick_w, TEX_SIZE, "RGB")
    br_nrm = _load_tiled(MAT_BRICK / "weathered_clay_brick_normal.png", 2.0, 3.5, brick_w, TEX_SIZE, "RGB")
    br_orm = _load_tiled(MAT_BRICK / "weathered_clay_brick_orm.png", 2.0, 3.5, brick_w, TEX_SIZE, "RGB")

    v_coords = 1.0 - np.linspace(0.0, 1.0, TEX_SIZE, dtype=np.float32)[:, None]
    base_damp = np.clip((0.18 - v_coords) / 0.18, 0.0, 1.0) * 0.22
    br_alb *= (1.0 - base_damp[..., None])
    brick_alb_img = Image.fromarray(np.clip(br_alb, 32, 225).astype(np.uint8), mode="RGB")

    bnrm = br_nrm / 255.0 * 2.0 - 1.0
    bnrm[..., 2] = np.maximum(bnrm[..., 2], 0.25)
    blen = np.sqrt(np.sum(bnrm * bnrm, axis=-1, keepdims=True))
    bnrm = bnrm / np.maximum(blen, 1e-6)
    brick_nrm_img = Image.fromarray(np.clip((bnrm * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    brick_ao = np.clip(br_orm[..., 0], 60, 255).astype(np.uint8)
    brick_rough = np.clip(br_orm[..., 1], 185, 248).astype(np.uint8)

    def _stitch(left: Image.Image, right: Image.Image, mode: str) -> Image.Image:
        canvas = Image.new(mode, (TEX_SIZE, TEX_SIZE))
        canvas.paste(left, (0, 0))
        canvas.paste(right, (split_px, 0))
        return canvas

    albedo_atlas = _stitch(stone_alb_img, brick_alb_img, "RGB")
    normal_atlas = _stitch(stone_nrm_img, brick_nrm_img, "RGB")
    ao_atlas = _stitch(Image.fromarray(stone_ao, mode="L"), Image.fromarray(brick_ao, mode="L"), "L")
    rough_atlas = _stitch(Image.fromarray(stone_rough, mode="L"), Image.fromarray(brick_rough, mode="L"), "L")

    ao_tmp = ASSET_DIR / "_tmp_ao.png"
    rough_tmp = ASSET_DIR / "_tmp_rough.png"
    albedo_atlas.save(ALBEDO_PATH, format="PNG")
    normal_atlas.save(NORMAL_PATH, format="PNG")
    ao_atlas.save(ao_tmp, format="PNG")
    rough_atlas.save(rough_tmp, format="PNG")

    process_pbr.pack_orm(ao_tmp, rough_tmp, "0.0", ORM_PATH, target_size=(TEX_SIZE, TEX_SIZE))
    ao_tmp.unlink(missing_ok=True)
    rough_tmp.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name=f"M_{MESH_NAME}",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated {TEX_SIZE}x{TEX_SIZE} maps + {TRES_PATH.name}")


def _build_mesh_and_export() -> None:
    """Build bricked_doorway geometry in Blender, UV-map jamb/brick atlas, and export GLB."""
    import bmesh
    import bpy
    from mathutils import Euler, Matrix, Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()
    bm = bmesh.new()
    rng = random.Random(225)

    def tag_verts(verts: list[bmesh.types.BMVert], tag: int) -> None:
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = tag

    def add_box(center: Vector, size: Vector, tag: int, tilt_deg: tuple[float, float, float] = (0.0, 0.0, 0.0)) -> None:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        rot = Euler((math.radians(tilt_deg[0]), math.radians(tilt_deg[1]), math.radians(tilt_deg[2])), "XYZ").to_matrix().to_4x4()
        xform = Matrix.Translation(center) @ rot @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        tag_verts(verts, tag)

    # Outer doorway: 1.25m W (X: -0.625..+0.625), 2.25m H (Z: 0.0..2.25), ~0.26m D (Y: -0.13..+0.13)
    # 1. Stepped molded concrete/stone door jamb surround (tag=0 stone)
    outer_jamb_w = 0.115
    inner_jamb_w = 0.055
    outer_d = 0.26
    inner_d = 0.22
    opening_w = TARGET_W - 2.0 * outer_jamb_w  # 1.02m
    lintel_h = 0.125
    opening_h = TARGET_H - lintel_h  # 2.125m

    # Left & Right outer jamb posts (grounded at z=0.0, stop cleanly beneath lintel to avoid z-fighting)
    for sx in (-1.0, 1.0):
        add_box(Vector((sx * (TARGET_W * 0.5 - outer_jamb_w * 0.5), 0.0, opening_h * 0.5)), Vector((outer_jamb_w, outer_d, opening_h)), tag=0)
        # Stepped inner molding trim projecting slightly inward, stopping beneath inner header
        inner_post_h = opening_h - 0.055
        add_box(
            Vector((sx * (opening_w * 0.5 - inner_jamb_w * 0.35), 0.0, inner_post_h * 0.5)),
            Vector((inner_jamb_w, inner_d, inner_post_h)),
            tag=0,
        )

    # Top outer lintel + stepped inner header trim
    add_box(Vector((0.0, 0.0, TARGET_H - lintel_h * 0.5)), Vector((TARGET_W, outer_d, lintel_h)), tag=0)
    add_box(Vector((0.0, 0.0, opening_h - 0.0275)), Vector((opening_w, inner_d, 0.055)), tag=0)

    # 2. Recessed main bricked-up infill wall (seated 0.055m behind front jamb face, tag=1 brick)
    wall_d = 0.14
    wall_y = 0.015  # recessed relative to front -0.13 face
    add_box(Vector((0.0, wall_y, opening_h * 0.5)), Vector((opening_w - 0.02, wall_d, opening_h)), tag=1)

    # 3. Proud staggered uneven red clay brick clusters on both faces + rough mortar patch (matching ref)
    brick_w = 0.215
    brick_h = 0.072
    brick_d = 0.036
    # Deterministic uneven relief clusters across the opening
    brick_spots = [
        (-0.32, 0.18, -0.8, 1.2), (+0.18, 0.22, 0.6, -1.0), (-0.08, 0.34, 1.1, 0.8),
        (+0.31, 0.44, -1.2, 1.4), (-0.28, 0.58, 0.7, -0.7), (+0.04, 0.66, -0.9, 1.1),
        (+0.28, 0.78, 1.3, -1.2), (-0.12, 0.92, -0.6, 0.9), (+0.16, 1.04, 0.8, -1.4),
        (-0.33, 1.15, 1.0, 1.0), (+0.02, 1.26, -1.3, -0.8), (+0.29, 1.36, 0.9, 1.2),
        (-0.24, 1.48, -0.7, -1.1), (+0.12, 1.58, 1.2, 0.7), (-0.05, 1.72, -1.0, 1.3),
        (+0.27, 1.82, 0.7, -0.9), (-0.30, 1.94, 1.4, 0.8), (+0.06, 2.00, -0.8, -1.2),
    ]
    for bx, bz, rx, rz in brick_spots:
        # Front face proud uneven brick
        add_box(
            Vector((bx, wall_y - wall_d * 0.5 + rng.uniform(-0.010, 0.002), bz)),
            Vector((brick_w * rng.uniform(0.85, 1.08), brick_d, brick_h * rng.uniform(0.88, 1.06))),
            tag=1,
            tilt_deg=(rx, rng.uniform(-1.2, 1.2), rz),
        )
        # Back face matching brick relief so back angle is equally detailed
        add_box(
            Vector((-bx * 0.9, wall_y + wall_d * 0.5 + rng.uniform(-0.002, 0.010), bz + 0.04)),
            Vector((brick_w * rng.uniform(0.85, 1.08), brick_d, brick_h * rng.uniform(0.88, 1.06))),
            tag=1,
            tilt_deg=(-rx, rng.uniform(-1.2, 1.2), -rz),
        )

    # Lower-left rough mortar patch block matching reference
    add_box(Vector((-0.26, wall_y - wall_d * 0.5 - 0.008, 0.86)), Vector((0.36, 0.028, 0.24)), tag=0, tilt_deg=(0.5, 0.8, -0.6))
    add_box(Vector((+0.24, wall_y + wall_d * 0.5 + 0.008, 0.94)), Vector((0.32, 0.026, 0.20)), tag=0, tilt_deg=(-0.5, -0.7, 0.5))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.faces.ensure_lookup_table()
    stone_faces = [f.index for f in bm.faces if f.material_index == 0]
    brick_faces = [f.index for f in bm.faces if f.material_index == 1]
    for f in bm.faces:
        f.material_index = 0

    mesh = bpy.data.meshes.new(MESH_NAME)
    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(name=f"M_{MESH_NAME}")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    img_alb = bpy.data.images.load(str(ALBEDO_PATH.resolve()), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    img_orm = bpy.data.images.load(str(ORM_PATH.resolve()), check_existing=True)
    img_orm.colorspace_settings.name = "Non-Color"
    tex_orm.image = img_orm
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    img_nrm = bpy.data.images.load(str(NORMAL_PATH.resolve()), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm
    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.inputs["Strength"].default_value = 0.9
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new(MESH_NAME, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")
    uv_data = mesh.uv_layers.active.data

    # Planar/box UV mapping aligned with world orientation so brick courses stay strictly horizontal!
    def _box_uv(face_indices: list[int], u_min: float, u_max: float, span_u: float, span_v: float) -> None:
        for idx in face_indices:
            poly = mesh.polygons[idx]
            n = poly.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for li in poly.loop_indices:
                vco = mesh.vertices[mesh.loops[li].vertex_index].co
                if ay >= ax and ay >= az:
                    lu = (vco.x + span_u * 0.5) / span_u
                    lv = vco.z / span_v
                elif ax >= ay and ax >= az:
                    lu = (vco.y + 0.15) / 0.30
                    lv = vco.z / span_v
                else:
                    lu = (vco.x + span_u * 0.5) / span_u
                    lv = (vco.y + 0.15) / 0.30
                lu = max(0.02, min(0.98, lu))
                lv = max(0.02, min(0.98, lv))
                uv_data[li].uv = (u_min + lu * (u_max - u_min), lv)

    _box_uv(stone_faces, 0.015, STONE_SPLIT_U - 0.015, TARGET_W, TARGET_H)
    _box_uv(brick_faces, STONE_SPLIT_U + 0.015, 0.985, opening_w, opening_h)

    # Center X/Y=0, min_z=0.0
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    cx = (min(xs) + max(xs)) * 0.5
    cy = (min(ys) + max(ys)) * 0.5
    z0 = min(zs)
    for v in mesh.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= z0
    mesh.update()

    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    dims_godot = [
        round(max(xs) - min(xs), 4),
        round(max(zs) - min(zs), 4),
        round(max(ys) - min(ys), 4),
    ]

    export_godot_glb(GLB_PATH, export_animations=False, export_morph=False)

    manifest = {
        "prop_slug": SLUG,
        "tri_count": tri_count,
        "tri_budget": 1200,
        "uv_layers": len(mesh.uv_layers),
        "min_y": round(min(zs), 4),
        "dimensions_m": dims_godot,
        "layer": "Layer 1 Environment",
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "ref_image": REF_IMAGE,
        "reference_image": REF_IMAGE,
        "material": f"res://assets/models/{SLUG}/{SLUG}.tres",
        "mesh": f"res://assets/models/{SLUG}/{SLUG}.glb",
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"BUILT_{SLUG.upper()}:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
