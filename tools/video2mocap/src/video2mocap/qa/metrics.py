"""Objective quality metrics. Every pipeline run writes them, so "it looks better" is always backed by
numbers and regressions are caught in CI.

- foot_skate_cm_s: mean horizontal speed of contact joints while in contact (0 is perfect)
- jitter_m_s3: mean jerk magnitude of all joints (lower = smoother); compare runs, not absolutes
- hf_energy_ratio: share of joint-position energy above `hf_cutoff_hz` (estimator noise lives there)
- penetration_ratio: frames where a contact joint is more than 1 cm below the ground
- reproj_px (optional): mean 2D reprojection error against detected keypoints
"""
from __future__ import annotations

import numpy as np

from ..motion import Motion


def foot_skate(motion: Motion, gpos: np.ndarray | None = None, up_axis: int = 1) -> dict[str, float]:
    if gpos is None:
        gpos, _ = motion.fk()
    horiz = [a for a in range(3) if a != up_axis]
    out = {}
    for name, mask in motion.contacts.items():
        j = motion.skeleton.index(name)
        v = np.linalg.norm(np.diff(gpos[:, j][:, horiz], axis=0), axis=1) * motion.fps
        m = mask[1:] & mask[:-1]
        out[name] = float(v[m].mean() * 100) if m.any() else 0.0
    return out


def jitter(motion: Motion, gpos: np.ndarray | None = None) -> float:
    if gpos is None:
        gpos, _ = motion.fk()
    if motion.num_frames < 4:
        return 0.0
    jerk = np.diff(gpos, n=3, axis=0) * motion.fps**3
    return float(np.linalg.norm(jerk, axis=-1).mean())


def hf_energy_ratio(motion: Motion, gpos: np.ndarray | None = None, hf_cutoff_hz: float = 12.0) -> float:
    if gpos is None:
        gpos, _ = motion.fk()
    x = gpos - gpos.mean(axis=0, keepdims=True)
    spec = np.abs(np.fft.rfft(x, axis=0)) ** 2
    freqs = np.fft.rfftfreq(x.shape[0], d=1.0 / motion.fps)
    total = spec[1:].sum()
    return float(spec[freqs > hf_cutoff_hz].sum() / total) if total > 0 else 0.0


def penetration(motion: Motion, gpos: np.ndarray | None = None, ground: float = 0.0, up_axis: int = 1,
                tol_m: float = 0.01) -> float:
    if gpos is None:
        gpos, _ = motion.fk()
    if not motion.contacts:
        return 0.0
    idx = [motion.skeleton.index(n) for n in motion.contacts]
    below = gpos[:, idx, up_axis] < ground - tol_m
    return float(below.any(axis=1).mean())


def reprojection_error(joints3d_cam: np.ndarray, K: np.ndarray, kp2d: np.ndarray, conf_thr: float = 0.5) -> float:
    """joints3d_cam (T,J,3) in camera space, K (3,3) or (T,3,3), kp2d (T,J,3) with confidence."""
    p = joints3d_cam @ (K.swapaxes(-1, -2) if K.ndim == 3 else K.T)
    uv = p[..., :2] / np.maximum(p[..., 2:3], 1e-6)
    ok = kp2d[..., 2] > conf_thr
    err = np.linalg.norm(uv - kp2d[..., :2], axis=-1)
    return float(err[ok].mean()) if ok.any() else float("nan")


def report(motion: Motion, ground: float = 0.0) -> dict:
    gpos, _ = motion.fk()
    skate = foot_skate(motion, gpos)
    return {
        "frames": motion.num_frames,
        "fps": motion.fps,
        "foot_skate_cm_s": skate,
        "foot_skate_cm_s_mean": float(np.mean(list(skate.values()))) if skate else 0.0,
        "jitter_m_s3": jitter(motion, gpos),
        "hf_energy_ratio": hf_energy_ratio(motion, gpos),
        "penetration_ratio": penetration(motion, gpos, ground),
        "contact_ratio": {k: float(v.mean()) for k, v in motion.contacts.items()},
    }
