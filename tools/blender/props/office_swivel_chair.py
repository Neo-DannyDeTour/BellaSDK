"""Procedural Post-Soviet Office Swivel Chair (0.90m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-53.png:
- 5-star angled steel base with dual-wheel casters grounded at min_y = 0
- Telescoping gas cylinder column + under-seat tilt mechanism & rear spine bracket
- Thick beveled/rounded padded seat cushion with worn dark center stain
- Curved, tapered shield-shaped padded backrest tilted slightly backward
- 2048x2048 PBR atlas (stained olive-gray fabric + matte charcoal steel + chrome shaft)

Usage:
    /usr/bin/python3 tools/blender/props/office_swivel_chair.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/office_swivel_chair.py
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
    rrect_ring,
    rx,
    ry,
    rz,
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-53.png"


def _seat_stain_decal(img, rng) -> None:
    """Paint dark central hand/body wear stain onto the seat/backrest fabric tile."""
    import numpy as np
    from PIL import Image

    arr = np.asarray(img, dtype=np.float32)
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    yn = (yy / float(h) - 0.50) / 0.28
    xn = (xx / float(w) - 0.50) / 0.26
    r2 = xn * xn + yn * yn
    stain = np.exp(-r2 * 1.45) * 0.52
    # Add irregular organic edge to stain
    edge_noise = rng.random((24, 24)).astype(np.float32)
    noise_full = np.asarray(
        Image.fromarray(edge_noise).resize((w, h), Image.Resampling.BICUBIC),
        dtype=np.float32,
    )
    stain = np.clip(stain * (0.75 + 0.50 * noise_full), 0.0, 0.58)
    arr *= (1.0 - stain[..., None])
    # Warm dark grime tint in center
    arr[..., 0] *= (1.0 - stain * 0.08)
    arr[..., 2] *= (1.0 - stain * 0.22)
    img.paste(Image.fromarray(np.clip(arr, 30, 240).astype(np.uint8), mode="RGB"))


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Seat top/cushion fabric with central grime stain
    # 1 = General weathered olive-gray upholstery fabric (sides/backrest)
    # 2 = Matte dark charcoal painted steel (5-star legs, bracket, spine, casters)
    # 3 = Scuffed bare steel / chrome (upper gas piston shaft)

    # 1. 5-star caster base (min_z = 0.0 at caster wheel bottom)
    wheel_r = 0.022
    wheel_w = 0.030
    leg_tip_r = 0.268
    hub_r = 0.040
    hub_z0 = 0.082
    hub_z1 = 0.145
    b.add_cyl(Vector((0.0, 0.0, (hub_z0 + hub_z1) * 0.5)), hub_r, hub_z1 - hub_z0, region=2, segs=10)

    for i in range(5):
        ang = math.radians(90.0 + i * 72.0)
        ca, sa = math.cos(ang), math.sin(ang)
        fwd = Vector((ca, sa, 0.0))
        side = Vector((-sa, ca, 0.0))

        # Tapered leg arm from hub down to caster socket
        p0 = fwd * (hub_r * 0.72) + Vector((0.0, 0.0, 0.116))
        p1 = fwd * leg_tip_r + Vector((0.0, 0.0, 0.056))
        r0 = [
            p0 - side * 0.017 - Vector((0.0, 0.0, 0.016)),
            p0 + side * 0.017 - Vector((0.0, 0.0, 0.016)),
            p0 + side * 0.015 + Vector((0.0, 0.0, 0.016)),
            p0 - side * 0.015 + Vector((0.0, 0.0, 0.016)),
        ]
        r1 = [
            p1 - side * 0.012 - Vector((0.0, 0.0, 0.011)),
            p1 + side * 0.012 - Vector((0.0, 0.0, 0.011)),
            p1 + side * 0.011 + Vector((0.0, 0.0, 0.011)),
            p1 - side * 0.011 + Vector((0.0, 0.0, 0.011)),
        ]
        b.add_loft([r0, r1], region=2, caps=(False, True), smooth=False)

        # Caster socket + wheel touching z = 0.0
        tip_xy = fwd * (leg_tip_r - 0.008)
        b.add_box(tip_xy + Vector((0.0, 0.0, 0.039)), (0.024, 0.024, 0.018), region=2, rot=rz(math.degrees(ang)))
        b.add_cyl(
            tip_xy + Vector((0.0, 0.0, wheel_r)),
            wheel_r,
            wheel_w,
            region=2,
            segs=8,
            rot=rz(math.degrees(ang)) @ ry(90.0),
        )

    # 2. Gas cylinder column (outer dark sleeve + inner steel shaft + collar)
    b.add_cyl(Vector((0.0, 0.0, 0.225)), 0.025, 0.180, region=2, segs=10)
    b.add_cyl(Vector((0.0, 0.0, 0.315)), 0.029, 0.018, region=2, segs=10)
    b.add_cyl(Vector((0.0, 0.0, 0.365)), 0.017, 0.090, region=3, segs=10)

    # 3. Under-seat mechanism + rear spine bracket (+Y is back)
    b.add_box(Vector((0.0, 0.015, 0.415)), (0.140, 0.200, 0.042), region=2)
    # Rear pivot joint + adjustment knob behind seat
    b.add_box(Vector((0.0, 0.220, 0.422)), (0.056, 0.090, 0.048), region=2)
    b.add_cyl(Vector((0.0, 0.272, 0.422)), 0.022, 0.028, region=2, segs=8, rot=rx(90.0))

    # Curved steel backrest spine bar rising from pivot up behind backrest
    spine_pts = [
        (Vector((0.0, 0.245, 0.420)), 0.038, 0.024),
        (Vector((0.0, 0.268, 0.520)), 0.036, 0.022),
        (Vector((0.0, 0.262, 0.675)), 0.034, 0.020),
        (Vector((0.0, 0.275, 0.775)), 0.034, 0.018),
    ]
    spine_rings = []
    for pt, sw, sd in spine_pts:
        hw, hd = sw * 0.5, sd * 0.5
        spine_rings.append([
            pt + Vector((-hw, -hd, 0.0)),
            pt + Vector((+hw, -hd, 0.0)),
            pt + Vector((+hw, +hd, 0.0)),
            pt + Vector((-hw, +hd, 0.0)),
        ])
    b.add_loft(spine_rings, region=2, caps=(True, True), smooth=False)

    # 4. Padded seat cushion (rounded beveled rectangle, front -Y, z = 0.432..0.506)
    seat_w, seat_d = 0.450, 0.445
    seat_rings = [
        rrect_ring(0.0, 0.0, seat_w, seat_d, 0.065, 2, 0.432, shrink=0.024),
        rrect_ring(0.0, 0.0, seat_w, seat_d, 0.065, 2, 0.452, shrink=0.0),
        rrect_ring(0.0, 0.0, seat_w, seat_d, 0.065, 2, 0.488, shrink=0.0),
        rrect_ring(0.0, 0.0, seat_w, seat_d, 0.065, 2, 0.506, shrink=0.026),
    ]
    b.add_loft(seat_rings, region=1, caps=(True, False), smooth=True)
    top_ring = seat_rings[-1]
    top_uvs = [((p.x / seat_w) + 0.5, (p.y / seat_d) + 0.5) for p in top_ring]
    b.add_quad(top_ring, region=0, uvs=top_uvs)

    # 5. Contoured curved backrest (tapered arched shield, concave on -Y front)
    # 6 horizontal rows (z) x 5 columns (x) -> front/back faces + perimeter
    rows = [
        # (z, half_width, y_center, curve_depth)
        (0.570, 0.168, 0.228, 0.028),
        (0.630, 0.198, 0.236, 0.032),
        (0.745, 0.190, 0.248, 0.034),
        (0.835, 0.168, 0.257, 0.030),
        (0.878, 0.140, 0.261, 0.025),
        (0.900, 0.098, 0.264, 0.020),
    ]
    cols_t = [-1.0, -0.5, 0.0, 0.5, 1.0]
    thick = 0.052

    front_grid: list[list] = []
    back_grid: list[list] = []
    for r_idx, (rz_val, hw, yc, curve_d) in enumerate(rows):
        f_row = []
        b_row = []
        # Taper thickness slightly near top & outer edges for cushioned bevel look
        edge_bevel = 0.65 if r_idx in (0, len(rows) - 1) else 1.0
        for c_idx, tx in enumerate(cols_t):
            x = tx * hw
            # Parabolic curve: center sits further back (+Y), sides wrap forward (-Y)
            y_curve = yc - curve_d * (tx * tx)
            col_t = thick * edge_bevel * (0.72 if abs(tx) > 0.9 else 1.0)
            f_row.append(b.bm.verts.new(Vector((x, y_curve - col_t * 0.5, rz_val))))
            b_row.append(b.bm.verts.new(Vector((x, y_curve + col_t * 0.5, rz_val))))
        front_grid.append(f_row)
        back_grid.append(b_row)

    def _uv_back(tx_i: int, rz_i: int) -> tuple[float, float]:
        u = (cols_t[tx_i] + 1.0) * 0.42 + 0.08
        v = (rows[rz_i][0] - 0.570) / 0.330 * 0.84 + 0.08
        return b.tile_uv(0, u, v)

    nr, nc = len(rows), len(cols_t)
    for r_i in range(nr - 1):
        for c_i in range(nc - 1):
            # Front (-Y) face: CCW from -Y is (bl, br, tr, tl)
            ff = b.bm.faces.new([
                front_grid[r_i][c_i],
                front_grid[r_i][c_i + 1],
                front_grid[r_i + 1][c_i + 1],
                front_grid[r_i + 1][c_i],
            ])
            ff.smooth = True
            for lp, (ti, ri) in zip(ff.loops, [(c_i, r_i), (c_i + 1, r_i), (c_i + 1, r_i + 1), (c_i, r_i + 1)]):
                lp[b.uv].uv = _uv_back(ti, ri)

            # Back (+Y) face: CCW from +Y is (br, bl, tl, tr)
            bf = b.bm.faces.new([
                back_grid[r_i][c_i + 1],
                back_grid[r_i][c_i],
                back_grid[r_i + 1][c_i],
                back_grid[r_i + 1][c_i + 1],
            ])
            bf.smooth = True
            for lp, (ti, ri) in zip(bf.loops, [(c_i + 1, r_i), (c_i, r_i), (c_i, r_i + 1), (c_i + 1, r_i + 1)]):
                lp[b.uv].uv = b.tile_uv(1, 0.1 + 0.2 * ti, 0.1 + 0.2 * ri)

    # Perimeter rim around backrest
    perim_f = (
        [front_grid[0][c] for c in range(nc - 1)]
        + [front_grid[r][nc - 1] for r in range(nr - 1)]
        + [front_grid[nr - 1][c] for c in range(nc - 1, 0, -1)]
        + [front_grid[r][0] for r in range(nr - 1, 0, -1)]
    )
    perim_b = (
        [back_grid[0][c] for c in range(nc - 1)]
        + [back_grid[r][nc - 1] for r in range(nr - 1)]
        + [back_grid[nr - 1][c] for c in range(nc - 1, 0, -1)]
        + [back_grid[r][0] for r in range(nr - 1, 0, -1)]
    )
    np_len = len(perim_f)
    for i in range(np_len):
        j = (i + 1) % np_len
        sf = b.bm.faces.new([perim_b[i], perim_b[j], perim_f[j], perim_f[i]])
        sf.smooth = True
        for k, lp in enumerate(sf.loops):
            lp[b.uv].uv = b.tile_uv(1, 0.2 + 0.15 * (k % 2), 0.2 + 0.15 * (k // 2))


SPEC = PropSpec(
    slug="office_swivel_chair",
    node_name="OfficeSwivelChair",
    mat_name="M_OfficeSwivelChair",
    ref_image=REF_IMAGE,
    target_h=0.90,
    tri_budget=1600,
    body="rigid",
    mass=9.5,
    seed=1853,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="fabric", rgb=(126, 128, 108), wear=0.6, rough=0.88, metal=0.0, nrm=1.0, decal=_seat_stain_decal),
        Region(kind="fabric", rgb=(120, 122, 104), wear=0.5, rough=0.88, metal=0.0, nrm=1.0),
        Region(kind="paint", rgb=(44, 44, 44), wear=0.45, rough=0.50, metal=0.68, nrm=0.7),
        Region(kind="steel", rgb=(142, 144, 146), wear=0.45, rough=0.34, metal=0.88, nrm=0.6),
    ],
    build=_build,
    collision=[
        ("BaseCollisionShape", (0.54, 0.43, 0.54), (0.0, 0.215, 0.0)),
        ("SeatCollisionShape", (0.45, 0.08, 0.45), (0.0, 0.468, 0.0)),
        ("BackrestCollisionShape", (0.40, 0.34, 0.08), (0.0, 0.735, -0.24)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
