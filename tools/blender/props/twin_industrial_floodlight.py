"""Procedural Twin Industrial Floodlight (0.38m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-43_2.png:
- Hexagonal/chamfered dark cast-metal wall junction box with 4 front bolt bosses
- Twin angled swivel yokes & knuckle joints aimed outward & downward
- Twin ribbed cast-metal parabolic lamp housings with beveled bezels & frosted glass lenses
- 2048x2048 PBR atlas (cast junction box, swivel hardware, ribbed lamp body, frosted lens)

Usage:
    /usr/bin/python3 tools/blender/props/twin_industrial_floodlight.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/twin_industrial_floodlight.py
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
    "slug": "twin_industrial_floodlight",
    "node_name": "TwinIndustrialFloodlight",
    "mat_name": "M_TwinIndustrialFloodlight",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-30_18-43_2.png",
    "tri_budget": 1400,
    "body": "static",
    "seed": 18432,
    "regions": [
        # 0: Dark weathered cast-iron wall junction box & mounting flange
        {
            "base": (72, 66, 62),
            "var": 0.12,
            "grime": 0.45,
            "rust": 0.36,
            "rough": 0.58,
            "metal": 0.78,
            "normal": 2.4,
        },
        # 1: Swivel yokes, knuckle bolts & junction box rivets
        {
            "base": (88, 82, 76),
            "var": 0.10,
            "grime": 0.38,
            "rust": 0.32,
            "rough": 0.50,
            "metal": 0.84,
            "normal": 2.0,
        },
        # 2: Dark oxidized cast-aluminum parabolic lamp housings & cooling ribs
        {
            "base": (66, 64, 62),
            "var": 0.14,
            "grime": 0.42,
            "rust": 0.28,
            "rough": 0.54,
            "metal": 0.80,
            "normal": 2.5,
        },
        # 3: Grimy frosted industrial glass lamp lenses (off state)
        {
            "base": (154, 156, 152),
            "var": 0.08,
            "grime": 0.35,
            "rust": 0.0,
            "rough": 0.30,
            "metal": 0.05,
            "normal": 1.2,
        },
    ],
}


def _paint_floodlight(idx: int, maps: dict, half: int) -> None:
    """Add radial lens fresnel rings on region 3 and cast-metal stipple on region 2."""
    import numpy as np

    if idx == 3:
        yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
        cx = (xx - half * 0.5) / float(half)
        cy = (yy - half * 0.5) / float(half)
        rad = np.sqrt(cx * cx + cy * cy)
        fresnel = 0.5 + 0.5 * np.sin(rad * 44.0 * math.pi)
        center_glow = np.clip(1.0 - rad * 1.8, 0.0, 1.0)
        maps["alb"] = np.clip(
            maps["alb"] * (0.86 + 0.12 * fresnel + 0.18 * center_glow)[..., None],
            40.0,
            232.0,
        )
        maps["rough"] = np.clip(0.28 + 0.10 * (1.0 - fresnel), 0.20, 0.48)


def _add_lamp_head(kit: Kit, sx: float, hub_pos: tuple[float, float, float]) -> None:
    """Add one angled swivel yoke, ribbed parabolic lamp housing, bezel, and lens."""
    from mathutils import Matrix, Vector

    yaw = sx * math.radians(26.0)
    pitch = math.radians(34.0)  # tilts -Y axis downward toward -Z
    rot_m = Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(pitch, 4, "X")
    xf = Matrix.Translation(Vector(hub_pos)) @ rot_m

    def xform_pt(pt: tuple[float, float, float]) -> tuple[float, float, float]:
        v = xf @ Vector(pt)
        return (v.x, v.y, v.z)

    # Swivel stem + cast knuckle at hub
    kit.cyl(xform_pt((0.0, -0.025, 0.0)), tuple((rot_m @ Vector((0, 1, 0))).normalized()), 0.020, 0.056, 8, 1)
    kit.cyl(hub_pos, (1, 0, 0), 0.022, 0.044, 8, 1)

    # Parabolic lamp housing rings (10-sided, along local -Y)
    profile = [
        (-0.045, 0.042),
        (-0.115, 0.048),
        (-0.165, 0.084),
        (-0.220, 0.102),
        (-0.236, 0.102),
        (-0.238, 0.092),
        (-0.214, 0.082),
    ]
    n_seg = 10
    rings: list[list[tuple[float, float, float]]] = []
    for ly, rad in profile:
        ring: list[tuple[float, float, float]] = []
        for k in range(n_seg):
            ang = 2.0 * math.pi * float(k) / float(n_seg) + math.pi / float(n_seg)
            lx = rad * math.cos(ang)
            lz = rad * math.sin(ang)
            ring.append(xform_pt((lx, ly, lz)))
        rings.append(ring)

    # Skin outer housing (region 2), inner bezel (region 2), and lens face (region 3)
    kit.loft(rings, [2, 2, 2, 2, 2, 3], cap_start=True, cap_end=True)

    # Center frosted bulb / lens cap protrusion inside reflector
    kit.cyl(
        xform_pt((0.0, -0.210, 0.0)),
        tuple((rot_m @ Vector((0, 1, 0))).normalized()),
        0.032,
        0.016,
        8,
        3,
        radius2=0.018,
    )

    # 4 longitudinal cast-metal cooling ribs along rear lamp barrel
    bmesh = kit.bmesh
    for k in range(4):
        ang = math.radians(45.0 + 90.0 * k)
        rx = 0.048 * math.cos(ang)
        rz = 0.048 * math.sin(ang)
        before = set(kit.bm.faces)
        ret = bmesh.ops.create_cube(kit.bm, size=1.0)
        verts = ret["verts"]
        rib_xf = (
            xf
            @ Matrix.Translation(Vector((rx, -0.095, rz)))
            @ Matrix.Rotation(ang, 4, "Y")
            @ Matrix.Diagonal((0.010, 0.088, 0.014, 1.0))
        )
        bmesh.ops.transform(kit.bm, matrix=rib_xf, verts=verts)
        for f in kit.bm.faces:
            if f not in before:
                f.material_index = 2


def build(kit: Kit) -> None:
    """Build twin industrial floodlight (0.38m H, wall at +Y, lights aimed -Y)."""
    # 1. Chamfered hexagonal wall junction box (z from 0.210 to 0.380 = top)
    hex_xz = [
        (-0.045, 0.380),
        (0.045, 0.380),
        (0.082, 0.320),
        (0.082, 0.245),
        (0.056, 0.210),
        (-0.056, 0.210),
        (-0.082, 0.245),
        (-0.082, 0.320),
    ]
    ring_back = [(x, 0.135, z) for x, z in hex_xz]
    ring_mid = [(x, 0.088, z) for x, z in hex_xz]
    ring_front = [(x * 0.90, 0.075, 0.295 + (z - 0.295) * 0.90) for x, z in hex_xz]
    kit.loft([ring_back, ring_mid, ring_front], 0, cap_start=True, cap_end=True)

    # 4 prominent rounded bolt/rivet bosses on front junction box cover
    for bx in (-0.032, 0.032):
        for bz in (0.262, 0.330):
            kit.cyl((bx, 0.070, bz), (0, 1, 0), 0.010, 0.012, 8, 1)

    # Horizontal yoke cross-bar emerging from lower junction box
    kit.cyl((0.0, 0.062, 0.222), (1, 0, 0), 0.018, 0.166, 8, 1)

    # 2. Twin angled swivel yokes & ribbed parabolic floodlight heads
    for sx in (-1.0, 1.0):
        _add_lamp_head(kit, sx, (sx * 0.083, 0.058, 0.222))


if __name__ == "__main__":
    run_prop(CFG, build, _paint_floodlight)
