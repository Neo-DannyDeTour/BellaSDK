"""Procedural Soviet Street Pedestal Payphone (1.55m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-23_3.png:
- Bolted square light-gray steel floor flange (min_y = 0) + dark rectangular pedestal post
- Rounded-top open-front light-gray steel acoustic hood with 'Phone' upper fascia & side emblems
- Recessed armored dark steel coin-phone chassis with instruction header, 3x4 keypad, coin return
- Left-side cradle bracket, angled heavy handset, and armored cord loop
- 2048x2048 PBR atlas (weathered gray enamel, dark pedestal steel, phone faceplate decal, chrome)

Usage:
    /usr/bin/python3 tools/blender/props/soviet_payphone.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/soviet_payphone.py
"""

from __future__ import annotations

import math
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
    rx,
    ry,
    rz,
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-23_3.png"


def _hood_sign_decal(img, rng) -> None:
    """Paint 'Phone' upper fascia banner (top half) and embossed side handset icon (bottom half)."""
    from PIL import ImageDraw

    draw = ImageDraw.Draw(img)
    w, h = img.size
    # Top half (V in [0.5..1.0]): 'Phone' fascia sign
    draw.rectangle([24, 36, w - 24, h // 2 - 28], fill=(134, 134, 130), outline=(72, 72, 70), width=6)
    f_hdr = font(FONT_BOLD, 175)
    txt = "P h o n e"
    bbox = draw.textbbox((0, 0), txt, font=f_hdr)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    draw.text(((w - tw) // 2 - bbox[0], (h // 2 - th) // 2 - bbox[1] - 6), txt, font=f_hdr, fill=(32, 34, 36))

    # Bottom half (V in [0.0..0.5]): subtle raised-relief phone handset silhouette on hood sides
    cy = int(h * 0.74)
    cx = w // 2
    draw.rounded_rectangle([cx - 170, cy - 170, cx + 170, cy + 170], radius=34, outline=(104, 104, 100), width=10)
    # Stylized handset curve in faded paint
    draw.arc([cx - 95, cy - 115, cx + 95, cy + 115], start=125, end=235, fill=(102, 102, 98), width=36)
    draw.ellipse([cx - 42, cy - 122, cx + 14, cy - 66], fill=(102, 102, 98))
    draw.ellipse([cx - 42, cy + 66, cx + 14, cy + 122], fill=(102, 102, 98))


def _coin_box_decal(img, rng) -> None:
    """Paint armored coin-phone front faceplate (header placard, 3x4 keypad grid, coin return)."""
    from PIL import ImageDraw

    draw = ImageDraw.Draw(img)
    w, h = img.size

    # Dark armored chassis base
    draw.rectangle([0, 0, w, h], fill=(42, 42, 44))
    draw.rectangle([16, 16, w - 16, h - 16], outline=(76, 76, 78), width=6)

    # Top header placard (instruction card + coin slot surround)
    draw.rectangle([48, 36, w - 48, 220], fill=(148, 154, 158), outline=(34, 36, 38), width=6)
    draw.rectangle([68, 52, w - 68, 118], fill=(64, 88, 112))
    f_sm = font(FONT_COND, 38)
    draw.text((92, 66), "LOCAL / LONG DIST.", font=f_sm, fill=(208, 212, 214))
    # Coin slot plate
    draw.rectangle([w - 220, 134, w - 76, 200], fill=(118, 120, 124), outline=(42, 42, 44), width=4)
    draw.rectangle([w - 164, 148, w - 144, 188], fill=(18, 18, 20))

    # Brushed steel 3x4 keypad plate on right half (y: 256..610)
    kp_x0, kp_y0, kp_x1, kp_y1 = int(w * 0.44), 260, w - 58, 620
    draw.rectangle([kp_x0, kp_y0, kp_x1, kp_y1], fill=(128, 130, 132), outline=(32, 32, 34), width=6)
    f_key = font(FONT_BOLD, 34)
    keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "*", "0", "#"]
    kw = (kp_x1 - kp_x0 - 48) // 3
    kh = (kp_y1 - kp_y0 - 48) // 4
    for idx, ch in enumerate(keys):
        r, c = idx // 3, idx % 3
        bx0 = kp_x0 + 24 + c * kw + 6
        by0 = kp_y0 + 24 + r * kh + 6
        bx1 = bx0 + kw - 12
        by1 = by0 + kh - 12
        draw.rectangle([bx0, by0, bx1, by1], fill=(166, 168, 170), outline=(48, 48, 50), width=4)
        draw.text((bx0 + 18, by0 + 12), ch, font=f_key, fill=(32, 34, 36))

    # Lower armored vault & coin return pocket (y: 660..984)
    draw.rectangle([48, 660, w - 48, h - 36], fill=(38, 38, 40), outline=(66, 66, 68), width=6)
    # Coin return cup (lower left)
    draw.rectangle([76, 720, 356, 940], fill=(116, 118, 122), outline=(28, 28, 30), width=6)
    draw.rectangle([104, 754, 328, 908], fill=(22, 22, 24))
    # Coin release push lever (lower right)
    draw.rectangle([w - 310, 760, w - 90, 910], fill=(92, 94, 96), outline=(28, 28, 30), width=5)


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Light-gray painted steel hood & base flange
    # 1 = Dark charcoal steel pedestal post & phone chassis sides
    # 2 = Hood 'Phone' fascia + side handset icon decals
    # 3 = Armored coin-phone faceplate decal

    # 1. Grounded floor flange + stepped collar (min_z = 0.0)
    b.add_box(Vector((0.0, 0.0, 0.015)), (0.24, 0.24, 0.030), region=0)
    b.add_box(Vector((0.0, 0.0, 0.042)), (0.16, 0.16, 0.024), region=0)

    # 2. Dark steel pedestal post (z = 0.030..0.725)
    b.add_box(Vector((0.0, 0.02, 0.378)), (0.112, 0.112, 0.696), region=1)
    # Gusset collar under hood
    b.add_box(Vector((0.0, 0.015, 0.708)), (0.19, 0.19, 0.032), region=0)

    # 3. Acoustic hood enclosure (z = 0.720..1.550, open front -Y)
    hood_w = 0.380
    hood_d = 0.320
    wall_t = 0.030
    hood_z0 = 0.720
    hood_z1 = 1.460
    hood_h = hood_z1 - hood_z0
    hood_cz = (hood_z0 + hood_z1) * 0.5

    # Bottom tray floor (inset inside side & back walls to prevent coplanar z-fighting)
    b.add_box(Vector((0.0, -wall_t * 0.5, hood_z0 + 0.016)), (hood_w - 2.0 * wall_t, hood_d - wall_t, 0.032), region=0)
    # Back wall (+Y)
    b.add_box(Vector((0.0, hood_d * 0.5 - wall_t * 0.5, hood_cz)), (hood_w, wall_t, hood_h), region=0)
    # Left & Right side walls with subtle handset emblem plates on outer faces
    for sx, side_name in ((-1.0, "left"), (1.0, "right")):
        wx = sx * (hood_w * 0.5 - wall_t * 0.5)
        b.add_box(Vector((wx, -wall_t * 0.5, hood_cz)), (wall_t, hood_d - wall_t, hood_h), region=0)
        # Outer emblem plate mapped to bottom half of Region 2
        px = sx * (hood_w * 0.5 + 0.001)
        if sx < 0:
            pts = [
                (px, 0.08, 1.02), (px, -0.10, 1.02),
                (px, -0.10, 1.24), (px, 0.08, 1.24),
            ]
        else:
            pts = [
                (px, -0.10, 1.02), (px, 0.08, 1.02),
                (px, 0.08, 1.24), (px, -0.10, 1.24),
            ]
        b.add_quad(pts, region=2, uvs=[(0.1, 0.04), (0.9, 0.04), (0.9, 0.46), (0.1, 0.46)])

    # Rounded/chamfered roof cap (z = 1.460..1.550) via 3-ring loft
    roof_rings = []
    for rz_val, rw, rd in (
        (1.460, hood_w, hood_d),
        (1.515, hood_w - 0.048, hood_d - 0.020),
        (1.550, hood_w - 0.130, hood_d - 0.045),
    ):
        hw, hd = rw * 0.5, rd * 0.5
        roof_rings.append([
            Vector((-hw, -hd, rz_val)),
            Vector((+hw, -hd, rz_val)),
            Vector((+hw, +hd, rz_val)),
            Vector((-hw, +hd, rz_val)),
        ])
    b.add_loft(roof_rings, region=0, caps=(True, True), smooth=False)

    # Upper front 'Phone' fascia header (z = 1.390..1.475)
    b.add_box(Vector((0.0, -hood_d * 0.5 + 0.018, 1.432)), (hood_w - 0.028, 0.036, 0.084), region=0)
    b.add_plate(
        Vector((0.0, -hood_d * 0.5 - 0.002, 1.432)),
        (hood_w - 0.036, 0.004, 0.076),
        region=2,
        uv_rect=(0.02, 0.52, 0.98, 0.98),
    )

    # 4. Recessed armored coin-phone chassis inside hood (y = +0.02..+0.12, z = 0.81..1.37)
    box_w, box_d, box_h = 0.245, 0.095, 0.555
    box_cy = 0.080
    box_cz = 1.090
    b.add_box(Vector((0.0, box_cy, box_cz)), (box_w, box_d, box_h), region=1, skip=("front",))
    b.add_plate(
        Vector((0.0, box_cy - box_d * 0.5, box_cz)),
        (box_w, 0.004, box_h),
        region=3,
        uv_rect=(0.01, 0.01, 0.99, 0.99),
    )
    # Raised 3D keypad bezel & coin return hood for crisp silhouette in 3/4 view
    face_y = box_cy - box_d * 0.5
    b.add_box(Vector((0.052, face_y - 0.005, 1.115)), (0.095, 0.012, 0.135), region=1, skip=("back",))
    b.add_box(Vector((-0.055, face_y - 0.007, 0.885)), (0.076, 0.015, 0.092), region=1, skip=("back",))

    # 5. Cradle bracket, angled heavy handset & armored cord loop on left side
    hx = -0.068
    hy = face_y - 0.020
    # Cradle fork
    b.add_box(Vector((hx, face_y - 0.014, 1.240)), (0.044, 0.028, 0.046), region=1)
    # Handset handle bar + earpiece + mouthpiece
    b.add_box(Vector((hx, hy - 0.016, 1.150)), (0.030, 0.028, 0.195), region=1, rot=rx(-5.0))
    b.add_cyl(Vector((hx, hy - 0.002, 1.242)), 0.028, 0.036, region=1, segs=8, rot=rx(85.0))
    b.add_cyl(Vector((hx, hy - 0.018, 1.055)), 0.026, 0.034, region=1, segs=8, rot=rx(85.0))

    # Armored cord loop hanging down below handset back into box
    cord_pts = [
        Vector((hx, hy - 0.018, 1.035)),
        Vector((hx - 0.015, hy - 0.015, 0.890)),
        Vector((hx - 0.028, hy + 0.005, 0.785)),
        Vector((hx - 0.010, face_y - 0.006, 0.835)),
    ]
    cord_rings = []
    for pt in cord_pts:
        r = 0.007
        cord_rings.append([
            pt + Vector((-r, -r, 0.0)),
            pt + Vector((+r, -r, 0.0)),
            pt + Vector((+r, +r, 0.0)),
            pt + Vector((-r, +r, 0.0)),
        ])
    b.add_loft(cord_rings, region=1, caps=(True, True), smooth=False)


SPEC = PropSpec(
    slug="soviet_payphone",
    node_name="SovietPayphone",
    mat_name="M_SovietPayphone",
    ref_image=REF_IMAGE,
    target_h=1.55,
    tri_budget=1500,
    body="static",
    seed=1823,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="paint", rgb=(132, 132, 128), wear=0.45, rough=0.58, metal=0.28, nrm=0.8),
        Region(kind="paint", rgb=(44, 44, 46), wear=0.50, rough=0.52, metal=0.58, nrm=0.8),
        Region(kind="paint", rgb=(130, 130, 126), wear=0.35, rough=0.60, metal=0.25, nrm=0.5, decal=_hood_sign_decal),
        Region(kind="steel", rgb=(76, 78, 80), wear=0.40, rough=0.46, metal=0.68, nrm=0.6, decal=_coin_box_decal),
    ],
    build=_build,
    collision=[
        ("CollisionShape3D", (0.382, 1.55, 0.34), (0.0, 0.775, 0.0)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
