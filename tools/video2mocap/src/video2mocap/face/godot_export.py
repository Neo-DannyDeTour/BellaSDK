"""Export ARKit-52 facial animation curves + head rotation to a Godot 4.7+ Animation .tres resource."""
from __future__ import annotations

from pathlib import Path
import json
import struct

import numpy as np

from .. import quat
from .capture import FaceTake

ARKIT_52_NAMES: tuple[str, ...] = (
    "browDownLeft",
    "browDownRight",
    "browInnerUp",
    "browOuterUpLeft",
    "browOuterUpRight",
    "cheekPuff",
    "cheekSquintLeft",
    "cheekSquintRight",
    "eyeBlinkLeft",
    "eyeBlinkRight",
    "eyeLookDownLeft",
    "eyeLookDownRight",
    "eyeLookInLeft",
    "eyeLookInRight",
    "eyeLookOutLeft",
    "eyeLookOutRight",
    "eyeLookUpLeft",
    "eyeLookUpRight",
    "eyeSquintLeft",
    "eyeSquintRight",
    "eyeWideLeft",
    "eyeWideRight",
    "jawForward",
    "jawLeft",
    "jawOpen",
    "jawRight",
    "mouthClose",
    "mouthDimpleLeft",
    "mouthDimpleRight",
    "mouthFrownLeft",
    "mouthFrownRight",
    "mouthFunnel",
    "mouthLeft",
    "mouthLowerDownLeft",
    "mouthLowerDownRight",
    "mouthPressLeft",
    "mouthPressRight",
    "mouthPucker",
    "mouthRight",
    "mouthRollLower",
    "mouthRollUpper",
    "mouthShrugLower",
    "mouthShrugUpper",
    "mouthSmileLeft",
    "mouthSmileRight",
    "mouthStretchLeft",
    "mouthStretchRight",
    "mouthUpperUpLeft",
    "mouthUpperUpRight",
    "noseSneerLeft",
    "noseSneerRight",
    "tongueOut",
)

LASH_SYNC_SHAPES: tuple[str, ...] = (
    "eyeBlinkLeft",
    "eyeBlinkRight",
    "eyeWideLeft",
    "eyeWideRight",
    "eyeSquintLeft",
    "eyeSquintRight",
)


def read_glb_bone_rest_quat(glb_path: str | Path, bone_name: str = "Head") -> np.ndarray:
    """Read a bone node's local rest rotation from a binary .glb as a normalized (w, x, y, z) float64 array."""
    data = Path(glb_path).read_bytes()
    if len(data) < 20:
        raise ValueError(f"Invalid GLB file (too short): {glb_path}")
    magic, _version, _length = struct.unpack_from("<3I", data, 0)
    if magic != 0x46546C67:
        raise ValueError(f"Invalid GLB magic 0x{magic:08X} in {glb_path}")

    gltf: dict | None = None
    offset = 12
    while offset + 8 <= len(data):
        chunk_len, chunk_type = struct.unpack_from("<2I", data, offset)
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_len
        if chunk_end > len(data):
            raise ValueError(f"Truncated GLB chunk in {glb_path}")
        if chunk_type == 0x4E4F534A:
            gltf = json.loads(data[chunk_start:chunk_end].decode("utf-8"))
            break
        offset = chunk_end

    if gltf is None:
        raise ValueError(f"No JSON chunk found in GLB: {glb_path}")

    for node in gltf.get("nodes", []):
        if node.get("name") == bone_name:
            if "rotation" in node:
                x, y, z, w = node["rotation"]
                return quat.normalize(np.array([w, x, y, z], dtype=np.float64))
            if "matrix" in node:
                m_row = np.asarray(node["matrix"], dtype=np.float64).reshape(4, 4).T
                r = m_row[:3, :3]
                col_norms = np.maximum(np.linalg.norm(r, axis=0, keepdims=True), 1e-12)
                return quat.from_matrix(r / col_norms)
            return np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)

    raise KeyError(f"Bone node '{bone_name}' not found in {glb_path}")


def _load_face_data(
    take_or_npz_path: str | Path | FaceTake,
) -> tuple[float, list[str], np.ndarray, np.ndarray, bool]:
    if isinstance(take_or_npz_path, FaceTake):
        return (
            take_or_npz_path.fps,
            list(take_or_npz_path.names),
            take_or_npz_path.curves,
            np.asarray(take_or_npz_path.head_rot, dtype=np.float64),
            False,
        )
    d = np.load(take_or_npz_path, allow_pickle=False)
    fps = float(d["fps"])
    names = [str(n) for n in d["names"]]
    curves = np.asarray(d["curves"], dtype=np.float32)
    is_additive = "head_additive" in d.files
    rot = np.asarray(d["head_additive"] if is_additive else d["head_rot"], dtype=np.float64)
    return fps, names, curves, rot, is_additive


def export_face_to_godot_tres(
    take_or_npz_path: str | Path | FaceTake,
    out_tres_path: str | Path,
    head_mesh_path: str = "BellaModel/Bella_Armature/Skeleton3D/Bella_Head",
    lash_mesh_path: str = "BellaModel/Bella_Armature/Skeleton3D/Bella_Eyelashes",
    skeleton_path: str = "BellaModel/Bella_Armature/Skeleton3D",
    glb_path: str | Path | None = None,
    head_rest_quat: tuple[float, float, float, float] | np.ndarray | None = None,
    neutral_center: bool = False,
) -> Path:
    """Write a Godot 4.7+ [gd_resource type="Animation" format=3] .tres file containing:
    - 52 ARKit TYPE_BLEND_SHAPE tracks on head_mesh_path
    - 6 synced eyelid TYPE_BLEND_SHAPE tracks on lash_mesh_path
    - 1 TYPE_ROTATION_3D track on <skeleton_path>:Head
    """
    fps, names, curves, head_rot, is_additive = _load_face_data(take_or_npz_path)
    num_frames = int(curves.shape[0])
    step = 1.0 / fps if fps > 0 else 1.0 / 30.0
    length = max((num_frames - 1) * step, 0.0)
    times = np.arange(num_frames, dtype=np.float64) * step

    name_to_idx = {n: i for i, n in enumerate(names)}
    all_shapes = list(ARKIT_52_NAMES)
    for n in names:
        if n not in all_shapes:
            all_shapes.append(n)

    lines: list[str] = [
        '[gd_resource type="Animation" format=3]',
        "",
        "[resource]",
        'resource_name = "face_performance"',
        f"length = {length:.4f}",
        f"step = {step:.6f}",
    ]

    track_idx = 0

    def emit_blend_track(node_path: str, shape_name: str, vals: np.ndarray) -> None:
        nonlocal track_idx
        b_entries = [f"{times[t_idx]:.4f}, 1.0, {float(v):.4f}" for t_idx, v in enumerate(vals)]
        b_str = ", ".join(b_entries)
        lines.extend([
            f'tracks/{track_idx}/type = "blend_shape"',
            f"tracks/{track_idx}/imported = false",
            f"tracks/{track_idx}/enabled = true",
            f'tracks/{track_idx}/path = NodePath("{node_path}:{shape_name}")',
            f"tracks/{track_idx}/interp = 1",
            f"tracks/{track_idx}/loop_wrap = true",
            f"tracks/{track_idx}/keys = PackedFloat32Array({b_str})",
        ])
        track_idx += 1

    zeros = np.zeros(num_frames, dtype=np.float32)
    for shape in all_shapes:
        col = curves[:, name_to_idx[shape]] if shape in name_to_idx else zeros
        emit_blend_track(head_mesh_path, shape, col)

    if lash_mesh_path:
        for shape in LASH_SYNC_SHAPES:
            col = curves[:, name_to_idx[shape]] if shape in name_to_idx else zeros
            emit_blend_track(lash_mesh_path, shape, col)

    if skeleton_path:
        if head_rest_quat is not None:
            q_rest = np.asarray(head_rest_quat, dtype=np.float64)
            if q_rest.shape != (4,):
                raise ValueError(f"head_rest_quat must have shape (4,), got {q_rest.shape}")
            q_rest = quat.normalize(q_rest)
        elif glb_path is not None:
            q_rest = read_glb_bone_rest_quat(glb_path, "Head")
        else:
            q_rest = np.array([1.0, 0.0, 0.0, 0.0], dtype=np.float64)

        if len(head_rot) > 0:
            head_rot = quat.make_continuous(quat.normalize(np.asarray(head_rot, dtype=np.float64)))
            if neutral_center and not is_additive:
                q_neutral = quat.normalize(head_rot.mean(axis=0))
                q_delta = quat.normalize(
                    quat.mul(np.broadcast_to(quat.conj(q_neutral), head_rot.shape), head_rot)
                )
            else:
                q_delta = head_rot
            q_final = quat.make_continuous(
                quat.normalize(quat.mul(np.broadcast_to(q_rest, q_delta.shape), q_delta))
            )
        else:
            q_final = np.empty((0, 4), dtype=np.float64)

        # v2m quaternions are wxyz; Godot rotation_3d keys are: time, transition(1.0), x, y, z, w
        q_entries: list[str] = []
        for t_idx, q in enumerate(q_final):
            w, x, y, z = float(q[0]), float(q[1]), float(q[2]), float(q[3])
            q_entries.append(f"{times[t_idx]:.4f}, 1.0, {x:.5f}, {y:.5f}, {z:.5f}, {w:.5f}")
        q_str = ", ".join(q_entries)
        lines.extend([
            f'tracks/{track_idx}/type = "rotation_3d"',
            f"tracks/{track_idx}/imported = false",
            f"tracks/{track_idx}/enabled = true",
            f'tracks/{track_idx}/path = NodePath("{skeleton_path}:Head")',
            f"tracks/{track_idx}/interp = 1",
            f"tracks/{track_idx}/loop_wrap = true",
            f"tracks/{track_idx}/keys = PackedFloat32Array({q_str})",
        ])
        track_idx += 1

    out_p = Path(out_tres_path)
    out_p.parent.mkdir(parents=True, exist_ok=True)
    out_p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_p
