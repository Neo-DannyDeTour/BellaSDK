"""Analytic two-bone IK, vectorised over frames."""
from __future__ import annotations

import numpy as np

from .. import quat
from ..motion import Motion

_EPS = 1e-8


def _unit(v: np.ndarray) -> np.ndarray:
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), _EPS)


def two_bone_ik(motion: Motion, chain: tuple[int, int, int], target: np.ndarray, weight: np.ndarray,
                keep_end_orientation: bool = True, pole: np.ndarray | None = None) -> None:
    """In-place. chain = (a, b, c) e.g. (thigh, shin, ankle). target (T,3), weight (T,) in [0,1].

    The knee keeps bending in the plane the estimator gave it (pole = current knee), so we never flip
    a knee. If keep_end_orientation, the end joint keeps its global orientation (foot stays flat).
    pole (T,3): direction the middle joint should bend towards, used only where the chain is (almost)
    straight and the bend plane is undefined. For legs, the foot's forward direction is a good pole.
    """
    a, b, c = chain
    sk = motion.skeleton
    frames = np.where(weight > 1e-4)[0]
    if frames.size == 0:
        return
    gpos, grot = motion.fk()
    gpos, grot = gpos[frames], grot[frames]
    w = np.clip(weight[frames], 0.0, 1.0)

    pa, pb, pc = gpos[:, a], gpos[:, b], gpos[:, c]
    # blend from the current end position towards the target by weight
    t = pc + (target[frames] - pc) * w[:, None]

    lab = np.linalg.norm(pb - pa, axis=-1)
    lcb = np.linalg.norm(pb - pc, axis=-1)
    lat = np.clip(np.linalg.norm(t - pa, axis=-1), 1e-4, (lab + lcb) * 0.9999)

    ac_ab_0 = np.arccos(np.clip(np.sum(_unit(pc - pa) * _unit(pb - pa), -1), -1, 1))
    ba_bc_0 = np.arccos(np.clip(np.sum(_unit(pa - pb) * _unit(pc - pb), -1), -1, 1))
    ac_ab_1 = np.arccos(np.clip((lcb**2 - lab**2 - lat**2) / (-2 * lab * lat), -1, 1))
    ba_bc_1 = np.arccos(np.clip((lat**2 - lab**2 - lcb**2) / (-2 * lab * lcb), -1, 1))

    raw0 = np.cross(pc - pa, pb - pa)
    straight = np.linalg.norm(raw0, axis=-1) < 1e-3 * lab * lcb
    if pole is not None and np.any(straight):
        raw0 = np.where(straight[:, None], np.cross(pc - pa, pole[frames]), raw0)
    axis0 = _unit(raw0)
    ga_inv = quat.conj(grot[:, a])
    gb_inv = quat.conj(grot[:, b])

    r0 = quat.from_axis_angle(quat.rotate(ga_inv, axis0), ac_ab_1 - ac_ab_0)
    r1 = quat.from_axis_angle(quat.rotate(gb_inv, axis0), ba_bc_1 - ba_bc_0)

    end_global = grot[:, c].copy()
    # 1) bend: set the a-b-c triangle to the length |a-t|
    motion.local_rot[frames, a] = quat.normalize(quat.mul(motion.local_rot[frames, a], r0))
    motion.local_rot[frames, b] = quat.normalize(quat.mul(motion.local_rot[frames, b], r1))
    # 2) swing: rotate the whole chain at `a` so c lands on t (recomputed after the bend, exact)
    gpos2, grot2 = motion.fk()
    pa2, pc2 = gpos2[frames, a], gpos2[frames, c]
    swing_g = quat.between(pc2 - pa2, t - pa2)  # global-frame rotation about a
    ga2 = grot2[frames, a]
    swing_l = quat.mul(quat.mul(quat.conj(ga2), swing_g), ga2)  # same rotation in a's local frame
    motion.local_rot[frames, a] = quat.normalize(quat.mul(motion.local_rot[frames, a], swing_l))
    if keep_end_orientation:
        _, grot2 = motion.fk()
        parent_g = grot2[frames, b]
        loc = quat.mul(quat.conj(parent_g), end_global)  # = rest_rot[c] * local_rot[c]
        motion.local_rot[frames, c] = quat.normalize(quat.mul(quat.conj(sk.rest_rot[c]), loc))
