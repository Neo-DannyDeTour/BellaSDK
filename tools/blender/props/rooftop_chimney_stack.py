"""Procedural Galvanized/Rusted Sheet-Metal Rooftop Chimney Stack (2.60m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-36.png
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-36_1.png

Features:
- Square sheet-metal roof flashing base plate (min_y = 0) with 4 corner bolts & tapered boot
- Tall galvanized/rusted cylindrical flue stack with mid-height lap seam & clamp rings
- Wider upper sleeve collar + recessed dark soot-stained flue throat opening
- 4 vertical support straps holding a wide conical sheet-metal rain cap cowl
- 2048x2048 PBR atlas (weathered galvanized steel, oxidized cap metal, rusted clamps, soot interior)

Usage:
    /usr/bin/python3 tools/blender/props/rooftop_chimney_stack.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/rooftop_chimney_stack.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import Kit, run_prop  # noqa: E402

CFG: dict = {
    "slug": "rooftop_chimney_stack",
    "node_name": "RooftopChimneyStack",
    "mat_name": "M_RooftopChimneyStack",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-30_18-36.png",
    "tri_budget": 1200,
    "body": "static",
    "seed": 18360,
    "regions": [
        # 0: Weathered galvanized sheet-metal flue stack & flashing
        {"base": (138, 140, 132), "var": 0.12, "grime": 0.36, "rust": 0.28, "rough": 0.54,
         "metal": 0.76, "normal": 2.0},
        # 1: Oxidized/weathered conical rain cap cowl & upper shroud collar
        {"base": (108, 106, 98), "var": 0.12, "grime": 0.42, "rust": 0.42, "rough": 0.60,
         "metal": 0.72, "normal": 2.2},
        # 2: Heavy rusted steel clamp rings, bolts & cap support straps
        {"base": (82, 66, 56), "var": 0.12, "grime": 0.36, "rust": 0.60, "rough": 0.66,
         "metal": 0.68, "normal": 2.2},
        # 3: Dark soot-stained interior flue throat
        {"base": (38, 36, 36), "var": 0.08, "grime": 0.65, "rust": 0.10, "rough": 0.92,
         "metal": 0.10, "normal": 2.0},
    ],
}


def _paint_chimney(idx: int, maps: dict, half: int) -> None:
    """Add vertical soot/rain drip streaks on sheet metal (0, 1)."""
    import numpy as np

    if idx in (0, 1):
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        drip = 0.5 + 0.5 * np.sin((xx / float(half)) * 36.0 * math.pi)
        maps["alb"] = np.clip(maps["alb"] * (0.93 + 0.10 * drip[..., None]), 32.0, 235.0)
        maps["rough"] = np.clip(maps["rough"] + 0.06 * (1.0 - drip), 0.38, 0.88)


def _circle_ring(z: float, r: float, segs: int) -> list[tuple[float, float, float]]:
    return [
        (r * math.cos(2.0 * math.pi * k / segs), r * math.sin(2.0 * math.pi * k / segs), z)
        for k in range(segs)
    ]


def build(kit: Kit) -> None:
    """Build 2.60m rooftop sheet-metal chimney stack with conical rain cap (min_z=0)."""
    segs = 14

    # 1. Grounded square roof flashing base plate (min_z = 0.0) + 4 corner bolts
    kit.box((0.0, 0.0, 0.011), (0.54, 0.54, 0.022), 0, bevel=0.004)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.cyl((sx * 0.225, sy * 0.225, 0.028), (0.0, 0.0, 1.0), 0.014, 0.014, 6, 2)

    # Tapered flashing boot collar (z = 0.022 -> 0.16m)
    boot_rings = [
        _circle_ring(0.022, 0.215, segs),
        _circle_ring(0.145, 0.168, segs),
    ]
    kit.loft(boot_rings, 0, cap_start=False, cap_end=False)

    # Lower clamp ring collar at z = 0.16m
    kit.cyl((0.0, 0.0, 0.160), (0.0, 0.0, 1.0), 0.175, 0.042, segs, 2)

    # 2. Main cylindrical sheet-metal flue pipe (z = 0.145 -> 1.88m)
    lower_pipe = [
        _circle_ring(0.145, 0.156, segs),
        _circle_ring(1.120, 0.156, segs),
        _circle_ring(1.125, 0.161, segs),
        _circle_ring(1.880, 0.158, segs),
    ]
    kit.loft(lower_pipe, 0, cap_start=False, cap_end=False)

    # Mid-height clamp ring band + tensioning ear at z = 1.12m
    kit.cyl((0.0, 0.0, 1.120), (0.0, 0.0, 1.0), 0.170, 0.036, segs, 2)
    kit.box((0.172, 0.0, 1.120), (0.026, 0.032, 0.030), 2)

    # 3. Wider upper cylindrical shroud/sleeve (z = 1.88 -> 2.34m) + hollow soot throat
    upper_shroud = [
        _circle_ring(1.880, 0.174, segs),
        _circle_ring(2.335, 0.174, segs),
        _circle_ring(2.340, 0.154, segs),  # rolled top rim lip
        _circle_ring(2.050, 0.152, segs),  # recessed soot-stained flue bore
    ]
    kit.loft(upper_shroud, [1, 1, 3], cap_start=True, cap_end=True)

    # Upper clamp bands around shroud
    kit.cyl((0.0, 0.0, 1.900), (0.0, 0.0, 1.0), 0.181, 0.034, segs, 2)
    kit.cyl((0.0, 0.0, 2.295), (0.0, 0.0, 1.0), 0.181, 0.030, segs, 2)

    # 4. 4 vertical/angled steel support straps holding the conical rain cap
    for k in range(4):
        ang = math.radians(45.0 + k * 90.0)
        ca, sa = math.cos(ang), math.sin(ang)
        p_bot = (ca * 0.174, sa * 0.174, 2.260)
        p_top = (ca * 0.215, sa * 0.215, 2.475)
        # Build flat strap via 2-ring tube or narrow box
        kit.tube([p_bot, p_top], radius=0.012, segs=4, region=2, cap=True)

    # 5. Conical sheet-metal rain cap cowl (z = 2.460 -> 2.600m)
    cap_rings = [
        _circle_ring(2.475, 0.020, segs),  # underside center
        _circle_ring(2.460, 0.275, segs),  # outer eaves rim
        _circle_ring(2.472, 0.275, segs),  # rim thickness
        _circle_ring(2.585, 0.028, segs),  # conical slope top
        _circle_ring(2.600, 0.012, segs),  # top apex finial tip
    ]
    kit.loft(cap_rings, [3, 1, 1, 2], cap_start=True, cap_end=True)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_chimney)
