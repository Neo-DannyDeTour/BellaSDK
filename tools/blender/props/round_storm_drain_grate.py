"""Procedural Round Precast Concrete Storm Drain Collar & Steel Bar Grate (1.60m H).

Matches reference /home/dkd/Downloads/hl2_refs/concrete_circle_around.png:
- Circular precast concrete tunnel collar ring (1.60m OD, 1.12m bore, min_y = 0)
- Recessed damp concrete inner tunnel bore sleeve with formwork rib texture
- Heavy rusted steel circular perimeter grate ring with 6 radial anchor lugs
- Horizontal mid-crossbar + 9 heavy vertical rusted steel security bars across bore
- 2048x2048 PBR atlas (weathered precast concrete, damp bore concrete, rusted bars, dark iron lugs)

Usage:
    /usr/bin/python3 tools/blender/props/round_storm_drain_grate.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/round_storm_drain_grate.py
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
    "slug": "round_storm_drain_grate",
    "node_name": "RoundStormDrainGrate",
    "mat_name": "M_RoundStormDrainGrate",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/concrete_circle_around.png",
    "tri_budget": 1600,
    "body": "static",
    "seed": 44012,
    "regions": [
        # 0: Weathered precast concrete outer collar ring
        {"base": (156, 152, 142), "var": 0.12, "grime": 0.45, "rust": 0.04, "rough": 0.88,
         "metal": 0.0, "normal": 2.8},
        # 1: Damp stained inner bore concrete sleeve
        {"base": (108, 106, 98), "var": 0.14, "grime": 0.58, "rust": 0.06, "rough": 0.90,
         "metal": 0.0, "normal": 2.8},
        # 2: Heavy rusted steel security bars & circular grate frame
        {"base": (78, 54, 42), "var": 0.14, "grime": 0.35, "rust": 0.72, "rough": 0.72,
         "metal": 0.65, "normal": 2.4},
        # 3: Dark oxidized iron mounting lugs & bolts
        {"base": (56, 48, 44), "var": 0.10, "grime": 0.32, "rust": 0.55, "rough": 0.64,
         "metal": 0.72, "normal": 2.2},
    ],
}


def _paint_drain(idx: int, maps: dict, half: int) -> None:
    """Add concrete aggregate speckles (0, 1) and horizontal corrosion bands on bars (2)."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(44012 + idx * 19)
    if idx in (0, 1):
        # Fine aggregate concrete pores & subtle stain blotches
        speck_grid = rng.random((128, 128)).astype(np.float32)
        specks = np.asarray(
            Image.fromarray(speck_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        pits = np.clip((0.28 - specks) / 0.18, 0.0, 1.0)
        maps["alb"] = np.clip(maps["alb"] * (1.0 - 0.18 * pits[..., None]), 32.0, 235.0)
        maps["rough"] = np.clip(maps["rough"] + 0.06 * pits, 0.75, 0.96)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)


def _xz_ring(cx: float, y: float, cz: float, r: float, segs: int) -> list[tuple[float, float, float]]:
    """Return CCW ring in XZ plane facing -Y (front)."""
    return [
        (cx + r * math.cos(2.0 * math.pi * k / segs), y, cz + r * math.sin(2.0 * math.pi * k / segs))
        for k in range(segs)
    ]


def _torus_ring_loft(
    kit: Kit,
    center_y: float,
    center_z: float,
    profile_ry: list[tuple[float, float]],
    segs: int,
    regions: list[int] | int,
) -> None:
    """Revolve a closed 2D (radius, y_offset) profile around the Y-axis at (0, center_y, center_z)."""
    rings = [
        _xz_ring(0.0, center_y + dy, center_z, rad, segs)
        for rad, dy in profile_ry
    ]
    # Close loop by repeating first ring at end
    rings.append(rings[0])
    kit.loft(rings, regions, cap_start=False, cap_end=False)


def build(kit: Kit) -> None:
    """Build 1.60m precast concrete storm drain collar + heavy vertical rusted steel bars."""
    cz = 0.80  # Outer radius = 0.80 -> min_z = 0.0, max_z = 1.60m
    r_out = 0.80
    r_in = 0.56
    depth = 0.44
    half_d = depth * 0.5

    # 1. Precast concrete circular collar (20-sided revolved closed profile)
    # Profile wraps CCW around cross-section in (r, y) so outward normals face outward
    collar_profile = [
        (r_in, -half_d + 0.015),          # front inner lip
        (r_in + 0.018, -half_d),          # front face inner edge
        (r_out - 0.022, -half_d),         # front face outer chamfer start
        (r_out, -half_d + 0.022),         # outer barrel front
        (r_out, +half_d - 0.022),         # outer barrel rear
        (r_out - 0.022, +half_d),         # rear face outer chamfer
        (r_in + 0.018, +half_d),          # rear face inner edge
        (r_in, +half_d - 0.015),          # rear inner lip
    ]
    # Region 0 on outer/front/rear faces, Region 1 on inner bore wall (last segment)
    collar_regs = [0, 0, 0, 0, 0, 0, 0, 1]
    _torus_ring_loft(kit, center_y=0.0, center_z=cz, profile_ry=collar_profile, segs=20, regions=collar_regs)

    # 2. Inner recessed concrete lip/step where grate seats (y = -0.06m)
    step_profile = [
        (r_in - 0.022, -0.095),
        (r_in + 0.005, -0.095),
        (r_in + 0.005, -0.055),
        (r_in - 0.022, -0.055),
    ]
    _torus_ring_loft(kit, center_y=0.0, center_z=cz, profile_ry=step_profile, segs=20, regions=1)

    # 3. Heavy circular rusted steel outer grate ring inside bore (r_frame = 0.535m)
    grate_y = -0.085
    rf_out = 0.540
    rf_in = 0.505
    frame_profile = [
        (rf_in, -0.022),
        (rf_out, -0.022),
        (rf_out, +0.022),
        (rf_in, +0.022),
    ]
    _torus_ring_loft(kit, center_y=grate_y, center_z=cz, profile_ry=frame_profile, segs=18, regions=2)

    # 4. 6 radial anchor lug brackets fastening steel ring into concrete bore
    for k in range(6):
        ang = math.radians(30.0 + k * 60.0)
        ca, sa = math.cos(ang), math.sin(ang)
        lx = ca * 0.542
        lz = cz + sa * 0.542
        kit.box((lx, grate_y, lz), (0.048, 0.052, 0.048), 3, bevel=0.003)

    # 5. Horizontal mid-transom crossbar + heavy central double vertical mullion + vertical bars
    kit.box((0.0, grate_y, cz), (rf_in * 2.02, 0.032, 0.036), 2, bevel=0.003)

    # Heavy vertical security bars across the circular bore (clipped cleanly inside rf_in + overlap)
    bar_xs = [-0.43, -0.325, -0.22, -0.115, 0.0, 0.115, 0.22, 0.325, 0.43]
    for bx in bar_xs:
        half_span = math.sqrt(max(0.0, (rf_in + 0.012) ** 2 - bx * bx))
        bar_h = half_span * 2.0
        if bx == 0.0:
            # Central heavier vertical mullion stile (echoing double-gate center spine in ref)
            kit.box((-0.016, grate_y, cz), (0.024, 0.036, bar_h), 2, bevel=0.002)
            kit.box((+0.016, grate_y, cz), (0.024, 0.036, bar_h), 2, bevel=0.002)
        else:
            kit.cyl((bx, grate_y, cz), (0.0, 0.0, 1.0), 0.015, bar_h, segs=6, region=2)

    # Secondary upper/lower horizontal stiffening flat bars for structural authenticity
    for z_off in (-0.28, 0.28):
        half_w = math.sqrt(max(0.0, (rf_in + 0.010) ** 2 - z_off * z_off))
        kit.box((0.0, grate_y + 0.008, cz + z_off), (half_w * 2.0, 0.014, 0.024), 3)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_drain)
