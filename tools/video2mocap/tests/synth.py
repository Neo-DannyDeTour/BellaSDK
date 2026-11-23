"""Synthetic motions with known ground truth for tests."""
from __future__ import annotations

import numpy as np

from video2mocap import quat
from video2mocap.motion import Motion
from video2mocap.rigs import test_humanoid


def walk(seconds: float = 4.0, fps: float = 30.0, speed: float = 1.0, cadence_hz: float = 1.0,
         stance: float = 0.6) -> Motion:
    """Physically consistent walk: each foot is planted at a fixed world spot during stance (zero
    skate ground truth) and swings in an arc; legs are solved with IK from a slightly bent pose."""
    sk = test_humanoid()
    T = int(seconds * fps)
    t = np.arange(T) / fps
    J = sk.num_joints
    P = 1.0 / cadence_hz
    stride = speed * P
    x = np.array([1.0, 0, 0])
    rot = quat.identity((T, J))
    root = np.zeros((T, 3))
    root[:, 2] = speed * t
    root[:, 1] = 0.88 + 0.015 * np.cos(4 * np.pi * cadence_hz * t)
    for side, sgn in (("Left", 1.0), ("Right", -1.0)):
        rot[:, sk.index(f"{side}UpLeg")] = quat.from_axis_angle(x, np.full(T, -0.25))
        rot[:, sk.index(f"{side}Leg")] = quat.from_axis_angle(x, np.full(T, 0.5))
        rot[:, sk.index(f"{side}Foot")] = quat.from_axis_angle(x, np.full(T, -0.25))
        arm = sk.index(f"{side}Arm")
        swing = 0.3 * np.sin(2 * np.pi * cadence_hz * t + (0 if sgn > 0 else np.pi))
        rot[:, arm] = quat.mul(quat.from_axis_angle(np.array([0, 0, 1.0]), np.full(T, sgn * -1.2)),
                               quat.from_axis_angle(x, swing))
    m = Motion(sk, fps, root, rot)
    from video2mocap.process.ik import two_bone_ik

    for side, sgn, phase0 in (("Left", 1.0, 0.0), ("Right", -1.0, 0.5)):
        a, b, c = sk.index(f"{side}UpLeg"), sk.index(f"{side}Leg"), sk.index(f"{side}Foot")
        target = np.zeros((T, 3))
        lateral = 0.09 * sgn
        for i, ti in enumerate(t):
            u = (ti / P + phase0) % 1.0  # 0..stance: planted, stance..1: swing
            cycle = np.floor(ti / P + phase0)
            plant_time = (cycle - phase0) * P  # start of this cycle's stance
            plant_z = speed * plant_time + 0.3 * stride
            if u < stance:
                z, y = plant_z, 0.07
            else:
                s = (u - stance) / (1 - stance)
                ease = 0.5 - 0.5 * np.cos(np.pi * s)
                z = plant_z + stride * ease
                y = 0.07 + 0.08 * np.sin(np.pi * s)
            target[i] = [lateral, y, z]
        two_bone_ik(m, (a, b, c), target, np.ones(T), keep_end_orientation=False)
        # foot flat on the ground during stance: cancel the inherited orientation
        _, grot = m.fk()
        m.local_rot[:, c] = quat.normalize(quat.mul(quat.conj(grot[:, b]), quat.identity((T,))))
    return m


def stand(seconds: float = 3.0, fps: float = 30.0) -> Motion:
    sk = test_humanoid()
    T = int(seconds * fps)
    root = np.tile([0.0, 0.95, 0.0], (T, 1))
    return Motion(sk, fps, root, quat.identity((T, sk.num_joints)))


def add_noise(m: Motion, rot_deg: float = 2.0, pos_m: float = 0.01, seed: int = 0) -> Motion:
    rng = np.random.default_rng(seed)
    out = m.copy()
    rv = np.radians(rot_deg) * rng.standard_normal(out.local_rot.shape[:-1] + (3,))
    out.local_rot = quat.normalize(quat.mul(out.local_rot, quat.from_rotvec(rv)))
    out.root_pos = out.root_pos + pos_m * rng.standard_normal(out.root_pos.shape)
    return out
