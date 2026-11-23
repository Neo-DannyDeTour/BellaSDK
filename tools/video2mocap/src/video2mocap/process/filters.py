"""Zero-phase temporal filtering.

Offline we can look into the future, so we use forward-backward (filtfilt) Butterworth filters:
no lag, no overshoot of contacts in time. Default cut-offs are deliberately conservative: our goal is
to remove estimator jitter, never to remove real motion (impacts, snaps, hand flicks).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.signal import butter, filtfilt

from .. import quat
from ..motion import Motion


def lowpass(x: np.ndarray, fps: float, cutoff_hz: float, order: int = 2) -> np.ndarray:
    """Zero-phase Butterworth low-pass along axis 0."""
    if cutoff_hz <= 0 or cutoff_hz >= fps / 2 or x.shape[0] < 3 * (order + 1) + 1:
        return x.copy()
    b, a = butter(order, cutoff_hz / (fps / 2.0))
    padlen = min(x.shape[0] - 1, 3 * max(len(a), len(b)) * 4)
    return filtfilt(b, a, x, axis=0, padlen=padlen, padtype="odd")


def smooth_quaternions(q: np.ndarray, fps: float, cutoff_hz: float) -> np.ndarray:
    """Low-pass a (T,...,4) quaternion track. Components are filtered after enforcing hemisphere
    continuity and renormalised; for the small rotations removed by a jitter filter this is
    numerically equivalent to filtering on the manifold."""
    q = quat.make_continuous(q, axis=0)
    return quat.normalize(lowpass(q, fps, cutoff_hz))


@dataclass
class SmoothingConfig:
    root_cutoff_hz: float = 6.0
    body_cutoff_hz: float = 8.0
    extremity_cutoff_hz: float = 10.0  # hands/feet move fast; keep their detail
    # joints whose name contains one of these tokens use extremity_cutoff_hz
    extremity_tokens: tuple[str, ...] = ("hand", "wrist", "finger", "thumb", "index", "middle", "ring",
                                         "pinky", "foot", "ankle", "toe", "head", "jaw", "eye")
    # optional per-joint override, name -> cutoff (0 disables filtering for that joint)
    overrides: dict[str, float] | None = None


def smooth_motion(motion: Motion, cfg: SmoothingConfig | None = None) -> Motion:
    cfg = cfg or SmoothingConfig()
    out = motion.copy()
    out.root_pos = lowpass(motion.root_pos, motion.fps, cfg.root_cutoff_hz)
    for j, name in enumerate(motion.skeleton.names):
        cutoff = cfg.body_cutoff_hz
        if any(tok in name.lower() for tok in cfg.extremity_tokens):
            cutoff = cfg.extremity_cutoff_hz
        if cfg.overrides and name in cfg.overrides:
            cutoff = cfg.overrides[name]
        out.local_rot[:, j] = smooth_quaternions(motion.local_rot[:, j], motion.fps, cutoff)
    out.meta.setdefault("history", []).append({"op": "smooth", "cfg": cfg.__dict__ | {"extremity_tokens": list(cfg.extremity_tokens)}})
    return out
