"""Procedural Soviet Wall-Mounted Wooden Kitchen Cabinet (0.68m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-11-04_03-43.png:
- Dark aged lacquered wood cabinet box with stepped overhanging crown cornice
- 4 tall vertical door sections with recessed molded inner panels
- 2 pairs of vertical tarnished brass/steel pulls & small underside wall cleats
- Grounded min_y = 0, single mesh, 2048x2048 PBR atlas

Usage:
    /usr/bin/python3 tools/blender/props/kitchen_wall_cabinet.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/kitchen_wall_cabinet.py
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

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-11-04_03-43.png"

CFG: dict = {
    "slug": "kitchen_wall_cabinet",
    "node_name": "KitchenWallCabinet",
    "mat_name": "M_KitchenWallCabinet",
    "script": __file__,
    "ref_image": REF_IMAGE,
    "tri_budget": 1100,
    "body": "static",
    "seed": 343,
    "regions": [
        # 0: Cabinet carcass, crown cornice, bottom plinth
        {"base": (106, 68, 38), "var": 0.08, "grime": 0.28, "rust": 0.0, "rough": 0.46,
         "metal": 0.0, "normal": 1.6},
        # 1: Door frames & molded rails
        {"base": (116, 74, 42), "var": 0.09, "grime": 0.25, "rust": 0.0, "rough": 0.44,
         "metal": 0.0, "normal": 1.7},
        # 2: Recessed dark wood door panels
        {"base": (72, 46, 26), "var": 0.08, "grime": 0.36, "rust": 0.0, "rough": 0.54,
         "metal": 0.0, "normal": 1.8},
        # 3: Tarnished brass/iron vertical pulls & brackets
        {"base": (152, 128, 86), "var": 0.08, "grime": 0.30, "rust": 0.14, "rough": 0.38,
         "metal": 0.84, "normal": 1.2},
    ],
}


def _load_square(path: Path, size: int, mode: str) -> object:
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert(mode).resize((size, size), Image.Resampling.BICUBIC)
    return np.asarray(img, dtype=np.float32)


def _paint_cabinet(idx: int, maps: dict, half: int) -> None:
    """Blend photogrammetry dark_varnished_planks and tarnished_brass into atlas regions."""
    import numpy as np

    if idx in (0, 1, 2):
        wood_dir = KIT_ROOT / "assets" / "materials" / "dark_varnished_planks" / "textures"
        alb = _load_square(wood_dir / "dark_varnished_planks_albedo.png", half, "RGB")
        nrm = _load_square(wood_dir / "dark_varnished_planks_normal.png", half, "RGB") / 255.0 * 2.0 - 1.0
        orm = _load_square(wood_dir / "dark_varnished_planks_orm.png", half, "RGB") / 255.0

        tint = {
            0: np.array([1.10, 0.92, 0.72], dtype=np.float32),
            1: np.array([1.18, 0.98, 0.76], dtype=np.float32),
            2: np.array([0.74, 0.62, 0.50], dtype=np.float32),
        }[idx]
        maps["alb"] = np.clip(alb * tint[None, None, :] * 0.84 + maps["alb"] * 0.16, 30.0, 225.0)
        mix_n = nrm * 0.76 + maps["nrm"] * 0.24
        mix_n[..., 2] = np.maximum(mix_n[..., 2], 0.25)
        mix_n /= np.sqrt(np.sum(mix_n * mix_n, axis=-1, keepdims=True))
        maps["nrm"] = mix_n
        rough_base = 0.44 if idx != 2 else 0.54
        maps["rough"] = np.clip(orm[..., 1] * 0.55 + rough_base * 0.45, 0.32, 0.72)
        maps["ao"] = np.clip(orm[..., 0] * 0.72 + maps["ao"] * 0.28, 0.48, 1.0)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)
    elif idx == 3:
        brass_dir = KIT_ROOT / "assets" / "materials" / "tarnished_brass" / "textures"
        alb = _load_square(brass_dir / "tarnished_brass_albedo.png", half, "RGB")
        nrm = _load_square(brass_dir / "tarnished_brass_normal.png", half, "RGB") / 255.0 * 2.0 - 1.0
        orm = _load_square(brass_dir / "tarnished_brass_orm.png", half, "RGB") / 255.0
        maps["alb"] = np.clip(alb * 0.75 + maps["alb"] * 0.25, 35.0, 225.0)
        mix_n = nrm * 0.7 + maps["nrm"] * 0.3
        mix_n[..., 2] = np.maximum(mix_n[..., 2], 0.3)
        mix_n /= np.sqrt(np.sum(mix_n * mix_n, axis=-1, keepdims=True))
        maps["nrm"] = mix_n
        maps["rough"] = np.clip(orm[..., 1] * 0.7 + 0.14, 0.24, 0.60)
        maps["ao"] = np.clip(orm[..., 0], 0.55, 1.0)
        maps["metal"] = np.full((half, half), 0.84, dtype=np.float32)


def _add_recessed_door(
    kit: Kit,
    cx: float,
    front_y: float,
    cz: float,
    w: float,
    h: float,
) -> None:
    """Build a framed cabinet door with a recessed molded inner panel (-Y front)."""
    # Dark recessed center panel
    kit.box((cx, front_y - 0.004, cz), (w - 0.012, 0.008, h - 0.012), 2)
    # Raised outer molded rails & stiles forming the recessed frame
    stile_w = 0.032
    rail_h = 0.036
    frame_d = 0.016
    fy = front_y - frame_d * 0.5
    kit.box((cx, fy, cz + h * 0.5 - rail_h * 0.5), (w - 0.004, frame_d, rail_h), 1)
    kit.box((cx, fy, cz - h * 0.5 + rail_h * 0.5), (w - 0.004, frame_d, rail_h), 1)
    inner_h = h - 2.0 * rail_h
    kit.box((cx - w * 0.5 + stile_w * 0.5 + 0.002, fy, cz), (stile_w, frame_d, inner_h), 1)
    kit.box((cx + w * 0.5 - stile_w * 0.5 - 0.002, fy, cz), (stile_w, frame_d, inner_h), 1)


def _add_vertical_pull(kit: Kit, px: float, front_y: float, pz: float) -> None:
    """Add a vertical tarnished brass cabinet pull handle on -Y face."""
    base_y = front_y - 0.016
    # Escutcheon backplate
    kit.box((px, base_y - 0.002, pz), (0.014, 0.004, 0.088), 3)
    # Standoff posts + vertical grip bar
    kit.box((px, base_y - 0.010, pz + 0.028), (0.008, 0.014, 0.010), 3)
    kit.box((px, base_y - 0.010, pz - 0.028), (0.008, 0.014, 0.010), 3)
    kit.box((px, base_y - 0.018, pz), (0.009, 0.008, 0.072), 3)


def build(kit: Kit) -> None:
    """Build wall-mounted wooden kitchen cabinet (Blender Z up, min_z=0, front=-Y, H=0.68m)."""
    cab_w = 1.240
    cab_d = 0.360
    front_y = -cab_d * 0.5  # -0.180m

    # 1. Underside wall-mounting cleat brackets (z: 0.0..0.032m, matching ref underside tabs)
    for bx in (-0.545, -0.024, 0.024, 0.545):
        kit.box((bx, 0.095, 0.016), (0.020, 0.145, 0.032), 0)

    # 2. Main cabinet carcass (z: 0.032..0.628m)
    kit.box((0.0, 0.0, 0.330), (cab_w, cab_d, 0.596), 0)

    # 3. Bottom plinth rail + center mullion + outer stiles
    kit.box((0.0, front_y - 0.006, 0.058), (cab_w + 0.006, 0.014, 0.052), 0)
    kit.box((0.0, front_y - 0.008, 0.356), (0.044, 0.016, 0.544), 0)
    for sx in (-1.0, 1.0):
        kit.box((sx * (cab_w * 0.5 - 0.018), front_y - 0.007, 0.356), (0.036, 0.014, 0.544), 0)

    # 4. Four tall recessed molded door panels (2 pairs, left & right of center mullion)
    door_zc = 0.354
    door_h = 0.520
    door_w = 0.278
    door_xs = (-0.438, -0.156, 0.156, 0.438)
    for dx in door_xs:
        _add_recessed_door(kit, dx, front_y, door_zc, door_w, door_h)

    # 5. Twin pairs of vertical metal pulls (matching ref inner-door handles)
    for px in (-0.314, -0.280, 0.280, 0.314):
        _add_vertical_pull(kit, px, front_y, 0.228)

    # 6. Stepped overhanging crown cornice (z: 0.628..0.680 -> exact 0.68m H)
    kit.box((0.0, -0.005, 0.640), (cab_w + 0.020, cab_d + 0.012, 0.024), 0)
    kit.box((0.0, -0.014, 0.666), (cab_w + 0.068, cab_d + 0.036, 0.028), 0, bevel=0.005)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_cabinet)
