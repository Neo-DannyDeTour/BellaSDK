"""Procedural Concrete Ribbed Street Planter (Chamfered Square, 0.48m tall).

Reference: /home/dkd/Desktop/Refs/IMG_20261125_160414.jpg

Run headless:
    python3 tools/blender/run.py tools/blender/props/concrete_ribbed_planter.py
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "concrete_ribbed_planter"
SLUG: str = "concrete_ribbed_planter"
REF_IMAGE: str = "/home/dkd/Desktop/Refs/IMG_20261125_160414.jpg"
SOIL_REF_IMAGE: Path = Path("/home/dkd/Desktop/Refs/IMG_20261125_161224.jpg")
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"

MAT_WEATHERED: Path = REPO_ROOT / "assets" / "materials" / "weathered_concrete" / "textures"
MAT_PEELING: Path = REPO_ROOT / "assets" / "materials" / "peeling_plaster_wall" / "textures"
MAT_STAINED: Path = REPO_ROOT / "assets" / "materials" / "factory_stained_concrete" / "textures"

TEX_SIZE: int = 2048
TARGET_HEIGHT: float = 0.48
BOT_HALF_W: float = 0.38
TOP_HALF_W: float = 0.41
CHAMFER_RATIO: float = 0.45  # Wide chamfered corners matching ref
WALL_THICK: float = 0.095
POCKET_DEPTH: float = 0.032


# ---------------------------------------------------------------------------
# Host Python Texture Synthesis (2048x2048) + process_pbr.py Pipeline
# ---------------------------------------------------------------------------

def _tile_2x2(path: Path, size: int, mode: str = "RGB") -> Any:
    """Load a seamless 1024x1024 map and tile 2x2 to native 2048x2048 without blur."""
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert(mode)
    half = size // 2
    if img.size != (half, half):
        img = img.resize((half, half), Image.Resampling.LANCZOS)
    arr = np.array(img, dtype=np.float32)
    tiled = np.tile(arr, (2, 2, 1) if arr.ndim == 3 else (2, 2))
    return tiled


def _rasterize_uv_and_smooth_z(uv_meta: dict[str, Any], size: int) -> dict[str, Any]:
    """Rasterize per-pixel zone ID, edge-distance AO, and barycentric smooth world Z."""
    import numpy as np
    from PIL import Image, ImageDraw

    zone_names = [
        "void",           # 0
        "wall_outer",     # 1
        "chamfer_outer",  # 2
        "pocket_back",    # 3
        "pocket_wall",    # 4
        "rim_top",        # 5
        "inner_wall",     # 6
        "soil",           # 7
        "bottom",         # 8
    ]
    zone_to_id = {name: idx for idx, name in enumerate(zone_names)}

    zone_img = Image.new("L", (size, size), 0)
    draw_zone = ImageDraw.Draw(zone_img)
    z_smooth = np.full((size, size), 0.5 * TARGET_HEIGHT, dtype=np.float32)

    for poly in uv_meta["polys"]:
        zid = zone_to_id[poly["zone"]]
        uvz = poly["uvz"]
        pts = [(u * (size - 1), (1.0 - v) * (size - 1)) for u, v, _ in uvz]
        draw_zone.polygon(pts, fill=zid)

        # Fan-triangulate polygon and barycentrically interpolate Z smoothly across pixels
        for i in range(1, len(uvz) - 1):
            p0 = (uvz[0][0] * (size - 1), (1.0 - uvz[0][1]) * (size - 1), uvz[0][2])
            p1 = (uvz[i][0] * (size - 1), (1.0 - uvz[i][1]) * (size - 1), uvz[i][2])
            p2 = (uvz[i + 1][0] * (size - 1), (1.0 - uvz[i + 1][1]) * (size - 1), uvz[i + 1][2])

            x0 = max(0, int(math.floor(min(p0[0], p1[0], p2[0]))) - 1)
            x1 = min(size - 1, int(math.ceil(max(p0[0], p1[0], p2[0]))) + 1)
            y0 = max(0, int(math.floor(min(p0[1], p1[1], p2[1]))) - 1)
            y1 = min(size - 1, int(math.ceil(max(p0[1], p1[1], p2[1]))) + 1)
            if x1 < x0 or y1 < y0:
                continue

            denom = (p1[1] - p2[1]) * (p0[0] - p2[0]) + (p2[0] - p1[0]) * (p0[1] - p2[1])
            if abs(denom) < 1e-8:
                continue

            xs = np.arange(x0, x1 + 1, dtype=np.float32)[None, :]
            ys = np.arange(y0, y1 + 1, dtype=np.float32)[:, None]

            w0 = ((p1[1] - p2[1]) * (xs - p2[0]) + (p2[0] - p1[0]) * (ys - p2[1])) / denom
            w1 = ((p2[1] - p0[1]) * (xs - p2[0]) + (p0[0] - p2[0]) * (ys - p2[1])) / denom
            w2 = 1.0 - w0 - w1

            inside = (w0 >= -0.02) & (w1 >= -0.02) & (w2 >= -0.02)
            if np.any(inside):
                z_patch = np.clip(w0 * p0[2] + w1 * p1[2] + w2 * p2[2], 0.0, TARGET_HEIGHT)
                cur = z_smooth[y0 : y1 + 1, x0 : x1 + 1]
                cur[inside] = z_patch[inside]

    return {
        "zone": np.array(zone_img, dtype=np.int32),
        "z_norm": np.clip(z_smooth / TARGET_HEIGHT, 0.0, 1.0),
    }


def _dilate_uv_islands(arr: Any, mask: Any, iterations: int = 14) -> Any:
    """Dilate valid island values into unused UV gutter to prevent mipmap bleeding."""
    import numpy as np

    out = arr.copy()
    filled = mask.copy()
    for _ in range(iterations):
        if np.all(filled):
            break
        frontier = ~filled
        accum = np.zeros_like(out, dtype=np.float32)
        count = np.zeros(filled.shape, dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted_fill = np.roll(np.roll(filled, dy, axis=0), dx, axis=1)
            shifted_val = np.roll(np.roll(out, dy, axis=0), dx, axis=1)
            valid = frontier & shifted_fill
            accum[valid] += shifted_val[valid]
            count[valid] += 1.0
        upd = count > 0
        if out.ndim == 3:
            out[upd] = (accum[upd] / count[upd, None]).astype(out.dtype)
        else:
            out[upd] = (accum[upd] / count[upd]).astype(out.dtype)
        filled[upd] = True
    return out


def _prepare_soil_patch(target_box: tuple[int, int, int, int], size: int) -> tuple[Any, Any, Any, Any]:
    """Build delighted photorealistic soil+leaf litter tile and derive companion maps."""
    import numpy as np
    from PIL import Image

    x0, y0, x1, y1 = target_box
    bw, bh = x1 - x0 + 1, y1 - y0 + 1

    # Extract clean flat-lit soil + dry leaf litter region from reference photo
    src = Image.open(SOIL_REF_IMAGE).convert("RGB")
    patch = src.crop((1170, 910, 1830, 1570))  # 660x660 pure soil + leaves + pine needles
    patch = patch.resize((bw, bh), Image.Resampling.LANCZOS)

    soil_tmp_dir = Path("/tmp") / f"{SLUG}_soil_tmp"
    soil_tmp_dir.mkdir(parents=True, exist_ok=True)
    patch_path = soil_tmp_dir / "soil_raw.png"
    patch.save(patch_path, format="PNG")

    # Delight and derive pixel-aligned stone/soil normal, roughness, AO via process_pbr.py
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "derive-maps",
            str(patch_path),
            "--out-dir",
            str(soil_tmp_dir),
            "--slug",
            "soil",
            "--preset",
            "stone",
            "--normal-strength",
            "2.6",
            "--delight",
            "--delight-strength",
            "0.45",
            "--non-seamless",
        ],
        check=True,
    )

    soil_alb = np.array(Image.open(soil_tmp_dir / "soil_albedo.png").convert("RGB"), dtype=np.float32)
    # Darken slightly to match damp humus in concrete_ribbed_planter ref while staying >= 34 sRGB
    soil_alb = np.clip(soil_alb * 0.82, 34.0, 210.0)
    soil_nrm = np.array(Image.open(soil_tmp_dir / "soil_normal.png").convert("RGB"), dtype=np.float32)
    soil_rgh = np.array(Image.open(soil_tmp_dir / "soil_roughness.png").convert("L"), dtype=np.float32)
    soil_ao = np.array(Image.open(soil_tmp_dir / "soil_ao.png").convert("L"), dtype=np.float32)

    full_alb = np.zeros((size, size, 3), dtype=np.float32)
    full_nrm = np.zeros((size, size, 3), dtype=np.float32)
    full_rgh = np.zeros((size, size), dtype=np.float32)
    full_ao = np.zeros((size, size), dtype=np.float32)

    full_alb[y0 : y1 + 1, x0 : x1 + 1] = soil_alb
    full_nrm[y0 : y1 + 1, x0 : x1 + 1] = soil_nrm
    full_rgh[y0 : y1 + 1, x0 : x1 + 1] = soil_rgh
    full_ao[y0 : y1 + 1, x0 : x1 + 1] = soil_ao
    return full_alb, full_nrm, full_rgh, full_ao


def synthesize_textures(uv_meta_path: Path) -> None:
    """Synthesize photorealistic 2048x2048 concrete+soil PBR maps via real scan textures."""
    import numpy as np
    from PIL import Image, ImageFilter

    uv_meta = json.loads(uv_meta_path.read_text(encoding="utf-8"))
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    masks = _rasterize_uv_and_smooth_z(uv_meta, TEX_SIZE)
    zone = masks["zone"]
    z_norm = masks["z_norm"]

    # Load native 2x2 tiled 2048x2048 scan maps
    wc_alb = _tile_2x2(MAT_WEATHERED / "weathered_concrete_albedo.png", TEX_SIZE, "RGB")
    wc_nrm = _tile_2x2(MAT_WEATHERED / "weathered_concrete_normal.png", TEX_SIZE, "RGB")
    wc_rgh = _tile_2x2(MAT_WEATHERED / "weathered_concrete_roughness.png", TEX_SIZE, "L")
    wc_ao = _tile_2x2(MAT_WEATHERED / "weathered_concrete_ao.png", TEX_SIZE, "L")

    fs_alb = _tile_2x2(MAT_STAINED / "factory_stained_concrete_albedo.png", TEX_SIZE, "RGB")
    fs_nrm = _tile_2x2(MAT_STAINED / "factory_stained_concrete_normal.png", TEX_SIZE, "RGB")
    fs_rgh = _tile_2x2(MAT_STAINED / "factory_stained_concrete_roughness.png", TEX_SIZE, "L")
    fs_ao = _tile_2x2(MAT_STAINED / "factory_stained_concrete_ao.png", TEX_SIZE, "L")

    pp_alb = _tile_2x2(MAT_PEELING / "peeling_plaster_wall_albedo.png", TEX_SIZE, "RGB")
    pp_nrm = _tile_2x2(MAT_PEELING / "peeling_plaster_wall_normal.png", TEX_SIZE, "RGB")
    pp_orm = _tile_2x2(MAT_PEELING / "peeling_plaster_wall_orm.png", TEX_SIZE, "RGB")

    # Classify peeling_plaster_wall layers so ~80% is weathered whitewash concrete and ~20% is
    # sharply chipped raw concrete (matching the white-painted ref with chipped corners):
    pp_lum = (0.299 * pp_alb[..., 0] + 0.587 * pp_alb[..., 1] + 0.114 * pp_alb[..., 2]) / 255.0
    # Deeply pitted/spalled dark-gray regions of peeling_plaster_wall mark where whitewash chipped off
    is_chipped_core = np.clip((0.50 - pp_lum) * 14.0, 0.0, 1.0)
    # Also include sharp paint-flake edges from the cream plaster boundary
    paint_mask = 1.0 - np.clip(is_chipped_core * 0.85, 0.0, 1.0)

    # Raw unpainted concrete: blend weathered_concrete + factory_stained_concrete tinted warm gray-tan
    raw_concrete = wc_alb * 0.58 + fs_alb * 0.42
    raw_concrete[..., 0] *= 0.94
    raw_concrete[..., 1] *= 0.90
    raw_concrete[..., 2] *= 0.76

    # Whitewashed concrete paint: cool chalky off-white preserving real cracks & pores from wc_alb
    wc_lum = (0.299 * wc_alb[..., 0] + 0.587 * wc_alb[..., 1] + 0.114 * wc_alb[..., 2]) / 255.0
    whitewash = np.zeros_like(wc_alb)
    whitewash[..., 0] = 194.0 + (wc_lum - 0.5) * 90.0
    whitewash[..., 1] = 199.0 + (wc_lum - 0.5) * 90.0
    whitewash[..., 2] = 198.0 + (wc_lum - 0.5) * 88.0
    whitewash = np.clip(whitewash, 95.0, 234.0)

    # Combine whitewash (~80%) with chipped/peeled raw tan-gray concrete patches (~20%)
    outer_concrete = raw_concrete * (1.0 - paint_mask[..., None]) + whitewash * paint_mask[..., None]

    # Smooth bottom-up splash-dirt / moss gradient (using barycentric z_norm + fs_alb grime!)
    # Extract mossy/stained variation from factory_stained_concrete (greenish-olive & dark streaks)
    fs_lum = (0.299 * fs_alb[..., 0] + 0.587 * fs_alb[..., 1] + 0.114 * fs_alb[..., 2]) / 255.0
    # Smooth organic height threshold around z_norm = 0.0 -> 0.34 (no hard seam!)
    splash_profile = np.clip(1.0 - z_norm / (0.24 + (1.0 - fs_lum) * 0.22), 0.0, 1.0)
    splash_profile = splash_profile ** 1.35

    moss_dirt = np.zeros_like(fs_alb)
    moss_dirt[..., 0] = fs_alb[..., 0] * 0.56
    moss_dirt[..., 1] = fs_alb[..., 1] * 0.55
    moss_dirt[..., 2] = fs_alb[..., 2] * 0.44
    outer_concrete = outer_concrete * (1.0 - splash_profile[..., None] * 0.82) + moss_dirt * (
        splash_profile[..., None] * 0.82
    )

    # Assemble albedo across all UV zones
    albedo = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    normal = wc_nrm * 0.65 + fs_nrm * 0.35
    roughness = wc_rgh * 0.60 + fs_rgh * 0.40
    ao = wc_ao * 0.60 + fs_ao * 0.40

    # Blend peeling paint edge normals subtly on chipped concrete outer surfaces
    chip_edge = np.abs(paint_mask - 0.5) < 0.45
    normal[chip_edge] = normal[chip_edge] * 0.55 + pp_nrm[chip_edge] * 0.45
    ao[chip_edge] = ao[chip_edge] * 0.75 + pp_orm[..., 0][chip_edge] * 0.25

    m_outer = (zone == 1) | (zone == 2)
    albedo[m_outer] = outer_concrete[m_outer]
    # Ground contact AO fade smoothly using z_norm
    ao[m_outer] *= np.clip(0.68 + z_norm[m_outer] * 0.36, 0.68, 1.0)

    # Recessed 2x2 pockets: unpainted tan-gray concrete + natural crevice AO
    m_pback = zone == 3
    m_pwall = zone == 4
    albedo[m_pback] = raw_concrete[m_pback] * (1.0 - splash_profile[m_pback, None] * 0.45)
    albedo[m_pwall] = raw_concrete[m_pwall] * 0.78

    # Compute distance-to-wall falloff inside pocket_back for realistic recessed AO shadow
    wall_mask_img = Image.fromarray(((m_pwall) * 255).astype(np.uint8), mode="L")
    wall_bleed = np.array(
        wall_mask_img.filter(ImageFilter.GaussianBlur(radius=14.0)), dtype=np.float32
    ) / 255.0
    ao[m_pback] *= np.clip(1.0 - wall_bleed[m_pback] * 0.55, 0.55, 1.0)
    ao[m_pwall] *= 0.65

    # Top rim (5): brighter weathered whitewash concrete with subtle chipped spots
    rim_paint_mask = np.clip(paint_mask * 1.15 + 0.15, 0.0, 1.0)
    m_rim = zone == 5
    albedo[m_rim] = (raw_concrete * (1.0 - rim_paint_mask[..., None]) + whitewash * rim_paint_mask[..., None])[m_rim]

    # Inner wall (6) & Bottom (8)
    m_inner = zone == 6
    m_bottom = zone == 8
    albedo[m_inner] = raw_concrete[m_inner] * 0.68
    ao[m_inner] *= 0.72
    albedo[m_bottom] = raw_concrete[m_bottom] * 0.52

    # Soil bed (7): real photo-derived soil + dry leaf litter mapped to Region D
    m_soil = zone == 7
    soil_ys, soil_xs = np.where(m_soil)
    soil_box = (int(soil_xs.min()), int(soil_ys.min()), int(soil_xs.max()), int(soil_ys.max()))
    soil_alb, soil_nrm, soil_rgh, soil_ao = _prepare_soil_patch(soil_box, TEX_SIZE)
    albedo[m_soil] = soil_alb[m_soil]
    normal[m_soil] = soil_nrm[m_soil]
    roughness[m_soil] = soil_rgh[m_soil]
    ao[m_soil] = soil_ao[m_soil]

    # Clamp concrete/stone roughness strictly to stone preset [0.62, 0.98] -> [158, 250]
    roughness = np.clip(roughness, 165.0, 248.0)
    ao = np.clip(ao, 65.0, 255.0)

    # Dilate valid UV islands into unused gutter (6px margin prevents mip bleeding cleanly)
    valid_mask = zone > 0
    albedo_u8 = _dilate_uv_islands(np.clip(albedo, 30.0, 240.0).astype(np.uint8), valid_mask, iterations=6)
    albedo_u8 = np.clip(albedo_u8, 30, 240).astype(np.uint8)
    normal_u8 = _dilate_uv_islands(np.clip(normal, 0.0, 255.0).astype(np.uint8), valid_mask, iterations=6)
    rough_u8 = _dilate_uv_islands(roughness.astype(np.uint8), valid_mask, iterations=6)
    ao_u8 = _dilate_uv_islands(ao.astype(np.uint8), valid_mask, iterations=6)

    albedo_path = ASSET_DIR / f"{SLUG}_albedo.png"
    normal_path = ASSET_DIR / f"{SLUG}_normal.png"
    orm_path = ASSET_DIR / f"{SLUG}_orm.png"
    tres_path = ASSET_DIR / f"{SLUG}.tres"
    ao_tmp = Path("/tmp") / f"{SLUG}_ao_tmp.png"
    rough_tmp = Path("/tmp") / f"{SLUG}_rough_tmp.png"

    Image.fromarray(albedo_u8, mode="RGB").save(albedo_path, format="PNG")
    Image.fromarray(normal_u8, mode="RGB").save(normal_path, format="PNG")
    Image.fromarray(ao_u8, mode="L").save(ao_tmp, format="PNG")
    Image.fromarray(rough_u8, mode="L").save(rough_tmp, format="PNG")

    # Pack ORM (R=AO, G=Roughness, B=0.0 Metallic) via process_pbr.py
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "pack-orm",
            "--ao",
            str(ao_tmp),
            "--roughness",
            str(rough_tmp),
            "--metallic",
            "0.0",
            "--output",
            str(orm_path),
        ],
        check=True,
    )

    # Build Godot 4 ORMMaterial3D .tres via process_pbr.py
    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "build-tres",
            "--name",
            SLUG,
            "--albedo",
            str(albedo_path),
            "--normal",
            str(normal_path),
            "--orm",
            str(orm_path),
            "--output",
            str(tres_path),
        ],
        check=True,
    )

    ao_tmp.unlink(missing_ok=True)
    rough_tmp.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# Blender Procedural BMesh Geometry + Structured Non-Overlapping UVs
# ---------------------------------------------------------------------------

def _octagon_ring_pts(half_w: float, chamfer: float) -> list[tuple[float, float]]:
    """Return 8 CCW corner (x, y) points for a chamfered square."""
    c = half_w - chamfer
    return [
        (-c, -half_w),  # 0: South left
        (c, -half_w),   # 1: South right
        (half_w, -c),   # 2: SE corner end -> East bottom
        (half_w, c),    # 3: East top
        (c, half_w),    # 4: NE corner end -> North right
        (-c, half_w),   # 5: North left
        (-half_w, c),   # 6: NW corner end -> West top
        (-half_w, -c),  # 7: West bottom
    ]


def _ring_with_subcols(half_w: float, chamfer: float) -> list[tuple[float, float, int]]:
    """Return 24 perimeter (x, y, side_group) points: 5-col main faces + 1-col chamfers."""
    corners = _octagon_ring_pts(half_w, chamfer)
    # 5 columns per main face: left pillar (0.08), pocket L (0.375), center post (0.09),
    # pocket R (0.375), right pillar (0.08) -> elongated horizontal ribbed slots
    t_main = [0.0, 0.08, 0.455, 0.545, 0.92]
    pts: list[tuple[float, float, int]] = []
    for edge_idx in range(8):
        p0 = corners[edge_idx]
        p1 = corners[(edge_idx + 1) % 8]
        if edge_idx % 2 == 0:
            for t in t_main:
                x = p0[0] + (p1[0] - p0[0]) * t
                y = p0[1] + (p1[1] - p0[1]) * t
                pts.append((x, y, edge_idx))
        else:
            pts.append((p0[0], p0[1], edge_idx))
    return pts


def _assign_quad_uv(face: Any, uv_layer: Any, u0: float, u1: float, v0: float, v1: float) -> None:
    """Assign rectangular UV coordinates to a 4-vertex quad face."""
    coords = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    for loop, uv in zip(face.loops, coords):
        loop[uv_layer].uv = uv


def _build_planter_mesh() -> tuple[Any, dict[str, Any]]:
    """Build single manifold chamfered ribbed planter mesh and non-overlapping UVs."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    z_outer = [0.000, 0.155, 0.215, 0.260, 0.320, 0.466, 0.480]
    outer_rings: list[list[Any]] = []
    ring_meta: list[tuple[float, list[tuple[float, float, int]]]] = []

    for idx, z in enumerate(z_outer):
        t = z / TARGET_HEIGHT
        hw = BOT_HALF_W + (TOP_HALF_W - BOT_HALF_W) * t
        if idx == len(z_outer) - 1:
            hw -= 0.012
        ch = hw * CHAMFER_RATIO
        pts = _ring_with_subcols(hw, ch)
        ring_verts = [bm.verts.new((x, y, z)) for (x, y, _) in pts]
        outer_rings.append(ring_verts)
        ring_meta.append((z, pts))

    hw_top_in = TOP_HALF_W - WALL_THICK
    hw_in_bev = hw_top_in - 0.010
    hw_soil_edge = hw_top_in - 0.026

    inner_specs = [
        (0.480, hw_top_in),
        (0.470, hw_in_bev),
        (0.375, hw_soil_edge),
    ]
    inner_rings: list[list[Any]] = []
    for z, hw in inner_specs:
        ch = hw * CHAMFER_RATIO
        pts = _ring_with_subcols(hw, ch)
        inner_rings.append([bm.verts.new((x, y, z)) for (x, y, _) in pts])

    pts_soil_mid = _ring_with_subcols(hw_soil_edge * 0.52, hw_soil_edge * 0.52 * CHAMFER_RATIO)
    soil_mid_ring = []
    for i, (x, y, _) in enumerate(pts_soil_mid):
        jitter = 0.004 * math.sin(i * 1.7)
        soil_mid_ring.append(bm.verts.new((x, y, 0.387 + jitter)))
    soil_center_v = bm.verts.new((0.0, 0.0, 0.392))
    bot_center_v = bm.verts.new((0.0, 0.0, 0.0))

    n_cols = len(outer_rings[0])
    col_to_edge = [pt[2] for pt in ring_meta[0][1]]

    edge_col_local: list[int] = []
    counts: dict[int, int] = {}
    for e_id in col_to_edge:
        c = counts.get(e_id, 0)
        edge_col_local.append(c)
        counts[e_id] = c + 1

    face_zone: dict[Any, dict[str, Any]] = {}
    pocket_quads: list[tuple[Any, int, int, int, Vector]] = []

    for r in range(len(outer_rings) - 1):
        is_rim_bevel = r == len(outer_rings) - 2
        for c in range(n_cols):
            cn = (c + 1) % n_cols
            f = bm.faces.new((
                outer_rings[r][c],
                outer_rings[r][cn],
                outer_rings[r + 1][cn],
                outer_rings[r + 1][c],
            ))
            e_id = col_to_edge[c]
            l_col = edge_col_local[c]
            if is_rim_bevel:
                face_zone[f] = {"zone": "rim_top", "strip": e_id, "sub": ("bevel_out", l_col)}
            elif e_id % 2 == 0:
                face_zone[f] = {"zone": "wall_outer", "edge": e_id, "row": r, "col": l_col}
                if r in (1, 3) and l_col in (1, 3):
                    v0, v1, v2, _ = f.verts
                    nrm = (v1.co - v0.co).cross(v2.co - v0.co).normalized()
                    pocket_quads.append((f, e_id, r, l_col, nrm))
            else:
                face_zone[f] = {"zone": "chamfer_outer", "edge": e_id, "row": r}

    for f, e_id, r, l_col, out_nrm in pocket_quads:
        ret = bmesh.ops.extrude_discrete_faces(bm, faces=[f])
        back_face = ret["faces"][0]
        center = back_face.calc_center_median()
        for v in back_face.verts:
            to_c = center - v.co
            v.co = v.co - out_nrm * POCKET_DEPTH + to_c * 0.10

        face_zone[back_face] = {"zone": "pocket_back", "edge": e_id, "row": r, "col": l_col}
        for edge in back_face.edges:
            for adj in edge.link_faces:
                if adj is not back_face:
                    face_zone[adj] = {"zone": "pocket_wall", "edge": e_id, "row": r, "col": l_col}

    top_outer = outer_rings[-1]
    top_inner = inner_rings[0]
    for c in range(n_cols):
        cn = (c + 1) % n_cols
        f = bm.faces.new((top_outer[c], top_outer[cn], top_inner[cn], top_inner[c]))
        face_zone[f] = {"zone": "rim_top", "strip": col_to_edge[c], "sub": ("flat", edge_col_local[c])}

    for r in range(len(inner_rings) - 1):
        for c in range(n_cols):
            cn = (c + 1) % n_cols
            f = bm.faces.new((
                inner_rings[r][c],
                inner_rings[r][cn],
                inner_rings[r + 1][cn],
                inner_rings[r + 1][c],
            ))
            if r == 0:
                face_zone[f] = {"zone": "rim_top", "strip": col_to_edge[c], "sub": ("bevel_in", edge_col_local[c])}
            else:
                face_zone[f] = {"zone": "inner_wall", "edge": col_to_edge[c], "col": edge_col_local[c]}

    soil_outer = inner_rings[-1]
    for c in range(n_cols):
        cn = (c + 1) % n_cols
        f_ring = bm.faces.new((soil_outer[c], soil_outer[cn], soil_mid_ring[cn], soil_mid_ring[c]))
        face_zone[f_ring] = {"zone": "soil"}
        f_cap = bm.faces.new((soil_mid_ring[c], soil_mid_ring[cn], soil_center_v))
        face_zone[f_cap] = {"zone": "soil"}

    bot_ring = outer_rings[0]
    for c in range(n_cols):
        cn = (c + 1) % n_cols
        f_bot = bm.faces.new((bot_ring[cn], bot_ring[c], bot_center_v))
        face_zone[f_bot] = {"zone": "bottom"}

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    non_manifold_edges = [e for e in bm.edges if not e.is_manifold]
    non_manifold_verts = [v for v in bm.verts if not v.is_manifold]
    if non_manifold_edges or non_manifold_verts:
        raise RuntimeError(
            f"Non-manifold geometry detected: {len(non_manifold_edges)} edges, "
            f"{len(non_manifold_verts)} verts"
        )

    uv_layer = bm.loops.layers.uv.verify()

    col_widths = [0.140 if i % 2 == 0 else 0.080 for i in range(8)]
    pad_u = 0.011
    cur_u = 0.020
    edge_u_span: dict[int, tuple[float, float]] = {}
    for i, w in enumerate(col_widths):
        edge_u_span[i] = (cur_u, cur_u + w)
        cur_u += w + pad_u

    main_u_fracs = [0.0, 0.08, 0.455, 0.545, 0.92, 1.0]
    v_outer_rows = [0.560, 0.695, 0.748, 0.788, 0.842, 0.980]

    inner_u0 = 0.400
    inner_span_total = 0.580
    inner_pad = 0.008
    inner_unit = (inner_span_total - 7 * inner_pad) / sum(col_widths)
    inner_u_span: dict[int, tuple[float, float]] = {}
    iu = inner_u0
    for i, w in enumerate(col_widths):
        iw = w * inner_unit
        inner_u_span[i] = (iu, iu + iw)
        iu += iw + inner_pad

    soil_scale = 0.165 / max(hw_soil_edge, 1e-4)
    soil_cu, soil_cv = 0.185, 0.205

    bot_scale = 0.085 / max(BOT_HALF_W, 1e-4)
    bot_cu, bot_cv = 0.535, 0.105

    pocket_quad_lookup: dict[tuple[int, int, int], tuple[float, float, float, float]] = {}
    for e_id in (0, 2, 4, 6):
        su0, su1 = edge_u_span[e_id]
        sw = su1 - su0
        for r in (1, 3):
            for l_col in (1, 3):
                ou0 = su0 + sw * main_u_fracs[l_col]
                ou1 = su0 + sw * main_u_fracs[l_col + 1]
                ov0 = v_outer_rows[r]
                ov1 = v_outer_rows[r + 1]
                pocket_quad_lookup[(e_id, r, l_col)] = (ou0, ou1, ov0, ov1)

    for f in bm.faces:
        info = face_zone[f]
        zone = info["zone"]

        if zone == "wall_outer":
            e_id, r, l_col = info["edge"], info["row"], info["col"]
            su0, su1 = edge_u_span[e_id]
            sw = su1 - su0
            _assign_quad_uv(
                f, uv_layer,
                su0 + sw * main_u_fracs[l_col],
                su0 + sw * main_u_fracs[l_col + 1],
                v_outer_rows[r],
                v_outer_rows[r + 1],
            )
        elif zone == "chamfer_outer":
            e_id, r = info["edge"], info["row"]
            su0, su1 = edge_u_span[e_id]
            _assign_quad_uv(f, uv_layer, su0, su1, v_outer_rows[r], v_outer_rows[r + 1])
        elif zone in ("pocket_back", "pocket_wall"):
            e_id, r, l_col = info["edge"], info["row"], info["col"]
            ou0, ou1, ov0, ov1 = pocket_quad_lookup[(e_id, r, l_col)]
            cu, cv = (ou0 + ou1) * 0.5, (ov0 + ov1) * 0.5
            iu0 = cu + (ou0 - cu) * 0.70
            iu1 = cu + (ou1 - cu) * 0.70
            iv0 = cv + (ov0 - cv) * 0.70
            iv1 = cv + (ov1 - cv) * 0.70
            if zone == "pocket_back":
                xs = [v.co.x for v in f.verts]
                ys = [v.co.y for v in f.verts]
                zs = [v.co.z for v in f.verts]
                z_lo, z_hi = min(zs), max(zs)
                if e_id in (0, 4):
                    h_vals = xs if e_id == 0 else [-x for x in xs]
                else:
                    h_vals = ys if e_id == 2 else [-y for y in ys]
                h_lo, h_hi = min(h_vals), max(h_vals)
                for loop, hv, zv in zip(f.loops, h_vals, zs):
                    tu = (hv - h_lo) / max(h_hi - h_lo, 1e-5)
                    tv = (zv - z_lo) / max(z_hi - z_lo, 1e-5)
                    loop[uv_layer].uv = (iu0 + tu * (iu1 - iu0), iv0 + tv * (iv1 - iv0))
            else:
                for loop in f.loops:
                    co = loop.vert.co
                    rad = abs(co.y) if e_id in (0, 4) else abs(co.x)
                    hw_at_z = BOT_HALF_W + (TOP_HALF_W - BOT_HALF_W) * (co.z / TARGET_HEIGHT)
                    is_inner = rad < (hw_at_z - 0.015)
                    u_lo, u_hi = (iu0, iu1) if is_inner else (ou0, ou1)
                    v_lo, v_hi = (iv0, iv1) if is_inner else (ov0, ov1)
                    h_coord = co.x if e_id == 0 else (-co.x if e_id == 4 else (co.y if e_id == 2 else -co.y))
                    ch_z = hw_at_z * CHAMFER_RATIO
                    span_half = hw_at_z - ch_z
                    h_t = (h_coord + span_half) / max(2.0 * span_half, 1e-5)
                    f0, f1 = main_u_fracs[l_col], main_u_fracs[l_col + 1]
                    tu = max(0.0, min(1.0, (h_t - f0) / max(f1 - f0, 1e-5)))
                    z_bot = z_outer[r]
                    z_top = z_outer[r + 1]
                    tv = max(0.0, min(1.0, (co.z - z_bot) / max(z_top - z_bot, 1e-5)))
                    loop[uv_layer].uv = (u_lo + tu * (u_hi - u_lo), v_lo + tv * (v_hi - v_lo))
        elif zone == "rim_top":
            e_id = info["strip"]
            sub_kind, l_col = info["sub"]
            su0, su1 = edge_u_span[e_id]
            if e_id % 2 == 0:
                sw = su1 - su0
                ru0 = su0 + sw * main_u_fracs[l_col]
                ru1 = su0 + sw * main_u_fracs[l_col + 1]
            else:
                ru0, ru1 = su0, su1
            if sub_kind == "bevel_out":
                rv0, rv1 = 0.410, 0.432
            elif sub_kind == "flat":
                rv0, rv1 = 0.432, 0.508
            else:
                rv0, rv1 = 0.508, 0.530
            _assign_quad_uv(f, uv_layer, ru0, ru1, rv0, rv1)
        elif zone == "inner_wall":
            e_id, l_col = info["edge"], info["col"]
            su0, su1 = inner_u_span[e_id]
            if e_id % 2 == 0:
                sw = su1 - su0
                iu0 = su0 + sw * main_u_fracs[l_col]
                iu1 = su0 + sw * main_u_fracs[l_col + 1]
            else:
                iu0, iu1 = su0, su1
            _assign_quad_uv(f, uv_layer, iu0, iu1, 0.230, 0.380)
        elif zone == "soil":
            for loop in f.loops:
                co = loop.vert.co
                loop[uv_layer].uv = (soil_cu + co.x * soil_scale, soil_cv + co.y * soil_scale)
        elif zone == "bottom":
            for loop in f.loops:
                co = loop.vert.co
                loop[uv_layer].uv = (bot_cu + co.x * bot_scale, bot_cv + co.y * bot_scale)

    # Export per-vertex (u, v, z) for smooth barycentric height interpolation
    uv_polys: list[dict[str, Any]] = []
    for f in bm.faces:
        info = face_zone[f]
        uvz = [
            (float(loop[uv_layer].uv.x), float(loop[uv_layer].uv.y), float(loop.vert.co.z))
            for loop in f.loops
        ]
        uv_polys.append({
            "zone": info["zone"],
            "uvz": uvz,
        })

    for f in bm.faces:
        for loop in f.loops:
            uv = loop[uv_layer].uv
            if not (-1e-4 <= uv.x <= 1.0 + 1e-4 and -1e-4 <= uv.y <= 1.0 + 1e-4):
                raise RuntimeError(f"UV out of [0,1] bounds: {(uv.x, uv.y)} in {face_zone[f]}")

    mesh = bpy.data.meshes.new("ConcreteRibbedPlanter_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new("ConcreteRibbedPlanter", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    return obj, {"polys": uv_polys}


def _create_wired_material() -> Any:
    """Create Principled BSDF wired to synthesized albedo, ORM, and normal maps."""
    import bpy

    mat = bpy.data.materials.new(name="M_ConcreteRibbedPlanter")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (500, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (180, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    albedo_path = ASSET_DIR / f"{SLUG}_albedo.png"
    orm_path = ASSET_DIR / f"{SLUG}_orm.png"
    normal_path = ASSET_DIR / f"{SLUG}_normal.png"

    tex_alb = nt.nodes.new("ShaderNodeTexImage")
    tex_alb.location = (-400, 300)
    img_alb = bpy.data.images.load(str(albedo_path), check_existing=True)
    img_alb.colorspace_settings.name = "sRGB"
    tex_alb.image = img_alb
    nt.links.new(tex_alb.outputs["Color"], bsdf.inputs["Base Color"])

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

    tex_nrm = nt.nodes.new("ShaderNodeTexImage")
    tex_nrm.location = (-400, -300)
    img_nrm = bpy.data.images.load(str(normal_path), check_existing=True)
    img_nrm.colorspace_settings.name = "Non-Color"
    tex_nrm.image = img_nrm

    nrm_node = nt.nodes.new("ShaderNodeNormalMap")
    nrm_node.location = (-100, -300)
    nrm_node.inputs["Strength"].default_value = 0.90
    nt.links.new(tex_nrm.outputs["Color"], nrm_node.inputs["Color"])
    nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])

    return mat


def run_blender_build() -> None:
    """Build mesh, generate textures via host python3, wire material, and export GLB."""
    from tools.blender.common.exporter import clean_scene, export_godot_glb

    clean_scene()
    obj, uv_meta = _build_planter_mesh()

    uv_meta_path = Path("/tmp") / f"{SLUG}_uv_meta.json"
    uv_meta_path.write_text(json.dumps(uv_meta), encoding="utf-8")

    clean_env = {
        k: v for k, v in os.environ.items()
        if "PYTHON" not in k and "LD_" not in k and "SNAP" not in k
    }
    subprocess.run(
        ["/usr/bin/python3", str(Path(__file__).resolve()), "--textures-only", str(uv_meta_path)],
        env=clean_env,
        check=True,
    )

    mat = _create_wired_material()
    obj.data.materials.append(mat)

    mesh = obj.data
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    assert abs(min(zs)) < 1e-5, f"Expected grounded min_z=0, got {min(zs)}"
    assert abs(max(zs) - TARGET_HEIGHT) < 1e-5, f"Expected max_z={TARGET_HEIGHT}, got {max(zs)}"
    assert tri_count <= 2000, f"Tri count {tri_count} exceeds budget 2000"

    dims_godot = [
        round(max(xs) - min(xs), 4),
        round(max(zs) - min(zs), 4),
        round(max(ys) - min(ys), 4),
    ]

    output_glb = ASSET_DIR / f"{SLUG}.glb"
    export_godot_glb(output_glb, export_animations=False, export_morph=False)

    manifest = {
        "prop_slug": SLUG,
        "tri_count": tri_count,
        "uv_layers": len(mesh.uv_layers),
        "dimensions_m": dims_godot,
        "target_layer": "Layer 1 Environment",
        "collision_hint": "BoxShape3D",
        "generator": "procedural_bpy",
        "reference_image": REF_IMAGE,
        "manifold": True,
        "min_y_m": 0.0,
        "texture_resolution": f"{TEX_SIZE}x{TEX_SIZE}",
        "mesh": f"res://assets/models/{SLUG}/{SLUG}.glb",
        "material": f"res://assets/models/{SLUG}/{SLUG}.tres",
        "textures": {
            "albedo": f"res://assets/models/{SLUG}/{SLUG}_albedo.png",
            "normal": f"res://assets/models/{SLUG}/{SLUG}_normal.png",
            "orm": f"res://assets/models/{SLUG}/{SLUG}_orm.png",
        },
    }
    manifest_path = ASSET_DIR / "asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"BUILT_{SLUG.upper()}:", json.dumps(manifest, indent=2))


if __name__ == "__main__":
    if "--textures-only" in sys.argv:
        idx = sys.argv.index("--textures-only")
        meta_file = Path(sys.argv[idx + 1])
        synthesize_textures(meta_file)
    else:
        run_blender_build()
