"""Procedural Aged Soviet Wooden Dresser / Chest of Drawers (0.88m H).

Matches references /home/dkd/Downloads/hl2_refs/2026-10-30_18-32.png and
/home/dkd/Downloads/hl2_refs/2026-11-04_03-43_1.png:
- Short tapered wooden legs (min_y = 0) + lower apron skirt
- Framed carcass with recessed side panels and overhanging beveled top
- 3 tiers / 4 framed drawer fronts (2 wide upper drawers + 2 split lower drawers)
- Tarnished brass knobs & backplates
- 2048x2048 PBR atlas derived from dark_varnished_planks + tarnished_brass

Usage:
    /usr/bin/python3 tools/blender/props/wooden_dresser.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/wooden_dresser.py
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

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-30_18-32.png"

CFG: dict = {
    "slug": "wooden_dresser",
    "node_name": "WoodenDresser",
    "mat_name": "M_WoodenDresser",
    "script": __file__,
    "ref_image": REF_IMAGE,
    "tri_budget": 1200,
    "body": "static",
    "seed": 1832,
    "regions": [
        # 0: Carcass, overhanging top, legs, apron (warm-dark lacquered Soviet wood)
        {"base": (118, 74, 44), "var": 0.08, "grime": 0.25, "rust": 0.0, "rough": 0.44,
         "metal": 0.0, "normal": 1.6},
        # 1: Drawer fronts & raised molding frames (contrasted aged varnish)
        {"base": (128, 82, 48), "var": 0.10, "grime": 0.28, "rust": 0.0, "rough": 0.42,
         "metal": 0.0, "normal": 1.7},
        # 2: Recessed side panels & dark drawer shadow gaps
        {"base": (82, 50, 30), "var": 0.08, "grime": 0.35, "rust": 0.0, "rough": 0.56,
         "metal": 0.0, "normal": 1.8},
        # 3: Tarnished brass knobs & backplates
        {"base": (162, 134, 82), "var": 0.08, "grime": 0.30, "rust": 0.10, "rough": 0.36,
         "metal": 0.86, "normal": 1.2},
    ],
}


def _load_square(path: Path, size: int, mode: str) -> object:
    import numpy as np
    from PIL import Image

    img = Image.open(path).convert(mode).resize((size, size), Image.Resampling.BICUBIC)
    return np.asarray(img, dtype=np.float32)


def _paint_wood_and_brass(idx: int, maps: dict, half: int) -> None:
    """Blend photogrammetry dark_varnished_planks / tarnished_brass into region maps."""
    import numpy as np

    if idx in (0, 1, 2):
        wood_dir = KIT_ROOT / "assets" / "materials" / "dark_varnished_planks" / "textures"
        alb = _load_square(wood_dir / "dark_varnished_planks_albedo.png", half, "RGB")
        nrm = _load_square(wood_dir / "dark_varnished_planks_normal.png", half, "RGB") / 255.0 * 2.0 - 1.0
        orm = _load_square(wood_dir / "dark_varnished_planks_orm.png", half, "RGB") / 255.0

        # Tint to warm aged Soviet chestnut/walnut lacquer
        tint = {
            0: np.array([1.18, 0.96, 0.78], dtype=np.float32),
            1: np.array([1.28, 1.04, 0.82], dtype=np.float32),
            2: np.array([0.84, 0.72, 0.62], dtype=np.float32),
        }[idx]
        maps["alb"] = np.clip(alb * tint[None, None, :] * 0.82 + maps["alb"] * 0.18, 30.0, 230.0)
        mix_n = nrm * 0.75 + maps["nrm"] * 0.25
        mix_n[..., 2] = np.maximum(mix_n[..., 2], 0.25)
        mix_n /= np.sqrt(np.sum(mix_n * mix_n, axis=-1, keepdims=True))
        maps["nrm"] = mix_n
        rough_base = 0.42 if idx == 1 else (0.45 if idx == 0 else 0.56)
        maps["rough"] = np.clip(orm[..., 1] * 0.55 + rough_base * 0.45, 0.30, 0.72)
        maps["ao"] = np.clip(orm[..., 0] * 0.7 + maps["ao"] * 0.3, 0.50, 1.0)
        maps["metal"] = np.zeros((half, half), dtype=np.float32)
    elif idx == 3:
        brass_dir = KIT_ROOT / "assets" / "materials" / "tarnished_brass" / "textures"
        alb = _load_square(brass_dir / "tarnished_brass_albedo.png", half, "RGB")
        nrm = _load_square(brass_dir / "tarnished_brass_normal.png", half, "RGB") / 255.0 * 2.0 - 1.0
        orm = _load_square(brass_dir / "tarnished_brass_orm.png", half, "RGB") / 255.0
        maps["alb"] = np.clip(alb * 0.8 + maps["alb"] * 0.2, 35.0, 230.0)
        mix_n = nrm * 0.7 + maps["nrm"] * 0.3
        mix_n[..., 2] = np.maximum(mix_n[..., 2], 0.3)
        mix_n /= np.sqrt(np.sum(mix_n * mix_n, axis=-1, keepdims=True))
        maps["nrm"] = mix_n
        maps["rough"] = np.clip(orm[..., 1] * 0.7 + 0.12, 0.22, 0.58)
        maps["ao"] = np.clip(orm[..., 0], 0.55, 1.0)
        maps["metal"] = np.full((half, half), 0.85, dtype=np.float32)


def _add_tapered_leg(kit: Kit, cx: float, cy: float, h: float, region: int) -> None:
    """Build a 4-sided tapered corner leg grounded at z = 0.0."""
    b, t = 0.015, 0.024
    r_bot = [
        (cx - b, cy - b, 0.0),
        (cx + b, cy - b, 0.0),
        (cx + b, cy + b, 0.0),
        (cx - b, cy + b, 0.0),
    ]
    r_top = [
        (cx - t, cy - t, h),
        (cx + t, cy - t, h),
        (cx + t, cy + t, h),
        (cx - t, cy + t, h),
    ]
    kit.loft([r_bot, r_top], region, cap_start=True, cap_end=False)


def _add_framed_drawer(
    kit: Kit,
    cx: float,
    front_y: float,
    cz: float,
    w: float,
    h: float,
    knob_offsets: tuple[float, ...],
) -> None:
    """Build a framed drawer front with raised border molding and brass knobs (-Y front)."""
    # Outer raised molding frame around recessed drawer face
    frame_t = 0.022
    frame_d = 0.016
    face_d = 0.014
    kit.box((cx, front_y - face_d * 0.5, cz), (w, face_d, h), 1)
    # Top & bottom molding rails
    kit.box((cx, front_y - frame_d * 0.75, cz + h * 0.5 - frame_t * 0.5), (w, frame_d, frame_t), 1)
    kit.box((cx, front_y - frame_d * 0.75, cz - h * 0.5 + frame_t * 0.5), (w, frame_d, frame_t), 1)
    # Left & right molding stiles
    inner_h = h - 2.0 * frame_t
    kit.box((cx - w * 0.5 + frame_t * 0.5, front_y - frame_d * 0.75, cz), (frame_t, frame_d, inner_h), 1)
    kit.box((cx + w * 0.5 - frame_t * 0.5, front_y - frame_d * 0.75, cz), (frame_t, frame_d, inner_h), 1)

    # Brass backplates + knobs
    for kx in knob_offsets:
        px = cx + kx
        kit.box((px, front_y - face_d - 0.003, cz), (0.028, 0.006, 0.028), 3)
        kit.cyl((px, front_y - face_d - 0.014, cz), (0, -1, 0), 0.013, 0.018, 8, 3, radius2=0.009)


def build(kit: Kit) -> None:
    """Build Soviet wooden dresser (Blender Z up, min_z=0, front=-Y, total H=0.88m)."""
    leg_h = 0.110
    apron_h = 0.045
    body_z0 = leg_h + apron_h  # 0.155m
    top_thick = 0.034
    body_z1 = 0.880 - top_thick  # 0.846m
    body_h = body_z1 - body_z0  # 0.691m
    body_zc = 0.5 * (body_z0 + body_z1)

    body_w = 1.020
    body_d = 0.480
    front_y = -body_d * 0.5  # -0.240m

    # 1. Four tapered wooden feet grounded at z = 0.0
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            _add_tapered_leg(kit, sx * 0.455, sy * 0.195, leg_h + 0.005, region=0)

    # 2. Lower apron skirt & base molding rail
    kit.box((0.0, 0.0, leg_h + apron_h * 0.5), (body_w, body_d, apron_h), 0)
    kit.box((0.0, front_y - 0.006, leg_h + apron_h * 0.6), (body_w + 0.012, 0.012, apron_h * 0.8), 0)

    # 3. Main recessed carcass box + side panel stiles
    kit.box((0.0, 0.0, body_zc), (body_w - 0.028, body_d - 0.028, body_h - 0.004), 2)
    # Outer vertical corner stiles & top/bottom front face rails
    stile_w = 0.042
    for sx in (-1.0, 1.0):
        # Front corner stile
        kit.box((sx * (body_w * 0.5 - stile_w * 0.5), front_y + 0.020, body_zc), (stile_w, 0.040, body_h), 0)
        # Rear corner stile
        kit.box((sx * (body_w * 0.5 - stile_w * 0.5), body_d * 0.5 - 0.020, body_zc), (stile_w, 0.040, body_h), 0)
        # Top & bottom side rails framing recessed side panel
        kit.box((sx * (body_w * 0.5 - 0.014), 0.0, body_z1 - 0.024), (0.028, body_d - 0.080, 0.048), 0)
        kit.box((sx * (body_w * 0.5 - 0.014), 0.0, body_z0 + 0.024), (0.028, body_d - 0.080, 0.048), 0)
    # Rear solid panel
    kit.box((0.0, body_d * 0.5 - 0.010, body_zc), (body_w - 2.0 * stile_w, 0.020, body_h), 0)
    # Top & bottom front rails + drawer divider rails
    for rz in (body_z0 + 0.018, 0.376, 0.606, body_z1 - 0.018):
        kit.box((0.0, front_y + 0.016, rz), (body_w - 2.0 * stile_w, 0.032, 0.034), 0)

    # 4. Three drawer tiers (top wide, mid wide, bottom 2 split drawers)
    # Top wide drawer (z: 0.623..0.811)
    _add_framed_drawer(kit, 0.0, front_y, 0.717, 0.900, 0.184, (-0.26, 0.26))
    # Middle wide drawer (z: 0.393..0.589)
    _add_framed_drawer(kit, 0.0, front_y, 0.491, 0.900, 0.190, (-0.26, 0.26))
    # Bottom split pair (z: 0.173..0.359) + center divider mullion
    kit.box((0.0, front_y + 0.014, 0.266), (0.030, 0.028, 0.186), 0)
    _add_framed_drawer(kit, -0.232, front_y, 0.266, 0.432, 0.182, (0.0,))
    _add_framed_drawer(kit, 0.232, front_y, 0.266, 0.432, 0.182, (0.0,))

    # 5. Overhanging beveled top surface (z: 0.846..0.880 -> exact 0.88m H)
    kit.box((0.0, -0.006, 0.880 - top_thick * 0.5), (1.080, 0.530, top_thick), 0, bevel=0.006)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_wood_and_brass)
