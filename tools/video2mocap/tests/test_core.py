import numpy as np
import pytest

from video2mocap import quat
from video2mocap.io.bvh import read_bvh, write_bvh
from video2mocap.motion import Motion
from video2mocap.pipeline import postprocess
from video2mocap.process.edit import apply_edits
from video2mocap.process.filters import smooth_motion
from video2mocap.process.ik import two_bone_ik
from video2mocap.qa.metrics import foot_skate, jitter
from video2mocap.qa.review import select_keyframes
from video2mocap.rigs import TEST_HUMANOID_PROFILE

from synth import add_noise, stand, walk

RNG = np.random.default_rng(42)


@pytest.mark.parametrize("order", ["XYZ", "XZY", "YXZ", "YZX", "ZXY", "ZYX"])
def test_euler_roundtrip(order):
    q = quat.normalize(RNG.standard_normal((500, 4)))
    e = quat.to_euler(q, order)
    q2 = quat.from_euler(e, order)
    assert np.allclose(np.abs(np.sum(q * q2, -1)), 1.0, atol=1e-6)


def test_matrix_and_rotvec_roundtrip():
    q = quat.normalize(RNG.standard_normal((500, 4)))
    assert np.allclose(np.abs(np.sum(q * quat.from_matrix(quat.to_matrix(q)), -1)), 1.0, atol=1e-8)
    assert np.allclose(np.abs(np.sum(q * quat.from_rotvec(quat.to_rotvec(q)), -1)), 1.0, atol=1e-8)


def test_bvh_roundtrip(tmp_path):
    m = add_noise(walk(), rot_deg=20)
    write_bvh(m, tmp_path / "a.bvh")
    m2 = read_bvh(tmp_path / "a.bvh")
    p1, _ = m.fk()
    p2, _ = m2.fk()
    assert sorted(m2.skeleton.names) == sorted(m.skeleton.names)
    idx = [m2.skeleton.index(n) for n in m.skeleton.names]  # BVH stores joints depth-first
    assert np.abs(p1 - p2[:, idx]).max() < 1e-5
    assert m2.fps == pytest.approx(m.fps)


def test_save_load(tmp_path):
    m = walk()
    m.contacts = {"LeftToeBase": np.arange(m.num_frames) % 2 == 0}
    m.meta = {"source": "unit"}
    m.save(tmp_path / "m.npz")
    m2 = Motion.load(tmp_path / "m.npz")
    assert np.allclose(m2.local_rot, m.local_rot) and np.allclose(m2.root_pos, m.root_pos)
    assert (m2.contacts["LeftToeBase"] == m.contacts["LeftToeBase"]).all()
    assert m2.meta == m.meta


def test_two_bone_ik_reaches_target_and_keeps_foot():
    m = walk()
    sk = m.skeleton
    a, b, c = sk.index("LeftUpLeg"), sk.index("LeftLeg"), sk.index("LeftFoot")
    gpos, grot = m.fk()
    target = gpos[:, c] + np.array([0.05, 0.08, -0.04])
    two_bone_ik(m, (a, b, c), target, np.ones(m.num_frames))
    gpos2, grot2 = m.fk()
    assert np.linalg.norm(gpos2[:, c] - target, axis=-1).max() < 1e-3
    assert np.allclose(np.abs(np.sum(grot2[:, c] * grot[:, c], -1)), 1.0, atol=1e-6)
    # bone lengths unchanged by construction
    assert np.allclose(np.linalg.norm(gpos2[:, b] - gpos2[:, a], axis=-1), 0.42, atol=1e-9)


def test_smoothing_removes_noise_but_keeps_motion():
    clean = walk()
    noisy = add_noise(clean, rot_deg=3, pos_m=0.01)
    sm = smooth_motion(noisy)
    pc, _ = clean.fk()
    pn, _ = noisy.fk()
    ps, _ = sm.fk()
    assert jitter(sm) < 0.2 * jitter(noisy)
    # white noise inside the motion band cannot be removed without removing motion; demand improvement
    assert np.abs(ps - pc).mean() < 0.8 * np.abs(pn - pc).mean()


def test_smoothing_preserves_clean_motion():
    """Faithfulness: a clean motion must come out of the filter essentially unchanged."""
    clean = walk()
    pc, _ = clean.fk()
    ps, _ = smooth_motion(clean).fk()
    assert np.abs(ps - pc).max() < 0.015  # < 1.5 cm anywhere, even at the synthetic heel strikes
    assert np.abs(ps - pc).mean() < 0.002


def test_postprocess_kills_foot_skate_when_standing():
    raw = add_noise(stand(), rot_deg=1.0, pos_m=0.01, seed=3)
    # slow drift, the classic video-mocap skate
    raw.root_pos[:, 0] += np.linspace(0, 0.15, raw.num_frames)
    out, metrics = postprocess(raw, TEST_HUMANOID_PROFILE)
    assert all(v.mean() > 0.9 for v in out.contacts.values())
    assert metrics["final"]["foot_skate_cm_s_mean"] < 0.5
    assert metrics["final"]["foot_skate_cm_s_mean"] < 0.1 * metrics["raw"]["foot_skate_cm_s_mean"]


def test_postprocess_walk_has_alternating_contacts_and_low_skate():
    clean = walk(seconds=5)
    gt = clean.copy()
    gt.contacts = {}
    raw = add_noise(clean, rot_deg=1.0, pos_m=0.005, seed=7)
    out, metrics = postprocess(raw, TEST_HUMANOID_PROFILE)
    left, right = out.contacts["LeftToeBase"], out.contacts["RightToeBase"]
    assert 0.2 < left.mean() < 0.8 and 0.2 < right.mean() < 0.8
    assert metrics["final"]["foot_skate_cm_s_mean"] < metrics["before_foot_lock"]["foot_skate_cm_s_mean"]
    assert metrics["final"]["foot_skate_cm_s_mean"] < 2.0
    # the walk still travels: foot lock must not freeze the character
    assert out.root_pos[-1, 2] - out.root_pos[0, 2] > 4.5
    # faithfulness: post-processed motion stays close to ground truth
    pg, _ = clean.fk()
    po, _ = out.fk()
    assert np.abs(po - pg).mean() < 0.02


def test_edits_with_falloff():
    m = walk()
    j = m.skeleton.index("LeftForeArm")
    out = apply_edits(m, [{"op": "rotate", "joint": "LeftForeArm", "frames": [40, 50], "euler_deg": [0, 0, 30],
                           "falloff": 5}])
    d = np.abs(np.sum(out.local_rot[:, j] * m.local_rot[:, j], -1))
    assert np.allclose(d[:34], 1.0) and np.allclose(d[56:], 1.0)
    ang = np.degrees(2 * np.arccos(np.clip(d, -1, 1)))
    assert np.allclose(ang[40:51], 30.0, atol=1e-4)
    assert 0 < ang[37] < 30
    out2 = apply_edits(out, [{"op": "trim", "frames": [10, 59]}])
    assert out2.num_frames == 50


def test_keyframes():
    m = walk(seconds=10)
    ks = select_keyframes(m, max_frames=20)
    assert ks[0] == 0 and ks[-1] == m.num_frames - 1
    assert ks == sorted(ks)
    assert max(np.diff(ks)) <= 2 * m.num_frames // 20


def test_foot_skate_metric_zero_for_static():
    m = stand()
    m.contacts = {"LeftToeBase": np.ones(m.num_frames, bool)}
    assert foot_skate(m)["LeftToeBase"] == pytest.approx(0.0, abs=1e-9)
