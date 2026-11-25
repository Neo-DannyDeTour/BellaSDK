#!/usr/bin/env python3
"""Generate seamless 2048x2048 procedural chipwood albedo maps (sRGB 30-240)."""

from __future__ import annotations

import math
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

SIZE: int = 2048


def _make_flake_sprite(
    rng: np.random.Generator,
    length: int,
    width: int,
    base_rgb: tuple[int, int, int],
    grain_contrast: float,
    edge_dark: float,
) -> Image.Image:
    """Build single wood-grain flake RGBA sprite with beveled dark rim."""
    pad = 4
    w, h = length + pad * 2, width + pad * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)

    # Irregular chipped wood polygon
    pts: list[tuple[float, float]] = []
    segs = max(4, length // 24)
    for i in range(segs + 1):
        t = i / segs
        x = pad + t * length + rng.uniform(-1.5, 1.5)
        y = pad + rng.uniform(0.0, width * 0.22)
        pts.append((x, y))
    for i in range(segs, -1, -1):
        t = i / segs
        x = pad + t * length + rng.uniform(-1.5, 1.5)
        y = pad + width - rng.uniform(0.0, width * 0.22)
        pts.append((x, y))
    draw.polygon(pts, fill=255)

    mask_arr = np.asarray(mask, dtype=np.float32) / 255.0

    # Directional fiber streaks along flake X-axis
    y_noise = rng.normal(0.0, 1.0, (h, 1)).astype(np.float32)
    x_mod = np.linspace(0.0, rng.uniform(2.0, 6.0), w, dtype=np.float32)[None, :]
    grain = np.sin(y_noise * 4.5 + x_mod) * 0.5 + rng.normal(0.0, 0.35, (h, w))
    grain = np.clip(grain * grain_contrast, -0.22, 0.22)

    # Subtle edge darkening for crisp normal/AO derivation
    eroded = np.minimum.reduce([
        np.roll(mask_arr, 1, axis=0),
        np.roll(mask_arr, -1, axis=0),
        np.roll(mask_arr, 1, axis=1),
        np.roll(mask_arr, -1, axis=1),
    ])
    rim = np.clip(mask_arr - eroded, 0.0, 1.0)

    rgb = np.zeros((h, w, 3), dtype=np.float32)
    for c in range(3):
        val = base_rgb[c] * (1.0 + grain) * (1.0 - rim * edge_dark)
        rgb[:, :, c] = np.clip(val, 30.0, 240.0)

    alpha = (mask_arr * 255.0).astype(np.uint8)
    rgba = np.dstack([rgb.astype(np.uint8), alpha])
    return Image.fromarray(rgba, mode="RGBA")


def _paste_wrapped(canvas: Image.Image, sprite: Image.Image, x: int, y: int) -> None:
    """Paste sprite with toroidal 2048x2048 wrap (zero seam delta)."""
    sw, sh = sprite.size
    for dx in (-SIZE, 0, SIZE):
        px = x + dx
        if px + sw <= 0 or px >= SIZE:
            continue
        for dy in (-SIZE, 0, SIZE):
            py = y + dy
            if py + sh <= 0 or py >= SIZE:
                continue
            canvas.alpha_composite(sprite, (px, py))


def _generate_variant(
    slug: str,
    seed: int,
    bg_rgb: tuple[int, int, int],
    palette: list[tuple[int, int, int]],
    flake_count: int,
    len_range: tuple[int, int],
    wid_range: tuple[int, int],
    grain_contrast: float,
    edge_dark: float,
    bark_ratio: float = 0.0,
    fine_noise: float = 0.0,
) -> None:
    rng = np.random.default_rng(seed)
    base = np.full((SIZE, SIZE, 3), bg_rgb, dtype=np.float32)
    if fine_noise > 0.0:
        base += rng.normal(0.0, fine_noise, (SIZE, SIZE, 3)).astype(np.float32)
    base = np.clip(base, 30.0, 240.0).astype(np.uint8)
    canvas = Image.fromarray(base, mode="RGB").convert("RGBA")

    # Pre-bake sprite bank for fast stamping
    bank: list[Image.Image] = []
    for _ in range(56):
        is_bark = rng.random() < bark_ratio
        col = (58, 42, 32) if is_bark else palette[int(rng.integers(0, len(palette)))]
        jitter = rng.uniform(0.90, 1.10)
        rgb = tuple(int(np.clip(c * jitter, 30, 240)) for c in col)
        ln = int(rng.integers(len_range[0], len_range[1]))
        wd = int(rng.integers(wid_range[0], wid_range[1]))
        if is_bark:
            ln = max(12, ln // 2)
            wd = max(5, wd // 2)
        bank.append(_make_flake_sprite(rng, ln, wd, rgb, grain_contrast, edge_dark))

    for _ in range(flake_count):
        sp = bank[int(rng.integers(0, len(bank)))]
        angle = float(rng.uniform(0.0, 360.0))
        rot = sp.rotate(angle, resample=Image.Resampling.BILINEAR, expand=True)
        cx = int(rng.integers(0, SIZE)) - rot.width // 2
        cy = int(rng.integers(0, SIZE)) - rot.height // 2
        _paste_wrapped(canvas, rot, cx, cy)

    out_arr = np.clip(np.asarray(canvas.convert("RGB")), 30, 240).astype(np.uint8)
    out_path = Path(f"assets/materials/{slug}/textures/{slug}_albedo.png")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out_arr, mode="RGB").save(out_path, optimize=True)
    print(f"Wrote {out_path}")


def main() -> None:
    # 1. Coarse pale-tan raw OSB + bark flecks
    _generate_variant(
        slug="chipwood_osb_raw",
        seed=101,
        bg_rgb=(176, 138, 92),
        palette=[
            (226, 198, 152),
            (214, 176, 122),
            (198, 152, 98),
            (232, 208, 168),
            (184, 134, 80),
        ],
        flake_count=3400,
        len_range=(90, 240),
        wid_range=(18, 48),
        grain_contrast=0.14,
        edge_dark=0.34,
        bark_ratio=0.04,
    )

    # 2. Medium-coarse warm amber aged OSB
    _generate_variant(
        slug="chipwood_osb_aged",
        seed=202,
        bg_rgb=(132, 98, 64),
        palette=[
            (182, 144, 96),
            (164, 124, 78),
            (148, 108, 66),
            (194, 158, 110),
            (136, 98, 60),
        ],
        flake_count=4600,
        len_range=(68, 185),
        wid_range=(14, 34),
        grain_contrast=0.16,
        edge_dark=0.30,
        bark_ratio=0.015,
    )

    # 3. Fine granular raw particleboard core
    _generate_variant(
        slug="chipwood_particle_fine",
        seed=303,
        bg_rgb=(162, 124, 88),
        palette=[
            (210, 174, 134),
            (192, 148, 106),
            (172, 126, 86),
            (146, 104, 68),
            (222, 188, 148),
        ],
        flake_count=16500,
        len_range=(12, 46),
        wid_range=(4, 14),
        grain_contrast=0.10,
        edge_dark=0.38,
        bark_ratio=0.05,
        fine_noise=4.0,
    )


if __name__ == "__main__":
    main()
