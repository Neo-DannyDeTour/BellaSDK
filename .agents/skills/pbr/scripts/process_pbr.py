#!/usr/bin/env python3
"""PBR Texture Processing & Godot 4 ORMMaterial3D Generator.

Implements albedo delighting, PBR sRGB bounds clamping, cyclic seam inspection,
preset-aware companion map derivation, Godot 4 ORM packing, and .tres export.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict, Optional, Tuple

import numpy as np
from PIL import Image, ImageChops, ImageFilter

MATERIAL_PRESETS: Dict[str, Dict[str, float | bool]] = {
    "stone": {
        "base_roughness": 0.86,
        "rough_min": 0.62,
        "rough_max": 0.98,
        "normal_strength": 3.5,
        "is_metallic": False,
        "metallic": 0.0,
    },
    "plaster": {
        "base_roughness": 0.88,
        "rough_min": 0.68,
        "rough_max": 0.98,
        "normal_strength": 2.8,
        "is_metallic": False,
        "metallic": 0.0,
    },
    "wood": {
        "base_roughness": 0.72,
        "rough_min": 0.42,
        "rough_max": 0.92,
        "normal_strength": 2.5,
        "is_metallic": False,
        "metallic": 0.0,
    },
    "metal": {
        "base_roughness": 0.35,
        "rough_min": 0.12,
        "rough_max": 0.72,
        "normal_strength": 2.2,
        "is_metallic": True,
        "metallic": 1.0,
    },
    "fabric": {
        "base_roughness": 0.90,
        "rough_min": 0.75,
        "rough_max": 0.99,
        "normal_strength": 2.0,
        "is_metallic": False,
        "metallic": 0.0,
    },
    "wet": {
        "base_roughness": 0.22,
        "rough_min": 0.05,
        "rough_max": 0.55,
        "normal_strength": 2.5,
        "is_metallic": False,
        "metallic": 0.0,
    },
}


def _wrap_gaussian(arr: np.ndarray, sigma: float, seamless: bool = True) -> np.ndarray:
    """Apply Gaussian blur using cyclic padding so tile boundaries wrap cleanly."""
    pad = max(1, int(round(sigma * 3.0)))
    mode = "wrap" if seamless else "reflect"
    if arr.ndim == 2:
        padded = np.pad(arr, ((pad, pad), (pad, pad)), mode=mode)
        img = Image.fromarray(np.clip(padded * 255.0, 0, 255).astype(np.uint8), mode="L")
        blurred = np.array(img.filter(ImageFilter.GaussianBlur(radius=sigma)), dtype=np.float32) / 255.0
        return blurred[pad:-pad, pad:-pad]

    channels = []
    for ch in range(arr.shape[2]):
        channels.append(_wrap_gaussian(arr[..., ch], sigma, seamless=seamless))
    return np.stack(channels, axis=-1)


def _wrap_sobel(arr: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Compute wrap-safe X and Y gradients matching Sobel kernel weights."""
    xm1 = np.roll(arr, 1, axis=1)
    xp1 = np.roll(arr, -1, axis=1)
    ym1 = np.roll(arr, 1, axis=0)
    yp1 = np.roll(arr, -1, axis=0)

    dx = (
        (np.roll(xp1, 1, axis=0) + 2.0 * xp1 + np.roll(xp1, -1, axis=0))
        - (np.roll(xm1, 1, axis=0) + 2.0 * xm1 + np.roll(xm1, -1, axis=0))
    ) / 8.0
    dy = (
        (np.roll(yp1, 1, axis=1) + 2.0 * yp1 + np.roll(yp1, -1, axis=1))
        - (np.roll(ym1, 1, axis=1) + 2.0 * ym1 + np.roll(ym1, -1, axis=1))
    ) / 8.0
    return dx, dy


def delight_albedo(
    albedo_img: Image.Image,
    strength: float = 0.65,
    seamless: bool = True,
    srgb_min: int = 30,
    srgb_max: int = 240,
) -> Image.Image:
    """Flatten uneven macro lighting/shadows and clamp albedo to valid PBR range."""
    rgb = albedo_img.convert("RGB")
    arr = np.array(rgb, dtype=np.float32) / 255.0
    lum = np.clip(0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2], 1e-4, 1.0)

    radius = max(12.0, min(arr.shape[0], arr.shape[1]) * 0.08)
    macro_lum = np.clip(_wrap_gaussian(lum, sigma=radius, seamless=seamless), 1e-4, 1.0)
    target_mid = float(np.median(macro_lum))

    # Multiplicatively equalize macro lighting shifts without altering chroma hue ratios
    ratio = (target_mid / macro_lum) ** float(np.clip(strength, 0.0, 1.0))
    ratio = np.clip(ratio, 0.65, 1.6)
    delit = arr * ratio[..., None]

    lo = float(srgb_min) / 255.0
    hi = float(srgb_max) / 255.0
    delit = np.clip(delit, lo, hi)
    return Image.fromarray((delit * 255.0).astype(np.uint8), mode="RGB")


def derive_companion_maps(
    albedo_img: Image.Image,
    normal_strength: Optional[float] = None,
    base_roughness: Optional[float] = None,
    is_metallic: Optional[bool] = None,
    preset: str = "stone",
    seamless: bool = True,
) -> Tuple[Image.Image, Image.Image, Image.Image, Image.Image]:
    """Derive pixel-aligned Normal (+Y), Height, AO, and Roughness maps from albedo."""
    cfg = MATERIAL_PRESETS.get(preset, MATERIAL_PRESETS["stone"])
    eff_norm = float(normal_strength if normal_strength is not None else cfg["normal_strength"])
    eff_rough = float(base_roughness if base_roughness is not None else cfg["base_roughness"])
    eff_metal = bool(is_metallic if is_metallic is not None else cfg["is_metallic"])
    rough_min = float(cfg["rough_min"])
    rough_max = float(cfg["rough_max"])

    rgb = albedo_img.convert("RGB")
    arr = np.array(rgb, dtype=np.float32) / 255.0
    lum = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]

    # Band-pass height synthesis suppresses large painted color blotches while keeping surface relief
    macro = _wrap_gaussian(lum, sigma=24.0, seamless=seamless)
    mid = _wrap_gaussian(lum, sigma=3.0, seamless=seamless)
    fine = lum - mid
    mid_band = mid - macro
    height = 0.5 + 0.65 * mid_band + 0.45 * fine

    h_min, h_max = float(np.percentile(height, 2)), float(np.percentile(height, 98))
    height = np.clip((height - h_min) / (h_max - h_min + 1e-5), 0.0, 1.0)
    height_img = Image.fromarray((height * 255.0).astype(np.uint8), mode="L")

    # Tangent-space Normal map (Godot +Y OpenGL convention)
    dx, dy = _wrap_sobel(height)
    dx *= eff_norm * 4.0
    dy *= eff_norm * 4.0
    dz = np.ones_like(height)

    norm = np.sqrt(dx * dx + dy * dy + dz * dz)
    nx = dx / norm
    ny = -dy / norm
    nz = dz / norm

    norm_rgb = np.zeros((*height.shape, 3), dtype=np.uint8)
    norm_rgb[..., 0] = np.clip((nx * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    norm_rgb[..., 1] = np.clip((ny * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    norm_rgb[..., 2] = np.clip((nz * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    normal_img = Image.fromarray(norm_rgb, mode="RGB")

    # Crevice Ambient Occlusion
    large_smooth = _wrap_gaussian(height, sigma=14.0, seamless=seamless)
    crevice = np.clip((height - large_smooth) * 2.2 + 0.85, 0.25, 1.0)
    ao_img = Image.fromarray((crevice * 255.0).astype(np.uint8), mode="L")

    # Preset-calibrated Roughness map (crevices rougher, exposed high points slightly smoother)
    micro_var = (0.5 - height) * 0.22 + (arr[..., 0] - lum) * 0.06
    if eff_metal:
        rough = np.clip(eff_rough + micro_var, rough_min, rough_max)
    else:
        rough = np.clip(eff_rough + micro_var, rough_min, rough_max)
    roughness_img = Image.fromarray((rough * 255.0).astype(np.uint8), mode="L")

    return normal_img, height_img, ao_img, roughness_img


def offset_image(img: Image.Image, offset_x: Optional[int] = None, offset_y: Optional[int] = None) -> Image.Image:
    """Wrap texture by half width and half height (Photoshop Offset filter equivalent)."""
    w, h = img.size
    ox = w // 2 if offset_x is None else offset_x
    oy = h // 2 if offset_y is None else offset_y
    return ImageChops.offset(img, ox, oy)


def calculate_seam_score(img: Image.Image) -> float:
    """Calculate mean pixel delta across opposite edges (horizontal and vertical seams)."""
    rgb = img.convert("RGB")
    arr = np.array(rgb, dtype=np.float32)

    diff_v = np.mean(np.abs(arr[0, :, :] - arr[-1, :, :]))
    diff_h = np.mean(np.abs(arr[:, 0, :] - arr[:, -1, :]))
    return float((diff_v + diff_h) / 2.0)


def blend_seams(img: Image.Image, blend_radius: int = 32) -> Image.Image:
    """Cross-fade opposite boundaries with smoothstep falloff to eliminate wrap seams."""
    rgba = img.convert("RGBA")
    arr = np.array(rgba, dtype=np.float32)
    h, w, _ = arr.shape
    rad = max(2, min(blend_radius, w // 4, h // 4))

    t = np.linspace(0.0, 1.0, rad, dtype=np.float32)
    smooth = 3.0 * t * t - 2.0 * t * t * t
    weights = 0.5 * (1.0 - smooth)

    for dist in range(rad):
        wt = float(weights[dist])
        left_color = arr[:, dist, :].copy()
        right_color = arr[:, w - 1 - dist, :].copy()
        arr[:, dist, :] = left_color * (1.0 - wt) + right_color * wt
        arr[:, w - 1 - dist, :] = right_color * (1.0 - wt) + left_color * wt

    for dist in range(rad):
        wt = float(weights[dist])
        top_color = arr[dist, :, :].copy()
        bottom_color = arr[h - 1 - dist, :, :].copy()
        arr[dist, :, :] = top_color * (1.0 - wt) + bottom_color * wt
        arr[h - 1 - dist, :, :] = bottom_color * (1.0 - wt) + top_color * wt

    result = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(result, mode="RGBA").convert(img.mode)


def pack_orm(
    ao_path: Optional[Path],
    roughness_path: Optional[Path],
    metallic_path_or_val: str,
    output_path: Path,
    target_size: Optional[Tuple[int, int]] = None,
) -> Path:
    """Pack Occlusion (R), Roughness (G), Metallic (B) into single Godot 4 ORM PNG."""
    base_size = target_size

    def load_channel(path: Optional[Path], default_val: int) -> Image.Image:
        nonlocal base_size
        if path and path.is_file():
            loaded = Image.open(path).convert("L")
            if base_size is None:
                base_size = loaded.size
            elif loaded.size != base_size:
                loaded = loaded.resize(base_size, Image.Resampling.LANCZOS)
            return loaded
        if base_size is None:
            base_size = (2048, 2048)
        return Image.new("L", base_size, default_val)

    roughness_img = load_channel(roughness_path, 190)
    ao_img = load_channel(ao_path, 255)

    try:
        metal_val = float(metallic_path_or_val)
        int_val = int(np.clip(metal_val * 255.0, 0, 255))
        metal_img = Image.new("L", base_size, int_val)
    except ValueError:
        metal_img = load_channel(Path(metallic_path_or_val), 0)

    orm_img = Image.merge("RGB", (ao_img, roughness_img, metal_img))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    orm_img.save(output_path, format="PNG", optimize=True)
    return output_path


def to_res_path(path: Path) -> str:
    """Convert filesystem path to Godot res:// path relative to project.godot."""
    try:
        resolved = path.resolve()
        current = resolved
        while current != current.parent:
            if (current / "project.godot").is_file():
                rel = resolved.relative_to(current).as_posix()
                return f"res://{rel}"
            current = current.parent
    except Exception:
        pass
    return f"res://{path.as_posix()}"


def generate_godot_tres(
    material_name: str,
    albedo_path: Path,
    normal_path: Optional[Path],
    orm_path: Path,
    height_path: Optional[Path],
    output_tres: Path,
    uv_scale: Tuple[float, float, float] = (1.0, 1.0, 1.0),
    height_scale: float = 0.05,
    triplanar: bool = False,
) -> Path:
    """Generate Godot 4 ORMMaterial3D (.tres) matching BellaSDK format."""
    if triplanar and height_path and height_path.is_file():
        raise ValueError("heightmap_enabled cannot be combined with uv1_triplanar in Godot 4.")

    ext_resources = []
    load_step_idx = 1

    albedo_res = to_res_path(albedo_path)
    ext_resources.append(f'[ext_resource type="Texture2D" path="{albedo_res}" id="{load_step_idx}_albedo"]')
    albedo_id = f"{load_step_idx}_albedo"
    load_step_idx += 1

    orm_res = to_res_path(orm_path)
    ext_resources.append(f'[ext_resource type="Texture2D" path="{orm_res}" id="{load_step_idx}_orm"]')
    orm_id = f"{load_step_idx}_orm"
    load_step_idx += 1

    normal_id = None
    if normal_path and normal_path.is_file():
        normal_res = to_res_path(normal_path)
        ext_resources.append(f'[ext_resource type="Texture2D" path="{normal_res}" id="{load_step_idx}_normal"]')
        normal_id = f"{load_step_idx}_normal"
        load_step_idx += 1

    height_id = None
    if height_path and height_path.is_file():
        height_res = to_res_path(height_path)
        ext_resources.append(f'[ext_resource type="Texture2D" path="{height_res}" id="{load_step_idx}_height"]')
        height_id = f"{load_step_idx}_height"
        load_step_idx += 1

    content_lines = [
        f'[gd_resource type="ORMMaterial3D" load_steps={load_step_idx} format=3]',
        "",
        "\n".join(ext_resources),
        "",
        "[resource]",
        f'resource_name = "{material_name}"',
        f'albedo_texture = ExtResource("{albedo_id}")',
        f'orm_texture = ExtResource("{orm_id}")',
        "roughness = 1.0",
        "metallic = 1.0",
    ]

    if normal_id:
        content_lines.append("normal_enabled = true")
        content_lines.append(f'normal_texture = ExtResource("{normal_id}")')

    if height_id:
        content_lines.append("heightmap_enabled = true")
        content_lines.append(f"heightmap_scale = {height_scale}")
        content_lines.append(f'heightmap_texture = ExtResource("{height_id}")')

    if triplanar:
        content_lines.append("uv1_triplanar = true")

    content_lines.append(f"uv1_scale = Vector3({uv_scale[0]}, {uv_scale[1]}, {uv_scale[2]})")
    content_lines.append("")

    output_tres.parent.mkdir(parents=True, exist_ok=True)
    output_tres.write_text("\n".join(content_lines), encoding="utf-8")
    return output_tres


def main() -> None:
    parser = argparse.ArgumentParser(description="PBR Material Texture Processor & Godot 4 Generator")
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_p = subparsers.add_parser("check-seams", help="Wrap image and report seam score")
    check_p.add_argument("image", type=Path, help="Input texture image")
    check_p.add_argument("--save-offset", type=Path, default=None, help="Save wrapped offset image")
    check_p.add_argument("--threshold", type=float, default=12.0, help="Max tolerable seam delta score")

    blend_p = subparsers.add_parser("blend-seams", help="Smoothstep cross-fade opposing edges")
    blend_p.add_argument("image", type=Path, help="Input texture image")
    blend_p.add_argument("--output", "-o", type=Path, required=True, help="Output image path")
    blend_p.add_argument("--radius", type=int, default=32, help="Blend boundary pixel radius")

    delight_p = subparsers.add_parser("delight", help="Flatten macro lighting and clamp PBR albedo")
    delight_p.add_argument("image", type=Path, help="Input albedo image")
    delight_p.add_argument("--output", "-o", type=Path, required=True, help="Output delit albedo")
    delight_p.add_argument("--strength", type=float, default=0.65, help="Delight strength (0.0-1.0)")
    delight_p.add_argument("--non-seamless", action="store_true", help="Disable wrap padding (for UV atlases)")

    pack_p = subparsers.add_parser("pack-orm", help="Pack AO, Roughness, Metallic into single RGB texture")
    pack_p.add_argument("--ao", type=Path, default=None, help="AO map path (Red)")
    pack_p.add_argument("--roughness", type=Path, required=True, help="Roughness map path (Green)")
    pack_p.add_argument("--metallic", type=str, default="0.0", help="Metallic map path or float 0.0-1.0")
    pack_p.add_argument("--output", "-o", type=Path, required=True, help="Output ORM image path")

    tres_p = subparsers.add_parser("build-tres", help="Generate Godot 4 ORMMaterial3D (.tres)")
    tres_p.add_argument("--name", type=str, required=True, help="Material resource name")
    tres_p.add_argument("--albedo", type=Path, required=True, help="Albedo texture path")
    tres_p.add_argument("--orm", type=Path, required=True, help="ORM texture path")
    tres_p.add_argument("--normal", type=Path, default=None, help="Normal texture path")
    tres_p.add_argument("--height", type=Path, default=None, help="Optional Heightmap path (incompatible w/ triplanar)")
    tres_p.add_argument("--output", "-o", type=Path, required=True, help="Output .tres path")
    tres_p.add_argument("--height-scale", type=float, default=0.05, help="Heightmap displacement depth")
    tres_p.add_argument("--triplanar", action="store_true", help="Enable uv1_triplanar")

    derive_p = subparsers.add_parser("derive-maps", help="Derive Normal, Height, AO, and Roughness from Albedo")
    derive_p.add_argument("albedo", type=Path, help="Input Albedo texture path")
    derive_p.add_argument("--out-dir", "-o", type=Path, required=True, help="Output texture directory")
    derive_p.add_argument("--slug", type=str, required=True, help="Material slug prefix")
    derive_p.add_argument(
        "--preset",
        choices=sorted(MATERIAL_PRESETS.keys()),
        default="stone",
        help="Material roughness/relief preset",
    )
    derive_p.add_argument("--normal-strength", type=float, default=None, help="Override normal strength")
    derive_p.add_argument("--base-roughness", type=float, default=None, help="Override base roughness")
    derive_p.add_argument("--metallic", action="store_true", help="Force metallic calibration")
    derive_p.add_argument("--delight", action="store_true", help="Delight & clamp albedo in-place/out-dir")
    derive_p.add_argument("--delight-strength", type=float, default=0.65, help="Delight strength (0.0-1.0)")
    derive_p.add_argument("--non-seamless", action="store_true", help="Use reflect pad for UV atlases")

    args = parser.parse_args()

    if args.command == "check-seams":
        if not args.image.is_file():
            print(f"Error: File not found {args.image}", file=sys.stderr)
            sys.exit(1)
        img = Image.open(args.image)
        score = calculate_seam_score(img)
        print(f"Seam Score: {score:.2f} (Threshold: {args.threshold:.2f})")
        if args.save_offset:
            offset_img = offset_image(img)
            offset_img.save(args.save_offset)
            print(f"Offset preview saved to: {args.save_offset}")
        if score > args.threshold:
            print(
                f"FAIL: Visible seam detected (score {score:.2f} > {args.threshold:.2f}). "
                "Note: structured grids (bricks/tiles/planks) ghost under blend-seams; regenerate or inpaint offset instead."
            )
            sys.exit(2)
        print("PASS: Texture appears seamless.")
        sys.exit(0)

    elif args.command == "blend-seams":
        if not args.image.is_file():
            print(f"Error: File not found {args.image}", file=sys.stderr)
            sys.exit(1)
        print("Note: blend-seams works best on organic noise; inspect *_offset.png for brick/tile ghosting.")
        img = Image.open(args.image)
        blended = blend_seams(img, args.radius)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        blended.save(args.output)
        print(f"Blended seamless texture saved to: {args.output}")

    elif args.command == "delight":
        if not args.image.is_file():
            print(f"Error: File not found {args.image}", file=sys.stderr)
            sys.exit(1)
        img = Image.open(args.image)
        delit = delight_albedo(img, strength=args.strength, seamless=not args.non_seamless)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        delit.save(args.output, format="PNG")
        print(f"Delighted PBR albedo saved to: {args.output}")

    elif args.command == "pack-orm":
        out = pack_orm(args.ao, args.roughness, args.metallic, args.output)
        print(f"ORM texture generated: {out}")

    elif args.command == "build-tres":
        tres = generate_godot_tres(
            args.name,
            args.albedo,
            args.normal,
            args.orm,
            args.height,
            args.output,
            height_scale=args.height_scale,
            triplanar=args.triplanar,
        )
        print(f"Godot 4 ORMMaterial3D created: {tres}")

    elif args.command == "derive-maps":
        if not args.albedo.is_file():
            print(f"Error: File not found {args.albedo}", file=sys.stderr)
            sys.exit(1)
        alb_img = Image.open(args.albedo)
        args.out_dir.mkdir(parents=True, exist_ok=True)
        if args.delight:
            alb_img = delight_albedo(
                alb_img,
                strength=args.delight_strength,
                seamless=not args.non_seamless,
            )
            delit_path = args.out_dir / f"{args.slug}_albedo.png"
            alb_img.save(delit_path, format="PNG")
            print(f"Delighted albedo saved: {delit_path}")

        normal_img, height_img, ao_img, rough_img = derive_companion_maps(
            alb_img,
            normal_strength=args.normal_strength,
            base_roughness=args.base_roughness,
            is_metallic=True if args.metallic else None,
            preset=args.preset,
            seamless=not args.non_seamless,
        )
        norm_path = args.out_dir / f"{args.slug}_normal.png"
        height_path = args.out_dir / f"{args.slug}_height.png"
        ao_path = args.out_dir / f"{args.slug}_ao.png"
        rough_path = args.out_dir / f"{args.slug}_roughness.png"

        normal_img.save(norm_path, format="PNG")
        height_img.save(height_path, format="PNG")
        ao_img.save(ao_path, format="PNG")
        rough_img.save(rough_path, format="PNG")

        print(f"Normal map saved: {norm_path}")
        print(f"Height map saved: {height_path}")
        print(f"AO map saved: {ao_path}")
        print(f"Roughness map saved: {rough_path}")


if __name__ == "__main__":
    main()
