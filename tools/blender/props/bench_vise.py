"""Procedural Heavy Cast-Iron Bench Vise (0.24m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-10_19-23.png:
- Bolted circular cast-iron base flange with 3 mounting lugs & hex bolts (min_y = 0)
- Fixed rear jaw + rear anvil horn/pad + steel clamping jaw insert
- Rectangular heavy slide beam + front sliding jaw tower + steel jaw insert
- Lead screw hub, collar, and tilted sliding T-bar handle with spherical end knobs
- 2048x2048 PBR atlas (weathered petrol-blue enamel with vertical rust drips, bare steel, T-bar)

Usage:
    /usr/bin/python3 tools/blender/props/bench_vise.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/bench_vise.py
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
    "slug": "bench_vise",
    "node_name": "BenchVise",
    "mat_name": "M_BenchVise",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-11-10_19-23.png",
    "tri_budget": 1400,
    "body": "static",
    "seed": 19230,
    "regions": [
        # 0: Weathered cyan-blue enamel cast iron body (with rust streaks)
        {"base": (34, 118, 140), "var": 0.14, "grime": 0.38, "rust": 0.42, "rough": 0.48,
         "metal": 0.65, "normal": 2.4},
        # 1: Darker shaded enamel & slide beam / crevices
        {"base": (26, 84, 102), "var": 0.12, "grime": 0.44, "rust": 0.48, "rough": 0.56,
         "metal": 0.72, "normal": 2.2},
        # 2: Bare machined / scuffed steel (jaw plates, anvil face, lead screw, bolts)
        {"base": (132, 134, 136), "var": 0.10, "grime": 0.28, "rust": 0.25, "rough": 0.36,
         "metal": 0.88, "normal": 2.6},
        # 3: Worn zinc-steel T-bar handle & collar
        {"base": (182, 178, 170), "var": 0.08, "grime": 0.24, "rust": 0.16, "rough": 0.40,
         "metal": 0.84, "normal": 1.8},
    ],
}


def _paint_vise(idx: int, maps: dict, half: int) -> None:
    """Add vertical rust drip streaks on enamel (0, 1) and serrated steel grain on jaws (2)."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(19230 + idx * 41)
    if idx in (0, 1):
        # Vertical rust streaks mimicking water/oil runoff on the cast body
        col_grid = rng.random((12, 64)).astype(np.float32)
        streak = np.asarray(
            Image.fromarray(col_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        fine_grid = rng.random((96, 96)).astype(np.float32)
        pit = np.asarray(
            Image.fromarray(fine_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        rust_mask = np.clip((streak * 0.72 + pit * 0.28 - 0.56) / 0.18, 0.0, 1.0)
        rust_col = np.array([136.0, 74.0, 38.0], dtype=np.float32)
        rust_tex = rust_col[None, None, :] * (0.78 + 0.38 * pit)[..., None]

        maps["alb"] = np.clip(
            maps["alb"] * (1.0 - rust_mask[..., None]) + rust_tex * rust_mask[..., None],
            30.0,
            235.0,
        )
        maps["rough"] = np.clip(maps["rough"] + 0.34 * rust_mask, 0.38, 0.94)
        maps["metal"] = np.clip(maps["metal"] * (1.0 - 0.85 * rust_mask), 0.05, 0.85)
    elif idx == 2:
        # Fine machined cross-hatch / serrations on steel jaw plates & anvil pad
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        serr = 0.5 + 0.5 * np.sin(xx * (2.0 * math.pi / 22.0)) * np.sin(yy * (2.0 * math.pi / 22.0))
        maps["alb"] = np.clip(maps["alb"] * (0.86 + 0.24 * serr[..., None]), 45.0, 225.0)
        maps["rough"] = np.clip(0.32 + 0.16 * (1.0 - serr), 0.22, 0.65)
        h = 0.5 * serr
        gy, gx = np.gradient(h)
        nrm = np.stack([-gx * 2.8, gy * 2.8, np.ones_like(h)], axis=-1)
        nrm /= np.sqrt(np.sum(nrm * nrm, axis=-1, keepdims=True))
        maps["nrm"] = nrm


def _add_sphere_knob(kit: Kit, center: tuple[float, float, float], radius: float, region: int) -> None:
    """Add a low-poly sphere knob for the T-bar handle ends."""
    from mathutils import Matrix, Vector

    before = set(kit.bm.faces)
    kit.bmesh.ops.create_uvsphere(
        kit.bm,
        u_segments=10,
        v_segments=6,
        radius=radius,
        matrix=Matrix.Translation(Vector(center)),
    )
    for f in kit.bm.faces:
        if f not in before:
            f.material_index = region


def _build_vise(kit: Kit) -> None:
    """Build grounded 0.24m cast-iron bench vise (+Z up, -Y front)."""
    from mathutils import Vector

    # 1. Circular swivel/bolt base flange (z = 0.0 .. 0.030m)
    kit.cyl((0.0, 0.0, 0.011), (0.0, 0.0, 1.0), 0.098, 0.022, segs=16, region=0)
    kit.cyl((0.0, 0.0, 0.027), (0.0, 0.0, 1.0), 0.084, 0.010, segs=16, region=0, radius2=0.076)

    # 3 mounting lugs + hex bolts (2 front-angled, 1 rear)
    for ang_deg in (215.0, 325.0, 90.0):
        ang = math.radians(ang_deg)
        lx = math.cos(ang) * 0.102
        ly = math.sin(ang) * 0.102
        kit.cyl((lx, ly, 0.010), (0.0, 0.0, 1.0), 0.024, 0.020, segs=10, region=0)
        kit.cyl((lx, ly, 0.023), (0.0, 0.0, 1.0), 0.011, 0.008, segs=6, region=2)

    # 2. Fixed Rear Jaw Tower + Slide Tunnel (y > 0)
    # Lower pedestal neck rising from base
    ped_rings = [
        rrect(0.0, 0.042, 0.030, 0.118, 0.128, 0.014, n=3),
        rrect(0.0, 0.052, 0.072, 0.098, 0.126, 0.012, n=3),
        rrect(0.0, 0.056, 0.138, 0.104, 0.132, 0.012, n=3),
    ]
    kit.loft(ped_rings, region=0)

    # Fixed jaw upper head (z = 0.138 .. 0.240m, clamping face at y = +0.012)
    fixed_rings = [
        rrect(0.0, 0.058, 0.138, 0.108, 0.092, 0.012, n=3),
        rrect(0.0, 0.054, 0.194, 0.122, 0.084, 0.012, n=3),
        rrect(0.0, 0.046, 0.228, 0.122, 0.068, 0.008, n=3),
        rrect(0.0, 0.040, 0.240, 0.116, 0.056, 0.006, n=3),
    ]
    kit.loft(fixed_rings, region=0)

    # Rear anvil horn / pad extending backward (+Y)
    anvil_rings = [
        rrect(0.0, 0.128, 0.112, 0.078, 0.046, 0.010, n=3),
        rrect(0.0, 0.138, 0.146, 0.082, 0.072, 0.012, n=3),
        rrect(0.0, 0.144, 0.158, 0.074, 0.080, 0.012, n=3),
    ]
    kit.loft(anvil_rings, region=0)
    kit.box((0.0, 0.144, 0.161), (0.068, 0.072, 0.006), region=2, bevel=0.002)

    # Fixed jaw steel clamping plate
    kit.box((0.0, 0.009, 0.218), (0.114, 0.011, 0.042), region=2, bevel=0.002)

    # 3. Heavy Rectangular Slide Bar (passes through fixed jaw to front jaw)
    kit.box((0.0, 0.015, 0.106), (0.062, 0.256, 0.046), region=1, bevel=0.004)
    # Rear slide end cap
    kit.box((0.0, 0.146, 0.106), (0.054, 0.012, 0.038), region=2, bevel=0.002)

    # 4. Sliding Front Jaw Tower (-Y side, clamping face at y = -0.024 -> 0.033m jaw gap)
    front_rings = [
        rrect(0.0, -0.106, 0.058, 0.078, 0.096, 0.014, n=3),
        rrect(0.0, -0.098, 0.108, 0.092, 0.114, 0.014, n=3),
        rrect(0.0, -0.076, 0.156, 0.108, 0.096, 0.012, n=3),
        rrect(0.0, -0.066, 0.198, 0.122, 0.082, 0.010, n=3),
        rrect(0.0, -0.056, 0.228, 0.122, 0.064, 0.008, n=3),
        rrect(0.0, -0.052, 0.240, 0.116, 0.054, 0.006, n=3),
    ]
    kit.loft(front_rings, region=0)

    # Front jaw steel clamping plate
    kit.box((0.0, -0.021, 0.218), (0.114, 0.011, 0.042), region=2, bevel=0.002)

    # 5. Lead Screw Collar, Hub & Tilted Sliding T-Bar Handle (-Y front)
    screw_z = 0.098
    kit.cyl((0.0, -0.160, screw_z), (0.0, 1.0, 0.0), 0.027, 0.016, segs=12, region=3)
    kit.cyl((0.0, -0.184, screw_z), (0.0, 1.0, 0.0), 0.020, 0.034, segs=12, region=3)
    # Visible lead screw shaft inside gap under slide
    kit.cyl((0.0, -0.060, screw_z), (0.0, 1.0, 0.0), 0.011, 0.110, segs=10, region=2)

    # Tilted sliding T-bar rod with spherical end caps
    hub_center = Vector((0.0, -0.188, screw_z))
    tilt = math.radians(17.0)
    bar_dir = Vector((math.cos(tilt), 0.0, -math.sin(tilt)))
    half_len = 0.118
    p_a = hub_center - bar_dir * half_len
    p_b = hub_center + bar_dir * half_len
    kit.cyl(tuple(hub_center), tuple(bar_dir), 0.0075, half_len * 2.0, segs=10, region=3)
    _add_sphere_knob(kit, tuple(p_a), 0.0125, region=3)
    _add_sphere_knob(kit, tuple(p_b), 0.0125, region=3)


def main() -> None:
    run_prop(CFG, _build_vise, painter=_paint_vise)


if __name__ == "__main__":
    main()
