"""Procedural Post-Soviet Industrial Drink/Snack Vending Machine (1.85m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-22_1.png:
- Heavy rectangular dark painted steel cabinet grounded at min_y = 0
- Gently curved weathered slate-blue front graphic door panel with water-ripple motif + dispenser chute
- Recessed right-side vertical column with instruction placard, bill/coin acceptor, and 8 selection buttons
- Louvered side cooling vents + rear service panel for clean 360-degree turntable readability
- 2048x2048 PBR atlas (charcoal cabinet steel, slate-blue front graphic, selection panel decal, hardware)

Usage:
    /usr/bin/python3 tools/blender/props/soviet_vending_machine.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/soviet_vending_machine.py
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
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-22_1.png"

CAB_W: float = 1.02
CAB_H: float = 1.85
CAB_D: float = 0.78


def _front_graphic_decal(img, rng) -> None:
    """Paint weathered slate-blue industrial beverage graphic with water-ripple rings & faded stencil."""
    import numpy as np
    from PIL import Image, ImageDraw

    w, h = img.size
    arr = np.asarray(img, dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    yn = yy / float(h)
    xn = xx / float(w)

    # Subtle radial water-ripple highlight around lower-middle (yn ~ 0.62, xn ~ 0.48)
    dist = np.sqrt(((xn - 0.48) * 1.1) ** 2 + (yn - 0.62) ** 2)
    ring1 = np.exp(-((dist - 0.14) / 0.025) ** 2) * 32.0
    ring2 = np.exp(-((dist - 0.25) / 0.032) ** 2) * 20.0
    ring3 = np.exp(-((dist - 0.36) / 0.040) ** 2) * 12.0
    vignette = 1.0 - 0.28 * np.clip(((xn - 0.5) ** 2 + (yn - 0.5) ** 2) * 2.2, 0.0, 1.0)
    # Vertical condensation/grime streaks near bottom
    bot_grime = np.clip((yn - 0.76) / 0.24, 0.0, 1.0) * 0.30

    arr = arr * vignette[..., None] * (1.0 - bot_grime[..., None])
    ripple = (ring1 + ring2 + ring3)[..., None]
    arr[..., 0] += ripple[..., 0] * 0.70
    arr[..., 1] += ripple[..., 0] * 0.90
    arr[..., 2] += ripple[..., 0] * 1.10

    panel_img = Image.fromarray(np.clip(arr, 30, 240).astype(np.uint8), mode="RGB")
    draw = ImageDraw.Draw(panel_img)
    f_big = font(FONT_COND, 62)
    f_sub = font(FONT_COND, 38)
    # Faded industrial stencil lettering on upper left matching ref layout
    draw.text((78, 128), "CITY RESERVE", font=f_big, fill=(104, 124, 140))
    draw.text((78, 198), "PURIFIED WATER", font=f_sub, fill=(92, 112, 128))
    draw.text((78, 248), "DISPENSER  NO. 04", font=f_sub, fill=(84, 102, 118))

    # Dark frame border around dispenser cutout zone (matching chute position)
    cx0, cy0, cx1, cy1 = int(w * 0.30), int(h * 0.72), int(w * 0.70), int(h * 0.87)
    draw.rectangle([cx0, cy0, cx1, cy1], fill=(24, 26, 28), outline=(74, 82, 90), width=6)

    img.paste(panel_img)


def _control_column_decal(img, rng) -> None:
    """Paint right-hand vertical vending selection & payment column decal."""
    from PIL import ImageDraw

    draw = ImageDraw.Draw(img)
    w, h = img.size
    # Dark anodized column face
    draw.rectangle([0, 0, w, h], fill=(32, 34, 36))
    draw.rectangle([12, 12, w - 12, h - 12], outline=(58, 60, 62), width=6)

    # Top warning / instruction placard (y: 36..190)
    draw.rectangle([48, 36, w - 48, 195], fill=(146, 138, 120), outline=(44, 42, 38), width=5)
    f_lbl = font(FONT_BOLD, 34)
    draw.text((84, 62), "COLD DRINKS", font=f_lbl, fill=(40, 36, 32))
    draw.text((84, 112), "EXACT COIN ONLY", font=f_lbl, fill=(116, 46, 36))

    # Coin / bill acceptor bay (y: 250..420)
    draw.rectangle([62, 255, w - 62, 425], fill=(92, 94, 96), outline=(24, 24, 26), width=6)
    draw.rectangle([110, 290, 240, 325], fill=(22, 22, 24))
    draw.rectangle([w - 220, 280, w - 96, 390], fill=(42, 44, 46), outline=(124, 126, 128), width=4)

    # 8 selection button rows + subtle indicator dots (y: 465..845)
    for i in range(8):
        by0 = 468 + i * 46
        by1 = by0 + 34
        # Selection button label bar
        draw.rectangle([68, by0, w - 148, by1], fill=(122, 126, 128), outline=(22, 22, 24), width=4)
        # Status indicator lens (muted red/amber/one green active, matching ref)
        dot_col = (58, 128, 68) if i == 3 else (138, 52, 44)
        draw.ellipse([w - 118, by0 + 4, w - 88, by1 - 4], fill=dot_col, outline=(24, 24, 24), width=3)

    # Lower coin return slot (y: 880..970)
    draw.rectangle([90, 882, w - 90, 968], fill=(64, 66, 68), outline=(24, 24, 26), width=5)
    draw.rectangle([120, 902, w - 120, 948], fill=(22, 22, 24))


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Heavy charcoal-gray painted steel cabinet body, side louvers & trim
    # 1 = Curved weathered slate-blue front graphic door panel
    # 2 = Right-side selection & payment column decal
    # 3 = Dark gunmetal recessed dispenser interior & hardware

    # 1. Grounded recessed base plinth (min_z = 0.0)
    plinth_h = 0.042
    b.add_box(Vector((0.0, 0.012, plinth_h * 0.5)), (CAB_W - 0.04, CAB_D - 0.05, plinth_h), region=3)

    # 2. Main steel cabinet carcass (z = 0.042..1.850)
    body_h = CAB_H - plinth_h
    body_cz = plinth_h + body_h * 0.5
    b.add_box(Vector((0.0, 0.02, body_cz)), (CAB_W, CAB_D - 0.04, body_h), region=0)

    # 3. Gently curved front graphic door (x = -0.495..+0.255, z = 0.048..1.825)
    # 4 vertical columns curving outward at center (-Y) by 2.2cm
    fx0, fx1 = -0.495, 0.255
    fz0, fz1 = 0.048, 1.825
    front_y = -(CAB_D * 0.5 - 0.02)
    xs_f = [fx0 + (fx1 - fx0) * t for t in (0.0, 0.28, 0.50, 0.72, 1.0)]
    bow = [0.0, 0.016, 0.022, 0.016, 0.0]
    f_bot = [b.bm.verts.new(Vector((x, front_y - dy, fz0))) for x, dy in zip(xs_f, bow)]
    f_top = [b.bm.verts.new(Vector((x, front_y - dy, fz1))) for x, dy in zip(xs_f, bow)]
    b_bot = [b.bm.verts.new(Vector((x, front_y + 0.026, fz0))) for x in xs_f]
    b_top = [b.bm.verts.new(Vector((x, front_y + 0.026, fz1))) for x in xs_f]

    for i in range(4):
        u0 = i / 4.0
        u1 = (i + 1) / 4.0
        # Front curved graphic face
        ff = b.bm.faces.new([f_bot[i], f_bot[i + 1], f_top[i + 1], f_top[i]])
        ff.smooth = True
        for lp, uv in zip(ff.loops, [(u0, 0.01), (u1, 0.01), (u1, 0.99), (u0, 0.99)]):
            lp[b.uv].uv = b.tile_uv(1, *uv)
        # Top/bottom cap strip
        tf = b.bm.faces.new([f_top[i], f_top[i + 1], b_top[i + 1], b_top[i]])
        bf = b.bm.faces.new([b_bot[i], b_bot[i + 1], f_bot[i + 1], f_bot[i]])
        for sf in (tf, bf):
            sf.smooth = False
            for k, lp in enumerate(sf.loops):
                lp[b.uv].uv = b.tile_uv(0, 0.1 + 0.2 * (k % 2), 0.1 + 0.2 * (k // 2))

    # Left/right edge caps of curved door
    for v_pair in ((b_bot[0], f_bot[0], f_top[0], b_top[0]), (f_bot[-1], b_bot[-1], b_top[-1], f_top[-1])):
        ef = b.bm.faces.new(list(v_pair))
        ef.smooth = False
        for k, lp in enumerate(ef.loops):
            lp[b.uv].uv = b.tile_uv(0, 0.1 + 0.2 * (k % 2), 0.1 + 0.2 * (k // 2))

    # 4. Recessed dispenser chute frame & push flap on front graphic panel (x = -0.12, z = 0.36)
    ch_x, ch_z = -0.12, 0.375
    ch_w, ch_h = 0.275, 0.190
    ch_y = front_y - 0.024
    # Frame bezel (top, bottom, left, right)
    b.add_box(Vector((ch_x, ch_y, ch_z + ch_h * 0.5)), (ch_w, 0.022, 0.020), region=3)
    b.add_box(Vector((ch_x, ch_y, ch_z - ch_h * 0.5)), (ch_w, 0.022, 0.020), region=3)
    b.add_box(Vector((ch_x - ch_w * 0.5 + 0.010, ch_y, ch_z)), (0.020, 0.022, ch_h - 0.020), region=3)
    b.add_box(Vector((ch_x + ch_w * 0.5 - 0.010, ch_y, ch_z)), (0.020, 0.022, ch_h - 0.020), region=3)
    # Inner hinged push flap
    b.add_box(Vector((ch_x, ch_y + 0.008, ch_z + 0.012)), (ch_w - 0.044, 0.010, ch_h - 0.048), region=0)

    # 5. Right-side selection & payment column (x = +0.265..+0.495, z = 0.048..1.825)
    col_cx = 0.380
    col_w = 0.228
    b.add_box(Vector((col_cx, front_y + 0.004, (fz0 + fz1) * 0.5)), (col_w, 0.022, fz1 - fz0), region=3, skip=("front",))
    b.add_plate(
        Vector((col_cx, front_y - 0.008, (fz0 + fz1) * 0.5)),
        (col_w, 0.004, fz1 - fz0),
        region=2,
        uv_rect=(0.01, 0.01, 0.99, 0.99),
    )
    # 3D raised payment bezel & 8 selection button bars aligned to decal (leaving LED dots visible)
    b.add_box(Vector((col_cx, front_y - 0.012, 1.24)), (col_w - 0.042, 0.012, 0.24), region=3, skip=("back",))
    col_h = fz1 - fz0
    for i in range(8):
        v_frac = 1.0 - (485.0 + i * 46.0) / 1024.0
        bz = fz0 + v_frac * col_h
        b.add_box(Vector((col_cx - 0.028, front_y - 0.011, bz)), (0.098, 0.010, 0.026), region=3, skip=("back",))

    # 6. Side ventilation louvers (left & right sides) + rear service panel for 360-deg detail
    for sx in (-1.0, 1.0):
        lx = sx * (CAB_W * 0.5 + 0.003)
        b.add_box(Vector((lx, 0.14, 0.36)), (0.008, 0.30, 0.36), region=0)
        for vi in range(5):
            vz = 0.24 + vi * 0.06
            b.add_box(Vector((lx + sx * 0.003, 0.14, vz)), (0.008, 0.24, 0.022), region=3)

    # Rear compressor recess + vertical service door frame (+Y)
    back_y = CAB_D * 0.5 - 0.002
    b.add_box(Vector((0.0, back_y + 0.004, 0.95)), (0.82, 0.012, 1.48), region=3)
    b.add_box(Vector((0.0, back_y + 0.006, 0.28)), (0.64, 0.016, 0.28), region=0)


SPEC = PropSpec(
    slug="soviet_vending_machine",
    node_name="SovietVendingMachine",
    mat_name="M_SovietVendingMachine",
    ref_image=REF_IMAGE,
    target_h=1.85,
    tri_budget=1600,
    body="static",
    seed=1822,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="paint", rgb=(70, 72, 70), wear=0.45, rough=0.58, metal=0.42, nrm=0.85),
        Region(kind="paint", rgb=(74, 102, 126), wear=0.30, rough=0.46, metal=0.22, nrm=0.45, decal=_front_graphic_decal),
        Region(kind="paint", rgb=(48, 50, 52), wear=0.30, rough=0.50, metal=0.40, nrm=0.45, decal=_control_column_decal),
        Region(kind="steel", rgb=(52, 54, 56), wear=0.40, rough=0.52, metal=0.68, nrm=0.75),
    ],
    build=_build,
    collision=[
        ("CollisionShape3D", (1.042, 1.85, 0.807), (0.0, 0.925, 0.0)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
