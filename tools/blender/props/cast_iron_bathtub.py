"""Procedural cast-iron clawfoot bathtub (0.58m H, ~1.65m L): rolled rim, curved tub, cast feet.

Ref: /home/dkd/Downloads/hl2_refs/2026-11-04_03-46.png
Usage:
    python3 tools/blender/run.py tools/blender/props/cast_iron_bathtub.py
Regions: 0 = aged outer enamel, 1 = stained inner enamel, 2 = cast-iron feet, 3 = brass/chrome drain.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import (  # noqa: E402
    Kit,
    rrect,
    run_prop,
)

CFG: dict = {
    "slug": "cast_iron_bathtub",
    "node_name": "CastIronBathtub",
    "mat_name": "M_CastIronBathtub",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-11-04_03-46.png",
    "tri_budget": 1800,
    "body": "static",
    "seed": 37,
    "regions": [
        {"base": (196, 194, 182), "var": 0.08, "grime": 0.42, "rust": 0.16, "rough": 0.38,
         "normal": 1.6},
        {"base": (174, 170, 152), "var": 0.10, "grime": 0.65, "rust": 0.26, "rough": 0.36,
         "normal": 1.8},
        {"base": (64, 62, 58), "var": 0.12, "grime": 0.40, "rust": 0.25, "rough": 0.66,
         "metal": 0.86, "normal": 2.4},
        {"base": (138, 130, 114), "var": 0.10, "grime": 0.45, "rust": 0.20, "rough": 0.40,
         "metal": 0.84, "normal": 1.8},
    ],
}


def _add_foot(kit: Kit, sx: float, sy: float) -> None:
    """Add a splayed cast-iron claw/block foot grounded at z=0.0."""
    # Foot flares slightly outward toward floor and tucks into tub belly at z=0.145.
    x0, y0 = sx * 0.58, sy * 0.25
    x1, y1 = sx * 0.54, sy * 0.21
    rings = [
        rrect(x0, y0, 0.000, 0.095, 0.085, 0.022, n=3),
        rrect(x0, y0, 0.028, 0.082, 0.072, 0.018, n=3),
        rrect(x1, y1, 0.095, 0.072, 0.064, 0.016, n=3),
        rrect(x1 * 0.96, y1 * 0.94, 0.155, 0.092, 0.080, 0.018, n=3),
    ]
    kit.loft(rings, 2)


def build(kit: Kit) -> None:
    """Build cast-iron bathtub (1.65m L along X, 0.75m W along Y, 0.58m H along Z)."""
    # 1. Tub body + rolled rim + curved interior basin (11-ring closed solid, 24 pts/ring).
    # n=6 -> 24 points per ring; 10 strips * 24 * 2 = 480 tris + caps ~44 = ~524 tris.
    rings = [
        rrect(0.0, 0.0, 0.105, 1.38, 0.52, 0.16, n=6),  # outer bottom belly
        rrect(0.0, 0.0, 0.220, 1.48, 0.61, 0.17, n=6),  # outer lower curve
        rrect(0.0, 0.0, 0.420, 1.54, 0.66, 0.17, n=6),  # outer upper wall
        rrect(0.0, 0.0, 0.530, 1.57, 0.68, 0.17, n=6),  # under rolled rim neck
        rrect(0.0, 0.0, 0.548, 1.65, 0.75, 0.18, n=6),  # rolled rim outer edge (bottom)
        rrect(0.0, 0.0, 0.572, 1.65, 0.75, 0.18, n=6),  # rolled rim outer edge (top)
        rrect(0.0, 0.0, 0.580, 1.58, 0.69, 0.17, n=6),  # rolled rim crest (exact 0.58m H)
        rrect(0.0, 0.0, 0.562, 1.49, 0.61, 0.15, n=6),  # inner rim lip
        rrect(0.0, 0.0, 0.370, 1.42, 0.55, 0.14, n=6),  # inner wall mid
        rrect(0.0, 0.0, 0.200, 1.32, 0.48, 0.13, n=6),  # inner cove curve
        rrect(0.0, 0.0, 0.155, 1.18, 0.42, 0.11, n=6),  # inner tub floor
    ]
    kit.loft(rings, [0, 0, 0, 0, 0, 0, 1, 1, 1, 1])

    # 2. Four splayed cast-iron feet grounded at z=0.0.
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            _add_foot(kit, sx, sy)

    # 3. Drain strainer & overflow plate at drain end (-X) + underside drain pipe stub.
    kit.cyl((-0.50, 0.0, 0.158), (0, 0, 1), 0.036, 0.008, 12, 3)  # drain flange
    kit.cyl((-0.50, 0.0, 0.088), (0, 0, 1), 0.024, 0.040, 10, 2)  # underside drain outlet
    kit.cyl((-0.68, 0.0, 0.460), (1, 0, 0), 0.028, 0.014, 12, 3)  # overflow plate


if __name__ == "__main__":
    run_prop(CFG, build)
