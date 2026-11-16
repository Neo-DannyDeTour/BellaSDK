"""Pack 64-frame splatter RGBA and normal sequences into 8x8 2048x2048 Godot 4 atlases.

Reads rgba_0001.png..0064.png and norm_0001.png..0064.png from --input-dir,
applies a per-tile radial edge vignette (r > 0.88 smoothstep to 0 at r = 1.0),
normalizes normal vectors, dilates RGB and normal borders by 4px into
transparent pixels, sets neutral normal (128, 128, 255) in remaining
transparent areas, and exports splatter_8x8_albedo_alpha.png and
splatter_8x8_normal.png to --output-dir.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

GRID_COLS = 8
GRID_ROWS = 8
FRAME_COUNT = GRID_COLS * GRID_ROWS
TILE_SIZE = 256
ATLAS_SIZE = TILE_SIZE * GRID_COLS  # 2048
VIGNETTE_INNER = 0.88
VIGNETTE_OUTER = 1.0
DILATION_PX = 4
NEUTRAL_NORMAL = np.array([128, 128, 255], dtype=np.uint8)


def build_radial_vignette(size: int = TILE_SIZE) -> np.ndarray:
    """Return a (size, size) float32 vignette mask: 1 for r <= 0.88, smoothstep to 0 at r = 1.0."""
    coords = np.linspace(-1.0, 1.0, size, dtype=np.float32)
    yy, xx = np.meshgrid(coords, coords, indexing="ij")
    radius = np.sqrt(xx * xx + yy * yy)
    t = np.clip((radius - VIGNETTE_INNER) / (VIGNETTE_OUTER - VIGNETTE_INNER), 0.0, 1.0)
    smooth = t * t * (3.0 - 2.0 * t)
    return 1.0 - smooth


def dilate_rgb(
    rgb: np.ndarray,
    alpha_mask: np.ndarray,
    iterations: int = DILATION_PX,
) -> tuple[np.ndarray, np.ndarray]:
    """Dilate RGB values from alpha_mask pixels outward by `iterations` pixels (8-connected)."""
    out_rgb = rgb.astype(np.float32, copy=True)
    valid = alpha_mask.copy()
    h, w = valid.shape

    for _ in range(iterations):
        if np.all(valid):
            break
        padded_rgb = np.pad(out_rgb * valid[..., None], ((1, 1), (1, 1), (0, 0)), mode="constant")
        padded_val = np.pad(valid.astype(np.float32), ((1, 1), (1, 1)), mode="constant")

        acc_rgb = np.zeros_like(out_rgb)
        acc_cnt = np.zeros((h, w), dtype=np.float32)
        for dy in range(3):
            for dx in range(3):
                if dy == 1 and dx == 1:
                    continue
                acc_rgb += padded_rgb[dy : dy + h, dx : dx + w]
                acc_cnt += padded_val[dy : dy + h, dx : dx + w]

        fill = (~valid) & (acc_cnt > 0.0)
        out_rgb[fill] = acc_rgb[fill] / acc_cnt[fill, None]
        valid = valid | fill

    return out_rgb, valid


def normalize_normal_rgb(rgb: np.ndarray, valid_mask: np.ndarray) -> np.ndarray:
    """Normalize [0..255] tangent/camera-space normal RGB on valid_mask; neutral elsewhere."""
    vec = (rgb.astype(np.float32) / 255.0) * 2.0 - 1.0
    length = np.linalg.norm(vec, axis=-1, keepdims=True)
    non_zero = valid_mask[..., None] & (length > 1e-6)

    normalized = np.empty_like(vec)
    normalized[..., 0] = 0.0
    normalized[..., 1] = 0.0
    normalized[..., 2] = 1.0
    np.divide(vec, np.where(non_zero, length, 1.0), out=normalized, where=non_zero)

    encoded = np.clip(np.round((normalized * 0.5 + 0.5) * 255.0), 0.0, 255.0).astype(np.uint8)
    encoded[~valid_mask] = NEUTRAL_NORMAL
    return encoded


def load_tile_rgba(path: Path) -> np.ndarray:
    """Load an image as a (TILE_SIZE, TILE_SIZE, 4) uint8 RGBA numpy array."""
    if not path.is_file():
        raise FileNotFoundError(f"Missing frame: {path}")
    with Image.open(path) as img:
        rgba = img.convert("RGBA")
        if rgba.size != (TILE_SIZE, TILE_SIZE):
            rgba = rgba.resize((TILE_SIZE, TILE_SIZE), Image.Resampling.LANCZOS)
        return np.asarray(rgba, dtype=np.uint8).copy()


def pack_flipbook(input_dir: Path, output_dir: Path) -> tuple[Path, Path]:
    """Pack 64 rgba/norm frames from input_dir into 2048x2048 atlases in output_dir."""
    output_dir.mkdir(parents=True, exist_ok=True)
    vignette = build_radial_vignette(TILE_SIZE)

    albedo_atlas = np.zeros((ATLAS_SIZE, ATLAS_SIZE, 4), dtype=np.uint8)
    normal_atlas = np.zeros((ATLAS_SIZE, ATLAS_SIZE, 4), dtype=np.uint8)
    normal_atlas[..., :3] = NEUTRAL_NORMAL

    for idx in range(FRAME_COUNT):
        frame_num = idx + 1
        rgba_path = input_dir / f"rgba_{frame_num:04d}.png"
        norm_path = input_dir / f"norm_{frame_num:04d}.png"

        rgba = load_tile_rgba(rgba_path)
        norm = load_tile_rgba(norm_path)

        # Apply radial edge vignette to alpha so billboard edges never clip as hard boxes.
        vignetted_alpha = np.clip(
            np.round(rgba[..., 3].astype(np.float32) * vignette), 0.0, 255.0
        ).astype(np.uint8)
        alpha_mask = vignetted_alpha > 0

        # Dilate albedo RGB 4px into transparent pixels to prevent mipmap dark fringes.
        dilated_albedo_rgb, albedo_valid = dilate_rgb(rgba[..., :3], alpha_mask, DILATION_PX)
        albedo_tile = np.zeros((TILE_SIZE, TILE_SIZE, 4), dtype=np.uint8)
        albedo_tile[albedo_valid, :3] = np.clip(
            np.round(dilated_albedo_rgb[albedo_valid]), 0.0, 255.0
        ).astype(np.uint8)
        albedo_tile[..., 3] = vignetted_alpha

        # Normalize normals on visible pixels, dilate 4px, re-normalize, neutral outside.
        norm_unit_rgb = normalize_normal_rgb(norm[..., :3], alpha_mask)
        dilated_norm_rgb, norm_valid = dilate_rgb(norm_unit_rgb, alpha_mask, DILATION_PX)
        norm_tile_rgb = normalize_normal_rgb(dilated_norm_rgb, norm_valid)

        norm_tile = np.zeros((TILE_SIZE, TILE_SIZE, 4), dtype=np.uint8)
        norm_tile[..., :3] = norm_tile_rgb
        norm_tile[..., 3] = vignetted_alpha

        row = idx // GRID_COLS
        col = idx % GRID_COLS
        y0 = row * TILE_SIZE
        x0 = col * TILE_SIZE
        albedo_atlas[y0 : y0 + TILE_SIZE, x0 : x0 + TILE_SIZE] = albedo_tile
        normal_atlas[y0 : y0 + TILE_SIZE, x0 : x0 + TILE_SIZE] = norm_tile

    albedo_out = output_dir / "splatter_8x8_albedo_alpha.png"
    normal_out = output_dir / "splatter_8x8_normal.png"

    Image.fromarray(albedo_atlas, mode="RGBA").save(albedo_out)
    Image.fromarray(normal_atlas, mode="RGBA").save(normal_out)
    return albedo_out, normal_out


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Pack 64-frame splatter RGBA and normal sequences into 8x8 2048x2048 atlases."
    )
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=Path("build/frames"),
        help="Directory containing rgba_0001..0064.png and norm_0001..0064.png (default: build/frames)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("assets/vfx"),
        help="Output directory for packed 8x8 atlases (default: assets/vfx)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    args = parse_args(argv)
    albedo_out, normal_out = pack_flipbook(args.input_dir, args.output_dir)
    print(f"Exported {albedo_out} and {normal_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
