import numpy as np

from video2mocap.tracking import stitch_tracks


def box(cx, cy, h=200.0):
    return np.array([cx - h / 4, cy - h / 2, cx + h / 4, cy + h / 2], dtype=np.float32)


def test_fragments_of_one_walker_are_joined():
    # one person walking right, lost twice (ids 0, 2, 4 like ByteTrack produces)
    seen = {0: {t: box(100 + 3 * t, 400) for t in range(0, 66)},
            2: {t: box(100 + 3 * t, 400) for t in range(80, 140)},
            4: {t: box(100 + 3 * t, 400) for t in range(150, 200)}}
    out = stitch_tracks(seen, max_gap=90)
    assert len(out) == 1
    assert sorted(next(iter(out.values()))) == list(range(0, 66)) + list(range(80, 140)) + list(range(150, 200))


def test_two_people_side_by_side_stay_separate():
    seen = {0: {t: box(200, 400) for t in range(0, 100)},
            1: {t: box(700, 400) for t in range(0, 100)}}
    assert len(stitch_tracks(seen, max_gap=90)) == 2


def test_far_away_fragment_is_not_joined():
    seen = {0: {t: box(100, 400) for t in range(0, 50)},
            1: {t: box(900, 400) for t in range(60, 100)}}
    assert len(stitch_tracks(seen, max_gap=90)) == 2


def test_gap_too_long_is_not_joined():
    seen = {0: {t: box(100, 400) for t in range(0, 50)},
            1: {t: box(110, 400) for t in range(300, 350)}}
    assert len(stitch_tracks(seen, max_gap=90)) == 2
