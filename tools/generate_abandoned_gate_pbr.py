"""Generates non-repetitive, mathematically seamless PBR texture maps for:
1. Abandoned, moldy, ribbed industrial garage gate panels (2048x2048):
   - props/garage_gate/textures/gate_albedo.png
   - props/garage_gate/textures/gate_orm.png
   - props/garage_gate/textures/gate_normal.png
2. Weathered galvanized & rusted steel frame tracks/hardware (1024x1024):
   - props/garage_gate/textures/frame_albedo.png
   - props/garage_gate/textures/frame_orm.png
   - props/garage_gate/textures/frame_normal.png
"""

import os
import numpy as np
from PIL import Image

OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "props",
    "garage_gate",
    "textures",
)


def periodic_spectral_noise(
    size: int, power: float = 1.8, seed: int = 42
) -> np.ndarray:
  """Generates 100% periodic seamless 2D fractal noise via inverse FFT."""
  rng = np.random.RandomState(seed)
  kx = np.fft.fftfreq(size)
  ky = np.fft.fftfreq(size)
  kx_grid, ky_grid = np.meshgrid(kx, ky)
  k_sq = kx_grid**2 + ky_grid**2
  k_sq[0, 0] = 1.0

  amplitude = 1.0 / (k_sq ** (power * 0.5))
  amplitude[0, 0] = 0.0

  phase = rng.uniform(0.0, 2.0 * np.pi, (size, size))
  f_complex = amplitude * (np.cos(phase) + 1j * np.sin(phase))
  f_complex[0, 0] = 0.0

  spatial = np.fft.ifft2(f_complex).real
  spatial = (spatial - spatial.min()) / (spatial.max() - spatial.min() + 1e-8)
  return spatial.astype(np.float32)


def compute_normal_and_ao(
    height: np.ndarray, strength: float
) -> tuple[np.ndarray, np.ndarray]:
  """Computes toroid-wrapped OpenGL +Y tangent normal map and cavity AO."""
  def d_dx(arr: np.ndarray) -> np.ndarray:
    return (np.roll(arr, -1, axis=1) - np.roll(arr, 1, axis=1)) * 0.5

  def d_dy(arr: np.ndarray) -> np.ndarray:
    return (np.roll(arr, -1, axis=0) - np.roll(arr, 1, axis=0)) * 0.5

  dh_dx = d_dx(height) * strength
  dh_dy = d_dy(height) * strength

  nx = -dh_dx
  ny = dh_dy
  nz = np.ones_like(nx)
  mag = np.sqrt(nx**2 + ny**2 + nz**2)
  nx /= mag
  ny /= mag
  nz /= mag

  normal_rgb = np.stack(
      [
          ((nx * 0.5 + 0.5) * 255.0).astype(np.uint8),
          ((ny * 0.5 + 0.5) * 255.0).astype(np.uint8),
          ((nz * 0.5 + 0.5) * 255.0).astype(np.uint8),
      ],
      axis=-1,
  )

  curv = np.clip(1.0 - (d_dx(nx) + d_dy(ny)) * 0.75, 0.0, 1.0)
  ao = np.clip((0.82 + 0.18 * height) * curv, 0.42, 1.0)
  return normal_rgb, ao


def generate_panel_pbr(res: int = 2048) -> None:
  print(f"Generating {res}x{res} non-repetitive Panel PBR maps...")

  macro_n = periodic_spectral_noise(res, power=1.5, seed=111)
  mid_n = periodic_spectral_noise(res, power=2.0, seed=222)
  fine_n = periodic_spectral_noise(res, power=2.6, seed=333)
  grain_n = periodic_spectral_noise(res, power=3.4, seed=444)

  # Horizontal stamped sheet-metal ribs (4 subtle grooves across panel height)
  v_coord = np.linspace(0.0, 1.0, res, endpoint=False)[:, None]
  rib_wave = np.sin(v_coord * 2.0 * np.pi * 4.0)
  rib_groove = np.clip((rib_wave - 0.75) * 4.0, 0.0, 1.0).astype(np.float32)

  # Vertical rain/moisture drip streaks (high-frequency X variation, elongated Y)
  u_streak = periodic_spectral_noise(res, power=1.7, seed=555)
  # Stretch vertically by rolling/averaging along Y
  streak_v = (
      u_streak
      + np.roll(u_streak, 16, axis=0)
      + np.roll(u_streak, 32, axis=0)
      + np.roll(u_streak, 48, axis=0)
  ) * 0.25
  drip_mask = np.clip((streak_v - 0.58) * 2.8, 0.0, 1.0)

  # Bottom & top seam moisture accumulation (subtle gradient, zero loud blotches)
  edge_damp = np.clip(
      np.exp(-v_coord * 6.0) * 0.8 + np.exp(-(1.0 - v_coord) * 8.0) * 0.5,
      0.0,
      1.0,
  ).astype(np.float32)

  # Subtle chipped paint flakes (~15% rust exposure, mostly near grooves, drips, and seams)
  rust_field = (
      macro_n * 0.35
      + mid_n * 0.35
      + fine_n * 0.30
      + edge_damp * 0.22
      + drip_mask * 0.18
      + rib_groove * 0.12
  )
  rust_thresh = 0.76
  paint_mask = 1.0 - np.clip((rust_field - rust_thresh) / 0.025, 0.0, 1.0)

  # Organic mold & mildew spores concentrated in damp seams, drip paths, and rust borders
  mold_noise = mid_n * 0.5 + fine_n * 0.3 + grain_n * 0.2
  mold_affinity = np.clip(edge_damp * 0.85 + drip_mask * 0.55 + (1.0 - paint_mask) * 0.35, 0.0, 1.0)
  mold_mask = np.clip((mold_noise * mold_affinity - 0.30) * 2.8, 0.0, 1.0)

  # Bare steel micro-scratches
  scratch_mask = np.clip(
      ((grain_n > 0.90) & (fine_n > 0.62)).astype(np.float32) * paint_mask,
      0.0,
      1.0,
  )

  # Delighted Albedo Palette (subtle, natural weathered industrial olive-gray enamel)
  col_paint_a = np.array([0.33, 0.37, 0.31], dtype=np.float32)
  col_paint_b = np.array([0.39, 0.43, 0.36], dtype=np.float32)
  paint_var = (macro_n * 0.6 + fine_n * 0.4)[:, :, None]
  col_paint = col_paint_a * (1.0 - paint_var) + col_paint_b * paint_var

  # Subtle dirt/soot wash on paint from drips
  col_paint *= 1.0 - drip_mask[:, :, None] * 0.22 - rib_groove[:, :, None] * 0.10

  # Rust & Oxide (natural warm brown-ochre to dark oxide, not overly saturated red)
  col_rust_dark = np.array([0.19, 0.12, 0.08], dtype=np.float32)
  col_rust_ochre = np.array([0.36, 0.20, 0.11], dtype=np.float32)
  col_rust = col_rust_dark * (1.0 - fine_n[:, :, None]) + col_rust_ochre * fine_n[:, :, None]

  # Mold / Mildew (dark olive-black spores + mossy damp green)
  col_mold_dark = np.array([0.10, 0.12, 0.09], dtype=np.float32)
  col_mold_green = np.array([0.18, 0.23, 0.14], dtype=np.float32)
  col_mold = col_mold_dark * (1.0 - grain_n[:, :, None]) + col_mold_green * grain_n[:, :, None]

  # Bare steel scratches
  col_steel = np.array([0.46, 0.48, 0.50], dtype=np.float32)

  albedo = col_rust.copy()
  albedo = albedo * (1.0 - paint_mask[:, :, None]) + col_paint * paint_mask[:, :, None]
  albedo = albedo * (1.0 - scratch_mask[:, :, None]) + col_steel * scratch_mask[:, :, None]
  albedo = albedo * (1.0 - mold_mask[:, :, None] * 0.85) + col_mold * (mold_mask[:, :, None] * 0.85)
  albedo *= 0.94 + 0.12 * grain_n[:, :, None]
  albedo = np.clip(albedo, 0.0, 1.0)

  # Height Map: Ribbed grooves + stepped paint flakes + recessed rust pits + raised mold
  height = np.full((res, res), 0.55, dtype=np.float32)
  height -= rib_groove * 0.14
  height -= (1.0 - paint_mask) * (0.18 + fine_n * 0.08)
  height += mold_mask * 0.09
  height += grain_n * 0.025
  height = np.clip(height, 0.0, 1.0)

  normal_rgb, ao = compute_normal_and_ao(height, strength=5.0)
  ao = np.clip(ao - mold_mask * 0.12 - rib_groove * 0.10, 0.40, 1.0)

  # Roughness: Paint ~0.52, Rust ~0.90, Mold ~0.94, Bare steel ~0.32
  roughness = np.full((res, res), 0.90, dtype=np.float32)
  roughness = roughness * (1.0 - paint_mask) + 0.52 * paint_mask
  roughness = roughness * (1.0 - scratch_mask) + 0.32 * scratch_mask
  roughness = roughness * (1.0 - mold_mask * 0.9) + 0.94 * (mold_mask * 0.9)
  roughness += (grain_n - 0.5) * 0.06
  roughness = np.clip(roughness, 0.05, 1.0)

  # Metallic: Only bare steel scratches are conductive
  metallic = np.clip(scratch_mask * 0.90 * (1.0 - mold_mask), 0.0, 1.0)

  orm_rgb = np.stack(
      [
          (ao * 255.0).astype(np.uint8),
          (roughness * 255.0).astype(np.uint8),
          (metallic * 255.0).astype(np.uint8),
      ],
      axis=-1,
  )

  Image.fromarray((albedo * 255.0).astype(np.uint8)).save(os.path.join(OUT_DIR, "gate_albedo.png"))
  Image.fromarray(orm_rgb).save(os.path.join(OUT_DIR, "gate_orm.png"))
  Image.fromarray(normal_rgb).save(os.path.join(OUT_DIR, "gate_normal.png"))
  print("[PBR] Saved Panel Albedo, ORM, Normal.")


def generate_frame_pbr(res: int = 1024) -> None:
  print(f"Generating {res}x{res} Weathered Galvanized Steel Frame PBR maps...")

  macro_n = periodic_spectral_noise(res, power=1.7, seed=601)
  mid_n = periodic_spectral_noise(res, power=2.2, seed=602)
  grain_n = periodic_spectral_noise(res, power=3.2, seed=603)

  # Brushed directional steel grain
  brush = (
      grain_n
      + np.roll(grain_n, 4, axis=1)
      + np.roll(grain_n, 8, axis=1)
      + np.roll(grain_n, 12, axis=1)
  ) * 0.25

  # Rust & grease oxidation patches on steel tracks/shafts
  rust_mask = np.clip((macro_n * 0.65 + mid_n * 0.35 - 0.62) * 3.5, 0.0, 1.0)
  grease_mask = np.clip((mid_n * 0.6 + macro_n * 0.4 - 0.68) * 3.0, 0.0, 1.0)

  col_steel = np.array([0.46, 0.48, 0.50], dtype=np.float32) * (0.88 + 0.24 * brush[:, :, None])
  col_rust = np.array([0.28, 0.16, 0.10], dtype=np.float32) * (0.85 + 0.30 * grain_n[:, :, None])
  col_grease = np.array([0.14, 0.14, 0.13], dtype=np.float32)

  albedo = col_steel.copy()
  albedo = albedo * (1.0 - rust_mask[:, :, None]) + col_rust * rust_mask[:, :, None]
  albedo = albedo * (1.0 - grease_mask[:, :, None] * 0.7) + col_grease * (grease_mask[:, :, None] * 0.7)
  albedo = np.clip(albedo, 0.0, 1.0)

  height = 0.55 - rust_mask * 0.12 + brush * 0.05
  normal_rgb, ao = compute_normal_and_ao(height, strength=3.5)

  roughness = np.full((res, res), 0.42, dtype=np.float32) + (brush - 0.5) * 0.12
  roughness = roughness * (1.0 - rust_mask) + 0.88 * rust_mask
  roughness = roughness * (1.0 - grease_mask * 0.7) + 0.24 * (grease_mask * 0.7)
  roughness = np.clip(roughness, 0.08, 1.0)

  metallic = np.clip(0.88 * (1.0 - rust_mask * 0.9) * (1.0 - grease_mask * 0.5), 0.0, 1.0)

  orm_rgb = np.stack(
      [
          (ao * 255.0).astype(np.uint8),
          (roughness * 255.0).astype(np.uint8),
          (metallic * 255.0).astype(np.uint8),
      ],
      axis=-1,
  )

  Image.fromarray((albedo * 255.0).astype(np.uint8)).save(os.path.join(OUT_DIR, "frame_albedo.png"))
  Image.fromarray(orm_rgb).save(os.path.join(OUT_DIR, "frame_orm.png"))
  Image.fromarray(normal_rgb).save(os.path.join(OUT_DIR, "frame_normal.png"))
  print("[PBR] Saved Frame Albedo, ORM, Normal.")


if __name__ == "__main__":
  os.makedirs(OUT_DIR, exist_ok=True)
  generate_panel_pbr(2048)
  generate_frame_pbr(1024)
