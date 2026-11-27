"""Procedural Soviet Apartment Mailbox Bank (0.95m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-30_2.png:
- 6-column x 3-row wall-mounted steel compartment bank (18 numbered doors)
- Overhanging top cornice header & flush outer steel housing (min_y = 0)
- Per-door recessed mail slot hood, left-side cylinder lock, and weathered number plaque
- 2048x2048 PBR atlas (olive-brown painted steel, framed door panels, 18 plaques, tarnished metal)

Usage:
    /usr/bin/python3 tools/blender/props/apartment_mailbox_bank.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/apartment_mailbox_bank.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.street_prop import (  # noqa: E402
    ALL_BUT_FRONT,
    FONT_BOLD,
    FONT_COND,
    Builder,
    PropSpec,
    Region,
    font,
    main,
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-30_2.png"

COLS: int = 6
ROWS: int = 3
BANK_W: float = 1.34
BANK_H: float = 0.95
BANK_D: float = 0.16


def _door_panel_decal(img, rng) -> None:
    """Paint 3 subtle weathered vertical-framed door variants side-by-side in Region 1."""
    from PIL import ImageDraw

    draw = ImageDraw.Draw(img)
    w, h = img.size
    col_w = w // 3
    for i in range(3):
        x0 = i * col_w
        x1 = (i + 1) * col_w if i < 2 else w
        pad_x = int(col_w * 0.08)
        pad_top = int(h * 0.16)
        pad_bot = int(h * 0.08)
        # Outer door crease dark shadow
        draw.rectangle([x0 + 2, 2, x1 - 3, h - 3], outline=(38, 32, 24), width=4)
        # Inner stamped vertical panel frame
        draw.rectangle(
            [x0 + pad_x, pad_top, x1 - pad_x, h - pad_bot],
            outline=(48, 40, 30),
            width=4,
        )
        draw.rectangle(
            [x0 + pad_x + 4, pad_top + 4, x1 - pad_x - 4, h - pad_bot - 4],
            outline=(96, 84, 64),
            width=2,
        )
        # Mail slot dark opening near top
        slot_y0 = int(h * 0.065)
        slot_y1 = int(h * 0.110)
        draw.rectangle(
            [x0 + int(col_w * 0.13), slot_y0, x1 - int(col_w * 0.13), slot_y1],
            fill=(20, 18, 16),
            outline=(94, 80, 58),
            width=2,
        )
        # Subtle lock grime stain along left edge
        lx = x0 + int(col_w * 0.13)
        ly = int(h * 0.48)
        draw.ellipse([lx - 18, ly - 24, lx + 18, ly + 24], fill=(54, 46, 34))


def _number_plaques_decal(img, rng) -> None:
    """Paint 18 weathered numbered apartment plaques (6x3 grid) in Region 2."""
    import numpy as np
    from PIL import Image, ImageDraw

    w, h = img.size
    arr = np.asarray(img, dtype=np.float32)
    # Light aged enamel/paper base across tile
    arr = arr * 0.25 + np.array([154.0, 148.0, 132.0], dtype=np.float32)[None, None, :] * 0.75
    plaque_img = Image.fromarray(np.clip(arr, 30, 240).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(plaque_img)
    f_num = font(FONT_BOLD, 88)

    cw = w // COLS
    ch = h // ROWS
    for row in range(ROWS):
        for col in range(COLS):
            num = row * COLS + col + 1
            x0 = col * cw
            y0 = row * ch
            x1 = x0 + cw - 1
            y1 = y0 + ch - 1
            # Slight per-plaque age/tone jitter
            tone = int(rng.integers(-14, 14))
            bg = (
                max(35, min(225, 148 + tone)),
                max(35, min(225, 142 + tone)),
                max(35, min(225, 124 + tone)),
            )
            draw.rectangle([x0 + 6, y0 + 6, x1 - 6, y1 - 6], fill=bg, outline=(52, 46, 38), width=4)
            # Corner rivets
            for rx_p in (x0 + 16, x1 - 16):
                for ry_p in (y0 + 16, y1 - 16):
                    draw.ellipse([rx_p - 4, ry_p - 4, rx_p + 4, ry_p + 4], fill=(64, 58, 48))
            # Stenciled apartment number
            txt = str(num)
            bbox = draw.textbbox((0, 0), txt, font=f_num)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            tx = x0 + (cw - tw) // 2 - bbox[0]
            ty = y0 + (ch - th) // 2 - bbox[1]
            draw.text((tx, ty), txt, font=f_num, fill=(42, 38, 34))

    # Subtle overall grime wash
    f_arr = np.asarray(plaque_img, dtype=np.float32)
    f_arr *= (0.88 + 0.14 * rng.random((h, w, 1)).astype(np.float32))
    img.paste(Image.fromarray(np.clip(f_arr, 30, 240).astype(np.uint8), mode="RGB"))


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Cabinet shell & cornice (weathered olive-umber painted steel)
    # 1 = Compartment door fronts (3 subtle vertical door frame + mail slot variants)
    # 2 = 6x3 grid of numbered compartment plaques (1..18)
    # 3 = Tarnished brass/steel cylinder locks & slot trim

    shell_h = 0.924
    shell_d = 0.144
    b.add_box(Vector((0.0, 0.006, shell_h * 0.5)), (BANK_W, shell_d, shell_h), region=0)
    # Top overhanging cornice ledge
    b.add_box(Vector((0.0, -0.004, BANK_H - 0.013)), (BANK_W + 0.022, BANK_D + 0.016, 0.026), region=0)
    # Bottom sill trim
    b.add_box(Vector((0.0, -0.001, 0.009)), (BANK_W + 0.008, shell_d + 0.014, 0.018), region=0)

    inner_w = BANK_W - 0.036
    inner_z0 = 0.022
    inner_z1 = shell_h - 0.010
    col_pitch = inner_w / float(COLS)
    row_pitch = (inner_z1 - inner_z0) / float(ROWS)
    door_w = col_pitch - 0.008
    door_h = row_pitch - 0.008
    door_d = 0.015
    door_cy = -shell_d * 0.5 + 0.002

    for row in range(ROWS):
        # Top row = 0 in texture, bottom row = 2 in texture; Blender Z goes bottom->top
        cz = inner_z1 - (row + 0.5) * row_pitch
        for col in range(COLS):
            cx = -inner_w * 0.5 + (col + 0.5) * col_pitch
            variant = (row * COLS + col) % 3
            du = 1.0 / 3.0
            door_uv = (variant * du + 0.01, 0.02, (variant + 1) * du - 0.01, 0.98)

            # Raised door body + UV-mapped front face
            b.add_box(
                Vector((cx, door_cy, cz)),
                (door_w, door_d, door_h),
                region=0,
                skip=("front", "back"),
            )
            b.add_plate(
                Vector((cx, door_cy - door_d * 0.5, cz)),
                (door_w, 0.004, door_h),
                region=1,
                uv_rect=door_uv,
            )

            # Mail slot protective hood / visor lip at top of door
            b.add_box(
                Vector((cx, door_cy - door_d * 0.5 - 0.004, cz + door_h * 0.365)),
                (door_w * 0.72, 0.009, 0.012),
                region=3,
                skip=("back",),
            )

            # Cylinder lock & knob on left stile
            b.add_box(
                Vector((cx - door_w * 0.36, door_cy - door_d * 0.5 - 0.005, cz - 0.008)),
                (0.018, 0.011, 0.022),
                region=3,
                skip=("back",),
            )

            # Numbered plaque at lower center of door (UV cell in Region 2)
            pu0 = (col + 0.05) / float(COLS)
            pu1 = (col + 0.95) / float(COLS)
            # PIL y=0 (top row=0) corresponds to V=1.0 -> bottom row=2 has lowest V
            pv1 = 1.0 - (row + 0.06) / float(ROWS)
            pv0 = 1.0 - (row + 0.94) / float(ROWS)
            b.add_box(
                Vector((cx, door_cy - door_d * 0.5 - 0.002, cz - door_h * 0.27)),
                (door_w * 0.58, 0.005, 0.056),
                region=2,
                skip=("back",),
                uv_rects={"front": (pu0, pv0, pu1, pv1)},
            )


SPEC = PropSpec(
    slug="apartment_mailbox_bank",
    node_name="ApartmentMailboxBank",
    mat_name="M_ApartmentMailboxBank",
    ref_image=REF_IMAGE,
    target_h=0.95,
    tri_budget=1400,
    body="static",
    seed=1830,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="paint", rgb=(98, 82, 56), wear=0.48, rough=0.62, metal=0.25, nrm=0.9),
        Region(kind="paint", rgb=(102, 86, 58), wear=0.45, rough=0.60, metal=0.24, nrm=0.9, decal=_door_panel_decal),
        Region(kind="paint", rgb=(146, 140, 126), wear=0.45, rough=0.70, metal=0.15, nrm=0.5, decal=_number_plaques_decal),
        Region(kind="steel", rgb=(78, 72, 60), wear=0.55, rough=0.46, metal=0.72, nrm=0.7),
    ],
    build=_build,
    collision=[
        ("CollisionShape3D", (1.362, 0.95, 0.176), (0.0, 0.475, 0.0)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
