"""Procedural Octagonal Stone Planter (Stepped Plinth + Relief Panels + White Collar, 0.52m tall).

References:
    /home/dkd/Desktop/Refs/IMG_20261125_161224.jpg
    /home/dkd/Desktop/Refs/IMG_20261125_163802.jpg

Run headless:
    python3 tools/blender/run.py tools/blender/props/octagonal_stone_planter.py
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

ASSET_DIR: Path = REPO_ROOT / "assets" / "models" / "octagonal_stone_planter"
SLUG: str = "octagonal_stone_planter"
REF_IMAGES: list[str] = [
    "/home/dkd/Desktop/Refs/IMG_20261125_161224.jpg",
    "/home/dkd/Desktop/Refs/IMG_20261125_163802.jpg",
]
PROCESS_PBR: Path = REPO_ROOT / ".agents" / "skills" / "pbr" / "scripts" / "process_pbr.py"

TEX_SIZE: int = 1024
TARGET_HEIGHT: float = 0.52
COLLAR_HALF_W: float = 0.41  # 0.82m outer width across flats
CHAMFER_RATIO: float = 0.51  # Balanced architectural octagon (cardinal ~0.40m, diagonal ~0.30m)
WALL_THICK: float = 0.082
PANEL_DEPTH: float = 0.015


# ---------------------------------------------------------------------------
# Host Python Texture Synthesis + process_pbr.py Pipeline
# ---------------------------------------------------------------------------

def _fbm_2d(h: int, w: int, octaves: list[tuple[int, float]], seed: int) -> Any:
    """Generate multi-octave value noise array in [0, 1]."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    acc = np.zeros((h, w), dtype=np.float32)
    weight_sum = 0.0
    for grid_res, weight in octaves:
        low = rng.random((grid_res, grid_res), dtype=np.float32)
        img = Image.fromarray((low * 255.0).astype(np.uint8), mode="L")
        up = np.array(img.resize((w, h), Image.Resampling.BICUBIC), dtype=np.float32) / 255.0
        acc += up * weight
        weight_sum += weight
    return np.clip(acc / max(weight_sum, 1e-5), 0.0, 1.0)


def _rasterize_uv_masks(uv_meta: dict[str, Any], size: int) -> dict[str, Any]:
    """Rasterize per-pixel zone ID, world Z, and panel rects from UV metadata."""
    import numpy as np
    from PIL import Image, ImageDraw

    zone_names = [
        "void",         # 0
        "plinth",       # 1
        "body_frame",   # 2
        "panel_back",   # 3
        "panel_wall",   # 4
        "collar",       # 5
        "rim_top",      # 6
        "inner_wall",   # 7
        "soil",         # 8
        "bottom",       # 9
    ]
    zone_to_id = {name: idx for idx, name in enumerate(zone_names)}

    zone_img = Image.new("L", (size, size), 0)
    zval_img = Image.new("L", (size, size), 128)
    draw_zone = ImageDraw.Draw(zone_img)
    draw_zval = ImageDraw.Draw(zval_img)

    for poly in uv_meta["polys"]:
        zid = zone_to_id[poly["zone"]]
        pts = [(u * (size - 1), (1.0 - v) * (size - 1)) for u, v in poly["uvs"]]
        z_norm = int(np.clip((poly["z_avg"] / TARGET_HEIGHT) * 255.0, 0, 255))
        draw_zone.polygon(pts, fill=zid)
        draw_zval.polygon(pts, fill=z_norm)

    return {
        "zone": np.array(zone_img, dtype=np.int32),
        "z_norm": np.array(zval_img, dtype=np.float32) / 255.0,
        "panel_rects": uv_meta.get("panel_rects", []),
    }


def _dilate_uv_islands(rgb_arr: Any, mask: Any, iterations: int = 10) -> Any:
    """Dilate valid island colors into unused UV gutter to prevent mipmap bleeding."""
    import numpy as np

    out = rgb_arr.copy()
    filled = mask.copy()
    for _ in range(iterations):
        if np.all(filled):
            break
        frontier = ~filled
        accum = np.zeros_like(out, dtype=np.float32)
        count = np.zeros(filled.shape, dtype=np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            shifted_fill = np.roll(np.roll(filled, dy, axis=0), dx, axis=1)
            shifted_col = np.roll(np.roll(out, dy, axis=0), dx, axis=1)
            valid = frontier & shifted_fill
            accum[valid] += shifted_col[valid]
            count[valid] += 1.0
        upd = count > 0
        out[upd] = (accum[upd] / count[upd, None]).astype(out.dtype)
        filled[upd] = True
    return out


def _draw_panel_ornament(size: int, panel_rects: list[list[float]]) -> Any:
    """Paint symmetric carved stone medallion/scrollwork height relief in [0, 1]."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    orn = Image.new("L", (size, size), 128)
    draw = ImageDraw.Draw(orn)

    for u0, u1, v0, v1 in panel_rects:
        x0 = u0 * (size - 1)
        x1 = u1 * (size - 1)
        y0 = (1.0 - v1) * (size - 1)
        y1 = (1.0 - v0) * (size - 1)
        pw = x1 - x0
        ph = y1 - y0
        cx = (x0 + x1) * 0.5
        cy = (y0 + y1) * 0.5

        # Inner decorative border frame
        bx0, by0 = x0 + pw * 0.08, y0 + ph * 0.08
        bx1, by1 = x1 - pw * 0.08, y1 - ph * 0.08
        draw.rectangle([bx0, by0, bx1, by1], outline=195, width=max(2, int(pw * 0.045)))

        # Central carved diamond/medallion & symmetrical scrolls (inspired by ref 163802)
        rx, ry = pw * 0.24, ph * 0.22
        draw.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=210, width=max(2, int(pw * 0.05)))
        draw.ellipse([cx - rx * 0.45, cy - ry * 0.45, cx + rx * 0.45, cy + ry * 0.45], fill=215)

        for sx in (-1.0, 1.0):
            for sy in (-1.0, 1.0):
                scx = cx + sx * pw * 0.22
                scy = cy + sy * ph * 0.24
                srx = pw * 0.12
                sry = ph * 0.11
                draw.ellipse([scx - srx, scy - sry, scx + srx, scy + sry], outline=202, width=max(2, int(pw * 0.04)))
                draw.line(
                    [(cx + sx * pw * 0.05, cy), (scx, scy)],
                    fill=198,
                    width=max(2, int(pw * 0.035)),
                )

    orn_blur = orn.filter(ImageFilter.GaussianBlur(radius=1.2))
    return (np.array(orn_blur, dtype=np.float32) - 128.0) / 128.0


def synthesize_textures(uv_meta_path: Path) -> None:
    """Synthesize weathered terracotta sandstone + white rim + soil maps and run process_pbr.py."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter

    uv_meta = json.loads(uv_meta_path.read_text(encoding="utf-8"))
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    masks = _rasterize_uv_masks(uv_meta, TEX_SIZE)
    zone = masks["zone"]
    z_norm = masks["z_norm"]
    panel_rects = masks["panel_rects"]

    macro_n = _fbm_2d(TEX_SIZE, TEX_SIZE, [(8, 0.5), (16, 0.3), (32, 0.2)], seed=701)
    med_n = _fbm_2d(TEX_SIZE, TEX_SIZE, [(24, 0.45), (64, 0.35), (128, 0.2)], seed=702)
    fine_n = _fbm_2d(TEX_SIZE, TEX_SIZE, [(128, 0.5), (256, 0.35), (512, 0.15)], seed=703)

    # Horizontal chiseled / troweled sandstone striations (matching ref 161224)
    horiz_raw = _fbm_2d(TEX_SIZE // 8, TEX_SIZE // 2, [(16, 0.5), (48, 0.5)], seed=704)
    horiz_img = Image.fromarray((horiz_raw * 255.0).astype(np.uint8), mode="L").resize(
        (TEX_SIZE, TEX_SIZE), Image.Resampling.BILINEAR
    )
    striations = np.array(horiz_img, dtype=np.float32) / 255.0

    # Carved relief ornament field for panel_back
    ornament = _draw_panel_ornament(TEX_SIZE, panel_rects)

    # Stone pores
    rng = np.random.default_rng(705)
    pores = (rng.random((TEX_SIZE, TEX_SIZE)) > 0.990).astype(np.float32)
    pores = np.array(
        Image.fromarray((pores * 255.0).astype(np.uint8), mode="L").filter(
            ImageFilter.GaussianBlur(radius=0.7)
        ),
        dtype=np.float32,
    ) / 255.0

    albedo = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)

    # Warm buff/terracotta sandstone base matching both refs
    sandstone = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    sandstone[..., 0] = 192.0 + (macro_n - 0.5) * 24.0 + (striations - 0.5) * 26.0 + (fine_n - 0.5) * 16.0
    sandstone[..., 1] = 156.0 + (macro_n - 0.5) * 20.0 + (striations - 0.5) * 22.0 + (fine_n - 0.5) * 14.0
    sandstone[..., 2] = 124.0 + (macro_n - 0.5) * 18.0 + (striations - 0.5) * 18.0 + (fine_n - 0.5) * 12.0
    sandstone *= (1.0 - pores[..., None] * 0.22)

    # Ground grime / dust darkening gently near base Z=0..0.06m (keeps plinth warm sandstone)
    ground_grime = np.clip((0.09 + macro_n * 0.06 - z_norm) * 2.2, 0.0, 0.26)
    sandstone_weathered = sandstone * (1.0 - ground_grime[..., None])

    m_plinth = zone == 1
    m_body = zone == 2
    m_pback = zone == 3
    m_pwall = zone == 4

    albedo[m_plinth] = sandstone_weathered[m_plinth] * 0.94
    albedo[m_body] = sandstone_weathered[m_body]
    # Add carved relief highlight/crevice shading inside panels
    panel_tone = sandstone * (1.0 + ornament[..., None] * 0.18)
    albedo[m_pback] = panel_tone[m_pback]
    albedo[m_pwall] = sandstone_weathered[m_pwall] * 0.85

    # White-painted overhanging top collar (5) & top rim (6) with minimal edge wear
    white_paint = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    white_paint[..., 0] = 226.0 + (med_n - 0.5) * 14.0 + (fine_n - 0.5) * 10.0
    white_paint[..., 1] = 228.0 + (med_n - 0.5) * 14.0 + (fine_n - 0.5) * 10.0
    white_paint[..., 2] = 224.0 + (med_n - 0.5) * 14.0 + (fine_n - 0.5) * 10.0
    white_paint *= (1.0 - pores[..., None] * 0.12)

    chip_mask = np.clip((med_n * 0.65 + fine_n * 0.35 - 0.14) * 12.0, 0.0, 1.0)
    rim_col = sandstone * (1.0 - chip_mask[..., None]) + white_paint * chip_mask[..., None]

    m_collar = zone == 5
    m_rim = zone == 6
    albedo[m_collar] = rim_col[m_collar]
    albedo[m_rim] = rim_col[m_rim]

    # Inner wall (7) & Bottom (9)
    m_inner = zone == 7
    m_bottom = zone == 9
    albedo[m_inner] = sandstone[m_inner] * 0.72
    albedo[m_bottom] = sandstone[m_bottom] * 0.55

    # Soil bed (8): dark earth heavily scattered with dry autumn leaves & twigs
    soil_col = np.zeros((TEX_SIZE, TEX_SIZE, 3), dtype=np.float32)
    soil_col[..., 0] = 46.0 + med_n * 22.0 + fine_n * 18.0
    soil_col[..., 1] = 40.0 + med_n * 18.0 + fine_n * 15.0
    soil_col[..., 2] = 34.0 + med_n * 14.0 + fine_n * 11.0

    leaf_layer = Image.new("RGBA", (TEX_SIZE, TEX_SIZE), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(leaf_layer)
    soil_ys, soil_xs = np.where(zone == 8)
    if len(soil_xs) > 0:
        x_min, x_max = int(soil_xs.min()), int(soil_xs.max())
        y_min, y_max = int(soil_ys.min()), int(soil_ys.max())
        for _ in range(210):
            cx = int(rng.integers(x_min, x_max + 1))
            cy = int(rng.integers(y_min, y_max + 1))
            ang = float(rng.uniform(0.0, math.tau))
            rad_a = float(rng.uniform(6.0, 14.0))
            rad_b = float(rng.uniform(3.0, 7.0))
            pts = []
            for k in range(6):
                a = ang + k * (math.tau / 6.0)
                lx = cx + math.cos(a) * rad_a * math.cos(ang) - math.sin(a) * rad_b * math.sin(ang)
                ly = cy + math.cos(a) * rad_a * math.sin(ang) + math.sin(a) * rad_b * math.cos(ang)
                pts.append((lx, ly))
            tone = int(rng.integers(105, 172))
            col = (tone, int(tone * 0.78), int(tone * 0.54), 235)
            ldraw.polygon(pts, fill=col)
        for _ in range(180):
            cx = int(rng.integers(x_min, x_max + 1))
            cy = int(rng.integers(y_min, y_max + 1))
            ang = float(rng.uniform(0.0, math.tau))
            length = float(rng.uniform(8.0, 20.0))
            x2 = cx + math.cos(ang) * length
            y2 = cy + math.sin(ang) * length
            tone = int(rng.integers(90, 145))
            ldraw.line([(cx, cy), (x2, y2)], fill=(tone, int(tone * 0.78), int(tone * 0.55), 220), width=1)

    leaf_arr = np.array(leaf_layer, dtype=np.float32)
    leaf_alpha = leaf_arr[..., 3:4] / 255.0
    soil_col = soil_col * (1.0 - leaf_alpha) + leaf_arr[..., :3] * leaf_alpha
    m_soil = zone == 8
    albedo[m_soil] = soil_col[m_soil]

    # Clamp sRGB strictly to [30, 240] and dilate UV island gutters
    albedo_u8 = np.clip(albedo, 30.0, 240.0).astype(np.uint8)
    albedo_u8 = _dilate_uv_islands(albedo_u8, zone > 0, iterations=10)
    albedo_u8 = np.clip(albedo_u8, 30, 240).astype(np.uint8)

    albedo_path = ASSET_DIR / f"{SLUG}_albedo.png"
    normal_path = ASSET_DIR / f"{SLUG}_normal.png"
    orm_path = ASSET_DIR / f"{SLUG}_orm.png"
    tres_path = ASSET_DIR / f"{SLUG}.tres"

    Image.fromarray(albedo_u8, mode="RGB").save(albedo_path, format="PNG")

    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "derive-maps",
            str(albedo_path),
            "--out-dir",
            str(ASSET_DIR),
            "--slug",
            SLUG,
            "--preset",
            "stone",
            "--normal-strength",
            "3.0",
            "--non-seamless",
        ],
        check=True,
    )

    ao_path = ASSET_DIR / f"{SLUG}_ao.png"
    rough_path = ASSET_DIR / f"{SLUG}_roughness.png"
    height_path = ASSET_DIR / f"{SLUG}_height.png"

    # Enhance AO in panel recesses, under-collar shadow, and plinth base
    ao_arr = np.array(Image.open(ao_path).convert("L"), dtype=np.float32)
    ao_arr[m_pback] *= 0.88
    ao_arr[m_pwall] *= 0.74
    ao_arr[m_inner] *= 0.80
    ao_arr[m_plinth] *= 0.84
    ao_arr = np.clip(ao_arr, 60.0, 255.0).astype(np.uint8)
    Image.fromarray(ao_arr, mode="L").save(ao_path, format="PNG")

    subprocess.run(
        [
            sys.executable,
            str(PROCESS_PBR),
            "pack-orm",
            "--ao",
            str(ao_path),
            "--roughness",
            str(rough_path),
            "--metallic",
            "0.0",
            "--output",
            str(orm_path),
        ],
        check=True,
    )

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

    for tmp in (ao_path, rough_path, height_path):
        tmp.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# Blender Procedural BMesh Geometry + Structured Non-Overlapping UVs
# ---------------------------------------------------------------------------

def _octagon_ring_pts(half_w: float) -> list[tuple[float, float]]:
    """Return 8 CCW corner (x, y) points for an architectural octagon."""
    chamfer = half_w * CHAMFER_RATIO
    c = half_w - chamfer
    return [
        (-c, -half_w),
        (c, -half_w),
        (half_w, -c),
        (half_w, c),
        (c, half_w),
        (-c, half_w),
        (-half_w, c),
        (-half_w, -c),
    ]


def _ring_with_panel_cols(half_w: float) -> list[tuple[float, float, int, int]]:
    """Return 24 perimeter (x, y, side_idx, local_col) points (3 cols per each of 8 faces)."""
    corners = _octagon_ring_pts(half_w)
    t_cols = [0.0, 0.16, 0.84]
    pts: list[tuple[float, float, int, int]] = []
    for side_idx in range(8):
        p0 = corners[side_idx]
        p1 = corners[(side_idx + 1) % 8]
        for l_col, t in enumerate(t_cols):
            x = p0[0] + (p1[0] - p0[0]) * t
            y = p0[1] + (p1[1] - p0[1]) * t
            pts.append((x, y, side_idx, l_col))
    return pts


def _assign_quad_uv(face: Any, uv_layer: Any, u0: float, u1: float, v0: float, v1: float) -> None:
    """Assign rectangular UV coordinates to a 4-vertex quad face."""
    coords = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    for loop, uv in zip(face.loops, coords):
        loop[uv_layer].uv = uv


def _build_planter_mesh() -> tuple[Any, dict[str, Any]]:
    """Build single manifold octagonal stone planter mesh and non-overlapping UVs."""
    import bmesh
    import bpy
    from mathutils import Vector

    bm = bmesh.new()

    # Cross-section stations: (z, scale_relative_to_COLLAR_HALF_W, station_role)
    outer_specs = [
        (0.000, 0.90),   # 0: Lower plinth bottom
        (0.045, 0.90),   # 1: Lower plinth top
        (0.055, 0.84),   # 2: Upper plinth start
        (0.088, 0.84),   # 3: Upper plinth top
        (0.100, 0.81),   # 4: Body base (bottom of lower frame)
        (0.145, 0.824),  # 5: Bottom of recessed panel
        (0.390, 0.896),  # 6: Top of recessed panel
        (0.435, 0.91),   # 7: Top of body (under collar overhang)
        (0.445, 1.00),   # 8: Collar outer lip
        (0.506, 1.00),   # 9: Collar top before outer bevel
        (0.520, 0.975),  # 10: Outer rim top edge
    ]

    outer_rings: list[list[Any]] = []
    ring_meta: list[list[tuple[float, float, int, int]]] = []
    for z, sc in outer_specs:
        pts = _ring_with_panel_cols(COLLAR_HALF_W * sc)
        outer_rings.append([bm.verts.new((x, y, z)) for (x, y, _, _) in pts])
        ring_meta.append(pts)

    # Inner rim bevel -> inner cavity -> soil bed
    hw_in_top = COLLAR_HALF_W * 0.975 - WALL_THICK
    hw_in_bev = hw_in_top - 0.010
    hw_soil = hw_in_top - 0.025
    inner_specs = [
        (0.520, hw_in_top),
        (0.510, hw_in_bev),
        (0.415, hw_soil),
    ]
    inner_rings: list[list[Any]] = []
    for z, hw in inner_specs:
        pts = _ring_with_panel_cols(hw)
        inner_rings.append([bm.verts.new((x, y, z)) for (x, y, _, _) in pts])

    # Soil mound ring and center
    pts_soil_mid = _ring_with_panel_cols(hw_soil * 0.52)
    soil_mid_ring = []
    for i, (x, y, _, _) in enumerate(pts_soil_mid):
        jitter = 0.004 * math.cos(i * 1.4)
        soil_mid_ring.append(bm.verts.new((x, y, 0.428 + jitter)))
    soil_center_v = bm.verts.new((0.0, 0.0, 0.435))
    bot_center_v = bm.verts.new((0.0, 0.0, 0.0))

    n_cols = len(outer_rings[0])
    face_zone: dict[Any, dict[str, Any]] = {}
    panel_quads: list[tuple[Any, int, Vector]] = []

    for r in range(len(outer_rings) - 1):
        for c in range(n_cols):
            cn = (c + 1) % n_cols
            f = bm.faces.new((
                outer_rings[r][c],
                outer_rings[r][cn],
                outer_rings[r + 1][cn],
                outer_rings[r + 1][c],
            ))
            _, _, side_idx, l_col = ring_meta[r][c]
            if r <= 3:
                zname = "plinth"
            elif r <= 6:
                zname = "body_frame"
            elif r <= 8:
                zname = "collar"
            else:
                zname = "rim_top"

            face_zone[f] = {"zone": zname, "side": side_idx, "row": r, "col": l_col}
            if r == 5 and l_col == 1:
                v0, v1, v2, _ = f.verts
                nrm = (v1.co - v0.co).cross(v2.co - v0.co).normalized()
                panel_quads.append((f, side_idx, nrm))

    # Extrude the 8 decorative relief panels inward cleanly (manifold!)
    for f, side_idx, out_nrm in panel_quads:
        ret = bmesh.ops.extrude_discrete_faces(bm, faces=[f])
        back_face = ret["faces"][0]
        center = back_face.calc_center_median()
        for v in back_face.verts:
            to_c = center - v.co
            v.co = v.co - out_nrm * PANEL_DEPTH + to_c * 0.08
        face_zone[back_face] = {"zone": "panel_back", "side": side_idx, "row": 5, "col": 1}
        for edge in back_face.edges:
            for adj in edge.link_faces:
                if adj is not back_face:
                    face_zone[adj] = {"zone": "panel_wall", "side": side_idx, "row": 5, "col": 1}

    # Top flat rim + inner bevel + inner wall
    top_outer = outer_rings[-1]
    top_inner = inner_rings[0]
    for c in range(n_cols):
        cn = (c + 1) % n_cols
        _, _, side_idx, l_col = ring_meta[0][c]
        f_flat = bm.faces.new((top_outer[c], top_outer[cn], top_inner[cn], top_inner[c]))
        face_zone[f_flat] = {"zone": "rim_top", "side": side_idx, "sub": "flat", "col": l_col}

    for r in range(len(inner_rings) - 1):
        for c in range(n_cols):
            cn = (c + 1) % n_cols
            _, _, side_idx, l_col = ring_meta[0][c]
            f = bm.faces.new((
                inner_rings[r][c],
                inner_rings[r][cn],
                inner_rings[r + 1][cn],
                inner_rings[r + 1][c],
            ))
            if r == 0:
                face_zone[f] = {"zone": "rim_top", "side": side_idx, "sub": "bevel_in", "col": l_col}
            else:
                face_zone[f] = {"zone": "inner_wall", "side": side_idx, "col": l_col}

    # Soil bed
    soil_outer = inner_rings[-1]
    for c in range(n_cols):
        cn = (c + 1) % n_cols
        f_ring = bm.faces.new((soil_outer[c], soil_outer[cn], soil_mid_ring[cn], soil_mid_ring[c]))
        face_zone[f_ring] = {"zone": "soil"}
        f_cap = bm.faces.new((soil_mid_ring[c], soil_mid_ring[cn], soil_center_v))
        face_zone[f_cap] = {"zone": "soil"}

    # Bottom cap
    bot_ring = outer_rings[0]
    for c in range(n_cols):
        cn = (c + 1) % n_cols
        f_bot = bm.faces.new((bot_ring[cn], bot_ring[c], bot_center_v))
        face_zone[f_bot] = {"zone": "bottom"}

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # Verify manifoldness
    non_manifold_edges = [e for e in bm.edges if not e.is_manifold]
    non_manifold_verts = [v for v in bm.verts if not v.is_manifold]
    if non_manifold_edges or non_manifold_verts:
        raise RuntimeError(
            f"Non-manifold geometry detected: {len(non_manifold_edges)} edges, "
            f"{len(non_manifold_verts)} verts"
        )

    # -----------------------------------------------------------------------
    # Clean Non-Overlapping Structured UVs in [0, 1]^2
    # -----------------------------------------------------------------------
    uv_layer = bm.loops.layers.uv.verify()

    # Region A: 8 outer vertical columns in U:[0.02, 0.98], V:[0.52, 0.98]
    # Cardinal faces slightly wider than diagonal faces
    side_widths = [0.122 if i % 2 == 0 else 0.098 for i in range(8)]
    pad_u = 0.011
    cur_u = 0.020
    side_u_span: dict[int, tuple[float, float]] = {}
    for i, w in enumerate(side_widths):
        side_u_span[i] = (cur_u, cur_u + w)
        cur_u += w + pad_u

    col_fracs = [0.0, 0.16, 0.84, 1.0]
    # 10 rows from plinth bottom (r=0) up to collar top (r=9)
    v_rows = [0.520, 0.562, 0.574, 0.608, 0.622, 0.664, 0.864, 0.906, 0.922, 0.968, 0.980]
    # Note: r=9 (outer bevel of collar) is assigned to rim_top region below so white paint covers it!

    # Region C: Inner wall in U:[0.40, 0.98], V:[0.22, 0.36]
    inner_u0 = 0.400
    inner_pad = 0.008
    inner_unit = (0.580 - 7 * inner_pad) / sum(side_widths)
    inner_u_span: dict[int, tuple[float, float]] = {}
    iu = inner_u0
    for i, w in enumerate(side_widths):
        iw = w * inner_unit
        inner_u_span[i] = (iu, iu + iw)
        iu += iw + inner_pad

    soil_scale = 0.165 / max(hw_soil, 1e-4)
    soil_cu, soil_cv = 0.185, 0.195

    bot_scale = 0.085 / max(COLLAR_HALF_W * 0.90, 1e-4)
    bot_cu, bot_cv = 0.535, 0.105

    panel_rects: list[list[float]] = []
    panel_outer_uv: dict[int, tuple[float, float, float, float]] = {}
    for side_idx in range(8):
        su0, su1 = side_u_span[side_idx]
        sw = su1 - su0
        ou0 = su0 + sw * col_fracs[1]
        ou1 = su0 + sw * col_fracs[2]
        ov0 = v_rows[5]
        ov1 = v_rows[6]
        panel_outer_uv[side_idx] = (ou0, ou1, ov0, ov1)

        cu, cv = (ou0 + ou1) * 0.5, (ov0 + ov1) * 0.5
        iu0 = cu + (ou0 - cu) * 0.80
        iu1 = cu + (ou1 - cu) * 0.80
        iv0 = cv + (ov0 - cv) * 0.80
        iv1 = cv + (ov1 - cv) * 0.80
        panel_rects.append([iu0, iu1, iv0, iv1])

    # Precompute 8 face tangent unit vectors in XY for projecting panel_back & panel_wall
    corners_unit = _octagon_ring_pts(1.0)
    side_tangents: list[Vector] = []
    for side_idx in range(8):
        p0 = Vector((corners_unit[side_idx][0], corners_unit[side_idx][1], 0.0))
        p1 = Vector((corners_unit[(side_idx + 1) % 8][0], corners_unit[(side_idx + 1) % 8][1], 0.0))
        side_tangents.append((p1 - p0).normalized())

    for f in bm.faces:
        info = face_zone[f]
        zname = info["zone"]

        if zname in ("plinth", "body_frame", "collar"):
            side_idx, r, l_col = info["side"], info["row"], info["col"]
            su0, su1 = side_u_span[side_idx]
            sw = su1 - su0
            _assign_quad_uv(
                f, uv_layer,
                su0 + sw * col_fracs[l_col],
                su0 + sw * col_fracs[l_col + 1],
                v_rows[r],
                v_rows[r + 1],
            )
        elif zname in ("panel_back", "panel_wall"):
            side_idx = info["side"]
            ou0, ou1, ov0, ov1 = panel_outer_uv[side_idx]
            iu0, iu1, iv0, iv1 = panel_rects[side_idx]
            t_vec = side_tangents[side_idx]
            if zname == "panel_back":
                proj = [v.co.x * t_vec.x + v.co.y * t_vec.y for v in f.verts]
                zs = [v.co.z for v in f.verts]
                p_lo, p_hi = min(proj), max(proj)
                z_lo, z_hi = min(zs), max(zs)
                for loop, pv, zv in zip(f.loops, proj, zs):
                    tu = (pv - p_lo) / max(p_hi - p_lo, 1e-5)
                    tv = (zv - z_lo) / max(z_hi - z_lo, 1e-5)
                    loop[uv_layer].uv = (iu0 + tu * (iu1 - iu0), iv0 + tv * (iv1 - iv0))
            else:
                z_bot, z_top = outer_specs[5][0], outer_specs[6][0]
                for loop in f.loops:
                    co = loop.vert.co
                    # Interpolate expected outer radius at co.z to detect recessed verts
                    t_z = (co.z - z_bot) / max(z_top - z_bot, 1e-5)
                    sc_outer = outer_specs[5][1] + (outer_specs[6][1] - outer_specs[5][1]) * t_z
                    # Distance along outward normal ~ dot with perpendicular
                    n_xy = Vector((t_vec.y, -t_vec.x, 0.0))
                    r_cur = co.x * n_xy.x + co.y * n_xy.y
                    # Outer face at sc_outer has known radial offset from origin along n_xy
                    p_ref = corners_unit[side_idx]
                    r_outer = (p_ref[0] * n_xy.x + p_ref[1] * n_xy.y) * COLLAR_HALF_W * sc_outer
                    is_inner = r_cur < (r_outer - 0.006)
                    u_lo, u_hi = (iu0, iu1) if is_inner else (ou0, ou1)
                    v_lo, v_hi = (iv0, iv1) if is_inner else (ov0, ov1)

                    # Normalized tangential position across the side face
                    p0 = Vector((corners_unit[side_idx][0], corners_unit[side_idx][1], 0.0)) * COLLAR_HALF_W * sc_outer
                    p1 = Vector((corners_unit[(side_idx + 1) % 8][0], corners_unit[(side_idx + 1) % 8][1], 0.0)) * COLLAR_HALF_W * sc_outer
                    s0 = p0.dot(t_vec)
                    s1 = p1.dot(t_vec)
                    s_cur = co.x * t_vec.x + co.y * t_vec.y
                    s_t = (s_cur - s0) / max(s1 - s0, 1e-5)
                    tu = max(0.0, min(1.0, (s_t - col_fracs[1]) / (col_fracs[2] - col_fracs[1])))
                    tv = max(0.0, min(1.0, t_z))
                    loop[uv_layer].uv = (u_lo + tu * (u_hi - u_lo), v_lo + tv * (v_hi - v_lo))
        elif zname == "rim_top":
            side_idx, l_col = info["side"], info["col"]
            su0, su1 = side_u_span[side_idx]
            sw = su1 - su0
            ru0 = su0 + sw * col_fracs[l_col]
            ru1 = su0 + sw * col_fracs[l_col + 1]
            sub = info.get("sub", "bevel_out")
            if sub == "bevel_out":
                rv0, rv1 = 0.390, 0.415
            elif sub == "flat":
                rv0, rv1 = 0.415, 0.480
            else:
                rv0, rv1 = 0.480, 0.500
            _assign_quad_uv(f, uv_layer, ru0, ru1, rv0, rv1)
        elif zname == "inner_wall":
            side_idx, l_col = info["side"], info["col"]
            su0, su1 = inner_u_span[side_idx]
            sw = su1 - su0
            _assign_quad_uv(
                f, uv_layer,
                su0 + sw * col_fracs[l_col],
                su0 + sw * col_fracs[l_col + 1],
                0.220,
                0.360,
            )
        elif zname == "soil":
            for loop in f.loops:
                co = loop.vert.co
                loop[uv_layer].uv = (soil_cu + co.x * soil_scale, soil_cv + co.y * soil_scale)
        elif zname == "bottom":
            for loop in f.loops:
                co = loop.vert.co
                loop[uv_layer].uv = (bot_cu + co.x * bot_scale, bot_cv + co.y * bot_scale)

    uv_polys: list[dict[str, Any]] = []
    for f in bm.faces:
        info = face_zone[f]
        zs = [v.co.z for v in f.verts]
        uvs = [(float(loop[uv_layer].uv.x), float(loop[uv_layer].uv.y)) for loop in f.loops]
        uv_polys.append({
            "zone": info["zone"],
            "z_avg": sum(zs) / len(zs),
            "uvs": uvs,
        })

    for f in bm.faces:
        for loop in f.loops:
            uv = loop[uv_layer].uv
            if not (-1e-4 <= uv.x <= 1.0 + 1e-4 and -1e-4 <= uv.y <= 1.0 + 1e-4):
                raise RuntimeError(f"UV out of [0,1] bounds: {(uv.x, uv.y)} in {face_zone[f]}")

    mesh = bpy.data.meshes.new("OctagonalStonePlanter_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = False

    obj = bpy.data.objects.new("OctagonalStonePlanter", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    return obj, {"polys": uv_polys, "panel_rects": panel_rects}


def _create_wired_material() -> Any:
    """Create Principled BSDF wired to synthesized albedo, ORM, and normal maps."""
    import bpy

    mat = bpy.data.materials.new(name="M_OctagonalStonePlanter")
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
    nrm_node.inputs["Strength"].default_value = 0.85
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
        "collision_hint": "ConvexPolygonShape3D",
        "generator": "procedural_bpy",
        "reference_image": REF_IMAGES,
        "manifold": True,
        "min_y_m": 0.0,
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
