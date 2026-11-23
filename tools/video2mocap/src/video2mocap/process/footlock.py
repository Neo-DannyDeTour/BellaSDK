"""Foot locking: while a foot is in contact it must not move. This removes foot skating, the most
visible artefact of video-based mocap.

For every contact run we pick one anchor (where the foot actually planted), pin the ankle there with
two-bone IK, and ease in/out of the pin so there is no pop when the foot lifts.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from ..motion import Motion
from .contacts import contact_runs
from .ik import two_bone_ik


@dataclass
class Leg:
    hip: str  # thigh / upper-leg joint
    knee: str
    ankle: str
    toe: str | None = None  # contact joint used for detection (falls back to ankle)


@dataclass
class FootLockConfig:
    blend_frames: int = 4  # ease-in/out length around each contact
    anchor: str = "first_third"  # "first_third" | "mean" | "first"
    snap_to_ground: bool = True
    up_axis: int = 1


def _ease(n: int) -> np.ndarray:
    x = (np.arange(1, n + 1)) / (n + 1)
    return 0.5 - 0.5 * np.cos(np.pi * x)  # smoothstep-like cosine ramp


def lock_feet(motion: Motion, legs: list[Leg], contacts: dict[str, np.ndarray],
              cfg: FootLockConfig | None = None, ground_height: float | None = None) -> Motion:
    cfg = cfg or FootLockConfig()
    out = motion.copy()
    sk = out.skeleton
    T = out.num_frames
    for leg in legs:
        key = leg.toe or leg.ankle
        if key not in contacts:
            continue
        mask = contacts[key]
        gpos, _ = out.fk()
        ankle = gpos[:, sk.index(leg.ankle)]
        contact_pt = gpos[:, sk.index(key)]
        target = ankle.copy()
        weight = np.zeros(T)
        foot_vec = ankle - contact_pt  # ankle relative to the contact point, per frame
        for s, e in contact_runs(mask):
            if cfg.anchor == "first":
                win = slice(s, s + 1)
            elif cfg.anchor == "mean":
                win = slice(s, e)
            else:  # the plant is best described by the beginning of the stance
                win = slice(s, s + max(1, (e - s) // 3))
            # pin the CONTACT point (toe, or ankle if no toe); the ankle follows the foot's own
            # per-frame orientation, so heel-off / toe roll during push-off is preserved
            anchor = contact_pt[win].mean(axis=0)
            if cfg.snap_to_ground and ground_height is not None:
                anchor[cfg.up_axis] = ground_height
            n = cfg.blend_frames
            ramp = _ease(n)
            lo, hi = max(0, s - n), min(T, e + n)
            w = np.zeros(T)
            w[s:e] = 1.0
            w[lo:s] = ramp[n - (s - lo):]
            w[e:hi] = ramp[::-1][: hi - e]
            span = slice(lo, hi)
            take = w[span] > weight[span]
            seg_target = anchor + foot_vec[span]
            target[span] = np.where(take[:, None], seg_target, target[span])
            weight[span] = np.maximum(weight[span], w[span])
        chain = (sk.index(leg.hip), sk.index(leg.knee), sk.index(leg.ankle))
        pole = None
        if leg.toe:  # knees bend towards where the foot points
            pole = contact_pt - ankle
            pole[:, cfg.up_axis] = 0.0
        two_bone_ik(out, chain, target, weight, pole=pole)
    out.contacts = {k: v.copy() for k, v in contacts.items()}
    out.meta.setdefault("history", []).append({"op": "foot_lock", "legs": [leg.__dict__ for leg in legs],
                                                "cfg": cfg.__dict__})
    return out


def place_on_ground(motion: Motion, contact_joints: list[str], contacts: dict[str, np.ndarray],
                    sole_offset: float = 0.0, up_axis: int = 1) -> tuple[Motion, float]:
    """Shift the whole motion vertically so contact joints rest at y = sole_offset on average.
    Returns the new motion and the ground height (always 0 after shifting) for later stages."""
    out = motion.copy()
    gpos, _ = out.fk()
    hs = []
    for name in contact_joints:
        m = contacts.get(name)
        if m is not None and m.any():
            hs.append(gpos[m, out.skeleton.index(name), up_axis])
    if not hs:
        return out, 0.0
    level = float(np.median(np.concatenate(hs)))
    out.root_pos[:, up_axis] -= level - sole_offset
    shift = [0.0, 0.0, 0.0]
    shift[up_axis] = -(level - sole_offset)
    out.meta.setdefault("history", []).append({"op": "place_on_ground", "shift": shift})
    return out, 0.0
