"""Procedural Vintage Soviet Fiberboard/Leather Suitcase (0.22m H, ~0.68m L).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-30_18-22.png:
- Lying flat (min_y = 0, height = 0.22m, length = 0.68m, depth = 0.44m)
- Worn dark navy/charcoal vulcanized fiberboard shell with beveled lid seam
- 8 riveted metal corner guards, stitched leather carry handle + brackets, twin brass latches
- Single mesh, RigidBody3D (collision_layer = 4, collision_mask = 7, BoxShape3D)

Usage:
    /usr/bin/python3 tools/blender/props/vintage_suitcase.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/vintage_suitcase.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT: Path = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.blender.common.domestic_kit import (  # noqa: E402
    Kit,
    REPO_ROOT as KIT_ROOT,
    run_prop,
)

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-22.png"

CFG: dict = {
    "slug": "vintage_suitcase",
    "node_name": "VintageSuitcase",
    "mat_name": "M_VintageSuitcase",
    "script": __file__,
    "ref_image": REF_IMAGE,
    "tri_budget": 1000,
    "body": "rigid",
    "mass": 4.5,
    "seed": 1822,
    "regions": [
        # 0: Worn dark navy/charcoal fiberboard body & lid
        {"base": (44, 48, 56), "var": 0.11, "grime": 0.34, "rust": 0.0, "rough": 0.66,
         "metal": 0.0, "normal": 1.6},
        # 1: Scuffed dark brown/olive leather handle & trim straps
        {"base": (78, 62, 46), "var": 0.09, "grime": 0.28, "rust": 0.0, "rough": 0.56,
         "metal": 0.0, "normal": 1.4},
        # 2: Scuffed stamped tin/steel corner guards & D-rings
        {"base": (148, 146, 136), "var": 0.09, "grime": 0.30, "rust": 0.18, "rough": 0.42,
         "metal": 0.80, "normal": 1.2},
        # 3: Tarnished brass twin latches & rivets
        {"base": (158, 132, 74), "var": 0.08, "grime": 0.28, "rust": 0.10, "rough": 0.34,
         "metal": 0.88, "normal": 1.1},
    ],
}


def _paint_suitcase(idx: int, maps: dict, half: int) -> None:
    """Add fiberboard scuffs/edge wear (0) and tarnished metal maps (2, 3)."""
    import numpy as np
    from PIL import Image

    if idx == 0:
        # Subtle fiberboard grain + edge scuffing speckles
        rng = np.random.default_rng(1822)
        scuff = rng.random((64, 64)).astype(np.float32)
        scuff_up = np.asarray(
            Image.fromarray(scuff).resize((half, half), Image.Resampling.BILINEAR),
            dtype=np.float32,
        )
        wear = np.clip((scuff_up - 0.72) * 3.5, 0.0, 1.0)
        maps["alb"] = np.clip(maps["alb"] + wear[..., None] * 26.0, 32.0, 220.0)
        maps["rough"] = np.clip(maps["rough"] + wear * 0.12, 0.48, 0.86)
    elif idx in (2, 3):
        brass_dir = KIT_ROOT / "assets" / "materials" / "tarnished_brass" / "textures"
        orm = np.asarray(
            Image.open(brass_dir / "tarnished_brass_orm.png")
            .convert("RGB")
            .resize((half, half), Image.Resampling.BICUBIC),
            dtype=np.float32,
        ) / 255.0
        maps["rough"] = np.clip(orm[..., 1] * 0.6 + 0.16, 0.24, 0.62)
        maps["ao"] = np.clip(orm[..., 0], 0.55, 1.0)


def build(kit: Kit) -> None:
    """Build vintage suitcase lying flat (Blender Z up, min_z=0, L=0.68m, D=0.44m, H=0.22m)."""
    L = 0.680
    D = 0.440
    # 1. Four low brass/rubber bottom studs grounded at z = 0.0
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            kit.cyl((sx * 0.265, sy * 0.165, 0.004), (0, 0, 1), 0.014, 0.008, 8, 2)

    # 2. Lower suitcase shell (z: 0.008..0.152) + recessed parting rim + upper lid (z: 0.155..0.220)
    kit.box((0.0, 0.0, 0.080), (L, D, 0.144), 0, bevel=0.010)
    # Recessed dark parting strip between base and lid
    kit.box((0.0, 0.0, 0.1535), (L - 0.012, D - 0.012, 0.010), 1)
    # Upper lid (top at exact z = 0.220m)
    kit.box((0.0, 0.0, 0.1875), (L, D, 0.065), 0, bevel=0.010)

    # 3. Eight metal corner guard plates wrapping outer corners
    hx, hy = L * 0.5, D * 0.5
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            # Bottom corner guards (z ~ 0.022) & top corner guards (z ~ 0.205)
            kit.box((sx * (hx - 0.024), sy * (hy - 0.024), 0.025), (0.058, 0.058, 0.036), 2, bevel=0.004)
            kit.box((sx * (hx - 0.024), sy * (hy - 0.024), 0.204), (0.058, 0.058, 0.034), 2, bevel=0.004)

    # 4. Front (-Y) stitched leather carry handle & metal D-ring mounts
    front_y = -hy
    for sx in (-1.0, 1.0):
        kit.box((sx * 0.088, front_y - 0.006, 0.105), (0.026, 0.012, 0.032), 2)
    handle_pts = [
        (-0.084, front_y - 0.010, 0.105),
        (-0.062, front_y - 0.038, 0.105),
        (0.000, front_y - 0.046, 0.105),
        (0.062, front_y - 0.038, 0.105),
        (0.084, front_y - 0.010, 0.105),
    ]
    kit.tube(handle_pts, 0.011, 6, 1)

    # 5. Twin brass latches flanking front (-Y) handle, straddling lid seam (z = 0.1535)
    for lx in (-0.215, 0.215):
        kit.box((lx, front_y - 0.006, 0.153), (0.044, 0.012, 0.056), 3)
        kit.box((lx, front_y - 0.013, 0.160), (0.026, 0.008, 0.024), 3)

    # 6. Twin rear (+Y) brass strap hinges
    for lx in (-0.200, 0.200):
        kit.box((lx, hy + 0.004, 0.153), (0.034, 0.008, 0.042), 3)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_suitcase)
