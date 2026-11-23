"""Review material for a human or an AI reviewer (e.g. Claude reading images).

The estimator runs on EVERY frame (temporal models need dense input and it is what keeps motion
faithful). Key frames are only used for review: we pick the frames where mistakes are most likely or
most visible - extreme poses (local minima of pose speed), low estimator confidence, high
reprojection error - and render them side by side with the video so the reviewer can write edits.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ..motion import Motion


@dataclass
class Camera:
    """World -> camera per frame. x_cam = R @ x_world + t ; pixel = K @ x_cam."""

    K: np.ndarray  # (T,3,3)
    R: np.ndarray  # (T,3,3)
    t: np.ndarray  # (T,3)

    def project(self, pts_world: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        """(T,J,3) -> uv (T,J,2), depth (T,J)."""
        pc = np.einsum("tij,tkj->tki", self.R, pts_world) + self.t[:, None]
        pix = np.einsum("tij,tkj->tki", self.K, pc)
        z = pc[..., 2]
        return pix[..., :2] / np.maximum(pix[..., 2:3], 1e-6), z

    def save(self, path: str | Path) -> None:
        np.savez_compressed(path, K=self.K, R=self.R, t=self.t)

    @classmethod
    def load(cls, path: str | Path) -> "Camera":
        d = np.load(path)
        return cls(d["K"], d["R"], d["t"])


def select_keyframes(motion: Motion, max_frames: int = 24, min_spacing: int | None = None,
                     extra_scores: np.ndarray | None = None) -> list[int]:
    """Frames worth reviewing. extra_scores (T,) higher = more suspicious (e.g. reprojection error)."""
    T = motion.num_frames
    if T <= max_frames:
        return list(range(T))
    min_spacing = min_spacing or max(2, T // (max_frames * 2))
    gpos, _ = motion.fk()
    speed = np.zeros(T)
    speed[1:] = np.linalg.norm(np.diff(gpos, axis=0), axis=-1).sum(-1)
    speed[0] = speed[1]
    # extreme poses: local minima of speed (the "key poses" an animator would key)
    k = 3
    pad = np.pad(speed, k, mode="edge")
    is_min = np.array([speed[t] <= pad[t : t + 2 * k + 1].min() for t in range(T)])
    score = np.where(is_min, 1.0, 0.0)
    if motion.confidence is not None:
        score += 1.0 - motion.confidence.mean(axis=1)
    if extra_scores is not None:
        es = np.nan_to_num(extra_scores)
        if es.max() > 0:
            score += es / es.max()
    chosen = [0, T - 1]
    for t in np.argsort(-score):
        if len(chosen) >= max_frames:
            break
        if all(abs(t - c) >= min_spacing for c in chosen):
            chosen.append(int(t))
    # guarantee coverage: no gap larger than 2*T/max_frames
    chosen = sorted(set(chosen))
    max_gap = max(1, 2 * T // max_frames)
    filled = [chosen[0]]
    for c in chosen[1:]:
        while c - filled[-1] > max_gap:
            filled.append(filled[-1] + max_gap)
        filled.append(c)
    return filled


def _bones(motion: Motion) -> list[tuple[int, int]]:
    return [(int(p), j) for j, p in enumerate(motion.skeleton.parents) if p >= 0]


def render_contact_sheet(motion: Motion, frames: list[int], out_path: str | Path,
                         video_frames: dict[int, np.ndarray] | None = None, camera: Camera | None = None,
                         kp2d: np.ndarray | None = None, cols: int = 4, title: str = "") -> Path:
    """One tile per frame: [video + projected skeleton (if available)] | front view | side view.
    Bones: left side blue, right side red, centre grey. Contact joints are drawn as green squares."""
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    gpos, _ = motion.fk()
    names = [n.lower() for n in motion.skeleton.names]
    side = ["l" if ("left" in n or n.startswith("l_") or n.endswith("_l")) else
            "r" if ("right" in n or n.startswith("r_") or n.endswith("_r")) else "c" for n in names]
    color = {"l": "#2f6fd6", "r": "#d63a2f", "c": "#777777"}
    bones = _bones(motion)
    has_video = video_frames is not None and camera is not None
    panels = 3 if has_video else 2
    rows = int(np.ceil(len(frames) / cols))
    fig, axes = plt.subplots(rows, cols * panels, figsize=(cols * panels * 2.6, rows * 2.9), squeeze=False)
    uv = camera.project(gpos)[0] if camera is not None else None
    lo, hi = gpos.reshape(-1, 3).min(0), gpos.reshape(-1, 3).max(0)
    for i, f in enumerate(frames):
        r, c0 = divmod(i, cols)
        c0 *= panels
        p = gpos[f]
        contact_idx = [motion.skeleton.index(n) for n, m in motion.contacts.items() if m[f]]
        if has_video:
            ax = axes[r, c0]
            img = video_frames.get(f)
            if img is not None:
                ax.imshow(img)
            for a, b in bones:
                ax.plot(uv[f, [a, b], 0], uv[f, [a, b], 1], color=color[side[b]], lw=1.2)
            if kp2d is not None:
                ok = kp2d[f, :, 2] > 0.5
                ax.scatter(kp2d[f, ok, 0], kp2d[f, ok, 1], s=3, c="yellow")
            ax.set_title(f"f{f} video", fontsize=7)
            ax.axis("off")
        for k, (ax_i, ax_j, label) in enumerate([(0, 1, "front X/Y"), (2, 1, "side Z/Y")]):
            ax = axes[r, c0 + (1 if has_video else 0) + k]
            centre = p[0]
            for a, b in bones:
                ax.plot(p[[a, b], ax_i] - centre[ax_i], p[[a, b], ax_j], color=color[side[b]], lw=1.4)
            for j in contact_idx:
                ax.scatter(p[j, ax_i] - centre[ax_i], p[j, ax_j], marker="s", s=14, c="#1aa34a")
            ax.axhline(0.0, color="#bbbbbb", lw=0.6)
            ax.set_xlim(-1.0, 1.0)
            ax.set_ylim(min(lo[1], -0.05), max(hi[1], 1.9))
            ax.set_aspect("equal")
            ax.set_title(f"f{f} {label}", fontsize=7)
            ax.tick_params(labelsize=5)
    for ax in axes.flat[len(frames) * panels:]:
        ax.axis("off")
    if title:
        fig.suptitle(title, fontsize=9)
    fig.tight_layout()
    out_path = Path(out_path)
    fig.savefig(out_path, dpi=110)
    plt.close(fig)
    return out_path
