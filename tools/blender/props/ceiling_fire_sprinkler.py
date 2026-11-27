"""Procedural Ceiling Fire Sprinkler (0.22m H).

Matches reference /home/dkd/Downloads/hl2_refs/sprinkler.png:
- Short horizontal weathered dark steel supply pipe & central cast tee collar (top)
- Brass hexagonal wrench boss, 2-arm curved yoke frame, and lower nozzle hub
- Red-amber thermal glass trigger bulb centered inside yoke
- Toothed galvanized steel deflector disc + center retaining cone at bottom (min_y = 0)
- 2048x2048 PBR atlas (steel pipe/tee, brass yoke, galvanized deflector, glass bulb)

Usage:
    /usr/bin/python3 tools/blender/props/ceiling_fire_sprinkler.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/ceiling_fire_sprinkler.py
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
    "slug": "ceiling_fire_sprinkler",
    "node_name": "CeilingFireSprinkler",
    "mat_name": "M_CeilingFireSprinkler",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/sprinkler.png",
    "tri_budget": 900,
    "body": "static",
    "seed": 4101,
    "regions": [
        # 0: Dark weathered rusted steel supply pipe & tee collar
        {
            "base": (72, 60, 50),
            "var": 0.12,
            "grime": 0.42,
            "rust": 0.44,
            "rough": 0.56,
            "metal": 0.78,
            "normal": 2.4,
        },
        # 1: Tarnished industrial brass yoke frame & hex wrench boss
        {
            "base": (162, 132, 72),
            "var": 0.10,
            "grime": 0.36,
            "rust": 0.10,
            "rough": 0.38,
            "metal": 0.88,
            "normal": 1.8,
        },
        # 2: Aged galvanized steel toothed deflector disc & retaining screw
        {
            "base": (166, 172, 174),
            "var": 0.08,
            "grime": 0.30,
            "rust": 0.12,
            "rough": 0.36,
            "metal": 0.85,
            "normal": 1.8,
        },
        # 3: Thermal glass trigger bulb (crimson-amber tint)
        {
            "base": (146, 36, 30),
            "var": 0.06,
            "grime": 0.12,
            "rust": 0.0,
            "rough": 0.22,
            "metal": 0.05,
            "normal": 1.0,
        },
    ],
}


def _paint_sprinkler(idx: int, maps: dict, half: int) -> None:
    """Add radial brushed grooves on deflector (2) and pipe threading/grime streaks (0)."""
    import numpy as np

    if idx == 0:
        yy, _xx = np.mgrid[0:half, 0:half].astype(np.float32)
        rib = 0.5 + 0.5 * np.sin((yy / float(half)) * 48.0 * math.pi)
        maps["alb"] = np.clip(maps["alb"] * (0.93 + 0.12 * rib[..., None]), 30.0, 235.0)
        maps["rough"] = np.clip(maps["rough"] + 0.05 * (1.0 - rib), 0.30, 0.90)
    elif idx == 2:
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        cx = (xx - half * 0.5) / float(half)
        cy = (yy - half * 0.5) / float(half)
        rad = np.sqrt(cx * cx + cy * cy)
        brushed = 0.5 + 0.5 * np.sin(rad * 72.0 * math.pi)
        maps["alb"] = np.clip(maps["alb"] * (0.94 + 0.10 * brushed[..., None]), 32.0, 235.0)
        maps["rough"] = np.clip(maps["rough"] + 0.04 * (1.0 - brushed), 0.22, 0.72)


def _deflector_star(kit: Kit, z_bot: float, z_top: float, teeth: int, region: int) -> None:
    """Build a serrated toothed sprinkler deflector disc centered at XY=(0,0)."""
    r_outer = 0.043
    r_inner = 0.027
    n_pts = teeth * 2
    ring_bot: list[tuple[float, float, float]] = []
    ring_top: list[tuple[float, float, float]] = []
    for i in range(n_pts):
        ang = 2.0 * math.pi * float(i) / float(n_pts)
        rad = r_outer if (i % 2 == 0) else r_inner
        z_tip_offset = 0.002 if (i % 2 == 0) else 0.0
        x = rad * math.cos(ang)
        y = rad * math.sin(ang)
        ring_bot.append((x, y, z_bot + z_tip_offset))
        ring_top.append((x * 0.98, y * 0.98, z_top + z_tip_offset))
    kit.loft([ring_bot, ring_top], region, cap_start=True, cap_end=True)


def build(kit: Kit) -> None:
    """Build pendent ceiling fire sprinkler (0.22m total height, min Z = 0.0)."""
    # 1. Bottom retaining diffuser cone (tip at z = 0.0) & toothed deflector disc
    kit.cyl((0.0, 0.0, 0.006), (0, 0, 1), 0.002, 0.012, 8, 2, radius2=0.008)
    _deflector_star(kit, z_bot=0.006, z_top=0.011, teeth=10, region=2)

    # 2. Brass lower yoke hub & compression boss
    kit.cyl((0.0, 0.0, 0.017), (0, 0, 1), 0.011, 0.012, 10, 1, radius2=0.008)

    # 3. Two curved brass yoke arms flanking the central glass bulb
    for sx in (-1.0, 1.0):
        arm_pts = [
            (sx * 0.008, 0.0, 0.018),
            (sx * 0.024, 0.0, 0.040),
            (sx * 0.029, 0.0, 0.068),
            (sx * 0.024, 0.0, 0.095),
            (sx * 0.014, 0.0, 0.116),
        ]
        kit.tube(arm_pts, 0.0052, 6, 1, cap=True)

    # 4. Central thermal glass bulb + brass seats
    kit.cyl((0.0, 0.0, 0.028), (0, 0, 1), 0.007, 0.010, 8, 1)
    kit.cyl((0.0, 0.0, 0.044), (0, 0, 1), 0.0045, 0.022, 8, 3, radius2=0.0075)
    kit.cyl((0.0, 0.0, 0.068), (0, 0, 1), 0.0075, 0.026, 8, 3, radius2=0.0075)
    kit.cyl((0.0, 0.0, 0.088), (0, 0, 1), 0.0075, 0.014, 8, 3, radius2=0.0045)
    kit.cyl((0.0, 0.0, 0.103), (0, 0, 1), 0.009, 0.016, 8, 1)

    # 5. Hexagonal brass wrench boss & threaded steel drop nipple
    kit.cyl((0.0, 0.0, 0.121), (0, 0, 1), 0.021, 0.020, 6, 1)
    kit.cyl((0.0, 0.0, 0.144), (0, 0, 1), 0.014, 0.028, 10, 0)

    # 6. Horizontal dark steel supply pipe & central cast tee collar (top = 0.220m)
    pipe_z = 0.194
    kit.cyl((0.0, 0.0, pipe_z), (1, 0, 0), 0.0185, 0.280, 10, 0)
    kit.cyl((0.0, 0.0, pipe_z), (1, 0, 0), 0.0260, 0.096, 10, 0)
    kit.cyl((0.0, 0.0, 0.168), (0, 0, 1), 0.0215, 0.032, 10, 0)
    # Pipe end ring beads for clean silhouette termination
    for sx in (-1.0, 1.0):
        kit.cyl((sx * 0.136, 0.0, pipe_z), (1, 0, 0), 0.0215, 0.010, 10, 0)


if __name__ == "__main__":
    run_prop(CFG, build, _paint_sprinkler)
