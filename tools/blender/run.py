#!/usr/bin/env python3
"""Host runner for headless Blender asset generation pipeline.

Executes Blender in headless background mode, feeding in procedural generator
scripts with standard Godot 4 export presets.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_blender() -> str:
    """Locate the Blender executable on the host system."""
    env_bin = os.environ.get("BLENDER_BIN")
    if env_bin and Path(env_bin).is_file() and os.access(env_bin, os.X_OK):
        return env_bin

    # Standard paths on Ubuntu / Snap
    known_paths = [
        "/snap/bin/blender",
        "/usr/bin/blender",
        "/usr/local/bin/blender",
    ]
    for p in known_paths:
        if Path(p).is_file() and os.access(p, os.X_OK):
            return p

    which_path = shutil.which("blender")
    if which_path:
        return which_path

    raise FileNotFoundError(
        "Could not find 'blender' executable. Set BLENDER_BIN environment variable "
        "or ensure Blender is in your PATH."
    )


def list_generators(generators_dir: Path) -> list[str]:
    """Return all available generator script names."""
    if not generators_dir.is_dir():
        return []
    return [
        f.stem
        for f in sorted(generators_dir.glob("*.py"))
        if not f.name.startswith("__")
    ]


def main() -> int:
    pipeline_dir = Path(__file__).resolve().parent
    generators_dir = pipeline_dir / "generators"

    parser = argparse.ArgumentParser(
        description="Run headless Blender asset generators for Godot 4."
    )
    parser.add_argument(
        "generator",
        nargs="?",
        help="Name or path of the generator script (e.g. test_prop or path/to/script.py).",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all available generator scripts in tools/blender/generators/.",
    )
    parser.add_argument(
        "--blender-bin",
        default=None,
        help="Custom path to the blender executable.",
    )

    args, extra_args = parser.parse_known_args()

    if args.list:
        generators = list_generators(generators_dir)
        print("Available Blender asset generators:")
        for gen in generators:
            print(f"  - {gen}")
        return 0

    if not args.generator:
        parser.print_help()
        return 1

    try:
        blender_bin = args.blender_bin or find_blender()
    except FileNotFoundError as err:
        print(f"Error: {err}", file=sys.stderr)
        return 1

    # Resolve target script path
    script_path = Path(args.generator)
    if not script_path.is_file():
        candidate = generators_dir / f"{args.generator}.py"
        if candidate.is_file():
            script_path = candidate
        else:
            print(f"Error: Generator script '{args.generator}' not found.", file=sys.stderr)
            print(f"Looked in: {script_path} and {candidate}", file=sys.stderr)
            return 1

    script_path = script_path.resolve()

    cmd = [
        blender_bin,
        "--background",
        "--python",
        str(script_path),
        "--",
    ] + extra_args

    print(f"==> Launching Blender {blender_bin} in background mode")
    print(f"==> Script: {script_path}")
    if extra_args:
        print(f"==> Arguments: {' '.join(extra_args)}")
    sys.stdout.flush()

    # Run Blender process
    result = subprocess.run(cmd)
    if result.returncode == 0:
        print(f"\n[OK] Asset generation completed successfully via {script_path.name}")
    else:
        print(
            f"\n[ERROR] Blender execution failed with exit code {result.returncode}",
            file=sys.stderr,
        )
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
