"""Procedural Industrial Wall Vent Louver (0.62m H).

Matches references /home/dkd/Downloads/hl2_refs/2026-10-29_18-26_4.png and
/home/dkd/Downloads/hl2_refs/2026-10-31_15-51_1.png:
- Recessed painted steel duct housing & dark soot-stained plenum cavity
- Perimeter mounting flange with overhanging top rain lip & 10 perimeter screw heads
- 9 angled horizontal weatherproof louver blades + recessed vertical center mullion
- 2048x2048 PBR atlas (painted steel frame, louver blades, dark plenum, rusted screws)

Usage:
    /usr/bin/python3 tools/blender/props/wall_vent_louver.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/wall_vent_louver.py
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
    "slug": "wall_vent_louver",
    "node_name": "WallVentLouver",
    "mat_name": "M_WallVentLouver",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-29_18-26_4.png",
    "tri_budget": 1100,
    "body": "static",
    "seed": 18264,
    "regions": [
        # 0: Weathered painted olive-gray steel duct frame & perimeter flange
        {
            "base": (112, 114, 102),
            "var": 0.11,
            "grime": 0.44,
            "rust": 0.25,
            "rough": 0.56,
            "metal": 0.64,
            "normal": 2.2,
        },
        # 1: Chipped darker painted steel louver slats
        {
            "base": (88, 92, 84),
            "var": 0.12,
            "grime": 0.48,
            "rust": 0.30,
            "rough": 0.54,
            "metal": 0.72,
            "normal": 2.2,
        },
        # 2: Dark soot-stained recessed duct plenum cavity
        {
            "base": (36, 38, 36),
            "var": 0.08,
            "grime": 0.65,
            "rust": 0.18,
            "rough": 0.80,
            "metal": 0.42,
            "normal": 2.0,
        },
        # 3: Rusted steel perimeter screws & rivets
        {
            "base": (132, 126, 116),
            "var": 0.10,
            "grime": 0.32,
            "rust": 0.38,
            "rough": 0.46,
            "metal": 0.82,
            "normal": 1.8,
        },
    ],
}


def _paint_louver(idx: int, maps: dict, half: int) -> None:
    """Add vertical rain/soot grime streaks on frame (0) and edge-chip highlights on slats (1)."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(18264 + idx * 17)
    if idx in (0, 1):
        streak_grid = rng.random((12, 96)).astype(np.float32)
        streaks = np.asarray(
            Image.fromarray(streak_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        dark = 0.82 + 0.26 * streaks
        maps["alb"] = np.clip(maps["alb"] * dark[..., None], 30.0, 232.0)
        maps["rough"] = np.clip(maps["rough"] + 0.08 * (1.0 - streaks), 0.34, 0.92)


def _angled_box(
    kit: Kit,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    tilt_deg: float,
    region: int,
) -> None:
    """Add a box rotated around the local X axis."""
    from mathutils import Matrix, Vector

    bmesh = kit.bmesh
    before = set(kit.bm.faces)
    ret = bmesh.ops.create_cube(kit.bm, size=1.0)
    verts = ret["verts"]
    xf = (
        Matrix.Translation(Vector(center))
        @ Matrix.Rotation(math.radians(tilt_deg), 4, "X")
        @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    )
    bmesh.ops.transform(kit.bm, matrix=xf, verts=verts)
    for f in kit.bm.faces:
        if f not in before:
            f.material_index = region


def build(kit: Kit) -> None:
    """Build wall vent louver (0.62m H, front facing -Y, rear duct sleeve toward +Y)."""
    outer_w = 0.56
    outer_h = 0.62
    flange_w = 0.050
    flange_t = 0.016
    inner_w = outer_w - 2.0 * flange_w  # 0.46m
    inner_h = outer_h - 2.0 * flange_w  # 0.52m
    sleeve_t = 0.022
    sleeve_d = 0.120

    # 1. Perimeter front mounting flange (y in [-0.016, 0.0]) with chamfered outer rim
    fy = -flange_t * 0.5
    kit.box((0.0, fy, outer_h - flange_w * 0.5), (outer_w, flange_t, flange_w), 0, bevel=0.003)
    kit.box((0.0, fy, flange_w * 0.5), (outer_w, flange_t, flange_w), 0, bevel=0.003)
    kit.box((-(inner_w * 0.5 + flange_w * 0.5), fy, outer_h * 0.5), (flange_w, flange_t, inner_h), 0, bevel=0.003)
    kit.box((+(inner_w * 0.5 + flange_w * 0.5), fy, outer_h * 0.5), (flange_w, flange_t, inner_h), 0, bevel=0.003)

    # Top overhanging weather drip hood lip
    kit.box((0.0, -0.014, outer_h - 0.008), (outer_w + 0.012, 0.028, 0.016), 0, bevel=0.003)

    # 2. Recessed duct housing sleeve & dark plenum back plate (y in [0.0, sleeve_d])
    sy = sleeve_d * 0.5
    box_w = inner_w + 2.0 * sleeve_t
    kit.box((0.0, sy, outer_h - flange_w + sleeve_t * 0.5), (box_w, sleeve_d, sleeve_t), 0)
    kit.box((0.0, sy, flange_w - sleeve_t * 0.5), (box_w, sleeve_d, sleeve_t), 0)
    kit.box((-(inner_w * 0.5 + sleeve_t * 0.5), sy, outer_h * 0.5), (sleeve_t, sleeve_d, inner_h), 0)
    kit.box((+(inner_w * 0.5 + sleeve_t * 0.5), sy, outer_h * 0.5), (sleeve_t, sleeve_d, inner_h), 0)

    # Dark recessed interior duct baffle/backing
    kit.box((0.0, sleeve_d - 0.012, outer_h * 0.5), (inner_w, 0.024, inner_h), 2)
    # Recessed vertical center stiffener mullion behind louver slats
    kit.box((0.0, 0.046, outer_h * 0.5), (0.020, 0.016, inner_h), 2)

    # 3. Nine angled horizontal louver slats tilted downward toward -Y front
    n_slats = 9
    z_start = flange_w + 0.036
    z_end = outer_h - flange_w - 0.036
    for i in range(n_slats):
        t = float(i) / float(n_slats - 1)
        sz = z_start + t * (z_end - z_start)
        _angled_box(kit, (0.0, 0.016, sz), (inner_w - 0.004, 0.048, 0.007), tilt_deg=36.0, region=1)

    # 4. Perimeter screw heads (3 top, 3 bottom, 2 left, 2 right)
    screw_y = -flange_t - 0.003
    for sx in (-0.248, 0.0, 0.248):
        kit.cyl((sx, screw_y, outer_h - 0.026), (0, 1, 0), 0.0075, 0.006, 6, 3)
        kit.cyl((sx, screw_y, 0.025), (0, 1, 0), 0.0075, 0.006, 6, 3)
    for sz in (0.21, 0.41):
        kit.cyl((-0.255, screw_y, sz), (0, 1, 0), 0.0075, 0.006, 6, 3)
        kit.cyl((+0.255, screw_y, sz), (0, 1, 0), 0.0075, 0.006, 6, 3)


if __name__ == "__main__":
    run_prop(CFG, build, _paint_louver)
