"""Generates Old Garage PBR Decal PNGs and Cobweb Alpha-Card textures + Godot Decal scenes.

Outputs:
  - assets/decals/garage/oil_slick.png
  - assets/decals/garage/wet_puddle.png
  - assets/decals/garage/rust_streak.png
  - assets/decals/garage/wall_grime.png
  - assets/models/cobwebs/cobweb_alpha.png
  - assets/models/cobwebs/cobweb_corner.glb, cobweb_drape.glb, cobweb_fence.glb
"""

from __future__ import annotations

import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT: str = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DECAL_DIR: str = os.path.join(REPO_ROOT, "assets", "decals", "garage")
COBWEB_DIR: str = os.path.join(REPO_ROOT, "assets", "models", "cobwebs")


def make_oil_slick(path: str, size: int = 512) -> None:
    rng = random.Random(42)
    img = Image.new("RGBA", (size, size), (12, 11, 10, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2
    for _ in range(24):
        ox = cx + rng.randint(-size // 5, size // 5)
        oy = cy + rng.randint(-size // 5, size // 5)
        rx = rng.randint(size // 10, size // 4)
        ry = rng.randint(size // 12, size // 4)
        alpha = rng.randint(90, 210)
        draw.ellipse((ox - rx, oy - ry, ox + rx, oy + ry), fill=(14, 13, 12, alpha))
    # Subtle iridescent oil sheen ring
    for _ in range(8):
        ox = cx + rng.randint(-size // 6, size // 6)
        oy = cy + rng.randint(-size // 6, size // 6)
        r = rng.randint(size // 14, size // 7)
        draw.ellipse((ox - r, oy - r, ox + r, oy + r), fill=(26, 22, 30, 55))
    img = img.filter(ImageFilter.GaussianBlur(radius=14))
    img.save(path)


def make_wet_puddle(path: str, size: int = 512) -> None:
    rng = random.Random(77)
    img = Image.new("RGBA", (size, size), (28, 32, 34, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2
    for _ in range(18):
        ox = cx + rng.randint(-size // 4, size // 4)
        oy = cy + rng.randint(-size // 5, size // 5)
        rx = rng.randint(size // 9, size // 3)
        ry = rng.randint(size // 10, size // 4)
        draw.ellipse((ox - rx, oy - ry, ox + rx, oy + ry), fill=(22, 26, 28, rng.randint(60, 145)))
    img = img.filter(ImageFilter.GaussianBlur(radius=18))
    img.save(path)


def make_rust_streak(path: str, size: int = 512) -> None:
    rng = random.Random(101)
    img = Image.new("RGBA", (size, size), (65, 28, 12, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(36):
        x = rng.randint(size // 6, size - size // 6)
        y0 = rng.randint(16, size // 5)
        y1 = rng.randint(size // 2, size - 24)
        w = rng.randint(6, 28)
        col = (rng.randint(58, 95), rng.randint(24, 42), rng.randint(10, 18), rng.randint(65, 175))
        draw.rounded_rectangle((x - w // 2, y0, x + w // 2, y1), radius=w // 2, fill=col)
    img = img.filter(ImageFilter.GaussianBlur(radius=10))
    img.save(path)


def make_wall_grime(path: str, size: int = 512) -> None:
    rng = random.Random(202)
    img = Image.new("RGBA", (size, size), (22, 24, 20, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(50):
        x = rng.randint(size // 8, size - size // 8)
        y = rng.randint(size // 8, size - size // 8)
        rx = rng.randint(24, 90)
        ry = rng.randint(24, 110)
        draw.ellipse((x - rx, y - ry, x + rx, y + ry), fill=(26, 29, 22, rng.randint(28, 95)))
    img = img.filter(ImageFilter.GaussianBlur(radius=20))
    img.save(path)


def make_cobweb_texture(path: str, size: int = 512) -> None:
    rng = random.Random(303)
    img = Image.new("RGBA", (size, size), (210, 212, 205, 0))
    draw = ImageDraw.Draw(img)
    # Anchor corner top-left (20, 20)
    ax, ay = 28, 28
    spokes = 11
    max_r = int(size * 0.90)
    angles = [math.radians(4 + i * (82.0 / (spokes - 1))) for i in range(spokes)]
    for ang in angles:
        ex = int(ax + math.cos(ang) * max_r)
        ey = int(ay + math.sin(ang) * max_r)
        draw.line((ax, ay, ex, ey), fill=(210, 214, 208, 175), width=2)
    # Concentric sagging web rings
    for ring in range(1, 14):
        r = int((ring / 14.0) * max_r * 0.94)
        for i in range(len(angles) - 1):
            a0, a1 = angles[i], angles[i + 1]
            p0 = (ax + math.cos(a0) * r, ay + math.sin(a0) * r)
            p1 = (ax + math.cos(a1) * r, ay + math.sin(a1) * r)
            mid_a = (a0 + a1) * 0.5
            sag = r * (0.92 + rng.uniform(-0.03, 0.02))
            pm = (ax + math.cos(mid_a) * sag, ay + math.sin(mid_a) * sag)
            alpha = int(165 * (1.0 - ring / 17.0))
            draw.line((p0, pm, p1), fill=(215, 218, 212, max(45, alpha)), width=2)
    img = img.filter(ImageFilter.GaussianBlur(radius=0.8))
    img.save(path)


def main() -> None:
    os.makedirs(DECAL_DIR, exist_ok=True)
    os.makedirs(COBWEB_DIR, exist_ok=True)
    make_oil_slick(os.path.join(DECAL_DIR, "oil_slick.png"))
    make_wet_puddle(os.path.join(DECAL_DIR, "wet_puddle.png"))
    make_rust_streak(os.path.join(DECAL_DIR, "rust_streak.png"))
    make_wall_grime(os.path.join(DECAL_DIR, "wall_grime.png"))
    make_cobweb_texture(os.path.join(COBWEB_DIR, "cobweb_alpha.png"))
    print("[generate_garage_decals_and_cobwebs] Generated decals & cobweb PNGs.")


if __name__ == "__main__":
    main()
