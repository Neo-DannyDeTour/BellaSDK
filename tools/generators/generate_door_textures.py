#!/usr/bin/env python3
"""Procedural PBR texture generator for industrial louvered metal door."""

import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def generate_noise(width: int, height: int, scale: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    low_w = max(2, width // scale)
    low_h = max(2, height // scale)
    grid = rng.uniform(0.0, 1.0, (low_h, low_w)).astype(np.float32)
    img = Image.fromarray((grid * 255.0).astype(np.uint8), mode="L")
    img = img.resize((width, height), resample=Image.Resampling.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255.0


def build_textures(out_dir: str = "assets/textures/door") -> None:
    os.makedirs(out_dir, exist_ok=True)
    w, h = 1024, 2048

    n_coarse = generate_noise(w, h, 64, 101)
    n_med = generate_noise(w, h, 16, 202)
    n_fine = generate_noise(w, h, 4, 303)
    grunge = np.clip(n_coarse * 0.5 + n_med * 0.35 + n_fine * 0.15, 0.0, 1.0)

    # Base slate-teal metal RGB
    base_r = 62.0 + (grunge - 0.5) * 26.0
    base_g = 78.0 + (grunge - 0.5) * 30.0
    base_b = 80.0 + (grunge - 0.5) * 28.0
    albedo = np.stack([base_r, base_g, base_b], axis=-1).clip(0, 255).astype(np.uint8)

    ao = np.full((h, w), 240.0, dtype=np.float32)
    rough = np.clip(145.0 + (grunge - 0.5) * 70.0, 90.0, 225.0)
    metal = np.full((h, w), 195.0, dtype=np.float32)
    height_map = (grunge * 0.12).astype(np.float32)

    albedo_img = Image.fromarray(albedo, mode="RGB")
    draw_a = ImageDraw.Draw(albedo_img)

    # Panel inset seam
    draw_a.rectangle([20, 20, w - 20, h - 20], outline=(38, 48, 50), width=4)
    height_map[18:24, 18 : w - 18] -= 0.15
    height_map[h - 24 : h - 18, 18 : w - 18] -= 0.15
    height_map[18 : h - 18, 18:24] -= 0.15
    height_map[18 : h - 18, w - 24 : w - 18] -= 0.15

    # Louver coordinates: top & bottom vents
    vents = [
        (300, 230, 724, 710),
        (300, 1140, 724, 1620),
    ]
    slat_count = 13

    for vx0, vy0, vx1, vy1 in vents:
        # Frame recess
        draw_a.rectangle([vx0 - 10, vy0 - 10, vx1 + 10, vy1 + 10], outline=(42, 52, 54), width=6)
        ao[vy0 - 8 : vy1 + 8, vx0 - 8 : vx1 + 8] = 175.0
        height_map[vy0 - 6 : vy1 + 6, vx0 - 6 : vx1 + 6] -= 0.25

        slat_h = (vy1 - vy0) // slat_count
        for i in range(slat_count):
            sy0 = vy0 + i * slat_h
            sy1 = sy0 + slat_h - 4
            # Dark cavity under slat
            draw_a.rectangle([vx0, sy0, vx1, sy0 + 11], fill=(16, 20, 22))
            ao[sy0 : sy0 + 12, vx0:vx1] = 35.0
            rough[sy0 : sy0 + 12, vx0:vx1] = 230.0
            metal[sy0 : sy0 + 12, vx0:vx1] = 60.0

            # Lit angled slat blade
            draw_a.rectangle([vx0, sy0 + 12, vx1, sy1], fill=(108, 122, 124))
            for row in range(sy0 + 12, sy1):
                t = (row - (sy0 + 12)) / max(1, (sy1 - (sy0 + 12)))
                height_map[row, vx0:vx1] = 0.2 + t * 0.65

    # Upper-left white peeled paint strip (from reference)
    draw_a.polygon(
        [(272, 260), (298, 245), (300, 650), (282, 680), (270, 645)],
        fill=(188, 198, 200),
    )
    rough[245:680, 270:300] = 215.0
    metal[245:680, 270:300] = 30.0
    height_map[245:680, 270:300] += 0.12

    # Worn center stencil / scratch marks below top vent
    draw_a.rectangle([390, 795, 635, 812], fill=(82, 95, 97))
    rough[795:812, 390:635] = 210.0

    # Slight blur on albedo for natural weathering
    albedo_img = albedo_img.filter(ImageFilter.GaussianBlur(radius=0.6))
    albedo_img.save(os.path.join(out_dir, "door_albedo.png"))

    # ORM Map (R=AO, G=Roughness, B=Metallic)
    orm = np.stack([ao, rough, metal], axis=-1).clip(0, 255).astype(np.uint8)
    Image.fromarray(orm, mode="RGB").save(os.path.join(out_dir, "door_orm.png"))

    # Normal Map from height_map gradients (OpenGL +Y up)
    dy, dx = np.gradient(height_map)
    strength = 6.0
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(height_map)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx /= length
    ny /= length
    nz /= length

    norm_r = ((nx * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)
    norm_g = ((ny * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)
    norm_b = ((nz * 0.5 + 0.5) * 255.0).clip(0, 255).astype(np.uint8)
    normal_img = Image.fromarray(np.stack([norm_r, norm_g, norm_b], axis=-1), mode="RGB")
    normal_img.save(os.path.join(out_dir, "door_normal.png"))
    print(f"Generated door PBR textures in: {os.path.abspath(out_dir)}")


if __name__ == "__main__":
    build_textures("assets/textures/door")
