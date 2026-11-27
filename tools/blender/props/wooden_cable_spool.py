"""Procedural Weathered Wooden Cable Spool Lying Flat (0.72m H, ~1.15m Dia).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-04_03-49_2.png:
- Lying flat on bottom circular planked timber flange (min_y = 0)
- Central planked timber core barrel drum with hollow central arbor bore
- Top planked timber flange with beveled rim edge
- Steel center arbor flange collar plates, bore sleeve, and 6 raised bolt heads + washers
- 2048x2048 PBR atlas (planked pine wood flange, darker stave core, rusted steel arbor, bolts)

Usage:
    /usr/bin/python3 tools/blender/props/wooden_cable_spool.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/wooden_cable_spool.py
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
    "slug": "wooden_cable_spool",
    "node_name": "WoodenCableSpool",
    "mat_name": "M_WoodenCableSpool",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-11-04_03-49_2.png",
    "tri_budget": 1400,
    "body": "static",
    "seed": 11040349,
    "regions": [
        # 0: Weathered sun-bleached planked timber flanges
        {"base": (168, 146, 114), "var": 0.14, "grime": 0.34, "rust": 0.0, "rough": 0.80,
         "metal": 0.0, "normal": 2.6},
        # 1: Darker weathered timber stave barrel core
        {"base": (134, 112, 84), "var": 0.14, "grime": 0.40, "rust": 0.0, "rough": 0.84,
         "metal": 0.0, "normal": 2.6},
        # 2: Rusted steel center arbor flange plates & bore sleeve
        {"base": (118, 112, 108), "var": 0.12, "grime": 0.34, "rust": 0.45, "rough": 0.50,
         "metal": 0.68, "normal": 2.3},
        # 3: Corroded rust-orange/iron tie-rod bolt heads & washers
        {"base": (136, 88, 60), "var": 0.12, "grime": 0.28, "rust": 0.58, "rough": 0.54,
         "metal": 0.72, "normal": 2.4},
    ],
}


def _paint_spool(idx: int, maps: dict, half: int) -> None:
    """Add wood plank seams, grain fibers, and weathered knots on wood regions (0, 1)."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(11040349 + idx * 29)
    if idx in (0, 1):
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        u = xx / float(half)
        v = yy / float(half)
        # Wood grain fibers along U
        warp = np.asarray(
            Image.fromarray(rng.random((20, 6)).astype(np.float32), mode="F").resize(
                (half, half), Image.Resampling.BICUBIC
            ),
            dtype=np.float32,
        )
        fiber = np.asarray(
            Image.fromarray(rng.random((220, 18)).astype(np.float32), mode="F").resize(
                (half, half), Image.Resampling.BICUBIC
            ),
            dtype=np.float32,
        )
        grain = 0.5 + 0.5 * np.sin(v * 52.0 * math.pi + warp * 4.5)
        # Plank butt-joint seams across V (5 planks per face)
        plank_phase = (v * 5.0) % 1.0
        seam = np.exp(-((np.minimum(plank_phase, 1.0 - plank_phase)) / 0.018) ** 2)
        # Slight per-plank brightness shift
        plank_id = np.floor(v * 5.0)
        plank_var = 0.90 + 0.18 * ((np.sin(plank_id * 12.9898 + idx) * 43758.5453) % 1.0)

        alb = maps["alb"] * plank_var[..., None] * (0.86 + 0.22 * fiber + 0.08 * grain)[..., None]
        alb = alb * (1.0 - 0.55 * seam[..., None])
        maps["alb"] = np.clip(alb, 32.0, 232.0)
        maps["rough"] = np.clip(0.72 + 0.14 * (1.0 - grain) + 0.12 * seam, 0.62, 0.94)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)

        h = 0.45 * fiber + 0.35 * grain - 0.50 * seam
        gy, gx = np.gradient(h)
        nrm = np.stack([-gx * 3.0, gy * 3.0, np.ones_like(h)], axis=-1)
        nrm /= np.sqrt(np.sum(nrm * nrm, axis=-1, keepdims=True))
        maps["nrm"] = nrm


def _ring(r: float, z: float, segs: int) -> list[tuple[float, float, float]]:
    return [
        (r * math.cos(2.0 * math.pi * k / segs), r * math.sin(2.0 * math.pi * k / segs), z)
        for k in range(segs)
    ]


def _add_hollow_flange(
    kit: Kit,
    z_bot: float,
    z_top: float,
    r_in: float,
    r_out: float,
    segs: int,
    region: int,
) -> None:
    """Build a beveled hollow timber flange disc from z_bot to z_top with bore r_in."""
    cham = 0.012
    # Closed 6-ring cross-section loop: outer-bot -> outer-top -> inner-top -> inner-bot
    rings = [
        _ring(r_out - cham, z_bot, segs),
        _ring(r_out, z_bot + cham, segs),
        _ring(r_out, z_top - cham, segs),
        _ring(r_out - cham, z_top, segs),
        _ring(r_in, z_top, segs),
        _ring(r_in, z_bot, segs),
        _ring(r_out - cham, z_bot, segs),
    ]
    # Remove duplicate closing face seam by lofting open rings and bridging:
    # Actually loft(rings[:-1], cap_start=False, cap_end=False) misses closing strip;
    # include closing ring with cap_start=False, cap_end=False or build clean quads:
    bm = kit.bm
    vr = [[bm.verts.new(p) for p in r] for r in rings[:-1]]
    m = len(vr)
    for k in range(m):
        kn = (k + 1) % m
        for i in range(segs):
            j = (i + 1) % segs
            f = bm.faces.new((vr[k][i], vr[k][j], vr[kn][j], vr[kn][i]))
            f.material_index = region


def build(kit: Kit) -> None:
    """Build 0.72m H x 1.15m Dia wooden cable spool lying flat at (0, 0, 0)."""
    segs = 18
    r_flange = 0.575   # 1.15m diameter
    r_core = 0.305     # Inner drum barrel radius
    r_bore = 0.062     # Central steel arbor bore radius
    flange_h = 0.068
    flange_top_z = 0.706
    total_h = 0.720

    # 1. Bottom wooden flange (z = 0.0 -> 0.068m) & top wooden flange (z = 0.638 -> 0.706m)
    _add_hollow_flange(kit, 0.0, flange_h, r_bore, r_flange, segs, region=0)
    _add_hollow_flange(kit, flange_top_z - flange_h, flange_top_z, r_bore, r_flange, segs, region=0)

    # 2. Central timber stave barrel drum (z = 0.068 -> 0.638m)
    kit.cyl((0.0, 0.0, flange_top_z * 0.5), (0.0, 0.0, 1.0), r_core, flange_top_z - 2.0 * flange_h + 0.004, segs, 1)

    # 3. Steel center arbor flange collar plates & central bore sleeve
    _add_hollow_flange(kit, flange_top_z - 0.002, flange_top_z + 0.006, r_bore - 0.004, 0.165, 14, region=2)
    _add_hollow_flange(kit, 0.002, 0.012, r_bore - 0.004, 0.165, 14, region=2)

    # Inner steel bore sleeve tube running through the spool
    bore_rings = [
        _ring(r_bore - 0.004, 0.002, 12),
        _ring(r_bore - 0.004, flange_top_z + 0.004, 12),
    ]
    # Inverted winding for inward-facing bore sleeve
    kit.loft([list(reversed(r)) for r in bore_rings], 2, cap_start=False, cap_end=False)

    # 4. Six raised steel tie-rod bolt heads + circular washers on top arbor flange (peaking at exact 0.720m)
    for k in range(6):
        a = 2.0 * math.pi * k / 6
        bx, by = 0.118 * math.cos(a), 0.118 * math.sin(a)
        kit.cyl((bx, by, flange_top_z + 0.007), (0.0, 0.0, 1.0), 0.022, 0.006, 8, 2)
        kit.cyl((bx, by, flange_top_z + 0.011), (0.0, 0.0, 1.0), 0.015, 0.006, 6, 3)

    # 4 outer tie-rod washers & nuts at r = 0.240m on top flange
    for k in range(4):
        a = math.radians(45.0 + 90.0 * k)
        bx, by = 0.240 * math.cos(a), 0.240 * math.sin(a)
        kit.cyl((bx, by, flange_top_z + 0.002), (0.0, 0.0, 1.0), 0.024, 0.006, 8, 2)
        kit.cyl((bx, by, flange_top_z + 0.008), (0.0, 0.0, 1.0), 0.015, 0.010, 6, 3)


if __name__ == "__main__":
    if "--gen-textures" in sys.argv:
        from tools.blender.common.domestic_kit import generate_atlas

        generate_atlas(CFG, _paint_spool)
    else:
        run_prop(CFG, build, _paint_spool)
