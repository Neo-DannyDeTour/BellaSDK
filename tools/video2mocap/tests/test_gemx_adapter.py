import numpy as np
import pytest

from video2mocap import quat
from video2mocap.backends.gemx import axis_to_y, load_track

from synth import walk


@pytest.mark.parametrize("axis", [0, 1, 2])
@pytest.mark.parametrize("sign", [1, -1])
def test_axis_to_y(axis, sign):
    C = axis_to_y(axis, sign)
    v = np.zeros(3)
    v[axis] = sign
    assert np.allclose(C @ v, [0, 1, 0])
    assert np.isclose(np.linalg.det(C), 1.0)


def _fake_track(tmp_path, C_world):
    """Write a motion_raw.npz as the WSL runner would, with the world rotated by C_world (Y-up -> other)."""
    m = walk(seconds=1)
    sk = m.skeleton
    bvh_local = m.local_rot.copy()
    cq = quat.from_matrix(C_world)
    bvh_local[:, 0] = quat.mul(cq, bvh_local[:, 0])
    T = m.num_frames
    K = np.tile(np.array([[1000, 0, 640], [0, 1000, 360], [0, 0, 1.0]]), (T, 1, 1))
    R = np.tile(np.eye(3) @ C_world.T, (T, 1, 1))
    t = np.tile([0, 0, 5.0], (T, 1))
    np.savez(tmp_path / "motion_raw.npz", joint_names=np.array(sk.names), parents=sk.parents, offsets=sk.offsets,
             rest_rot=quat.identity((sk.num_joints,)), bvh_local=bvh_local, root_pos=m.root_pos @ C_world.T,
             fps=30.0, frame_start=10, frame_end=10 + T - 1, track_id=3, kp2d=np.zeros((T, 77, 3)), K=K,
             cam_R=R, cam_t=t)
    return m


@pytest.mark.parametrize("C_world", [np.eye(3), axis_to_y(2, 1).T, axis_to_y(0, -1).T])
def test_load_track_restores_y_up_and_camera(tmp_path, C_world):
    ref = _fake_track(tmp_path, C_world)
    m, cam, kp2d = load_track(tmp_path)
    p_ref, _ = ref.fk()
    p, _ = m.fk()
    assert np.abs(p - p_ref).max() < 1e-6
    assert m.meta["frame_start"] == 10 and m.meta["track_id"] == 3
    # camera must see the same pixels before and after the world change
    uv_new, _ = cam.project(p)
    from video2mocap.qa.review import Camera
    raw = np.load(tmp_path / "motion_raw.npz")
    cam_raw = Camera(raw["K"], raw["cam_R"], raw["cam_t"])
    uv_raw, _ = cam_raw.project(p_ref @ C_world.T)
    assert np.abs(uv_new - uv_raw).max() < 1e-6
