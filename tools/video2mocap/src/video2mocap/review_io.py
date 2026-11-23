"""Load what a review sheet needs from a track folder: video frames, camera and 2D keypoints."""
from __future__ import annotations

from pathlib import Path

import numpy as np

from .qa.review import Camera


def read_frames(video: str | Path, frames: list[int]) -> dict[int, np.ndarray]:
    import imageio.v3 as iio

    wanted = set(frames)
    out: dict[int, np.ndarray] = {}
    for i, img in enumerate(iio.imiter(str(video), plugin="pyav")):
        if i in wanted:
            out[i] = img
        if len(out) == len(wanted):
            break
    return out


def load_review_inputs(track_dir: str | Path, frames: list[int]):
    """Frames are indices into the track's own clip (track_dir/clip.mp4), like the motion."""
    from .backends.gemx import load_track

    track_dir = Path(track_dir)
    _, cam, kp2d = load_track(track_dir)
    clip = track_dir / "clip.mp4"
    video = read_frames(clip, frames) if clip.exists() else None
    return video, cam, kp2d
