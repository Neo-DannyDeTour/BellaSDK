"""Procedural Ribbed Industrial HDPE Plastic Milk Crate (0.30m H).

Matches reference /home/dkd/Downloads/hl2_refs/2026-10-29_18-22.png:
- Molded safety-yellow HDPE plastic crate (min_y = 0, H = 0.30m, L = 0.44m, D = 0.34m)
- Reinforced corner posts, top & bottom rails, mid-height rib band
- Open slatted sidewalls, recessed end carry handles, molded grid floor
- Single mesh, RigidBody3D (collision_layer = 4, collision_mask = 7, BoxShape3D)

Usage:
    /usr/bin/python3 tools/blender/props/plastic_milk_crate.py --gen-textures
    python3 tools/blender/run.py tools/blender/props/plastic_milk_crate.py
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

REF_IMAGE: str = "/home/dkd/Downloads/hl2_refs/2026-10-29_18-22.png"

CFG: dict = {
    "slug": "plastic_milk_crate",
    "node_name": "PlasticMilkCrate",
    "mat_name": "M_PlasticMilkCrate",
    "script": __file__,
    "ref_image": REF_IMAGE,
    "tri_budget": 1200,
    "body": "rigid",
    "mass": 2.4,
    "seed": 18220,
    "regions": [
        # 0: Molded safety-yellow HDPE outer rims & corner posts
        {"base": (204, 168, 28), "var": 0.07, "grime": 0.28, "rust": 0.0, "rough": 0.48,
         "metal": 0.0, "normal": 1.1},
        # 1: Sidewall slats & ribs (slightly scuffed yellow HDPE)
        {"base": (196, 160, 26), "var": 0.08, "grime": 0.32, "rust": 0.0, "rough": 0.50,
         "metal": 0.0, "normal": 1.2},
        # 2: Floor grid & recessed inner rim (slightly dirtier grime in recesses)
        {"base": (176, 144, 24), "var": 0.08, "grime": 0.42, "rust": 0.0, "rough": 0.54,
         "metal": 0.0, "normal": 1.2},
        # 3: Handle lips & stacking lugs (scuffed yellow HDPE)
        {"base": (212, 178, 34), "var": 0.06, "grime": 0.22, "rust": 0.0, "rough": 0.45,
         "metal": 0.0, "normal": 1.0},
    ],
}


def _paint_hdpe(idx: int, maps: dict, half: int) -> None:
    """Blend weathered HDPE micro-texture + scuff roughness (~0.48)."""
    import numpy as np
    from PIL import Image

    hdpe_dir = KIT_ROOT / "assets" / "materials" / "hdpe_weathered_plastic" / "textures"
    if (hdpe_dir / "hdpe_weathered_plastic_normal.png").is_file():
        nrm = (
            np.asarray(
                Image.open(hdpe_dir / "hdpe_weathered_plastic_normal.png")
                .convert("RGB")
                .resize((half, half), Image.Resampling.BICUBIC),
                dtype=np.float32,
            )
            / 255.0
            * 2.0
            - 1.0
        )
        orm = (
            np.asarray(
                Image.open(hdpe_dir / "hdpe_weathered_plastic_orm.png")
                .convert("RGB")
                .resize((half, half), Image.Resampling.BICUBIC),
                dtype=np.float32,
            )
            / 255.0
        )
        mix_n = nrm * 0.65 + maps["nrm"] * 0.35
        mix_n[..., 2] = np.maximum(mix_n[..., 2], 0.35)
        mix_n /= np.sqrt(np.sum(mix_n * mix_n, axis=-1, keepdims=True))
        maps["nrm"] = mix_n
        maps["rough"] = np.clip(orm[..., 1] * 0.45 + 0.26, 0.38, 0.64)
        maps["ao"] = np.clip(orm[..., 0] * 0.75 + maps["ao"] * 0.25, 0.55, 1.0)
    maps["metal"] = np.zeros((half, half), dtype=np.float32)


def build(kit: Kit) -> None:
    """Build molded ribbed plastic milk crate (Blender Z up, min_z=0, L=0.44m, D=0.34m, H=0.30m)."""
    L = 0.440
    D = 0.340
    H = 0.300
    hx = L * 0.5  # 0.220
    hy = D * 0.5  # 0.170

    # 1. Four sturdy corner posts (z: 0.0..0.300) + proud outer corner rib buttresses
    post_w = 0.036
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            px = sx * (hx - post_w * 0.5)
            py = sy * (hy - post_w * 0.5)
            kit.box((px, py, H * 0.5), (post_w, post_w, H), 0)
            # Outer molded corner reinforcement ribs (offset outside post face by 0.002m)
            kit.box((sx * (hx - 0.005), sy * (hy - 0.044), H * 0.5), (0.014, 0.012, H - 0.020), 0)
            kit.box((sx * (hx - 0.044), sy * (hy - 0.005), H * 0.5), (0.012, 0.014, H - 0.020), 0)

    # 2. Reinforced top perimeter rim & bottom base rail spanning cleanly between corner posts
    rim_h = 0.026
    rim_t = 0.022
    span_x = L - 2.0 * post_w - 0.002
    span_y = D - 2.0 * post_w - 0.002
    for zc in (rim_h * 0.5, H - rim_h * 0.5):
        for sy in (-1.0, 1.0):
            kit.box((0.0, sy * (hy - rim_t * 0.5 - 0.002), zc), (span_x, rim_t, rim_h), 0)
        for sx in (-1.0, 1.0):
            kit.box((sx * (hx - rim_t * 0.5 - 0.002), 0.0, zc), (rim_t, span_y, rim_h), 0)

    # 3. Mid-height horizontal structural rib band (inset 0.004m from outer rim)
    mid_z = 0.144
    band_t = 0.016
    band_span_x = L - 2.0 * post_w - 0.002
    band_span_y = D - 2.0 * post_w - 0.002
    for sy in (-1.0, 1.0):
        kit.box((0.0, sy * (hy - 0.013), mid_z), (band_span_x, band_t, 0.024), 1)
    for sx in (-1.0, 1.0):
        kit.box((sx * (hx - 0.013), 0.0, mid_z), (band_t, band_span_y, 0.024), 1)

    # 4. Long sidewalls (y = ±hy): 7 vertical molded slats + 2 horizontal bars (non-coplanar depths)
    slat_span_z = H - 2.0 * rim_h - 0.002
    for sy in (-1.0, 1.0):
        wy = sy * (hy - 0.013)
        kit.box((0.0, wy, 0.072), (band_span_x, 0.014, 0.014), 1)
        kit.box((0.0, wy, 0.214), (band_span_x, 0.014, 0.014), 1)
        for i in range(7):
            sx_pos = -0.150 + i * 0.050
            kit.box((sx_pos, wy, H * 0.5), (0.012, 0.010, slat_span_z), 1)

    # 5. Short end walls (x = ±hx) with recessed open carry-handle slots near top
    for sx in (-1.0, 1.0):
        wx = sx * (hx - 0.013)
        # Reinforced handle sill bar + flanking vertical struts
        kit.box((wx, 0.0, 0.204), (0.020, 0.168, 0.018), 3)
        for sy in (-1.0, 1.0):
            kit.box((wx, sy * 0.076, 0.239), (0.016, 0.016, 0.054), 3)
        # Lower horizontal bar + 4 vertical slats (non-coplanar with horizontal bars)
        kit.box((wx, 0.0, 0.072), (0.014, band_span_y, 0.014), 1)
        for yp in (-0.110, -0.042, 0.042, 0.110):
            slat_top = 0.194 if abs(yp) < 0.08 else (H - rim_h - 0.002)
            slat_bot = rim_h + 0.001
            kit.box((wx, yp, 0.5 * (slat_top + slat_bot)), (0.010, 0.012, slat_top - slat_bot), 1)

    # 6. Molded floor grid (non-coplanar heights between longitudinal and transverse ribs)
    floor_x = L - 0.044
    floor_y = D - 0.044
    for i in range(6):
        fx = -0.150 + i * 0.060
        kit.box((fx, 0.0, 0.011), (0.014, floor_y, 0.014), 2)
    for j in range(5):
        fy = -0.110 + j * 0.055
        kit.box((0.0, fy, 0.011), (floor_x, 0.012, 0.010), 2)


if __name__ == "__main__":
    run_prop(CFG, build, painter=_paint_hdpe)
