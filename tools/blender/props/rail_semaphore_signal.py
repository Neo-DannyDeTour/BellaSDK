"""Procedural Railway 3-Lens Semaphore Signal (3.20m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-20.png:
- Cast concrete plinth base (grounded min_y = 0) + bolted steel flange plate
- Tall weathered dark steel H-beam mast with relay junction box & conduit
- Steel maintenance grating platform with tubular safety guardrail
- Rear steel service ladder with rungs & mast standoff brackets
- Rounded-corner 3-lens signal head box (Red / Amber / Green) with hooded visors
- 2048x2048 PBR atlas (weathered steel, charcoal housing, concrete plinth, 3 Fresnel lenses)

Usage:
    /usr/bin/python3 tools/blender/props/rail_semaphore_signal.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/rail_semaphore_signal.py
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
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-20.png"
TARGET_H: float = 3.20


def _signal_lenses_decal(img, rng) -> None:
    """Paint 3 stacked circular Fresnel railway signal lenses (Red, Amber, Green)."""
    import numpy as np
    from PIL import ImageDraw

    w, h = img.size
    draw = ImageDraw.Draw(img)
    # Dark housing rubber gasket background
    draw.rectangle([0, 0, w, h], fill=(32, 34, 36))

    # V=0..1 maps bottom->top in Blender UV; PIL y=0 is top (V=1).
    # Top band (y: 0..h/3) = Red, Mid (h/3..2h/3) = Amber, Bot (2h/3..h) = Green
    specs = [
        (0, (196, 44, 34), (234, 96, 68)),
        (1, (214, 162, 42), (238, 204, 88)),
        (2, (58, 164, 92), (108, 214, 138)),
    ]
    band_h = h // 3
    cx = w // 2
    rad = int(min(w, band_h) * 0.42)

    for idx, base_col, hot_col in specs:
        cy = idx * band_h + band_h // 2
        # Rubber seal outer ring
        draw.ellipse([cx - rad - 16, cy - rad - 16, cx + rad + 16, cy + rad + 16], fill=(28, 30, 32))
        draw.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=base_col)
        # Concentric Fresnel lens ridges
        for frac in (0.86, 0.70, 0.54, 0.38, 0.22):
            rr = int(rad * frac)
            ring_col = tuple(int(base_col[c] * 0.72 + 24) for c in range(3))
            draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=ring_col, width=5)
        # Inner filament hot-spot
        hr = int(rad * 0.30)
        draw.ellipse([cx - hr, cy - hr, cx + hr, cy + hr], fill=hot_col)
        # Subtle dust/soot smudge across lower lens
        smudge_r = int(rad * 0.92)
        draw.arc([cx - smudge_r, cy - smudge_r, cx + smudge_r, cy + smudge_r],
                 start=20, end=160, fill=(44, 42, 38), width=8)

    # Subtle grime speckle across the decal
    arr = np.asarray(img, dtype=np.float32)
    noise = rng.normal(0.0, 5.0, size=arr.shape).astype(np.float32)
    arr = np.clip(arr + noise, 30, 240).astype(np.uint8)
    from PIL import Image
    img.paste(Image.fromarray(arr, mode="RGB"))


def _add_rounded_signal_box(
    b: Builder,
    cx: float,
    y0: float,
    y1: float,
    z0: float,
    z1: float,
    w: float,
    corner_r: float,
    region: int,
) -> None:
    """Build vertical rounded-corner signal housing extruded along Y (front -Y to back +Y)."""
    from mathutils import Vector

    hw = w * 0.5
    hz = (z1 - z0) * 0.5
    cz = (z0 + z1) * 0.5
    r = min(corner_r, hw * 0.8, hz * 0.4)
    # 4 corner arcs in XZ plane (CCW viewed from -Y)
    corners = [
        (hw - r, -hz + r, -90.0),
        (hw - r, hz - r, 0.0),
        (-hw + r, hz - r, 90.0),
        (-hw + r, -hz + r, 180.0),
    ]
    seg = 2
    profile: list[tuple[float, float]] = []
    for ox, oz, a0 in corners:
        for k in range(seg + 1):
            a = math.radians(a0 + 90.0 * k / seg)
            profile.append((cx + ox + r * math.cos(a), cz + oz + r * math.sin(a)))

    v_front = [b.bm.verts.new(Vector((px, y0, pz))) for px, pz in profile]
    v_back = [b.bm.verts.new(Vector((px, y1, pz))) for px, pz in profile]
    n = len(profile)
    for i in range(n):
        j = (i + 1) % n
        b._face([v_front[i], v_front[j], v_back[j], v_back[i]], region, False, None, None)
    b._face(list(reversed(v_front)), region, False, None, None)
    b._face(v_back, region, False, None, None)


def _add_visor_hood(
    b: Builder,
    cx: float,
    y_base: float,
    cz: float,
    r_in: float,
    thick: float,
    depth_top: float,
    depth_bot: float,
    region: int,
) -> None:
    """Solid overhanging half-cylindrical visor hood projecting toward -Y."""
    from mathutils import Vector

    r_out = r_in + thick
    segs = 8
    # Span from right (-15 deg) over top (+90 deg) to left (+195 deg)
    a_start = math.radians(-18.0)
    a_end = math.radians(198.0)
    in_b, out_b, in_f, out_f = [], [], [], []
    for k in range(segs + 1):
        a = a_start + (a_end - a_start) * (k / segs)
        ca, sa = math.cos(a), math.sin(a)
        # Top projects further than bottom tips (classic slanted railway hood)
        t_top = max(sa, 0.0)
        d = depth_bot + (depth_top - depth_bot) * t_top
        in_b.append(b.bm.verts.new(Vector((cx + r_in * ca, y_base, cz + r_in * sa))))
        out_b.append(b.bm.verts.new(Vector((cx + r_out * ca, y_base, cz + r_out * sa))))
        in_f.append(b.bm.verts.new(Vector((cx + r_in * ca, y_base - d, cz + r_in * sa))))
        out_f.append(b.bm.verts.new(Vector((cx + r_out * ca, y_base - d, cz + r_out * sa))))

    for i in range(segs):
        j = i + 1
        # Outer surface
        b._face([out_b[i], out_f[i], out_f[j], out_b[j]], region, True, None, None)
        # Inner surface
        b._face([in_b[j], in_f[j], in_f[i], in_b[i]], region, True, None, None)
        # Front rim cap
        b._face([in_f[i], in_f[j], out_f[j], out_f[i]], region, False, None, None)
        # Back rim cap
        b._face([out_b[i], out_b[j], in_b[j], in_b[i]], region, False, None, None)

    # End caps at k=0 and k=segs
    b._face([in_b[0], in_f[0], out_f[0], out_b[0]], region, False, None, None)
    b._face([out_b[-1], out_f[-1], in_f[-1], in_b[-1]], region, False, None, None)


def _add_lens_disc(
    b: Builder,
    cx: float,
    y_face: float,
    cz: float,
    rad: float,
    v0: float,
    v1: float,
    region: int,
) -> None:
    """10-sided slightly domed Fresnel lens facing -Y mapped to a vertical third of region."""
    from mathutils import Vector

    segs = 10
    ring_pts = []
    uvs_ring = []
    vc = (v0 + v1) * 0.5
    vr = (v1 - v0) * 0.44
    ur = vr  # 1:1 aspect ratio inside square atlas tile so painted circle stays round
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        ca, sa = math.cos(a), math.sin(a)
        ring_pts.append(Vector((cx + rad * ca, y_face, cz + rad * sa)))
        uvs_ring.append((0.5 + ur * ca, vc + vr * sa))
    center_pt = Vector((cx, y_face - 0.012, cz))
    for i in range(segs):
        j = (i + 1) % segs
        # CCW when viewed from -Y
        b.add_quad(
            [center_pt, ring_pts[j], ring_pts[i]],
            region=region,
            uvs=[(0.5, vc), uvs_ring[j], uvs_ring[i]],
        )


def _build(b: Builder) -> None:
    from mathutils import Vector

    # Regions:
    # 0 = Weathered dark olive/brownish steel (mast, ladder, platform, brackets)
    # 1 = Dark charcoal/black matte enamel (signal head box, visors, relay box)
    # 2 = Cast concrete plinth base
    # 3 = 3-lens Fresnel signal glass decal

    # 1. Grounded cast concrete plinth base (z = 0.0 .. 0.18m, min_z = 0.0)
    r_bot = rrect_ring(0.0, 0.04, 0.48, 0.48, 0.04, seg=1, z=0.0)
    r_mid = rrect_ring(0.0, 0.04, 0.46, 0.46, 0.04, seg=1, z=0.14)
    r_top = rrect_ring(0.0, 0.04, 0.40, 0.40, 0.03, seg=1, z=0.18)
    b.add_loft([r_bot, r_mid, r_top], region=2, smooth=False)

    # 2. Steel anchor baseplate & 4 corner bolts (z = 0.18 .. 0.205m)
    b.add_box(Vector((0.0, 0.04, 0.192)), (0.28, 0.28, 0.024), region=0)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            b.add_cyl(Vector((sx * 0.10, 0.04 + sy * 0.10, 0.214)), 0.016, 0.022, region=0, segs=6)

    # 3. Tall H-beam steel mast (z = 0.204 .. 2.94m, centered at y = 0.03)
    mast_z0, mast_z1 = 0.204, 2.94
    mast_h = mast_z1 - mast_z0
    mast_cz = (mast_z0 + mast_z1) * 0.5
    # Web + front/back flanges
    b.add_box(Vector((0.0, 0.03, mast_cz)), (0.024, 0.11, mast_h), region=0)
    b.add_box(Vector((0.0, -0.028, mast_cz)), (0.14, 0.022, mast_h), region=0)
    b.add_box(Vector((0.0, 0.088, mast_cz)), (0.14, 0.022, mast_h), region=0)
    # Mast top cap
    b.add_box(Vector((0.0, 0.03, mast_z1 + 0.01)), (0.16, 0.16, 0.020), region=0)

    # 4. Electrical relay/junction box on lower-mid mast + vertical conduit
    b.add_box(Vector((-0.14, 0.03, 1.40)), (0.14, 0.13, 0.28), region=1)
    b.add_box(Vector((-0.07, 0.03, 1.40)), (0.03, 0.14, 0.04), region=0)
    b.add_cyl(Vector((-0.12, -0.03, 1.79)), 0.014, 0.54, region=0, segs=6)

    # 5. Service grating platform & safety guardrail around rear/sides (z = 1.94 .. 2.58m)
    plat_z = 1.94
    b.add_box(Vector((0.04, 0.19, plat_z)), (0.48, 0.34, 0.028), region=0)
    # Support gusset struts under platform
    for sx in (-0.16, 0.16):
        b.add_box(Vector((sx, 0.17, 1.82)), (0.024, 0.22, 0.024), region=0, rot=rx(-42.0))
    # Rear & right-side guardrail posts + top/mid rails (matching ref catwalk cage)
    post_pts = [(-0.18, 0.34), (0.26, 0.34), (0.26, 0.04)]
    for px, py in post_pts:
        b.add_cyl(Vector((px, py, 2.26)), 0.013, 0.62, region=0, segs=6)
    for rz_h in (2.25, 2.56):
        b.add_cyl(Vector((0.04, 0.34, rz_h)), 0.012, 0.44, region=0, segs=6, rot=ry(90.0))
        b.add_cyl(Vector((0.26, 0.19, rz_h)), 0.012, 0.30, region=0, segs=6, rot=rx(90.0))
    # Left-side grab bar beside signal head (visible in ref)
    b.add_cyl(Vector((-0.26, -0.10, 2.38)), 0.012, 0.86, region=0, segs=6)
    b.add_box(Vector((-0.21, -0.10, 1.96)), (0.12, 0.022, 0.022), region=0)
    b.add_box(Vector((-0.21, -0.10, 2.79)), (0.12, 0.022, 0.022), region=0)

    # 6. Rear steel service ladder (z = 0.28 .. 2.74m, y = 0.26)
    lad_z0, lad_z1 = 0.28, 2.74
    lad_h = lad_z1 - lad_z0
    lad_cz = (lad_z0 + lad_z1) * 0.5
    for sx in (-0.13, 0.13):
        b.add_box(Vector((sx, 0.26, lad_cz)), (0.022, 0.032, lad_h), region=0)
    # 9 horizontal ladder rungs
    for ri in range(9):
        rz_pos = 0.42 + ri * 0.275
        b.add_cyl(Vector((0.0, 0.26, rz_pos)), 0.011, 0.26, region=0, segs=6, rot=ry(90.0))
    # 4 pairs of standoff brackets tying ladder rails to mast
    for bz in (0.48, 1.12, 1.78, 2.52):
        for sx in (-0.11, 0.11):
            b.add_box(Vector((sx, 0.17, bz)), (0.024, 0.16, 0.028), region=0)

    # 7. Signal head mounting brackets (mast y=-0.03 -> box back y=-0.06)
    for bz in (2.22, 2.86):
        b.add_box(Vector((0.0, -0.045, bz)), (0.18, 0.06, 0.05), region=0)

    # 8. Rounded-corner 3-lens signal head housing (z = 2.02 .. 3.20m)
    _add_rounded_signal_box(
        b,
        cx=0.0,
        y0=-0.26,
        y1=-0.06,
        z0=2.02,
        z1=TARGET_H,
        w=0.42,
        corner_r=0.075,
        region=1,
    )
    # Rear service access door panel on signal head
    b.add_box(Vector((0.0, -0.052, 2.61)), (0.28, 0.016, 0.94), region=0)

    # 9. Three stacked circular lenses (Red, Amber, Green) + bezel rings + hooded visors
    lens_specs = [
        (2.94, 0.68, 0.98),  # Top Red
        (2.61, 0.35, 0.65),  # Middle Amber
        (2.28, 0.02, 0.32),  # Bottom Green
    ]
    for lz, v0, v1 in lens_specs:
        # Dark circular bezel frame
        b.add_cyl(Vector((0.0, -0.266, lz)), 0.105, 0.020, region=1, segs=10, rot=rx(90.0), smooth=False)
        # Fresnel lens disc
        _add_lens_disc(b, cx=0.0, y_face=-0.278, cz=lz, rad=0.084, v0=v0, v1=v1, region=3)
        # Solid overhanging visor hood
        _add_visor_hood(
            b,
            cx=0.0,
            y_base=-0.262,
            cz=lz,
            r_in=0.098,
            thick=0.012,
            depth_top=0.165,
            depth_bot=0.055,
            region=1,
        )


SPEC = PropSpec(
    slug="rail_semaphore_signal",
    node_name="RailSemaphoreSignal",
    mat_name="M_RailSemaphoreSignal",
    ref_image=REF_IMAGE,
    target_h=TARGET_H,
    tri_budget=1600,
    body="static",
    seed=1820,
    script_path=Path(__file__).resolve(),
    regions=[
        Region(kind="steel", rgb=(72, 68, 60), wear=0.55, rough=0.64, metal=0.58, nrm=0.85),
        Region(kind="paint", rgb=(40, 42, 44), wear=0.42, rough=0.56, metal=0.45, nrm=0.70),
        Region(kind="paint", rgb=(132, 128, 118), wear=0.12, rough=0.88, metal=0.0, nrm=0.90),
        Region(kind="paint", rgb=(36, 36, 38), wear=0.08, rough=0.26, metal=0.10, nrm=0.35, decal=_signal_lenses_decal),
    ],
    build=_build,
    collision=[
        ("CollisionShape3D", (0.56, 3.20, 0.78), (0.0, 1.60, 0.02)),
    ],
)

if __name__ == "__main__":
    main(SPEC)
