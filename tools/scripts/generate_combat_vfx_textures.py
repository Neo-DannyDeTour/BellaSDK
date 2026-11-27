"""Generates deterministic combat & environment VFX atlases and noise textures for BellaSDK.

Outputs:
  1. assets/vfx/smoke/hl2_smoke_cloud_4x4.png   (2048x2048 RGBA, 4x4 cauliflower smoke clouds)
  2. assets/vfx/smoke/hl2_smoke_normal_4x4.png  (2048x2048 RGBA, 4x4 OpenGL +Y tangent normals)
  3. assets/vfx/smoke/smoke_puff_8x8.png        (2048x2048 RGBA, 8x8 expanding smoke sequence)
  4. assets/vfx/fire/fire_tongues_4x4.png       (2048x2048 RGBA, 4x4 crisp licking flame tongues)
  5. assets/vfx/fire/fire_noise_tile.png        (512x512 RGBA, seamlessly tileable warped FBM)
  6. assets/vfx/fire_flipbook_8x8.png           (2048x2048 RGBA, 8x8 looping HDR-ready flames)
  7. assets/vfx/muzzle/muzzle_flash_atlas.png   (1024x1024 RGB, 2x2 blend_add muzzle flashes)
  8. assets/vfx/impacts/impact_debris_2x2.png   (512x512 RGBA, 2x2 impact debris sprites)
"""

from __future__ import annotations

import math
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

REPO_ROOT: Path = Path(__file__).resolve().parents[2]
VFX_DIR: Path = REPO_ROOT / "assets" / "vfx"


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    """Vectorized cubic Hermite smoothstep in [0, 1]."""
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def quintic_fade(t: np.ndarray) -> np.ndarray:
    """Perlin quintic interpolation curve 6t^5 - 15t^4 + 10t^3."""
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def perlin2d(
    x: np.ndarray,
    y: np.ndarray,
    period_x: int,
    period_y: int,
    seed: int,
) -> np.ndarray:
    """Vectorized periodic 2D Perlin gradient noise in roughly [-1, 1]."""
    rng = np.random.Generator(np.random.PCG64(seed))
    angles = rng.uniform(0.0, 2.0 * np.pi, size=(period_y, period_x)).astype(np.float32)
    gx_table = np.cos(angles)
    gy_table = np.sin(angles)

    x_floor = np.floor(x)
    y_floor = np.floor(y)
    xf = (x - x_floor).astype(np.float32)
    yf = (y - y_floor).astype(np.float32)

    ix0 = np.mod(x_floor.astype(np.int32), period_x)
    iy0 = np.mod(y_floor.astype(np.int32), period_y)
    ix1 = np.mod(ix0 + 1, period_x)
    iy1 = np.mod(iy0 + 1, period_y)

    g00x, g00y = gx_table[iy0, ix0], gy_table[iy0, ix0]
    g10x, g10y = gx_table[iy0, ix1], gy_table[iy0, ix1]
    g01x, g01y = gx_table[iy1, ix0], gy_table[iy1, ix0]
    g11x, g11y = gx_table[iy1, ix1], gy_table[iy1, ix1]

    d00 = g00x * xf + g00y * yf
    d10 = g10x * (xf - 1.0) + g10y * yf
    d01 = g01x * xf + g01y * (yf - 1.0)
    d11 = g11x * (xf - 1.0) + g11y * (yf - 1.0)

    u = quintic_fade(xf)
    v = quintic_fade(yf)

    nx0 = d00 + u * (d10 - d00)
    nx1 = d01 + u * (d11 - d01)
    return (nx0 + v * (nx1 - nx0)) * 1.4142135


def fbm2d(
    u01: np.ndarray,
    v01: np.ndarray,
    base_period_x: int,
    base_period_y: int,
    octaves: int,
    gain: float,
    seed: int,
    billow: bool = False,
) -> np.ndarray:
    """Periodic multi-octave 2D Perlin FBM on normalized [0, 1] coords, returning [0, 1]."""
    total = np.zeros_like(u01, dtype=np.float32)
    amp = 1.0
    norm = 0.0
    px = base_period_x
    py = base_period_y
    for i in range(octaves):
        n = perlin2d(u01 * px, v01 * py, px, py, seed + i * 97)
        if billow:
            val = 1.0 - np.abs(n)
        else:
            val = 0.5 * n + 0.5
        total += val * amp
        norm += amp
        amp *= gain
        px *= 2
        py *= 2
    return np.clip(total / max(norm, 1e-6), 0.0, 1.0)


def tile_margin_mask(u: np.ndarray, v: np.ndarray, inner: float = 0.80, outer: float = 0.93) -> np.ndarray:
    """Guarantees smooth falloff to exact 0.0 before every tile edge (u, v in [-1, 1])."""
    box_d = np.maximum(np.abs(u), np.abs(v))
    rad_d = np.sqrt(u * u + v * v)
    box_mask = 1.0 - smoothstep(inner + 0.04, outer, box_d)
    rad_mask = 1.0 - smoothstep(inner, outer + 0.02, rad_d)
    return box_mask * rad_mask


def smin_exp(a: np.ndarray, b: np.ndarray, k: float = 0.14) -> np.ndarray:
    """Smooth minimum for organic lobe blending."""
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


def smax_poly(a: np.ndarray, b: np.ndarray, k: float = 0.12) -> np.ndarray:
    """Smooth maximum for blending overlapping hemisphere lobe heights."""
    h = np.clip(0.5 + 0.5 * (a - b) / k, 0.0, 1.0)
    return b * (1.0 - h) + a * h + k * h * (1.0 - h)


def build_cauliflower_cloud_cell(
    size: int,
    seed: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Generate one lush full-frame billowing cauliflower cloud cell without circular halos.

    Returns (heightfield, density, top_lit_height, erosion_detail, alpha) all float32 in [0, 1].
    """
    coords = np.linspace(-1.0, 1.0, size, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    u01 = (uu + 1.0) * 0.5
    v01 = (vv + 1.0) * 0.5

    rng = np.random.Generator(np.random.PCG64(seed))

    wx = fbm2d(u01, v01, 3, 3, octaves=3, gain=0.5, seed=seed + 11) - 0.5
    wy = fbm2d(u01, v01, 3, 3, octaves=3, gain=0.5, seed=seed + 37) - 0.5
    wu01 = u01 + wx * 0.15
    wv01 = v01 + wy * 0.15

    billow_macro = fbm2d(wu01, wv01, 4, 4, octaves=4, gain=0.52, seed=seed + 101, billow=True)
    billow_fine = fbm2d(wu01, wv01, 8, 8, octaves=3, gain=0.48, seed=seed + 211, billow=True)
    erosion_fbm = fbm2d(wu01, wv01, 5, 5, octaves=4, gain=0.52, seed=seed + 307, billow=False)

    # Full-frame clustered 3D spherical lobes filling ~76-84% of the tile cleanly.
    height = np.zeros((size, size), dtype=np.float32)
    rot = rng.uniform(0.0, 2.0 * np.pi)
    for i in range(15):
        if i < 3:
            ang = rot + i * (2.0 * np.pi / 3.0) + rng.uniform(-0.35, 0.35)
            dist = rng.uniform(0.05, 0.24)
            lr = rng.uniform(0.42, 0.52)
            lobe_amp = rng.uniform(0.86, 1.0)
        elif i < 9:
            ang = rot + (i - 3) * (2.0 * np.pi / 6.0) + rng.uniform(-0.3, 0.3)
            dist = rng.uniform(0.24, 0.44)
            lr = rng.uniform(0.28, 0.38)
            lobe_amp = rng.uniform(0.66, 0.88)
        else:
            ang = rng.uniform(0.0, 2.0 * np.pi)
            dist = rng.uniform(0.36, 0.54)
            lr = rng.uniform(0.18, 0.27)
            lobe_amp = rng.uniform(0.45, 0.72)

        cx = math.cos(ang) * dist
        cy = math.sin(ang) * dist * 0.90
        du = uu - cx + (wx * 0.14)
        dv = vv - cy + (wy * 0.14)
        d2 = (du * du + dv * dv) / max(lr * lr, 1e-4)
        sphere_h = np.sqrt(np.maximum(0.0, 1.0 - d2)) * lobe_amp
        height = smax_poly(height, sphere_h, k=0.14)

    # Carve plump cauliflower ridges into the heightfield.
    cauliflower_mod = 0.62 * billow_macro + 0.38 * billow_fine
    height_raw = height * (0.58 + 0.46 * cauliflower_mod)

    # Organic lobe silhouette cutoff BEFORE tile margin so no outer circular ring forms.
    margin = tile_margin_mask(uu, vv, inner=0.80, outer=0.93)
    silhouette = smoothstep(0.11, 0.28, height_raw) * margin
    height_clean = np.clip(height_raw * silhouette, 0.0, 1.0)

    # Smooth alpha follows the organic cloud lobes cleanly to zero.
    alpha = np.clip(smoothstep(0.11, 0.42, height_raw) * margin, 0.0, 1.0)

    # R = cloud density, G = top-lit lobe height, B = turbulence erosion detail.
    # All RGB channels scale cleanly with silhouette so there is zero color halo outside alpha.
    density = np.clip(smoothstep(0.02, 0.62, height_raw) * (0.76 + 0.24 * cauliflower_mod) * alpha, 0.0, 1.0)
    grad_y = np.gradient(height_clean, axis=0)
    top_bias = np.clip(-grad_y * 12.0, -0.35, 0.45)
    top_lit = np.clip((height_raw * 0.76 + cauliflower_mod * 0.28 + top_bias * 0.28) * alpha, 0.0, 1.0)
    erosion_detail = np.clip((0.55 * erosion_fbm + 0.45 * billow_fine) * alpha, 0.0, 1.0)

    return height_clean, density, top_lit, erosion_detail, alpha


def heightfield_to_opengl_normal(height: np.ndarray, mask: np.ndarray, strength: float = 28.0) -> np.ndarray:
    """Convert a float32 heightfield [0,1] into OpenGL +Y tangent-space RGBA uint8 normals."""
    pad = np.pad(height, 1, mode="edge")
    h_smooth = (
        4.0 * pad[1:-1, 1:-1]
        + 2.0 * (pad[:-2, 1:-1] + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:])
        + (pad[:-2, :-2] + pad[:-2, 2:] + pad[2:, :-2] + pad[2:, 2:])
    ) / 16.0

    dy_img, dx_img = np.gradient(h_smooth)
    nx = -dx_img * strength
    ny = dy_img * strength
    nz = np.ones_like(nx, dtype=np.float32)

    fade = smoothstep(0.01, 0.16, mask)
    nx *= fade
    ny *= fade

    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    nx *= inv_len
    ny *= inv_len
    nz *= inv_len

    rgba = np.empty((*height.shape, 4), dtype=np.uint8)
    rgba[..., 0] = np.clip(np.round((nx * 0.5 + 0.5) * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 1] = np.clip(np.round((ny * 0.5 + 0.5) * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 2] = np.clip(np.round((nz * 0.5 + 0.5) * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 3] = 255
    return rgba


def generate_hl2_smoke_atlases() -> None:
    """Generate hl2_smoke_cloud_4x4.png and matched hl2_smoke_normal_4x4.png (2048x2048)."""
    grid = 4
    tile = 512
    atlas_size = grid * tile

    cloud_atlas = np.zeros((atlas_size, atlas_size, 4), dtype=np.uint8)
    normal_atlas = np.zeros((atlas_size, atlas_size, 4), dtype=np.uint8)
    normal_atlas[..., 0] = 128
    normal_atlas[..., 1] = 128
    normal_atlas[..., 2] = 255
    normal_atlas[..., 3] = 255

    for idx in range(grid * grid):
        row = idx // grid
        col = idx % grid
        seed = 1000 + idx * 173
        height, density, top_lit, erosion, alpha = build_cauliflower_cloud_cell(tile, seed=seed)
        normals = heightfield_to_opengl_normal(height, alpha, strength=30.0)

        y0, y1 = row * tile, (row + 1) * tile
        x0, x1 = col * tile, (col + 1) * tile

        cloud_atlas[y0:y1, x0:x1, 0] = np.clip(np.round(density * 255.0), 0.0, 255.0).astype(np.uint8)
        cloud_atlas[y0:y1, x0:x1, 1] = np.clip(np.round(top_lit * 255.0), 0.0, 255.0).astype(np.uint8)
        cloud_atlas[y0:y1, x0:x1, 2] = np.clip(np.round(erosion * 255.0), 0.0, 255.0).astype(np.uint8)
        cloud_atlas[y0:y1, x0:x1, 3] = np.clip(np.round(alpha * 255.0), 0.0, 255.0).astype(np.uint8)
        normal_atlas[y0:y1, x0:x1] = normals

    out_dir = VFX_DIR / "smoke"
    out_dir.mkdir(parents=True, exist_ok=True)
    Image.fromarray(cloud_atlas, mode="RGBA").save(out_dir / "hl2_smoke_cloud_4x4.png")
    Image.fromarray(normal_atlas, mode="RGBA").save(out_dir / "hl2_smoke_normal_4x4.png")


def generate_smoke_puff_8x8() -> None:
    """Generate full-frame 2048x2048 8x8 billowing expanding & dissipating smoke puff sequence."""
    grid = 8
    tile = 256
    atlas_size = grid * tile
    atlas = np.zeros((atlas_size, atlas_size, 4), dtype=np.uint8)

    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    u01 = (uu + 1.0) * 0.5
    v01 = (vv + 1.0) * 0.5
    margin = tile_margin_mask(uu, vv, inner=0.80, outer=0.93)

    rng = np.random.Generator(np.random.PCG64(4242))
    lobes: list[tuple[float, float, float, float, float]] = []
    for i in range(14):
        ang = i * (2.0 * np.pi / 14.0) + rng.uniform(-0.25, 0.25)
        dist = rng.uniform(0.08, 0.42) if i > 2 else rng.uniform(0.0, 0.14)
        rad = rng.uniform(0.32, 0.44) if i < 6 else rng.uniform(0.22, 0.34)
        amp = rng.uniform(0.78, 1.0) if i < 6 else rng.uniform(0.58, 0.84)
        spin = rng.uniform(-0.28, 0.28)
        lobes.append((ang, dist, rad, amp, spin))

    for idx in range(grid * grid):
        t = idx / float(grid * grid - 1)
        # Expands rapidly from ~58% tile diameter to full ~86% tile diameter, then erodes cleanly.
        expand = 0.62 + 0.48 * (1.0 - (1.0 - t) ** 2.2)
        erosion_prog = max(0.0, (t - 0.38) / 0.62)

        adv_v = (v01 + t * 0.36) % 1.0
        adv_u = (u01 + 0.045 * math.sin(t * 2.0 * math.pi)) % 1.0

        wx = fbm2d(adv_u, adv_v, 3, 3, octaves=3, gain=0.5, seed=5001) - 0.5
        wy = fbm2d(adv_u, adv_v, 3, 3, octaves=3, gain=0.5, seed=5077) - 0.5
        wu = (adv_u + wx * 0.14) % 1.0
        wv = (adv_v + wy * 0.14) % 1.0

        billow = fbm2d(wu, wv, 4, 4, octaves=4, gain=0.52, seed=5113, billow=True)
        detail = fbm2d(wu, wv, 7, 7, octaves=3, gain=0.5, seed=5209, billow=False)

        height = np.zeros((tile, tile), dtype=np.float32)
        for ang, dist, rad, amp, spin in lobes:
            a_t = ang + spin * t
            d_t = dist * expand
            r_t = rad * (0.76 + 0.38 * expand)
            cx = math.cos(a_t) * d_t
            cy = math.sin(a_t) * d_t - 0.04 * t
            du = uu - cx + wx * (0.12 + 0.10 * t)
            dv = vv - cy + wy * (0.12 + 0.10 * t)
            d2 = (du * du + dv * dv) / max(r_t * r_t, 1e-4)
            sh = np.sqrt(np.maximum(0.0, 1.0 - d2)) * amp
            height = smax_poly(height, sh, k=0.14)

        height_mod = height * (0.60 + 0.46 * billow)
        # Organic lobe silhouette gate BEFORE margin so no circular outer halo appears.
        erode_cut = 0.08 + 0.46 * (erosion_prog ** 1.35)
        density = height_mod * (0.72 + 0.28 * detail)
        alpha = smoothstep(erode_cut, erode_cut + 0.25, density) * (1.0 - 0.72 * (erosion_prog ** 2.2))
        alpha = np.clip(alpha * margin, 0.0, 1.0)

        height_masked = height_mod * smoothstep(0.02, 0.18, alpha)
        grad_y = np.gradient(height_masked, axis=0)
        lit = np.clip(0.68 + 0.24 * billow - grad_y * 4.5, 0.62, 0.98)

        row, col = divmod(idx, grid)
        y0, y1 = row * tile, (row + 1) * tile
        x0, x1 = col * tile, (col + 1) * tile
        nz = alpha > 0.002
        atlas[y0:y1, x0:x1, 0] = np.where(nz, np.clip(np.round(lit * 246.0), 0.0, 255.0).astype(np.uint8), 0)
        atlas[y0:y1, x0:x1, 1] = np.where(nz, np.clip(np.round(lit * 244.0), 0.0, 255.0).astype(np.uint8), 0)
        atlas[y0:y1, x0:x1, 2] = np.where(nz, np.clip(np.round(lit * 240.0), 0.0, 255.0).astype(np.uint8), 0)
        atlas[y0:y1, x0:x1, 3] = np.clip(np.round(alpha * 255.0), 0.0, 255.0).astype(np.uint8)

    out_path = VFX_DIR / "smoke" / "smoke_puff_8x8.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, mode="RGBA").save(out_path)


def generate_fire_noise_tile() -> None:
    """Generate 512x512 seamlessly tileable multi-octave domain-warped FBM noise."""
    size = 512
    coords = np.linspace(0.0, 1.0, size, endpoint=False, dtype=np.float32)
    v01, u01 = np.meshgrid(coords, coords, indexing="ij")

    wx1 = fbm2d(u01, v01, 4, 3, octaves=4, gain=0.52, seed=7001) - 0.5
    wy1 = fbm2d(u01, v01, 4, 3, octaves=4, gain=0.52, seed=7053) - 0.5
    wu1 = (u01 + wx1 * 0.20) % 1.0
    wv1 = (v01 + wy1 * 0.24) % 1.0

    wx2 = fbm2d(wu1, wv1, 6, 5, octaves=3, gain=0.5, seed=7109) - 0.5
    wy2 = fbm2d(wu1, wv1, 6, 5, octaves=3, gain=0.5, seed=7187) - 0.5
    wu2 = (wu1 + wx2 * 0.11) % 1.0
    wv2 = (wv1 + wy2 * 0.14) % 1.0

    main_fbm = fbm2d(wu2, wv2, 6, 5, octaves=5, gain=0.52, seed=7243, billow=False)
    val = smoothstep(0.16, 0.84, main_fbm)
    gray = np.clip(np.round(val * 255.0), 0.0, 255.0).astype(np.uint8)

    rgba = np.empty((size, size, 4), dtype=np.uint8)
    rgba[..., 0] = gray
    rgba[..., 1] = gray
    rgba[..., 2] = gray
    rgba[..., 3] = 255

    out_path = VFX_DIR / "fire" / "fire_noise_tile.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, mode="RGBA").save(out_path)


def _eval_flame_tongue_field(
    uu: np.ndarray,
    vv: np.ndarray,
    seed: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Compute crisp zero-stipple licking flame fields: (core_heat, outer_body, curl_detail, alpha)."""
    rng = np.random.Generator(np.random.PCG64(seed))
    u01 = (uu + 1.0) * 0.5
    v01 = (vv + 1.0) * 0.5

    # Smooth low-frequency organic S-curve flow (zero stipple).
    sway_x = fbm2d(u01, v01, 3, 3, octaves=3, gain=0.42, seed=seed + 13) - 0.5
    sway_y = fbm2d(u01, v01, 3, 3, octaves=3, gain=0.42, seed=seed + 41) - 0.5

    h = np.clip((0.68 - vv) / 1.50, 0.0, 1.15)
    bend = 0.16 * np.sin(h * 5.0 + rng.uniform(0.0, 6.28)) * (h ** 1.1) + sway_x * (0.12 + 0.30 * h)
    u_bent = uu - bend
    v_bent = vv + sway_y * (0.06 + 0.12 * h)

    # Rounded glowing hearth base (centered at v=+0.36, never flat-bottomed).
    base_rx = 0.34
    base_ry = 0.30
    sdf = np.sqrt((u_bent / base_rx) ** 2 + ((v_bent - 0.36) / base_ry) ** 2) - 1.0
    sdf *= 0.28

    # 4 distinct S-curving licking flame tongues rising to pointed tips.
    tongue_specs = [
        (-0.20, rng.uniform(-0.62, -0.32), 0.38, rng.uniform(0.11, 0.15)),
        (-0.04, rng.uniform(-0.82, -0.62), 0.36, rng.uniform(0.13, 0.17)),
        (0.14, rng.uniform(-0.74, -0.44), 0.38, rng.uniform(0.11, 0.15)),
        (rng.uniform(-0.12, 0.12), rng.uniform(-0.78, -0.52), 0.32, rng.uniform(0.09, 0.13)),
    ]
    for ox, top_y, bot_y, base_r in tongue_specs:
        freq = rng.uniform(4.2, 6.8)
        amp = rng.uniform(0.06, 0.13)
        ph = rng.uniform(0.0, 2.0 * np.pi)

        t_h = np.clip((bot_y - v_bent) / max(bot_y - top_y, 0.25), 0.0, 1.0)
        t_center = ox * (1.0 - 0.25 * t_h) + amp * np.sin(t_h * freq + ph) * (t_h ** 0.75)
        t_radius = base_r * ((1.0 - t_h * 0.92) ** 0.85) + 0.008
        v_clamp = np.clip(v_bent, top_y, bot_y)
        tongue_sdf = np.sqrt((u_bent - t_center) ** 2 + (v_bent - v_clamp) ** 2) - t_radius
        sdf = smin_exp(sdf, tongue_sdf, k=0.075)

    # 1-2 detached rising lick droplets above the tips.
    for _ in range(2):
        dx0 = rng.uniform(-0.18, 0.18)
        dy0 = rng.uniform(-0.78, -0.54)
        dr = rng.uniform(0.025, 0.048)
        d_sdf = np.sqrt(((u_bent - dx0) / 0.65) ** 2 + ((v_bent - dy0) / 1.45) ** 2) - dr
        sdf = smin_exp(sdf, d_sdf, k=0.025)

    edge_wave = fbm2d(u01, v01, 4, 4, octaves=2, gain=0.4, seed=seed + 89) - 0.5
    sdf_clean = sdf + edge_wave * 0.028

    margin = tile_margin_mask(uu, vv, inner=0.80, outer=0.93)
    alpha = np.clip((1.0 - smoothstep(-0.014, 0.016, sdf_clean)) * margin, 0.0, 1.0)

    # Smooth licking curl ribbons inside the flame (zero stipple).
    curl_wave = np.sin(u_bent * 12.0 + v_bent * 8.0 + sway_x * 6.5) * 0.5 + 0.5
    curl_fbm = fbm2d(u01, v01, 4, 5, octaves=3, gain=0.45, seed=seed + 151)
    curl_detail = np.clip(0.58 * curl_wave + 0.42 * curl_fbm, 0.0, 1.0)

    # Full luminous outer body across entire silhouette (no dark/black rim).
    outer_body = np.clip(0.55 + 0.45 * smoothstep(0.0, 0.18, -sdf_clean), 0.0, 1.0) * smoothstep(0.0, 0.05, alpha)

    # Incandescent core heat peaking in hearth & hot tongue spines.
    core_dist = np.sqrt((u_bent * 1.45) ** 2 + ((v_bent - 0.28) * 1.05) ** 2)
    core_heat = np.clip(
        smoothstep(0.56, 0.02, core_dist) * 0.85 + smoothstep(0.02, 0.18, -sdf_clean) * 0.55,
        0.0,
        1.0,
    ) * smoothstep(0.0, 0.05, alpha)

    return core_heat, outer_body, curl_detail, alpha


def generate_fire_tongues_4x4() -> None:
    """Generate 2048x2048 4x4 crisp zero-noise licking flame tongues (zero green pixels)."""
    grid = 4
    tile = 512
    atlas_size = grid * tile
    atlas = np.zeros((atlas_size, atlas_size, 4), dtype=np.uint8)

    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")

    for idx in range(grid * grid):
        core_heat, outer_body, curl_detail, alpha = _eval_flame_tongue_field(uu, vv, seed=8000 + idx * 193)

        # R=incandescent core heat, G=outer flame body, B=licking curl detail, A=mask.
        # Keep R >= G >= B everywhere so zero green pixels appear, while staying bright to the edge.
        r_ch = np.clip(0.72 * outer_body + 0.34 * core_heat, 0.0, 1.0)
        g_ch = np.clip(0.32 * outer_body + 0.62 * core_heat, 0.0, r_ch)
        b_ch = np.clip(0.28 * curl_detail * outer_body + 0.55 * (core_heat ** 1.5), 0.0, g_ch)

        row, col = divmod(idx, grid)
        y0, y1 = row * tile, (row + 1) * tile
        x0, x1 = col * tile, (col + 1) * tile

        mask_nz = alpha > 0.002
        atlas[y0:y1, x0:x1, 0] = np.where(mask_nz, np.clip(np.round(r_ch * 255.0), 0.0, 255.0).astype(np.uint8), 0)
        atlas[y0:y1, x0:x1, 1] = np.where(mask_nz, np.clip(np.round(g_ch * 255.0), 0.0, 255.0).astype(np.uint8), 0)
        atlas[y0:y1, x0:x1, 2] = np.where(mask_nz, np.clip(np.round(b_ch * 255.0), 0.0, 255.0).astype(np.uint8), 0)
        atlas[y0:y1, x0:x1, 3] = np.clip(np.round(alpha * 255.0), 0.0, 255.0).astype(np.uint8)

    out_path = VFX_DIR / "fire" / "fire_tongues_4x4.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, mode="RGBA").save(out_path)


def generate_fire_flipbook_8x8() -> None:
    """Generate clean 2048x2048 8x8 looping turbulent HDR-ready fire flipbook (zero green)."""
    grid = 8
    tile = 256
    atlas_size = grid * tile
    atlas = np.zeros((atlas_size, atlas_size, 4), dtype=np.uint8)

    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    u01 = (uu + 1.0) * 0.5
    v01 = (vv + 1.0) * 0.5
    margin = tile_margin_mask(uu, vv, inner=0.78, outer=0.92)

    for idx in range(grid * grid):
        t = idx / float(grid * grid)
        theta = 2.0 * math.pi * t

        # Seamless looping upward advection over integer periodic vertical grid.
        v_scroll = (v01 + t * 1.0) % 1.0
        u_sway = (u01 + 0.06 * math.sin(theta)) % 1.0

        wx = fbm2d(u_sway, v_scroll, 3, 4, octaves=3, gain=0.5, seed=9101) - 0.5
        wy = fbm2d(u_sway, v_scroll, 3, 4, octaves=3, gain=0.5, seed=9157) - 0.5
        wu = (u_sway + wx * 0.24) % 1.0
        wv = (v_scroll + wy * 0.20) % 1.0

        turb = fbm2d(wu, wv, 4, 5, octaves=4, gain=0.52, seed=9203, billow=False)
        curls = fbm2d(wu, wv, 6, 7, octaves=3, gain=0.52, seed=9291, billow=True)

        # Rounded flame envelope rising into licking turbulent tips.
        h = np.clip((0.70 - vv) / 1.52, 0.0, 1.15)
        sway = (
            0.13 * math.sin(theta) * (h ** 1.1)
            + 0.09 * np.sin(h * 6.0 + theta) * h
            + wx * (0.18 + 0.34 * h)
        )
        u_f = uu - sway
        v_f = vv + wy * (0.08 + 0.16 * h)

        # Smooth rounded teardrop profile (wider at lower hearth, tapering to tips).
        half_w = 0.52 * ((1.0 - np.clip(h * 0.85, 0.0, 0.96)) ** 0.55) + 0.04
        dy = (v_f - 0.24) * 0.72
        dx = u_f / np.maximum(half_w, 0.04)
        base_dist = np.sqrt(dx * dx + dy * dy)

        # Rich internal multi-toned heat gradient (deep red/orange pockets + bright core ribbons).
        envelope = 1.0 - smoothstep(0.16, 0.96, base_dist)
        core_glow = np.exp(-3.4 * (dx * dx * 0.8 + ((v_f - 0.36) * 1.55) ** 2))
        ribbon = smoothstep(0.24, 0.78, 0.45 * turb + 0.55 * curls)
        heat = np.clip((envelope * (0.28 + 0.88 * ribbon) + core_glow * 0.46) * margin, 0.0, 1.0)

        alpha = smoothstep(0.09, 0.34, heat) * margin
        # Keep rich tonal range [0..1] instead of clipping interior to flat yellow.
        temp = np.clip(smoothstep(0.10, 0.98, heat) * 0.94, 0.0, 1.0)

        r_col = smoothstep(0.02, 0.40, temp)
        g_col = (smoothstep(0.28, 0.92, temp) ** 1.35) * 0.92
        b_col = (smoothstep(0.68, 0.99, temp) ** 1.50) * 0.76

        r_out = r_col * alpha
        g_out = np.minimum(g_col * alpha, r_out)
        b_out = np.minimum(b_col * alpha, g_out)

        row, col = divmod(idx, grid)
        y0, y1 = row * tile, (row + 1) * tile
        x0, x1 = col * tile, (col + 1) * tile

        atlas[y0:y1, x0:x1, 0] = np.clip(np.round(r_out * 255.0), 0.0, 255.0).astype(np.uint8)
        atlas[y0:y1, x0:x1, 1] = np.clip(np.round(g_out * 255.0), 0.0, 255.0).astype(np.uint8)
        atlas[y0:y1, x0:x1, 2] = np.clip(np.round(b_out * 255.0), 0.0, 255.0).astype(np.uint8)
        atlas[y0:y1, x0:x1, 3] = np.clip(np.round(alpha * 255.0), 0.0, 255.0).astype(np.uint8)

    out_path = VFX_DIR / "fire_flipbook_8x8.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, mode="RGBA").save(out_path)


def _blackbody_additive_rgb(intensity: np.ndarray) -> np.ndarray:
    """Map HDR-like flash intensity [0, 1+] to warm blackbody RGB on black background."""
    t = np.clip(intensity, 0.0, 1.0)
    r = smoothstep(0.0, 0.35, t)
    g = (smoothstep(0.18, 0.85, t) ** 1.15) * 0.96
    b = (smoothstep(0.55, 1.0, t) ** 1.35) * 0.85
    rgb = np.stack([r, np.minimum(g, r), np.minimum(b, g)], axis=-1)
    return np.clip(np.round(rgb * 255.0), 0.0, 255.0).astype(np.uint8)


def _radial_star_flash(
    tile: int,
    rays: list[tuple[float, float, float]],
    seed: int,
    core_radius: float,
    gas_cloud_r: float,
    ragged_amp: float,
) -> np.ndarray:
    """Build an irregular turbulent HL2 gas-burst front muzzle flash cell on pure black."""
    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    u01 = (uu + 1.0) * 0.5
    v01 = (vv + 1.0) * 0.5

    turb = fbm2d(u01, v01, 6, 6, octaves=4, gain=0.55, seed=seed) - 0.5
    turb_fine = fbm2d(u01, v01, 11, 11, octaves=3, gain=0.52, seed=seed + 19) - 0.5
    wu = uu + turb * 0.14
    wv = vv + turb * 0.14
    r = np.sqrt(wu * wu + wv * wv)
    ang = np.arctan2(wv, wu)

    ray_field = np.zeros_like(r, dtype=np.float32)
    for idx, (ray_ang, ray_len, ray_width) in enumerate(rays):
        d_ang = np.abs(np.arctan2(np.sin(ang - ray_ang), np.cos(ang - ray_ang)))
        w_eff = ray_width * (1.0 - 0.62 * np.clip(r / max(ray_len, 1e-4), 0.0, 1.0))
        ang_profile = np.exp(-0.5 * (d_ang / np.maximum(w_eff, 0.010)) ** 2)
        len_eff = ray_len + turb * ragged_amp + turb_fine * (ragged_amp * 0.45)
        rad_profile = np.clip(1.0 - r / np.maximum(len_eff, 0.10), 0.0, 1.0) ** 1.45
        spike = ang_profile * rad_profile * (0.78 + 0.44 * ((idx % 3) * 0.5 + turb_fine + 0.5))
        ray_field = np.maximum(ray_field, spike)

    # Irregular turbulent hot gas cloud around muzzle (replaces geometric ring).
    gas_fbm = fbm2d(u01, v01, 5, 5, octaves=4, gain=0.58, seed=seed + 37, billow=True)
    gas_cloud = np.exp(-0.5 * (r / gas_cloud_r) ** 2.1) * np.clip((gas_fbm - 0.18) * 1.35, 0.0, 1.0)
    core = np.exp(-0.5 * (r / core_radius) ** 2.2) * (0.95 + 0.25 * gas_fbm)

    streak_noise = fbm2d(
        (ang / (2.0 * np.pi)) % 1.0,
        np.clip(r * 0.55, 0.0, 0.99),
        22,
        4,
        octaves=3,
        gain=0.55,
        seed=seed + 71,
    )
    streaks = (
        np.clip((streak_noise - 0.52) * 2.4, 0.0, 1.0)
        * (1.0 - smoothstep(0.12, 0.88, r))
        * 0.62
    )

    margin = tile_margin_mask(uu, vv, inner=0.76, outer=0.93)
    intensity = np.clip((ray_field * 0.92 + core + gas_cloud * 0.72 + streaks) * margin, 0.0, 1.25)
    return _blackbody_additive_rgb(intensity)


def _side_muzzle_jet(
    tile: int,
    seed: int,
    half_angle_rad: float,
    jet_length: float,
    baffle_amp: float,
    turbulence_amp: float,
) -> np.ndarray:
    """Build a left-to-right turbulent HL2 gas-lance or ragged wide-angle blast cone on black."""
    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    u01 = (uu + 1.0) * 0.5
    v01 = (vv + 1.0) * 0.5

    ox = -0.74
    dx = uu - ox
    dy = vv
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)

    turb = fbm2d(u01, v01, 6, 6, octaves=4, gain=0.55, seed=seed) - 0.5
    streaks = fbm2d(u01, v01, 4, 16, octaves=3, gain=0.55, seed=seed + 53) - 0.5
    billow = fbm2d(u01, v01, 8, 8, octaves=3, gain=0.55, seed=seed + 97, billow=True)

    fwd = np.clip(dx / jet_length, 0.0, 1.5)
    cone_ang = np.abs(ang)
    ang_limit = half_angle_rad * (0.40 + 0.74 * smoothstep(0.0, 0.45, fwd)) + turb * turbulence_amp
    cone_mask = 1.0 - smoothstep(ang_limit * 0.24, ang_limit, cone_ang)

    len_env = (1.0 - smoothstep(0.24, 1.0, fwd + turb * turbulence_amp * 1.15)) * smoothstep(-0.04, 0.04, dx)
    axial_core = np.exp(-0.5 * (dy / (0.036 + 0.092 * fwd)) ** 2) * (1.0 - smoothstep(0.16, 0.90, fwd))

    baffle = (
        np.exp(-0.5 * ((dx - 0.06) / 0.065) ** 2)
        * np.exp(-0.5 * (dy / (0.22 + 0.16 * baffle_amp)) ** 2)
        * np.clip(0.45 + 0.85 * billow + 0.4 * turb, 0.0, 1.3)
        * baffle_amp
    )
    port_core = np.exp(-0.5 * (r / 0.14) ** 2) * (0.85 + 0.35 * billow)

    jet_body = cone_mask * len_env * np.clip(0.55 + 0.65 * streaks + 0.35 * billow, 0.0, 1.4)
    margin = tile_margin_mask(uu, vv, inner=0.76, outer=0.93)
    intensity = np.clip((jet_body * 0.94 + axial_core * 0.58 + baffle + port_core) * margin, 0.0, 1.25)
    return _blackbody_additive_rgb(intensity)


def generate_muzzle_flash_atlas() -> None:
    """Generate 1024x1024 2x2 irregular turbulent HL2 muzzle flash atlas on pure black."""
    tile = 512
    atlas = np.zeros((tile * 2, tile * 2, 3), dtype=np.uint8)

    # (0,0) Revolver irregular 6-spike turbulent incandescent gas star.
    revolver_rays = [
        (-0.18, 0.88, 0.075),
        (0.94, 0.72, 0.088),
        (2.15, 0.84, 0.070),
        (2.86, 0.62, 0.082),
        (-2.45, 0.79, 0.090),
        (-1.26, 0.90, 0.072),
    ]
    atlas[0:tile, 0:tile] = _radial_star_flash(
        tile, revolver_rays, seed=10101, core_radius=0.14, gas_cloud_r=0.28, ragged_amp=0.18
    )

    # (1,0) Revolver turbulent forward gas lance side-jet.
    atlas[0:tile, tile : tile * 2] = _side_muzzle_jet(
        tile, seed=10202, half_angle_rad=0.22, jet_length=1.54, baffle_amp=0.68, turbulence_amp=0.16
    )

    # (0,1) Shotgun chaotic multi-lobe turbulent orange-white blast star.
    shotgun_rays = [
        (0.08, 0.92, 0.13),
        (0.76, 0.78, 0.16),
        (1.52, 0.89, 0.12),
        (2.24, 0.72, 0.15),
        (3.04, 0.90, 0.14),
        (-2.48, 0.82, 0.17),
        (-1.64, 0.88, 0.13),
        (-0.82, 0.74, 0.15),
        (-0.34, 0.64, 0.12),
    ]
    atlas[tile : tile * 2, 0:tile] = _radial_star_flash(
        tile, shotgun_rays, seed=10303, core_radius=0.19, gas_cloud_r=0.40, ragged_amp=0.30
    )

    # (1,1) Shotgun broad turbulent wide-angle muzzle blast cone.
    atlas[tile : tile * 2, tile : tile * 2] = _side_muzzle_jet(
        tile, seed=10404, half_angle_rad=0.66, jet_length=1.56, baffle_amp=0.92, turbulence_amp=0.32
    )

    out_path = VFX_DIR / "muzzle" / "muzzle_flash_atlas.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, mode="RGB").save(out_path)


def _polygon_sdf(uu: np.ndarray, vv: np.ndarray, verts: np.ndarray) -> np.ndarray:
    """Vectorized signed distance to a polygon (N, 2) in [-1, 1]."""
    n = verts.shape[0]
    min_d2 = np.full_like(uu, 1e9, dtype=np.float32)
    inside = np.zeros_like(uu, dtype=bool)
    for i in range(n):
        j = (i + 1) % n
        ax, ay = verts[i]
        bx, by = verts[j]
        ex, ey = bx - ax, by - ay
        wx, wy = uu - ax, vv - ay
        denom = ex * ex + ey * ey + 1e-8
        proj = np.clip((wx * ex + wy * ey) / denom, 0.0, 1.0)
        px = wx - ex * proj
        py = wy - ey * proj
        min_d2 = np.minimum(min_d2, px * px + py * py)

        cond = (ay > vv) != (by > vv)
        x_int = ax + (vv - ay) * ex / (ey if abs(ey) > 1e-8 else 1e-8)
        inside ^= cond & (uu < x_int)

    dist = np.sqrt(min_d2)
    return np.where(inside, -dist, dist)


def generate_impact_debris_2x2() -> None:
    """Generate 512x512 2x2 RGBA impact debris sprites."""
    tile = 256
    atlas = np.zeros((tile * 2, tile * 2, 4), dtype=np.uint8)

    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    u01 = (uu + 1.0) * 0.5
    v01 = (vv + 1.0) * 0.5
    margin = tile_margin_mask(uu, vv, inner=0.78, outer=0.92)

    # (0,0) Jagged grey concrete chunk: sharp chiseled fracture silhouette + facet lighting.
    concrete_verts = np.array(
        [
            [-0.64, -0.14],
            [-0.36, -0.62],
            [0.06, -0.44],
            [0.44, -0.58],
            [0.66, -0.06],
            [0.40, 0.24],
            [0.54, 0.52],
            [0.02, 0.68],
            [-0.48, 0.42],
            [-0.38, 0.08],
        ],
        dtype=np.float32,
    )
    c_sdf = _polygon_sdf(uu, vv, concrete_verts)
    c_chip = (fbm2d(u01, v01, 7, 7, octaves=3, gain=0.5, seed=11001) - 0.5) * 0.055
    c_alpha = (1.0 - smoothstep(-0.012, 0.014, c_sdf + c_chip)) * margin
    c_tex = fbm2d(u01, v01, 10, 10, octaves=4, gain=0.55, seed=11023)
    # Sharp fracture plane shading split along diagonal ridge.
    ridge = smoothstep(-0.08, 0.08, uu * 0.65 + vv * 0.75 - 0.05)
    facet_shade = np.clip(0.84 - 0.36 * ridge + 0.20 * (c_tex - 0.5), 0.34, 0.96)
    c_cell = np.zeros((tile, tile, 4), dtype=np.uint8)
    c_nz = c_alpha > 0.002
    c_cell[..., 0] = np.where(c_nz, np.clip(np.round(facet_shade * 194.0), 0.0, 255.0).astype(np.uint8), 0)
    c_cell[..., 1] = np.where(c_nz, np.clip(np.round(facet_shade * 192.0), 0.0, 255.0).astype(np.uint8), 0)
    c_cell[..., 2] = np.where(c_nz, np.clip(np.round(facet_shade * 186.0), 0.0, 255.0).astype(np.uint8), 0)
    c_cell[..., 3] = np.clip(np.round(c_alpha * 255.0), 0.0, 255.0).astype(np.uint8)
    atlas[0:tile, 0:tile] = c_cell

    # (1,0) Elongated warm tan wood splinter: sharp needle tip + torn fiber butt + grain.
    ang = -0.18
    ca, sa = math.cos(ang), math.sin(ang)
    ur = uu * ca - vv * sa
    vr = uu * sa + vv * ca
    wood_verts = np.array(
        [
            [-0.80, -0.05],
            [-0.58, -0.13],
            [-0.40, -0.08],
            [-0.10, -0.12],
            [0.80, -0.01],
            [0.18, 0.08],
            [-0.28, 0.13],
            [-0.52, 0.07],
            [-0.74, 0.11],
        ],
        dtype=np.float32,
    )
    w_sdf = _polygon_sdf(ur, vr, wood_verts)
    w_jagged = (fbm2d((ur + 1.0) * 0.5, (vr + 1.0) * 0.5, 4, 12, octaves=3, gain=0.5, seed=11101) - 0.5) * 0.025
    w_alpha = (1.0 - smoothstep(-0.010, 0.014, w_sdf + w_jagged)) * margin
    grain = np.sin(vr * 48.0 + fbm2d((ur + 1.0) * 0.5, (vr + 1.0) * 0.5, 3, 14, octaves=2, gain=0.5, seed=11131) * 4.5)
    w_lit = np.clip(0.72 - 0.70 * vr + 0.14 * grain, 0.42, 1.0)
    w_cell = np.zeros((tile, tile, 4), dtype=np.uint8)
    w_nz = w_alpha > 0.002
    w_cell[..., 0] = np.where(w_nz, np.clip(np.round(w_lit * 228.0), 0.0, 255.0).astype(np.uint8), 0)
    w_cell[..., 1] = np.where(w_nz, np.clip(np.round(w_lit * 176.0), 0.0, 255.0).astype(np.uint8), 0)
    w_cell[..., 2] = np.where(w_nz, np.clip(np.round(w_lit * 110.0), 0.0, 255.0).astype(np.uint8), 0)
    w_cell[..., 3] = np.clip(np.round(w_alpha * 255.0), 0.0, 255.0).astype(np.uint8)
    atlas[0:tile, tile : tile * 2] = w_cell

    # (0,1) Bright tapered spark streak: crisp hot lance with glowing tail.
    sx = np.clip((uu + 0.78) / 1.44, 0.0, 1.0)
    half_h = 0.014 + 0.095 * (sx ** 0.75) * np.sqrt(np.maximum(0.0, 1.0 - np.clip((uu - 0.18) / 0.52, 0.0, 1.0) ** 2))
    spark_core_dist = np.abs(vv) / np.maximum(half_h, 0.008)
    spark_env = smoothstep(-0.78, -0.15, uu) * (1.0 - smoothstep(0.45, 0.74, uu))
    spark_heat = np.exp(-0.95 * (spark_core_dist ** 1.7)) * spark_env
    s_alpha = np.clip(smoothstep(0.04, 0.35, spark_heat) * margin, 0.0, 1.0)
    s_rgb = _blackbody_additive_rgb(np.clip(spark_heat * 1.25, 0.0, 1.0))
    s_cell = np.zeros((tile, tile, 4), dtype=np.uint8)
    s_cell[..., :3] = s_rgb
    s_cell[..., 3] = np.clip(np.round(s_alpha * 255.0), 0.0, 255.0).astype(np.uint8)
    atlas[tile : tile * 2, 0:tile] = s_cell

    # (1,1) Irregular dark earth clod: lumpy organic aggregate + angular soil protrusions.
    clod_fbm = fbm2d(u01, v01, 5, 5, octaves=4, gain=0.55, seed=11201, billow=True)
    clod_warp = fbm2d(u01, v01, 4, 4, octaves=3, gain=0.5, seed=11243) - 0.5
    uw = uu + clod_warp * 0.24
    vw = vv + clod_warp * 0.22
    e_main = np.sqrt(((uw - 0.04) / 0.52) ** 2 + ((vw + 0.02) / 0.42) ** 2)
    e_lobe1 = np.sqrt(((uw + 0.28) / 0.32) ** 2 + ((vw - 0.22) / 0.28) ** 2)
    e_lobe2 = np.sqrt(((uw - 0.26) / 0.24) ** 2 + ((vw + 0.24) / 0.22) ** 2)
    e_dist = np.minimum(e_main, np.minimum(e_lobe1, e_lobe2))
    e_field = (1.0 - smoothstep(0.42, 0.90, e_dist - (clod_fbm - 0.45) * 0.36)) * margin
    e_alpha = smoothstep(0.08, 0.30, e_field)
    e_shade = np.clip(0.46 - 0.24 * uu - 0.28 * vv + 0.46 * clod_fbm, 0.16, 0.96)
    e_cell = np.zeros((tile, tile, 4), dtype=np.uint8)
    e_nz = e_alpha > 0.002
    e_cell[..., 0] = np.where(e_nz, np.clip(np.round(e_shade * 96.0), 0.0, 255.0).astype(np.uint8), 0)
    e_cell[..., 1] = np.where(e_nz, np.clip(np.round(e_shade * 70.0), 0.0, 255.0).astype(np.uint8), 0)
    e_cell[..., 2] = np.where(e_nz, np.clip(np.round(e_shade * 46.0), 0.0, 255.0).astype(np.uint8), 0)
    e_cell[..., 3] = np.clip(np.round(e_alpha * 255.0), 0.0, 255.0).astype(np.uint8)
    atlas[tile : tile * 2, tile : tile * 2] = e_cell

    out_path = VFX_DIR / "impacts" / "impact_debris_2x2.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(atlas, mode="RGBA").save(out_path)


def main() -> None:
    t0 = time.perf_counter()
    if "--muzzle-only" in sys.argv:
        generate_muzzle_flash_atlas()
        elapsed = time.perf_counter() - t0
        print(f"[generate_combat_vfx_textures] Regenerated muzzle_flash_atlas.png in {elapsed:.2f}s.")
        return
    generate_hl2_smoke_atlases()
    generate_smoke_puff_8x8()
    generate_fire_noise_tile()
    generate_fire_tongues_4x4()
    generate_fire_flipbook_8x8()
    generate_muzzle_flash_atlas()
    generate_impact_debris_2x2()
    elapsed = time.perf_counter() - t0
    print(f"[generate_combat_vfx_textures] Generated all 8 VFX textures in {elapsed:.2f}s.")


if __name__ == "__main__":
    main()
