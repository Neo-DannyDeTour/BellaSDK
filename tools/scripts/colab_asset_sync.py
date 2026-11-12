#!/usr/bin/env python3
"""
BellaSDK Colab 3D Asset Sync & Ingestion Bridge.
Receives, validates, and unpacks 3D asset bundles (GLB + ORM textures)
generated in Google Colab into the BellaSDK assets tree.
"""

import argparse
import base64
import json
import os
import sys
from pathlib import Path
from typing import Dict, Any, Optional
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MODELS_DIR = REPO_ROOT / "assets" / "models"


def unpack_bundle_data(bundle_dict: Dict[str, Any], output_root: Optional[Path] = None) -> Path:
    """Unpacks a JSON bundle dictionary containing base64 files into target asset folder."""
    prop_slug = bundle_dict.get("prop_slug", "unnamed_prop")
    target_dir = (output_root or DEFAULT_MODELS_DIR) / prop_slug
    target_dir.mkdir(parents=True, exist_ok=True)

    files = bundle_dict.get("files", {})
    if not files:
        raise ValueError("Bundle contains no files")

    print(f"Unpacking asset bundle for '{prop_slug}' into: {target_dir}")

    for filename, b64_str in files.items():
        file_path = target_dir / filename
        data = base64.b64decode(b64_str)
        with open(file_path, "wb") as f:
            f.write(data)
        print(f"  -> Wrote: {filename} ({len(data)} bytes)")

    # Write manifest/metadata
    meta = {
        "prop_slug": prop_slug,
        "tri_count": bundle_dict.get("tri_count", 0),
        "target_layer": bundle_dict.get("target_layer", "Layer 3 Interactive"),
        "generator": bundle_dict.get("generator", "TRELLIS"),
    }
    with open(target_dir / "asset_manifest.json", "w", encoding="utf-8") as f:
        json.dump(meta, f, indent=2)

    # Validate ORM packing if present
    orm_file = target_dir / f"{prop_slug}_orm.png"
    if orm_file.is_file():
        validate_orm_texture(orm_file)

    print(f"Asset '{prop_slug}' successfully ingested into {target_dir}")
    return target_dir


def validate_orm_texture(orm_path: Path) -> bool:
    """Validates that the packed ORM texture matches Godot 4 expectations."""
    try:
        with Image.open(orm_path) as img:
            if img.mode != "RGB":
                print(f"  [WARN] ORM texture mode is {img.mode}, expected RGB")
                return False
            w, h = img.size
            print(f"  [PASS] Godot ORM texture validated ({w}x{h}, RGB: R=AO, G=Roughness, B=Metallic)")
            return True
    except Exception as e:
        print(f"  [ERROR] Failed to read ORM texture: {e}")
        return False


def unpack_from_base64_file(input_path: Path, output_root: Optional[Path] = None) -> Path:
    """Reads a base64 bundle file (JSON or raw text) and unpacks it."""
    with open(input_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    # Try parsing as JSON directly
    try:
        data = json.loads(content)
        return unpack_bundle_data(data, output_root)
    except json.JSONDecodeError:
        # Check if raw base64 encoded JSON
        decoded = base64.b64decode(content).decode("utf-8")
        data = json.loads(decoded)
        return unpack_bundle_data(data, output_root)


def main() -> int:
    parser = argparse.ArgumentParser(description="BellaSDK Colab 3D Asset Bridge")
    subparsers = parser.add_subparsers(dest="command", help="Sub-command")

    # Ingest command
    ingest_cmd = subparsers.add_parser("ingest", help="Ingest a base64 bundle file from Colab")
    ingest_cmd.add_argument("bundle_file", type=Path, help="Path to base64 bundle JSON file")
    ingest_cmd.add_argument("--output-dir", type=Path, default=None, help="Target root directory")

    # Paste command (read from stdin)
    paste_cmd = subparsers.add_parser("paste", help="Read bundle payload directly from stdin")
    paste_cmd.add_argument("--output-dir", type=Path, default=None, help="Target root directory")

    args = parser.parse_args()

    if args.command == "ingest":
        if not args.bundle_file.is_file():
            print(f"File not found: {args.bundle_file}", file=sys.stderr)
            return 1
        unpack_from_base64_file(args.bundle_file, args.output_dir)
        return 0
    elif args.command == "paste":
        print("Reading bundle payload from stdin (paste and press Ctrl+D)...")
        raw = sys.stdin.read().strip()
        if not raw:
            print("No data received", file=sys.stderr)
            return 1
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            decoded = base64.b64decode(raw).decode("utf-8")
            data = json.loads(decoded)
        unpack_bundle_data(data, args.output_dir)
        return 0
    else:
        parser.print_help()
        return 1


if __name__ == "__main__":
    sys.exit(main())
