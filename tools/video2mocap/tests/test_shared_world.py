import numpy as np

from video2mocap import quat
from video2mocap.qa.review import Camera
from video2mocap.run import apply_rigid, shared_world

from synth import walk


def _rot_y(a):
    return quat.to_matrix(quat.from_axis_angle(np.array([0, 1.0, 0]), a))


def test_two_people_same_camera_end_up_in_one_world():
    T = 30
    K = np.tile(np.eye(3), (T, 1, 1))
    # one true world W; the camera sees it with (Rc, tc)
    Rc, tc = _rot_y(0.4), np.array([0.2, -1.0, 6.0])
    # each track has its own arbitrary world: X_i = A_i X_W + c_i (yaw + offset, as GEM-X canonicalises)
    A = [_rot_y(0.0), _rot_y(1.3)]
    c = [np.zeros(3), np.array([3.0, 0.0, -2.0])]
    cams = []
    for Ai, ci in zip(A, c):
        # X_cam = Rc X_W + tc = Rc A_i^T (X_i - c_i) + tc
        Ri = Rc @ Ai.T
        ti = tc - Ri @ ci
        cams.append(Camera(K, np.tile(Ri, (T, 1, 1)), np.tile(ti, (T, 1))))
    person_W = walk(seconds=1)
    person_W.root_pos = person_W.root_pos + np.array([1.0, 0, 0])
    tracks = []
    for Ai, ci in zip(A, c):
        Mi = Ai
        tracks.append(apply_rigid(person_W, Mi, ci))  # the same body expressed in track i's world
    placed = [apply_rigid(m, M, b) for m, (M, b) in zip(tracks, shared_world(cams))]
    p0, _ = placed[0].fk()
    p1, _ = placed[1].fk()
    assert np.abs(p0 - p1).max() < 1e-6
