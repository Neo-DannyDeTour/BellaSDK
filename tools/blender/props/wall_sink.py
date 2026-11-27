"""Procedural wall-hung utility sink (0.42m H): porcelain basin, twin taps, gooseneck, P-trap.

Ref: /home/dkd/Downloads/hl2_refs/sink.png
Usage:
    python3 tools/blender/run.py tools/blender/props/wall_sink.py
Regions: 0 = glazed porcelain, 1 = stained basin interior, 2 = chrome, 3 = trap pipe.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import (  # noqa: E402
    Kit,
    arc_path,
    rrect,
    run_prop,
)

CFG: dict = {
    "slug": "wall_sink",
    "node_name": "WallSink",
    "mat_name": "M_WallSink",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/sink.png",
    "tri_budget": 1500,
    "body": "static",
    "seed": 11,
    "regions": [
        {"base": (204, 204, 194), "var": 0.06, "grime": 0.28, "rust": 0.04, "rough": 0.32,
         "normal": 1.4},
        {"base": (176, 172, 156), "var": 0.08, "grime": 0.58, "rust": 0.14, "rough": 0.36,
         "normal": 1.6},
        {"base": (182, 184, 186), "var": 0.08, "grime": 0.25, "rust": 0.08, "rough": 0.28,
         "metal": 0.92, "normal": 1.5},
        {"base": (98, 95, 88), "var": 0.12, "grime": 0.45, "rust": 0.32, "rough": 0.52,
         "metal": 0.78, "normal": 2.2},
    ],
}


def build(kit: Kit) -> None:
    """Build the sink geometry (Blender Z up, wall at +Y, front at -Y)."""
    z_rim = 0.27
    # Basin shell with wider rear tap deck (wall=+Y) matching sink.png.
    rings = [
        rrect(0.0, -0.025, 0.14, 0.34, 0.24, 0.055),
        rrect(0.0, -0.015, 0.23, 0.52, 0.38, 0.045),
        rrect(0.0, 0.000, z_rim, 0.55, 0.44, 0.035),
        rrect(0.0, -0.045, z_rim, 0.49, 0.295, 0.032),
        rrect(0.0, -0.045, 0.17, 0.32, 0.19, 0.045),
    ]
    kit.loft(rings, [0, 0, 0, 1])
    kit.box((0.0, 0.21, 0.315), (0.55, 0.022, 0.11), 0, bevel=0.008)  # chamfered backsplash
    kit.box((0.0, 0.155, z_rim + 0.004), (0.22, 0.055, 0.008), 2, bevel=0.002)  # tap deck
    kit.cyl((0.0, -0.045, 0.172), (0, 0, 1), 0.024, 0.006, 12, 2)  # drain strainer

    # Twin cross-head taps on rear deck.
    for sx in (-1.0, 1.0):
        x = sx * 0.085
        kit.cyl((x, 0.155, z_rim + 0.020), (0, 0, 1), 0.014, 0.030, 10, 2)
        kit.cyl((x, 0.155, z_rim + 0.040), (0, 0, 1), 0.007, 0.012, 8, 2)
        kit.box((x, 0.155, z_rim + 0.050), (0.052, 0.010, 0.010), 2)
        kit.box((x, 0.155, z_rim + 0.050), (0.010, 0.052, 0.010), 2)

    # Gooseneck spout curving out over the basin.
    path = [(0.0, 0.155, z_rim + 0.008)]
    path += arc_path((0.0, 0.095, 0.325), 0.060, 0.0, 180.0, 9, plane="yz")
    path += [(0.0, 0.035, 0.295)]
    kit.tube(path, 0.009, 8, 2)

    # P-trap: tailpipe, U-bend, riser, bend into wall (+Y=0.22).
    trap = [(0.0, -0.045, 0.15), (0.0, -0.045, 0.03)]
    trap += arc_path((0.0, 0.015, 0.03), 0.06, 180.0, 360.0, 9, plane="yz")[1:]
    trap += [(0.0, 0.075, 0.095)]
    trap += arc_path((0.0, 0.105, 0.095), 0.03, 180.0, 90.0, 5, plane="yz")[1:]
    trap += [(0.0, 0.215, 0.125)]
    kit.tube(trap, 0.011, 8, 3)
    kit.cyl((0.0, -0.045, 0.135), (0, 0, 1), 0.018, 0.016, 10, 3)  # slip nut
    kit.cyl((0.0, 0.215, 0.125), (0, 1, 0), 0.024, 0.008, 12, 3)  # wall flange


if __name__ == "__main__":
    run_prop(CFG, build)
