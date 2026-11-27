"""Procedural Cast-Iron & Slatted Wood Street Bench (0.82m H, ~1.80m L).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-26_1.png:
- Heavy dark cast-iron side leg frames with foot pads (min_y = 0), curved armrests,
  backrest spines, and center under-seat support cradle + diagonal tie-braces
- 4 weathered dark teal-green painted wood seat slats + 3 angled backrest slats
- Raised carriage-bolt fastener heads along the strap lines
- 2048x2048 PBR atlas (weathered painted wood slats, wood wear variation, cast iron, bolts)

Usage:
    /usr/bin/python3 tools/blender/props/metal_street_bench.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/metal_street_bench.py
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
    "slug": "metal_street_bench",
    "node_name": "MetalStreetBench",
    "mat_name": "M_MetalStreetBench",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-30_18-26_1.png",
    "tri_budget": 1500,
    "body": "static",
    "seed": 18261,
    "regions": [
        # 0: Weathered dark petrol-teal painted timber slats (seat/back)
        {"base": (42, 76, 74), "var": 0.14, "grime": 0.34, "rust": 0.0, "rough": 0.72,
         "metal": 0.0, "normal": 2.4},
        # 1: Cast-iron legs, armrests, cradle & straps
        {"base": (48, 50, 52), "var": 0.10, "grime": 0.35, "rust": 0.28, "rough": 0.56,
         "metal": 0.72, "normal": 2.0},
        # 2: Rusted steel hardware / carriage bolts & under-frame braces
        {"base": (88, 86, 82), "var": 0.12, "grime": 0.30, "rust": 0.42, "rough": 0.48,
         "metal": 0.78, "normal": 2.0},
        # 3: Slightly sun-faded teal-slate wood plank variation
        {"base": (52, 84, 80), "var": 0.15, "grime": 0.32, "rust": 0.0, "rough": 0.75,
         "metal": 0.0, "normal": 2.4},
    ],
}


def _paint_bench(idx: int, maps: dict, half: int) -> None:
    """Add wood grain + chipped paint streaks on slat regions (0, 3) and iron pits on 1."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(18261 + idx * 31)
    if idx in (0, 3):
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        # Stretched horizontal wood grain fibers
        low_grid = rng.random((24, 6)).astype(np.float32)
        warp = np.asarray(
            Image.fromarray(low_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        fine_grid = rng.random((256, 16)).astype(np.float32)
        fiber = np.asarray(
            Image.fromarray(fine_grid, mode="F").resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        )
        grain = 0.5 + 0.5 * np.sin((yy / float(half)) * 42.0 * math.pi + warp * 5.0)
        wood_tone = np.array([104.0, 90.0, 72.0], dtype=np.float32)
        # Chipped paint revealing weathered gray-brown wood along streaks
        chip_field = 0.55 * fiber + 0.45 * grain
        chip_mask = np.clip((chip_field - 0.68) / 0.14, 0.0, 1.0) * 0.65

        alb = maps["alb"] * (0.86 + 0.22 * fiber + 0.08 * grain)[..., None]
        alb = alb * (1.0 - chip_mask[..., None]) + wood_tone[None, None, :] * chip_mask[..., None]
        maps["alb"] = np.clip(alb, 32.0, 220.0)
        maps["rough"] = np.clip(0.68 + 0.14 * (1.0 - grain) + 0.10 * chip_mask, 0.58, 0.92)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)

        h_wood = 0.45 * fiber + 0.35 * grain - 0.20 * chip_mask
        gy, gx = np.gradient(h_wood)
        nrm = np.stack([-gx * 3.2, gy * 3.2, np.ones_like(h_wood)], axis=-1)
        nrm /= np.sqrt(np.sum(nrm * nrm, axis=-1, keepdims=True))
        maps["nrm"] = nrm


def _rotated_box(
    kit: Kit,
    center: tuple[float, float, float],
    size: tuple[float, float, float],
    tilt_deg: float,
    region: int,
    bevel: float = 0.004,
) -> None:
    """Create a box rotated around local X axis (pitch in YZ plane)."""
    from mathutils import Matrix, Vector

    bmesh = kit.bmesh
    before = set(kit.bm.faces)
    ret = bmesh.ops.create_cube(kit.bm, size=1.0)
    verts = ret["verts"]
    scale_xf = Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    rot_xf = Matrix.Rotation(math.radians(tilt_deg), 4, "X")
    trans_xf = Matrix.Translation(Vector(center))
    bmesh.ops.transform(kit.bm, matrix=trans_xf @ rot_xf @ scale_xf, verts=verts)
    if bevel > 0.0:
        vset = set(verts)
        edges = [e for e in kit.bm.edges if all(v in vset for v in e.verts)]
        bmesh.ops.bevel(
            kit.bm,
            geom=edges,
            offset=bevel,
            offset_type="OFFSET",
            segments=1,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )
    for f in kit.bm.faces:
        if f not in before:
            f.material_index = region


def _rect_loft(
    kit: Kit,
    pts: list[tuple[float, float, float]],
    half_w: float,
    half_h: float,
    region: int,
) -> None:
    """Loft a rectangular cross-section bar along a YZ polyline (constant X width)."""
    from mathutils import Vector

    path = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(path):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, len(path) - 1)]
        tan = (b - a).normalized()
        # Local X is always (1, 0, 0); normal in YZ plane is tan x X
        side_x = Vector((1.0, 0.0, 0.0))
        up_yz = side_x.cross(tan).normalized()
        rings.append([
            tuple(p - side_x * half_w - up_yz * half_h),
            tuple(p + side_x * half_w - up_yz * half_h),
            tuple(p + side_x * half_w + up_yz * half_h),
            tuple(p - side_x * half_w + up_yz * half_h),
        ])
    kit.loft(rings, region, cap_start=True, cap_end=True)


def build(kit: Kit) -> None:
    """Build cast-iron & slatted wood street bench (1.80m L x 0.82m H, min_z=0)."""
    bench_len = 1.80

    # 1. Seat slats (4 planks sloping gently back ~4 deg from front y=-0.215 to y=+0.115)
    seat_tilt = 4.0
    seat_y0 = -0.215
    seat_pitch_y = 0.104
    seat_z0 = 0.430
    for idx in range(4):
        sy = seat_y0 + idx * seat_pitch_y
        sz = seat_z0 - idx * seat_pitch_y * math.tan(math.radians(seat_tilt))
        reg = 0 if idx % 2 == 0 else 3
        _rotated_box(kit, (0.0, sy, sz), (bench_len, 0.088, 0.028), seat_tilt, reg, bevel=0.004)

    # 2. Backrest slats (3 planks tilted ~16 deg back, reaching z=0.820 at top edge)
    back_tilt = 16.0
    # Top slat center placed so rotated top edge reaches z = 0.820
    # Half-height in Z of tilted 0.104m wide x 0.026m thick plank:
    # (0.052*cos(16) + 0.013*sin(16)) = 0.0536m -> center at 0.820 - 0.0536 = 0.7664m
    back_top_z = 0.7664
    back_top_y = 0.258
    back_step = 0.122
    st = math.sin(math.radians(back_tilt))
    ct = math.cos(math.radians(back_tilt))
    for idx in range(3):
        off = idx * back_step
        by = back_top_y - off * st
        bz = back_top_z - off * ct
        reg = 3 if idx % 2 == 0 else 0
        # Rotate plank upright (90 - back_tilt) so width=0.104m runs along backrest slope
        _rotated_box(
            kit,
            (0.0, by, bz),
            (bench_len, 0.026, 0.104),
            -(back_tilt),
            reg,
            bevel=0.004,
        )

    # 3. Left & right cast-iron end frames (x = +-0.76m)
    frame_xs = (-0.76, 0.76)
    for fx in frame_xs:
        # Grounded foot pads (min_z = 0.0)
        kit.box((fx, -0.235, 0.009), (0.068, 0.072, 0.018), 1, bevel=0.003)
        kit.box((fx, +0.235, 0.009), (0.068, 0.072, 0.018), 1, bevel=0.003)

        # Front leg rising from foot pad to seat cradle and continuing up to armrest post
        _rect_loft(
            kit,
            [
                (fx, -0.235, 0.016),
                (fx, -0.215, 0.220),
                (fx, -0.195, 0.415),
                (fx, -0.195, 0.595),
            ],
            half_w=0.019,
            half_h=0.021,
            region=1,
        )

        # Rear leg rising to seat rear and continuing up along backrest spine
        _rect_loft(
            kit,
            [
                (fx, +0.235, 0.016),
                (fx, +0.185, 0.220),
                (fx, +0.155, 0.395),
                (fx, +0.205, 0.580),
                (fx, +0.278, 0.805),
            ],
            half_w=0.019,
            half_h=0.021,
            region=1,
        )

        # Horizontal/sloped under-seat cradle bar joining front & rear legs
        _rect_loft(
            kit,
            [
                (fx, -0.235, 0.402),
                (fx, -0.040, 0.390),
                (fx, +0.155, 0.376),
            ],
            half_w=0.018,
            half_h=0.018,
            region=1,
        )

        # Curved/beveled cast-iron armrest connecting front post top to backrest spine
        _rect_loft(
            kit,
            [
                (fx, -0.225, 0.598),
                (fx, -0.110, 0.606),
                (fx, +0.060, 0.586),
                (fx, +0.205, 0.562),
            ],
            half_w=0.024,
            half_h=0.014,
            region=1,
        )

        # Lower decorative/structural arch gusset under seat
        _rect_loft(
            kit,
            [
                (fx, -0.210, 0.240),
                (fx, -0.010, 0.320),
                (fx, +0.180, 0.240),
            ],
            half_w=0.012,
            half_h=0.012,
            region=1,
        )

    # 4. Center steel cradle strap (x = 0.0) + under-seat diagonal tie braces
    _rect_loft(
        kit,
        [
            (0.0, -0.225, 0.402),
            (0.0, +0.150, 0.376),
            (0.0, +0.278, 0.790),
        ],
        half_w=0.015,
        half_h=0.014,
        region=2,
    )
    # Diagonal steel braces from center seat cradle down to outer side frames
    for sx in (-1.0, 1.0):
        kit.tube(
            [
                (0.0, -0.02, 0.372),
                (sx * 0.74, -0.02, 0.210),
            ],
            radius=0.012,
            segs=6,
            region=2,
        )
    # Rear longitudinal stretcher rod linking left & right frames
    kit.tube([(-0.76, 0.195, 0.185), (0.76, 0.195, 0.185)], radius=0.012, segs=6, region=2)

    # 5. Carriage bolt heads along the 3 strap lines on seat & backrest
    for bx in (-0.76, 0.0, 0.76):
        for idx in range(4):
            sy = seat_y0 + idx * seat_pitch_y
            sz = seat_z0 - idx * seat_pitch_y * math.tan(math.radians(seat_tilt)) + 0.015
            kit.box((bx, sy, sz), (0.014, 0.014, 0.008), 2)
        for idx in range(3):
            off = idx * back_step
            by = back_top_y - off * st - 0.014
            bz = back_top_z - off * ct
            kit.box((bx, by, bz), (0.014, 0.008, 0.014), 2)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_bench)
