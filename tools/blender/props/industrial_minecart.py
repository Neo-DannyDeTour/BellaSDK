"""Procedural Heavy Riveted Steel Industrial Minecart (1.15m H x 1.55m L).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-10_19-28.png:
- 4 flanged rail wheels with spoked hubs on 2 steel axles & bearing pillow blocks (min_y = 0)
- Heavy steel undercarriage frame with end buffer beams & coupling blocks
- Hollow thick-walled V-tapered riveted steel hopper body with rolled top rim flange
- Vertical corner reinforcing straps with lifting lugs, end dump-latch bars & hex pivot plates
- 2048x2048 PBR atlas (riveted gunmetal hopper, rusted undercarriage iron, worn steel hardware)

Usage:
    /usr/bin/python3 tools/blender/props/industrial_minecart.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/industrial_minecart.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.street_prop import (  # noqa: E402
    Builder,
    PropSpec,
    Region,
    main,
    rx,
    ry,
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-10_19-28.png"
TARGET_H: float = 1.15


def _hopper_plate_decal(img, rng) -> None:
    """Paint subtle industrial quarry grime, horizontal weld seams & lower ore dust."""
    import numpy as np
    from PIL import Image, ImageDraw

    w, h = img.size
    draw = ImageDraw.Draw(img)
    # Subtle horizontal riveted seam lines across panel
    for y_frac in (0.28, 0.72):
        yy = int(h * y_frac)
        draw.line([(0, yy), (w, yy)], fill=(48, 50, 54), width=5)
        for rx_pos in range(28, w - 20, 56):
            draw.ellipse([rx_pos - 6, yy - 6, rx_pos + 6, yy + 6], fill=(104, 106, 112), outline=(36, 38, 40), width=2)

    arr = np.asarray(img, dtype=np.float32)
    yy_g, _ = np.mgrid[0:h, 0:w].astype(np.float32)
    yn = yy_g / float(h)
    # Lower hopper quarry dust & rust patina
    dust = np.clip((yn - 0.58) / 0.42, 0.0, 1.0) * 0.25
    dust_col = np.array([92.0, 80.0, 70.0], dtype=np.float32)
    arr = arr * (1.0 - dust[..., None]) + dust_col[None, None, :] * dust[..., None]
    img.paste(Image.fromarray(np.clip(arr, 30, 240).astype(np.uint8), mode="RGB"))


def _add_flanged_wheel(b: Builder, cx: float, cy: float, cz: float, side_sign: float) -> None:
    """Build 12-sided flanged cast-iron rail wheel with inner rail flange & spoked hub."""
    from mathutils import Vector

    # Main wheel tread (r = 0.155m, width = 0.068m along Y)
    b.add_cyl(Vector((cx, cy, cz)), 0.155, 0.068, region=2, segs=12, rot=rx(90.0))
    # Inner rail flange (r = 0.175m so bottom touches z=0.0, width = 0.018m on track-inside face)
    flange_y = cy - side_sign * 0.034
    b.add_cyl(Vector((cx, flange_y, cz)), 0.175, 0.018, region=2, segs=12, rot=rx(90.0))
    # Outer hub boss (r = 0.052m, width = 0.088m)
    b.add_cyl(Vector((cx, cy + side_sign * 0.008, cz)), 0.052, 0.084, region=1, segs=8, rot=rx(90.0))
    # Two crossed cast spoke bars on outer face
    spoke_y = cy + side_sign * 0.036
    b.add_box(Vector((cx, spoke_y, cz)), (0.25, 0.016, 0.028), region=1)
    b.add_box(Vector((cx, spoke_y, cz)), (0.028, 0.016, 0.25), region=1)


def _rect_ring(cx: float, cy: float, lx: float, wy: float, z: float) -> list:
    """CCW (from +Z) rectangular ring at height z."""
    from mathutils import Vector

    hx, hy = lx * 0.5, wy * 0.5
    return [
        Vector((cx - hx, cy - hy, z)),
        Vector((cx + hx, cy - hy, z)),
        Vector((cx + hx, cy + hy, z)),
        Vector((cx - hx, cy + hy, z)),
    ]


def _build_hopper_tub(b: Builder) -> None:
    """Build hollow thick-walled V-tapered steel hopper with rolled top rim flange."""
    # Outer profile from z=0.42m keel -> z=0.68m shoulder -> z=1.105m top -> z=1.15m rolled rim
    outer_rings = [
        _rect_ring(0.0, 0.0, 1.24, 0.40, 0.42),
        _rect_ring(0.0, 0.0, 1.50, 0.82, 0.68),
        _rect_ring(0.0, 0.0, 1.50, 0.82, 1.105),
        _rect_ring(0.0, 0.0, 1.55, 0.88, 1.105),
        _rect_ring(0.0, 0.0, 1.55, 0.88, TARGET_H),
    ]
    b.add_loft(outer_rings, region=0, caps=(True, False), smooth=False)

    # Inner cavity wall descending from rim top (z=1.15m) down to inner floor (z=0.46m)
    inner_rings = [
        _rect_ring(0.0, 0.0, 1.18, 0.34, 0.46),
        _rect_ring(0.0, 0.0, 1.44, 0.76, 0.69),
        _rect_ring(0.0, 0.0, 1.44, 0.76, TARGET_H),
    ]
    # Skin inner walls inward-facing (reverse winding so normals face cavity center)
    vr = [[b.bm.verts.new(p) for p in ring] for ring in inner_rings]
    for k in range(len(vr) - 1):
        for i in range(4):
            j = (i + 1) % 4
            b._face([vr[k][j], vr[k][i], vr[k + 1][i], vr[k + 1][j]], 1, False, None, None)
    # Inner floor cap (+Z facing)
    b._face([b.bm.verts.new(p) for p in inner_rings[0]], 1, False, None, None)

    # Top rim lip annular cap connecting outer_rings[-1] to inner_rings[-1]
    o_top = [b.bm.verts.new(p) for p in outer_rings[-1]]
    i_top = [b.bm.verts.new(p) for p in inner_rings[-1]]
    for i in range(4):
        j = (i + 1) % 4
        b._face([o_top[i], o_top[j], i_top[j], i_top[i]], 2, False, None, None)


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Weathered slate-gunmetal hopper steel + subtle rivet/seam decal
    # 1 = Heavy dark rusted undercarriage & cast-iron wheel hubs
    # 2 = Worn/oiled machined steel (wheel treads, flanges, straps, latch bar, hex bolts)

    # 1. 4 Flanged rail wheels on 2 axles (min_z = 0.0 at z_center - 0.175 = 0.0)
    wheel_z = 0.175
    axle_xs = (-0.42, 0.42)
    track_half_y = 0.31
    for ax in axle_xs:
        # Solid steel axle
        b.add_cyl(Vector((ax, 0.0, wheel_z)), 0.036, 0.76, region=1, segs=8, rot=rx(90.0))
        for sy in (-1.0, 1.0):
            _add_flanged_wheel(b, cx=ax, cy=sy * track_half_y, cz=wheel_z, side_sign=sy)
            # Axle bearing pillow block connecting axle to frame
            b.add_box(Vector((ax, sy * 0.22, 0.26)), (0.11, 0.09, 0.14), region=1)

    # 2. Heavy steel undercarriage chassis frame (z = 0.30 .. 0.42m)
    for sy in (-1.0, 1.0):
        b.add_box(Vector((0.0, sy * 0.22, 0.355)), (1.42, 0.075, 0.095), region=1)
    # Front/rear heavy buffer cross-beams & coupling blocks
    for sx in (-1.0, 1.0):
        b.add_box(Vector((sx * 0.65, 0.0, 0.355)), (0.11, 0.68, 0.10), region=1)
        b.add_box(Vector((sx * 0.73, 0.0, 0.355)), (0.09, 0.16, 0.09), region=2)
        b.add_cyl(Vector((sx * 0.74, 0.0, 0.385)), 0.016, 0.11, region=2, segs=6)
    # Rocker cradle cross-beams supporting hopper keel
    for ax in axle_xs:
        b.add_box(Vector((ax, 0.0, 0.385)), (0.09, 0.44, 0.075), region=1)

    # 3. Hollow V-tapered steel hopper tub (z = 0.42 .. 1.15m)
    _build_hopper_tub(b)

    # 4. Corner vertical reinforcing straps & lifting lugs (4 corners on +/-Y sides)
    for sx in (-0.59, 0.59):
        for sy in (-1.0, 1.0):
            # Vertical bolted strap plate on upper vertical wall
            b.add_box(Vector((sx, sy * 0.418, 0.89)), (0.075, 0.018, 0.36), region=2)
            # Lifting D-lug loop near top of strap
            b.add_box(Vector((sx, sy * 0.435, 0.99)), (0.032, 0.024, 0.075), region=2)
            # Top & bottom strap rivets
            for rz_pos in (0.74, 0.89, 1.04):
                b.add_cyl(Vector((sx, sy * 0.430, rz_pos)), 0.010, 0.010, region=2, segs=6, rot=rx(90.0))

    # 5. Front & rear vertical dump-latch bars, square pivot plates & hex nuts (+/-X ends)
    for sx in (-1.0, 1.0):
        end_x = sx * 0.764
        # Square backing plate & oversized hex pivot nut proud on end wall (z = 0.67m)
        b.add_box(Vector((sx * 0.742, 0.0, 0.67)), (0.026, 0.14, 0.14), region=2)
        b.add_cyl(Vector((sx * 0.768, 0.0, 0.67)), 0.036, 0.028, region=2, segs=6, rot=rx(0.0) @ ry(90.0))
        # Vertical latch bar running from top rim down to bottom catch hook
        b.add_box(Vector((end_x, 0.0, 0.85)), (0.024, 0.026, 0.58), region=2)
        b.add_box(Vector((sx * 0.71, 0.0, 0.54)), (0.11, 0.028, 0.024), region=2)
        b.add_box(Vector((end_x, 0.0, 1.13)), (0.04, 0.034, 0.045), region=2)


SPEC = PropSpec(
    slug="industrial_minecart",
    node_name="IndustrialMinecart",
    mat_name="M_IndustrialMinecart",
    ref_image=REF_IMAGE,
    target_h=TARGET_H,
    tri_budget=2000,
    body="static",
    seed=1928,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="steel", rgb=(80, 84, 92), wear=0.58, rough=0.56, metal=0.68, nrm=0.75, decal=_hopper_plate_decal),
        Region(kind="steel", rgb=(58, 52, 48), wear=0.68, rough=0.68, metal=0.64, nrm=0.90),
        Region(kind="steel", rgb=(108, 110, 116), wear=0.40, rough=0.42, metal=0.82, nrm=0.65),
    ],
    build=_build,
    collision=[
        ("CollisionShape3D", (1.55, 1.15, 0.88), (0.0, 0.575, 0.0)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
