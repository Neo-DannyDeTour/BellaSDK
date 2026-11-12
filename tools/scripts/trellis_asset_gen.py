#!/usr/bin/env python3
"""
BellaSDK TRELLIS 3D Asset Generator & Ingestion Tool (/3d).
Connects to Microsoft TRELLIS API, generates 3D GLB assets from concept plates,
decimates to target tri budget, packs Godot 4 ORM textures, and installs into BellaSDK.
"""

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

import numpy as np
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODELS_DIR = REPO_ROOT / "assets" / "models"
HF_TOKEN = os.environ.get("HF_TOKEN", "")
SPACES = ["trellis-community/TRELLIS", "microsoft/TRELLIS.2"]


def prepare_input_plate(
    image_path: Path,
    auto_crop_box: bool = True,
    pad_neutral_gray: bool = True
) -> Path:
    """Preprocesses reference plate to isolate object and apply #808080 neutral background."""
    img = Image.open(image_path).convert("RGB")

    # If auto-crop requested and image has dark vignetted corners
    if auto_crop_box:
        arr = np.array(img.convert("L"))
        # Check if corners are near pitch black (flashlight cone)
        corner_mean = (float(arr[0, 0]) + float(arr[0, -1]) + float(arr[-1, 0]) + float(arr[-1, -1])) / 4.0
        if corner_mean < 15.0:
            print("Detected dark vignetted spotlight in reference plate. Isolating center object...")
            # Detect center bright rectangular area
            threshold = 40
            bright_rows = np.where(arr.mean(axis=1) > threshold)[0]
            bright_cols = np.where(arr.mean(axis=0) > threshold)[0]
            if len(bright_rows) > 0 and len(bright_cols) > 0:
                y_min = int(bright_rows[0])
                y_max = int(bright_rows[-1])
                x_min = int(bright_cols[0])
                x_max = int(bright_cols[-1])
                # Margin clamp
                pad_x = int((x_max - x_min) * 0.05)
                pad_y = int((y_max - y_min) * 0.05)
                x0 = max(0, x_min - pad_x)
                y0 = max(0, y_min - pad_y)
                x1 = min(img.width, x_max + pad_x)
                y1 = min(img.height, y_max + pad_y)
                img = img.crop((x0, y0, x1, y1))
                print(f"Cropped bounds: ({x0}, {y0}, {x1}, {y1}) -> size: {img.size}")

    if pad_neutral_gray:
        # Pad onto square canvas matching source background to preserve aspect ratio
        max_dim = max(img.width, img.height)
        canvas_size = max(512, max_dim)
        bg_color = (128, 128, 128) if corner_mean < 15.0 else img.getpixel((0, 0))
        canvas = Image.new("RGB", (canvas_size, canvas_size), bg_color)
        x_off = (canvas_size - img.width) // 2
        y_off = (canvas_size - img.height) // 2
        canvas.paste(img, (x_off, y_off))
        img = canvas

    temp_plate = Path("/tmp") / f"trellis_plate_{image_path.stem}.png"
    img.save(temp_plate, format="PNG")
    print(f"Prepared clean input plate: {temp_plate} ({img.size[0]}x{img.size[1]})")
    return temp_plate


def connect_trellis_client():
    """Establishes connection to available TRELLIS Hugging Face space."""
    from gradio_client import Client
    for space_name in SPACES:
        try:
            print(f"Connecting to TRELLIS space: {space_name}...")
            client = Client(space_name, token=HF_TOKEN)
            print(f"Connected successfully: {space_name}")
            return client
        except Exception as err:
            print(f"Space '{space_name}' connection failed: {err}")
    raise RuntimeError("Could not connect to any active TRELLIS Hugging Face space.")


def generate_3d_asset(
    client,
    input_plate_path: Path,
    seed: int = 42,
    simplify_ratio: float = 0.95
) -> str:
    """Invokes TRELLIS image-to-3D endpoints and retrieves raw GLB path."""
    from gradio_client import handle_file

    try:
        client.predict(api_name="/start_session")
    except Exception:
        pass

    print(f"Preprocessing input plate via /preprocess_image...")
    prep_out = client.predict(
        image=handle_file(str(input_plate_path)),
        api_name="/preprocess_image"
    )
    prep_file = prep_out["path"] if isinstance(prep_out, dict) and "path" in prep_out else str(prep_out)
    print(f"Preprocessed plate ready at: {prep_file}")

    print("Generating 3D model via /generate_and_extract_glb (approx 30-60s)...")
    video_preview, viewer_glb, download_glb = client.predict(
        image=handle_file(prep_file),
        multiimages=[],
        seed=seed,
        ss_guidance_strength=7.5,
        ss_sampling_steps=12,
        slat_guidance_strength=3.0,
        slat_sampling_steps=12,
        multiimage_algo="stochastic",
        mesh_simplify=simplify_ratio,
        texture_size=1024,
        api_name="/generate_and_extract_glb"
    )
    glb_src = download_glb["path"] if isinstance(download_glb, dict) and "path" in download_glb else str(download_glb)
    print(f"GLB generated successfully: {glb_src}")
    return glb_src


def decimate_mesh_budget(glb_path: Path, target_budget: int) -> int:
    """Simplifies mesh faces to target tri budget using quadric decimation."""
    import trimesh

    scene_or_mesh = trimesh.load(str(glb_path))
    if isinstance(scene_or_mesh, trimesh.Scene):
        mesh = trimesh.util.concatenate(
            [m for m in scene_or_mesh.geometry.values() if isinstance(m, trimesh.Trimesh)]
        )
    else:
        mesh = scene_or_mesh

    face_count = len(mesh.faces)
    print(f"Raw mesh triangle count: {face_count}")

    if face_count > target_budget:
        reduction = 1.0 - (float(target_budget) / float(face_count))
        reduction = max(0.01, min(0.99, reduction))
        print(f"Decimating mesh ({face_count} -> {target_budget} tris, reduction={reduction:.2%})...")
        simplified = mesh.simplify_quadric_decimation(reduction)
        simplified.export(str(glb_path))
        face_count = len(simplified.faces)
        print(f"Decimated mesh triangles: {face_count}")

    return face_count


def scale_mesh_geometry(
    glb_path: Path,
    target_height: Optional[float] = None,
    scale_factor: Optional[float] = None
) -> Tuple[float, float, float]:
    """Bakes physical real-world meter scale directly into vertex coordinates."""
    if target_height is None and scale_factor is None:
        return (0.0, 0.0, 0.0)

    import trimesh

    scene = trimesh.load(str(glb_path))
    factor = scale_factor if scale_factor is not None else (target_height / float(scene.extents[1]))
    print(f"Baking scale factor {factor:.4f} directly into vertex coordinates...")

    for geom in scene.geometry.values():
        geom.apply_scale(factor)

    scene.export(str(glb_path))
    reloaded = trimesh.load(str(glb_path))
    print(f"Baked mesh extents (X, Y, Z): {reloaded.extents}")
    return (float(reloaded.extents[0]), float(reloaded.extents[1]), float(reloaded.extents[2]))


def pack_godot_orm_texture(
    output_path: Path,
    metallic: float = 0.0,
    roughness: float = 0.7,
    size: Tuple[int, int] = (1024, 1024)
) -> Path:
    """Packs Godot 4 ORM texture (R=AO, G=Roughness, B=Metallic)."""
    ao_channel = Image.new("L", size, 255)
    rough_val = int(np.clip(roughness * 255.0, 0, 255))
    rough_channel = Image.new("L", size, rough_val)
    metal_val = int(np.clip(metallic * 255.0, 0, 255))
    metal_channel = Image.new("L", size, metal_val)

    orm_img = Image.merge("RGB", (ao_channel, rough_channel, metal_channel))
    orm_img.save(output_path, format="PNG", optimize=True)
    print(f"Saved packed Godot 4 ORM texture: {output_path} (R=AO, G={roughness}, B={metallic})")
    return output_path


def create_godot_material_resource(
    output_tres_path: Path,
    prop_slug: str,
    res_dir: str
) -> Path:
    """Generates Godot 4 ORMMaterial3D .tres resource file."""
    content = f"""[gd_resource type="ORMMaterial3D" load_steps=2 format=3]

[ext_resource type="Texture2D" path="{res_dir}/{prop_slug}_orm.png" id="1_orm"]

[resource]
resource_name = "M_{prop_slug}"
orm_texture = ExtResource("1_orm")
roughness = 1.0
metallic = 1.0
"""
    with open(output_tres_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"Generated Godot 4 material: {output_tres_path}")
    return output_tres_path


def run_pipeline(
    image_path: Path,
    prop_slug: str,
    target_layer: str = "Layer 1 Environment",
    tri_budget: int = 2000,
    metallic: float = 0.0,
    roughness: float = 0.7,
    target_height: Optional[float] = None,
    scale_factor: Optional[float] = None,
    output_dir: Optional[Path] = None,
    seed: int = 42
) -> Path:
    """Executes end-to-end 4-gate 3D generation and asset ingestion."""
    target_dir = (output_dir or (DEFAULT_MODELS_DIR / prop_slug))
    target_dir.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print(f"BellaSDK 3D Generator: '{prop_slug}'")
    print(f"Target Layer: {target_layer} | Tri Budget: {tri_budget}")
    print(f"Destination: {target_dir}")
    print("=" * 60)

    # 1. Prepare clean input plate
    clean_plate = prepare_input_plate(image_path)

    # 2. Connect & run TRELLIS inference
    client = connect_trellis_client()
    raw_glb_src = generate_3d_asset(client, clean_plate, seed=seed)

    # 3. Copy GLB to asset destination
    final_glb_path = target_dir / f"{prop_slug}.glb"
    shutil.copy(raw_glb_src, final_glb_path)
    print(f"Copied GLB to target: {final_glb_path}")

    # 4. Decimate to tri budget
    final_tris = decimate_mesh_budget(final_glb_path, tri_budget)

    # 5. Bake physical scale directly into vertices if requested
    dimensions = scale_mesh_geometry(final_glb_path, target_height=target_height, scale_factor=scale_factor)

    # 6. Pack Godot 4 ORM texture
    orm_path = target_dir / f"{prop_slug}_orm.png"
    pack_godot_orm_texture(orm_path, metallic=metallic, roughness=roughness)

    # 7. Generate Godot .tres material
    res_dir = f"res://assets/models/{prop_slug}"
    tres_path = target_dir / f"{prop_slug}.tres"
    create_godot_material_resource(tres_path, prop_slug, res_dir)

    # 8. Write asset manifest
    manifest_data = {
        "prop_slug": prop_slug,
        "tri_count": final_tris,
        "target_layer": target_layer,
        "generator": "TRELLIS",
        "dimensions_m": list(dimensions) if dimensions != (0.0, 0.0, 0.0) else None,
        "scale": [1.0, 1.0, 1.0],
        "reference_image": str(image_path),
        "metallic": metallic,
        "roughness": roughness
    }
    manifest_path = target_dir / "asset_manifest.json"
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest_data, f, indent=2)

    print("-" * 60)
    print(f"[SUCCESS] Asset '{prop_slug}' ready in BellaSDK: {target_dir}")
    print(f"  - GLB: {final_glb_path.name} ({final_tris} tris)")
    print(f"  - ORM: {orm_path.name}")
    print(f"  - Material: {tres_path.name}")
    print(f"  - Manifest: {manifest_path.name}")
    print("=" * 60)

    return target_dir


def main() -> int:
    parser = argparse.ArgumentParser(description="BellaSDK TRELLIS 3D Asset Generator (/3d)")
    parser.add_argument("--image", type=Path, required=True, help="Input concept plate path")
    parser.add_argument("--slug", type=str, default="electro_box", help="Prop slug identifier")
    parser.add_argument("--layer", type=str, default="Layer 1 Environment", help="Target collision layer")
    parser.add_argument("--tri-budget", type=int, default=2000, help="Target max triangle count")
    parser.add_argument("--metallic", type=float, default=0.0, help="Metallic value (0.0=dielectric, 1.0=metal)")
    parser.add_argument("--roughness", type=float, default=0.7, help="Roughness value (0.0-1.0)")
    parser.add_argument("--target-height", type=float, default=None, help="Target height in meters (bakes scale into vertices)")
    parser.add_argument("--scale", type=float, default=None, help="Uniform scale multiplier (bakes scale into vertices)")
    parser.add_argument("--output-dir", type=Path, default=None, help="Target asset output directory")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed")

    args = parser.parse_args()

    if not args.image.is_file():
        print(f"Error: input image not found: {args.image}", file=sys.stderr)
        return 1

    run_pipeline(
        image_path=args.image,
        prop_slug=args.slug,
        target_layer=args.layer,
        tri_budget=args.tri_budget,
        metallic=args.metallic,
        roughness=args.roughness,
        target_height=args.target_height,
        scale_factor=args.scale,
        output_dir=args.output_dir,
        seed=args.seed
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
