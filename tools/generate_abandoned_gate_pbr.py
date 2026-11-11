"""Generates authentic, mathematically seamless 2048x2048 PBR texture maps

for abandoned, moldy, chipped industrial sectional garage gates.
Outputs:
  - props/garage_gate/textures/gate_albedo.png
  - props/garage_gate/textures/gate_orm.png (R: AO, G: Roughness, B: Metallic)
  - props/garage_gate/textures/gate_normal.png (OpenGL +Y tangent space)
"""

import math
import os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, sobel

RES = 2048
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
  k_sq[0, 0] = 1.0  # Avoid zero division at DC component

  amplitude = 1.0 / (k_sq ** (power * 0.5))
  amplitude[0, 0] = 0.0

  phase = rng.uniform(0.0, 2.0 * np.pi, (size, size))
  f_complex = amplitude * (np.cos(phase) + 1j * np.sin(phase))

  # Symmetrize for real output
  f_complex[0, 0] = 0.0
  spatial = np.fft.ifft2(f_complex).real
  spatial = (spatial - spatial.min()) / (spatial.max() - spatial.min() + 1e-8)
  return spatial.astype(np.float32)


def generate_gate_pbr() -> None:
  os.makedirs(OUT_DIR, exist_ok=True)
  print(f"Generating 2048x2048 PBR maps into {OUT_DIR}...")

  # 1. Multi-scale periodic noise synthesis
  macro_noise = periodic_spectral_noise(RES, power=1.6, seed=101)
  mid_noise = periodic_spectral_noise(RES, power=1.9, seed=202)
  fine_noise = periodic_spectral_noise(RES, power=2.4, seed=303)
  micro_grain = periodic_spectral_noise(RES, power=3.2, seed=404)
  scratch_noise = periodic_spectral_noise(RES, power=2.8, seed=505)

  # Vertical drip distortion (periodic along X and Y)
  y_coords = np.linspace(0, 2 * np.pi, RES, endpoint=False)
  drip_modulation = 0.5 + 0.5 * np.sin(
      y_coords[:, None] * 3.0 + macro_noise * 2.0
  )
  drip_streaks = np.clip(
      (periodic_spectral_noise(RES, power=1.4, seed=707) * 2.5 - 1.2), 0.0, 1.0
  )
  drip_mask = np.clip(drip_modulation * drip_streaks * 1.5, 0.0, 1.0)

  # 2. Paint vs Rust Masking (Stepped peeling paint flakes)
  # Paint covers ~65% of the panel, rust breaches in patches and drip channels
  paint_field = (
      macro_noise * 0.55 + mid_noise * 0.35 + fine_noise * 0.10 - drip_mask * 0.20
  )
  paint_threshold = 0.42
  paint_mask_raw = paint_field > paint_threshold

  # Paint flake edge transition: sharp micro-edge with flaking bevel
  edge_dist = np.clip(
      (paint_field - paint_threshold) / 0.03, 0.0, 1.0
  )  # 0 at rust, 1 inside paint
  paint_mask = edge_dist

  # Exposed steel scratches along edges and high-friction lines
  scratch_mask = np.clip(
      (scratch_noise > 0.88).astype(np.float32)
      * (mid_noise > 0.45).astype(np.float32)
      * 1.8,
      0.0,
      1.0,
  )

  # 3. Organic Mildew & Mold Spore Colonies
  # Mold thrives in damp cavities, lower runoff, and edges of peeling paint
  mold_seed = (
      periodic_spectral_noise(RES, power=2.1, seed=808) * 0.6
      + periodic_spectral_noise(RES, power=3.0, seed=909) * 0.4
  )
  # Mold concentrates around paint edges and lower moisture zones
  mold_affinity = (1.0 - np.abs(paint_field - paint_threshold) * 8.0).clip(
      0.0, 1.0
  ) * 0.7 + (macro_noise > 0.65).astype(np.float32) * 0.5
  mold_mask = np.clip((mold_seed * mold_affinity - 0.28) * 3.5, 0.0, 1.0)

  # 4. Color Palette Construction (Linear PBR / Delighted Diffuse)
  # Palette definitions:
  # Base paint: Olive drab / sage green enamel (#4d5848 -> #626e5a)
  col_paint_base = np.array([0.31, 0.36, 0.28], dtype=np.float32)
  col_paint_worn = np.array([0.38, 0.43, 0.34], dtype=np.float32)
  col_paint = (
      col_paint_base * (1.0 - fine_noise[:, :, None] * 0.25)
      + col_paint_worn * (fine_noise[:, :, None] * 0.25)
  )

  # Rust colors: Dark burnt pits (#381c10) to warm iron oxide (#6a331c)
  col_rust_dark = np.array([0.22, 0.11, 0.06], dtype=np.float32)
  col_rust_mid = np.array([0.42, 0.20, 0.11], dtype=np.float32)
  rust_tone = mid_noise[:, :, None]
  col_rust = col_rust_dark * (1.0 - rust_tone) + col_rust_mid * rust_tone

  # Bare steel scratches (#65686b)
  col_bare_steel = np.array([0.42, 0.43, 0.45], dtype=np.float32)

  # Mold / Mildew colors: Dark olive-black spores (#161c14) with damp greenish-yellow fringe (#2d3a24)
  col_mold_dark = np.array([0.09, 0.11, 0.08], dtype=np.float32)
  col_mold_fringe = np.array([0.18, 0.23, 0.14], dtype=np.float32)
  col_mold = (
      col_mold_dark * (1.0 - micro_grain[:, :, None])
      + col_mold_fringe * micro_grain[:, :, None]
  )

  # Composite Albedo:
  # Start with Rust
  albedo = col_rust.copy()
  # Blend Bare Steel scratches
  albedo = albedo * (1.0 - scratch_mask[:, :, None]) + col_bare_steel * (
      scratch_mask[:, :, None]
  )
  # Blend Peeling Enamel Paint
  albedo = albedo * (1.0 - paint_mask[:, :, None]) + col_paint * (
      paint_mask[:, :, None]
  )
  # Blend Mold Spore Colonies
  albedo = albedo * (1.0 - mold_mask[:, :, None]) + col_mold * (
      mold_mask[:, :, None]
  )

  # Apply subtle micro-surface grime modulation
  albedo *= 0.92 + 0.16 * micro_grain[:, :, None]
  albedo = np.clip(albedo, 0.0, 1.0)

  # 5. Physical Height Map Synthesis
  # Structural depths: Rust pit (0.25) < Bare steel (0.42) < Paint slab (0.62) < Raised mold (0.72)
  height = np.full((RES, RES), 0.35, dtype=np.float32)  # Base substrate
  height -= (1.0 - paint_mask) * (0.15 + mid_noise * 0.12)  # Rust pits
  height += paint_mask * 0.22  # Stepped paint thickness
  height += scratch_mask * 0.05  # Scratch ridges
  height += mold_mask * 0.12  # Organic raised crust
  height += micro_grain * 0.02  # Micro-bump
  height = np.clip(height, 0.0, 1.0)

  # 6. OpenGL Normal Map (+Y Up, Tangent Space)
  # Toroid-wrapped Sobel gradients for 100% boundary continuity
  def wrapped_derivative_x(arr: np.ndarray) -> np.ndarray:
    return (np.roll(arr, -1, axis=1) - np.roll(arr, 1, axis=1)) * 0.5

  def wrapped_derivative_y(arr: np.ndarray) -> np.ndarray:
    return (np.roll(arr, -1, axis=0) - np.roll(arr, 1, axis=0)) * 0.5

  normal_strength = 6.5
  dh_dx = wrapped_derivative_x(height) * normal_strength
  dh_dy = (
      wrapped_derivative_y(height) * normal_strength
  )  # +Y is up in OpenGL/Godot

  # Normal components: Nx = -dh/dx, Ny = -dh/dy (or +dh/dy depending on convention), Nz = 1.0
  norm_x = -dh_dx
  norm_y = (
      dh_dy  # Standard Godot OpenGL: screen-up vector points towards positive Y
  )
  norm_z = np.ones_like(norm_x)

  magnitude = np.sqrt(norm_x**2 + norm_y**2 + norm_z**2)
  norm_x /= magnitude
  norm_y /= magnitude
  norm_z /= magnitude

  # Pack to [0, 255] RGB
  normal_rgb = np.stack(
      [
          ((norm_x * 0.5 + 0.5) * 255.0).astype(np.uint8),
          ((norm_y * 0.5 + 0.5) * 255.0).astype(np.uint8),
          ((norm_z * 0.5 + 0.5) * 255.0).astype(np.uint8),
      ],
      axis=-1,
  )

  # 7. Ambient Occlusion (Cavity Shading)
  # Darken deep rust pits, paint crevices, and spore crevices
  ao_curv = np.clip(
      1.0 - (wrapped_derivative_x(norm_x) + wrapped_derivative_y(norm_y)) * 0.8,
      0.0,
      1.0,
  )
  ao_raw = 0.80 + 0.20 * height
  # Extra occlusion inside tight mold clusters and stepped paint cliff edges
  ao = np.clip(ao_raw * ao_curv - mold_mask * 0.15, 0.40, 1.0)

  # 8. Roughness Map (G Channel)
  # Enamel paint: ~0.50
  # Porous rust: 0.88 - 0.95
  # Organic mildew: 0.92 - 0.96
  # Scraped bare steel: 0.30 - 0.35
  roughness = np.full((RES, RES), 0.90, dtype=np.float32)  # Default rust
  roughness = roughness * (1.0 - paint_mask) + 0.50 * paint_mask
  roughness = roughness * (1.0 - scratch_mask) + 0.32 * scratch_mask
  roughness = roughness * (1.0 - mold_mask) + 0.94 * mold_mask
  roughness += (micro_grain - 0.5) * 0.06
  roughness = np.clip(roughness, 0.05, 1.0)

  # 9. Metallic Map (B Channel)
  # Conductor (0.85 - 1.0) only on bare steel scratches; dielectric (0.0) on paint, rust, mold
  metallic = scratch_mask * 0.90
  metallic *= 1.0 - mold_mask  # Mold covers metal
  metallic = np.clip(metallic, 0.0, 1.0)

  # 10. Assemble ORM Texture (R: AO, G: Roughness, B: Metallic)
  orm_rgb = np.stack(
      [
          (ao * 255.0).astype(np.uint8),
          (roughness * 255.0).astype(np.uint8),
          (metallic * 255.0).astype(np.uint8),
      ],
      axis=-1,
  )

  # Convert Albedo to 8-bit sRGB
  albedo_rgb = (albedo * 255.0).astype(np.uint8)

  # Save images
  albedo_path = os.path.join(OUT_DIR, "gate_albedo.png")
  orm_path = os.path.join(OUT_DIR, "gate_orm.png")
  normal_path = os.path.join(OUT_DIR, "gate_normal.png")

  Image.fromarray(albedo_rgb).save(albedo_path)
  Image.fromarray(orm_rgb).save(orm_path)
  Image.fromarray(normal_rgb).save(normal_path)

  print(f"[PBR Generator] Saved Albedo: {albedo_path}")
  print(f"[PBR Generator] Saved ORM:    {orm_path}")
  print(f"[PBR Generator] Saved Normal: {normal_path}")


if __name__ == "__main__":
  generate_gate_pbr()
