"""Convert the GEM-X runner output (track_XX/motion_raw.npz, written in WSL) into a Motion + Camera."""
from __future__ import annotations

from pathlib import Path

import numpy as np

from .. import quat
from ..motion import Motion, Skeleton
from ..qa.review import Camera


def _up_alignment(motion: Motion) -> np.ndarray:
    """Rotation matrix taking the motion's dominant body-up direction (hips -> head) to +Y.
    Only exact axis permutations/sign flips are produced, so the data is never resampled."""
    gpos, _ = motion.fk()
    names = motion.skeleton.names
    head = names.index("Head") if "Head" in names else int(np.argmax(gpos[0, :, 1]))
    up = (gpos[:, head] - gpos[:, 0]).mean(axis=0)
    axis = int(np.argmax(np.abs(up)))
    sign = np.sign(up[axis])
    return axis_to_y(axis, sign)


def axis_to_y(axis: int, sign: float) -> np.ndarray:
    """Proper rotation (det +1) mapping sign * e_axis to +Y."""
    table = {
        (1, 1): np.eye(3),
        (1, -1): np.diag([1.0, -1.0, -1.0]),  # 180 about X
        (2, 1): np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], float),  # -90 about X
        (2, -1): np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float),  # +90 about X
        (0, 1): np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], float),  # +90 about Z
        (0, -1): np.array([[0, 1, 0], [-1, 0, 0], [0, 0, 1]], float),  # -90 about Z
    }
    return table[(axis, int(sign))]


def load_track(track_dir: str | Path) -> tuple[Motion, Camera, np.ndarray]:
    """-> (motion in Y-up metres, world->camera per frame, kp2d (T,77,3) in source-video pixels)."""
    track_dir = Path(track_dir)
    d = np.load(track_dir / "motion_raw.npz", allow_pickle=False)
    rest = np.asarray(d["rest_rot"], float)
    sk = Skeleton([str(n) for n in d["joint_names"]], d["parents"], d["offsets"], rest)
    bvh_local = np.asarray(d["bvh_local"], float)  # = rest * anim
    local = quat.mul(quat.conj(np.broadcast_to(rest, bvh_local.shape)), bvh_local)
    m = Motion(sk, float(d["fps"]), d["root_pos"], local)
    m.meta = {"backend": "gemx", "license": "commercial-ok", "source_dir": str(track_dir),
              "frame_start": int(d["frame_start"]), "frame_end": int(d["frame_end"]),
              "track_id": int(d["track_id"])}

    C = _up_alignment(m)
    cam = Camera(np.asarray(d["K"], float), np.asarray(d["cam_R"], float), np.asarray(d["cam_t"], float))
    if not np.allclose(C, np.eye(3)):
        cq = quat.from_matrix(C)
        m.root_pos = m.root_pos @ C.T
        # new root global = C * rest0 * local0  ->  local0' = rest0^-1 * C * rest0 * local0
        r0 = sk.rest_rot[0]
        m.local_rot[:, 0] = quat.normalize(quat.mul(quat.mul(quat.conj(r0), quat.mul(cq, r0)), m.local_rot[:, 0]))
        cam = Camera(cam.K, cam.R @ C.T[None], cam.t)  # x_cam = R x = (R C^T)(C x)
        m.meta["up_alignment"] = C.tolist()
    return m, cam, np.asarray(d["kp2d"], float)
