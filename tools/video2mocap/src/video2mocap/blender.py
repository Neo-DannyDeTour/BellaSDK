"""Headless Blender bridge: BVH -> FBX/GLB ready for Unreal/Godot (Blender imports BVH natively)."""
from __future__ import annotations

import glob
import os
import shutil
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "blender" / "bvh_to_fbx.py"
SCRIPT_GLB = Path(__file__).resolve().parents[2] / "scripts" / "blender" / "bvh_to_godot_glb.py"


def find_blender(explicit: str | None = None) -> str:
    if explicit:
        return explicit
    if os.environ.get("BLENDER"):
        return os.environ["BLENDER"]
    found = shutil.which("blender")
    if found:
        return found
    candidates = [
        "/snap/bin/blender",
        "/usr/bin/blender",
        "/usr/local/bin/blender",
    ]
    candidates += sorted(glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe"), reverse=True)
    candidates += ["/Applications/Blender.app/Contents/MacOS/Blender"]
    for c in candidates:
        if Path(c).exists():
            return c
    raise FileNotFoundError("Blender not found: pass --blender or set BLENDER")


def bvh_to_fbx(bvh: str, fbx: str, blender: str | None = None, fps: float | None = None) -> None:
    exe = find_blender(blender)
    cmd = [exe, "--background", "--factory-startup", "--python", str(SCRIPT), "--", str(Path(bvh).resolve()),
           str(Path(fbx).resolve())]
    if fps:
        cmd += ["--fps", str(fps)]
    res = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if res.returncode != 0 or not Path(fbx).exists():
        raise RuntimeError(f"Blender export failed:\n{res.stdout[-3000:]}\n{res.stderr[-3000:]}")


def bvh_to_glb(bvh: str, glb: str, blender: str | None = None, fps: float | None = None) -> None:
    exe = find_blender(blender)
    cmd = [exe, "--background", "--factory-startup", "--python", str(SCRIPT_GLB), "--", str(Path(bvh).resolve()),
           str(Path(glb).resolve()), "--remap-godot"]
    if fps:
        cmd += ["--fps", str(fps)]
    res = subprocess.run(cmd, check=False, capture_output=True, text=True)
    if res.returncode != 0 or not Path(glb).exists():
        raise RuntimeError(f"Blender GLB export failed:\n{res.stdout[-3000:]}\n{res.stderr[-3000:]}")
