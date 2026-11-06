#!/usr/bin/env python3
"""
PBR Texture Processing & Godot 4 ORMMaterial3D Generator
Implements Nuno Silva's seam inspection and Godot 4 60 FPS ORM texture packing.
"""

import argparse
import sys
from pathlib import Path
from typing import Optional, Tuple
import numpy as np
from PIL import Image, ImageChops
from scipy.ndimage import gaussian_filter, sobel


def derive_companion_maps(
    albedo_img: Image.Image,
    normal_strength: float = 3.5,
    base_roughness: float = 0.88,
    is_metallic: bool = False,
) -> Tuple[Image.Image, Image.Image, Image.Image, Image.Image]:
    """
    Derives pixel-aligned Normal, Height (medium contrast), AO, and Roughness maps
    with cyclic boundary wrapping to guarantee seamless continuity matching the Albedo.
    """
    rgb = albedo_img.convert("RGB")
    arr = np.array(rgb, dtype=np.float32) / 255.0

    # Luminance estimation
    lum = 0.299 * arr[..., 0] + 0.587 * arr[..., 1] + 0.114 * arr[..., 2]

    # Height map (medium contrast with structure + micro-crevice relief)
    smooth = gaussian_filter(lum, sigma=3.0, mode="wrap")
    detail = lum - smooth
    height = smooth + 0.5 * detail
    h_min, h_max = float(np.percentile(height, 2)), float(np.percentile(height, 98))
    height = np.clip((height - h_min) / (h_max - h_min + 1e-5), 0.0, 1.0)
    height_img = Image.fromarray((height * 255).astype(np.uint8), mode="L")

    # Normal map (Tangent-space, Godot Y-up / OpenGL standard)
    dx = sobel(height, axis=1, mode="wrap") * normal_strength
    dy = sobel(height, axis=0, mode="wrap") * normal_strength
    dz = np.ones_like(height)

    norm = np.sqrt(dx**2 + dy**2 + dz**2)
    nx = dx / norm
    ny = -dy / norm  # Godot uses Y-up (green channel inverted relative to image space y)
    nz = dz / norm

    norm_rgb = np.zeros((*height.shape, 3), dtype=np.uint8)
    norm_rgb[..., 0] = np.clip((nx * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    norm_rgb[..., 1] = np.clip((ny * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    norm_rgb[..., 2] = np.clip((nz * 0.5 + 0.5) * 255, 0, 255).astype(np.uint8)
    normal_img = Image.fromarray(norm_rgb, mode="RGB")

    # Ambient Occlusion (crevices and deep relief have contact shadows)
    large_smooth = gaussian_filter(height, sigma=15.0, mode="wrap")
    crevice = np.clip((height - large_smooth) * 2.2 + 0.8, 0.0, 1.0)
    ao_img = Image.fromarray((crevice * 255).astype(np.uint8), mode="L")

    # Roughness map modulated around base roughness
    if is_metallic:
        rough = np.clip(base_roughness + (1.0 - height) * 0.15, 0.1, 0.6)
    else:
        # Porous stone: peaks slightly smoother, crevices rougher
        rough = np.clip(base_roughness + (1.0 - height) * 0.1 + (arr[..., 0] - lum) * 0.05, 0.65, 0.98)
    roughness_img = Image.fromarray((rough * 255).astype(np.uint8), mode="L")

    return normal_img, height_img, ao_img, roughness_img


def offset_image(img: Image.Image, offset_x: Optional[int] = None, offset_y: Optional[int] = None) -> Image.Image:
    """Wraps texture by half width and half height (Photoshop Offset filter equivalent)."""
    w, h = img.size
    ox = w // 2 if offset_x is None else offset_x
    oy = h // 2 if offset_y is None else offset_y
    return ImageChops.offset(img, ox, oy)


def calculate_seam_score(img: Image.Image) -> float:
    """Calculates boundary delta variance across opposite edges (horizontal and vertical seams)."""
    rgb = img.convert("RGB")
    arr = np.array(rgb, dtype=np.float32)

    # Top row vs Bottom row
    top_row = arr[0, :, :]
    bottom_row = arr[-1, :, :]
    diff_v = np.mean(np.abs(top_row - bottom_row))

    # Left col vs Right col
    left_col = arr[:, 0, :]
    right_col = arr[:, -1, :]
    diff_h = np.mean(np.abs(left_col - right_col))

    return float((diff_v + diff_h) / 2.0)


def blend_seams(img: Image.Image, blend_radius: int = 32) -> Image.Image:
    """Seamless boundary cross-fade so opposite edges meet identically (Photoshop offset blend equivalent)."""
    rgb = img.convert("RGBA")
    arr = np.array(rgb, dtype=np.float32)
    h, w, _ = arr.shape
    rad = min(blend_radius, w // 4, h // 4)

    # Horizontal seam blending (left x=0 vs right x=w-1)
    for dist in range(rad):
        weight = 0.5 * (1.0 - float(dist) / float(rad))
        left_color = arr[:, dist, :].copy()
        right_color = arr[:, w - 1 - dist, :].copy()
        arr[:, dist, :] = left_color * (1.0 - weight) + right_color * weight
        arr[:, w - 1 - dist, :] = right_color * (1.0 - weight) + left_color * weight

    # Vertical seam blending (top y=0 vs bottom y=h-1)
    for dist in range(rad):
        weight = 0.5 * (1.0 - float(dist) / float(rad))
        top_color = arr[dist, :, :].copy()
        bottom_color = arr[h - 1 - dist, :, :].copy()
        arr[dist, :, :] = top_color * (1.0 - weight) + bottom_color * weight
        arr[h - 1 - dist, :] = bottom_color * (1.0 - weight) + top_color * weight

    result = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(result, mode="RGBA").convert(img.mode)


def pack_orm(
    ao_path: Optional[Path],
    roughness_path: Optional[Path],
    metallic_path_or_val: str,
    output_path: Path,
    target_size: Optional[Tuple[int, int]] = None,
) -> Path:
    """Packs Occlusion (R), Roughness (G), Metallic (B) into single ORM texture."""
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

    # Load Roughness (Green) first to determine size if possible
    roughness_img = load_channel(roughness_path, 128)
    # Load Occlusion (Red) - default full white (no occlusion = 255)
    ao_img = load_channel(ao_path, 255)

    # Load Metallic (Blue)
    try:
        metal_val = float(metallic_path_or_val)
        int_val = int(np.clip(metal_val * 255.0, 0, 255))
        metal_img = Image.new("L", base_size, int_val)
    except ValueError:
        m_path = Path(metallic_path_or_val)
        metal_img = load_channel(m_path, 0)

    # Merge channels R=AO, G=Roughness, B=Metallic
    orm_img = Image.merge("RGB", (ao_img, roughness_img, metal_img))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    orm_img.save(output_path, format="PNG", optimize=True)
    return output_path


def to_res_path(path: Path) -> str:
    """Converts filesystem path to Godot res:// path relative to repo root."""
    try:
        resolved = path.resolve()
        # Find Git / project root containing project.godot
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
) -> Path:
    """Generates Godot 4 ORMMaterial3D (.tres) matching BellaSDK format."""
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
    ]

    if normal_id:
        content_lines.append("normal_enabled = true")
        content_lines.append(f'normal_texture = ExtResource("{normal_id}")')

    if height_id:
        content_lines.append("heightmap_enabled = true")
        content_lines.append(f"heightmap_scale = {height_scale}")
        content_lines.append(f'heightmap_texture = ExtResource("{height_id}")')

    content_lines.append(f"uv1_scale = Vector3({uv_scale[0]}, {uv_scale[1]}, {uv_scale[2]})")
    content_lines.append("")

    output_tres.parent.mkdir(parents=True, exist_ok=True)
    output_tres.write_text("\n".join(content_lines), encoding="utf-8")
    return output_tres


def main() -> None:
    parser = argparse.ArgumentParser(description="PBR Material Texture Processor & Godot 4 Generator")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Seam check
    check_p = subparsers.add_parser("check-seams", help="Wrap image and report seam score")
    check_p.add_argument("image", type=Path, help="Input texture image")
    check_p.add_argument("--save-offset", type=Path, default=None, help="Save wrapped offset image")
    check_p.add_argument("--threshold", type=float, default=12.0, help="Max tolerable seam delta score")

    # Seam blend
    blend_p = subparsers.add_parser("blend-seams", help="Cross-fade opposing edges for seamless tiling")
    blend_p.add_argument("image", type=Path, help="Input texture image")
    blend_p.add_argument("--output", "-o", type=Path, required=True, help="Output image path")
    blend_p.add_argument("--radius", type=int, default=32, help="Blend boundary pixel radius")

    # Pack ORM
    pack_p = subparsers.add_parser("pack-orm", help="Pack AO, Roughness, Metallic into single RGB texture")
    pack_p.add_argument("--ao", type=Path, default=None, help="AO map path (Red)")
    pack_p.add_argument("--roughness", type=Path, required=True, help="Roughness map path (Green)")
    pack_p.add_argument("--metallic", type=str, default="0.0", help="Metallic map path or constant 0.0-1.0 (Blue)")
    pack_p.add_argument("--output", "-o", type=Path, required=True, help="Output ORM image path")

    # Generate tres
    tres_p = subparsers.add_parser("build-tres", help="Generate Godot 4 ORMMaterial3D (.tres)")
    tres_p.add_argument("--name", type=str, required=True, help="Material resource name")
    tres_p.add_argument("--albedo", type=Path, required=True, help="Albedo texture path")
    tres_p.add_argument("--orm", type=Path, required=True, help="ORM texture path")
    tres_p.add_argument("--normal", type=Path, default=None, help="Normal texture path")
    tres_p.add_argument("--height", type=Path, default=None, help="Heightmap texture path")
    tres_p.add_argument("--output", "-o", type=Path, required=True, help="Output .tres path")
    tres_p.add_argument("--height-scale", type=float, default=0.05, help="Heightmap displacement depth")

    # Derive maps
    derive_p = subparsers.add_parser("derive-maps", help="Derive Normal, Height, AO, and Roughness from Albedo")
    derive_p.add_argument("albedo", type=Path, help="Input Albedo texture path")
    derive_p.add_argument("--out-dir", "-o", type=Path, required=True, help="Output texture directory")
    derive_p.add_argument("--slug", type=str, required=True, help="Material slug prefix")
    derive_p.add_argument("--normal-strength", type=float, default=3.5, help="Normal depth multiplier")
    derive_p.add_argument("--base-roughness", type=float, default=0.88, help="Target base roughness")
    derive_p.add_argument("--metallic", action="store_true", help="Flag if material is metallic")

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
            print(f"FAIL: Visible seam detected (score {score:.2f} > {args.threshold:.2f})")
            sys.exit(2)
        else:
            print("PASS: Texture appears seamless.")
            sys.exit(0)

    elif args.command == "blend-seams":
        if not args.image.is_file():
            print(f"Error: File not found {args.image}", file=sys.stderr)
            sys.exit(1)
        img = Image.open(args.image)
        blended = blend_seams(img, args.radius)
        blended.save(args.output)
        print(f"Blended seamless texture saved to: {args.output}")

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
        )
        print(f"Godot 4 ORMMaterial3D created: {tres}")

    elif args.command == "derive-maps":
        if not args.albedo.is_file():
            print(f"Error: File not found {args.albedo}", file=sys.stderr)
            sys.exit(1)
        alb_img = Image.open(args.albedo)
        normal_img, height_img, ao_img, rough_img = derive_companion_maps(
            alb_img,
            normal_strength=args.normal_strength,
            base_roughness=args.base_roughness,
            is_metallic=args.metallic,
        )
        args.out_dir.mkdir(parents=True, exist_ok=True)
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
