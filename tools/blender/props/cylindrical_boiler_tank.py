"""Procedural Horizontal Cylindrical Riveted Steel Pressure Boiler (1.35m H, ~1.85m L).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-31_15-48_1.png
- /home/dkd/Downloads/hl2_refs/2026-11-04_03-34_1.png

Features:
- Twin heavy rusted-steel cradle saddles with floor plates and side gussets (min_y = 0)
- Horizontal riveted steel pressure tank (~1.85m L) with dished end heads and
  circumferential seam strap bands
- Heavy bolted circular end manway hatch with hinge bracket and perimeter bolts
- Top flanged pipe nozzles and valve collar reaching exact 1.35m height
- 2048x2048 PBR atlas (weathered gray-olive shell, rusted cradles/collars, hatch/nozzles, bolts)

Usage:
    /usr/bin/python3 tools/blender/props/cylindrical_boiler_tank.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/cylindrical_boiler_tank.py
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
    "slug": "cylindrical_boiler_tank",
    "node_name": "CylindricalBoilerTank",
    "mat_name": "M_CylindricalBoilerTank",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-31_15-48_1.png",
    "tri_budget": 1800,
    "body": "static",
    "seed": 10311548,
    "regions": [
        # 0: Weathered painted gray-olive steel pressure drum shell
        {"base": (132, 136, 128), "var": 0.12, "grime": 0.44, "rust": 0.34, "rough": 0.62,
         "metal": 0.52, "normal": 2.3},
        # 1: Dark rusted steel cradle saddles, end flange collars & seam bands
        {"base": (66, 60, 56), "var": 0.11, "grime": 0.38, "rust": 0.52, "rough": 0.60,
         "metal": 0.72, "normal": 2.4},
        # 2: Bolted manway hatch cover & top flange nozzles
        {"base": (92, 90, 86), "var": 0.10, "grime": 0.36, "rust": 0.36, "rough": 0.54,
         "metal": 0.74, "normal": 2.2},
        # 3: Corroded rust-orange/iron rivets, hex bolts & valve wheel
        {"base": (110, 72, 52), "var": 0.12, "grime": 0.28, "rust": 0.62, "rough": 0.58,
         "metal": 0.76, "normal": 2.5},
    ],
}


def _paint_boiler(idx: int, maps: dict, half: int) -> None:
    """Add subtle mottled weathering on boiler shell (0) without directional UV seam cutoffs."""
    import numpy as np

    if idx == 0:
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        u = xx / float(half)
        v = yy / float(half)
        mottle = 0.5 + 0.5 * np.sin(u * 14.0 * math.pi + np.cos(v * 12.0 * math.pi) * 1.8)
        maps["alb"] = np.clip(maps["alb"] * (0.93 + 0.12 * mottle[..., None]), 32.0, 234.0)
        maps["rough"] = np.clip(maps["rough"] + 0.08 * (1.0 - mottle), 0.42, 0.92)


def _x_ring(x: float, cy: float, cz: float, r: float, segs: int) -> list[tuple[float, float, float]]:
    """Return CCW ring in YZ plane (normal pointing +X) around (x, cy, cz)."""
    return [
        (x, cy + r * math.cos(2.0 * math.pi * k / segs), cz + r * math.sin(2.0 * math.pi * k / segs))
        for k in range(segs)
    ]


def _add_cradle_saddle(kit: Kit, cx: float, cz_drum: float, r_drum: float) -> None:
    """Build a heavy flared steel cradle saddle grounded at z = 0.0 supporting the drum."""
    # Grounded base foot plate (min_z = 0.0)
    kit.box((cx, 0.0, 0.020), (0.20, 1.04, 0.040), 1)

    half_x = 0.070
    # Left & right angled cheek pillars
    for sy in (-1.0, 1.0):
        # Outer cheek post
        kit.box((cx, sy * 0.42, 0.23), (0.14, 0.12, 0.38), 1)
        # Slanted saddle cheek brace
        y0, y1 = sy * 0.18, sy * 0.45
        z_top_in = cz_drum - math.sqrt(max(0.01, r_drum * r_drum - y0 * y0)) + 0.02
        z_top_out = cz_drum - math.sqrt(max(0.01, r_drum * r_drum - 0.36 * 0.36)) + 0.02
        ring_a = [
            (cx - half_x, y0, 0.04),
            (cx - half_x, y1, 0.04),
            (cx - half_x, y1, z_top_out),
            (cx - half_x, y0, z_top_in),
        ]
        ring_b = [
            (cx + half_x, y0, 0.04),
            (cx + half_x, y1, 0.04),
            (cx + half_x, y1, z_top_out),
            (cx + half_x, y0, z_top_in),
        ]
        if sy < 0:
            ring_a = list(reversed(ring_a))
            ring_b = list(reversed(ring_b))
        kit.loft([ring_a, ring_b], 1, cap_start=True, cap_end=True)

    # Center belly support block under keel
    kit.box((cx, 0.0, 0.16), (0.14, 0.38, 0.24), 1)


def build(kit: Kit) -> None:
    """Build 1.35m H (~1.85m L) horizontal riveted steel pressure boiler grounded at (0, 0, 0)."""
    cz_drum = 0.72
    r_drum = 0.46
    segs = 16

    # 1. Twin cradle saddles grounded at z = 0.0
    _add_cradle_saddle(kit, -0.56, cz_drum, r_drum)
    _add_cradle_saddle(kit, +0.56, cz_drum, r_drum)

    # 2. Horizontal cylindrical pressure drum with dished ends & circumferential seam bands
    # Total length along X: -0.925m to +0.925m = 1.85m (including end hatch)
    shell_profile = [
        # (x, radius, region_next)
        (-0.880, 0.16, 0),   # Rear dished head center
        (-0.820, 0.36, 0),   # Rear dished shoulder
        (-0.760, 0.46, 1),   # Rear end collar start
        (-0.710, 0.495, 1),  # Rear heavy riveted collar ring
        (-0.670, 0.495, 1),
        (-0.650, 0.46, 0),   # Main shell bay 1
        (-0.240, 0.46, 1),
        (-0.220, 0.478, 1),  # Mid seam strap 1
        (-0.190, 0.478, 1),
        (-0.170, 0.46, 0),   # Main shell bay 2
        (0.170, 0.46, 1),
        (0.190, 0.478, 1),   # Mid seam strap 2
        (0.220, 0.478, 1),
        (0.240, 0.46, 0),    # Main shell bay 3
        (0.650, 0.46, 1),
        (0.670, 0.495, 1),   # Front heavy riveted collar ring
        (0.710, 0.495, 1),
        (0.760, 0.46, 0),    # Front dished shoulder
        (0.825, 0.35, 0),
    ]
    rings = [_x_ring(x, 0.0, cz_drum, r, segs) for x, r, _ in shell_profile]
    regs = [reg for _, _, reg in shell_profile[:-1]]
    kit.loft(rings, regs, cap_start=True, cap_end=True)

    # 3. Bolted circular end manway hatch on +X end (reaching x = +0.925m -> total 1.85m L)
    kit.cyl((0.835, 0.0, cz_drum), (1.0, 0.0, 0.0), 0.27, 0.075, 12, 1)
    kit.cyl((0.885, 0.0, cz_drum), (1.0, 0.0, 0.0), 0.22, 0.055, 12, 2)
    kit.cyl((0.915, 0.0, cz_drum), (1.0, 0.0, 0.0), 0.10, 0.020, 10, 2)
    # Hinge lug & clamping dog on manway hatch
    kit.box((0.865, -0.26, cz_drum), (0.07, 0.06, 0.11), 3)
    # Perimeter hex bolts on end hatch
    n_hatch_bolts = 6
    for k in range(n_hatch_bolts):
        a = 2.0 * math.pi * k / n_hatch_bolts
        by = 0.235 * math.cos(a)
        bz = cz_drum + 0.235 * math.sin(a)
        kit.cyl((0.895, by, bz), (1.0, 0.0, 0.0), 0.016, 0.025, 5, 3)

    # 4. Rear small gauge/cleanout boss on -X end (x = -0.925m for 1.85m symmetry)
    kit.cyl((-0.895, 0.0, cz_drum), (-1.0, 0.0, 0.0), 0.11, 0.060, 10, 2)

    # 5. Rivets along the two heavy end collar rings (8 rivets each)
    for rx in (-0.690, 0.690):
        for k in range(8):
            a = 2.0 * math.pi * k / 8
            ry = 0.498 * math.cos(a)
            rz = cz_drum + 0.498 * math.sin(a)
            kit.cyl((rx, ry, rz), (0.0, math.cos(a), math.sin(a)), 0.014, 0.018, 5, 3)

    # 6. Top flanged pipe nozzles (reaching exact z = 1.350m)
    # Nozzle A: Heavy bolted steam dome / blind flange at x = -0.30m (top at z = 1.350m)
    kit.cyl((-0.30, 0.0, 1.215), (0.0, 0.0, 1.0), 0.110, 0.110, 10, 2)
    kit.cyl((-0.30, 0.0, 1.300), (0.0, 0.0, 1.0), 0.155, 0.032, 10, 1)
    kit.cyl((-0.30, 0.0, 1.333), (0.0, 0.0, 1.0), 0.145, 0.034, 10, 2)
    for k in range(4):
        a = 2.0 * math.pi * k / 4
        kit.cyl((-0.30 + 0.128 * math.cos(a), 0.128 * math.sin(a), 1.335), (0.0, 0.0, 1.0), 0.013, 0.024, 5, 3)

    # Nozzle B: Secondary flanged outlet nozzle + valve wheel at x = +0.28m
    kit.cyl((0.28, 0.0, 1.210), (0.0, 0.0, 1.0), 0.068, 0.110, 8, 2)
    kit.cyl((0.28, 0.0, 1.275), (0.0, 0.0, 1.0), 0.105, 0.026, 8, 1)
    kit.cyl((0.28, 0.0, 1.310), (0.0, 0.0, 1.0), 0.028, 0.055, 8, 3)

    # Side lower drain/inlet boss on front (+Y) side
    kit.cyl((0.0, 0.455, 0.56), (0.0, 1.0, 0.0), 0.055, 0.075, 8, 2)


if __name__ == "__main__":
    if "--gen-textures" in sys.argv:
        from tools.blender.common.domestic_kit import generate_atlas

        generate_atlas(CFG, _paint_boiler)
    else:
        run_prop(CFG, build, _paint_boiler)
