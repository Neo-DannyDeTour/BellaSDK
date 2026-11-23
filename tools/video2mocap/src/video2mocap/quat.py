"""Minimal, vectorised quaternion math. Convention: (w, x, y, z), unit quaternions, active rotations."""
from __future__ import annotations

import numpy as np


def normalize(q: np.ndarray) -> np.ndarray:
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def identity(shape: tuple[int, ...] = ()) -> np.ndarray:
    q = np.zeros(shape + (4,))
    q[..., 0] = 1.0
    return q


def mul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    aw, ax, ay, az = np.moveaxis(a, -1, 0)
    bw, bx, by, bz = np.moveaxis(b, -1, 0)
    return np.stack(
        [
            aw * bw - ax * bx - ay * by - az * bz,
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
        ],
        axis=-1,
    )


def conj(q: np.ndarray) -> np.ndarray:
    return q * np.array([1.0, -1.0, -1.0, -1.0])


def rotate(q: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Rotate vectors v (...,3) by quaternions q (...,4)."""
    w = q[..., :1]
    u = q[..., 1:]
    t = 2.0 * np.cross(u, v)
    return v + w * t + np.cross(u, t)


def from_axis_angle(axis: np.ndarray, angle: np.ndarray) -> np.ndarray:
    axis = np.asarray(axis, dtype=float)
    angle = np.asarray(angle, dtype=float)
    axis = axis / np.maximum(np.linalg.norm(axis, axis=-1, keepdims=True), 1e-12)
    half = angle[..., None] * 0.5
    shape = np.broadcast_shapes(axis.shape[:-1], angle.shape)
    w = np.broadcast_to(np.cos(half), shape + (1,))
    xyz = np.broadcast_to(np.sin(half) * axis, shape + (3,))
    return np.concatenate([w, xyz], axis=-1)


def from_rotvec(rv: np.ndarray) -> np.ndarray:
    angle = np.linalg.norm(rv, axis=-1)
    safe = np.where(angle < 1e-12, 1.0, angle)
    axis = rv / safe[..., None]
    q = from_axis_angle(axis, angle)
    q[angle < 1e-12] = identity()
    return q


def to_rotvec(q: np.ndarray) -> np.ndarray:
    q = normalize(q)
    q = np.where(q[..., :1] < 0, -q, q)
    s = np.linalg.norm(q[..., 1:], axis=-1)
    angle = 2.0 * np.arctan2(s, q[..., 0])
    scale = np.where(s < 1e-12, 2.0, angle / np.where(s < 1e-12, 1.0, s))
    return q[..., 1:] * scale[..., None]


def from_matrix(m: np.ndarray) -> np.ndarray:
    """Rotation matrices (...,3,3) -> quaternions (...,4). Shepperd's method."""
    m = np.asarray(m, dtype=float)
    shape = m.shape[:-2]
    m = m.reshape(-1, 3, 3)
    q = np.empty((m.shape[0], 4))
    tr = m[:, 0, 0] + m[:, 1, 1] + m[:, 2, 2]
    for i in range(m.shape[0]):
        r = m[i]
        if tr[i] > 0:
            s = np.sqrt(tr[i] + 1.0) * 2
            q[i] = [0.25 * s, (r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s]
        elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
            s = np.sqrt(1.0 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
            q[i] = [(r[2, 1] - r[1, 2]) / s, 0.25 * s, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s]
        elif r[1, 1] > r[2, 2]:
            s = np.sqrt(1.0 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
            q[i] = [(r[0, 2] - r[2, 0]) / s, (r[0, 1] + r[1, 0]) / s, 0.25 * s, (r[1, 2] + r[2, 1]) / s]
        else:
            s = np.sqrt(1.0 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
            q[i] = [(r[1, 0] - r[0, 1]) / s, (r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, 0.25 * s]
    return normalize(q).reshape(shape + (4,))


def to_matrix(q: np.ndarray) -> np.ndarray:
    q = normalize(q)
    w, x, y, z = np.moveaxis(q, -1, 0)
    return np.stack(
        [
            np.stack([1 - 2 * (y * y + z * z), 2 * (x * y - w * z), 2 * (x * z + w * y)], -1),
            np.stack([2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)], -1),
            np.stack([2 * (x * z - w * y), 2 * (y * z + w * x), 1 - 2 * (x * x + y * y)], -1),
        ],
        axis=-2,
    )


_AXES = {"X": np.array([1.0, 0, 0]), "Y": np.array([0, 1.0, 0]), "Z": np.array([0, 0, 1.0])}


def from_euler(angles_deg: np.ndarray, order: str = "ZXY") -> np.ndarray:
    """Intrinsic Euler (BVH convention): R = R_order[0] * R_order[1] * R_order[2]."""
    angles = np.radians(np.asarray(angles_deg, dtype=float))
    q = identity(angles.shape[:-1])
    for i, ax in enumerate(order):
        q = mul(q, from_axis_angle(np.broadcast_to(_AXES[ax], angles.shape[:-1] + (3,)), angles[..., i]))
    return q


def to_euler(q: np.ndarray, order: str = "ZXY") -> np.ndarray:
    """Inverse of from_euler for any Tait-Bryan order. Returns degrees, (...,3) in `order`."""
    m = to_matrix(q)
    idx = {"X": 0, "Y": 1, "Z": 2}
    i, j, k = (idx[a] for a in order)
    # sign of the permutation (i,j,k)
    sign = 1.0 if (j - i) % 3 == 1 else -1.0
    sy = np.clip(sign * m[..., i, k], -1.0, 1.0)
    b = np.arcsin(sy)
    a = np.arctan2(-sign * m[..., j, k], m[..., k, k])
    c = np.arctan2(-sign * m[..., i, j], m[..., i, i])
    # gimbal lock: put everything into the first angle
    lock = np.abs(sy) > 0.999999
    if np.any(lock):
        a_l = np.arctan2(sign * m[..., k, j], m[..., j, j])
        a = np.where(lock, a_l, a)
        c = np.where(lock, 0.0, c)
    return np.degrees(np.stack([a, b, c], axis=-1))


def make_continuous(q: np.ndarray, axis: int = 0) -> np.ndarray:
    """Flip signs along time so consecutive quaternions are in the same hemisphere."""
    q = np.array(q, copy=True)
    q = np.moveaxis(q, axis, 0)
    for t in range(1, q.shape[0]):
        d = np.sum(q[t] * q[t - 1], axis=-1, keepdims=True)
        q[t] = np.where(d < 0, -q[t], q[t])
    return np.moveaxis(q, 0, axis)


def slerp(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
    t = np.asarray(t, dtype=float)[..., None]
    d = np.sum(a * b, axis=-1, keepdims=True)
    b = np.where(d < 0, -b, b)
    d = np.abs(d)
    theta = np.arccos(np.clip(d, -1.0, 1.0))
    s = np.sin(theta)
    small = s < 1e-6
    wa = np.where(small, 1.0 - t, np.sin((1.0 - t) * theta) / np.where(small, 1.0, s))
    wb = np.where(small, t, np.sin(t * theta) / np.where(small, 1.0, s))
    return normalize(wa * a + wb * b)


def between(u: np.ndarray, v: np.ndarray) -> np.ndarray:
    """Shortest-arc rotation taking direction u to direction v."""
    u = u / np.linalg.norm(u, axis=-1, keepdims=True)
    v = v / np.linalg.norm(v, axis=-1, keepdims=True)
    c = np.cross(u, v)
    d = np.sum(u * v, axis=-1, keepdims=True)
    q = np.concatenate([1.0 + d, c], axis=-1)
    # antiparallel case: any orthogonal axis
    anti = (1.0 + d[..., 0]) < 1e-8
    if np.any(anti):
        ortho = np.cross(u, np.array([1.0, 0, 0]))
        bad = np.linalg.norm(ortho, axis=-1) < 1e-6
        ortho = np.where(bad[..., None], np.cross(u, np.array([0, 1.0, 0])), ortho)
        q = np.where(anti[..., None], np.concatenate([np.zeros_like(d), ortho], axis=-1), q)
    return normalize(q)
