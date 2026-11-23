"""Tests for Godot 4.7+ exports: Blender 5.3 discovery, GLB skeletal animation, and ARKit-52 .tres facial animation."""
from __future__ import annotations

import json
import re
import shutil
import struct
import subprocess
from pathlib import Path

import numpy as np
import pytest
from synth import walk

from video2mocap import quat
from video2mocap.blender import bvh_to_glb, find_blender
from video2mocap.face.capture import FaceTake
from video2mocap.face.godot_export import (
    ARKIT_52_NAMES,
    LASH_SYNC_SHAPES,
    export_face_to_godot_tres,
    read_glb_bone_rest_quat,
)
from video2mocap.io.bvh import write_bvh

try:
    BLENDER = find_blender()
except FileNotFoundError:
    BLENDER = None

GODOT = shutil.which("godot")


def test_find_blender_locates_snap_or_system():
    exe = find_blender()
    assert Path(exe).exists()


@pytest.mark.skipif(BLENDER is None, reason="Blender not installed")
def test_bvh_to_glb_godot_skeleton_profile_humanoid(tmp_path):
    m = walk(seconds=1.0, fps=30.0)
    bvh_path = tmp_path / "walk.bvh"
    glb_path = tmp_path / "walk.glb"
    json_path = tmp_path / "glb_info.json"
    write_bvh(m, bvh_path)
    bvh_to_glb(str(bvh_path), str(glb_path), blender=BLENDER, fps=m.fps)
    assert glb_path.exists() and glb_path.stat().st_size > 1000

    inspect_code = (
        "import bpy, json, sys\n"
        "argv = sys.argv[sys.argv.index('--') + 1:]\n"
        "bpy.ops.wm.read_factory_settings(use_empty=True)\n"
        "bpy.ops.import_scene.gltf(filepath=argv[0])\n"
        "arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')\n"
        "bpy.context.scene.frame_set(1)\n"
        "bones = {b.name: list(arm.matrix_world @ b.head) for b in arm.pose.bones}\n"
        "json.dump({'bones': bones}, open(argv[1], 'w'))\n"
    )
    subprocess.run(
        [BLENDER, "--background", "--factory-startup", "--python-expr", inspect_code, "--", str(glb_path), str(json_path)],
        check=True,
        capture_output=True,
    )
    info = json.loads(json_path.read_text(encoding="utf-8"))
    bones = info["bones"]
    for expected in ("Hips", "Head", "LeftUpperLeg", "LeftLowerLeg", "LeftUpperArm", "RightUpperLeg", "RightLowerLeg"):
        assert expected in bones, f"missing Godot SkeletonProfileHumanoid bone {expected} in {list(bones)}"
    # Verify 1.0m meter scale (Blender Z-up after glTF import: Hips ~0.88m, Head ~1.5m)
    hips_z = bones["Hips"][2]
    head_z = bones["Head"][2]
    assert 0.5 < hips_z < 1.3, f"expected Hips height in meters (~0.88m), got {hips_z}"
    assert 1.2 < head_z < 2.0, f"expected Head height in meters (~1.55m), got {head_z}"


def test_export_face_to_godot_tres_52_arkit_plus_lashes_and_head(tmp_path):
    T = 15
    curves = np.linspace(0.0, 1.0, T * len(ARKIT_52_NAMES), dtype=np.float32).reshape(T, len(ARKIT_52_NAMES))
    head_rot = quat.from_axis_angle(np.array([0.0, 1.0, 0.0]), np.linspace(-0.2, 0.2, T))
    valid = np.ones(T, dtype=bool)
    take = FaceTake(fps=30.0, names=list(ARKIT_52_NAMES), curves=curves, head_rot=head_rot, valid=valid)
    npz_path = tmp_path / "take.npz"
    tres_path = tmp_path / "face_anim.tres"
    take.save(npz_path)

    out = export_face_to_godot_tres(npz_path, tres_path)
    assert out == tres_path and tres_path.exists()
    text = tres_path.read_text(encoding="utf-8")
    assert text.startswith('[gd_resource type="Animation" format=3]')

    for shape in ARKIT_52_NAMES:
        assert f'NodePath("BellaModel/Bella_Armature/Skeleton3D/Bella_Head:{shape}")' in text
    for lash_shape in LASH_SYNC_SHAPES:
        assert f'NodePath("BellaModel/Bella_Armature/Skeleton3D/Bella_Eyelashes:{lash_shape}")' in text
    assert 'type = "rotation_3d"' in text
    assert 'NodePath("BellaModel/Bella_Armature/Skeleton3D:Head")' in text
    # 52 head blend_shape + 6 lash blend_shape + 1 head rotation_3d = 59 tracks (0..58)
    assert "tracks/58/type =" in text
    assert "tracks/59/" not in text

    if GODOT:
        gd_script = tmp_path / "verify_load.gd"
        gd_script.write_text(
            "extends SceneTree\n"
            "func _init() -> void:\n"
            f'\tvar anim: Animation = ResourceLoader.load("{tres_path}") as Animation\n'
            "\tassert(anim != null)\n"
            "\tassert(anim.get_track_count() == 59)\n"
            '\tprint("GODOT_TRES_LOAD_OK")\n'
            "\tquit()\n",
            encoding="utf-8",
        )
        res = subprocess.run([GODOT, "--headless", "-s", str(gd_script)], check=False, capture_output=True, text=True)
        assert "GODOT_TRES_LOAD_OK" in res.stdout, f"Godot ResourceLoader failed:\n{res.stdout}\n{res.stderr}"


def _write_minimal_glb(path: Path, gltf_dict: dict) -> Path:
    json_bytes = json.dumps(gltf_dict).encode("utf-8")
    pad = (-len(json_bytes)) % 4
    json_bytes += b" " * pad
    total_len = 12 + 8 + len(json_bytes)
    header = struct.pack("<3I", 0x46546C67, 2, total_len)
    chunk = struct.pack("<2I", len(json_bytes), 0x4E4F534A) + json_bytes
    path.write_bytes(header + chunk)
    return path


def _parse_head_rot_wxyz(tres_path: Path) -> np.ndarray:
    text = tres_path.read_text(encoding="utf-8")
    m = re.search(r'type = "rotation_3d".*?keys = PackedFloat32Array\(([^)]+)\)', text, re.S)
    assert m is not None, "rotation_3d track keys not found"
    vals = np.fromstring(m.group(1), sep=",", dtype=np.float64).reshape(-1, 6)
    # Godot key layout: time, transition, x, y, z, w -> convert to wxyz
    return vals[:, [5, 2, 3, 4]]


def test_read_glb_bone_rest_quat(tmp_path):
    q_head = quat.from_axis_angle(np.array([1.0, 0.0, 0.0]), np.radians(-42.4543))
    q_neck = quat.from_axis_angle(np.array([0.0, 1.0, 0.0]), np.radians(25.0))
    m_neck = np.eye(4, dtype=np.float64)
    m_neck[:3, :3] = quat.to_matrix(q_neck) * 2.0  # scaled to verify column normalization
    m_neck[:3, 3] = [0.0, 0.1, 0.0]

    glb = _write_minimal_glb(
        tmp_path / "rig.glb",
        {
            "asset": {"version": "2.0"},
            "nodes": [
                {"name": "Root"},
                {"name": "Head", "rotation": [q_head[1], q_head[2], q_head[3], q_head[0]]},
                {"name": "Neck", "matrix": m_neck.T.reshape(-1).tolist()},
            ],
        },
    )

    got_head = read_glb_bone_rest_quat(glb, "Head")
    assert np.allclose(got_head, q_head, atol=1e-6)

    got_neck = read_glb_bone_rest_quat(glb, "Neck")
    assert abs(float(np.dot(got_neck, q_neck))) > 1.0 - 1e-6

    got_root = read_glb_bone_rest_quat(glb, "Root")
    assert np.allclose(got_root, [1.0, 0.0, 0.0, 0.0], atol=1e-6)

    with pytest.raises(KeyError):
        read_glb_bone_rest_quat(glb, "MissingBone")


def test_export_face_head_rest_neutral_center_and_continuity(tmp_path):
    T = 21
    curves = np.zeros((T, len(ARKIT_52_NAMES)), dtype=np.float32)
    q_rest = quat.from_axis_angle(np.array([1.0, 0.0, 0.0]), np.radians(-42.4543))
    q_pitch_bias = quat.from_axis_angle(np.array([1.0, 0.0, 0.0]), np.radians(-10.0))
    q_yaw_osc = quat.from_axis_angle(np.array([0.0, 1.0, 0.0]), np.linspace(-0.25, 0.25, T))
    # Combine constant camera pitch offset + symmetric yaw oscillation, with deliberate sign flips
    head_rot = quat.mul(np.broadcast_to(q_pitch_bias, (T, 4)), q_yaw_osc)
    head_rot[5:12] *= -1.0

    take = FaceTake(fps=30.0, names=list(ARKIT_52_NAMES), curves=curves, head_rot=head_rot, valid=np.ones(T, dtype=bool))
    npz_path = tmp_path / "take.npz"
    take.save(npz_path)

    # 1) Explicit head_rest_quat without neutral_center composes q_rest * q_delta
    tres_raw = tmp_path / "raw_rest.tres"
    export_face_to_godot_tres(npz_path, tres_raw, head_rest_quat=q_rest, neutral_center=False)
    got_raw = _parse_head_rot_wxyz(tres_raw)
    expected_raw = quat.make_continuous(
        quat.normalize(quat.mul(np.broadcast_to(q_rest, (T, 4)), quat.make_continuous(head_rot)))
    )
    assert np.allclose(got_raw, expected_raw, atol=1e-4)
    assert np.all(np.sum(got_raw[:-1] * got_raw[1:], axis=-1) > 0.0)

    # 2) glb_path + neutral_center=True removes constant pitch offset so mean equals q_rest
    glb = _write_minimal_glb(
        tmp_path / "ghost.glb",
        {
            "asset": {"version": "2.0"},
            "nodes": [{"name": "Head", "rotation": [q_rest[1], q_rest[2], q_rest[3], q_rest[0]]}],
        },
    )
    tres_centered = tmp_path / "centered.tres"
    export_face_to_godot_tres(npz_path, tres_centered, glb_path=glb, neutral_center=True)
    got_centered = _parse_head_rot_wxyz(tres_centered)
    mean_centered = quat.normalize(got_centered.mean(axis=0))
    assert np.allclose(mean_centered, q_rest, atol=1e-4)
    assert np.all(np.sum(got_centered[:-1] * got_centered[1:], axis=-1) > 0.0)

    # 3) head_additive in npz is NOT double-centered when neutral_center=True
    add_npz = tmp_path / "face_additive.npz"
    np.savez_compressed(
        add_npz,
        fps=30.0,
        names=np.array(ARKIT_52_NAMES),
        curves=curves,
        head_additive=np.broadcast_to(q_pitch_bias, (T, 4)),
    )
    tres_add = tmp_path / "additive.tres"
    export_face_to_godot_tres(add_npz, tres_add, head_rest_quat=q_rest, neutral_center=True)
    got_add = _parse_head_rot_wxyz(tres_add)
    expected_add = quat.normalize(quat.mul(q_rest, q_pitch_bias))
    assert np.allclose(got_add[0], expected_add, atol=1e-4)
