"""Procedural Forged Rusted Iron Hanging Meat Hook (0.55m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-05_19-30_2.png:
- Grounded at min_y = 0 (bottom of the J-hook curve), height 0.55m
- Forged S-curve octagonal shank transitioning into a heavy curved hook bowl + sharp tip
- Forged upper mounting eye with bolted steel U-bracket clevis at top
- RigidBody3D (collision_layer = 4, collision_mask = 7, BoxShape3D)
- 2048x2048 PBR atlas (forged dark iron, pitted rust crust, worn bright edge steel, bracket iron)

Usage:
    /usr/bin/python3 tools/blender/props/hanging_meat_hook.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/hanging_meat_hook.py
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
    "slug": "hanging_meat_hook",
    "node_name": "HangingMeatHook",
    "mat_name": "M_HangingMeatHook",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-11-05_19-30_2.png",
    "tri_budget": 900,
    "body": "rigid",
    "mass": 4.5,
    "seed": 51930,
    "regions": [
        # 0: Forged dark rusted iron shank & hook body
        {"base": (68, 52, 44), "var": 0.16, "grime": 0.42, "rust": 0.52, "rough": 0.64,
         "metal": 0.72, "normal": 2.8},
        # 1: Heavier flaky orange-brown rust crust in recesses
        {"base": (88, 54, 38), "var": 0.18, "grime": 0.40, "rust": 0.72, "rough": 0.78,
         "metal": 0.42, "normal": 3.2},
        # 2: Worn bare iron tip & inside hook curve
        {"base": (118, 114, 110), "var": 0.10, "grime": 0.25, "rust": 0.20, "rough": 0.38,
         "metal": 0.88, "normal": 2.0},
        # 3: Mounting U-bracket & pivot bolt
        {"base": (52, 48, 46), "var": 0.12, "grime": 0.36, "rust": 0.38, "rough": 0.60,
         "metal": 0.78, "normal": 2.4},
    ],
}


def _paint_hook(idx: int, maps: dict, half: int) -> None:
    """Add hand-forged hammer facet marks on iron surfaces."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(51930 + idx * 29)
    hammer_grid = rng.random((48, 48)).astype(np.float32)
    hammer = np.asarray(
        Image.fromarray(hammer_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
        dtype=np.float32,
    )
    maps["alb"] = np.clip(maps["alb"] * (0.86 + 0.26 * hammer[..., None]), 30.0, 225.0)
    gy, gx = np.gradient(hammer)
    nrm = np.stack([-gx * 2.4, gy * 2.4, np.ones_like(hammer)], axis=-1)
    nrm /= np.sqrt(np.sum(nrm * nrm, axis=-1, keepdims=True))
    maps["nrm"] = nrm


def _build_hook(kit: Kit) -> None:
    """Build grounded 0.55m forged hanging meat hook (+Z up, profile in YZ plane)."""
    # 1. Main forged S-curve shank -> heavy J-hook bowl -> sharpened tip
    # Swept in YZ plane so bottom of hook sits at z = 0.000m (exact grounded height)
    # Path points (x, y, z) and forged octagonal radius at each station:
    stations = [
        ((0.0, 0.008, 0.470), 0.019),   # just below mounting eye
        ((0.0, 0.004, 0.420), 0.015),   # forged neck waist
        ((0.0, -0.010, 0.345), 0.014),  # upper S-bend forward
        ((0.0, -0.022, 0.265), 0.015),  # mid shank
        ((0.0, -0.032, 0.195), 0.017),  # lower elbow bend backward
        ((0.0, -0.048, 0.130), 0.020),  # heavy forged heel
        ((0.0, -0.042, 0.068), 0.021),  # descending curve
        ((0.0, -0.014, 0.026), 0.020),  # bottom-back curve
        ((0.0, +0.022, 0.016), 0.016),  # exact bottom belly (min z ~ 0.0)
        ((0.0, +0.062, 0.028), 0.015),  # ascending front curve
        ((0.0, +0.092, 0.062), 0.014),  # front throat
        ((0.0, +0.106, 0.108), 0.012),  # tapering hook tip base
        ((0.0, +0.104, 0.152), 0.008),  # taper
        ((0.0, +0.096, 0.184), 0.003),  # sharp forged point
    ]
    pts = [p for p, _ in stations]
    rads = [r for _, r in stations]
    kit.tube(pts, radius=rads, segs=8, region=0, cap=True)

    # 2. Forged mounting eye loop at top of shank (z = 0.465 .. 0.530m)
    # Built as a closed ring loop around horizontal X axis at (0, 0.008, 0.495)
    eye_pts = []
    eye_r = 0.024
    for k in range(13):
        ang = math.radians(270.0 + 360.0 * k / 12.0)
        eye_pts.append((0.0, 0.008 + eye_r * math.cos(ang), 0.495 + eye_r * math.sin(ang)))
    kit.tube(eye_pts, radius=0.010, segs=6, region=1, cap=True)

    # 3. Overhead U-clevis mounting bracket & bolt pin (reaches z = 0.550m)
    # Two vertical bracket straps flanking the mounting eye (±X) + top beam plate + cross bolt
    kit.box((-0.022, 0.008, 0.515), (0.010, 0.036, 0.062), region=3, bevel=0.002)
    kit.box((+0.022, 0.008, 0.515), (0.010, 0.036, 0.062), region=3, bevel=0.002)
    kit.box((0.0, 0.008, 0.545), (0.054, 0.038, 0.010), region=3, bevel=0.002)
    # Cross pivot bolt through mounting eye
    kit.cyl((0.0, 0.008, 0.495), (1.0, 0.0, 0.0), 0.009, 0.064, segs=8, region=2)


def main() -> None:
    run_prop(CFG, _build_hook, painter=_paint_hook)


if __name__ == "__main__":
    main()
