"""Procedural Heavy Cast-Iron Wood Stove (0.92m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-29_18-24.png:
- 4 splayed stubby cast-iron feet grounded at min_y = 0
- Stepped base apron, riveted cast-iron firebox box, overhanging top stove plate + twin side wire handles
- Front arched/domed firebox door with hinges & latch bar + lower slotted ash draft vent
- Top stepped flue collar + vertical cast-iron stovepipe neck rising to 0.92m
- 2048x2048 PBR atlas (sooty cast iron, heat-rusted top plate, matte ash/soot recess, worn steel hardware)

Usage:
    /usr/bin/python3 tools/blender/props/cast_iron_wood_stove.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/cast_iron_wood_stove.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import Kit, rrect, run_prop  # noqa: E402

CFG: dict = {
    "slug": "cast_iron_wood_stove",
    "node_name": "CastIronWoodStove",
    "mat_name": "M_CastIronWoodStove",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-29_18-24.png",
    "tri_budget": 1600,
    "body": "static",
    "seed": 29182,
    "regions": [
        # 0: Sooty dark charcoal cast iron body & legs
        {"base": (44, 43, 44), "var": 0.14, "grime": 0.45, "rust": 0.22, "rough": 0.70,
         "metal": 0.74, "normal": 2.8},
        # 1: Heat-oxidized rusted cast iron top plate & flue collar
        {"base": (56, 48, 44), "var": 0.16, "grime": 0.40, "rust": 0.54, "rough": 0.76,
         "metal": 0.65, "normal": 3.0},
        # 2: Matte soot interior / ash draft vent louvers
        {"base": (32, 31, 31), "var": 0.10, "grime": 0.60, "rust": 0.10, "rough": 0.90,
         "metal": 0.15, "normal": 2.2},
        # 3: Worn bare/oily steel door latch, hinges, side wire handles & damper
        {"base": (104, 98, 92), "var": 0.10, "grime": 0.30, "rust": 0.24, "rough": 0.46,
         "metal": 0.85, "normal": 2.0},
    ],
}


def _paint_stove(idx: int, maps: dict, half: int) -> None:
    """Add pebbled cast-iron grain on body/top (0, 1) and horizontal vent slits on ash vent (2)."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(29182 + idx * 37)
    if idx in (0, 1):
        # Fine cast-iron sand-casting dimple bump
        grain_grid = rng.random((180, 180)).astype(np.float32)
        pebble = np.asarray(
            Image.fromarray(grain_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        maps["alb"] = np.clip(maps["alb"] * (0.88 + 0.22 * pebble[..., None]), 30.0, 220.0)
        gy, gx = np.gradient(pebble)
        k = 2.6 if idx == 0 else 3.0
        nrm = np.stack([-gx * k, gy * k, np.ones_like(pebble)], axis=-1)
        nrm /= np.sqrt(np.sum(nrm * nrm, axis=-1, keepdims=True))
        maps["nrm"] = nrm
    elif idx == 2:
        yy, _ = np.mgrid[0:half, 0:half].astype(np.float32)
        slats = 0.5 + 0.5 * np.sin((yy / float(half)) * 22.0 * math.pi)
        maps["alb"] = np.clip(maps["alb"] * (0.72 + 0.38 * slats[..., None]), 30.0, 180.0)
        gy, gx = np.gradient(slats)
        nrm = np.stack([-gx * 2.5, gy * 2.5, np.ones_like(slats)], axis=-1)
        nrm /= np.sqrt(np.sum(nrm * nrm, axis=-1, keepdims=True))
        maps["nrm"] = nrm


def _build_stove(kit: Kit) -> None:
    """Build grounded 0.92m cast-iron wood stove (+Z up, -Y front)."""
    # 1. Four splayed stubby cast-iron feet (z = 0.0 .. 0.128m)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            fx_bot, fy_bot = sx * 0.265, sy * 0.225
            fx_top, fy_top = sx * 0.225, sy * 0.190
            leg_rings = [
                rrect(fx_bot, fy_bot, 0.000, 0.056, 0.056, 0.012, n=2),
                rrect(fx_bot * 0.96, fy_bot * 0.96, 0.025, 0.044, 0.044, 0.010, n=2),
                rrect(fx_top, fy_top, 0.128, 0.068, 0.068, 0.012, n=2),
            ]
            kit.loft(leg_rings, region=0)

    # 2. Base ash hearth apron / lip (z = 0.118 .. 0.155m)
    kit.box((0.0, -0.015, 0.136), (0.580, 0.530, 0.036), region=0, bevel=0.006)

    # 3. Main cast-iron firebox box (z = 0.155 .. 0.562m)
    kit.box((0.0, 0.0, 0.358), (0.520, 0.450, 0.408), region=0, bevel=0.008)

    # Corner vertical trim ribs
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.box((sx * 0.256, sy * 0.221, 0.358), (0.024, 0.024, 0.404), region=0, bevel=0.003)

    # 4. Front (-Y) arched firebox door + frame + hinges + latch bar (matches ref)
    front_y = -0.225
    # Raised outer door surround frame (rounded rect)
    frame_rings = [
        rrect(0.0, 0.0, 0.0, 0.320, 0.270, 0.095, n=3),
        rrect(0.0, 0.0, 0.016, 0.304, 0.254, 0.090, n=3),
    ]
    # Rotate rings to lie on XZ plane facing -Y
    xz_frame = [[(x, front_y - z, 0.382 + y) for (x, y, z) in r] for r in frame_rings]
    kit.loft(xz_frame, region=0)

    # Inner raised door panel
    door_rings = [
        rrect(0.0, 0.0, 0.016, 0.264, 0.218, 0.082, n=3),
        rrect(0.0, 0.0, 0.028, 0.244, 0.198, 0.076, n=3),
    ]
    xz_door = [[(x, front_y - z, 0.382 + y) for (x, y, z) in r] for r in door_rings]
    kit.loft(xz_door, region=1)

    # Right-side hinge barrels & left-side horizontal latch bar + handle
    for hz in (0.325, 0.435):
        kit.cyl((0.152, front_y - 0.020, hz), (0.0, 0.0, 1.0), 0.011, 0.036, segs=8, region=3)
    kit.box((-0.105, front_y - 0.034, 0.365), (0.140, 0.014, 0.022), region=3, bevel=0.002)
    kit.box((-0.172, front_y - 0.042, 0.365), (0.026, 0.026, 0.034), region=3, bevel=0.003)

    # Lower rectangular ash draft vent plate below door (z = 0.178 .. 0.242m)
    kit.box((0.0, front_y - 0.008, 0.210), (0.285, 0.016, 0.062), region=0, bevel=0.003)
    kit.box((0.0, front_y - 0.014, 0.210), (0.235, 0.010, 0.040), region=2)
    kit.box((0.042, front_y - 0.020, 0.210), (0.024, 0.012, 0.022), region=3)

    # 5. Overhanging cast-iron top plate (z = 0.562 .. 0.598m) + 2 burner rings
    top_rings = [
        rrect(0.0, 0.0, 0.562, 0.600, 0.520, 0.016, n=2),
        rrect(0.0, 0.0, 0.586, 0.616, 0.536, 0.016, n=2),
        rrect(0.0, 0.0, 0.598, 0.596, 0.516, 0.014, n=2),
    ]
    kit.loft(top_rings, region=1)
    # Recessed seam rim on top + front cast-iron hotplate lid disc
    kit.cyl((-0.125, -0.055, 0.600), (0.0, 0.0, 1.0), 0.105, 0.008, segs=14, region=1)

    # Twin side steel wire carry handles (±X, matching ref 2026-10-29_18-24.png)
    for sx in (-1.0, 1.0):
        pts = [
            (sx * 0.262, -0.115, 0.528),
            (sx * 0.345, -0.105, 0.538),
            (sx * 0.345, +0.105, 0.538),
            (sx * 0.262, +0.115, 0.528),
        ]
        kit.tube(pts, radius=0.008, segs=6, region=3, cap=True)

    # 6. Top stepped flue collar + short vertical stovepipe neck (z = 0.598 .. 0.920m)
    flue_x, flue_y = 0.115, 0.085
    # Square cast collar base pad
    kit.box((flue_x, flue_y, 0.606), (0.195, 0.195, 0.018), region=1, bevel=0.003)
    # Stepped conical cast-iron flue collar
    kit.cyl((flue_x, flue_y, 0.635), (0.0, 0.0, 1.0), 0.088, 0.044, segs=16, region=1, radius2=0.072)
    # Vertical stovepipe neck reaching exact 0.920m
    kit.cyl((flue_x, flue_y, 0.788), (0.0, 0.0, 1.0), 0.068, 0.264, segs=16, region=1, radius2=0.068)
    # Raised crimp bead collar & damper lever knob on pipe
    kit.cyl((flue_x, flue_y, 0.910), (0.0, 0.0, 1.0), 0.073, 0.020, segs=16, region=1)
    # Recessed soot cap disk on very top (z = 0.920)
    kit.cyl((flue_x, flue_y, 0.918), (0.0, 0.0, 1.0), 0.060, 0.004, segs=14, region=2)
    kit.cyl((flue_x + 0.074, flue_y, 0.745), (1.0, 0.0, 0.0), 0.007, 0.042, segs=6, region=3)


def main() -> None:
    run_prop(CFG, _build_stove, painter=_paint_stove)


if __name__ == "__main__":
    main()
