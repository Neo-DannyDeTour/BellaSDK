"""Procedural Substation Oil-Cooled Steel Transformer (2.15m H).

Matches references:
- /home/dkd/Downloads/hl2_refs/2026-10-30_18-40.png
- /home/dkd/Downloads/hl2_refs/2026-11-05_19-32_1.png

Features:
- Heavy welded steel base skid rails with cross-members (min_y = 0)
- Cylindrical/rounded-oval oil-cooled steel tank with bolted top cover rim,
  lower circular bolted inspection hatch, lifting lugs, and teal lower accent band
- Twin banks of vertical cooling radiator fins with upper/lower oil header manifolds
- 3 tall ribbed glazed-ceramic HV bushings on angled/stepped turret collars with
  rusted steel top caps and terminal studs reaching exact 2.15m height
- 2048x2048 PBR atlas (painted tank/fins, dark steel skid/hardware, ceramic, bronze/rust)

Usage:
    /usr/bin/python3 tools/blender/props/substation_transformer.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/substation_transformer.py
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
    "slug": "substation_transformer",
    "node_name": "SubstationTransformer",
    "mat_name": "M_SubstationTransformer",
    "script": __file__,
    "ref_image": "/home/dkd/Downloads/hl2_refs/2026-10-30_18-40.png",
    "tri_budget": 2000,
    "body": "static",
    "seed": 10301840,
    "regions": [
        # 0: Weathered cream/olive-gray painted steel transformer tank + cooling fins
        {"base": (182, 178, 158), "var": 0.11, "grime": 0.42, "rust": 0.16, "rough": 0.62,
         "metal": 0.32, "normal": 2.1},
        # 1: Dark weathered structural steel base skid, collars, hatch & lifting lugs
        {"base": (72, 74, 72), "var": 0.10, "grime": 0.36, "rust": 0.40, "rough": 0.54,
         "metal": 0.74, "normal": 2.2},
        # 2: Ribbed glazed-cream ceramic HV insulator bushings
        {"base": (214, 206, 184), "var": 0.06, "grime": 0.24, "rust": 0.0, "rough": 0.22,
         "metal": 0.0, "normal": 1.2},
        # 3: Rusted steel/oxidized bronze top terminal caps, studs & drain valve
        {"base": (102, 70, 52), "var": 0.12, "grime": 0.30, "rust": 0.55, "rough": 0.56,
         "metal": 0.70, "normal": 2.4},
    ],
}


def _paint_transformer(idx: int, maps: dict, half: int) -> None:
    """Add vertical rain/oil grime streaks and lower teal accent band on tank (0)."""
    import numpy as np

    yy, xx = np.mgrid[0:half, 0:half].astype(np.float32)
    u = xx / float(half)
    v = 1.0 - yy / float(half)
    if idx == 0:
        # Subtle mottled grime & weathering (orientation-agnostic for smart_project islands)
        streak = 0.5 + 0.5 * np.sin(u * 26.0 * math.pi + np.sin(v * 8.0) * 1.4)
        drip = 0.12 * (1.0 - streak)
        maps["alb"] = np.clip(maps["alb"] * (1.0 - drip[..., None]), 32.0, 236.0)
        maps["rough"] = np.clip(maps["rough"] + drip * 0.35, 0.40, 0.90)
    elif idx == 2:
        # Glazed porcelain slight specular sheen + grime bands in shed recesses
        band = 0.5 + 0.5 * np.sin(v * 24.0 * math.pi)
        maps["alb"] = np.clip(maps["alb"] * (0.90 + 0.12 * band[..., None]), 45.0, 238.0)
        maps["rough"] = np.clip(0.18 + 0.14 * (1.0 - band), 0.14, 0.42)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)


def _circle_ring(cx: float, cy: float, z: float, rx: float, ry: float, segs: int) -> list[tuple[float, float, float]]:
    return [
        (cx + rx * math.cos(2.0 * math.pi * k / segs), cy + ry * math.sin(2.0 * math.pi * k / segs), z)
        for k in range(segs)
    ]


def _add_ribbed_bushing(
    kit: Kit,
    base_pt: tuple[float, float, float],
    tilt_rad: float,
    yaw_rad: float,
    total_len: float,
    segs: int = 8,
    n_ribs: int = 4,
) -> None:
    """Build a tilted HV ceramic bushing with turret collar, ribbed sheds, cap, and top lug."""
    from mathutils import Matrix, Vector

    rot = Matrix.Rotation(yaw_rad, 4, "Z") @ Matrix.Rotation(tilt_rad, 4, "Y")
    origin = Vector(base_pt)

    def _xform_ring(r: float, z_local: float) -> list[tuple[float, float, float]]:
        pts = []
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            p = origin + (rot @ Vector((r * math.cos(a), r * math.sin(a), z_local)))
            pts.append((p.x, p.y, p.z))
        return pts

    # 1. Stepped steel mounting turret collar
    collar_h = 0.085
    collar_rings = [
        _xform_ring(0.125, -0.025),
        _xform_ring(0.125, 0.030),
        _xform_ring(0.092, collar_h),
    ]
    kit.loft(collar_rings, 1, cap_start=True, cap_end=False)

    # 2. Ribbed ceramic insulator stack (3 rings per shed rib: core -> flared skirt -> core)
    cer_z0 = collar_h
    cer_h = total_len - collar_h - 0.19
    rib_pitch = cer_h / float(n_ribs)
    cer_rings: list[list[tuple[float, float, float]]] = [_xform_ring(0.056, cer_z0)]
    for i in range(n_ribs):
        z_a = cer_z0 + i * rib_pitch
        z_mid = z_a + rib_pitch * 0.45
        z_next = z_a + rib_pitch
        cer_rings.append(_xform_ring(0.042, z_a + rib_pitch * 0.12))
        cer_rings.append(_xform_ring(0.080 - i * 0.003, z_mid))
        cer_rings.append(_xform_ring(0.040, z_next))
    kit.loft(cer_rings, 2, cap_start=False, cap_end=False)

    # 3. Rusted metal top oil-expansion cap + terminal blade stud
    cap_z0 = cer_z0 + cer_h
    cap_z1 = cap_z0 + 0.125
    lug_z1 = total_len
    cap_rings = [
        _xform_ring(0.064, cap_z0),
        _xform_ring(0.068, cap_z0 + 0.020),
        _xform_ring(0.048, cap_z1),
    ]
    kit.loft(cap_rings, 3, cap_start=False, cap_end=True)

    # Terminal stud & blade
    stud_rings = [
        _xform_ring(0.018, cap_z1),
        _xform_ring(0.014, lug_z1),
    ]
    kit.loft(stud_rings, 3, cap_start=False, cap_end=True)


def build(kit: Kit) -> None:
    """Build 2.15m H substation oil-cooled transformer grounded at (0, 0, 0)."""
    # 1. Heavy steel base skid rails (min_z = 0.0, z = 0.0 -> 0.10m)
    for sy in (-0.34, 0.34):
        kit.box((0.0, sy, 0.050), (1.06, 0.10, 0.100), 1)
    for sx in (-0.42, 0.42):
        kit.box((sx, 0.0, 0.055), (0.09, 0.62, 0.085), 1)

    # 2. Main oil-cooled steel tank body (z = 0.10 -> 1.38m)
    # Rounded-oval tank (0.86m wide X, 0.74m deep Y) with bottom base rim & top bolted flange
    segs_tank = 14
    tank_rings = [
        _circle_ring(0.0, 0.0, 0.100, 0.405, 0.345, segs_tank),
        _circle_ring(0.0, 0.0, 0.155, 0.425, 0.365, segs_tank),
        _circle_ring(0.0, 0.0, 1.290, 0.425, 0.365, segs_tank),
        _circle_ring(0.0, 0.0, 1.320, 0.455, 0.395, segs_tank),
        _circle_ring(0.0, 0.0, 1.380, 0.455, 0.395, segs_tank),
        _circle_ring(0.0, 0.0, 1.395, 0.420, 0.360, segs_tank),
    ]
    kit.loft(tank_rings, [1, 0, 1, 1, 1], cap_start=True, cap_end=True)

    # 3. Vertical cooling radiator fin banks on -X and +X flanks (5 fins per side)
    # Plus top & bottom oil header manifolds linking fins to tank wall
    fin_ys = (-0.22, -0.11, 0.0, 0.11, 0.22)
    for sx in (-1.0, 1.0):
        # Upper & lower horizontal oil header manifolds
        kit.box((sx * 0.475, 0.0, 1.18), (0.14, 0.48, 0.065), 1)
        kit.box((sx * 0.475, 0.0, 0.28), (0.14, 0.48, 0.065), 1)
        for fy in fin_ys:
            kit.box((sx * 0.515, fy, 0.73), (0.16, 0.022, 0.96), 0)

    # 4. Lower circular bolted inspection hatch on front (-Y) face + drain valve
    kit.cyl((0.14, -0.375, 0.34), (0.0, -1.0, 0.0), 0.135, 0.055, 10, 1)
    kit.cyl((0.14, -0.405, 0.34), (0.0, -1.0, 0.0), 0.112, 0.025, 10, 0)
    # Drain valve + small breather cap on top
    kit.cyl((-0.18, -0.385, 0.24), (0.0, -1.0, 0.0), 0.032, 0.075, 8, 3)
    kit.cyl((-0.24, 0.20, 1.44), (0.0, 0.0, 1.0), 0.036, 0.100, 8, 3)

    # 5. Four heavy welded lifting lugs on upper tank corners
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.box((sx * 0.33, sy * 0.34, 1.24), (0.045, 0.075, 0.095), 1)

    # 6. Three tall ribbed ceramic HV bushings on top (reaching exact z = 2.15m)
    # Arranged across the top deck with slight outward splay like HL2 substation transformers
    bushing_specs = [
        # (base_x, base_y, base_z, tilt_deg, yaw_deg, length)
        (0.0, 0.04, 1.385, 0.0, 0.0, 0.765),         # Center vertical reaches exactly 2.150m
        (-0.22, -0.06, 1.375, -11.0, 20.0, 0.745),   # Left splayed bushing
        (0.22, -0.06, 1.375, 11.0, -20.0, 0.745),    # Right splayed bushing
    ]
    for bx, by, bz, tilt_d, yaw_d, blen in bushing_specs:
        _add_ribbed_bushing(
            kit,
            (bx, by, bz),
            math.radians(tilt_d),
            math.radians(yaw_d),
            blen,
            segs=8,
            n_ribs=4,
        )


if __name__ == "__main__":
    if "--gen-textures" in sys.argv:
        from tools.blender.common.domestic_kit import generate_atlas

        generate_atlas(CFG, _paint_transformer)
    else:
        run_prop(CFG, build, _paint_transformer)
