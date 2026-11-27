"""Procedural Soviet pedestal toilet (0.78m H): porcelain bowl, rear cistern, bakelite seat.

Ref: /home/dkd/Downloads/hl2_refs/2026-11-04_03-46.png
Usage:
    python3 tools/blender/run.py tools/blender/props/soviet_toilet.py
Regions: 0 = aged glazed porcelain, 1 = stained bowl interior, 2 = bakelite/wood seat, 3 = metal.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import (  # noqa: E402
    Kit,
    ellipse,
    rrect,
    run_prop,
)

CFG: dict = {
    "slug": "soviet_toilet",
    "node_name": "SovietToilet",
    "mat_name": "M_SovietToilet",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-11-04_03-46.png",
    "tri_budget": 1600,
    "body": "static",
    "seed": 23,
    "regions": [
        {"base": (206, 205, 196), "var": 0.06, "grime": 0.24, "rust": 0.04, "rough": 0.30,
         "normal": 1.4},
        {"base": (168, 162, 144), "var": 0.08, "grime": 0.58, "rust": 0.18, "rough": 0.34,
         "normal": 1.6},
        {"base": (88, 52, 34), "var": 0.10, "grime": 0.25, "rust": 0.0, "rough": 0.38,
         "normal": 1.6},
        {"base": (172, 174, 176), "var": 0.08, "grime": 0.30, "rust": 0.15, "rough": 0.32,
         "metal": 0.90, "normal": 1.5},
    ],
}


def build(kit: Kit) -> None:
    """Build Soviet pedestal toilet (Blender Z up, min_z=0, front=-Y, rear=+Y)."""
    # 1. Pedestal + sculpted oval bowl (20-segment closed loft, single shell).
    bowl_rings = [
        ellipse(0.0, 0.03, 0.000, 0.26, 0.36, n=20, power=2.5),  # floor base
        ellipse(0.0, 0.03, 0.025, 0.24, 0.34, n=20, power=2.4),  # plinth lip
        ellipse(0.0, 0.03, 0.145, 0.19, 0.27, n=20, power=2.2),  # pedestal waist
        ellipse(0.0, 0.00, 0.255, 0.28, 0.38, n=20, power=2.1),  # under-bowl flare
        ellipse(0.0, -0.025, 0.340, 0.36, 0.47, n=20, power=2.1),  # outer bowl belly
        ellipse(0.0, -0.025, 0.390, 0.38, 0.49, n=20, power=2.1),  # outer rim
        ellipse(0.0, -0.045, 0.390, 0.295, 0.37, n=20, power=2.0),  # inner rim
        ellipse(0.0, -0.045, 0.270, 0.205, 0.26, n=20, power=2.0),  # inner bowl slope
        ellipse(0.0, -0.035, 0.175, 0.105, 0.125, n=20, power=2.0),  # trap sump
    ]
    kit.loft(bowl_rings, [0, 0, 0, 0, 0, 0, 1, 1])

    # 2. Rear cistern shelf (behind inner bowl wall y>=+0.145) + tank + beveled lid + flush button.
    kit.box((0.0, 0.215, 0.370), (0.31, 0.135, 0.065), 0, bevel=0.008)  # rear porcelain shelf
    kit.cyl((0.0, 0.205, 0.405), (0, 0, 1), 0.026, 0.045, 10, 0)  # tank-to-bowl neck

    # Cistern body (tapered subtly wider at top for classic Soviet ceramic profile).
    tank_rings = [
        rrect(0.0, 0.205, 0.415, 0.365, 0.165, 0.022, n=3),
        rrect(0.0, 0.205, 0.742, 0.382, 0.175, 0.022, n=3),
    ]
    kit.loft(tank_rings, 0)
    # Overhanging chamfered lid.
    lid_rings = [
        rrect(0.0, 0.205, 0.742, 0.400, 0.192, 0.022, n=3),
        rrect(0.0, 0.205, 0.764, 0.400, 0.192, 0.022, n=3),
        rrect(0.0, 0.205, 0.772, 0.380, 0.174, 0.020, n=3),
    ]
    kit.loft(lid_rings, 0)

    # Chrome flush button on lid top (reaches exact 0.780m).
    kit.cyl((0.0, 0.205, 0.774), (0, 0, 1), 0.024, 0.006, 12, 3)
    kit.cyl((0.0, 0.205, 0.777), (0, 0, 1), 0.014, 0.006, 12, 3)

    # Side water supply valve & stub pipe on left side of cistern.
    kit.cyl((-0.192, 0.205, 0.455), (1, 0, 0), 0.012, 0.020, 8, 3)
    kit.cyl((-0.198, 0.205, 0.425), (0, 0, 1), 0.008, 0.070, 8, 3)

    # 3. Hinged bakelite/wooden oval seat ring (hollow closed torus loft) + metal hinge lugs.
    o_bot = ellipse(0.0, -0.040, 0.391, 0.365, 0.425, n=20, power=2.0)
    o_top = ellipse(0.0, -0.040, 0.413, 0.360, 0.420, n=20, power=2.0)
    i_top = ellipse(0.0, -0.040, 0.413, 0.235, 0.295, n=20, power=2.0)
    i_bot = ellipse(0.0, -0.040, 0.391, 0.240, 0.300, n=20, power=2.0)
    kit.loft([o_bot, o_top, i_top, i_bot, o_bot], 2, cap_start=False, cap_end=False)

    # Rear hinge bracket bar & lugs connecting seat to porcelain shelf.
    for sx in (-0.075, 0.075):
        kit.box((sx, 0.135, 0.400), (0.026, 0.042, 0.018), 3, bevel=0.002)
        kit.cyl((sx, 0.145, 0.392), (0, 0, 1), 0.009, 0.016, 8, 3)


if __name__ == "__main__":
    run_prop(CFG, build)
