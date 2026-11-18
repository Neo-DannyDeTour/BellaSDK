#!/usr/bin/env python3
"""Generates a 256x256 HL2-style 'Květa' tin paint can texture for Godot 4 CylinderMesh."""

from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def generate_texture(output_path: Path) -> None:
    """Build 256x256 RGBA paint can texture matching Godot 4 CylinderMesh UV layout."""
    width: int = 256
    height: int = 256
    rng = random.Random(42)

    # Base aged off-white paper/tin
    img = Image.new("RGBA", (width, height), (194, 184, 158, 255))
    draw = ImageDraw.Draw(img)

    # --- UV Layout for Godot 4 CylinderMesh (verified on Godot 4.7.1) ---
    # Side wrap:  U [0.0..1.0] (X: 0..255),   V [0.0..0.5] (Y: 0..127)
    # Top cap:    U [0.0..0.5] (X: 0..127),   V [0.5..1.0] (Y: 128..255) -> center (64, 192)
    # Bottom cap: U [0.5..1.0] (X: 128..255), V [0.5..1.0] (Y: 128..255) -> center (192, 192)

    # 1. Side Label Design (Y: 0..127)
    teal_dark = (34, 68, 60, 255)
    teal_mid = (46, 86, 76, 255)
    paper_cream = (202, 192, 164, 255)

    # Background bands on cylinder side
    draw.rectangle([0, 0, width - 1, 127], fill=paper_cream)
    draw.rectangle([20, 6, 85, 120], fill=teal_dark)
    draw.rectangle([145, 6, 235, 120], fill=teal_mid)

    # Thin industrial border lines & spec lines
    draw.rectangle([90, 6, 138, 120], outline=teal_dark, width=2)
    for y_line in range(14, 115, 12):
        draw.line([(152, y_line), (228, y_line)], fill=paper_cream, width=2)

    # Vertical "Květa" text block (drawn horizontally, centered, then rotated 90 deg CCW)
    # Reads bottom-to-top on the can just like HL2's ELAVIA paint can.
    label_text = "Květa"
    txt_w, txt_h = 112, 46
    txt_img = Image.new("RGBA", (txt_w, txt_h), (0, 0, 0, 0))
    txt_draw = ImageDraw.Draw(txt_img)
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30
        )
    except OSError:
        font = ImageFont.load_default()

    bbox = txt_draw.textbbox((0, 0), label_text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    pos_x = (txt_w - text_w) // 2 - bbox[0]
    pos_y = (txt_h - text_h) // 2 - bbox[1]
    txt_draw.text((pos_x, pos_y), label_text, fill=teal_dark, font=font)

    txt_rot = txt_img.rotate(90, expand=True)
    # Center inside the [90..138, 6..120] bordered panel
    paste_x = 90 + (48 - txt_rot.width) // 2
    paste_y = 6 + (114 - txt_rot.height) // 2
    img.paste(txt_rot, (paste_x, paste_y), txt_rot)

    # 2. Top & Bottom Metallic Caps (Y: 128..255)
    tin_base = (128, 124, 114, 255)
    tin_ring = (92, 88, 80, 255)
    tin_hi = (152, 148, 136, 255)
    draw.rectangle([0, 128, width - 1, height - 1], fill=tin_base)

    for cap_center_x in (64, 192):
        cap_center_y = 192
        draw.ellipse(
            [cap_center_x - 58, cap_center_y - 58, cap_center_x + 58, cap_center_y + 58],
            outline=tin_ring,
            width=4,
        )
        draw.ellipse(
            [cap_center_x - 46, cap_center_y - 46, cap_center_x + 46, cap_center_y + 46],
            outline=tin_hi,
            width=2,
        )
        draw.ellipse(
            [cap_center_x - 32, cap_center_y - 32, cap_center_x + 32, cap_center_y + 32],
            outline=tin_ring,
            width=2,
        )

    # Top/bottom rim lip on side wrap
    draw.rectangle([0, 0, width - 1, 4], fill=tin_base)
    draw.rectangle([0, 123, width - 1, 127], fill=tin_base)

    # 3. Grunge, Rust & Noise Pass
    pixels = img.load()
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            grain = rng.randint(-18, 18)
            # Rust & dirt blotches near bottom rim and seams
            if rng.random() < 0.06 or (110 < y < 127 and rng.random() < 0.35):
                r = max(0, min(255, r - 45 + grain))
                g = max(0, min(255, g - 55 + grain))
                b = max(0, min(255, b - 65 + grain))
            else:
                r = max(0, min(255, r + grain))
                g = max(0, min(255, g + grain))
                b = max(0, min(255, b + grain))
            pixels[x, y] = (r, g, b, a)

    img = img.filter(ImageFilter.GaussianBlur(radius=0.4))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(output_path, "PNG")
    print(f"Saved: {output_path}")


if __name__ == "__main__":
    project_root = Path(__file__).resolve().parents[2]
    generate_texture(project_root / "assets/textures/kveta_paint_can.png")
