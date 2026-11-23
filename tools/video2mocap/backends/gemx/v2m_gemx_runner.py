"""video2mocap runner for NVIDIA GEM-X. Runs INSIDE the GEM-X venv with the GEM-X repo as cwd:

    cd ~/v2m/GEM-X && .venv/bin/python /path/to/v2m_gemx_runner.py --video clip.mp4 --out runs/clip [--static_cam]

Unlike GEM-X's demo (which keeps only the largest person), this tracks EVERY person, runs GEM-X once
per track, and writes one self-contained `track_XX/motion_raw.npz` per person:

  joint_names (J,) parents (J,) offsets (J,3) rest_rot (J,4 wxyz)    per-person SOMA skeleton, metres
  local_rot (T,J,4 wxyz) root_pos (T,3)                               animation in GEM-X world space
  fps, frame_start, frame_end                                         position in the source video
  kp2d (T,77,3)                                                       2D keypoints (x, y, conf), source pixels
  K (T,3,3) cam_R (T,3,3) cam_t (T,3)                                 world->camera, for reprojection/review

It only needs numpy/scipy/torch plus the GEM-X repo. The skeleton/rotation conversion follows
GEM-X's scripts/demo/retarget_utils.py (Apache-2.0) but avoids its soma-retargeter dependency.
"""
from __future__ import annotations

import argparse
import gc
import json
import os
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import torch
from scipy.spatial.transform import Rotation

GEMX = Path.cwd()
sys.path.insert(0, str(GEMX))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))  # video2mocap (pure numpy parts)

from video2mocap.tracking import stitch_tracks  # noqa: E402

os.environ.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")


def _limit_sam3db_batch() -> None:
    """GEM-X extracts SAM-3D-Body (ViT-H) features 16 crops at a time, which does not fit in 8 GB of
    VRAM next to the other models. Results do not depend on the batch size, only speed does."""
    from gem.utils.sam3db_extractor import SAM3DBExtractor

    batch = int(os.environ.get("V2M_SAM_BATCH", "4"))
    original = SAM3DBExtractor.extract_video_features
    if getattr(original, "_v2m_patched", False):
        return

    def patched(self, *args, **kwargs):
        kwargs["batch_size"] = min(kwargs.get("batch_size", batch), batch)
        return original(self, *args, **kwargs)

    patched._v2m_patched = True
    SAM3DBExtractor.extract_video_features = patched


def _free_gpu() -> None:
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()

SOMA_BVH = GEMX / "third_party/soma-retargeter/soma_retargeter/configs/soma/soma_zero_frame0.bvh"


# ----------------------------------------------------------------------------------------- tracking
def track_all(video: str, min_frames: int, max_people: int, cache: Path | None = None
              ) -> tuple[dict[int, dict], int, int, int, float]:
    """Detect + track every person. Raw per-frame detections are checkpointed to `cache` every 50
    frames, so a GPU failure (e.g. another app grabbing the GPU) resumes instead of starting over.
    Detections are cached (not tracker state): on resume, tracking is replayed from frame 0, which
    is cheap and gives exactly the same tracks."""
    import cv2

    from gem.utils.video_io_utils import read_video_np
    from gem.utils.yolox_detector import ByteTracker, YOLOXDetector
    from tqdm import tqdm

    frames = read_video_np(video)
    T, H, W, _ = frames.shape
    fps = cv2.VideoCapture(video).get(cv2.CAP_PROP_FPS) or 30.0
    dets: list = []
    if cache is not None and cache.exists():
        dets = list(np.load(cache, allow_pickle=True)["dets"])
        print(f"[v2m] resuming detection at frame {len(dets)}/{T}")
    det = YOLOXDetector() if len(dets) < T else None
    for i in tqdm(range(len(dets), T), desc="[v2m] detect all", initial=len(dets), total=T):
        boxes, scores = det.detect(frames[i][..., ::-1].copy())
        dets.append((np.asarray(boxes, np.float32), np.asarray(scores, np.float32)))
        if cache is not None and (len(dets) % 50 == 0 or len(dets) == T):
            np.savez(cache, dets=np.array(dets, dtype=object))
    del frames, det
    _free_gpu()

    tracker = ByteTracker()
    seen: dict[int, dict[int, np.ndarray]] = defaultdict(dict)
    for i, (boxes, scores) in enumerate(tqdm(dets, desc="[v2m] track all")):
        for box, tid, _score in tracker.update(boxes, scores):
            seen[int(tid)][i] = np.asarray(box, dtype=np.float32)

    seen = stitch_tracks(seen, max_gap=int(round(3 * fps)))
    tracks = {}
    for tid, obs in seen.items():
        if len(obs) < min_frames:
            continue
        ts = np.array(sorted(obs))
        s, e = int(ts[0]), int(ts[-1])
        boxes = np.stack([obs[t] for t in ts])
        full = np.stack([np.interp(np.arange(s, e + 1), ts, boxes[:, k]) for k in range(4)], axis=1)
        full[:, [0, 2]] = full[:, [0, 2]].clip(0, W - 1)
        full[:, [1, 3]] = full[:, [1, 3]].clip(0, H - 1)
        area = float(((full[:, 2] - full[:, 0]) * (full[:, 3] - full[:, 1])).mean())
        tracks[tid] = {"start": s, "end": e, "bbx_xyxy": full.astype(np.float32), "mean_area": area,
                       "observed": len(obs), "coverage": len(obs) / (e - s + 1)}
    keep = sorted(tracks, key=lambda k: -tracks[k]["mean_area"] * tracks[k]["observed"])[:max_people]
    return {k: tracks[k] for k in keep}, T, W, H, fps


def cut_clip(video: str, start: int, end: int, fps: float, out: Path) -> None:
    """Frame-exact sub-clip [start, end] (re-encoded, near-lossless)."""
    vf = f"select=between(n\\,{start}\\,{end}),setpts=PTS-STARTPTS"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", video, "-vf", vf, "-r", f"{fps}", "-c:v", "libx264",
                    "-crf", "12", "-pix_fmt", "yuv420p", "-an", str(out)], check=True)


# ----------------------------------------------------------------------------------------- GEM-X
def run_gemx_on_track(clip: Path, out_dir: Path, bbx_xyxy: np.ndarray, static_cam: bool, no_imgfeat: bool,
                      ddim: bool) -> dict:
    from gem.utils.geo_transform import get_bbx_xys_from_xyxy
    from gem.utils.kp2d_utils import smooth_bbx_xyxy

    from scripts.demo import demo_soma_onnx as demo

    _limit_sam3db_batch()
    _free_gpu()
    args = SimpleNamespace(video=str(clip), output_root=str(out_dir), static_cam=static_cam, verbose=False,
                           ckpt=None, exp="gem_soma_regression", force_pytorch=False, retarget=False,
                           no_imgfeat=no_imgfeat, ddim=ddim)
    cfg = demo._build_cfg(args)
    bbx = smooth_bbx_xyxy(torch.from_numpy(bbx_xyxy).float(), window=5)
    bbx_xys = get_bbx_xys_from_xyxy(bbx, base_enlarge=1.2).float()
    Path(cfg.paths.bbx).parent.mkdir(parents=True, exist_ok=True)
    if not Path(cfg.paths.bbx).exists():  # our multi-person boxes: GEM-X then skips its own detection
        torch.save({"bbx_xyxy": bbx, "bbx_xys": bbx_xys}, cfg.paths.bbx)
    demo.run_preprocess_fast(cfg, force_pytorch=False, no_imgfeat=no_imgfeat)
    data = demo.load_data_dict(cfg, no_imgfeat=no_imgfeat)
    if not Path(cfg.paths.hpe_results).exists():
        pred = demo.run_inference_fast(cfg, data, force_pytorch=False, no_imgfeat=no_imgfeat, use_ddim=ddim)
        torch.save(pred, cfg.paths.hpe_results)
    pred = torch.load(cfg.paths.hpe_results, weights_only=False)
    vitpose = torch.load(cfg.paths.vitpose, weights_only=False)
    return {"pred": pred, "vitpose": vitpose[0] if isinstance(vitpose, tuple) else vitpose}


# ----------------------------------------------------------------------------------------- SOMA
def _bvh_hierarchy(path: Path) -> tuple[list[str], list[int]]:
    names, parents, stack, pending_end = [], [], [], False
    toks = path.read_text().split()
    i = 0
    while toks[i] != "MOTION":
        t = toks[i]
        if t in ("ROOT", "JOINT"):
            names.append(toks[i + 1])
            parents.append(stack[-1] if stack else -1)
            i += 2
        elif t == "End":
            pending_end = True
            i += 2
        elif t == "{":
            stack.append(-2 if pending_end else len(names) - 1)
            pending_end = False
            i += 1
        elif t == "}":
            stack.pop()
            i += 1
        else:
            i += 1
    return names, parents


def _np(x):
    return x.detach().cpu().numpy() if isinstance(x, torch.Tensor) else np.asarray(x)


def soma_motion(body_params: dict) -> dict:
    """GEM-X SOMA params -> per-person skeleton + local rotations (Hips becomes the root)."""
    from soma.assets import get_assets_dir

    from gem.utils.soma_utils.soma_layer import SomaLayer

    names, parents = _bvh_hierarchy(SOMA_BVH)  # 78 joints, [0] = dummy "Root"
    root_dir = Path("inputs/soma_assets") if Path("inputs/soma_assets").exists() else Path(get_assets_dir())
    orient = Rotation.from_matrix(np.load(root_dir / "SOMA_neutral.npz")["t_pose_world"][..., :3, :3])

    soma = SomaLayer(data_root="inputs/soma_assets", low_lod=True, device="cpu", identity_model_type="mhr",
                     mode="warp")
    ident = torch.as_tensor(_np(body_params["identity_coeffs"]), dtype=torch.float32)[0:1]
    scale = torch.as_tensor(_np(body_params["scale_params"]), dtype=torch.float32)[0:1]
    with torch.no_grad():
        pos77 = soma.get_skeleton(ident, scale)[0].cpu().numpy()
    pos = np.concatenate([np.zeros((1, 3)), pos77], axis=0)

    J = len(names)
    offsets = np.zeros((J, 3))
    rest = np.zeros((J, 4))
    for j in range(J):
        p = parents[j]
        offsets[j] = pos[j] if p < 0 else orient[p].inv().apply(pos[j] - pos[p])
        r = Rotation.identity() if p < 0 else orient[p].inv() * orient[j]
        rest[j] = np.roll(r.as_quat(), 1)  # xyzw -> wxyz

    go = _np(body_params["global_orient"])
    bp = _np(body_params["body_pose"]).reshape(go.shape[0], -1, 3)
    T = go.shape[0]
    rv = np.concatenate([go[:, None], bp], axis=1)  # (T,77,3): index k -> skeleton joint k+1
    local = np.zeros((T, J, 4))
    local[:, 0] = [1, 0, 0, 0]
    for j in range(1, J):
        r = orient[parents[j]].inv() * Rotation.from_rotvec(rv[:, j - 1]) * orient[j]
        local[:, j] = np.roll(r.as_quat(), 1, axis=-1)

    # drop the dummy Root: Hips (index 1) becomes the animated root; its translation is `transl`
    keep = list(range(1, J))
    new_parents = [-1 if parents[j] == 0 else parents[j] - 1 for j in keep]
    return {
        "joint_names": np.array([names[j] for j in keep]),
        "parents": np.array(new_parents),
        "offsets": offsets[keep],
        "rest_rot": rest[keep],
        "bvh_local": local[:, keep],  # includes rest (rest * anim)
        "root_pos": _np(body_params["transl"]).astype(np.float64),
        "hips_global_rot_xyzw": (Rotation.from_rotvec(go) * orient[1]).as_quat(),
    }


def camera_from_pred(pred: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """World->camera per frame from the same body seen in world and camera space."""
    g, c = pred["body_params_global"], pred["body_params_incam"]
    Rg = Rotation.from_rotvec(_np(g["global_orient"]))
    Rc = Rotation.from_rotvec(_np(c["global_orient"]))
    R = (Rc * Rg.inv()).as_matrix()
    t = _np(c["transl"]) - np.einsum("tij,tj->ti", R, _np(g["transl"]))
    K = _np(pred["K_fullimg"])
    if K.ndim == 2:
        K = np.repeat(K[None], R.shape[0], axis=0)
    return K, R, t


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--static_cam", action="store_true")
    ap.add_argument("--max_people", type=int, default=8)
    ap.add_argument("--min_seconds", type=float, default=1.0)
    ap.add_argument("--no_imgfeat", action="store_true", help="skip SAM-3D-Body features (keypoints only)")
    ap.add_argument("--ddim", action="store_true", help="diffusion sampling: slower, higher quality")
    a = ap.parse_args()

    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    video = str(Path(a.video).resolve())
    tracks_file = out / "tracks.npz"
    if tracks_file.exists():
        d = np.load(tracks_file, allow_pickle=True)
        tracks, (T, W, H, fps) = d["tracks"].item(), d["info"]
    else:
        import cv2

        fps0 = cv2.VideoCapture(video).get(cv2.CAP_PROP_FPS) or 30.0
        tracks, T, W, H, fps = track_all(video, int(a.min_seconds * fps0), a.max_people, out / "detections.npz")
        np.savez(tracks_file, tracks=np.array(tracks, dtype=object), info=np.array([T, W, H, fps]))
    print(f"[v2m] {len(tracks)} people: " + ", ".join(f"id{k} f{v['start']}-{v['end']}" for k, v in tracks.items()))

    summary = {"video": video, "frames": int(T), "width": int(W), "height": int(H), "fps": float(fps),
               "backend": "gemx", "license": "commercial-ok (see docs/LICENSES.md)",
               "image_features": not a.no_imgfeat, "static_cam": a.static_cam, "tracks": []}
    for n, (tid, tr) in enumerate(sorted(tracks.items(), key=lambda kv: kv[1]["start"])):
        tdir = out / f"track_{n:02d}"
        tdir.mkdir(exist_ok=True)
        clip = tdir / "clip.mp4"
        if not clip.exists():
            cut_clip(video, tr["start"], tr["end"], fps, clip)
        res = run_gemx_on_track(clip, tdir / "gemx", tr["bbx_xyxy"], a.static_cam, a.no_imgfeat, a.ddim)
        pred = res["pred"]
        sm = soma_motion(pred["body_params_global"])
        K, R, t = camera_from_pred(pred)
        np.savez_compressed(
            tdir / "motion_raw.npz", fps=fps, frame_start=tr["start"], frame_end=tr["end"], track_id=tid,
            kp2d=_np(res["vitpose"]), K=K, cam_R=R, cam_t=t, bbx_xyxy=tr["bbx_xyxy"], **sm)
        summary["tracks"].append({"dir": tdir.name, "track_id": int(tid), "start": int(tr["start"]),
                                  "end": int(tr["end"]), "coverage": tr["coverage"]})
        print(f"[v2m] track {n} done -> {tdir / 'motion_raw.npz'}")
        del res, pred
        _free_gpu()
    (out / "run.json").write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
