#!/usr/bin/env python3
"""End-to-end Dark Man & Tactical Fire Axe post-processing and asset manifest builder.

Performs Gate 4 delighting on raw baked albedos, generates micro-detail normal/roughness
channels, packs 2048x2048 linear ORM textures (R=AO, G=Roughness, B=Metallic), cleans
temporary intermediate textures, and writes asset_manifest.json.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT_DIR = REPO_ROOT / "assets" / "models" / "dark_man"
BLENDER_SCRIPT = REPO_ROOT / "tools" / "blender" / "generators" / "dark_man.py"


def delight_albedo(raw_path: Path, out_path: Path, target_luma: float = 0.088, size: int = 2048) -> None:
    """Strips baked studio lighting gradients using masked low-pass normalization -> neutral carbon."""
    img = Image.open(raw_path).convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
    arr = np.asarray(img, dtype=np.float32) / 255.0

    # Masked blur prevents black UV gutters from dragging local denominator down around thin limbs
    valid = (arr.sum(axis=-1, keepdims=True) > 0.015).astype(np.float32)
    num_blur = np.asarray(
        Image.fromarray(np.clip(arr * valid * 255.0, 0, 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(radius=40)
        ),
        dtype=np.float32,
    ) / 255.0
    den_blur = np.asarray(
        Image.fromarray(np.clip(valid[:, :, 0] * 255.0, 0, 255).astype(np.uint8)).filter(
            ImageFilter.GaussianBlur(radius=40)
        ),
        dtype=np.float32,
    )[:, :, None] / 255.0

    local_avg = num_blur / np.maximum(den_blur, 0.15)
    local_luma = np.maximum(local_avg.mean(axis=-1, keepdims=True), 0.04)
    src_luma = arr.mean(axis=-1, keepdims=True)

    # Desaturate studio color casts while preserving subtle neutral fold micro-contrast
    ratio = (src_luma / local_luma) * target_luma
    carbon_luma = np.clip(ratio, target_luma * 0.68, target_luma * 1.45)
    neutral = np.repeat(carbon_luma, 3, axis=-1)
    # Keep only 20% of subtle neutral material tint, never chalky blue-grey glares
    blended = neutral * 0.85 + np.clip((arr / np.maximum(local_avg, 0.04)) * target_luma, 0.05, 0.13) * 0.15

    final_arr = np.where(valid > 0.5, blended, target_luma)
    delighted = np.clip(final_arr * 255.0, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(delighted, mode="RGB").save(out_path, format="PNG", optimize=True)


def enhance_suit_normal(
    raw_normal_path: Path,
    delighted_albedo_path: Path,
    out_path: Path,
    size: int = 2048,
) -> None:
    """Blends high-frequency garment fold bump onto Cycles tangent normal (+Y OpenGL)."""
    base_n = Image.open(raw_normal_path).convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
    alb_luma = Image.open(delighted_albedo_path).convert("L").resize((size, size), Image.Resampling.LANCZOS)

    n_arr = (np.asarray(base_n, dtype=np.float32) / 255.0) * 2.0 - 1.0
    h = np.asarray(alb_luma, dtype=np.float32) / 255.0
    # Compute subtle fabric wrinkle derivatives
    dh_dx = np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)
    dh_dy = np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)

    n_arr[:, :, 0] -= dh_dx * 1.4
    n_arr[:, :, 1] += dh_dy * 1.4  # OpenGL +Y up
    norm = np.maximum(np.linalg.norm(n_arr, axis=-1, keepdims=True), 1e-5)
    n_unit = np.clip(((n_arr / norm) * 0.5 + 0.5) * 255.0, 0.0, 255.0).astype(np.uint8)
    Image.fromarray(n_unit, mode="RGB").save(out_path, format="PNG", optimize=True)


def pack_suit_orm(ao_path: Path, albedo_path: Path, out_path: Path, size: int = 2048) -> None:
    """Packs 2048x2048 linear ORM for carbon-black semi-matte elastomer suit."""
    ao = Image.open(ao_path).convert("L").resize((size, size), Image.Resampling.LANCZOS)
    alb = Image.open(albedo_path).convert("L").resize((size, size), Image.Resampling.LANCZOS)

    ao_arr = np.asarray(ao, dtype=np.float32) / 255.0
    alb_arr = np.asarray(alb, dtype=np.float32) / 255.0

    # Semi-matte elastomer: creases rougher (~0.56), exposed surfaces (~0.36)
    rough_arr = np.clip(0.36 + (1.0 - ao_arr) * 0.22 + (0.10 - np.minimum(alb_arr, 0.10)) * 0.6, 0.28, 0.65)
    r_chan = np.clip(ao_arr * 255.0, 0.0, 255.0).astype(np.uint8)
    g_chan = np.clip(rough_arr * 255.0, 0.0, 255.0).astype(np.uint8)
    b_chan = np.zeros((size, size), dtype=np.uint8)

    orm = np.stack([r_chan, g_chan, b_chan], axis=-1)
    Image.fromarray(orm, mode="RGB").save(out_path, format="PNG", optimize=True)


def pack_axe_orm(
    ao_path: Path,
    rough_path: Path,
    metal_path: Path,
    out_path: Path,
    size: int = 2048,
) -> None:
    """Packs 2048x2048 linear ORM for fire axe (gunmetal steel head + vulcanized rubber grip)."""
    ao = np.maximum(np.asarray(Image.open(ao_path).convert("L").resize((size, size), Image.Resampling.LANCZOS), dtype=np.uint8), 56)
    rough = Image.open(rough_path).convert("L").resize((size, size), Image.Resampling.LANCZOS)
    metal = Image.open(metal_path).convert("L").resize((size, size), Image.Resampling.LANCZOS)

    orm = np.stack([
        ao,
        np.asarray(rough, dtype=np.uint8),
        np.asarray(metal, dtype=np.uint8),
    ], axis=-1)
    Image.fromarray(orm, mode="RGB").save(out_path, format="PNG", optimize=True)


def stitch_preview(out_dir: Path) -> None:
    """Combines 4 rendered verification views into dark_man_preview.png and cleans tiles."""
    names = ["front", "side", "back", "iso"]
    tiles = []
    for n in names:
        p = out_dir / f"_prev_dark_man_{n}.png"
        if p.is_file():
            tiles.append(Image.open(p).convert("RGB"))
            p.unlink()
    if len(tiles) == 4:
        w, h = tiles[0].size
        sheet = Image.new("RGB", (w * 4, h))
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * w, 0))
        sheet.save(out_dir / "dark_man_preview.png", format="PNG", optimize=True)


def finalize_assets(out_dir: Path, size: int = 2048) -> None:
    """Delights raw albedos, packs ORM textures, removes temp bakes, writes manifest."""
    delight_albedo(out_dir / "_raw_dark_man_albedo.png", out_dir / "dark_man_albedo.png", target_luma=0.088, size=size)
    enhance_suit_normal(out_dir / "dark_man_normal.png", out_dir / "dark_man_albedo.png", out_dir / "dark_man_normal.png", size=size)
    pack_suit_orm(out_dir / "_raw_dark_man_ao.png", out_dir / "dark_man_albedo.png", out_dir / "dark_man_orm.png", size=size)

    pack_axe_orm(
        out_dir / "_raw_fire_axe_ao.png",
        out_dir / "_raw_fire_axe_rough.png",
        out_dir / "_raw_fire_axe_metal.png",
        out_dir / "fire_axe_orm.png",
        size=size,
    )
    stitch_preview(out_dir)

    for tex_name in [
        "dark_man_albedo.png",
        "dark_man_normal.png",
        "dark_man_orm.png",
        "fire_axe_albedo.png",
        "fire_axe_normal.png",
        "fire_axe_orm.png",
    ]:
        arr = np.asarray(Image.open(out_dir / tex_name))
        if int(arr.max()) <= int(arr.min()):
            raise RuntimeError(f"Baked texture {tex_name} is flat/empty (min={arr.min()}, max={arr.max()})")
        print(f"[DarkMan] Verified {tex_name}: min={arr.min(axis=(0, 1)).tolist()} max={arr.max(axis=(0, 1)).tolist()}")

    axe_orm = np.asarray(Image.open(out_dir / "fire_axe_orm.png"))
    if int(axe_orm[:, :, 2].max()) < 200:
        raise RuntimeError(f"fire_axe_orm Metallic channel missing/too low: max={axe_orm[:, :, 2].max()}")
    dm_alb = np.asarray(Image.open(out_dir / "dark_man_albedo.png"))
    if int(dm_alb.max()) > 45:
        raise RuntimeError(f"dark_man_albedo too bright after delighting: max={dm_alb.max()}")

    stats = {}
    stats_file = out_dir / "_bake_stats.json"
    if stats_file.is_file():
        stats = json.loads(stats_file.read_text(encoding="utf-8"))

    # Remove intermediate scratch bakes
    for tmp_name in [
        "_raw_dark_man_albedo.png",
        "_raw_dark_man_ao.png",
        "_raw_fire_axe_ao.png",
        "_raw_fire_axe_rough.png",
        "_raw_fire_axe_metal.png",
        "_bake_stats.json",
    ]:
        p = out_dir / tmp_name
        if p.is_file():
            p.unlink()

    manifest = {
        "prop_slug": "dark_man",
        "assets": ["dark_man.glb", "fire_axe.glb"],
        "dark_man_tris": stats.get("dark_man_tris", 15000),
        "fire_axe_tris": stats.get("fire_axe_tris", 1900),
        "physics_layer": "Layer 5 Enemies",
        "render_layer": "Layer 3 Interactive",
        "skeleton_profile": "SkeletonProfileHumanoid",
        "animations": ["Idle_Hold_Axe"],
        "texture_resolution": f"{size}x{size}",
        "generator": "TRELLIS + Blender 5.x Cycles Bake + Auto-Rig",
    }
    (out_dir / "asset_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"[DarkMan] Assets finalized in {out_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Finalize Dark Man & Fire Axe assets.")
    parser.add_argument("--raw-body", type=Path, default=None, help="Optional raw TRELLIS body GLB to run Blender step")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--tex-size", type=int, default=2048)
    args = parser.parse_args()

    if args.raw_body is not None:
        cmd = [
            "/snap/bin/blender", "--background", "--python", str(BLENDER_SCRIPT),
            "--", "--raw-body", str(args.raw_body), "--out-dir", str(args.out_dir), "--tex-size", str(args.tex_size),
        ]
        subprocess.run(cmd, check=True)

    finalize_assets(args.out_dir, size=args.tex_size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
