"""End-to-end: video -> per-person clean motions, review sheets and exports."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import numpy as np

from . import quat
from .io.bvh import write_bvh
from .motion import Motion
from .pipeline import postprocess
from .qa.review import Camera, render_contact_sheet, select_keyframes
from .rigs import PROFILES

REPO = Path(__file__).resolve().parents[2]


def to_wsl_path(p: Path) -> str:
    p = Path(p).resolve()
    drive = p.drive.rstrip(":").lower()
    return f"/mnt/{drive}" + p.as_posix()[2:]


def run_backend_gemx(video: Path, out: Path, static_cam: bool, max_people: int, extra: list[str]) -> None:
    args = [to_wsl_path(video), to_wsl_path(out), "--max_people", str(max_people), *extra]
    if static_cam:
        args.append("--static_cam")
    if sys.platform == "win32":
        cmd = ["wsl", "-d", "Ubuntu", "--exec", "bash", to_wsl_path(REPO / "backends/gemx/run_wsl.sh"), *args]
    else:
        cmd = ["bash", str(REPO / "backends/gemx/run_wsl.sh"), str(video), str(out), *args[2:]]
    subprocess.run(cmd, check=True)


def shared_world(cams: list[Camera]) -> list[tuple[np.ndarray, np.ndarray]]:
    """Static camera: express every track in track 0's world. X_cam = R_i X_i + t_i, so
    X_0 = R_0^T (R_i X_i + t_i - t_0). The rotation is projected onto a yaw (both worlds are
    gravity-aligned, Y-up), so people never get tilted by noise in the camera estimate."""
    def mean_rt(c: Camera):
        q = quat.make_continuous(quat.from_matrix(c.R))
        R = quat.to_matrix(quat.normalize(q.mean(axis=0)))
        return R, np.median(c.t, axis=0)

    R0, t0 = mean_rt(cams[0])
    out = []
    for c in cams:
        Ri, ti = mean_rt(c)
        M = R0.T @ Ri
        yaw = np.arctan2(M[0, 2], M[2, 2])
        Myaw = quat.to_matrix(quat.from_axis_angle(np.array([0, 1.0, 0]), yaw))
        out.append((Myaw, R0.T @ (ti - t0)))
    return out


def apply_rigid(m: Motion, M: np.ndarray, b: np.ndarray) -> Motion:
    out = m.copy()
    out.root_pos = m.root_pos @ M.T + b
    mq = quat.from_matrix(M)
    r0 = m.skeleton.rest_rot[0]
    out.local_rot[:, 0] = quat.normalize(quat.mul(quat.mul(quat.conj(r0), quat.mul(mq, r0)), m.local_rot[:, 0]))
    return out


def camera_for(motion: Motion, cam: Camera) -> Camera:
    """Camera for a motion that went through rigid shifts after estimation (ground placement):
    x_cam = R (x - shift) + t  ->  t' = t - R shift."""
    shift = np.zeros(3)
    for h in motion.meta.get("history", []):
        if h.get("op") == "place_on_ground":
            shift += np.asarray(h["shift"], float)
    return Camera(cam.K, cam.R, cam.t - np.einsum("tij,j->ti", cam.R, shift))


def reprojection_px(motion: Motion, cam: Camera, kp2d: np.ndarray, conf_thr: float = 0.5) -> float:
    """Mean 2D error (px) between the motion's joints and the detected keypoints (same SOMA-77 order)."""
    gpos, _ = motion.fk()
    if kp2d.shape[1] != gpos.shape[1]:
        return float("nan")
    uv, z = cam.project(gpos)
    ok = (kp2d[..., 2] > conf_thr) & (z > 0)
    return float(np.linalg.norm(uv - kp2d[..., :2], axis=-1)[ok].mean()) if ok.any() else float("nan")


def run_video(video: str, out: str, static_cam: bool = True, max_people: int = 8, backend: str = "gemx",
              extra: list[str] | None = None, fbx: bool = False, glb: bool = False) -> dict:
    if backend != "gemx":
        raise ValueError(f"unknown backend {backend}")
    from .backends.gemx import load_track

    video_p, out_p = Path(video).resolve(), Path(out).resolve()
    out_p.mkdir(parents=True, exist_ok=True)
    if not (out_p / "run.json").exists():
        run_backend_gemx(video_p, out_p, static_cam, max_people, extra or [])
    run = json.loads((out_p / "run.json").read_text())
    rig = PROFILES["soma77"]

    raws, cams, kps = [], [], []
    for tr in run["tracks"]:
        m, cam, kp = load_track(out_p / tr["dir"])
        raws.append(m), cams.append(cam), kps.append(kp)
    placements = shared_world(cams) if static_cam and len(raws) > 1 else [(np.eye(3), np.zeros(3))] * len(raws)

    summary = {"tracks": []}
    for tr, raw, cam, kp, (M, b) in zip(run["tracks"], raws, cams, kps, placements):
        tdir = out_p / tr["dir"]
        clean, metrics = postprocess(apply_rigid(raw, M, b), rig)
        clean.meta["shared_world"] = {"M": M.tolist(), "b": b.tolist()}
        clean.save(tdir / "clean.npz")
        (tdir / "metrics.json").write_text(json.dumps(metrics, indent=2))
        write_bvh(clean, tdir / "clean.bvh")
        if fbx:
            from .blender import bvh_to_fbx

            bvh_to_fbx(str(tdir / "clean.bvh"), str(tdir / "clean.fbx"), fps=clean.fps)
        if glb:
            from .blender import bvh_to_glb

            bvh_to_glb(str(tdir / "clean.bvh"), str(tdir / "clean.glb"), fps=clean.fps)
        # review sheet + reprojection in the track's own world (the camera belongs to that world)
        review_m, _ = postprocess(raw, rig)
        review_cam = camera_for(review_m, cam)
        metrics["raw"]["reproj_px"] = reprojection_px(raw, cam, kp)
        metrics["final"]["reproj_px"] = reprojection_px(review_m, review_cam, kp)
        (tdir / "metrics.json").write_text(json.dumps(metrics, indent=2))
        frames = select_keyframes(review_m, max_frames=12)
        try:
            from .review_io import read_frames

            vf = read_frames(tdir / "clip.mp4", frames)
        except Exception as e:  # video reading is optional
            print(f"[v2m] review without video frames: {e}")
            vf = None
        render_contact_sheet(review_m, frames, tdir / "review.png", vf, review_cam, kp,
                             title=f"{video_p.name} {tr['dir']} (src f{tr['start']}-{tr['end']})")
        summary["tracks"].append({"dir": tr["dir"], "start": tr["start"], "end": tr["end"],
                                  "final": metrics["final"], "raw": metrics["raw"]})
        print(f"[v2m] {tr['dir']}: reproj {metrics['raw']['reproj_px']:.1f} -> {metrics['final']['reproj_px']:.1f} px, skate {metrics['raw']['foot_skate_cm_s_mean']:.1f} -> "
              f"{metrics['final']['foot_skate_cm_s_mean']:.2f} cm/s, jitter {metrics['raw']['jitter_m_s3']:.1f} -> "
              f"{metrics['final']['jitter_m_s3']:.1f}")
    (out_p / "summary.json").write_text(json.dumps(summary, indent=2))
    return summary
