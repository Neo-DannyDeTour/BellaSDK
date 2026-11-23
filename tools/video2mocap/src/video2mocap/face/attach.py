"""Merge a face take onto one person of a body run.

Body gives the head's overall orientation (it must agree with the neck and torso); the face take
gives the expression curves and the small head motion on top of it (relative to the take's own
neutral head pose), so a face recorded sitting at a desk still fits a body that is walking.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np

from .. import quat
from .capture import FaceTake


def resample_take(take: FaceTake, times_s: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Curves, head rotations and validity at arbitrary times (seconds into the face take)."""
    t_src = np.arange(take.num_frames) / take.fps
    inside = (times_s >= 0) & (times_s <= t_src[-1])
    x = np.clip(times_s, 0, t_src[-1])
    curves = np.stack([np.interp(x, t_src, take.curves[:, k]) for k in range(take.curves.shape[1])], axis=1)
    curves[~inside] = 0.0
    i0 = np.clip(np.floor(x * take.fps).astype(int), 0, take.num_frames - 1)
    i1 = np.clip(i0 + 1, 0, take.num_frames - 1)
    w = x * take.fps - i0
    rot = quat.slerp(take.head_rot[i0], take.head_rot[i1], w)
    valid = inside & take.valid[i0]
    return curves, rot, valid


def attach_face(run_dir: str | Path, person: int, take_path: str | Path, offset_s: float = 0.0,
                time_scale: float = 1.0) -> Path:
    """offset_s: t_face = t_body * time_scale + offset_s (t_body in seconds of the body source video).
    time_scale != 1 stretches the face performance if it was acted faster/slower."""
    run_dir = Path(run_dir)
    run = json.loads((run_dir / "run.json").read_text())
    tr = run["tracks"][person]
    tdir = run_dir / tr["dir"]
    take = FaceTake.load(take_path)
    fps = float(run["fps"])
    frames = np.arange(tr["start"], tr["end"] + 1)
    t_face = frames / fps * time_scale + offset_s
    curves, rot, valid = resample_take(take, t_face)
    # head motion relative to the take's neutral pose (median orientation over valid frames)
    ok = take.valid
    neutral = quat.normalize(quat.make_continuous(take.head_rot[ok]).mean(axis=0)) if ok.any() else quat.identity()
    head_add = quat.mul(np.broadcast_to(quat.conj(neutral), rot.shape), rot)
    head_add[~valid] = [1, 0, 0, 0]
    np.savez_compressed(tdir / "face.npz", names=np.array(take.names), curves=curves.astype(np.float32),
                        head_additive=head_add, valid=valid, fps=fps, frame_start=tr["start"],
                        meta=json.dumps({"take": str(take_path), "offset_s": offset_s, "time_scale": time_scale,
                                         **take.meta}))
    with open(tdir / "face_curves.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["frame", *take.names])
        for i, row in enumerate(curves):
            w.writerow([i, *np.round(row, 4)])
    return tdir / "face.npz"
