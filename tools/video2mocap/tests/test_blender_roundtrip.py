"""Integration: motion -> BVH -> Blender -> FBX -> Blender re-import must reproduce every joint position.
Skipped when Blender is not installed."""
import json
import subprocess
from pathlib import Path

import numpy as np
import pytest

from video2mocap.blender import bvh_to_fbx, find_blender
from video2mocap.io.bvh import write_bvh

from synth import add_noise, walk

ROOT = Path(__file__).resolve().parents[1]

try:
    BLENDER = find_blender()
except FileNotFoundError:
    BLENDER = None


@pytest.mark.skipif(BLENDER is None, reason="Blender not installed")
def test_fbx_reproduces_joint_positions(tmp_path):
    m = add_noise(walk(seconds=2), rot_deg=15, pos_m=0.0)  # large rotations exercise Euler conversion
    write_bvh(m, tmp_path / "m.bvh")
    bvh_to_fbx(str(tmp_path / "m.bvh"), str(tmp_path / "m.fbx"), blender=BLENDER)
    subprocess.run([BLENDER, "--background", "--factory-startup", "--python",
                    str(ROOT / "scripts" / "blender" / "dump_fbx_joints.py"), "--",
                    str(tmp_path / "m.fbx"), str(tmp_path / "m.json")], check=True, capture_output=True)
    d = json.loads((tmp_path / "m.json").read_text())
    got = np.array(d["frames"])  # Blender units (cm), Z-up
    g, _ = m.fk()
    ours = g[:, [m.skeleton.index(n) for n in d["names"]]] * 100.0
    ours_zup = np.stack([ours[..., 0], -ours[..., 2], ours[..., 1]], axis=-1)
    assert got.shape == ours_zup.shape
    err = np.abs(got - ours_zup).max()
    assert err < 0.05, f"max joint error {err:.4f} cm"
