"""Procedural Weathered Railway Chevron Marker Sign (0.95m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-20_1.png (chamfered yellow/black chevron plate)
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-21_2.png (heavy low steel trackside stand)

Features:
- Heavy rusted steel twin-skid base stand with bolted crossbars & diagonal A-braces
- Chamfered-corner weathered yellow steel sign plate with bold black downward chevron
- Rear stiffening ribs, U-bolt clamp brackets, and carriage bolts
- 2048x2048 PBR atlas (rusted frame steel, weathered yellow/black chevron decal, iron hardware)

Usage:
    /usr/bin/python3 tools/blender/props/rail_chevron_sign.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/rail_chevron_sign.py
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
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-20_1.png"
TARGET_H: float = 0.95


def _chevron_plate_decal(img, rng) -> None:
    """Paint weathered industrial yellow railway plate with bold black downward V-chevron."""
    import numpy as np
    from PIL import Image, ImageDraw

    w, h = img.size
    draw = ImageDraw.Draw(img)

    # Subtle dark border frame wear
    draw.rectangle([0, 0, w - 1, h - 1], outline=(84, 60, 36), width=14)

    # Bold downward-pointing black V-chevron matching 2026-10-30_18-20_1.png
    pad_x = int(w * 0.13)
    top_y = int(h * 0.19)
    arm_h = int(h * 0.30)
    tip_y = int(h * 0.78)
    mid_x = w // 2
    chevron_poly = [
        (pad_x, top_y),
        (mid_x, top_y + int(h * 0.29)),
        (w - pad_x, top_y),
        (w - pad_x, top_y + arm_h),
        (mid_x, tip_y),
        (pad_x, top_y + arm_h),
    ]
    draw.polygon(chevron_poly, fill=(38, 40, 36))

    # Scratches & rust edge chipping across paint and chevron
    for _ in range(95):
        x0 = int(rng.integers(0, w))
        y0 = int(rng.integers(0, h))
        ang = float(rng.uniform(-0.8, 0.8))
        ln = int(rng.integers(25, 160))
        x1 = x0 + int(ln * math.cos(ang))
        y1 = y0 + int(ln * math.sin(ang))
        col = (94, 68, 42) if rng.random() < 0.6 else (212, 184, 96)
        draw.line([(x0, y0), (x1, y1)], fill=col, width=int(rng.integers(1, 4)))

    # Edge rust blotches around perimeter & corner bolt zones
    arr = np.asarray(img, dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    xn = xx / float(w)
    yn = yy / float(h)
    edge_dist = np.minimum(np.minimum(xn, 1.0 - xn), np.minimum(yn, 1.0 - yn))
    edge_rust = np.clip((0.085 - edge_dist) / 0.085, 0.0, 1.0)
    noise = rng.random((h // 8, w // 8)).astype(np.float32)
    noise_full = np.asarray(
        Image.fromarray(noise).resize((w, h), Image.Resampling.BICUBIC), dtype=np.float32
    )
    rust_mask = np.clip((edge_rust * 0.85 + (noise_full - 0.45) * 0.7) * (edge_dist < 0.15), 0.0, 0.85)
    rust_col = np.array([76.0, 48.0, 30.0], dtype=np.float32)
    arr = arr * (1.0 - rust_mask[..., None]) + rust_col[None, None, :] * rust_mask[..., None]

    # Vertical rainwater grime streaks from top
    streak = np.clip((0.28 - yn) / 0.28, 0.0, 1.0) * 0.22 * noise_full
    arr *= (1.0 - streak[..., None])

    img.paste(Image.fromarray(np.clip(arr, 30, 240).astype(np.uint8), mode="RGB"))


def _add_chamfered_plate(
    b: Builder,
    cx: float,
    cy: float,
    cz: float,
    w: float,
    h: float,
    thick: float,
    chamfer: float,
    tilt_deg: float,
    front_region: int,
    back_region: int,
) -> None:
    """Build 8-sided chamfered rectangular metal plate rotated around X by tilt_deg."""
    from mathutils import Vector

    hw = w * 0.5
    hh = h * 0.5
    ht = thick * 0.5
    ch = chamfer
    # CCW profile in local XZ when viewed from -Y
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
    rm = rx(tilt_deg)
    cvec = Vector((cx, cy, cz))

    vf = [b.bm.verts.new(cvec + rm @ Vector((px, -ht, pz))) for px, pz in pts_xz]
    vb = [b.bm.verts.new(cvec + rm @ Vector((px, ht, pz))) for px, pz in pts_xz]

    # Front face mapped directly [0..1] onto front_region
    f_front = b.bm.faces.new(vf)
    f_front.smooth = False
    for loop, (px, pz) in zip(f_front.loops, pts_xz):
        u = 0.02 + ((px + hw) / w) * 0.96
        v = 0.02 + ((pz + hh) / h) * 0.96
        loop[b.uv].uv = b.tile_uv(front_region, u, v)

    # Back face mapped to back_region
    b._face(list(reversed(vb)), back_region, False, None, None)

    # Perimeter thickness strips
    n = len(pts_xz)
    for i in range(n):
        j = (i + 1) % n
        b._face([vf[i], vb[i], vb[j], vf[j]], back_region, False, None, None)


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Heavy dark rusted steel (base skids, A-frame stand, plate back)
    # 1 = Weathered yellow/black chevron plate decal
    # 2 = Dark forged iron hardware (bolts, gussets, clamp brackets)

    # 1. Twin heavy rusted steel base skids on ground (z = 0.0 .. 0.055m, min_z = 0.0)
    skid_len = 0.64
    skid_w = 0.085
    skid_h = 0.055
    for sx in (-0.21, 0.21):
        b.add_box(Vector((sx, 0.02, skid_h * 0.5)), (skid_w, skid_len, skid_h), region=0)
        # Beveled front/rear skid end-caps
        b.add_box(Vector((sx, -0.295, 0.022)), (skid_w * 0.92, 0.04, 0.036), region=2)
        b.add_box(Vector((sx, 0.335, 0.022)), (skid_w * 0.92, 0.04, 0.036), region=2)

    # 2. Front & rear heavy cross-tie beams + corner gusset pads
    for cy in (-0.16, 0.22):
        b.add_box(Vector((0.0, cy, 0.075)), (0.52, 0.060, 0.042), region=0)
        for sx in (-0.21, 0.21):
            b.add_cyl(Vector((sx, cy, 0.104)), 0.014, 0.018, region=2, segs=6)

    # 3. Main vertical/slightly-raked steel posts & diagonal rear A-frame braces
    tilt_deg = -7.0  # tilts top backward (+Y) slightly for trackside readability
    post_h = 0.72
    for sx in (-0.16, 0.16):
        # Main front upright post
        b.add_box(Vector((sx, -0.055, 0.43)), (0.036, 0.036, post_h), region=0, rot=rx(tilt_deg))
        # Rear diagonal brace strut from rear crossbar (y=0.22, z=0.09) to upper post (y=-0.02, z=0.60)
        dy = 0.22 - (-0.01)
        dz = 0.60 - 0.09
        diag_len = math.hypot(dy, dz)
        diag_ang = math.degrees(math.atan2(dy, dz))
        b.add_box(
            Vector((sx, 0.105, 0.345)),
            (0.030, 0.030, diag_len),
            region=0,
            rot=rx(diag_ang),
        )
        # Stiffener gusset bracket at post base
        b.add_box(Vector((sx, -0.085, 0.125)), (0.046, 0.065, 0.055), region=2)

    # Rear horizontal tie-bar between diagonal struts
    b.add_box(Vector((0.0, 0.125, 0.31)), (0.35, 0.028, 0.028), region=0)

    # 4. Two horizontal steel mounting bars behind the sign plate
    for bz, by in ((0.41, -0.072), (0.71, -0.035)):
        b.add_box(Vector((0.0, by, bz)), (0.48, 0.028, 0.032), region=0, rot=rx(tilt_deg))
        for sx in (-0.16, 0.16):
            # U-clamp collar on rear of rail
            b.add_box(Vector((sx, by + 0.022, bz)), (0.052, 0.020, 0.048), region=2, rot=rx(tilt_deg))

    # 5. Chamfered-corner weathered yellow/black chevron plate (top hits z = 0.95m)
    plate_w = 0.60
    plate_h = 0.65
    plate_cz = 0.625
    plate_cy = -0.075
    _add_chamfered_plate(
        b,
        cx=0.0,
        cy=plate_cy,
        cz=plate_cz,
        w=plate_w,
        h=plate_h,
        thick=0.014,
        chamfer=0.075,
        tilt_deg=tilt_deg,
        front_region=1,
        back_region=0,
    )

    # 4 front carriage bolt heads attaching plate to horizontal mounting bars
    rm = rx(tilt_deg)
    for sx in (-0.16, 0.16):
        for local_z in (-0.21, 0.09):
            bolt_pos = Vector((sx, plate_cy, plate_cz)) + rm @ Vector((0.0, -0.010, local_z))
            b.add_cyl(bolt_pos, 0.013, 0.012, region=2, segs=6, rot=rx(90.0 + tilt_deg))


SPEC = PropSpec(
    slug="rail_chevron_sign",
    node_name="RailChevronSign",
    mat_name="M_RailChevronSign",
    ref_image=REF_IMAGE,
    target_h=TARGET_H,
    tri_budget=800,
    body="static",
    seed=1821,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="steel", rgb=(74, 46, 34), wear=0.72, rough=0.72, metal=0.55, nrm=0.90),
        Region(kind="paint", rgb=(204, 162, 44), wear=0.52, rough=0.52, metal=0.22, nrm=0.65, decal=_chevron_plate_decal),
        Region(kind="steel", rgb=(48, 44, 42), wear=0.55, rough=0.62, metal=0.68, nrm=0.80),
    ],
    build=_build,
    collision=[
        ("CollisionShape3D", (0.60, 0.95, 0.68), (0.0, 0.475, 0.02)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
