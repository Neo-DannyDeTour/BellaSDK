"""Procedural Railway Manual Switch Throw & Target Flag (1.35m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-21.png:
- Twin creosote/weathered sleeper base ties grounded at min_y = 0
- Flared cast-iron switch stand pedestal with bolted foot plates & central web
- Manual switch throw gear box, notched latch sector plate, & drop-down lever arm
- Tall vertical square steel rod mast rising to 1.35m
- Chamfered-corner weathered red/orange target vane bolted to upper mast
- 2048x2048 PBR atlas (cast iron, sleeper wood/steel, weathered safety orange-red vane)

Usage:
    /usr/bin/python3 tools/blender/props/rail_switch_flag.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/rail_switch_flag.py
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

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-21.png"
TARGET_H: float = 1.35


def _vane_decal(img, rng) -> None:
    """Paint weathered safety red/orange enamel target vane with edge chipping & grime."""
    import numpy as np
    from PIL import Image, ImageDraw

    w, h = img.size
    draw = ImageDraw.Draw(img)

    # Subtle dark rusted border wear
    draw.rectangle([0, 0, w - 1, h - 1], outline=(98, 42, 26), width=12)

    # Scratches & chipped enamel streaks
    for _ in range(70):
        x0 = int(rng.integers(0, w))
        y0 = int(rng.integers(0, h))
        ang = float(rng.uniform(-1.2, 1.2))
        ln = int(rng.integers(20, 130))
        x1 = x0 + int(ln * math.cos(ang))
        y1 = y0 + int(ln * math.sin(ang))
        col = (88, 44, 30) if rng.random() < 0.65 else (228, 118, 62)
        draw.line([(x0, y0), (x1, y1)], fill=col, width=int(rng.integers(1, 3)))

    arr = np.asarray(img, dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xn = xx / float(w)
    yn = yy / float(h)
    edge_dist = np.minimum(np.minimum(xn, 1.0 - xn), np.minimum(yn, 1.0 - yn))
    edge_rust = np.clip((0.075 - edge_dist) / 0.075, 0.0, 1.0)
    noise = rng.random((h // 8, w // 8)).astype(np.float32)
    noise_full = np.asarray(
        Image.fromarray(noise).resize((w, h), Image.Resampling.BICUBIC), dtype=np.float32
    )
    rust_mask = np.clip((edge_rust * 0.8 + (noise_full - 0.48) * 0.6) * (edge_dist < 0.14), 0.0, 0.82)
    rust_col = np.array([78.0, 42.0, 28.0], dtype=np.float32)
    arr = arr * (1.0 - rust_mask[..., None]) + rust_col[None, None, :] * rust_mask[..., None]

    # Subtle grime around center mounting bolts
    for by in (0.28, 0.72):
        d = np.sqrt((xn - 0.5) ** 2 + (yn - by) ** 2)
        bolt_grime = np.clip((0.08 - d) / 0.08, 0.0, 1.0) * 0.32
        arr *= (1.0 - bolt_grime[..., None])

    img.paste(Image.fromarray(np.clip(arr, 30, 240).astype(np.uint8), mode="RGB"))


def _add_chamfered_vane(
    b: Builder,
    cx: float,
    cy: float,
    cz: float,
    w: float,
    h: float,
    thick: float,
    chamfer: float,
    vane_region: int,
    edge_region: int,
) -> None:
    """Build vertical chamfered-corner target vane with both faces mapped to vane_region."""
    from mathutils import Vector

    hw = w * 0.5
    hh = h * 0.5
    ht = thick * 0.5
    ch = chamfer
    pts_xz = [
        (-hw + ch, -hh),
        (hw - ch, -hh),
        (hw, -hh + ch),
        (hw, hh - ch),
        (hw - ch, hh),
        (-hw + ch, hh),
        (-hw, hh - ch),
        (-hw, -hh + ch),
    ]
    vf = [b.bm.verts.new(Vector((cx + px, cy - ht, cz + pz))) for px, pz in pts_xz]
    vb = [b.bm.verts.new(Vector((cx + px, cy + ht, cz + pz))) for px, pz in pts_xz]

    f_front = b.bm.faces.new(vf)
    f_front.smooth = False
    for loop, (px, pz) in zip(f_front.loops, pts_xz):
        u = 0.03 + ((px + hw) / w) * 0.94
        v = 0.03 + ((pz + hh) / h) * 0.94
        loop[b.uv].uv = b.tile_uv(vane_region, u, v)

    f_back = b.bm.faces.new(list(reversed(vb)))
    f_back.smooth = False
    for loop, (px, pz) in zip(f_back.loops, reversed(pts_xz)):
        u = 0.03 + ((px + hw) / w) * 0.94
        v = 0.03 + ((pz + hh) / h) * 0.94
        loop[b.uv].uv = b.tile_uv(vane_region, u, v)

    n = len(pts_xz)
    for i in range(n):
        j = (i + 1) % n
        b._face([vf[i], vb[i], vb[j], vf[j]], edge_region, False, None, None)


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Dark cast-iron / weathered forged steel (pedestal, throw box, lever, mast)
    # 1 = Creosote weathered sleeper ties
    # 2 = Weathered safety red/orange target vane decal

    # 1. Twin base sleeper ties grounded at min_z = 0.0 (z = 0.0 .. 0.036m)
    for sx in (-0.16, 0.16):
        b.add_box(Vector((sx, 0.0, 0.018)), (0.115, 0.56, 0.036), region=1)
        # Heavy bolted steel foot pad on top of sleeper
        b.add_box(Vector((sx, 0.0, 0.048)), (0.11, 0.15, 0.024), region=0)
        for bx in (-0.035, 0.035):
            for by in (-0.05, 0.05):
                b.add_cyl(Vector((sx + bx, by, 0.065)), 0.009, 0.014, region=0, segs=6)

    # 2. Flared cast-iron switch stand pedestal (z = 0.06 .. 0.48m)
    ped_z0, ped_z1 = 0.06, 0.48
    ped_h = ped_z1 - ped_z0
    ped_cz = (ped_z0 + ped_z1) * 0.5
    # Two angled cast-iron A-legs converging toward center column
    leg_ang = math.degrees(math.atan2(0.115, ped_h))
    leg_len = math.hypot(0.115, ped_h)
    for sx in (-1.0, 1.0):
        b.add_box(
            Vector((sx * 0.095, 0.0, ped_cz)),
            (0.036, 0.095, leg_len),
            region=0,
            rot=ry(-sx * leg_ang),
        )
    # Central cast-iron web & vertical stiffener rib
    b.add_box(Vector((0.0, 0.0, 0.34)), (0.13, 0.024, 0.26), region=0)
    b.add_box(Vector((0.0, 0.0, 0.16)), (0.24, 0.024, 0.08), region=0)
    # Central vertical sleeve column anchored cleanly into lower horizontal web (z = 0.14 .. 0.48m)
    b.add_cyl(Vector((0.0, 0.0, 0.31)), 0.024, 0.34, region=0, segs=8)

    # 3. Manual switch throw box & notched latch sector (z = 0.47 .. 0.56m)
    b.add_box(Vector((0.0, 0.0, 0.485)), (0.22, 0.14, 0.026), region=0)
    b.add_box(Vector((0.0, 0.0, 0.530)), (0.12, 0.11, 0.065), region=0)
    # Side pivot bracket & drop-down weighted throw lever arm (+X side)
    b.add_box(Vector((0.08, 0.0, 0.525)), (0.06, 0.036, 0.036), region=0)
    b.add_cyl(Vector((0.115, -0.02, 0.525)), 0.016, 0.06, region=0, segs=6, rot=rx(90.0))
    # Weighted lever arm angled slightly outward & hanging down
    b.add_box(Vector((0.125, -0.02, 0.38)), (0.020, 0.024, 0.29), region=0, rot=ry(-6.0))
    # Counterweight grip bulb at bottom of lever
    b.add_cyl(Vector((0.140, -0.02, 0.23)), 0.026, 0.065, region=0, segs=8)

    # 4. Tall vertical square steel target mast rod (z = 0.56 .. 1.35m)
    mast_z0, mast_z1 = 0.56, TARGET_H
    b.add_box(Vector((0.0, 0.0, (mast_z0 + mast_z1) * 0.5)), (0.026, 0.026, mast_z1 - mast_z0), region=0)
    # Top mast finial cap
    b.add_box(Vector((0.0, 0.0, TARGET_H - 0.012)), (0.036, 0.036, 0.024), region=0)

    # 5. Weathered red/orange chamfered target vane bolted to upper mast (z = 0.87 .. 1.31m)
    vane_cz = 1.09
    _add_chamfered_vane(
        b,
        cx=0.0,
        cy=-0.020,
        cz=vane_cz,
        w=0.24,
        h=0.44,
        thick=0.012,
        chamfer=0.028,
        vane_region=2,
        edge_region=0,
    )
    # Rear clamp straps & front carriage bolts securing vane to mast
    for bz in (0.96, 1.22):
        b.add_box(Vector((0.0, 0.002, bz)), (0.048, 0.034, 0.028), region=0)
        b.add_cyl(Vector((0.0, -0.028, bz)), 0.010, 0.012, region=0, segs=6, rot=rx(90.0))


SPEC = PropSpec(
    slug="rail_switch_flag",
    node_name="RailSwitchFlag",
    mat_name="M_RailSwitchFlag",
    ref_image=REF_IMAGE,
    target_h=TARGET_H,
    tri_budget=1000,
    body="static",
    seed=18210,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="steel", rgb=(54, 54, 56), wear=0.62, rough=0.66, metal=0.66, nrm=0.85),
        Region(kind="paint", rgb=(68, 52, 38), wear=0.45, rough=0.84, metal=0.10, nrm=0.95),
        Region(kind="paint", rgb=(226, 74, 30), wear=0.48, rough=0.46, metal=0.20, nrm=0.60, decal=_vane_decal),
    ],
    build=_build,
    collision=[
        ("CollisionShape3D", (0.44, 1.35, 0.56), (0.0, 0.675, 0.0)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
