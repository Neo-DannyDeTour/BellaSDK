"""Procedural Post-Soviet Courtyard Carpet-Beating / Drying Frame (2.10m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-29_2.png:
- 4 grounded tubular steel vertical posts (2.40m span x 0.90m depth x 2.10m H)
- Twin upper longitudinal horizontal steel rails + 4 transverse overhead cross-rungs
- Lower twin rungs on each end frame + angled corner side gusset braces
- 2048x2048 PBR atlas (mottled weathered green-gray painted pipe + rusted rails/welds)

Usage:
    /usr/bin/python3 tools/blender/props/carpet_beater_frame.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/carpet_beater_frame.py
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.street_prop import (  # noqa: E402
    Builder,
    PropSpec,
    Region,
    main,
    rx,
    ry,
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-29_2.png"


def _add_strut(b: Builder, p0, p1, radius: float, segs: int, region: int) -> None:
    """Place a cylinder spanning directly between two 3D endpoints."""
    from mathutils import Vector

    a = Vector(p0)
    z = Vector(p1)
    delta = z - a
    length = delta.length
    if length < 1e-6:
        return
    mid = (a + z) * 0.5
    rot = delta.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    b.add_cyl(mid, radius, length, region=region, segs=segs, rot=rot, caps=(False, False))


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Weathered mottled green-gray painted steel pipe (vertical posts & brackets)
    # 1 = Heavily rusted & scuffed weathered steel (horizontal beating rails & rungs)
    # 2 = Oxidized dark iron weld collars & base ground sleeves

    half_w = 1.160   # 2.32m center-to-center -> ~2.40m outer width with rail ends/collars
    half_d = 0.440   # 0.88m center-to-center (~0.94m outer depth)
    post_h = 2.100
    post_r = 0.026
    rail_z = 2.010

    # 1. 4 grounded vertical corner posts (z = 0.0 .. 2.10m) + base & top clamp collars
    for sx in (-half_w, half_w):
        for sy in (-half_d, half_d):
            b.add_cyl(Vector((sx, sy, post_h * 0.5)), post_r, post_h, region=0, segs=10)
            # Ground anchor sleeve at z = 0.0
            b.add_cyl(Vector((sx, sy, 0.025)), 0.032, 0.050, region=2, segs=10)
            # Top rail clamp sleeve
            b.add_cyl(Vector((sx, sy, rail_z)), 0.033, 0.068, region=2, segs=10)

    # 2. Twin upper longitudinal horizontal rails (front & back, extending past posts to 2.40m)
    rail_len = (half_w + 0.040) * 2.0  # 2.40m total width
    for sy in (-half_d, half_d):
        b.add_cyl(Vector((0.0, sy, rail_z)), 0.019, rail_len, region=1, segs=8, rot=ry(90.0))

    # 3. 4 overhead transverse cross-bars connecting front & back rails
    cross_span = (half_d + 0.030) * 2.0
    for cx in (-half_w, -0.387, 0.387, half_w):
        b.add_cyl(Vector((cx, 0.0, rail_z)), 0.015, cross_span, region=1, segs=8, rot=rx(90.0))

    # 4. Twin lower horizontal end rungs on left & right post pairs (matching ref)
    end_span = half_d * 2.0
    for sx in (-half_w, half_w):
        for rz_val in (0.280, 0.580):
            b.add_cyl(Vector((sx, 0.0, rz_val)), 0.014, end_span, region=1, segs=8, rot=rx(90.0), caps=(False, False))

    # 5. 4 angled side corner gusset braces supporting the upper rails
    brace_drop = 0.300
    brace_run = 0.300
    for sx, dir_x in ((-half_w, 1.0), (half_w, -1.0)):
        for sy in (-half_d, half_d):
            p_post = Vector((sx, sy, rail_z - brace_drop))
            p_rail = Vector((sx + dir_x * brace_run, sy, rail_z))
            _add_strut(b, p_post, p_rail, radius=0.013, segs=6, region=0)


SPEC = PropSpec(
    slug="carpet_beater_frame",
    node_name="CarpetBeaterFrame",
    mat_name="M_CarpetBeaterFrame",
    ref_image=REF_IMAGE,
    target_h=2.10,
    tri_budget=1200,
    body="static",
    collision=[
        ("CollisionShape3D", (2.40, 2.10, 0.94), (0.0, 1.05, 0.0)),
    ],
    seed=18292,
    regions=[
        Region(kind="steel", rgb=(118, 128, 110), wear=0.62, rough=0.62, metal=0.42, nrm=1.1),
        Region(kind="steel", rgb=(134, 96, 72), wear=0.78, rough=0.72, metal=0.55, nrm=1.2),
        Region(kind="steel", rgb=(82, 74, 68), wear=0.55, rough=0.74, metal=0.50, nrm=1.0),
    ],
    build=_build,
    script_path=Path(__file__).resolve(),
)

if __name__ == "__main__":
    main(SPEC)
