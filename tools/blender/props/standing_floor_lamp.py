"""Procedural Standing Floor Lamp with Flared Floral Cloth Lampshade (1.58m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-32_2.png:
- Weighted round stepped metal base grounded at min_y = 0
- Slender turned metal stem with decorative baluster collar and neck
- Hollow flared faded cloth lampshade with subtle vintage Soviet floral print & rolled trim
- Inner bulb/socket + 3-wire spider + top turned finial
- Single mesh, 2048x2048 PBR atlas

Usage:
    /usr/bin/python3 tools/blender/props/standing_floor_lamp.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/standing_floor_lamp.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import (  # noqa: E402
    Kit,
    REPO_ROOT as KIT_ROOT,
    ellipse,
    run_prop,
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-32_2.png"

CFG: dict = {
    "slug": "standing_floor_lamp",
    "node_name": "StandingFloorLamp",
    "mat_name": "M_StandingFloorLamp",
    "script": __file__,
    "ref_image": REF_IMAGE,
    "tri_budget": 1200,
    "body": "static",
    "seed": 18322,
    "regions": [
        # 0: Outer faded cream/beige linen lampshade with vintage floral print
        {"base": (196, 186, 152), "var": 0.07, "grime": 0.24, "rust": 0.0, "rough": 0.86,
         "metal": 0.0, "normal": 1.1},
        # 1: Aged patinated brass/olive-bronze weighted base, stem, finial
        {"base": (118, 108, 68), "var": 0.09, "grime": 0.34, "rust": 0.14, "rough": 0.44,
         "metal": 0.78, "normal": 1.3},
        # 2: Inner lampshade lining & warm frosted bulb
        {"base": (212, 200, 168), "var": 0.05, "grime": 0.14, "rust": 0.0, "rough": 0.72,
         "metal": 0.0, "normal": 0.6},
        # 3: Dark tarnished brass socket & wire spider
        {"base": (72, 64, 48), "var": 0.07, "grime": 0.30, "rust": 0.16, "rough": 0.46,
         "metal": 0.82, "normal": 1.2},
    ],
}


def _paint_lamp(idx: int, maps: dict, half: int) -> None:
    """Paint linen weave + faded floral print on shade (0) and tarnished brass patina on metal (1,3)."""
    import numpy as np
    from PIL import Image

    if idx == 0:
        # Subtle woven linen cross-hatch + faded vintage rose/leaf clusters
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        u = xx / float(half)
        v = yy / float(half)
        weave = 0.96 + 0.04 * np.sin(xx * 1.25) * np.sin(yy * 1.25)
        alb = maps["alb"] * weave[..., None]

        # 7x5 delicate faded floral clusters so motifs stay crisp & avoid large seam smears
        rng = np.random.default_rng(18322)
        flower_col = np.array([154.0, 72.0, 52.0], dtype=np.float32)
        leaf_col = np.array([78.0, 94.0, 58.0], dtype=np.float32)
        for row in range(5):
            for col in range(7):
                cu = (col + 0.5 + 0.35 * (row % 2)) / 7.0 + float(rng.uniform(-0.02, 0.02))
                cv = (row + 0.5) / 5.0 + float(rng.uniform(-0.02, 0.02))
                cu = cu % 1.0
                du = np.minimum(np.abs(u - cu), 1.0 - np.abs(u - cu))
                dv = v - cv
                # Crisp small blossom cluster + leaves
                r_fl = np.sqrt((du * 30.0) ** 2 + (dv * 26.0) ** 2)
                fl_mask = np.clip(1.0 - r_fl, 0.0, 1.0) ** 1.15 * 0.72
                r_lf1 = np.sqrt(((du - 0.024) * 34.0) ** 2 + ((dv + 0.014) * 36.0) ** 2)
                r_lf2 = np.sqrt(((du + 0.024) * 34.0) ** 2 + ((dv - 0.012) * 36.0) ** 2)
                lf_mask = np.clip(1.0 - np.minimum(r_lf1, r_lf2), 0.0, 1.0) ** 1.2 * 0.65
                alb = alb * (1.0 - fl_mask[..., None]) + flower_col[None, None, :] * fl_mask[..., None]
                alb = alb * (1.0 - lf_mask[..., None]) + leaf_col[None, None, :] * lf_mask[..., None]

        # Aged yellowing & top/bottom heat darkening
        edge_burn = np.clip(1.0 - 0.14 * np.exp(-((v - 0.5) * 2.1) ** 2), 0.80, 1.0)
        maps["alb"] = np.clip(alb * edge_burn[..., None], 40.0, 225.0)
        maps["rough"] = np.clip(maps["rough"], 0.78, 0.94)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)
    elif idx in (1, 3):
        brass_path = KIT_ROOT / "assets" / "materials" / "tarnished_brass" / "textures"
        alb_b = np.asarray(
            Image.open(brass_path / "tarnished_brass_albedo.png")
            .convert("RGB")
            .resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        orm_b = np.asarray(
            Image.open(brass_path / "tarnished_brass_orm.png")
            .convert("RGB")
            .resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        ) / 255.0
        tint = np.array([0.82, 0.80, 0.56], dtype=np.float32) if idx == 1 else np.array([0.55, 0.52, 0.40], dtype=np.float32)
        maps["alb"] = np.clip(alb_b * tint[None, None, :] * 0.72 + maps["alb"] * 0.28, 32.0, 220.0)
        maps["rough"] = np.clip(orm_b[..., 1] * 0.65 + 0.18, 0.28, 0.68)
        maps["ao"] = np.clip(orm_b[..., 0], 0.50, 1.0)


def build(kit: Kit) -> None:
    """Build standing floor lamp (Blender Z up, min_z=0, total H=1.58m)."""
    # 1. Weighted stepped round base + lower turned stem + baluster + upper neck + finial
    # Profile (radius, z) lofted with 14 segments
    stem_profile = [
        (0.165, 0.000),
        (0.165, 0.016),
        (0.145, 0.028),
        (0.105, 0.036),
        (0.095, 0.048),
        (0.042, 0.062),
        (0.022, 0.088),
        (0.017, 0.140),
        (0.016, 0.880),
        (0.028, 0.915),  # Turned decorative baluster collar
        (0.016, 0.945),
        (0.024, 0.968),
        (0.012, 0.990),
        (0.011, 1.240),  # Upper slender stem entering shade
    ]
    rings = [ellipse(0.0, 0.0, z, r * 2.0, r * 2.0, n=14) for r, z in stem_profile]
    kit.loft(rings, 1, cap_start=True, cap_end=True)

    # 2. Lamp socket + frosted bulb inside shade
    kit.cyl((0.0, 0.0, 1.275), (0, 0, 1), 0.018, 0.070, 10, 3)
    bulb_rings = [
        ellipse(0.0, 0.0, 1.310, 0.034, 0.034, n=10),
        ellipse(0.0, 0.0, 1.350, 0.062, 0.062, n=10),
        ellipse(0.0, 0.0, 1.385, 0.052, 0.052, n=10),
        ellipse(0.0, 0.0, 1.405, 0.022, 0.022, n=10),
    ]
    kit.loft(bulb_rings, 2, cap_start=False, cap_end=True)

    # 3. Three-spoke wire spider & central harp rod up to top finial
    for k in range(3):
        ang = math.radians(k * 120.0)
        cx, cy = math.cos(ang), math.sin(ang)
        kit.tube(
            [(0.0, 0.0, 1.505), (cx * 0.096, cy * 0.096, 1.505)],
            0.004,
            5,
            3,
        )
    kit.cyl((0.0, 0.0, 1.455), (0, 0, 1), 0.005, 0.140, 6, 3)

    # 4. Top turned finial (z: 1.515..1.580 -> exact 1.58m H)
    finial_rings = [
        ellipse(0.0, 0.0, 1.515, 0.030, 0.030, n=10),
        ellipse(0.0, 0.0, 1.535, 0.014, 0.014, n=10),
        ellipse(0.0, 0.0, 1.560, 0.024, 0.024, n=10),
        ellipse(0.0, 0.0, 1.580, 0.008, 0.008, n=10),
    ]
    kit.loft(finial_rings, 1, cap_start=True, cap_end=True)

    # 5. Hollow flared cloth lampshade (z: 1.150..1.522) with rolled lower/upper trim
    # Closed manifold loop: outer wall (bottom->top), top rim, inner wall (top->bottom), bottom rim
    shade_loop = [
        # Outer wall
        (0.222, 1.150, 0),
        (0.226, 1.164, 0),
        (0.214, 1.175, 0),
        (0.112, 1.512, 0),
        (0.104, 1.522, 0),
        # Inner wall
        (0.096, 1.516, 2),
        (0.206, 1.172, 2),
        (0.214, 1.154, 2),
        (0.222, 1.150, 0),
    ]
    shade_rings = [ellipse(0.0, 0.0, z, r * 2.0, r * 2.0, n=20) for r, z, _ in shade_loop]
    strip_regions = [shade_loop[i][2] for i in range(len(shade_loop) - 1)]
    kit.loft(shade_rings, strip_regions, cap_start=False, cap_end=False)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_lamp)
