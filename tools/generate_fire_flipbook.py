#!/usr/bin/env python3
"""
Procedural 8x8 Curl-Advected Fire Flipbook & Normal Map Generator for Godot 4.
Uses divergence-free streamfunction curl + thermal buoyancy + MacCormack advection
+ vorticity confinement + blackbody radiation color ramp.

Outputs:
  - assets/textures/fire_flipbook/T_fire_color_alpha.png (2048x2048 RGBA)
  - assets/textures/fire_flipbook/T_fire_normal.png      (2048x2048 RGB Normal Map)
  - assets/textures/fire_flipbook/T_fire_preview_black.png (2048x2048 RGB on black)
"""

from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates, maximum_filter, minimum_filter

# --- Configuration ---
GRID_SIZE: int = 8
FRAMES: int = GRID_SIZE * GRID_SIZE  # 64 frames
TILE_RES: int = 256
ATLAS_RES: int = GRID_SIZE * TILE_RES  # 2048x2048
SEED: int = 1337


def generate_bandlimited_noise(
    shape: tuple[int, int], sigma: float, rng: np.random.Generator
) -> np.ndarray:
    """Generates smooth, zero-mean, unit-std spatial noise via Gaussian filtering."""
    raw: np.ndarray = rng.standard_normal(shape).astype(np.float32)
    filtered: np.ndarray = gaussian_filter(raw, sigma=sigma, mode="wrap")
    std: float = float(np.std(filtered))
    return filtered / (std + 1e-6)


def compute_curl_velocity(psi: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Computes divergence-free 2D velocity (vy, vx) from scalar streamfunction psi."""
    dpsi_dy, dpsi_dx = np.gradient(psi)
    vy: np.ndarray = dpsi_dx
    vx: np.ndarray = -dpsi_dy
    return vy, vx


def advect_maccormack(
    field: np.ndarray,
    vy: np.ndarray,
    vx: np.ndarray,
    coords_y: np.ndarray,
    coords_x: np.ndarray,
    dt: float = 1.0,
) -> np.ndarray:
    """
    2nd-order MacCormack semi-Lagrangian advection with local extrema clamping.
    Prevents numerical dissipation so thin flame tongues and curling hooks stay razor-sharp.
    """
    h, w = field.shape
    back_y: np.ndarray = np.clip(coords_y - vy * dt, 0.0, h - 1.0)
    back_x: np.ndarray = np.clip(coords_x - vx * dt, 0.0, w - 1.0)

    # Forward predictor
    phi_hat: np.ndarray = map_coordinates(
        field, [back_y, back_x], order=1, mode="constant", cval=0.0
    )

    # Reverse trace for error estimation
    fwd_y: np.ndarray = np.clip(coords_y + vy * dt, 0.0, h - 1.0)
    fwd_x: np.ndarray = np.clip(coords_x + vx * dt, 0.0, w - 1.0)
    phi_tilde: np.ndarray = map_coordinates(
        phi_hat, [fwd_y, fwd_x], order=1, mode="constant", cval=0.0
    )

    # Error-corrected field
    corrected: np.ndarray = phi_hat + 0.5 * (field - phi_tilde)

    # Clamp to 3x3 neighborhood extrema to eliminate MacCormack overshoot/ringing
    local_min: np.ndarray = minimum_filter(field, size=3, mode="constant", cval=0.0)
    local_max: np.ndarray = maximum_filter(field, size=3, mode="constant", cval=0.0)
    return np.clip(corrected, local_min, local_max)


def apply_vorticity_confinement(
    vy: np.ndarray, vx: np.ndarray, heat: np.ndarray, strength: float
) -> tuple[np.ndarray, np.ndarray]:
    """Injects rotational curl along sharp thermal gradients to create licking flame tendrils."""
    dvx_dy, dvx_dx = np.gradient(vx)
    dvy_dy, dvy_dx = np.gradient(vy)
    omega: np.ndarray = dvx_dy - dvy_dx

    abs_omega: np.ndarray = np.abs(omega) + gaussian_filter(heat, sigma=2.0) * 1.5
    d_om_y, d_om_x = np.gradient(abs_omega)
    norm: np.ndarray = np.hypot(d_om_y, d_om_x) + 1e-5
    ny: np.ndarray = d_om_y / norm
    nx: np.ndarray = d_om_x / norm

    # 2D cross product (N x omega)
    force_y: np.ndarray = -nx * omega * strength
    force_x: np.ndarray = ny * omega * strength
    return vy + force_y, vx + force_x


def blackbody_color_ramp(heat: np.ndarray, smoke: np.ndarray) -> np.ndarray:
    """
    Computes blackbody thermal radiation color from heat and smoke fields.
    Core: intense yellow-white emission (1.0, 0.96, 0.75)
    High: bright golden yellow (1.0, 0.72, 0.08)
    Mid: vibrant flame orange (1.0, 0.32, 0.02)
    Low: deep crimson red (0.75, 0.08, 0.01)
    Soot: dark charcoal smoke (0.12, 0.11, 0.10)
    """
    h: np.ndarray = np.clip(heat, 0.0, 1.0)
    rgb: np.ndarray = np.zeros((*h.shape, 3), dtype=np.float32)

    # Smoke base color (dark cool soot)
    smoke_mask: np.ndarray = np.clip(smoke, 0.0, 1.0)
    rgb[..., 0] = 0.12 * smoke_mask
    rgb[..., 1] = 0.11 * smoke_mask
    rgb[..., 2] = 0.10 * smoke_mask

    # Low heat: crimson flame (smoothstep 0.05 -> 0.35)
    crimson_t: np.ndarray = np.clip((h - 0.05) / 0.30, 0.0, 1.0)
    crimson_t = crimson_t * crimson_t * (3.0 - 2.0 * crimson_t)
    rgb[..., 0] = rgb[..., 0] * (1.0 - crimson_t) + 0.85 * crimson_t
    rgb[..., 1] = rgb[..., 1] * (1.0 - crimson_t) + 0.12 * crimson_t
    rgb[..., 2] = rgb[..., 2] * (1.0 - crimson_t) + 0.01 * crimson_t

    # Mid heat: vibrant orange (smoothstep 0.25 -> 0.60)
    orange_t: np.ndarray = np.clip((h - 0.25) / 0.35, 0.0, 1.0)
    orange_t = orange_t * orange_t * (3.0 - 2.0 * orange_t)
    rgb[..., 0] = rgb[..., 0] * (1.0 - orange_t) + 1.00 * orange_t
    rgb[..., 1] = rgb[..., 1] * (1.0 - orange_t) + 0.45 * orange_t
    rgb[..., 2] = rgb[..., 2] * (1.0 - orange_t) + 0.03 * orange_t

    # High heat: golden yellow (smoothstep 0.50 -> 0.80)
    yellow_t: np.ndarray = np.clip((h - 0.50) / 0.30, 0.0, 1.0)
    yellow_t = yellow_t * yellow_t * (3.0 - 2.0 * yellow_t)
    rgb[..., 0] = rgb[..., 0] * (1.0 - yellow_t) + 1.00 * yellow_t
    rgb[..., 1] = rgb[..., 1] * (1.0 - yellow_t) + 0.82 * yellow_t
    rgb[..., 2] = rgb[..., 2] * (1.0 - yellow_t) + 0.18 * yellow_t

    # Core heat: white-hot combustion center (smoothstep 0.75 -> 1.0)
    white_t: np.ndarray = np.clip((h - 0.75) / 0.25, 0.0, 1.0)
    white_t = white_t * white_t * (3.0 - 2.0 * white_t)
    rgb[..., 0] = rgb[..., 0] * (1.0 - white_t) + 1.00 * white_t
    rgb[..., 1] = rgb[..., 1] * (1.0 - white_t) + 0.97 * white_t
    rgb[..., 2] = rgb[..., 2] * (1.0 - white_t) + 0.82 * white_t

    return rgb


def shade_fire_frame(
    heat: np.ndarray, smoke: np.ndarray, frame_idx: int, total_frames: int
) -> tuple[np.ndarray, np.ndarray]:
    """Computes lit RGBA tile and camera-space OpenGL normal tile."""
    t_norm: float = frame_idx / float(total_frames - 1)

    # Life fades: quick ignition (0..4), sustained burn, smooth late dissipation (44..63)
    fade_in: float = float(np.clip((frame_idx + 0.5) / 5.0, 0.0, 1.0))
    fade_out: float = float(np.clip(1.0 - max(0.0, (t_norm - 0.55) / 0.45) ** 1.6, 0.0, 1.0))

    # Density composite
    combustion_alpha: np.ndarray = np.clip(heat * 1.4 + smoke * 0.8, 0.0, 1.0)
    alpha: np.ndarray = (
        np.power(combustion_alpha, 0.85) * fade_in * fade_out
    )

    # Color from blackbody ramp
    rgb: np.ndarray = blackbody_color_ramp(heat, smoke)

    # Internal fold highlights from heat gradients
    smooth_heat: np.ndarray = gaussian_filter(heat, sigma=1.5)
    gy, gx = np.gradient(smooth_heat)
    grad_mag: np.ndarray = np.hypot(gy, gx)
    ridge: np.ndarray = np.clip(grad_mag * 4.0, 0.0, 1.0) * np.sqrt(np.clip(heat, 0.0, 1.0))

    # Add subtle flame edge ridge glow
    for c in range(3):
        rgb[..., c] = np.clip(rgb[..., c] + ridge * (0.35 if c < 2 else 0.05), 0.0, 1.0)

    # Pack RGBA
    rgba: np.ndarray = np.zeros((TILE_RES, TILE_RES, 4), dtype=np.float32)
    rgba[..., 0] = rgb[..., 0]
    rgba[..., 1] = rgb[..., 1]
    rgba[..., 2] = rgb[..., 2]
    rgba[..., 3] = np.clip(alpha, 0.0, 1.0)

    # Pack Camera-Space Normal Map (R=+X, G=+Y OpenGL up convention, B=+Z)
    combined_field: np.ndarray = heat + smoke * 0.4
    smooth_surf: np.ndarray = gaussian_filter(combined_field, sigma=1.8)
    sgy, sgx = np.gradient(smooth_surf)

    normal_scale: float = 9.0 * fade_out
    nx: np.ndarray = -sgx * normal_scale
    ny: np.ndarray = sgy * normal_scale  # gy > 0 at top edge -> positive ny (up)
    nz: np.ndarray = np.ones_like(nx)
    inv_len: np.ndarray = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-6)

    normals: np.ndarray = np.zeros((TILE_RES, TILE_RES, 3), dtype=np.float32)
    normals[..., 0] = (nx * inv_len) * 0.5 + 0.5
    normals[..., 1] = (ny * inv_len) * 0.5 + 0.5
    normals[..., 2] = (nz * inv_len) * 0.5 + 0.5

    return rgba, normals


def main() -> None:
    rng: np.random.Generator = np.random.default_rng(SEED)
    coords_y, coords_x = np.meshgrid(
        np.arange(TILE_RES, dtype=np.float32),
        np.arange(TILE_RES, dtype=np.float32),
        indexing="ij",
    )

    center_x: float = TILE_RES * 0.5
    # Flame emitter anchored near lower-middle of tile
    emitter_y_pos: float = TILE_RES * 0.72

    dy_emitter: np.ndarray = coords_y - emitter_y_pos
    dx_emitter: np.ndarray = coords_x - center_x
    radius_emitter: np.ndarray = np.hypot(dy_emitter * 1.3, dx_emitter) / (TILE_RES * 0.22)
    angle_emitter: np.ndarray = np.arctan2(dy_emitter, dx_emitter)

    # Radial border containment mask so fire never clips tile boundaries
    center: float = TILE_RES * 0.5
    dy_center: np.ndarray = coords_y - center
    dx_center: np.ndarray = coords_x - center
    radius_tile: np.ndarray = np.hypot(dy_center, dx_center) / center
    border_mask: np.ndarray = np.clip(1.0 - np.power(radius_tile / 0.88, 4.0), 0.0, 1.0)
    # Extra top margin dissipation
    top_dissipation: np.ndarray = np.clip(coords_y / 32.0, 0.0, 1.0)
    border_mask *= top_dissipation

    # Asymmetric multi-lobed flame burner shape
    burner_lobes: np.ndarray = (
        1.0
        + 0.40 * np.cos(3.0 * angle_emitter + 0.3)
        + 0.25 * np.sin(5.0 * angle_emitter - 0.7)
    )
    burner_noise: np.ndarray = (
        0.7
        + 0.3 * generate_bandlimited_noise((TILE_RES, TILE_RES), sigma=8.0, rng=rng)
    )
    flame_emitter: np.ndarray = (
        np.exp(-((radius_emitter / (0.65 * burner_lobes)) ** 2.2))
        * np.clip(burner_noise, 0.1, 1.4)
    )

    # 3 octaves of divergence-free curl streamfunctions
    psi_large: np.ndarray = generate_bandlimited_noise((TILE_RES, TILE_RES), 24.0, rng)
    psi_med: np.ndarray = generate_bandlimited_noise((TILE_RES, TILE_RES), 12.0, rng)
    psi_small: np.ndarray = generate_bandlimited_noise((TILE_RES, TILE_RES), 6.0, rng)

    vy_l, vx_l = compute_curl_velocity(psi_large)
    vy_m, vx_m = compute_curl_velocity(psi_med)
    vy_s, vx_s = compute_curl_velocity(psi_small)

    # Velocity fields and advected scalars
    heat: np.ndarray = np.zeros((TILE_RES, TILE_RES), dtype=np.float32)
    smoke: np.ndarray = np.zeros((TILE_RES, TILE_RES), dtype=np.float32)
    vy: np.ndarray = np.zeros((TILE_RES, TILE_RES), dtype=np.float32)
    vx: np.ndarray = np.zeros((TILE_RES, TILE_RES), dtype=np.float32)

    # Atlases
    atlas_rgba: np.ndarray = np.zeros((ATLAS_RES, ATLAS_RES, 4), dtype=np.uint8)
    atlas_norm: np.ndarray = np.zeros((ATLAS_RES, ATLAS_RES, 3), dtype=np.uint8)
    atlas_preview: np.ndarray = np.zeros((ATLAS_RES, ATLAS_RES, 3), dtype=np.uint8)

    for frame in range(FRAMES):
        # 1. Fuel & heat injection at base
        # Sustained burn through frame 28, ramping down to frame 42
        if frame < 28:
            inject_weight: float = float(np.sin(min(1.0, (frame + 1) / 10.0) * np.pi * 0.5))
            # Modulate emitter with slight temporal flutter
            flutter: float = 1.0 + 0.18 * float(np.sin(frame * 0.95))
            heat = np.clip(heat + flame_emitter * (inject_weight * flutter * 0.65), 0.0, 1.4)
        elif frame < 42:
            # Cutoff phase: detach from burner base
            cutoff_t: float = 1.0 - (frame - 28) / 14.0
            heat = np.clip(heat + flame_emitter * (cutoff_t * 0.25), 0.0, 1.4)

        # 2. Thermal buoyancy (upward velocity is negative Y in screen coordinates)
        buoyancy_vy: np.ndarray = -np.clip(heat * 3.8 + 0.4, 0.0, 5.0)

        # Inward pinch at bottom to simulate chimney draft
        inward_vx: np.ndarray = -dx_emitter * 0.015 * np.clip(heat, 0.0, 1.0)

        # Dynamic curl turbulence (turbulent rolls amplify as flame rises)
        curl_weight: float = float(np.clip((frame + 3) / 10.0, 0.4, 1.2))
        target_vy: np.ndarray = (
            buoyancy_vy
            + (vy_l * 2.2 + vy_m * 1.5 + vy_s * 0.75) * curl_weight
        )
        target_vx: np.ndarray = (
            inward_vx
            + (vx_l * 2.2 + vx_m * 1.5 + vx_s * 0.75) * curl_weight
        )

        # Blend momentum & apply vorticity confinement for licking tongues
        vy = 0.72 * vy + 0.28 * target_vy
        vx = 0.72 * vx + 0.28 * target_vx
        vy, vx = apply_vorticity_confinement(vy, vx, heat, strength=1.1)

        vy *= border_mask
        vx *= border_mask

        # 3. Advection (2 substeps for CFL stability and crisp tendrils)
        for _ in range(2):
            heat = advect_maccormack(heat, vy, vx, coords_y, coords_x, dt=0.55)
            smoke = advect_maccormack(smoke, vy, vx, coords_y, coords_x, dt=0.55)
            heat *= border_mask
            smoke *= border_mask

        # Thermal cooling & conversion of cold flame into smoke soot
        cooling_rate: float = 0.032 + 0.025 * max(0.0, (frame - 30) / 34.0)
        cooling_loss: np.ndarray = heat * cooling_rate
        heat = np.clip(heat - cooling_loss, 0.0, 1.5)
        # Smoke soot generation from cooling edges
        smoke = np.clip(smoke * 0.96 + cooling_loss * 1.2, 0.0, 1.0)

        # Micro-diffusion to prevent grid aliasing
        heat = 0.95 * heat + 0.05 * gaussian_filter(heat, sigma=0.5)

        # 4. Shade frame into 8x8 atlas
        rgba_tile, norm_tile = shade_fire_frame(heat, smoke, frame, FRAMES)

        row: int = frame // GRID_SIZE
        col: int = frame % GRID_SIZE
        y0, y1 = row * TILE_RES, (row + 1) * TILE_RES
        x0, x1 = col * TILE_RES, (col + 1) * TILE_RES

        atlas_rgba[y0:y1, x0:x1] = np.clip(rgba_tile * 255.0, 0, 255).astype(np.uint8)
        atlas_norm[y0:y1, x0:x1] = np.clip(norm_tile * 255.0, 0, 255).astype(np.uint8)

        # Premultiplied black preview
        preview_rgb: np.ndarray = rgba_tile[..., :3] * rgba_tile[..., 3:4]
        atlas_preview[y0:y1, x0:x1] = np.clip(preview_rgb * 255.0, 0, 255).astype(np.uint8)

    # 5. Output file paths
    out_dir: Path = Path("assets/textures/fire_flipbook")
    out_dir.mkdir(parents=True, exist_ok=True)

    path_rgba: Path = out_dir / "T_fire_color_alpha.png"
    path_norm: Path = out_dir / "T_fire_normal.png"
    path_prev: Path = out_dir / "T_fire_preview_black.png"

    Image.fromarray(atlas_rgba, mode="RGBA").save(path_rgba)
    Image.fromarray(atlas_norm, mode="RGB").save(path_norm)
    Image.fromarray(atlas_preview, mode="RGB").save(path_prev)
    print(f"[OK] Generated 2048x2048 Fire Flipbooks:\n  {path_rgba}\n  {path_norm}\n  {path_prev}")


if __name__ == "__main__":
    main()
