"""Procedural Industrial 3-Compartment Galvanized Washing Trough (0.88m H, ~1.90m L).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-04_03-46_2.png:
- Open 3-compartment galvanized sheet-metal trough basin with 2 interior dividers
- Rolled tubular top edge rim along front and back walls
- Raised boxy galvanized backsplash / utility end housing (reaching exact 0.88m H)
- 4 dark weathered angle-iron legs with floor feet (min_y = 0)
- Recessed bottom drain strainers and underside drain fittings
- 2048x2048 PBR atlas (galvanized zinc spangle, stained basin interior, angle iron, brass/steel drains)

Usage:
    /usr/bin/python3 tools/blender/props/industrial_washing_trough.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/industrial_washing_trough.py
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
    "slug": "industrial_washing_trough",
    "node_name": "IndustrialWashingTrough",
    "mat_name": "M_IndustrialWashingTrough",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-11-04_03-46_2.png",
    "tri_budget": 1400,
    "body": "static",
    "seed": 11040346,
    "regions": [
        # 0: Weathered galvanized sheet metal (outer walls, rim, end housing)
        {"base": (158, 164, 166), "var": 0.13, "grime": 0.36, "rust": 0.24, "rough": 0.46,
         "metal": 0.68, "normal": 2.0},
        # 1: Stained/corroded galvanized interior basin & dividers (water line + rust patches)
        {"base": (132, 136, 134), "var": 0.14, "grime": 0.48, "rust": 0.34, "rough": 0.56,
         "metal": 0.58, "normal": 2.2},
        # 2: Dark painted/rusted structural steel angle-iron legs & mounting cleats
        {"base": (68, 70, 72), "var": 0.10, "grime": 0.34, "rust": 0.38, "rough": 0.54,
         "metal": 0.72, "normal": 2.2},
        # 3: Tarnished brass/steel drain strainers, underside tees & fasteners
        {"base": (112, 98, 76), "var": 0.12, "grime": 0.32, "rust": 0.40, "rough": 0.46,
         "metal": 0.76, "normal": 2.0},
    ],
}


def _paint_trough(idx: int, maps: dict, half: int) -> None:
    """Add smooth fine galvanized zinc mottling on sheet metal (0, 1) without blocky pixels."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(11040346 + idx * 17)
    if idx in (0, 1):
        # Soft multi-scale zinc mottling (smooth bicubic, no blocky nearest-neighbor squares)
        low = rng.random((14, 14)).astype(np.float32)
        mottle = np.asarray(
            Image.fromarray(low, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        fine = rng.random((120, 120)).astype(np.float32)
        grain = np.asarray(
            Image.fromarray(fine, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        maps["alb"] = np.clip(maps["alb"] * (0.90 + 0.14 * mottle[..., None] + 0.08 * grain[..., None]), 36.0, 236.0)
        maps["rough"] = np.clip(maps["rough"] + 0.10 * (0.5 - mottle), 0.32, 0.88)


def _add_angle_leg(kit: Kit, x: float, y: float, sx: float, sy: float, z0: float, z1: float) -> None:
    """Build an L-section steel angle-iron leg from z0 to z1 with corner at (x, y)."""
    arm = 0.048
    thick = 0.008
    h = z1 - z0
    cz = 0.5 * (z0 + z1)
    # Flange along X
    kit.box((x - sx * (arm * 0.5 - thick * 0.5), y, cz), (arm, thick, h), 2)
    # Flange along Y
    kit.box((x, y - sy * (arm * 0.5 - thick * 0.5), cz), (thick, arm, h), 2)


def build(kit: Kit) -> None:
    """Build 0.88m H (~1.90m L) 3-compartment galvanized wash trough grounded at (0, 0, 0)."""
    # Main basin spans X in [-0.95, +0.62], right raised utility/backsplash box X in [+0.62, +0.95]
    # Total X length = 1.90m; Y depth = 0.60m (-0.30 .. +0.30); Z height = 0.88m (0.0 .. 0.88m)
    x_left = -0.950
    x_right_basin = 0.620
    x_right_end = 0.950
    y_half = 0.285
    wall_t = 0.018

    z_floor_bot = 0.270
    z_floor_top = 0.295
    z_rim = 0.720
    z_splash = 0.880

    basin_len = x_right_basin - x_left  # 1.57m
    basin_cx = 0.5 * (x_left + x_right_basin)
    basin_w = y_half * 2.0  # 0.57m
    wall_h = z_rim - z_floor_top
    wall_cz = 0.5 * (z_floor_top + z_rim)

    # 1. Open galvanized basin floor + 4 perimeter walls
    kit.box((basin_cx, 0.0, 0.5 * (z_floor_bot + z_floor_top)), (basin_len, basin_w, z_floor_top - z_floor_bot), 1)
    # Front (-Y) and Rear (+Y) outer walls
    kit.box((basin_cx, -(y_half - wall_t * 0.5), wall_cz), (basin_len, wall_t, wall_h), 0)
    kit.box((basin_cx, +(y_half - wall_t * 0.5), wall_cz), (basin_len, wall_t, wall_h), 0)
    # Left (-X) end wall and Right (+X) basin end wall
    kit.box((x_left + wall_t * 0.5, 0.0, wall_cz), (wall_t, basin_w - 2.0 * wall_t, wall_h), 0)
    kit.box((x_right_basin - wall_t * 0.5, 0.0, wall_cz), (wall_t, basin_w - 2.0 * wall_t, wall_h), 0)

    # 2. Rolled tubular top rim rails along front, back, and left end
    kit.cyl((basin_cx, -y_half, z_rim + 0.008), (1.0, 0.0, 0.0), 0.018, basin_len + 0.02, 8, 0)
    kit.cyl((basin_cx, +y_half, z_rim + 0.008), (1.0, 0.0, 0.0), 0.018, basin_len + 0.02, 8, 0)
    kit.cyl((x_left, 0.0, z_rim + 0.008), (0.0, 1.0, 0.0), 0.018, basin_w + 0.02, 8, 0)

    # 3. Raised rear backsplash lip along back (+Y) edge of basin + right-end utility backsplash box
    # Rear backsplash lip (z = 0.72 -> 0.85m)
    kit.box((basin_cx, y_half - 0.008, 0.785), (basin_len, 0.018, 0.130), 0, bevel=0.004)
    # Right-end raised rounded-top galvanized utility/splashback housing (X in [0.62, 0.95], Z in [0.27, 0.88])
    kit.box((0.5 * (x_right_basin + x_right_end), 0.0, 0.5 * (z_floor_bot + z_splash)),
            (x_right_end - x_right_basin, basin_w, z_splash - z_floor_bot), 0, bevel=0.032)

    # 4. Two internal vertical compartment divider plates splitting basin into 3 equal bays
    inner_len = basin_len - 2.0 * wall_t
    bay_len = inner_len / 3.0
    for idx in (1, 2):
        dx = x_left + wall_t + idx * bay_len
        kit.box((dx, 0.0, wall_cz - 0.006), (0.016, basin_w - 2.0 * wall_t, wall_h - 0.012), 1, bevel=0.003)

    # 5. Three drain strainers inside the 3 bays + underside drain pipe manifold
    for idx in range(3):
        bx = x_left + wall_t + (idx + 0.5) * bay_len
        kit.cyl((bx, 0.0, z_floor_top + 0.004), (0.0, 0.0, 1.0), 0.038, 0.008, 10, 3)
        kit.cyl((bx, 0.0, z_floor_bot - 0.030), (0.0, 0.0, 1.0), 0.024, 0.060, 8, 3)
    # Horizontal drain collector pipe underneath basin
    kit.cyl((basin_cx, 0.0, z_floor_bot - 0.055), (1.0, 0.0, 0.0), 0.022, inner_len * 0.75, 8, 3)

    # 6. Four dark structural angle-iron legs grounded at z = 0.0
    # Mounted outside the front/back walls like in 2026-11-04_03-46_2.png
    leg_xs = (-0.54, 0.54)
    for lx in leg_xs:
        sx = -1.0 if lx < 0 else 1.0
        _add_angle_leg(kit, lx, -(y_half + 0.014), sx, -1.0, 0.0, z_rim + 0.015)
        _add_angle_leg(kit, lx, +(y_half + 0.014), sx, +1.0, 0.0, z_rim + 0.015)
        # Underside cross-tie angle brace between front & back legs
        kit.box((lx, 0.0, z_floor_bot - 0.018), (0.040, basin_w + 0.02, 0.032), 2)


if __name__ == "__main__":
    if "--gen-textures" in sys.argv:
        from tools.blender.common.domestic_kit import generate_atlas

        generate_atlas(CFG, _paint_trough)
    else:
        run_prop(CFG, build, _paint_trough)
