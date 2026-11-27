"""Procedural Red Alarm Cage Beacon on Gooseneck Conduit Arm (0.48m H).

Matches references /home/dkd/Downloads/hl2_refs/2026-10-30_18-51_1.png and
/home/dkd/Downloads/hl2_refs/2026-10-30_18-45.png:
- Square beveled wall mounting plate with 4 corner bolts & conduit hub collar
- Curved gooseneck steel conduit arm sweeping out and down into cast socket cap
- Flared cast-metal mounting socket hood
- Red ribbed glass beacon dome (10 vertical Fresnel ribs)
- Protective steel wire cage (2 crossing U-hoops + 2 horizontal guard rings)
- 2048x2048 PBR atlas (conduit/socket metal, wire cage, red ribbed glass, bolts)

Usage:
    /usr/bin/python3 tools/blender/props/red_alarm_cage_beacon.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/red_alarm_cage_beacon.py
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
    "slug": "red_alarm_cage_beacon",
    "node_name": "RedAlarmCageBeacon",
    "mat_name": "M_RedAlarmCageBeacon",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-30_18-51_1.png",
    "tri_budget": 1400,
    "body": "static",
    "seed": 18511,
    "regions": [
        # 0: Weathered dark gray-brown steel gooseneck conduit, wall plate & cast socket
        {
            "base": (88, 84, 78),
            "var": 0.12,
            "grime": 0.44,
            "rust": 0.34,
            "rough": 0.56,
            "metal": 0.80,
            "normal": 2.2,
        },
        # 1: Protective galvanized/aged steel wire cage
        {
            "base": (118, 116, 110),
            "var": 0.10,
            "grime": 0.36,
            "rust": 0.26,
            "rough": 0.48,
            "metal": 0.84,
            "normal": 1.8,
        },
        # 2: Deep ruby-red ribbed glass alarm beacon dome
        {
            "base": (176, 30, 26),
            "var": 0.06,
            "grime": 0.14,
            "rust": 0.0,
            "rough": 0.18,
            "metal": 0.04,
            "normal": 1.4,
        },
        # 3: Rusted steel corner mounting bolts
        {
            "base": (114, 108, 100),
            "var": 0.10,
            "grime": 0.34,
            "rust": 0.40,
            "rough": 0.46,
            "metal": 0.82,
            "normal": 1.8,
        },
    ],
}


def _paint_beacon(idx: int, maps: dict, half: int) -> None:
    """Add vertical Fresnel rib shading + warm inner bulb glow gradient on red glass (2)."""
    import numpy as np

    if idx == 2:
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        u = xx / float(half)
        v = yy / float(half)
        ribs = 0.5 + 0.5 * np.cos(u * 20.0 * math.pi)
        # Subtle warm orange-red core tint toward middle of beacon dome
        core = np.exp(-((v - 0.52) / 0.28) ** 2)
        alb = maps["alb"].copy()
        alb[..., 0] = np.clip(alb[..., 0] * (0.88 + 0.18 * ribs + 0.14 * core), 45.0, 238.0)
        alb[..., 1] = np.clip(alb[..., 1] * (0.75 + 0.25 * ribs + 0.85 * core), 30.0, 145.0)
        alb[..., 2] = np.clip(alb[..., 2] * (0.70 + 0.20 * ribs + 0.35 * core), 30.0, 110.0)
        maps["alb"] = alb
        maps["rough"] = np.clip(0.16 + 0.08 * (1.0 - ribs), 0.14, 0.30)


def _closed_ring_tube(
    kit: Kit,
    cx: float,
    cy: float,
    z: float,
    ring_r: float,
    wire_r: float,
    ring_segs: int,
    wire_segs: int,
    region: int,
) -> None:
    """Sweep a closed horizontal wire ring around (cx, cy, z)."""
    from mathutils import Vector

    rings: list[list[tuple[float, float, float]]] = []
    for i in range(ring_segs):
        theta = 2.0 * math.pi * float(i) / float(ring_segs)
        rad_dir = Vector((math.cos(theta), math.sin(theta), 0.0))
        up_dir = Vector((0.0, 0.0, 1.0))
        center = Vector((cx + ring_r * rad_dir.x, cy + ring_r * rad_dir.y, z))
        ring: list[tuple[float, float, float]] = []
        for k in range(wire_segs):
            phi = 2.0 * math.pi * float(k) / float(wire_segs)
            p = center + (rad_dir * math.cos(phi) + up_dir * math.sin(phi)) * wire_r
            ring.append((p.x, p.y, p.z))
        rings.append(ring)

    bm = kit.bm
    vr = [[bm.verts.new(p) for p in ring] for ring in rings]
    for i in range(ring_segs):
        inext = (i + 1) % ring_segs
        for k in range(wire_segs):
            knext = (k + 1) % wire_segs
            f = bm.faces.new((vr[i][k], vr[inext][k], vr[inext][knext], vr[i][knext]))
            f.material_index = region


def _ribbed_dome(kit: Kit, cx: float, cy: float, region: int) -> None:
    """Build 10-ribbed red glass beacon dome hanging from socket cap."""
    n_pts = 20
    # (z, base_radius, rib_amp)
    levels = [
        (0.194, 0.048, 0.0020),
        (0.135, 0.050, 0.0032),
        (0.080, 0.049, 0.0032),
        (0.046, 0.041, 0.0024),
        (0.028, 0.024, 0.0012),
        (0.020, 0.006, 0.0000),
    ]
    rings: list[list[tuple[float, float, float]]] = []
    for z, base_r, amp in levels:
        ring: list[tuple[float, float, float]] = []
        for i in range(n_pts):
            ang = 2.0 * math.pi * float(i) / float(n_pts)
            rad = base_r + (amp if (i % 2 == 0) else -amp)
            ring.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang), z))
        rings.append(ring)
    kit.loft(rings, region, cap_start=True, cap_end=True)


def build(kit: Kit) -> None:
    """Build red alarm cage beacon on gooseneck arm (0.48m H, wall at +Y)."""
    # 1. Square beveled wall mounting plate & 4 corner bolts (wall at y = +0.215)
    kit.box((0.0, 0.207, 0.355), (0.094, 0.016, 0.094), 0, bevel=0.003)
    kit.cyl((0.0, 0.192, 0.355), (0, 1, 0), 0.022, 0.020, 10, 0)
    for bx in (-0.032, 0.032):
        for bz in (0.323, 0.387):
            kit.cyl((bx, 0.197, bz), (0, 1, 0), 0.0065, 0.008, 6, 3)

    # 2. Curved gooseneck conduit arm (apex center z = 0.467 + radius 0.013 = 0.480m)
    bx, by = 0.0, -0.022
    arm_pts = [
        (0.0, 0.195, 0.355),
        (0.0, 0.155, 0.392),
        (0.0, 0.115, 0.428),
        (0.0, 0.078, 0.454),
        (0.0, 0.048, 0.466),
        (0.0, 0.020, 0.466),
        (0.0, -0.002, 0.453),
        (0.0, -0.016, 0.428),
        (0.0, by, 0.390),
        (0.0, by, 0.264),
    ]
    kit.tube(arm_pts, 0.013, 8, 0, cap=True)

    # 3. Cast metal mounting socket cap & threaded entry collar
    kit.cyl((bx, by, 0.256), (0, 0, 1), 0.022, 0.026, 10, 0)
    kit.cyl((bx, by, 0.222), (0, 0, 1), 0.068, 0.046, 12, 0, radius2=0.032)
    kit.cyl((bx, by, 0.196), (0, 0, 1), 0.072, 0.012, 12, 0)

    # 4. Red ribbed glass beacon dome
    _ribbed_dome(kit, bx, by, region=2)

    # 5. Protective steel wire cage: 2 crossing U-hoops (min_z = 0.000m) + 2 guard rings
    u_r = 0.066
    for ang_deg in (45.0, 135.0):
        c = math.cos(math.radians(ang_deg))
        s = math.sin(math.radians(ang_deg))
        hoop_pts = [
            (bx + u_r * c, by + u_r * s, 0.192),
            (bx + u_r * c, by + u_r * s, 0.134),
            (bx + u_r * c, by + u_r * s, 0.072),
            (bx + 0.048 * c, by + 0.048 * s, 0.024),
            (bx, by, 0.0045),
            (bx - 0.048 * c, by - 0.048 * s, 0.024),
            (bx - u_r * c, by - u_r * s, 0.072),
            (bx - u_r * c, by - u_r * s, 0.134),
            (bx - u_r * c, by - u_r * s, 0.192),
        ]
        kit.tube(hoop_pts, 0.0045, 6, 1, cap=True)

    _closed_ring_tube(kit, bx, by, 0.134, ring_r=u_r, wire_r=0.0045, ring_segs=12, wire_segs=6, region=1)
    _closed_ring_tube(kit, bx, by, 0.072, ring_r=u_r, wire_r=0.0045, ring_segs=12, wire_segs=6, region=1)


if __name__ == "__main__":
    run_prop(CFG, build, _paint_beacon)
