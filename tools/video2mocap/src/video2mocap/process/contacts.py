"""Foot contact detection and ground estimation.

A foot is in contact when it is close to the ground AND (almost) still. We use hysteresis (separate
enter/exit thresholds) and minimum durations so contacts don't flicker - flicker is what produces
the "skating then popping" look of most video mocap.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..motion import Motion
from .filters import lowpass


@dataclass
class ContactConfig:
    height_enter_m: float = 0.05  # foot joint height above its own ground level to start a contact
    height_exit_m: float = 0.08
    speed_enter_mps: float = 0.25  # horizontal speed to start a contact
    speed_exit_mps: float = 0.45
    min_contact_frames: int = 4
    max_gap_frames: int = 2  # gaps shorter than this inside a contact are filled
    use_estimator_contacts: bool = True  # if the backend predicted contacts, combine with them
    # contact DECISIONS are made on a heavily low-passed copy of the foot track (the motion itself is
    # untouched); this keeps residual jitter from breaking a stance into flickering pieces
    detect_cutoff_hz: float = 3.0
    # Estimators skate: a planted foot from video mocap can still "move" 0.2-0.6 m/s while a swinging
    # foot moves 1.5-3.5 m/s. Speed thresholds therefore scale with the foot's own swing speed
    # (90th percentile): enter = max(speed_enter_mps, adaptive_speed_ratio * p90).
    adaptive_speed_ratio: float = 0.25
    # ground level is a rolling low percentile over this window (slopes, uneven floors, drift)
    ground_window_s: float = 2.0


def estimate_ground_height(heights: np.ndarray, percentile: float = 5.0) -> float:
    """Ground level of one foot joint from its height track (robust low percentile)."""
    return float(np.percentile(heights, percentile))


def rolling_ground(heights: np.ndarray, window: int, percentile: float = 10.0) -> np.ndarray:
    """Per-frame ground level: low percentile of the height in a centred window, then smoothed."""
    T = len(heights)
    if window >= T:
        return np.full(T, estimate_ground_height(heights, percentile))
    half = window // 2
    g = np.array([np.percentile(heights[max(0, t - half): t + half + 1], percentile) for t in range(T)])
    k = np.ones(half | 1) / (half | 1)
    return np.convolve(np.pad(g, (len(k) // 2,), mode="edge"), k, mode="valid")[:T]


def _runs(mask: np.ndarray) -> list[tuple[int, int]]:
    """[start, end) of True runs."""
    m = np.concatenate([[False], mask, [False]]).astype(int)
    d = np.diff(m)
    return list(zip(np.where(d == 1)[0], np.where(d == -1)[0]))


def clean_mask(mask: np.ndarray, min_len: int, max_gap: int) -> np.ndarray:
    mask = mask.copy()
    # fill short gaps
    for s, e in _runs(~mask):
        if s > 0 and e < len(mask) and (e - s) <= max_gap:
            mask[s:e] = True
    # drop short contacts
    for s, e in _runs(mask):
        if (e - s) < min_len:
            mask[s:e] = False
    return mask


def detect_contacts(motion: Motion, foot_joints: list[str], cfg: ContactConfig | None = None,
                    up_axis: int = 1) -> dict[str, np.ndarray]:
    cfg = cfg or ContactConfig()
    gpos, _ = motion.fk()
    horiz = [a for a in range(3) if a != up_axis]
    out: dict[str, np.ndarray] = {}
    for name in foot_joints:
        j = motion.skeleton.index(name)
        p = lowpass(gpos[:, j], motion.fps, cfg.detect_cutoff_hz)
        h = p[:, up_axis] - rolling_ground(p[:, up_axis], int(cfg.ground_window_s * motion.fps))
        v = np.zeros(len(p))
        v[1:] = np.linalg.norm(np.diff(p[:, horiz], axis=0), axis=1) * motion.fps
        v[0] = v[1] if len(v) > 1 else 0.0
        p90 = float(np.percentile(v, 90))
        v_enter = max(cfg.speed_enter_mps, cfg.adaptive_speed_ratio * p90)
        v_exit = v_enter * cfg.speed_exit_mps / cfg.speed_enter_mps
        state = False
        mask = np.zeros(len(p), dtype=bool)
        for t in range(len(p)):
            if state:
                state = h[t] < cfg.height_exit_m and v[t] < v_exit
            else:
                state = h[t] < cfg.height_enter_m and v[t] < v_enter
            mask[t] = state
        if cfg.use_estimator_contacts and name in motion.contacts:
            # estimator says contact and geometry roughly agrees -> contact
            est = motion.contacts[name] & (h < cfg.height_exit_m * 1.5)
            mask = mask | est
        out[name] = clean_mask(mask, cfg.min_contact_frames, cfg.max_gap_frames)
    return out


def contact_runs(mask: np.ndarray) -> list[tuple[int, int]]:
    return _runs(mask)
