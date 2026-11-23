import numpy as np

from video2mocap import quat
from video2mocap.face.attach import resample_take
from video2mocap.face.capture import FaceTake, _apply_frame_rotation, _fill_gaps, _iter_frames
from video2mocap.face.sync import ENV_HZ, detect_clap, offset_by_audio


def _env_with_clap(seconds, clap_s, seed):
    rng = np.random.default_rng(seed)
    e = 0.01 + 0.002 * rng.random(int(seconds * ENV_HZ))
    k = int(clap_s * ENV_HZ)
    e[k:k + 6] = [0.9, 0.6, 0.3, 0.15, 0.08, 0.04]
    return e


def test_clap_detection_and_offset():
    a, b = _env_with_clap(8, 1.25, 0), _env_with_clap(8, 2.40, 1)
    assert abs(detect_clap(a) - 1.25) < 0.011 and abs(detect_clap(b) - 2.40) < 0.011


def test_audio_cross_correlation_offset():
    rng = np.random.default_rng(3)
    speech = np.abs(np.convolve(rng.standard_normal(20 * ENV_HZ), np.ones(20) / 20, "same")) + 0.01
    a = speech[200:200 + 10 * ENV_HZ]
    b = speech[200 + int(1.3 * ENV_HZ):200 + int(1.3 * ENV_HZ) + 10 * ENV_HZ]  # B starts 1.3 s later
    off, conf = offset_by_audio(a, b)
    assert abs(off - (-1.3)) < 0.01 and conf > 0.5  # t_B = t_A - 1.3


def test_gap_fill_and_resample():
    T, K = 30, 52
    C = np.tile(np.linspace(0, 1, T)[:, None], (1, K))
    R = quat.identity((T,))
    valid = np.ones(T, bool)
    valid[10:13] = False
    C[10:13] = np.nan
    R[10:13] = np.nan
    C2, R2 = _fill_gaps(C, R, valid, max_gap=5)
    assert np.allclose(C2[10:13, 0], np.linspace(0, 1, T)[10:13])
    take = FaceTake(30.0, [f"b{k}" for k in range(K)], C2, R2, valid)
    curves, rot, ok = resample_take(take, np.array([0.5, 0.5 + 1 / 60, 5.0]))
    assert np.isclose(curves[0, 0], C2[15, 0]) and np.isclose(curves[1, 0], (C2[15, 0] + C2[16, 0]) / 2)
    assert ok[0] and not ok[2] and curves[2].sum() == 0


def test_apply_frame_rotation_all_orientations():
    # 2x3 image with unique marker values per corner
    img = np.zeros((2, 3, 3), dtype=np.uint8)
    img[0, 0] = [10, 0, 0]  # top-left
    img[0, 2] = [20, 0, 0]  # top-right
    img[1, 0] = [30, 0, 0]  # bottom-left
    img[1, 2] = [40, 0, 0]  # bottom-right

    out_0 = _apply_frame_rotation(img, 0)
    assert out_0 is img

    # 90 CCW: top-right moves to top-left; shape (2,3) -> (3,2)
    out_90 = _apply_frame_rotation(img, 90)
    assert out_90.shape == (3, 2, 3) and out_90.flags["C_CONTIGUOUS"]
    assert np.array_equal(out_90[0, 0], [20, 0, 0])
    assert np.array_equal(out_90[2, 0], [10, 0, 0])

    # -90 and 270 (90 CW): bottom-left moves to top-left; shape (2,3) -> (3,2)
    for deg in (-90, 270):
        out_cw = _apply_frame_rotation(img, deg)
        assert out_cw.shape == (3, 2, 3) and out_cw.flags["C_CONTIGUOUS"]
        assert np.array_equal(out_cw[0, 0], [30, 0, 0])
        assert np.array_equal(out_cw[0, 1], [10, 0, 0])

    # 180 and -180: bottom-right moves to top-left; shape (2,3) -> (2,3)
    for deg in (180, -180):
        out_180 = _apply_frame_rotation(img, deg)
        assert out_180.shape == (2, 3, 3) and out_180.flags["C_CONTIGUOUS"]
        assert np.array_equal(out_180[0, 0], [40, 0, 0])
        assert np.array_equal(out_180[1, 2], [10, 0, 0])


def test_iter_frames_applies_display_matrix_rotation(tmp_path):
    import av

    mp4_path = tmp_path / "rotated_90.mp4"
    with av.open(str(mp4_path), mode="w") as out:
        s = out.add_stream("mpeg4", rate=30)
        s.width, s.height = 64, 32
        s.pix_fmt = "yuv420p"
        s.set_display_rotation(90)
        raw = np.zeros((32, 64, 3), dtype=np.uint8)
        raw[:, 32:] = [255, 255, 255]  # right half bright -> after 90 CCW, top half bright
        fr = av.VideoFrame.from_ndarray(raw, format="rgb24")
        for pkt in s.encode(fr):
            out.mux(pkt)
        for pkt in s.encode():
            out.mux(pkt)

    decoded = list(_iter_frames(mp4_path))
    assert len(decoded) == 1
    _fps, rgb = decoded[0]
    assert rgb.shape == (64, 32, 3) and rgb.flags["C_CONTIGUOUS"]
    assert rgb[:28].mean() > 200 and rgb[36:].mean() < 55
