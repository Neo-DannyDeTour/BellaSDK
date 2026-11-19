#!/usr/bin/env python3
"""Procedural PBR Bark & Alpha-Scissored Foliage Atlas Generator for BellaSDK.

Generates:
1. overgrown_bark (1024x1024 seamless oak bark w/ moss streaks)
2. foliage_ivy_atlas (1024x1024 RGBA ivy vine cluster + normal + StandardMaterial3D .tres)
3. foliage_weeds_atlas (1024x1024 RGBA grass & weed blades fanning from bottom + normal + .tres)
4. foliage_tree_canopy (1024x1024 RGBA oak branch & lobed leaf cluster + normal + .tres)
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Tuple

import numpy as np
from PIL import Image

ROOT_DIR = Path(__file__).resolve().parents[2]
MATERIALS_DIR = ROOT_DIR / "assets" / "materials"


def _smooth_quintic(t: np.ndarray) -> np.ndarray:
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def tileable_value_noise(
    h: int, w: int, gh: int, gw: int, rng: np.random.Generator
) -> np.ndarray:
    """C2-continuous periodic 2D value noise that wraps seamlessly at boundaries."""
    grid = rng.random((gh, gw), dtype=np.float32)

    uy = (np.arange(h, dtype=np.float32) * gh) / float(h)
    ux = (np.arange(w, dtype=np.float32) * gw) / float(w)

    y0 = np.floor(uy).astype(np.int32) % gh
    y1 = (y0 + 1) % gh
    fy = _smooth_quintic(uy - np.floor(uy))[:, None]

    x0 = np.floor(ux).astype(np.int32) % gw
    x1 = (x0 + 1) % gw
    fx = _smooth_quintic(ux - np.floor(ux))[None, :]

    c00 = grid[y0[:, None], x0[None, :]]
    c10 = grid[y0[:, None], x1[None, :]]
    c01 = grid[y1[:, None], x0[None, :]]
    c11 = grid[y1[:, None], x1[None, :]]

    top = c00 * (1.0 - fx) + c10 * fx
    bot = c01 * (1.0 - fx) + c11 * fx
    return top * (1.0 - fy) + bot * fy


def tileable_fbm(
    h: int,
    w: int,
    octaves: list[Tuple[int, int, float]],
    rng: np.random.Generator,
) -> np.ndarray:
    """Multi-octave periodic fractal noise normalized to [0, 1]."""
    acc = np.zeros((h, w), dtype=np.float32)
    weight_sum = 0.0
    for gh, gw, wt in octaves:
        acc += wt * tileable_value_noise(h, w, gh, gw, rng)
        weight_sum += wt
    return np.clip(acc / max(weight_sum, 1e-6), 0.0, 1.0)


def dilate_rgba_and_height(
    rgb: np.ndarray,
    alpha: np.ndarray,
    height: np.ndarray,
    iterations: int = 14,
) -> Tuple[np.ndarray, np.ndarray]:
    """Pad RGB and height outward from opaque mask to avoid mipmap dark/cliff edges."""
    out_rgb = rgb.copy()
    out_h = height.copy()
    mask = alpha > 0.15

    for _ in range(iterations):
        valid = mask.astype(np.float32)
        acc_rgb = np.zeros_like(out_rgb)
        acc_h = np.zeros_like(out_h)
        cnt = np.zeros_like(valid)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                sv = np.roll(np.roll(valid, dy, axis=0), dx, axis=1)
                sr = np.roll(np.roll(out_rgb, dy, axis=0), dx, axis=1)
                sh = np.roll(np.roll(out_h, dy, axis=0), dx, axis=1)
                acc_rgb += sr * sv[..., None]
                acc_h += sh * sv
                cnt += sv
        fill = (~mask) & (cnt > 0.0)
        if not np.any(fill):
            break
        out_rgb[fill] = acc_rgb[fill] / cnt[fill, None]
        out_h[fill] = acc_h[fill] / cnt[fill]
        mask = mask | fill

    return out_rgb, out_h


def height_to_normal_map(
    height: np.ndarray, alpha: np.ndarray, strength: float = 3.2
) -> Image.Image:
    """Compute Godot +Y OpenGL tangent-space normal map from dilated height."""
    p = np.pad(height, ((1, 1), (1, 1)), mode="edge")
    dx = (
        (p[:-2, 2:] + 2.0 * p[1:-1, 2:] + p[2:, 2:])
        - (p[:-2, :-2] + 2.0 * p[1:-1, :-2] + p[2:, :-2])
    ) / 8.0
    dy = (
        (p[2:, :-2] + 2.0 * p[2:, 1:-1] + p[2:, 2:])
        - (p[:-2, :-2] + 2.0 * p[:-2, 1:-1] + p[:-2, 2:])
    ) / 8.0

    edge_fade = np.clip(alpha * 2.5, 0.0, 1.0)
    dx *= strength * edge_fade
    dy *= strength * edge_fade
    dz = np.ones_like(height)

    inv_len = 1.0 / np.sqrt(dx * dx + dy * dy + dz * dz)
    nx = dx * inv_len
    ny = -dy * inv_len
    nz = dz * inv_len

    out = np.zeros((*height.shape, 3), dtype=np.uint8)
    out[..., 0] = np.clip((nx * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[..., 1] = np.clip((ny * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[..., 2] = np.clip((nz * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(out, mode="RGB")


def write_foliage_tres(
    tres_path: Path,
    mat_name: str,
    albedo_rel: str,
    normal_rel: str,
    roughness: float = 0.72,
) -> None:
    """Write Godot 4 StandardMaterial3D .tres with ALPHA_SCISSOR and cull_mode=2."""
    content = "\n".join(
        [
            '[gd_resource type="StandardMaterial3D" load_steps=3 format=3]',
            "",
            f'[ext_resource type="Texture2D" path="{albedo_rel}" id="1_albedo"]',
            f'[ext_resource type="Texture2D" path="{normal_rel}" id="2_normal"]',
            "",
            "[resource]",
            f'resource_name = "{mat_name}"',
            "transparency = 2",
            "alpha_scissor_threshold = 0.5",
            "cull_mode = 2",
            'albedo_texture = ExtResource("1_albedo")',
            f"roughness = {roughness:.2f}",
            "normal_enabled = true",
            'normal_texture = ExtResource("2_normal")',
            "",
        ]
    )
    tres_path.parent.mkdir(parents=True, exist_ok=True)
    tres_path.write_text(content, encoding="utf-8")


def _bezier_segment_distance(
    xx: np.ndarray,
    yy: np.ndarray,
    p0: Tuple[float, float],
    p1: Tuple[float, float],
    p2: Tuple[float, float],
    n_segs: int = 36,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Exact distance, parameter t in [0,1], and signed lateral offset to quadratic Bezier."""
    ts = np.linspace(0.0, 1.0, n_segs + 1, dtype=np.float32)
    bx = (1.0 - ts) ** 2 * p0[0] + 2.0 * (1.0 - ts) * ts * p1[0] + ts ** 2 * p2[0]
    by = (1.0 - ts) ** 2 * p0[1] + 2.0 * (1.0 - ts) * ts * p1[1] + ts ** 2 * p2[1]

    ax = bx[:-1]
    ay = by[:-1]
    sdx = bx[1:] - ax
    sdy = by[1:] - ay
    slen2 = sdx * sdx + sdy * sdy + 1e-8
    slen = np.sqrt(slen2)

    px = xx[..., None] - ax[None, None, :]
    py = yy[..., None] - ay[None, None, :]
    u = np.clip((px * sdx[None, None, :] + py * sdy[None, None, :]) / slen2[None, None, :], 0.0, 1.0)

    cx = ax[None, None, :] + u * sdx[None, None, :]
    cy = ay[None, None, :] + u * sdy[None, None, :]
    rx = xx[..., None] - cx
    ry = yy[..., None] - cy
    d2 = rx * rx + ry * ry

    k_best = np.argmin(d2, axis=-1)
    dist = np.sqrt(np.take_along_axis(d2, k_best[..., None], axis=-1)[..., 0])
    u_best = np.take_along_axis(u, k_best[..., None], axis=-1)[..., 0]
    t_near = (k_best.astype(np.float32) + u_best) / float(n_segs)

    # Signed lateral offset using segment normal
    nx_best = -sdy[k_best] / slen[k_best]
    ny_best = sdx[k_best] / slen[k_best]
    rx_best = np.take_along_axis(rx, k_best[..., None], axis=-1)[..., 0]
    ry_best = np.take_along_axis(ry, k_best[..., None], axis=-1)[..., 0]
    signed_s = rx_best * nx_best + ry_best * ny_best
    return dist, t_near, signed_s


# ---------------------------------------------------------------------------
# 1. Seamless Overgrown Oak Bark (1024x1024 RGB)
# ---------------------------------------------------------------------------
def generate_overgrown_bark(size: int = 1024) -> Path:
    rng = np.random.default_rng(4201)
    yy, xx = np.meshgrid(
        np.arange(size, dtype=np.int32), np.arange(size, dtype=np.int32), indexing="ij"
    )

    # Periodic domain warp for gnarled vertical oak fissures
    warp_x = (tileable_fbm(size, size, [(4, 8, 0.55), (8, 16, 0.45)], rng) - 0.5) * 38.0
    warp_y = (tileable_fbm(size, size, [(4, 8, 0.55), (8, 16, 0.45)], rng) - 0.5) * 24.0
    wy = (yy + np.round(warp_y).astype(np.int32)) % size
    wx = (xx + np.round(warp_x).astype(np.int32)) % size

    # Primary deep vertical oak ridges + secondary scaly plates (high-freq vertical grain)
    macro_ridges = tileable_fbm(
        size,
        size,
        [(4, 16, 0.42), (8, 32, 0.34), (16, 64, 0.24)],
        rng,
    )[wy, wx]
    # Add asymmetric saw/furrow shaping (avoid smooth symmetrical contour loops)
    sub_ridges = tileable_fbm(
        size,
        size,
        [(16, 96, 0.45), (32, 192, 0.35), (64, 256, 0.20)],
        rng,
    )[wy, wx]
    fine_splinters = tileable_fbm(
        size,
        size,
        [(64, 256, 0.50), (128, 512, 0.35), (256, 512, 0.15)],
        rng,
    )
    horiz_breaks = tileable_fbm(
        size,
        size,
        [(32, 16, 0.45), (64, 32, 0.35), (128, 64, 0.20)],
        rng,
    )

    # Deep V-fissures carved at zero crossings of shifted noise + flaky plates
    furrow_v = np.clip(np.abs(macro_ridges - 0.48) * 2.5, 0.0, 1.0) ** 0.65
    plate_step = np.clip((sub_ridges - 0.22) * 1.45, 0.0, 1.0)
    bark_h = np.clip(furrow_v * 0.68 + plate_step * 0.24 + fine_splinters * 0.22 - 0.08, 0.0, 1.0)

    # Crisp horizontal bark plate cracks on raised ridges
    crack_mask = np.clip((0.30 - horiz_breaks) * 5.2, 0.0, 1.0) * np.clip(
        (bark_h - 0.42) * 2.4, 0.0, 1.0
    )
    bark_h = np.clip(bark_h - crack_mask * 0.40, 0.0, 1.0)

    # Micro-flaking grain
    micro_pitting = rng.normal(0.0, 0.045, size=(size, size)).astype(np.float32)
    bark_h = np.clip(bark_h + micro_pitting * (0.4 + 0.6 * bark_h), 0.0, 1.0)

    dark_fissure = np.array([38.0, 32.0, 26.0], dtype=np.float32)
    mid_bark = np.array([86.0, 74.0, 60.0], dtype=np.float32)
    ridge_light = np.array([134.0, 120.0, 102.0], dtype=np.float32)

    t1 = np.clip(bark_h / 0.48, 0.0, 1.0)[..., None]
    t2 = np.clip((bark_h - 0.48) / 0.52, 0.0, 1.0)[..., None]
    col = dark_fissure * (1.0 - t1) + mid_bark * t1
    col = col * (1.0 - t2) + ridge_light * t2

    # Subtle weathered ash/warm oak patch variation
    tint = tileable_fbm(size, size, [(4, 8, 0.5), (16, 32, 0.5)], rng)[..., None]
    col = col * (0.86 + 0.26 * tint)

    # Moss streaks nestled in vertical bark crevices
    moss_patch = tileable_fbm(
        size, size, [(4, 8, 0.45), (8, 24, 0.35), (32, 64, 0.20)], rng
    )[wy, wx]
    in_crevice = np.clip((0.66 - bark_h) * 2.1, 0.0, 1.0)
    moss_mask = np.clip((moss_patch - 0.49) * 3.6, 0.0, 1.0) * (0.22 + 0.78 * in_crevice)
    moss_detail = tileable_fbm(size, size, [(64, 64, 0.4), (256, 256, 0.6)], rng)
    moss_col = np.zeros_like(col)
    moss_col[..., 0] = 54.0 + 30.0 * moss_detail
    moss_col[..., 1] = 74.0 + 36.0 * moss_detail
    moss_col[..., 2] = 38.0 + 20.0 * moss_detail
    col = col * (1.0 - moss_mask[..., None] * 0.80) + moss_col * (moss_mask[..., None] * 0.80)

    # Subtle crusty pale lichen flecks on outer bark plates
    lichen_noise = tileable_fbm(size, size, [(32, 32, 0.4), (128, 128, 0.6)], rng)
    lichen_mask = (
        np.clip((lichen_noise - 0.74) * 7.5, 0.0, 1.0)
        * np.clip((bark_h - 0.58) * 2.8, 0.0, 1.0)
        * (1.0 - moss_mask)
    )
    lichen_col = np.array([146.0, 150.0, 128.0], dtype=np.float32)
    col = col * (1.0 - lichen_mask[..., None] * 0.62) + lichen_col * (
        lichen_mask[..., None] * 0.62
    )

    out_path = MATERIALS_DIR / "overgrown_bark" / "textures" / "overgrown_bark_albedo.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(col, 32, 232).astype(np.uint8), mode="RGB").save(
        out_path, format="PNG"
    )
    return out_path


# ---------------------------------------------------------------------------
# Vectorized Leaf & Stem Primitives (Segment-Exact Distance)
# ---------------------------------------------------------------------------
def _blend_layer(
    canvas_rgb: np.ndarray,
    canvas_a: np.ndarray,
    canvas_h: np.ndarray,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    layer_rgb: np.ndarray,
    layer_a: np.ndarray,
    layer_h: np.ndarray,
) -> None:
    dst_rgb = canvas_rgb[y0:y1, x0:x1]
    dst_a = canvas_a[y0:y1, x0:x1]
    dst_h = canvas_h[y0:y1, x0:x1]

    a = layer_a[..., None]
    canvas_rgb[y0:y1, x0:x1] = layer_rgb * a + dst_rgb * (1.0 - a)
    canvas_a[y0:y1, x0:x1] = layer_a + dst_a * (1.0 - layer_a)
    canvas_h[y0:y1, x0:x1] = layer_h * layer_a + dst_h * (1.0 - layer_a)


def _draw_bezier_stem(
    canvas_rgb: np.ndarray,
    canvas_a: np.ndarray,
    canvas_h: np.ndarray,
    p0: Tuple[float, float],
    p1: Tuple[float, float],
    p2: Tuple[float, float],
    r0: float,
    r1: float,
    col0: np.ndarray,
    col1: np.ndarray,
    base_h: float,
    taper_cap: bool = True,
) -> None:
    """Draw smooth continuous tapered quadratic Bezier stem using segment distance."""
    h_img, w_img = canvas_a.shape
    pad = int(max(r0, r1) + 6)
    xs = [p0[0], p1[0], p2[0]]
    ys = [p0[1], p1[1], p2[1]]
    x0 = max(0, int(min(xs)) - pad)
    x1 = min(w_img, int(max(xs)) + pad + 1)
    y0 = max(0, int(min(ys)) - pad)
    y1 = min(h_img, int(max(ys)) + pad + 1)
    if x1 <= x0 or y1 <= y0:
        return

    yy, xx = np.mgrid[y0:y1, x0:x1]
    dist, t_near, _ = _bezier_segment_distance(xx, yy, p0, p1, p2, n_segs=32)

    rad = r0 * (1.0 - t_near) + r1 * t_near
    if taper_cap:
        rad = rad * np.clip((1.0 - t_near) * 14.0, 0.25, 1.0)
    alpha = np.clip((rad - dist + 0.7) / 1.4, 0.0, 1.0)
    if not np.any(alpha > 0.01):
        return

    prof = np.sqrt(np.clip(1.0 - (dist / np.maximum(rad, 1e-3)) ** 2, 0.0, 1.0))
    rgb = (col0 * (1.0 - t_near[..., None]) + col1 * t_near[..., None]) * (
        0.68 + 0.42 * prof[..., None]
    )
    h_val = base_h + 0.14 * prof
    _blend_layer(canvas_rgb, canvas_a, canvas_h, x0, y0, x1, y1, rgb, alpha, h_val)


def _draw_ivy_leaf(
    canvas_rgb: np.ndarray,
    canvas_a: np.ndarray,
    canvas_h: np.ndarray,
    cx: float,
    cy: float,
    scale: float,
    angle: float,
    aspect: float,
    base_col: np.ndarray,
    vein_col: np.ndarray,
    edge_wear: float,
    base_h: float,
    rng: np.random.Generator,
) -> None:
    """Draw 5-lobed post-apocalyptic English ivy leaf with palmate veins."""
    h_img, w_img = canvas_a.shape
    half = int(scale * 1.25) + 4
    x0 = max(0, int(cx) - half)
    x1 = min(w_img, int(cx) + half + 1)
    y0 = max(0, int(cy) - half)
    y1 = min(h_img, int(cy) + half + 1)
    if x1 <= x0 or y1 <= y0:
        return

    yy, xx = np.mgrid[y0:y1, x0:x1]
    px = (xx - cx) / scale
    py = (yy - cy) / scale
    ca, sa = math.cos(angle), math.sin(angle)
    u = (px * ca + py * sa) / aspect
    v = -px * sa + py * ca

    vc = v - 0.18
    r = np.sqrt(u * u + vc * vc) + 1e-6
    theta = np.arctan2(u, vc)

    lobe_main = 0.72 * np.exp(-1.55 * (np.abs(theta) ** 1.45))
    lobe_mid = 0.56 * np.exp(-2.35 * (np.abs(np.abs(theta) - 1.06) ** 1.35))
    lobe_base = 0.36 * np.exp(-2.85 * (np.abs(np.abs(theta) - 2.08) ** 1.35))
    cordate = 0.22 + 0.12 * np.cos(theta)
    edge_r = np.maximum.reduce([lobe_main, lobe_mid, lobe_base, cordate])
    edge_r *= 1.0 + 0.025 * np.sin(theta * 9.0 + rng.uniform(0, 6.28))

    sdf_px = (edge_r - r) * scale
    alpha = np.clip((sdf_px + 0.65) / 1.3, 0.0, 1.0)
    if not np.any(alpha > 0.01):
        return

    vp = v + 0.02
    rp = np.sqrt(u * u + vp * vp) + 1e-6
    thetap = np.arctan2(u, vp)
    vein_angles = [0.0, 0.98, -0.98, 1.92, -1.92]
    vein_mask = np.zeros_like(r)
    for idx_v, va in enumerate(vein_angles):
        max_len = 0.78 if idx_v == 0 else (0.58 if abs(va) < 1.3 else 0.38)
        d_ang = np.abs(thetap - va) * rp
        thickness = (0.024 if idx_v == 0 else 0.017) * (1.0 - 0.65 * rp / max_len)
        len_fade = np.clip((max_len - rp) * 6.0, 0.0, 1.0)
        vm = np.clip(1.0 - d_ang / np.maximum(thickness, 0.004), 0.0, 1.0) * len_fade
        vein_mask = np.maximum(vein_mask, vm)

        if idx_v <= 2:
            cva, sva = math.cos(va), math.sin(va)
            v_along = vp * cva + u * sva
            u_perp = -vp * sva + u * cva
            side_t = np.abs(u_perp) * 1.4 + v_along
            branch_wave = np.abs(np.sin(side_t * 26.0))
            sub_vm = (
                np.clip(1.0 - branch_wave * 4.5, 0.0, 1.0)
                * np.clip((v_along - 0.12) * 5.0, 0.0, 1.0)
                * np.clip((max_len * 0.85 - rp) * 5.0, 0.0, 1.0)
                * np.clip((0.35 - np.abs(u_perp)) * 4.0, 0.0, 1.0)
            )
            vein_mask = np.maximum(vein_mask, sub_vm * 0.45)

    norm_r = np.clip(r / np.maximum(edge_r, 1e-4), 0.0, 1.0)
    center_shade = 0.86 + 0.18 * (1.0 - norm_r) - 0.08 * np.abs(np.sin(thetap * 2.5))
    rgb = base_col * center_shade[..., None]
    rgb = rgb * (1.0 - vein_mask[..., None] * 0.72) + vein_col * (
        vein_mask[..., None] * 0.72
    )

    edge_band = np.clip((norm_r - 0.76) * 4.2, 0.0, 1.0) * edge_wear
    wear_col = np.array([124.0, 106.0, 46.0], dtype=np.float32)
    rgb = rgb * (1.0 - edge_band[..., None] * 0.65) + wear_col * (
        edge_band[..., None] * 0.65
    )

    dome = np.sqrt(np.clip(1.0 - (norm_r ** 2) * 0.65, 0.0, 1.0)) * 0.12
    h_val = base_h + dome + vein_mask * 0.045 - 0.02 * np.abs(np.sin(thetap * 2.5))
    _blend_layer(canvas_rgb, canvas_a, canvas_h, x0, y0, x1, y1, rgb, alpha, h_val)


def generate_foliage_ivy_atlas(size: int = 1024) -> Tuple[Path, Path]:
    rng = np.random.default_rng(7103)
    rgb = np.zeros((size, size, 3), dtype=np.float32)
    alpha = np.zeros((size, size), dtype=np.float32)
    height = np.zeros((size, size), dtype=np.float32)

    # Organic meandering vine runners curving across the cluster (no straight bars)
    stems = [
        ((230, 895), (385, 610), (320, 215), 9.5, 4.2),
        ((765, 885), (560, 560), (700, 195), 9.0, 4.0),
        ((490, 930), (545, 550), (475, 165), 10.5, 4.2),
        ((195, 620), (495, 535), (825, 445), 8.0, 3.8),
        ((240, 315), (485, 415), (785, 295), 7.0, 3.5),
    ]
    stem_c0 = np.array([62.0, 56.0, 36.0], dtype=np.float32)
    stem_c1 = np.array([76.0, 86.0, 44.0], dtype=np.float32)
    for p0, p1, p2, r0, r1 in stems:
        _draw_bezier_stem(
            rgb, alpha, height, p0, p1, p2, r0, r1, stem_c0, stem_c1, 0.25, taper_cap=False
        )

    # Place leaves both AT stem endpoints (so no bare sticks poke out!) and along stems
    leaf_specs = []
    for s_idx, (p0, p1, p2, _, _) in enumerate(stems):
        for end_pt, ang_bias in [(p0, math.pi), (p2, 0.0)]:
            leaf_specs.append(
                (s_idx * 2, float(end_pt[0]), float(end_pt[1]), float(rng.uniform(96, 128)),
                 ang_bias + float(rng.uniform(-0.6, 0.6)), float(rng.uniform(0.95, 1.08)), end_pt)
            )

    for i in range(52):
        p0, p1, p2, _, _ = stems[i % len(stems)]
        t = rng.uniform(0.06, 0.94)
        bx = (1.0 - t) ** 2 * p0[0] + 2.0 * (1.0 - t) * t * p1[0] + t ** 2 * p2[0]
        by = (1.0 - t) ** 2 * p0[1] + 2.0 * (1.0 - t) * t * p1[1] + t ** 2 * p2[1]
        cx = float(np.clip(bx + rng.normal(0, 32), 125, size - 125))
        cy = float(np.clip(by + rng.normal(0, 32), 125, size - 125))
        scale = float(rng.uniform(82.0, 142.0))
        dx = cx - bx
        dy = cy - by
        angle = math.atan2(-dx, dy) + float(rng.uniform(-0.85, 0.85))
        aspect = float(rng.uniform(0.92, 1.10))
        leaf_specs.append((20 + i, cx, cy, scale, angle, aspect, (bx, by)))

    # Draw petioles pass first so leaves sit naturally in front of stems/petioles
    for idx, cx, cy, scale, angle, _aspect, stem_pt in leaf_specs:
        sa, ca = math.sin(angle), math.cos(angle)
        attach_x = cx - sa * (scale * 0.16)
        attach_y = cy + ca * (scale * 0.16)
        mid_x = (attach_x + stem_pt[0]) * 0.5 + float(rng.uniform(-6, 6))
        mid_y = (attach_y + stem_pt[1]) * 0.5 + float(rng.uniform(-6, 6))
        _draw_bezier_stem(
            rgb, alpha, height,
            stem_pt, (mid_x, mid_y), (attach_x, attach_y),
            3.4, 2.6, stem_c1, stem_c1, 0.27, taper_cap=False,
        )

    for idx, cx, cy, scale, angle, aspect, _stem_pt in leaf_specs:
        shade = rng.uniform(0.80, 1.16)
        warmth = rng.uniform(0.0, 1.0)
        base_col = np.array(
            [
                (54.0 + 24.0 * warmth) * shade,
                (80.0 + 18.0 * (1.0 - warmth * 0.4)) * shade,
                (38.0 + 10.0 * (1.0 - warmth)) * shade,
            ],
            dtype=np.float32,
        )
        vein_col = np.clip(
            base_col * np.array([1.38, 1.32, 1.15], dtype=np.float32) + 14.0, 40, 210
        )
        edge_wear = float(rng.uniform(0.22, 0.72))
        _draw_ivy_leaf(
            rgb, alpha, height,
            cx, cy, scale, angle, aspect,
            base_col, vein_col, edge_wear,
            0.34 + idx * 0.008,
            rng,
        )

    noise = tileable_fbm(size, size, [(32, 32, 0.5), (128, 128, 0.5)], rng)
    rgb = np.clip(rgb * (0.91 + 0.18 * noise[..., None]), 28, 225)

    dil_rgb, dil_h = dilate_rgba_and_height(rgb, alpha, height, iterations=14)
    rgba_u8 = np.zeros((size, size, 4), dtype=np.uint8)
    rgba_u8[..., :3] = np.clip(dil_rgb, 0, 255).astype(np.uint8)
    rgba_u8[..., 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)

    tex_dir = MATERIALS_DIR / "foliage_ivy_atlas" / "textures"
    tex_dir.mkdir(parents=True, exist_ok=True)
    albedo_path = tex_dir / "foliage_ivy_atlas_albedo.png"
    normal_path = tex_dir / "foliage_ivy_atlas_normal.png"

    Image.fromarray(rgba_u8, mode="RGBA").save(albedo_path, format="PNG")
    height_to_normal_map(dil_h, alpha, strength=3.4).save(normal_path, format="PNG")

    write_foliage_tres(
        MATERIALS_DIR / "foliage_ivy_atlas" / "foliage_ivy_atlas.tres",
        "foliage_ivy_atlas",
        "res://assets/materials/foliage_ivy_atlas/textures/foliage_ivy_atlas_albedo.png",
        "res://assets/materials/foliage_ivy_atlas/textures/foliage_ivy_atlas_normal.png",
        roughness=0.72,
    )
    return albedo_path, normal_path


# ---------------------------------------------------------------------------
# 3. Tall Wild Grass & Weed Blades (1024x1024 RGBA, fanning from bottom edge)
# ---------------------------------------------------------------------------
def _draw_grass_blade(
    canvas_rgb: np.ndarray,
    canvas_a: np.ndarray,
    canvas_h: np.ndarray,
    p0: Tuple[float, float],
    p1: Tuple[float, float],
    p2: Tuple[float, float],
    max_width: float,
    col_base: np.ndarray,
    col_mid: np.ndarray,
    col_tip: np.ndarray,
    base_h: float,
) -> None:
    """Draw smooth continuous curved grass blade with central keel fold."""
    h_img, w_img = canvas_a.shape
    pad = int(max_width + 6)
    xs = [p0[0], p1[0], p2[0]]
    ys = [p0[1], p1[1], p2[1]]
    x0 = max(0, int(min(xs)) - pad)
    x1 = min(w_img, int(max(xs)) + pad + 1)
    y0 = max(0, int(min(ys)) - pad)
    y1 = min(h_img, int(max(ys)) + pad + 1)
    if x1 <= x0 or y1 <= y0:
        return

    yy, xx = np.mgrid[y0:y1, x0:x1]
    dist, t_near, signed_s = _bezier_segment_distance(xx, yy, p0, p1, p2, n_segs=40)

    width = (
        max_width
        * (0.68 + 0.32 * np.sin(np.clip(t_near * 2.2, 0.0, math.pi)))
        * ((1.0 - t_near) ** 0.78)
    )
    width = np.maximum(width, 0.9 * (1.0 - t_near))

    alpha = np.clip((width - dist + 0.65) / 1.3, 0.0, 1.0)
    if not np.any(alpha > 0.01):
        return

    norm_s = np.clip(np.abs(signed_s) / np.maximum(width, 1e-3), 0.0, 1.0)
    keel = 1.0 - 0.24 * norm_s + 0.08 * np.cos(norm_s * 14.0)
    side_shade = 0.92 + 0.16 * np.clip(signed_s / np.maximum(width, 1e-3), -1.0, 1.0)

    t1 = np.clip(t_near / 0.55, 0.0, 1.0)[..., None]
    t2 = np.clip((t_near - 0.55) / 0.45, 0.0, 1.0)[..., None]
    rgb = col_base * (1.0 - t1) + col_mid * t1
    rgb = rgb * (1.0 - t2) + col_tip * t2
    rgb = rgb * (keel * side_shade)[..., None]

    h_val = base_h + 0.10 * (1.0 - norm_s) + 0.02 * np.cos(norm_s * 14.0)
    _blend_layer(canvas_rgb, canvas_a, canvas_h, x0, y0, x1, y1, rgb, alpha, h_val)


def generate_foliage_weeds_atlas(size: int = 1024) -> Tuple[Path, Path]:
    rng = np.random.default_rng(8209)
    rgb = np.zeros((size, size, 3), dtype=np.float32)
    alpha = np.zeros((size, size), dtype=np.float32)
    height = np.zeros((size, size), dtype=np.float32)

    blades = []
    for i in range(48):
        x_root = float(rng.uniform(250, 774))
        y_root = float(size - 1)
        fan_bias = (x_root - size * 0.5) / 260.0
        # Mix outward fanning blades with central upright crossing blades
        lean = fan_bias * rng.uniform(90, 220) + rng.normal(0, 95)
        blade_h = float(rng.uniform(340, 910))
        x_tip = float(np.clip(x_root + lean, 48, size - 48))
        y_tip = float(np.clip(y_root - blade_h, 48, size - 160))
        x_mid = float(x_root + lean * rng.uniform(0.32, 0.58))
        y_mid = float(y_root - blade_h * rng.uniform(0.54, 0.72))
        w = float(rng.uniform(10.0, 22.0))
        is_dry = rng.random() < 0.28
        blades.append((i, (x_root, y_root), (x_mid, y_mid), (x_tip, y_tip), w, is_dry))

    blades.sort(key=lambda b: b[3][1])

    for idx, p0, p1, p2, w, is_dry in blades:
        shade = rng.uniform(0.84, 1.15)
        if is_dry:
            c_base = np.array([62.0, 60.0, 34.0], dtype=np.float32) * shade
            c_mid = np.array([108.0, 100.0, 56.0], dtype=np.float32) * shade
            c_tip = np.array([162.0, 148.0, 88.0], dtype=np.float32) * shade
        else:
            c_base = np.array([46.0, 58.0, 28.0], dtype=np.float32) * shade
            c_mid = np.array([86.0, 102.0, 50.0], dtype=np.float32) * shade
            c_tip = np.array([142.0, 134.0, 74.0], dtype=np.float32) * shade

        _draw_grass_blade(
            rgb, alpha, height, p0, p1, p2, w, c_base, c_mid, c_tip, 0.25 + idx * 0.01
        )

    # 4 smooth weed seed stalks with staggered seed pods
    stalk_c0 = np.array([68.0, 72.0, 38.0], dtype=np.float32)
    stalk_c1 = np.array([138.0, 128.0, 72.0], dtype=np.float32)
    for s_idx in range(4):
        rx = float(rng.uniform(350, 670))
        tx = float(np.clip(rx + rng.uniform(-160, 160), 150, size - 150))
        ty = float(rng.uniform(80, 210))
        mx = (rx + tx) * 0.5 + float(rng.uniform(-40, 40))
        my = (size + ty) * 0.5
        _draw_bezier_stem(
            rgb, alpha, height,
            (rx, size - 1), (mx, my), (tx, ty),
            5.0, 2.2, stalk_c0, stalk_c1, 0.65 + s_idx * 0.02, taper_cap=True,
        )
        for k in range(11):
            t = 0.66 + k * 0.032
            sx = (1.0 - t) ** 2 * rx + 2.0 * (1.0 - t) * t * mx + t ** 2 * tx
            sy = (1.0 - t) ** 2 * (size - 1) + 2.0 * (1.0 - t) * t * my + t ** 2 * ty
            side = -1.0 if (k % 2 == 0) else 1.0
            _draw_grass_blade(
                rgb, alpha, height,
                (sx, sy),
                (sx + side * 12.0, sy - 16.0),
                (sx + side * 18.0, sy - 34.0),
                6.2, stalk_c1 * 0.85, stalk_c1, stalk_c1 * 1.15, 0.72,
            )

    noise = tileable_fbm(size, size, [(32, 32, 0.5), (128, 128, 0.5)], rng)
    rgb = np.clip(rgb * (0.92 + 0.16 * noise[..., None]), 28, 230)

    dil_rgb, dil_h = dilate_rgba_and_height(rgb, alpha, height, iterations=14)
    rgba_u8 = np.zeros((size, size, 4), dtype=np.uint8)
    rgba_u8[..., :3] = np.clip(dil_rgb, 0, 255).astype(np.uint8)
    rgba_u8[..., 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)

    tex_dir = MATERIALS_DIR / "foliage_weeds_atlas" / "textures"
    tex_dir.mkdir(parents=True, exist_ok=True)
    albedo_path = tex_dir / "foliage_weeds_atlas_albedo.png"
    normal_path = tex_dir / "foliage_weeds_atlas_normal.png"

    Image.fromarray(rgba_u8, mode="RGBA").save(albedo_path, format="PNG")
    height_to_normal_map(dil_h, alpha, strength=3.0).save(normal_path, format="PNG")

    write_foliage_tres(
        MATERIALS_DIR / "foliage_weeds_atlas" / "foliage_weeds_atlas.tres",
        "foliage_weeds_atlas",
        "res://assets/materials/foliage_weeds_atlas/textures/foliage_weeds_atlas_albedo.png",
        "res://assets/materials/foliage_weeds_atlas/textures/foliage_weeds_atlas_normal.png",
        roughness=0.76,
    )
    return albedo_path, normal_path


# ---------------------------------------------------------------------------
# 4. Oak Leaf Branch Cluster (1024x1024 RGBA)
# ---------------------------------------------------------------------------
def _draw_oak_leaf(
    canvas_rgb: np.ndarray,
    canvas_a: np.ndarray,
    canvas_h: np.ndarray,
    cx: float,
    cy: float,
    length: float,
    angle: float,
    width_ratio: float,
    base_col: np.ndarray,
    vein_col: np.ndarray,
    autumn_tint: float,
    base_h: float,
    rng: np.random.Generator,
) -> None:
    """Draw elongated lobed oak leaf (Quercus) with rounded lobes & pinnate veins."""
    h_img, w_img = canvas_a.shape
    half = int(length * 0.95) + 8
    x0 = max(0, int(cx) - half)
    x1 = min(w_img, int(cx) + half + 1)
    y0 = max(0, int(cy) - half)
    y1 = min(h_img, int(cy) + half + 1)
    if x1 <= x0 or y1 <= y0:
        return

    yy, xx = np.mgrid[y0:y1, x0:x1]
    px = (xx - cx) / length
    py = (yy - cy) / length
    ca, sa = math.cos(angle), math.sin(angle)
    u = px * ca + py * sa
    v = -px * sa + py * ca + 0.45  # petiole at v=0, rounded apex at v=1.0

    vc = np.clip(v, 0.0, 1.0)
    # Elongated obovate oak silhouette: narrow base, widest near v=0.64, rounded tip
    envelope = (np.sin(vc * math.pi) ** 0.58) * (0.38 + 0.72 * vc) * width_ratio

    # 4.5 rounded oak lobes per side (power < 1 rounds lobe peaks & deepens rounded sinuses)
    phase = float(rng.uniform(0.0, 0.25))
    raw_cos = 0.5 + 0.5 * np.cos((vc * 4.2 + phase) * 2.0 * math.pi)
    lobe_wave = raw_cos ** 0.62
    lobe_amp = (np.sin(vc * math.pi) ** 0.9) * 0.24 * width_ratio
    half_w = envelope * 0.72 + lobe_amp * lobe_wave

    in_v = np.minimum(v - 0.03, 1.0 - v)
    sdf = np.minimum(half_w - np.abs(u), in_v * 0.8) * length
    alpha = np.clip((sdf + 0.65) / 1.3, 0.0, 1.0)
    if not np.any(alpha > 0.01):
        return

    # Pinnate midrib + side veins aimed into lobes
    midrib = (
        np.clip(1.0 - np.abs(u) / 0.015, 0.0, 1.0)
        * np.clip((0.94 - v) * 10.0, 0.0, 1.0)
        * np.clip(v * 12.0, 0.0, 1.0)
    )
    side_coord = (vc - np.abs(u) * 0.95) * 4.2 + phase
    side_dist = np.abs(side_coord - np.round(side_coord))
    side_veins = (
        np.clip(1.0 - side_dist / 0.075, 0.0, 1.0)
        * np.clip((half_w * 0.85 - np.abs(u)) * 8.0, 0.0, 1.0)
        * np.clip((v - 0.14) * 8.0, 0.0, 1.0)
        * np.clip((0.90 - v) * 8.0, 0.0, 1.0)
    )
    vein_mask = np.maximum(midrib, side_veins * 0.68)

    norm_u = np.clip(np.abs(u) / np.maximum(half_w, 1e-4), 0.0, 1.0)
    shade = 0.88 + 0.18 * (1.0 - norm_u) - 0.06 * vc
    rgb = base_col * shade[..., None]
    rgb = rgb * (1.0 - vein_mask[..., None] * 0.70) + vein_col * (
        vein_mask[..., None] * 0.70
    )

    tip_wear = np.clip((vc - 0.55) * 1.3 + norm_u * 0.42 - 0.36, 0.0, 1.0) * autumn_tint
    autumn_col = np.array([138.0, 108.0, 44.0], dtype=np.float32)
    rgb = rgb * (1.0 - tip_wear[..., None] * 0.58) + autumn_col * (
        tip_wear[..., None] * 0.58
    )

    dome = np.sqrt(np.clip(1.0 - norm_u ** 2 * 0.6, 0.0, 1.0)) * 0.11
    h_val = base_h + dome + vein_mask * 0.04
    _blend_layer(canvas_rgb, canvas_a, canvas_h, x0, y0, x1, y1, rgb, alpha, h_val)


def generate_foliage_tree_canopy(size: int = 1024) -> Tuple[Path, Path]:
    rng = np.random.default_rng(9307)
    rgb = np.zeros((size, size, 3), dtype=np.float32)
    alpha = np.zeros((size, size), dtype=np.float32)
    height = np.zeros((size, size), dtype=np.float32)

    # Branching oak twigs anchored at bottom-center edge (512, 1023)
    twigs = [
        ((512, 1023), (506, 670), (518, 220), 14.0, 4.0),
        ((510, 810), (360, 620), (225, 375), 9.5, 3.5),
        ((510, 760), (675, 590), (805, 355), 9.5, 3.5),
        ((512, 550), (385, 410), (275, 240), 7.5, 3.0),
        ((512, 510), (645, 380), (755, 225), 7.5, 3.0),
        ((410, 650), (295, 610), (205, 555), 6.5, 2.5),
        ((635, 615), (755, 585), (835, 525), 6.5, 2.5),
    ]
    twig_c0 = np.array([70.0, 56.0, 40.0], dtype=np.float32)
    twig_c1 = np.array([86.0, 70.0, 48.0], dtype=np.float32)
    for p0, p1, p2, r0, r1 in twigs:
        _draw_bezier_stem(
            rgb, alpha, height, p0, p1, p2, r0, r1, twig_c0, twig_c1, 0.25, taper_cap=False
        )

    leaves = []
    # Terminal oak leaves capping each twig tip so no bare sticks poke out
    for t_idx, (p0, p1, p2, _, _) in enumerate(twigs):
        tx, ty = float(p2[0]), float(p2[1])
        # Twig end tangent direction
        ang = math.atan2(-(tx - p1[0]), -(ty - p1[1])) + float(rng.uniform(-0.25, 0.25))
        # Rotate leaf so v points outward: tip direction is (-sin(angle), cos(angle))?
        # Wait: in _draw_oak_leaf, v = -px*sa + py*ca + 0.45. Increasing v moves along (-sa, ca).
        # To move along (dx, dy) = (tx - p1[0], ty - p1[1]), set (-sa, ca) = (dx, dy)/norm => sa = -dx, ca = dy => angle = atan2(-dx, dy)
        ang = math.atan2(-(tx - p1[0]), ty - p1[1]) + float(rng.uniform(-0.3, 0.3))
        leaves.append((t_idx, tx, ty, float(rng.uniform(148, 185)), float(rng.uniform(0.39, 0.46)), ang, p2))

    # Lateral oak leaves fanning off all twigs
    for i in range(46):
        p0, p1, p2, _, _ = twigs[i % len(twigs)]
        t = rng.uniform(0.20, 0.96)
        bx = (1.0 - t) ** 2 * p0[0] + 2.0 * (1.0 - t) * t * p1[0] + t ** 2 * p2[0]
        by = (1.0 - t) ** 2 * p0[1] + 2.0 * (1.0 - t) * t * p1[1] + t ** 2 * p2[1]
        cx = float(np.clip(bx + rng.normal(0, 36), 145, size - 145))
        cy = float(np.clip(by + rng.normal(0, 34), 145, size - 155))
        dx = cx - bx
        dy = cy - by
        out_ang = math.atan2(-dx, dy) + float(rng.uniform(-0.65, 0.65))
        length = float(rng.uniform(138.0, 208.0))
        width_ratio = float(rng.uniform(0.38, 0.48))
        leaves.append((10 + i, cx, cy, length, width_ratio, out_ang, (bx, by)))

    # Draw all petioles behind leaves first so no petiole crosses over a leaf blade
    for idx, cx, cy, length, _width_ratio, angle, twig_pt in leaves:
        sa, ca = math.sin(angle), math.cos(angle)
        base_x = cx + sa * (length * 0.36)
        base_y = cy - ca * (length * 0.36)
        _draw_bezier_stem(
            rgb, alpha, height,
            twig_pt, ((twig_pt[0] + base_x) * 0.5, (twig_pt[1] + base_y) * 0.5), (base_x, base_y),
            3.2, 2.4, twig_c1, twig_c1, 0.27, taper_cap=False,
        )

    for idx, cx, cy, length, width_ratio, angle, _twig_pt in leaves:
        shade = rng.uniform(0.80, 1.18)
        autumn = rng.uniform(0.15, 0.85)
        base_col = np.array(
            [
                (64.0 + 30.0 * autumn) * shade,
                (86.0 + 12.0 * (1.0 - autumn * 0.35)) * shade,
                (38.0 + 6.0 * (1.0 - autumn)) * shade,
            ],
            dtype=np.float32,
        )
        vein_col = np.clip(
            base_col * np.array([1.35, 1.28, 1.12], dtype=np.float32) + 14.0, 45, 208
        )
        _draw_oak_leaf(
            rgb, alpha, height,
            cx, cy, length, angle, width_ratio,
            base_col, vein_col, autumn,
            0.34 + idx * 0.008,
            rng,
        )

    noise = tileable_fbm(size, size, [(32, 32, 0.5), (128, 128, 0.5)], rng)
    rgb = np.clip(rgb * (0.91 + 0.18 * noise[..., None]), 28, 225)

    dil_rgb, dil_h = dilate_rgba_and_height(rgb, alpha, height, iterations=14)
    rgba_u8 = np.zeros((size, size, 4), dtype=np.uint8)
    rgba_u8[..., :3] = np.clip(dil_rgb, 0, 255).astype(np.uint8)
    rgba_u8[..., 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)

    tex_dir = MATERIALS_DIR / "foliage_tree_canopy" / "textures"
    tex_dir.mkdir(parents=True, exist_ok=True)
    albedo_path = tex_dir / "foliage_tree_canopy_albedo.png"
    normal_path = tex_dir / "foliage_tree_canopy_normal.png"

    Image.fromarray(rgba_u8, mode="RGBA").save(albedo_path, format="PNG")
    height_to_normal_map(dil_h, alpha, strength=3.4).save(normal_path, format="PNG")

    write_foliage_tres(
        MATERIALS_DIR / "foliage_tree_canopy" / "foliage_tree_canopy.tres",
        "foliage_tree_canopy",
        "res://assets/materials/foliage_tree_canopy/textures/foliage_tree_canopy_albedo.png",
        "res://assets/materials/foliage_tree_canopy/textures/foliage_tree_canopy_normal.png",
        roughness=0.74,
    )
    return albedo_path, normal_path


def main() -> None:
    bark_alb = generate_overgrown_bark(1024)
    print(f"Generated bark albedo: {bark_alb}")
    ivy_alb, ivy_norm = generate_foliage_ivy_atlas(1024)
    print(f"Generated ivy atlas: {ivy_alb}, {ivy_norm}")
    weeds_alb, weeds_norm = generate_foliage_weeds_atlas(1024)
    print(f"Generated weeds atlas: {weeds_alb}, {weeds_norm}")
    canopy_alb, canopy_norm = generate_foliage_tree_canopy(1024)
    print(f"Generated canopy atlas: {canopy_alb}, {canopy_norm}")


if __name__ == "__main__":
    main()
