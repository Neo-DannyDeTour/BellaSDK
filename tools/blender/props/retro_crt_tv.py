"""Procedural retro boxy CRT TV / monitor (0.42m H): cathode cabinet, curved glass, dials, rear vent.

Ref: /home/dkd/Downloads/hl2_refs/2026-10-29_18-27_1.png
Usage:
    python3 tools/blender/run.py tools/blender/props/retro_crt_tv.py
Regions: 0 = beige/gray metal cabinet, 1 = dark bezel & rear housing, 2 = CRT glass, 3 = dials/trim.
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
    "slug": "retro_crt_tv",
    "node_name": "RetroCrtTv",
    "mat_name": "M_RetroCrtTv",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-29_18-27_1.png",
    "tri_budget": 1400,
    "body": "rigid",
    "mass": 14.0,
    "seed": 53,
    "regions": [
        {"base": (184, 176, 148), "var": 0.08, "grime": 0.30, "rust": 0.06, "rough": 0.54,
         "metal": 0.26, "normal": 1.8},
        {"base": (44, 46, 48), "var": 0.06, "grime": 0.25, "rust": 0.04, "rough": 0.48,
         "metal": 0.20, "normal": 1.6},
        {"base": (44, 56, 50), "var": 0.04, "grime": 0.08, "rust": 0.0, "rough": 0.10,
         "metal": 0.05, "normal": 0.4},
        {"base": (156, 154, 148), "var": 0.08, "grime": 0.25, "rust": 0.10, "rough": 0.32,
         "metal": 0.82, "normal": 1.6},
    ],
}


def _paint_crt(idx: int, maps: dict, half: int) -> None:
    """Add subtle phosphor vignette + scanlines on CRT glass region (idx == 2)."""
    if idx != 2:
        return
    import numpy as np

    yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
    nx = (xx / half - 0.5) * 2.0
    ny = (yy / half - 0.5) * 2.0
    r2 = np.clip(nx * nx + ny * ny, 0.0, 1.5)
    glow = np.exp(-r2 * 1.45)
    scan = 0.94 + 0.06 * np.sin(yy * 0.9)
    maps["alb"] = np.clip(maps["alb"] * (0.72 + 0.45 * glow[..., None]) * scan[..., None], 30, 220)
    maps["rough"] = np.clip(0.08 + 0.05 * r2, 0.07, 0.18)


def _xz_rrect(cx: float, y: float, cz: float, w: float, h: float, r: float, n: int = 3) -> list:
    """Convert an XZ rounded rectangle at depth y into CCW-from-front (+Y inward) ring."""
    pts = rrect(cx, cz, y, w, h, r, n=n)
    return [(x, py, z) for (x, z, py) in pts]


def build(kit: Kit) -> None:
    """Build boxy retro CRT TV (Blender Z up, min_z=0, front=-Y, rear=+Y, total H=0.42m)."""
    # 1. Four low rubber/metal feet grounded at z=0.0.
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.cyl((sx * 0.21, sy * 0.13, 0.006), (0, 0, 1), 0.018, 0.012, 8, 1)

    # 2. Main boxy outer metal cabinet (z: 0.012 -> 0.420 => 0.408m body, total = 0.420m).
    z_mid = 0.216
    kit.box((0.0, 0.005, z_mid), (0.52, 0.31, 0.408), 0, bevel=0.008)

    # 3. Front bezel frame (recessed border around screen + right-hand control strip, -Y).
    kit.box((0.0, -0.152, z_mid), (0.495, 0.014, 0.382), 1, bevel=0.004)
    # Recessed dark screen surround (left-shifted for classic right control column).
    kit.box((-0.042, -0.157, z_mid), (0.378, 0.012, 0.342), 1, bevel=0.004)

    # 4. Curved convex CRT glass screen protruding gently from recess (-Y).
    crt_rings = [
        _xz_rrect(-0.042, -0.156, z_mid, 0.344, 0.304, 0.032, n=4),
        _xz_rrect(-0.042, -0.167, z_mid, 0.280, 0.244, 0.026, n=4),
        _xz_rrect(-0.042, -0.172, z_mid, 0.160, 0.135, 0.016, n=4),
    ]
    kit.loft(crt_rings, 2, cap_start=False, cap_end=True)

    # 5. Right-side dial & control strip (matching boxy bezel aesthetic in ref).
    ctrl_x = 0.195
    kit.box((ctrl_x, -0.160, z_mid), (0.072, 0.014, 0.348), 1, bevel=0.003)
    # Two chunky stepped rotary dials (VHF/UHF & Volume/Tuning).
    for dz in (0.320, 0.240):
        kit.cyl((ctrl_x, -0.172, dz), (0, -1, 0), 0.022, 0.014, 12, 3)
        kit.cyl((ctrl_x, -0.181, dz), (0, -1, 0), 0.014, 0.010, 10, 1)
    # Three square selector buttons + speaker slot bars below dials.
    for bz in (0.175, 0.145, 0.115):
        kit.box((ctrl_x, -0.169, bz), (0.026, 0.010, 0.014), 3, bevel=0.001)
    for sz in (0.082, 0.068, 0.054):
        kit.box((ctrl_x, -0.167, sz), (0.044, 0.005, 0.005), 3)

    # 6. Also add side recess trim / handle grip indents on +X/-X sides and rear cathode vent box (+Y).
    for sx in (-1.0, 1.0):
        kit.box((sx * 0.261, 0.005, 0.295), (0.006, 0.11, 0.026), 1)
    # Stepped tapered rear cathode-tube vent housing (+Y).
    rear_rings = [
        _xz_rrect(0.0, 0.160, z_mid, 0.34, 0.28, 0.020, n=2),
        _xz_rrect(0.0, 0.235, z_mid, 0.23, 0.19, 0.016, n=2),
        _xz_rrect(0.0, 0.255, z_mid, 0.19, 0.16, 0.014, n=2),
    ]
    kit.loft(rear_rings, 1)
    # Rear cooling vent louvers on top/sides of rear housing.
    for vz in (0.155, 0.185, 0.215, 0.245, 0.275):
        kit.box((0.0, 0.258, vz), (0.14, 0.006, 0.010), 3)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_crt)
