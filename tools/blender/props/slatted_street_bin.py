"""Procedural Slatted Concrete Street Bin with Crinkled Polyethylene Liner (0.78m).

Matches reference /home/dkd/Desktop/Refs/IMG_20261125_163031.jpg:
- Grounded square concrete footing pad (min_y = 0 at origin)
- Square concrete housing with 2 tiers of 5 vertical slots on all 4 sides
- Overhanging beveled concrete top collar
- Recessed crinkled dark polyethylene trash-bag liner visible through slots & throat
- 2048x2048 PBR maps derived from real aggregate/weathered concrete + crinkled poly folds

Usage:
    python3 tools/blender/props/slatted_street_bin.py --textures
    python3 tools/blender/run.py tools/blender/props/slatted_street_bin.py
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "slatted_street_bin"
GLB_PATH: Path = ASSET_DIR / "slatted_street_bin.glb"
TRES_PATH: Path = ASSET_DIR / "slatted_street_bin.tres"
MANIFEST_PATH: Path = ASSET_DIR / "asset_manifest.json"
ALBEDO_PATH: Path = ASSET_DIR / "slatted_street_bin_albedo.png"
NORMAL_PATH: Path = ASSET_DIR / "slatted_street_bin_normal.png"
ORM_PATH: Path = ASSET_DIR / "slatted_street_bin_orm.png"
REF_IMAGE: str = "/home/dkd/Desktop/Refs/IMG_20261125_163031.jpg"

MAT_WEATHERED_CONCRETE: Path = REPO_ROOT / "assets" / "materials" / "weathered_concrete" / "textures"
MAT_AGGREGATE_CONCRETE: Path = REPO_ROOT / "assets" / "materials" / "aggregate_concrete" / "textures"

# UV atlas split (2048x2048):
# U in [0.0, STONE_SPLIT_U) = cast aggregate concrete (V bands: plinth / shaft / collar)
# U in [STONE_SPLIT_U, 1.0] = crinkled dark polyethylene trash-bag liner
TEX_SIZE: int = 2048
STONE_SPLIT_U: float = 0.68

# Target height = 0.78m (Blender Z: 0.0 -> 0.78m, Godot Y: 0.0 -> 0.78m)
TOTAL_HEIGHT: float = 0.78
PLINTH_W: float = 0.42
PLINTH_H: float = 0.045

SHAFT_OUTER_W: float = 0.36
SHAFT_WALL_T: float = 0.030
SHAFT_INNER_W: float = SHAFT_OUTER_W - 2.0 * SHAFT_WALL_T  # 0.30m
CORNER_PIER_W: float = 0.052

BOT_BAND_H: float = 0.050
TIER_H: float = 0.250
MID_BAND_H: float = 0.055
TOP_BAND_H: float = 0.045
COLLAR_Z0: float = PLINTH_H + BOT_BAND_H + TIER_H + MID_BAND_H + TIER_H + TOP_BAND_H  # 0.695m
COLLAR_OUTER_W: float = 0.425
COLLAR_INNER_W: float = 0.295

SLAT_COUNT: int = 4  # 4 slats divide 5 vertical slots per tier per face
SLAT_W: float = 0.029


def _generate_pbr_textures() -> None:
    """Build 2048x2048 concrete + crinkled polyethylene PBR atlas maps."""
    import numpy as np
    from PIL import Image

    pbr_dir = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts"
    if str(pbr_dir) not in sys.path:
        sys.path.insert(0, str(pbr_dir))
    import process_pbr  # noqa: E402

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    split_px = int(round(TEX_SIZE * STONE_SPLIT_U))
    stone_w = split_px
    liner_w = TEX_SIZE - split_px

    def _load_tiled(path: Path, tiles_x: float, tiles_y: float, out_w: int, out_h: int, mode: str) -> np.ndarray:
        src = Image.open(path).convert(mode)
        sw, sh = src.size
        rep_x = max(1, int(math.ceil(tiles_x)))
        rep_y = max(1, int(math.ceil(tiles_y)))
        tiled = Image.new(mode, (sw * rep_x, sh * rep_y))
        for iy in range(rep_y):
            for ix in range(rep_x):
                tiled.paste(src, (ix * sw, iy * sh))
        crop_w = max(1, int(round(sw * tiles_x)))
        crop_h = max(1, int(round(sh * tiles_y)))
        cropped = tiled.crop((0, 0, crop_w, crop_h))
        resized = cropped.resize((out_w, out_h), Image.Resampling.BICUBIC)
        return np.array(resized, dtype=np.float32)

    # 1. Cast Aggregate Concrete (weathered_concrete + fine-tiled aggregate_concrete)
    wc_alb = _load_tiled(MAT_WEATHERED_CONCRETE / "weathered_concrete_albedo.png", 1.35, 2.0, stone_w, TEX_SIZE, "RGB")
    wc_nrm = _load_tiled(MAT_WEATHERED_CONCRETE / "weathered_concrete_normal.png", 1.35, 2.0, stone_w, TEX_SIZE, "RGB")
    wc_orm = _load_tiled(MAT_WEATHERED_CONCRETE / "weathered_concrete_orm.png", 1.35, 2.0, stone_w, TEX_SIZE, "RGB")

    ag_alb = _load_tiled(MAT_AGGREGATE_CONCRETE / "aggregate_concrete_albedo.png", 4.0, 6.0, stone_w, TEX_SIZE, "RGB")
    ag_nrm = _load_tiled(MAT_AGGREGATE_CONCRETE / "aggregate_concrete_normal.png", 4.0, 6.0, stone_w, TEX_SIZE, "RGB")
    ag_orm = _load_tiled(MAT_AGGREGATE_CONCRETE / "aggregate_concrete_orm.png", 4.0, 6.0, stone_w, TEX_SIZE, "RGB")

    # Blend 76% weathered concrete + 24% fine aggregate concrete for cast concrete pores & grit
    stone_alb = 0.76 * wc_alb + 0.24 * ag_alb
    # Warm sand-gray concrete tint matching IMG_20261125_163031.jpg
    stone_alb[..., 0] *= 0.99
    stone_alb[..., 1] *= 0.97
    stone_alb[..., 2] *= 0.92

    # Height-band weathering in UV V space (image y=0 is top V=1.0, y=TEX_SIZE is bottom V=0.0):
    # V in [0.015, 0.165] = plinth (bottom dirt/soil splash)
    # V in [0.185, 0.785] = shaft (clean cast concrete + subtle lower splash)
    # V in [0.805, 0.985] = top collar (subtle rim grime)
    v_coords = 1.0 - np.linspace(0.0, 1.0, TEX_SIZE, dtype=np.float32)[:, None]

    # Plinth damp dirt & soil tint (V <= 0.17)
    plinth_mask = np.clip((0.175 - v_coords) / 0.04, 0.0, 1.0)
    # Subtle gradient within plinth + lower shaft splash
    dirt_grad = np.clip((0.26 - v_coords) / 0.24, 0.0, 1.0)
    dirt_factor = np.clip(0.18 * plinth_mask + 0.10 * dirt_grad, 0.0, 0.28)
    stone_alb[..., 0] *= (1.0 - dirt_factor * 0.75)
    stone_alb[..., 1] *= (1.0 - dirt_factor * 0.85)
    stone_alb[..., 2] *= (1.0 - dirt_factor * 1.00)

    # Subtle top collar rim grime (V >= 0.80)
    collar_grime = np.clip((v_coords - 0.80) / 0.18, 0.0, 1.0) * 0.08
    stone_alb *= (1.0 - collar_grime[..., None])

    stone_alb_img = Image.fromarray(np.clip(stone_alb, 30, 240).astype(np.uint8), mode="RGB")

    # Blend photogrammetry normal maps cleanly and renormalize
    nrm_mix = (0.75 * wc_nrm + 0.25 * ag_nrm) / 255.0 * 2.0 - 1.0
    nrm_mix[..., 2] = np.maximum(nrm_mix[..., 2], 0.25)
    nrm_len = np.sqrt(np.sum(nrm_mix * nrm_mix, axis=-1, keepdims=True))
    nrm_mix = nrm_mix / np.maximum(nrm_len, 1e-6)
    stone_nrm_img = Image.fromarray(np.clip((nrm_mix * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8), mode="RGB")

    stone_ao = np.clip(0.75 * wc_orm[..., 0] + 0.25 * ag_orm[..., 0] - dirt_factor * 40.0, 50, 255).astype(np.uint8)
    stone_rough = np.clip(0.75 * wc_orm[..., 1] + 0.25 * ag_orm[..., 1], 175, 248).astype(np.uint8)
    stone_ao_img = Image.fromarray(stone_ao, mode="L")
    stone_rough_img = Image.fromarray(stone_rough, mode="L")

    # 2. Crinkled Dark Polyethylene Trash-Bag Liner (Voronoi facet ridges + sharp fold creases)
    rng = np.random.default_rng(163031)
    yy, xx = np.mgrid[0:TEX_SIZE, 0:liner_w].astype(np.float32)
    xx_n = xx / float(liner_w)
    yy_n = yy / float(TEX_SIZE)

    def _voronoi_folds(n_pts: int, weight_aniso_y: float) -> tuple[np.ndarray, np.ndarray]:
        pts_x = rng.random(n_pts, dtype=np.float32)
        pts_y = rng.random(n_pts, dtype=np.float32)
        d1 = np.full((TEX_SIZE, liner_w), 1e9, dtype=np.float32)
        d2 = np.full((TEX_SIZE, liner_w), 1e9, dtype=np.float32)
        for px, py in zip(pts_x, pts_y):
            dx = np.abs(xx_n - px)
            dy = np.abs(yy_n - py) * weight_aniso_y
            dist = np.sqrt(dx * dx + dy * dy)
            mask1 = dist < d1
            d2 = np.where(mask1, d1, np.minimum(d2, dist))
            d1 = np.where(mask1, dist, d1)
        ridge = np.clip((d2 - d1) * 14.0, 0.0, 1.0)
        return ridge, d1

    ridge_coarse, d_coarse = _voronoi_folds(26, weight_aniso_y=0.65)
    ridge_med, _ = _voronoi_folds(75, weight_aniso_y=0.80)
    ridge_fine, _ = _voronoi_folds(190, weight_aniso_y=1.15)

    # Smooth facet domes + sharp V-crease folds typical of crumpled black LDPE/HDPE film
    poly_height = (
        0.48 * np.clip(ridge_coarse, 0.0, 1.0)
        + 0.34 * np.clip(ridge_med, 0.0, 1.0)
        + 0.18 * ridge_fine
        - 0.15 * np.clip(d_coarse * 3.5, 0.0, 1.0)
    )
    p_min, p_max = float(np.percentile(poly_height, 1)), float(np.percentile(poly_height, 99))
    poly_h = np.clip((poly_height - p_min) / max(p_max - p_min, 1e-5), 0.0, 1.0)

    # Dark charcoal polyethylene albedo (sRGB 30..78) with crisp angular fold ridges
    crest = np.clip(1.0 - ridge_coarse, 0.0, 1.0) ** 3.0
    med_crest = np.clip(1.0 - ridge_med, 0.0, 1.0) ** 3.2
    poly_lum = 31.0 + poly_h * 20.0 + crest * 22.0 + med_crest * 14.0
    poly_r = np.clip(poly_lum * 0.96, 30, 240)
    poly_g = np.clip(poly_lum * 0.98, 30, 240)
    poly_b = np.clip(poly_lum * 1.05, 30, 240)
    poly_alb_img = Image.fromarray(np.stack([poly_r, poly_g, poly_b], axis=-1).astype(np.uint8), mode="RGB")

    # Sharp fold tangent normals (OpenGL +Y) directly from poly_h
    dx_p = np.gradient(poly_h, axis=1) * 16.0
    dy_p = np.gradient(poly_h, axis=0) * 16.0
    dz_p = np.ones_like(poly_h)
    norm_p = np.sqrt(dx_p * dx_p + dy_p * dy_p + dz_p * dz_p)
    p_nrm_rgb = np.zeros((TEX_SIZE, liner_w, 3), dtype=np.uint8)
    p_nrm_rgb[..., 0] = np.clip(((dx_p / norm_p) * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    p_nrm_rgb[..., 1] = np.clip(((-dy_p / norm_p) * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    p_nrm_rgb[..., 2] = np.clip(((dz_p / norm_p) * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    poly_nrm_img = Image.fromarray(p_nrm_rgb, mode="RGB")

    # Semi-gloss polyethylene roughness strictly within 0.28..0.42 (sRGB 71..107)
    poly_rough = np.clip(0.41 - poly_h * 0.12 - crest * 0.03, 0.28, 0.42)
    poly_ao = np.clip(0.55 + poly_h * 0.45, 0.45, 1.0)
    poly_ao_img = Image.fromarray((poly_ao * 255.0).astype(np.uint8), mode="L")
    poly_rough_img = Image.fromarray((poly_rough * 255.0).astype(np.uint8), mode="L")

    # 3. Stitch left (stone) + right (polyethylene liner) into 2048x2048 atlas
    def _stitch_lr(left: Image.Image, right: Image.Image, mode: str) -> Image.Image:
        canvas = Image.new(mode, (TEX_SIZE, TEX_SIZE))
        canvas.paste(left, (0, 0))
        canvas.paste(right, (split_px, 0))
        return canvas

    albedo_atlas = _stitch_lr(stone_alb_img, poly_alb_img, "RGB")
    normal_atlas = _stitch_lr(stone_nrm_img, poly_nrm_img, "RGB")
    ao_atlas = _stitch_lr(stone_ao_img, poly_ao_img, "L")
    rough_atlas = _stitch_lr(stone_rough_img, poly_rough_img, "L")

    ao_tmp = ASSET_DIR / "_tmp_ao.png"
    rough_tmp = ASSET_DIR / "_tmp_rough.png"
    albedo_atlas.save(ALBEDO_PATH, format="PNG")
    normal_atlas.save(NORMAL_PATH, format="PNG")
    ao_atlas.save(ao_tmp, format="PNG")
    rough_atlas.save(rough_tmp, format="PNG")

    # Concrete + polyethylene liner are both dielectric (metallic = 0.0)
    process_pbr.pack_orm(ao_tmp, rough_tmp, "0.0", ORM_PATH, target_size=(TEX_SIZE, TEX_SIZE))
    ao_tmp.unlink(missing_ok=True)
    rough_tmp.unlink(missing_ok=True)

    process_pbr.generate_godot_tres(
        material_name="M_SlattedStreetBin",
        albedo_path=ALBEDO_PATH,
        normal_path=NORMAL_PATH,
        orm_path=ORM_PATH,
        height_path=None,
        output_tres=TRES_PATH,
        triplanar=False,
    )
    print(f"[Textures] Generated 2048x2048 {ALBEDO_PATH.name}, {NORMAL_PATH.name}, {ORM_PATH.name}, {TRES_PATH.name}")


def _build_mesh_and_export() -> None:
    """Build slatted street bin geometry in Blender, UV-pack stone+liner bands, and export GLB."""
    import bmesh
    import bpy
    from mathutils import Matrix, Vector

    from tools.blender.common.exporter import clean_scene, export_godot_glb

    if not (ALBEDO_PATH.is_file() and NORMAL_PATH.is_file() and ORM_PATH.is_file() and TRES_PATH.is_file()):
        subprocess.run(
            ["/usr/bin/python3", str(Path(__file__).resolve()), "--textures"],
            check=True,
        )

    clean_scene()

    def add_box(bm: bmesh.types.BMesh, center: Vector, size: Vector, tag: int) -> None:
        ret = bmesh.ops.create_cube(bm, size=1.0)
        verts = ret["verts"]
        xform = Matrix.Translation(center) @ Matrix.Diagonal((size.x, size.y, size.z, 1.0))
        bmesh.ops.transform(bm, matrix=xform, verts=verts)
        vset = set(verts)
        for f in bm.faces:
            if all(v in vset for v in f.verts):
                f.material_index = tag

    def add_square_ring(
        bm: bmesh.types.BMesh,
        z0: float,
        z1: float,
        outer_w: float,
        inner_w: float,
        tag: int,
    ) -> None:
        ho = outer_w * 0.5
        hi = inner_w * 0.5
        mid_z = (z0 + z1) * 0.5
        h = z1 - z0
        wall_t = ho - hi
        add_box(bm, Vector((0.0, -(hi + wall_t * 0.5), mid_z)), Vector((outer_w, wall_t, h)), tag)
        add_box(bm, Vector((0.0, +(hi + wall_t * 0.5), mid_z)), Vector((outer_w, wall_t, h)), tag)
        add_box(bm, Vector((-(hi + wall_t * 0.5), 0.0, mid_z)), Vector((wall_t, inner_w, h)), tag)
        add_box(bm, Vector((+(hi + wall_t * 0.5), 0.0, mid_z)), Vector((wall_t, inner_w, h)), tag)

    def add_beveled_collar(bm: bmesh.types.BMesh, z0: float, z1: float, tag: int) -> None:
        ho_shaft = SHAFT_OUTER_W * 0.5
        ho_max = COLLAR_OUTER_W * 0.5
        ho_top = ho_max - 0.012
        hi_shaft = SHAFT_INNER_W * 0.5
        hi_throat = COLLAR_INNER_W * 0.5
        hi_top = hi_throat + 0.012

        rings_spec = [
            (ho_shaft, hi_shaft, z0),
            (ho_max, hi_throat, z0 + 0.022),
            (ho_max, hi_throat, z1 - 0.014),
            (ho_top, hi_top, z1),
        ]
        outer_loops: list[list[bmesh.types.BMVert]] = []
        inner_loops: list[list[bmesh.types.BMVert]] = []
        for ho, hi, z in rings_spec:
            outer_loops.append([
                bm.verts.new((-ho, -ho, z)),
                bm.verts.new((+ho, -ho, z)),
                bm.verts.new((+ho, +ho, z)),
                bm.verts.new((-ho, +ho, z)),
            ])
            inner_loops.append([
                bm.verts.new((-hi, -hi, z)),
                bm.verts.new((+hi, -hi, z)),
                bm.verts.new((+hi, +hi, z)),
                bm.verts.new((-hi, +hi, z)),
            ])

        faces: list[bmesh.types.BMFace] = []
        for r in range(len(rings_spec) - 1):
            for i in range(4):
                j = (i + 1) % 4
                faces.append(bm.faces.new((
                    outer_loops[r][i], outer_loops[r][j],
                    outer_loops[r + 1][j], outer_loops[r + 1][i],
                )))
                faces.append(bm.faces.new((
                    inner_loops[r][j], inner_loops[r][i],
                    inner_loops[r + 1][i], inner_loops[r + 1][j],
                )))

        for i in range(4):
            j = (i + 1) % 4
            faces.append(bm.faces.new((
                inner_loops[0][i], inner_loops[0][j],
                outer_loops[0][j], outer_loops[0][i],
            )))
            faces.append(bm.faces.new((
                outer_loops[-1][i], outer_loops[-1][j],
                inner_loops[-1][j], inner_loops[-1][i],
            )))

        for f in faces:
            f.material_index = tag

    def add_tapered_plinth(bm: bmesh.types.BMesh, tag: int) -> None:
        hb = PLINTH_W * 0.5
        ht = (PLINTH_W - 0.016) * 0.5
        v_bot = [
            bm.verts.new((-hb, -hb, 0.0)),
            bm.verts.new((+hb, -hb, 0.0)),
            bm.verts.new((+hb, +hb, 0.0)),
            bm.verts.new((-hb, +hb, 0.0)),
        ]
        v_top = [
            bm.verts.new((-ht, -ht, PLINTH_H)),
            bm.verts.new((+ht, -ht, PLINTH_H)),
            bm.verts.new((+ht, +ht, PLINTH_H)),
            bm.verts.new((-ht, +ht, PLINTH_H)),
        ]
        faces = [
            bm.faces.new(list(reversed(v_bot))),
            bm.faces.new(v_top),
        ]
        for i in range(4):
            j = (i + 1) % 4
            faces.append(bm.faces.new((v_bot[i], v_bot[j], v_top[j], v_top[i])))
        for f in faces:
            f.material_index = tag

    def add_poly_liner(bm: bmesh.types.BMesh, tag: int) -> None:
        z_bot = PLINTH_H + 0.010
        z_top = COLLAR_Z0 + 0.056
        outer_w = SHAFT_INNER_W - 0.014
        inner_w = outer_w - 0.016
        floor_h = 0.012
        add_box(bm, Vector((0.0, 0.0, z_bot + floor_h * 0.5)), Vector((outer_w, outer_w, floor_h)), tag)
        add_square_ring(bm, z_bot + floor_h, z_top, outer_w, inner_w, tag)
        add_square_ring(bm, z_top - 0.014, z_top, outer_w + 0.010, inner_w, tag)

    bm = bmesh.new()

    # Tags: 0=plinth, 1=shaft, 2=collar, 3=polyethylene liner
    add_tapered_plinth(bm, tag=0)

    z = PLINTH_H
    add_square_ring(bm, z, z + BOT_BAND_H, SHAFT_OUTER_W, SHAFT_INNER_W, tag=1)
    z += BOT_BAND_H

    pier_off = SHAFT_OUTER_W * 0.5 - CORNER_PIER_W * 0.5
    wall_mid = SHAFT_OUTER_W * 0.5 - SHAFT_WALL_T * 0.5
    clear_span = SHAFT_OUTER_W - 2.0 * CORNER_PIER_W
    slot_w = (clear_span - SLAT_COUNT * SLAT_W) / float(SLAT_COUNT + 1)
    slat_centers = [
        -clear_span * 0.5 + (i + 1) * slot_w + (i + 0.5) * SLAT_W
        for i in range(SLAT_COUNT)
    ]

    for tier_idx in range(2):
        tier_z_mid = z + TIER_H * 0.5
        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                add_box(
                    bm,
                    Vector((sx * pier_off, sy * pier_off, tier_z_mid)),
                    Vector((CORNER_PIER_W, CORNER_PIER_W, TIER_H)),
                    tag=1,
                )
        for u in slat_centers:
            for sign in (-1.0, 1.0):
                add_box(
                    bm,
                    Vector((u, sign * wall_mid, tier_z_mid)),
                    Vector((SLAT_W, SHAFT_WALL_T, TIER_H)),
                    tag=1,
                )
                add_box(
                    bm,
                    Vector((sign * wall_mid, u, tier_z_mid)),
                    Vector((SHAFT_WALL_T, SLAT_W, TIER_H)),
                    tag=1,
                )
        z += TIER_H
        if tier_idx == 0:
            add_square_ring(bm, z, z + MID_BAND_H, SHAFT_OUTER_W, SHAFT_INNER_W, tag=1)
            z += MID_BAND_H

    add_square_ring(bm, z, z + TOP_BAND_H, SHAFT_OUTER_W, SHAFT_INNER_W, tag=1)
    z += TOP_BAND_H

    add_beveled_collar(bm, z, TOTAL_HEIGHT, tag=2)
    add_poly_liner(bm, tag=3)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    bm.faces.ensure_lookup_table()
    plinth_faces = [f.index for f in bm.faces if f.material_index == 0]
    shaft_faces = [f.index for f in bm.faces if f.material_index == 1]
    collar_faces = [f.index for f in bm.faces if f.material_index == 2]
    liner_faces = [f.index for f in bm.faces if f.material_index == 3]
    for f in bm.faces:
        f.material_index = 0

    mesh = bpy.data.meshes.new("SlattedStreetBin")
    bm.to_mesh(mesh)
    bm.free()

    mat = bpy.data.materials.new(name="M_SlattedStreetBin")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (180, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.location = (-380, 260)
    img_alb = bpy.data.images.load(str(ALBEDO_PATH.resolve()), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

    tex_orm = nt.nodes.new("ShaderNodeTexImage")
    tex_orm.location = (-380, 0)
    img_orm = bpy.data.images.load(str(ORM_PATH.resolve()), check_existing=True)
    img_orm.colorspace_settings.name = "Non-Color"
    tex_orm.image = img_orm

    sep = nt.nodes.new("ShaderNodeSeparateColor")
    sep.location = (-120, 0)
    nt.links.new(tex_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-380, -260)
    img_nrm = bpy.data.images.load(str(NORMAL_PATH.resolve()), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm

    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-120, -260)
    nrm_node.inputs["Strength"].default_value = 0.85
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new("SlattedStreetBin", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    mesh.uv_layers.new(name="UVMap")

    def _unwrap_region(
        face_indices: list[int],
        u_min: float,
        u_max: float,
        v_min: float,
        v_max: float,
    ) -> None:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_mode(type="FACE")
        bpy.ops.mesh.select_all(action="DESELECT")
        bpy.ops.object.mode_set(mode="OBJECT")
        for idx in face_indices:
            mesh.polygons[idx].select = True
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.015)
        bpy.ops.object.mode_set(mode="OBJECT")

        uv_data = mesh.uv_layers.active.data
        u_vals: list[float] = []
        v_vals: list[float] = []
        for idx in face_indices:
            for li in mesh.polygons[idx].loop_indices:
                uv = uv_data[li].uv
                u_vals.append(uv.x)
                v_vals.append(uv.y)
        cur_u0, cur_u1 = min(u_vals), max(u_vals)
        cur_v0, cur_v1 = min(v_vals), max(v_vals)
        du = max(cur_u1 - cur_u0, 1e-6)
        dv = max(cur_v1 - cur_v0, 1e-6)
        for idx in face_indices:
            for li in mesh.polygons[idx].loop_indices:
                uv = uv_data[li].uv
                uv.x = u_min + ((uv.x - cur_u0) / du) * (u_max - u_min)
                uv.y = v_min + ((uv.y - cur_v0) / dv) * (v_max - v_min)

    _unwrap_region(plinth_faces, 0.015, STONE_SPLIT_U - 0.015, 0.015, 0.165)
    _unwrap_region(shaft_faces, 0.015, STONE_SPLIT_U - 0.015, 0.185, 0.785)
    _unwrap_region(collar_faces, 0.015, STONE_SPLIT_U - 0.015, 0.805, 0.985)
    _unwrap_region(liner_faces, STONE_SPLIT_U + 0.015, 0.985, 0.015, 0.985)

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
        "prop_slug": "slatted_street_bin",
        "tri_count": tri_count,
        "uv_layers": len(mesh.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 3 Interactive",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "reference_image": REF_IMAGE,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("BUILT_SLATTED_STREET_BIN:", json.dumps(manifest, indent=2))


def main() -> None:
    if "--textures" in sys.argv:
        _generate_pbr_textures()
    else:
        _build_mesh_and_export()


if __name__ == "__main__":
    main()
