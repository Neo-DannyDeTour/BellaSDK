#!/usr/bin/env python3
"""Local Ubuntu AI Video-to-BVH motion capture CLI for Godiva.

Extracts 3D world pose landmarks per frame using MediaPipe PoseLandmarker,
applies zero-phase temporal smoothing, solves hierarchical joint rotations in
standard BVH Y-up space, and writes a .bvh file directly compatible with
tools/blender/retarget_godiva_mocap.py.

Usage:
    .venv_mocap/bin/python tools/scripts/video_to_bvh.py \\
        --input reference_walk.mp4 \\
        --output assets/mocap/godiva/walk.bvh \\
        --fps 60 --smooth 0.35
"""

from __future__ import annotations

import argparse
import math
import urllib.request
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from scipy.signal import savgol_filter
from scipy.spatial.transform import Rotation

MODEL_URLS: Dict[str, str] = {
    "lite": (
        "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
        "pose_landmarker_lite/float16/latest/pose_landmarker_lite.task"
    ),
    "full": (
        "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
        "pose_landmarker_full/float16/latest/pose_landmarker_full.task"
    ),
    "heavy": (
        "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
        "pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"
    ),
}

# MediaPipe 33-landmark indices
LM_NOSE = 0
LM_LEFT_EAR = 7
LM_RIGHT_EAR = 8
LM_LEFT_SHOULDER = 11
LM_RIGHT_SHOULDER = 12
LM_LEFT_ELBOW = 13
LM_RIGHT_ELBOW = 14
LM_LEFT_WRIST = 15
LM_RIGHT_WRIST = 16
LM_LEFT_INDEX = 19
LM_RIGHT_INDEX = 20
LM_LEFT_HIP = 23
LM_RIGHT_HIP = 24
LM_LEFT_KNEE = 25
LM_RIGHT_KNEE = 26
LM_LEFT_ANKLE = 27
LM_RIGHT_ANKLE = 28
LM_LEFT_HEEL = 29
LM_RIGHT_HEEL = 30
LM_LEFT_FOOT_INDEX = 31
LM_RIGHT_FOOT_INDEX = 32

# Standard BVH T-pose hierarchy (Y-up, +Z forward, +X subject left, meters)
# Tuple: (joint_name, parent_name, offset_xyz, end_site_offset_or_None)
BVH_JOINTS: List[Tuple[str, Optional[str], Tuple[float, float, float], Optional[Tuple[float, float, float]]]] = [
    ("Hips", None, (0.0, 0.90, 0.0), None),
    ("Spine", "Hips", (0.0, 0.12, 0.0), None),
    ("Spine1", "Spine", (0.0, 0.22, 0.0), None),
    ("Neck", "Spine1", (0.0, 0.20, 0.0), None),
    ("Head", "Neck", (0.0, 0.11, 0.0), (0.0, 0.18, 0.0)),
    ("LeftShoulder", "Spine1", (0.05, 0.16, 0.0), None),
    ("LeftArm", "LeftShoulder", (0.13, 0.0, 0.0), None),
    ("LeftForeArm", "LeftArm", (0.27, 0.0, 0.0), None),
    ("LeftHand", "LeftForeArm", (0.24, 0.0, 0.0), (0.12, 0.0, 0.0)),
    ("RightShoulder", "Spine1", (-0.05, 0.16, 0.0), None),
    ("RightArm", "RightShoulder", (-0.13, 0.0, 0.0), None),
    ("RightForeArm", "RightArm", (-0.27, 0.0, 0.0), None),
    ("RightHand", "RightForeArm", (-0.24, 0.0, 0.0), (-0.12, 0.0, 0.0)),
    ("LeftUpLeg", "Hips", (0.10, -0.02, 0.0), None),
    ("LeftLeg", "LeftUpLeg", (0.0, -0.43, 0.0), None),
    ("LeftFoot", "LeftLeg", (0.0, -0.42, 0.0), None),
    ("LeftToeBase", "LeftFoot", (0.0, -0.05, 0.12), (0.0, 0.0, 0.08)),
    ("RightUpLeg", "Hips", (-0.10, -0.02, 0.0), None),
    ("RightLeg", "RightUpLeg", (0.0, -0.43, 0.0), None),
    ("RightFoot", "RightLeg", (0.0, -0.42, 0.0), None),
    ("RightToeBase", "RightFoot", (0.0, -0.05, 0.12), (0.0, 0.0, 0.08)),
]

# Rest bone direction vector for each joint in BVH world space
REST_DIRS: Dict[str, np.ndarray] = {
    "Hips": np.array([0.0, 1.0, 0.0]),
    "Spine": np.array([0.0, 1.0, 0.0]),
    "Spine1": np.array([0.0, 1.0, 0.0]),
    "Neck": np.array([0.0, 1.0, 0.0]),
    "Head": np.array([0.0, 1.0, 0.0]),
    "LeftShoulder": np.array([1.0, 0.0, 0.0]),
    "LeftArm": np.array([1.0, 0.0, 0.0]),
    "LeftForeArm": np.array([1.0, 0.0, 0.0]),
    "LeftHand": np.array([1.0, 0.0, 0.0]),
    "RightShoulder": np.array([-1.0, 0.0, 0.0]),
    "RightArm": np.array([-1.0, 0.0, 0.0]),
    "RightForeArm": np.array([-1.0, 0.0, 0.0]),
    "RightHand": np.array([-1.0, 0.0, 0.0]),
    "LeftUpLeg": np.array([0.0, -1.0, 0.0]),
    "LeftLeg": np.array([0.0, -1.0, 0.0]),
    "LeftFoot": np.array([0.0, -0.38, 0.925]),
    "LeftToeBase": np.array([0.0, 0.0, 1.0]),
    "RightUpLeg": np.array([0.0, -1.0, 0.0]),
    "RightLeg": np.array([0.0, -1.0, 0.0]),
    "RightFoot": np.array([0.0, -0.38, 0.925]),
    "RightToeBase": np.array([0.0, 0.0, 1.0]),
}


def _safe_norm(v: np.ndarray, fallback: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    if n < 1e-6:
        return fallback.copy()
    return v / n


def _basis_from_x_y(x_hint: np.ndarray, y_dir: np.ndarray) -> np.ndarray:
    """Builds a right-handed 3x3 rotation matrix with +Y along y_dir and +X toward x_hint."""
    y = _safe_norm(y_dir, np.array([0.0, 1.0, 0.0]))
    z = np.cross(x_hint, y)
    if np.linalg.norm(z) < 1e-5:
        alt = np.array([1.0, 0.0, 0.0]) if abs(y[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
        z = np.cross(alt, y)
    z = _safe_norm(z, np.array([0.0, 0.0, 1.0]))
    x = _safe_norm(np.cross(y, z), np.array([1.0, 0.0, 0.0]))
    return np.column_stack((x, y, z))


def _rot_from_vec_and_hint(
    rest_dir: np.ndarray,
    target_dir: np.ndarray,
    rest_hint: np.ndarray,
    target_hint: np.ndarray,
) -> Rotation:
    """Computes a flip-free world rotation aligning rest_dir->target_dir with twist hint."""
    r_fwd = _safe_norm(rest_dir, np.array([0.0, 1.0, 0.0]))
    t_fwd = _safe_norm(target_dir, r_fwd)

    r_side = np.cross(r_fwd, rest_hint)
    if np.linalg.norm(r_side) < 1e-5:
        alt = np.array([0.0, 0.0, 1.0]) if abs(r_fwd[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
        r_side = np.cross(r_fwd, alt)
    r_side = _safe_norm(r_side, np.array([1.0, 0.0, 0.0]))
    r_up = _safe_norm(np.cross(r_side, r_fwd), np.array([0.0, 1.0, 0.0]))
    mat_rest = np.column_stack((r_fwd, r_side, r_up))

    t_side = np.cross(t_fwd, target_hint)
    if np.linalg.norm(t_side) < 1e-5:
        # Fallback to shortest-arc rotation if hint is collinear
        dot = float(np.clip(np.dot(r_fwd, t_fwd), -1.0, 1.0))
        if dot > 0.9999:
            return Rotation.identity()
        if dot < -0.9999:
            return Rotation.from_rotvec(r_side * math.pi)
        axis = _safe_norm(np.cross(r_fwd, t_fwd), r_side)
        return Rotation.from_rotvec(axis * math.acos(dot))
    t_side = _safe_norm(t_side, r_side)
    t_up = _safe_norm(np.cross(t_side, t_fwd), r_up)
    mat_tgt = np.column_stack((t_fwd, t_side, t_up))

    return Rotation.from_matrix(mat_tgt @ mat_rest.T)


def _ensure_model_file(variant: str, explicit_path: Optional[Path]) -> Path:
    """Returns local path to MediaPipe PoseLandmarker .task file, downloading if absent."""
    if explicit_path is not None:
        if not explicit_path.is_file():
            raise FileNotFoundError(f"Pose model file not found: {explicit_path}")
        return explicit_path

    repo_root = Path(__file__).resolve().parent.parent.parent
    cache_dir = repo_root / ".venv_mocap" / "models"
    cache_dir.mkdir(parents=True, exist_ok=True)
    model_path = cache_dir / f"pose_landmarker_{variant}.task"
    if not model_path.is_file():
        url = MODEL_URLS[variant]
        print(f"[video_to_bvh] Downloading MediaPipe pose model ({variant}) to {model_path}...")
        urllib.request.urlretrieve(url, str(model_path))
    return model_path


def _extract_world_landmarks(video_path: Path, model_path: Path) -> Tuple[np.ndarray, float]:
    """Runs MediaPipe PoseLandmarker over video_path; returns (landmarks[N,33,3], src_fps)."""
    if not video_path.is_file():
        raise FileNotFoundError(f"Input video not found: {video_path}")

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Failed to open video: {video_path}")

    src_fps = float(cap.get(cv2.CAP_PROP_FPS))
    if src_fps <= 1.0 or math.isnan(src_fps):
        src_fps = 30.0

    options = vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.4,
        min_pose_presence_confidence=0.4,
        min_tracking_confidence=0.4,
    )

    raw_frames: List[Optional[np.ndarray]] = []
    frame_idx = 0
    with vision.PoseLandmarker.create_from_options(options) as landmarker:
        while True:
            ok, frame_bgr = cap.read()
            if not ok:
                break
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame_rgb)
            ts_ms = int(round((frame_idx / src_fps) * 1000.0))
            result = landmarker.detect_for_video(mp_img, ts_ms)

            if result.pose_world_landmarks:
                pts = np.zeros((33, 3), dtype=np.float64)
                for i, lm in enumerate(result.pose_world_landmarks[0]):
                    # Convert MediaPipe (+X left, +Y down, +Z away) -> BVH (+X left, +Y up, +Z fwd)
                    pts[i, 0] = float(lm.x)
                    pts[i, 1] = float(-lm.y)
                    pts[i, 2] = float(-lm.z)
                raw_frames.append(pts)
            else:
                raw_frames.append(None)
            frame_idx += 1

    cap.release()
    valid_indices = [i for i, f in enumerate(raw_frames) if f is not None]
    if not valid_indices:
        raise RuntimeError(f"No human pose detected in any frame of {video_path}")

    # Linearly interpolate any frames where pose detection dropped out
    n_frames = len(raw_frames)
    arr = np.zeros((n_frames, 33, 3), dtype=np.float64)
    for i in valid_indices:
        arr[i] = raw_frames[i]  # type: ignore[assignment]
    if len(valid_indices) < n_frames:
        valid_x = np.array(valid_indices, dtype=np.float64)
        all_x = np.arange(n_frames, dtype=np.float64)
        for lm_i in range(33):
            for ax in range(3):
                arr[:, lm_i, ax] = np.interp(all_x, valid_x, arr[valid_indices, lm_i, ax])

    return arr, src_fps


def _resample_and_smooth(landmarks: np.ndarray, src_fps: float, dst_fps: float, smooth: float) -> np.ndarray:
    """Resamples landmarks to dst_fps and applies zero-phase Savitzky-Golay smoothing."""
    n_src = landmarks.shape[0]
    if n_src == 1:
        return landmarks.copy()

    duration = (n_src - 1) / src_fps
    n_dst = max(2, int(round(duration * dst_fps)) + 1)
    t_src = np.linspace(0.0, duration, n_src)
    t_dst = np.linspace(0.0, duration, n_dst)

    resampled = np.zeros((n_dst, 33, 3), dtype=np.float64)
    for lm_i in range(33):
        for ax in range(3):
            resampled[:, lm_i, ax] = np.interp(t_dst, t_src, landmarks[:, lm_i, ax])

    smooth_clamped = max(0.0, min(1.0, smooth))
    if smooth_clamped > 0.0 and n_dst >= 5:
        # Map smooth in (0..1] to odd Savitzky-Golay window in [5..min(n_dst, 25)]
        win = int(round(5 + smooth_clamped * 20))
        if win % 2 == 0:
            win += 1
        win = min(win, n_dst if n_dst % 2 == 1 else n_dst - 1)
        if win >= 5:
            poly = min(3, win - 2)
            for lm_i in range(33):
                for ax in range(3):
                    resampled[:, lm_i, ax] = savgol_filter(resampled[:, lm_i, ax], win, poly)

    return resampled


def _solve_frame_rotations(pts: np.ndarray) -> Tuple[np.ndarray, Dict[str, Rotation]]:
    """Solves world-space Rotation for every BVH joint and grounded Hips position."""
    l_hip = pts[LM_LEFT_HIP]
    r_hip = pts[LM_RIGHT_HIP]
    mid_hip = 0.5 * (l_hip + r_hip)

    l_sh = pts[LM_LEFT_SHOULDER]
    r_sh = pts[LM_RIGHT_SHOULDER]
    mid_sh = 0.5 * (l_sh + r_sh)

    l_ear = pts[LM_LEFT_EAR]
    r_ear = pts[LM_RIGHT_EAR]
    mid_ear = 0.5 * (l_ear + r_ear)
    nose = pts[LM_NOSE]

    # Estimate grounded hip height above lowest foot point
    foot_ys = [
        pts[LM_LEFT_HEEL][1],
        pts[LM_RIGHT_HEEL][1],
        pts[LM_LEFT_FOOT_INDEX][1],
        pts[LM_RIGHT_FOOT_INDEX][1],
    ]
    hip_height = max(0.25, float(mid_hip[1] - min(foot_ys)))
    hips_pos = np.array([0.0, hip_height, 0.0], dtype=np.float64)

    # Torso / Hips / Chest / Head world orientations
    hip_left = _safe_norm(l_hip - r_hip, np.array([1.0, 0.0, 0.0]))
    sh_left = _safe_norm(l_sh - r_sh, hip_left)
    torso_up = _safe_norm(mid_sh - mid_hip, np.array([0.0, 1.0, 0.0]))

    r_hips = Rotation.from_matrix(_basis_from_x_y(hip_left, torso_up))
    r_chest = Rotation.from_matrix(_basis_from_x_y(sh_left, torso_up))
    # Split twist evenly across Spine and Spine1
    r_spine = Rotation.from_matrix(
        _basis_from_x_y(_safe_norm(0.5 * (hip_left + sh_left), hip_left), torso_up)
    )

    torso_fwd = _safe_norm(np.cross(sh_left, torso_up), np.array([0.0, 0.0, 1.0]))
    neck_dir = _safe_norm(mid_ear - mid_sh, torso_up)
    head_left = _safe_norm(l_ear - r_ear, sh_left)
    head_fwd = _safe_norm(nose - mid_ear, torso_fwd)
    head_up = _safe_norm(np.cross(head_fwd, head_left), neck_dir)
    r_neck = Rotation.from_matrix(_basis_from_x_y(0.5 * (sh_left + head_left), neck_dir))
    r_head = Rotation.from_matrix(_basis_from_x_y(head_left, head_up))

    world_rots: Dict[str, Rotation] = {
        "Hips": r_hips,
        "Spine": r_spine,
        "Spine1": r_chest,
        "Neck": r_neck,
        "Head": r_head,
        "LeftShoulder": r_chest,
        "RightShoulder": r_chest,
    }

    # Arms
    for side, sh_i, el_i, wr_i, idx_i, sign in (
        ("Left", LM_LEFT_SHOULDER, LM_LEFT_ELBOW, LM_LEFT_WRIST, LM_LEFT_INDEX, 1.0),
        ("Right", LM_RIGHT_SHOULDER, LM_RIGHT_ELBOW, LM_RIGHT_WRIST, LM_RIGHT_INDEX, -1.0),
    ):
        u_vec = pts[el_i] - pts[sh_i]
        l_vec = pts[wr_i] - pts[el_i]
        h_vec = pts[idx_i] - pts[wr_i]

        # Bend normal hints elbow orientation; fall back to torso forward when arm is straight
        bend_hint = np.cross(u_vec, l_vec) * sign
        arm_hint = bend_hint if np.linalg.norm(bend_hint) > 0.015 else torso_fwd

        world_rots[f"{side}Arm"] = _rot_from_vec_and_hint(
            REST_DIRS[f"{side}Arm"], u_vec, np.array([0.0, 0.0, 1.0]), arm_hint
        )
        world_rots[f"{side}ForeArm"] = _rot_from_vec_and_hint(
            REST_DIRS[f"{side}ForeArm"], l_vec, np.array([0.0, 0.0, 1.0]), arm_hint
        )
        world_rots[f"{side}Hand"] = _rot_from_vec_and_hint(
            REST_DIRS[f"{side}Hand"], h_vec, np.array([0.0, 0.0, 1.0]), arm_hint
        )

    # Legs
    hip_fwd = _safe_norm(np.cross(hip_left, torso_up), np.array([0.0, 0.0, 1.0]))
    for side, hp_i, kn_i, an_i, ft_i in (
        ("Left", LM_LEFT_HIP, LM_LEFT_KNEE, LM_LEFT_ANKLE, LM_LEFT_FOOT_INDEX),
        ("Right", LM_RIGHT_HIP, LM_RIGHT_KNEE, LM_RIGHT_ANKLE, LM_RIGHT_FOOT_INDEX),
    ):
        u_vec = pts[kn_i] - pts[hp_i]
        l_vec = pts[an_i] - pts[kn_i]
        f_vec = pts[ft_i] - pts[an_i]

        world_rots[f"{side}UpLeg"] = _rot_from_vec_and_hint(
            REST_DIRS[f"{side}UpLeg"], u_vec, np.array([0.0, 0.0, 1.0]), hip_fwd
        )
        world_rots[f"{side}Leg"] = _rot_from_vec_and_hint(
            REST_DIRS[f"{side}Leg"], l_vec, np.array([0.0, 0.0, 1.0]), hip_fwd
        )
        world_rots[f"{side}Foot"] = _rot_from_vec_and_hint(
            REST_DIRS[f"{side}Foot"], f_vec, np.array([0.0, 1.0, 0.0]), torso_up
        )
        world_rots[f"{side}ToeBase"] = world_rots[f"{side}Foot"]

    return hips_pos, world_rots


def _build_hierarchy_lines() -> List[str]:
    """Formats the BVH HIERARCHY block."""
    children_map: Dict[Optional[str], List[Tuple[str, Tuple[float, float, float], Optional[Tuple[float, float, float]]]]] = {}
    for name, parent, offset, end_site in BVH_JOINTS:
        children_map.setdefault(parent, []).append((name, offset, end_site))

    lines: List[str] = ["HIERARCHY"]

    def _emit(
        name: str,
        offset: Tuple[float, float, float],
        end_site: Optional[Tuple[float, float, float]],
        depth: int,
        is_root: bool,
    ) -> None:
        pad = "  " * depth
        kind = "ROOT" if is_root else "JOINT"
        lines.append(f"{pad}{kind} {name}")
        lines.append(f"{pad}{{")
        lines.append(f"{pad}  OFFSET {offset[0]:.6f} {offset[1]:.6f} {offset[2]:.6f}")
        if is_root:
            lines.append(
                f"{pad}  CHANNELS 6 Xposition Yposition Zposition Zrotation Xrotation Yrotation"
            )
        else:
            lines.append(f"{pad}  CHANNELS 3 Zrotation Xrotation Yrotation")

        kids = children_map.get(name, [])
        for c_name, c_off, c_end in kids:
            _emit(c_name, c_off, c_end, depth + 1, is_root=False)

        if end_site is not None:
            lines.append(f"{pad}  End Site")
            lines.append(f"{pad}  {{")
            lines.append(f"{pad}    OFFSET {end_site[0]:.6f} {end_site[1]:.6f} {end_site[2]:.6f}")
            lines.append(f"{pad}  }}")
        lines.append(f"{pad}}}")

    root_name, root_off, root_end = children_map[None][0]
    _emit(root_name, root_off, root_end, depth=0, is_root=True)
    return lines


def _joint_dfs_order() -> List[Tuple[str, Optional[str]]]:
    """Returns joints in exact BVH DFS emission order matching the HIERARCHY block."""
    children_map: Dict[Optional[str], List[str]] = {}
    for name, parent, _, _ in BVH_JOINTS:
        children_map.setdefault(parent, []).append(name)

    order: List[Tuple[str, Optional[str]]] = []

    def _walk(name: str, parent: Optional[str]) -> None:
        order.append((name, parent))
        for child in children_map.get(name, []):
            _walk(child, name)

    _walk(children_map[None][0], None)
    return order


def write_bvh(landmarks: np.ndarray, fps: float, out_path: Path) -> None:
    """Solves per-frame local ZXY Euler angles and writes a standard .bvh file."""
    n_frames = landmarks.shape[0]
    dfs_joints = _joint_dfs_order()
    n_joints = len(dfs_joints)

    hips_positions = np.zeros((n_frames, 3), dtype=np.float64)
    euler_rad = np.zeros((n_frames, n_joints, 3), dtype=np.float64)

    for f_idx in range(n_frames):
        hips_pos, world_rots = _solve_frame_rotations(landmarks[f_idx])
        hips_positions[f_idx] = hips_pos
        for j_idx, (j_name, p_name) in enumerate(dfs_joints):
            r_world = world_rots[j_name]
            if p_name is None:
                r_local = r_world
            else:
                r_local = world_rots[p_name].inv() * r_world
            # Intrinsic ZXY matches BVH "Zrotation Xrotation Yrotation"
            euler_rad[f_idx, j_idx] = r_local.as_euler("ZXY", degrees=False)

    # Unwrap Euler angles across frames to prevent 360-deg jumps
    euler_rad = np.unwrap(euler_rad, axis=0)
    euler_deg = np.degrees(euler_rad)

    lines = _build_hierarchy_lines()
    lines.append("MOTION")
    lines.append(f"Frames: {n_frames}")
    lines.append(f"Frame Time: {1.0 / fps:.6f}")

    for f_idx in range(n_frames):
        vals: List[str] = [
            f"{hips_positions[f_idx, 0]:.6f}",
            f"{hips_positions[f_idx, 1]:.6f}",
            f"{hips_positions[f_idx, 2]:.6f}",
        ]
        for j_idx in range(n_joints):
            rz, rx, ry = euler_deg[f_idx, j_idx]
            vals.append(f"{rz:.4f}")
            vals.append(f"{rx:.4f}")
            vals.append(f"{ry:.4f}")
        lines.append(" ".join(vals))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[video_to_bvh] Wrote {out_path} ({n_frames} frames @ {fps:.1f} FPS)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract 3D human pose from an MP4 video via MediaPipe and export a BVH clip."
    )
    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Input video file (.mp4, .mov, .webm, etc.).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output .bvh file path (e.g. assets/mocap/godiva/walk.bvh).",
    )
    parser.add_argument(
        "--fps",
        type=float,
        default=60.0,
        help="Target output BVH frame rate (default: 60).",
    )
    parser.add_argument(
        "--smooth",
        type=float,
        default=0.35,
        help="Temporal smoothing strength in [0.0..1.0] (default: 0.35).",
    )
    parser.add_argument(
        "--model",
        type=str,
        choices=("lite", "full", "heavy"),
        default="full",
        help="MediaPipe PoseLandmarker model variant (default: full).",
    )
    parser.add_argument(
        "--model-path",
        type=Path,
        default=None,
        help="Optional path to a local pose_landmarker_*.task file.",
    )
    args = parser.parse_args()

    model_path = _ensure_model_file(args.model, args.model_path)
    raw_landmarks, src_fps = _extract_world_landmarks(args.input, model_path)
    smoothed = _resample_and_smooth(raw_landmarks, src_fps=src_fps, dst_fps=args.fps, smooth=args.smooth)
    write_bvh(smoothed, fps=args.fps, out_path=args.output)


if __name__ == "__main__":
    main()
