"""Tracking utilities shared by backends (pure numpy)."""
from __future__ import annotations

import numpy as np


def stitch_tracks(seen: dict[int, dict[int, np.ndarray]], max_gap: int, max_center_dist: float = 1.0,
                  max_size_ratio: float = 1.6) -> dict[int, dict[int, np.ndarray]]:
    """Re-join fragments of the same person. ByteTrack starts a new id whenever a person is lost for a
    few frames (small, occluded, motion blur); a single walker can come out as 3+ tracks. A fragment B
    is appended to A when B starts after A ends (gap <= max_gap) and B's first box is close to A's
    last box (centre distance < max_center_dist box heights, similar size). Greedy, in time order;
    the closest candidate wins. Overlapping tracks are never merged (two people)."""

    def ends(obs):
        ts = sorted(obs)
        return ts[0], ts[-1]

    def centre_h(b):
        return np.array([(b[0] + b[2]) / 2, (b[1] + b[3]) / 2]), max(b[3] - b[1], 1.0)

    frags = {k: dict(v) for k, v in seen.items()}
    merged = True
    while merged:
        merged = False
        order = sorted(frags, key=lambda k: ends(frags[k])[0])
        for a in order:
            a_end = ends(frags[a])[1]
            best, best_d = None, None
            ca, ha = centre_h(frags[a][a_end])
            for b in order:
                if b == a:
                    continue
                b_start = ends(frags[b])[0]
                gap = b_start - a_end
                if gap <= 0 or gap > max_gap:
                    continue
                cb, hb = centre_h(frags[b][b_start])
                d = np.linalg.norm(ca - cb) / ha
                if d > max_center_dist or max(ha, hb) / min(ha, hb) > max_size_ratio:
                    continue
                if best is None or d < best_d:
                    best, best_d = b, d
            if best is not None:
                frags[a].update(frags.pop(best))
                merged = True
                break
    return frags
