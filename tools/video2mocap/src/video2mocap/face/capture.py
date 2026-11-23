"""Face capture: video -> 52 ARKit-style blendshape curves + head rotation, per frame.

Backend: MediaPipe Face Landmarker (code and blendshape model under Apache-2.0, model card
"Blendshape V2", Nov 2022). Runs on CPU, so it never competes with the body estimator for the GPU.
Best input: a face-cam take (phone in front of the face, face filling the frame, even light).
"""
from __future__ import annotations

import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from .. import quat
from ..process.filters import lowpass

MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"


def model_path() -> Path:
    local = Path(__file__).resolve().parents[3] / "models" / "face_landmarker.task"
    if local.exists():
        return local
    cache = Path.home() / ".cache" / "video2mocap" / "face_landmarker.task"
    if not cache.exists():
        cache.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(MODEL_URL, cache)
    return cache


@dataclass
class FaceTake:
    fps: float
    names: list[str]  # 52 ARKit names (MediaPipe's "_neutral" is dropped)
    curves: np.ndarray  # (T,52) in [0,1]
    head_rot: np.ndarray  # (T,4) wxyz, head orientation in camera space
    valid: np.ndarray  # (T,) bool, a face was found (before gap filling)
    meta: dict = field(default_factory=dict)

    @property
    def num_frames(self) -> int:
        return self.curves.shape[0]

    def save(self, path: str | Path) -> None:
        import json

        np.savez_compressed(path, fps=self.fps, names=np.array(self.names), curves=self.curves,
                            head_rot=self.head_rot, valid=self.valid, meta=json.dumps(self.meta))

    @classmethod
    def load(cls, path: str | Path) -> "FaceTake":
        import json

        d = np.load(path, allow_pickle=False)
        return cls(float(d["fps"]), [str(n) for n in d["names"]], d["curves"], d["head_rot"], d["valid"],
                   json.loads(str(d["meta"])))


def _apply_frame_rotation(rgb: np.ndarray, rotation_deg: int) -> np.ndarray:
    k = int(round(rotation_deg / 90.0)) % 4
    if k:
        return np.ascontiguousarray(np.rot90(rgb, k))
    return rgb


def _iter_frames(video: str | Path):
    import av

    with av.open(str(video)) as c:
        s = c.streams.video[0]
        fps = float(s.average_rate or 30)
        for fr in c.decode(s):
            rot = int(getattr(fr, "rotation", 0) or 0)
            if rot == 0 and "rotate" in s.metadata:
                rot = -int(round(float(s.metadata["rotate"])))
            yield fps, _apply_frame_rotation(fr.to_ndarray(format="rgb24"), rot)


def capture_face(video: str | Path, max_gap_s: float = 0.5, cutoff_hz: float = 10.0,
                 blink_cutoff_hz: float = 15.0) -> FaceTake:
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision

    opts = vision.FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=str(model_path())),
        running_mode=vision.RunningMode.VIDEO, num_faces=1,
        output_face_blendshapes=True, output_facial_transformation_matrixes=True)
    names: list[str] | None = None
    curves, rots, valid = [], [], []
    fps = 30.0
    with vision.FaceLandmarker.create_from_options(opts) as lm:
        for i, (fps, rgb) in enumerate(_iter_frames(video)):
            res = lm.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), int(i * 1000 / fps))
            if res.face_blendshapes:
                bs = [c for c in res.face_blendshapes[0] if c.category_name != "_neutral"]
                if names is None:
                    names = [c.category_name for c in bs]
                curves.append([c.score for c in bs])
                rots.append(quat.from_matrix(np.asarray(res.facial_transformation_matrixes[0])[:3, :3]))
                valid.append(True)
            else:
                curves.append(None)
                rots.append(None)
                valid.append(False)
    if names is None:
        raise RuntimeError(f"no face found in {video}")
    T, K = len(curves), len(names)
    valid_a = np.array(valid)
    C = np.full((T, K), np.nan)
    R = np.full((T, 4), np.nan)
    for t in range(T):
        if valid[t]:
            C[t], R[t] = curves[t], rots[t]
    C, R = _fill_gaps(C, R, valid_a, int(max_gap_s * fps))
    # zero-phase smoothing; blinks are fast, keep more bandwidth for them
    ok = ~np.isnan(C[:, 0])
    if ok.sum() > 10:
        blink = np.array(["Blink" in n for n in names])
        C[ok] = np.clip(np.where(blink, lowpass(C[ok], fps, blink_cutoff_hz), lowpass(C[ok], fps, cutoff_hz)), 0, 1)
        R[ok] = quat.normalize(lowpass(quat.make_continuous(R[ok]), fps, cutoff_hz))
    C = np.nan_to_num(C, nan=0.0)
    R[np.isnan(R[:, 0])] = [1, 0, 0, 0]
    return FaceTake(fps, names, C.astype(np.float32), R, valid_a,
                    {"source": str(video), "backend": "mediapipe-face-landmarker", "license": "Apache-2.0",
                     "valid_ratio": float(valid_a.mean())})


def _fill_gaps(C: np.ndarray, R: np.ndarray, valid: np.ndarray, max_gap: int) -> tuple[np.ndarray, np.ndarray]:
    """Linear interpolation over short dropouts (blur, a hand passing); long gaps stay empty."""
    idx = np.where(valid)[0]
    if idx.size < 2:
        return C, R
    for a, b in zip(idx[:-1], idx[1:]):
        if 1 < b - a <= max_gap + 1:
            w = (np.arange(a + 1, b) - a) / (b - a)
            C[a + 1 : b] = C[a] + (C[b] - C[a]) * w[:, None]
            R[a + 1 : b] = quat.slerp(np.broadcast_to(R[a], (len(w), 4)), np.broadcast_to(R[b], (len(w), 4)), w)
    return C, R


def capture_face_from_track(run_dir: str | Path, person: int, crop_px: int = 384, **kw) -> FaceTake:
    """Face from the BODY video: crop and upscale each person's head (located by projecting the solved
    skeleton) before MediaPipe. Works when faces are reasonably visible but small in a wide shot."""
    import json

    from PIL import Image

    from ..backends.gemx import load_track

    run_dir = Path(run_dir)
    run = json.loads((run_dir / "run.json").read_text())
    tr = run["tracks"][person]
    tdir = run_dir / tr["dir"]
    raw, cam, _ = load_track(tdir)
    names = raw.skeleton.names
    gpos, _ = raw.fk()
    uv, z = cam.project(gpos)
    head, top = uv[:, names.index("Head")], uv[:, names.index("HeadEnd")]
    size = np.maximum(np.linalg.norm(top - head, axis=-1) * 3.2, 24)
    centre = (head + top) / 2
    clip = tdir / "clip.mp4"
    tmp = tdir / "face_crops.mp4"
    import av

    with av.open(str(clip)) as src, av.open(str(tmp), "w") as dst:
        s = src.streams.video[0]
        out = dst.add_stream("libx264", rate=int(round(float(s.average_rate or 30))))
        out.width = out.height = crop_px
        out.pix_fmt = "yuv420p"
        out.options = {"crf": "12"}
        for i, fr in enumerate(src.decode(s)):
            if i >= len(centre):
                break
            img = fr.to_image()
            c, h = centre[i], size[i] / 2
            box = (int(c[0] - h), int(c[1] - h), int(c[0] + h), int(c[1] + h))
            crop = img.crop(box).resize((crop_px, crop_px), Image.BICUBIC) if z[i, 0] > 0 else \
                Image.new("RGB", (crop_px, crop_px))
            for p in out.encode(av.VideoFrame.from_image(crop)):
                dst.mux(p)
        for p in out.encode():
            dst.mux(p)
    take = capture_face(tmp, **kw)
    take.meta.update({"from_track": tr["dir"], "crop_px": crop_px})
    return take
