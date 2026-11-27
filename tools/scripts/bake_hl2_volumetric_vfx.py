"""Vectorized 3D Beer-Lambert Volumetric Curl-Noise Ray-Integration baker for HL2 fire & smoke.

Generates photographic, zero-firefly semi-realistic HL2 combat VFX atlases:
- assets/vfx/smoke/hl2_smoke_cloud_4x4.png   (2048x2048 RGBA, lush wispy diffuse clouds)
- assets/vfx/smoke/hl2_smoke_normal_4x4.png  (2048x2048 OpenGL +Y, 24px-blurred macro-lobe normals)
- assets/vfx/smoke/smoke_puff_8x8.png        (2048x2048 RGBA, 8x8 billowing & dissolving sequence)
- assets/vfx/fire/fire_tongues_4x4.png       (2048x2048 RGBA, 4x4 silky roaring HL2 fire tongues)
- assets/vfx/fire_flipbook_8x8.png           (2048x2048 RGBA, 8x8 continuous roaring fire loop)
"""

from __future__ import annotations

import math
import time
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

REPO_ROOT: Path = Path(__file__).resolve().parents[2]
VFX_DIR: Path = REPO_ROOT / "assets" / "vfx"


def smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    """Vectorized cubic Hermite smoothstep in [0, 1]."""
    t = np.clip((x - edge0) / max(edge1 - edge0, 1e-6), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def tile_feather(size: int, inner: float, outer: float) -> np.ndarray:
    """Smooth radial + border feather fading cleanly to 0 before tile edges."""
    coords = np.linspace(-1.0, 1.0, size, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    r_rad = np.sqrt(uu * uu + vv * vv)
    r_box = np.maximum(np.abs(uu), np.abs(vv))
    r = np.maximum(r_rad * 0.96, r_box)
    return 1.0 - smoothstep(inner, outer, r)


def _kolmogorov_3d(shape: tuple[int, int, int], k_min: float, power: float, seed: int) -> np.ndarray:
    """Generate a seamlessly tileable 3D turbulent field normalized to [0, 1] via 3D FFT."""
    rng = np.random.Generator(np.random.PCG64(seed))
    nz, ny, nx = shape
    white = rng.standard_normal(shape, dtype=np.float32)
    spec = np.fft.rfftn(white)

    kz = np.fft.fftfreq(nz)[:, None, None] * nz
    ky = np.fft.fftfreq(ny)[None, :, None] * ny
    kx = np.fft.rfftfreq(nx)[None, None, :] * nx
    k_mag = np.sqrt(kx * kx + ky * ky + kz * kz)

    filt = np.where(k_mag >= k_min, (k_mag + 0.5) ** (-power), 0.0).astype(np.float32)
    filt[0, 0, 0] = 0.0
    field = np.fft.irfftn(spec * filt, s=shape, axes=(0, 1, 2)).astype(np.float32)
    std = float(np.std(field)) + 1e-6
    return np.clip(0.5 + 0.24 * (field / std), 0.0, 1.0)


def _build_curl_volume(shape: tuple[int, int, int], seed: int) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Build a 3D divergence-free curl displacement field from smooth 3D scalar potentials."""
    px = _kolmogorov_3d(shape, k_min=1.2, power=2.45, seed=seed)
    py = _kolmogorov_3d(shape, k_min=1.2, power=2.45, seed=seed + 101)
    pz = _kolmogorov_3d(shape, k_min=1.2, power=2.45, seed=seed + 202)

    dpz_dy = np.roll(pz, -1, axis=1) - np.roll(pz, 1, axis=1)
    dpy_dz = np.roll(py, -1, axis=0) - np.roll(py, 1, axis=0)
    dpx_dz = np.roll(px, -1, axis=0) - np.roll(px, 1, axis=0)
    dpz_dx = np.roll(pz, -1, axis=2) - np.roll(pz, 1, axis=2)
    dpy_dx = np.roll(py, -1, axis=2) - np.roll(py, 1, axis=2)
    dpx_dy = np.roll(px, -1, axis=1) - np.roll(px, 1, axis=1)

    cx = (dpz_dy - dpy_dz) * 4.5
    cy = (dpx_dz - dpz_dx) * 4.5
    cz = (dpy_dx - dpx_dy) * 4.5
    return cx.astype(np.float32), cy.astype(np.float32), cz.astype(np.float32)


def _sample_3d(vol: np.ndarray, uz: np.ndarray, uy: np.ndarray, ux: np.ndarray) -> np.ndarray:
    """Fast vectorized periodic trilinear lookup on 3D volume (Z, Y, X) for coords in [0, 1)."""
    nz, ny, nx = vol.shape
    fz = (uz % 1.0) * nz
    fy = (uy % 1.0) * ny
    fx = (ux % 1.0) * nx

    z0 = np.floor(fz).astype(np.int32) % nz
    y0 = np.floor(fy).astype(np.int32) % ny
    x0 = np.floor(fx).astype(np.int32) % nx
    z1 = (z0 + 1) % nz
    y1 = (y0 + 1) % ny
    x1 = (x0 + 1) % nx

    tz = fz - np.floor(fz)
    ty = fy - np.floor(fy)
    tx = fx - np.floor(fx)

    c000 = vol[z0, y0, x0]
    c100 = vol[z0, y0, x1]
    c010 = vol[z0, y1, x0]
    c110 = vol[z0, y1, x1]
    c001 = vol[z1, y0, x0]
    c101 = vol[z1, y0, x1]
    c011 = vol[z1, y1, x0]
    c111 = vol[z1, y1, x1]

    c00 = c000 + (c100 - c000) * tx
    c10 = c010 + (c110 - c010) * tx
    c01 = c001 + (c101 - c001) * tx
    c11 = c011 + (c111 - c011) * tx
    c0 = c00 + (c10 - c00) * ty
    c1 = c01 + (c11 - c01) * ty
    return c0 + (c1 - c0) * tz


def _raymarch_smoke_tile(
    tile: int,
    n_slices: int,
    vol_turb: np.ndarray,
    vol_fine: np.ndarray,
    curl: tuple[np.ndarray, np.ndarray, np.ndarray],
    seed: int,
    expand: float = 1.0,
    dissolve: float = 0.0,
    time_offset: float = 0.0,
) -> tuple[np.ndarray, np.ndarray]:
    """Ray-integrate a lush 3D curl-warped wispy HL2 smoke cloud via Beer-Lambert scattering."""
    rng = np.random.Generator(np.random.PCG64(seed))
    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    feather = tile_feather(tile, inner=0.58, outer=0.95)

    lobes: list[tuple[float, float, float, float, float]] = []
    for i in range(6):
        ang = i * (2.0 * math.pi / 6.0) + float(rng.uniform(-0.35, 0.35))
        dist = float(rng.uniform(0.08, 0.30)) * expand if i > 0 else 0.04
        rad = float(rng.uniform(0.34, 0.46)) * (0.90 + 0.18 * expand)
        lobes.append(
            (
                math.cos(ang) * dist,
                math.sin(ang) * dist - 0.04 * time_offset,
                float(rng.uniform(-0.22, 0.22)),
                rad,
                float(rng.uniform(0.78, 1.0)),
            )
        )

    cx_v, cy_v, cz_v = curl
    shift_x = float(rng.uniform(0.0, 1.0))
    shift_y = float(rng.uniform(0.0, 1.0)) + time_offset * 0.25
    shift_z = float(rng.uniform(0.0, 1.0))

    z_vals = np.linspace(0.72, -0.72, n_slices, dtype=np.float32)
    dz = 1.44 / float(n_slices)

    transmittance = np.ones((tile, tile), dtype=np.float32)
    radiance = np.zeros((tile, tile), dtype=np.float32)
    optical_depth = np.zeros((tile, tile), dtype=np.float32)

    for z_val in z_vals:
        zz = np.full_like(uu, z_val)
        ux = uu * 0.36 + shift_x
        uy = vv * 0.36 + shift_y
        uz = zz * 0.36 + shift_z

        dx = _sample_3d(cx_v, uz, uy, ux)
        dy = _sample_3d(cy_v, uz, uy, ux)
        dz_w = _sample_3d(cz_v, uz, uy, ux)

        xw = uu + dx * 0.24
        yw = vv + dy * 0.24
        zw = zz + dz_w * 0.24

        envelope = np.zeros_like(uu)
        for lx, ly, lz, lrad, lamp in lobes:
            d2 = ((xw - lx) ** 2 + (yw - ly) ** 2 + (zw - lz) ** 2) / max(lrad * lrad, 1e-4)
            g = np.exp(-1.55 * d2) * lamp
            envelope = np.maximum(envelope, g)

        turb = _sample_3d(
            vol_turb, uz * 1.4 + dz_w * 0.08, uy * 1.4 + dy * 0.08, ux * 1.4 + dx * 0.08
        )
        fine = _sample_3d(vol_fine, uz * 2.2, uy * 2.2 + time_offset * 0.18, ux * 2.2)
        wisp = turb * 0.72 + fine * 0.28

        rho = np.maximum(0.0, envelope * (0.45 + 1.15 * wisp) - (0.06 + 0.22 * dissolve))
        rho = (rho ** 1.08) * (1.0 - 0.62 * dissolve)

        l_sample = _sample_3d(vol_turb, (uz + 0.09), (uy - 0.14), (ux + 0.05))
        shade = np.clip(0.56 + 0.32 * (1.0 - vv) * 0.5 + 0.28 * (turb - l_sample), 0.52, 1.0)

        step_absorb = np.exp(-rho * dz * 3.8)
        step_alpha = 1.0 - step_absorb
        radiance += transmittance * step_alpha * shade
        transmittance *= step_absorb
        optical_depth += rho * dz

    alpha = np.clip((1.0 - transmittance) * feather, 0.0, 1.0)
    scattered = radiance / np.maximum(1.0 - transmittance, 1e-4)
    rgb_val = np.where(alpha > 0.002, np.clip(0.58 + 0.42 * scattered, 0.55, 1.0), 0.0)

    rgba = np.empty((tile, tile, 4), dtype=np.uint8)
    u8_rgb = np.clip(np.round(rgb_val * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 0] = u8_rgb
    rgba[..., 1] = u8_rgb
    rgba[..., 2] = u8_rgb
    rgba[..., 3] = np.clip(np.round(alpha * 255.0), 0.0, 255.0).astype(np.uint8)
    return rgba, optical_depth * feather


def _blurred_macro_normal(optical_depth: np.ndarray, alpha_u8: np.ndarray) -> np.ndarray:
    """Compute heavily blurred macro-lobe OpenGL +Y normals (zero plastic crinkle)."""
    tile = optical_depth.shape[0]
    norm_d = optical_depth / max(float(np.max(optical_depth)), 1e-4)
    img_d = Image.fromarray(np.clip(np.round(norm_d * 255.0), 0.0, 255.0).astype(np.uint8), mode="L")
    blurred = np.asarray(img_d.filter(ImageFilter.GaussianBlur(radius=24)), dtype=np.float32) / 255.0

    dy, dx = np.gradient(blurred)
    nx = -dx * 10.0
    ny = dy * 10.0
    nz = np.ones_like(nx, dtype=np.float32)

    fade = smoothstep(0.02, 0.25, alpha_u8.astype(np.float32) / 255.0)
    nx *= fade * 0.42
    ny *= fade * 0.42

    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    nx *= inv_len
    ny *= inv_len
    nz *= inv_len

    nx *= 0.45
    ny *= 0.45
    nz = nz * 0.45 + 0.55
    inv_len2 = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    nx *= inv_len2
    ny *= inv_len2
    nz *= inv_len2

    rgba = np.empty((tile, tile, 4), dtype=np.uint8)
    rgba[..., 0] = np.clip(np.round((nx * 0.5 + 0.5) * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 1] = np.clip(np.round((ny * 0.5 + 0.5) * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 2] = np.clip(np.round((nz * 0.5 + 0.5) * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 3] = 255
    return rgba


def _blackbody_fire_rgb(temp: np.ndarray) -> np.ndarray:
    """Map continuous fire temperature [0, 1+] to silky photographic HL2 blackbody RGB."""
    t = np.clip(temp, 0.0, 1.15)
    c_red = np.stack(
        [
            smoothstep(0.0, 0.24, t) * 0.65,
            smoothstep(0.04, 0.34, t) * 0.07,
            smoothstep(0.10, 0.40, t) * 0.005,
        ],
        axis=-1,
    )
    c_orange = np.stack([np.ones_like(t), np.full_like(t, 0.32), np.full_like(t, 0.02)], axis=-1)
    c_gold = np.stack([np.ones_like(t), np.full_like(t, 0.74), np.full_like(t, 0.16)], axis=-1)
    c_white = np.stack([np.ones_like(t), np.full_like(t, 0.96), np.full_like(t, 0.84)], axis=-1)

    w_orange = smoothstep(0.14, 0.42, t)[..., None]
    w_gold = smoothstep(0.42, 0.74, t)[..., None]
    w_white = smoothstep(0.74, 1.02, t)[..., None]

    col = c_red * (1.0 - w_orange) + c_orange * w_orange
    col = col * (1.0 - w_gold) + c_gold * w_gold
    col = col * (1.0 - w_white) + c_white * w_white
    intensity = smoothstep(0.01, 0.30, t)[..., None] * (0.60 + 0.60 * t[..., None])
    return col * intensity


def _raymarch_fire_tile(
    tile: int,
    n_slices: int,
    vol_turb: np.ndarray,
    vol_fine: np.ndarray,
    curl: tuple[np.ndarray, np.ndarray, np.ndarray],
    seed: int,
    phase: float = 0.0,
) -> np.ndarray:
    """Ray-integrate continuous silky 3D turbulent flame ribbons (zero grainy splatter)."""
    rng = np.random.Generator(np.random.PCG64(seed))
    coords = np.linspace(-1.0, 1.0, tile, dtype=np.float32)
    vv, uu = np.meshgrid(coords, coords, indexing="ij")
    feather = tile_feather(tile, inner=0.72, outer=0.96)

    h = np.clip((0.68 - vv) / 1.50, 0.0, 1.25)

    # 3 strong asymmetric rising flame plumes (broad hearth merging into curling vertical tongues).
    jets: list[tuple[float, float, float, float, float]] = []
    for j in range(3):
        jx = float(rng.uniform(-0.18, 0.18)) if j > 0 else 0.0
        jz = float(rng.uniform(-0.12, 0.12))
        jh = float(rng.uniform(0.86, 1.10))
        jr = float(rng.uniform(0.28, 0.38))
        lean = float(rng.uniform(-0.14, 0.14))
        jets.append((jx, jz, jh, jr, lean))

    cx_v, cy_v, cz_v = curl
    shift_x = float(rng.uniform(0.0, 1.0))
    shift_y = float(rng.uniform(0.0, 1.0)) + phase
    shift_z = float(rng.uniform(0.0, 1.0))

    z_vals = np.linspace(0.50, -0.50, n_slices, dtype=np.float32)
    dz = 1.00 / float(n_slices)

    accum_rgb = np.zeros((tile, tile, 3), dtype=np.float32)
    trans = np.ones((tile, tile), dtype=np.float32)

    for z_val in z_vals:
        zz = np.full_like(uu, z_val)
        # Vertically stretched buoyancy coords (Y frequency < X frequency -> smooth flame ribbons).
        ux = uu * 0.34 + shift_x
        uy = vv * 0.20 + shift_y
        uz = zz * 0.34 + shift_z

        dx = _sample_3d(cx_v, uz, uy, ux)
        dy = _sample_3d(cy_v, uz, uy, ux)
        dz_w = _sample_3d(cz_v, uz, uy, ux)

        swirl_amp = 0.08 + 0.30 * (h ** 1.10)
        xw = uu + dx * swirl_amp
        yw = vv + dy * (swirl_amp * 0.65)
        zw = zz + dz_w * swirl_amp

        hw = np.clip((0.68 - yw) / 1.50, -0.2, 1.35)
        base_env = smoothstep(-0.10, 0.15, hw)

        jet_field = np.zeros_like(uu)
        for jx, jz, jh, jr, lean in jets:
            taper_r = jr * ((1.0 - np.clip(hw / jh, 0.0, 1.0)) ** 0.55)
            x_center = jx + lean * np.clip(hw, 0.0, 1.2)
            r2 = ((xw - x_center) ** 2 + (zw - jz) ** 2) / np.maximum(taper_r * taper_r, 0.003)
            tip_fade = 1.0 - smoothstep(jh * 0.55, jh * 1.05, hw)
            g = np.exp(-1.35 * r2) * tip_fade * base_env
            jet_field = np.maximum(jet_field, g)

        turb = _sample_3d(
            vol_turb,
            uz * 1.15 + dz_w * 0.08,
            uy * 0.95 + phase * 0.6 + dy * 0.08,
            ux * 1.15 + dx * 0.08,
        )
        fine = _sample_3d(vol_fine, uz * 1.75, uy * 1.35 + phase * 1.1, ux * 1.75)

        ridge = 1.0 - np.abs(2.0 * fine - 1.0)
        flame_density = np.maximum(
            0.0, jet_field * (0.48 + 0.85 * turb + 0.25 * (ridge ** 1.4)) - 0.07
        )
        temp = flame_density * (1.10 - 0.50 * np.clip(hw, 0.0, 1.0)) * (0.78 + 0.35 * ridge)

        emit_rgb = _blackbody_fire_rgb(temp)
        step_absorb = np.exp(-flame_density * dz * 1.25)
        accum_rgb += trans[..., None] * emit_rgb * (dz * 2.4)
        trans *= step_absorb

    rgb_out = (accum_rgb * 1.28) / (1.0 + 0.28 * accum_rgb)
    rgb_out *= feather[..., None]
    lum = 0.299 * rgb_out[..., 0] + 0.587 * rgb_out[..., 1] + 0.114 * rgb_out[..., 2]
    alpha = np.clip(smoothstep(0.01, 0.32, lum) * feather, 0.0, 1.0)

    rgba = np.empty((tile, tile, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(np.round(rgb_out * 255.0), 0.0, 255.0).astype(np.uint8)
    rgba[..., 3] = np.clip(np.round(alpha * 255.0), 0.0, 255.0).astype(np.uint8)
    return rgba


def generate_smoke_atlases(
    vol_turb: np.ndarray,
    vol_fine: np.ndarray,
    curl: tuple[np.ndarray, np.ndarray, np.ndarray],
) -> None:
    """Bake 4x4 HL2 smoke cloud, 24px-blurred macro normal atlas, and 8x8 smoke puff sequence."""
    smoke_dir = VFX_DIR / "smoke"
    smoke_dir.mkdir(parents=True, exist_ok=True)

    atlas_4x4 = np.zeros((2048, 2048, 4), dtype=np.uint8)
    normal_4x4 = np.zeros((2048, 2048, 4), dtype=np.uint8)

    for idx in range(16):
        row, col = divmod(idx, 4)
        y0, y1 = row * 512, (row + 1) * 512
        x0, x1 = col * 512, (col + 1) * 512
        rgba, opt_depth = _raymarch_smoke_tile(
            512, 14, vol_turb, vol_fine, curl, seed=3000 + idx * 97, expand=1.0, dissolve=0.06
        )
        atlas_4x4[y0:y1, x0:x1] = rgba
        normal_4x4[y0:y1, x0:x1] = _blurred_macro_normal(opt_depth, rgba[..., 3])

    Image.fromarray(atlas_4x4, mode="RGBA").save(smoke_dir / "hl2_smoke_cloud_4x4.png")
    Image.fromarray(normal_4x4, mode="RGBA").save(smoke_dir / "hl2_smoke_normal_4x4.png")

    atlas_8x8 = np.zeros((2048, 2048, 4), dtype=np.uint8)
    for idx in range(64):
        t = idx / 63.0
        expand = 0.72 + 0.42 * (1.0 - (1.0 - t) ** 2.0)
        dissolve = max(0.0, (t - 0.32) / 0.68) * 0.85
        rgba, _ = _raymarch_smoke_tile(
            256, 12, vol_turb, vol_fine, curl, seed=4100, expand=expand, dissolve=dissolve, time_offset=t
        )
        row, col = divmod(idx, 8)
        atlas_8x8[row * 256 : (row + 1) * 256, col * 256 : (col + 1) * 256] = rgba

    Image.fromarray(atlas_8x8, mode="RGBA").save(smoke_dir / "smoke_puff_8x8.png")


def generate_fire_atlases(
    vol_turb: np.ndarray,
    vol_fine: np.ndarray,
    curl: tuple[np.ndarray, np.ndarray, np.ndarray],
) -> None:
    """Bake 4x4 roaring HL2 fire tongues and 8x8 continuous roaring fire flipbook."""
    fire_dir = VFX_DIR / "fire"
    fire_dir.mkdir(parents=True, exist_ok=True)

    atlas_4x4 = np.zeros((2048, 2048, 4), dtype=np.uint8)
    for idx in range(16):
        row, col = divmod(idx, 4)
        y0, y1 = row * 512, (row + 1) * 512
        x0, x1 = col * 512, (col + 1) * 512
        atlas_4x4[y0:y1, x0:x1] = _raymarch_fire_tile(
            512, 14, vol_turb, vol_fine, curl, seed=5000 + idx * 131, phase=idx * 0.14
        )
    Image.fromarray(atlas_4x4, mode="RGBA").save(fire_dir / "fire_tongues_4x4.png")

    atlas_8x8 = np.zeros((2048, 2048, 4), dtype=np.uint8)
    for idx in range(64):
        t = idx / 64.0
        row, col = divmod(idx, 8)
        atlas_8x8[row * 256 : (row + 1) * 256, col * 256 : (col + 1) * 256] = _raymarch_fire_tile(
            256, 12, vol_turb, vol_fine, curl, seed=6200, phase=t * 2.0
        )
    Image.fromarray(atlas_8x8, mode="RGBA").save(VFX_DIR / "fire_flipbook_8x8.png")


def main() -> None:
    t0 = time.perf_counter()
    vol_shape = (64, 128, 128)
    # High spectral decay powers (2.35 / 2.25) give silky fluid ribbons without grainy confetti.
    vol_turb = _kolmogorov_3d(vol_shape, k_min=1.5, power=2.35, seed=9101)
    vol_fine = _kolmogorov_3d(vol_shape, k_min=2.5, power=2.25, seed=9203)
    curl = _build_curl_volume(vol_shape, seed=9307)

    generate_smoke_atlases(vol_turb, vol_fine, curl)
    generate_fire_atlases(vol_turb, vol_fine, curl)

    elapsed = time.perf_counter() - t0
    print(f"[bake_hl2_volumetric_vfx] Baked all 5 volumetric HL2 smoke & fire atlases in {elapsed:.2f}s.")


if __name__ == "__main__":
    main()
