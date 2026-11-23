"""Photos / video -> textured 3D mesh (photogrammetry).

Stages (each one is skipped if its output exists, so a run can be resumed):
  1. ingest      pick sharp, non-redundant images (from a folder or a video)
  2. sfm         camera poses + sparse points          COLMAP (BSD-3)
  3. undistort   undistorted images for dense stereo   COLMAP
  4. mvs         dense cloud -> mesh -> refine -> texture   OpenMVS (AGPL, run as an external tool)
  5. export      mesh.obj + texture, and a report

External tools are found through $COLMAP / $OPENMVS_DIR, or the default install in ~/tools.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

IMG_EXT = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".heic"}
VIDEO_EXT = {".mp4", ".mov", ".m4v", ".mkv", ".webm", ".avi"}


def tool(name: str) -> str:
    home = Path.home() / "tools"
    if name == "colmap":
        cands = [os.environ.get("COLMAP"), shutil.which("colmap"), home / "colmap/bin/colmap.exe"]
    else:
        d = os.environ.get("OPENMVS_DIR")
        cands = [Path(d) / f"{name}.exe" if d else None, Path(d) / name if d else None, shutil.which(name),
                 home / f"openmvs/vc17/x64/Release/{name}.exe"]
    for c in cands:
        if c and Path(c).exists():
            return str(c)
    raise FileNotFoundError(f"{name} not found (set COLMAP / OPENMVS_DIR, see docs/scan/README.md)")


def run(cmd: list[str], log: Path, cwd: Path | None = None) -> None:
    t0 = time.time()
    with open(log, "a", encoding="utf-8") as f:
        f.write(f"\n$ {' '.join(map(str, cmd))}\n")
        f.flush()
        res = subprocess.run([str(c) for c in cmd], stdout=f, stderr=subprocess.STDOUT, cwd=cwd)
        f.write(f"[exit {res.returncode} in {time.time() - t0:.0f}s]\n")
    if res.returncode != 0:
        raise RuntimeError(f"{Path(cmd[0]).name} failed (exit {res.returncode}); see {log}")


# ------------------------------------------------------------------------------------------ ingest
def sharpness(gray: np.ndarray) -> float:
    """Variance of the Laplacian: low = blurry."""
    g = gray.astype(np.float32)
    lap = -4 * g[1:-1, 1:-1] + g[:-2, 1:-1] + g[2:, 1:-1] + g[1:-1, :-2] + g[1:-1, 2:]
    return float(lap.var())


def ingest(src: Path, out_dir: Path, max_images: int = 300, max_side: int = 3200,
           video_every_s: float = 0.33) -> dict:
    """Copy (and downscale) the input images, or extract sharp frames from a video: one candidate
    every `video_every_s` seconds, keeping the sharpest frame of each window."""
    from PIL import Image, ImageOps

    out_dir.mkdir(parents=True, exist_ok=True)
    kept, dropped = [], 0
    if src.is_dir():
        files = sorted(p for p in src.iterdir() if p.suffix.lower() in IMG_EXT)
        scores = []
        for p in files:
            im = ImageOps.exif_transpose(Image.open(p))
            small = np.asarray(im.convert("L").resize((800, int(800 * im.height / im.width))))
            scores.append(sharpness(small))
        thr = np.percentile(scores, 10) * 0.5 if scores else 0  # drop only clearly blurry shots
        for p, s in zip(files, scores):
            if s < thr:
                dropped += 1
                continue
            im = ImageOps.exif_transpose(Image.open(p)).convert("RGB")
            im.thumbnail((max_side, max_side))
            dst = out_dir / (p.stem + ".jpg")
            im.save(dst, quality=95)
            kept.append(dst.name)
        if len(kept) > max_images:  # uniform subsample keeps coverage
            idx = set(np.linspace(0, len(kept) - 1, max_images).round().astype(int))
            for i, n in enumerate(list(kept)):
                if i not in idx:
                    (out_dir / n).unlink()
            kept = [n for i, n in enumerate(kept) if i in idx]
    elif src.suffix.lower() in VIDEO_EXT:
        import av

        with av.open(str(src)) as c:
            s = c.streams.video[0]
            fps = float(s.average_rate or 30)
            win = max(1, int(round(video_every_s * fps)))
            best, best_s, n = None, -1.0, 0
            for i, fr in enumerate(c.decode(s)):
                img = fr.to_image()
                sc = sharpness(np.asarray(img.convert("L").resize((640, int(640 * img.height / img.width)))))
                if sc > best_s:
                    best, best_s = img, sc
                if (i + 1) % win == 0:
                    best.thumbnail((max_side, max_side))
                    name = f"f{n:05d}.jpg"
                    best.save(out_dir / name, quality=95)
                    kept.append(name)
                    n += 1
                    best, best_s = None, -1.0
                    if n >= max_images:
                        break
    else:
        raise ValueError(f"{src}: expected a folder of photos or a video")
    return {"images": len(kept), "dropped_blurry": dropped}


# ------------------------------------------------------------------------------------------ pipeline
@dataclass
class ScanConfig:
    max_images: int = 300
    max_side: int = 3200
    matcher: str = "exhaustive"  # "sequential" for long videos
    resolution_level: int = 1  # OpenMVS densify: 0 = full res, 1 = half (8 GB GPUs), 2 = quarter
    decimate: float = 1.0  # OpenMVS mesh decimation factor (1 = keep)
    refine: bool = True
    texture_size: int = 8192
    clean: bool = False  # remove people + plates with Codex (one call per photo), see scan/clean.py
    extra: dict = field(default_factory=dict)


def scan(src: str | Path, out: str | Path, cfg: ScanConfig | None = None) -> dict:
    cfg = cfg or ScanConfig()
    src, out = Path(src).resolve(), Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    log = out / "scan.log"
    report: dict = {"source": str(src), "config": cfg.__dict__, "stages": {}}
    images, sparse, dense = out / "images", out / "sparse", out / "dense"
    t0 = time.time()

    if not images.exists() or not any(images.iterdir()):
        report["stages"]["ingest"] = ingest(src, images, cfg.max_images, cfg.max_side)
    mask_args: list = []
    if cfg.clean:
        from .clean import clean_folder

        report["stages"]["clean"] = {"edited": sum(1 for v in clean_folder(images, out).values()
                                                   if v.get("edited_area", 0) > 0)}
        # COLMAP ignores features where its mask is black: invert our "edited region" masks so no
        # geometry is ever derived from invented pixels (the real background comes from other photos)
        from PIL import Image, ImageOps

        cm = out / "colmap_masks"
        cm.mkdir(exist_ok=True)
        for mpath in (out / "masks").glob("*.png"):
            ImageOps.invert(Image.open(mpath).convert("L")).save(cm / f"{mpath.stem}.jpg.png")
        images = out / "images_clean"
        mask_args = ["--ImageReader.mask_path", cm]
    colmap = tool("colmap")
    db = out / "database.db"
    if not (sparse / "0").exists():
        sparse.mkdir(exist_ok=True)
        run([colmap, "feature_extractor", "--database_path", db, "--image_path", images,
             "--ImageReader.single_camera", "1", "--ImageReader.camera_model", "OPENCV", *mask_args], log)
        run([colmap, f"{cfg.matcher}_matcher", "--database_path", db], log)
        run([colmap, "mapper", "--database_path", db, "--image_path", images, "--output_path", sparse], log)
    aligned = out / "sparse_aligned"
    if not (aligned / "cameras.bin").exists():
        # gravity-up: COLMAP's frame is arbitrary; Manhattan alignment finds the vertical from the
        # building lines (falls back to image orientation for objects without straight lines)
        aligned.mkdir(exist_ok=True)
        try:
            run([colmap, "model_orientation_aligner", "--image_path", images, "--input_path", sparse / "0",
                 "--output_path", aligned, "--method", "MANHATTAN-WORLD"], log)
        except RuntimeError:
            run([colmap, "model_orientation_aligner", "--image_path", images, "--input_path", sparse / "0",
                 "--output_path", aligned, "--method", "IMAGE-ORIENTATION"], log)
    if not (dense / "sparse").exists():
        run([colmap, "image_undistorter", "--image_path", images, "--input_path", aligned,
             "--output_path", dense, "--output_type", "COLMAP"], log)
    report["stages"]["sfm"] = _sfm_stats(colmap, sparse / "0", log)

    mvs = out / "mvs"
    mvs.mkdir(exist_ok=True)
    om = lambda n: tool(n)  # noqa: E731
    scene, dscene, mesh, rmesh, tmesh = (mvs / n for n in ("scene.mvs", "scene_dense.mvs", "scene_mesh.ply",
                                                            "scene_mesh_refine.ply", "scene_textured.obj"))
    if not scene.exists():
        run([om("InterfaceCOLMAP"), "-i", dense, "-o", scene, "--image-folder", dense / "images"], log, cwd=mvs)
    if not dscene.exists():
        run([om("DensifyPointCloud"), "-i", scene, "-o", dscene, "--resolution-level", str(cfg.resolution_level)], log, cwd=mvs)
    if not mesh.exists():
        run([om("ReconstructMesh"), "-i", dscene, "-p", mvs / "scene_dense.ply", "-o", mesh,
             "--decimate", str(cfg.decimate)], log, cwd=mvs)
    src_mesh = mesh
    if cfg.refine:
        if not rmesh.exists():
            run([om("RefineMesh"), "-i", dscene, "-m", mesh, "-o", rmesh, "--resolution-level", str(cfg.resolution_level + 1)],
                log, cwd=mvs)
        src_mesh = rmesh
    if not tmesh.exists():
        run([om("TextureMesh"), "-i", dscene, "-m", src_mesh, "-o", tmesh, "--export-type", "obj",
             "--max-texture-size", str(cfg.texture_size),
             # seam levelling in the OpenMVS 2.4.0 Windows build fills patches with black (verified on
             # the openMVS sample: 56 % black texels with it, 0 % without), so it is off for now
             "--global-seam-leveling", "0", "--local-seam-leveling", "0"], log, cwd=mvs)

    final = out / "model"
    final.mkdir(exist_ok=True)
    for f in mvs.glob("scene_textured*"):
        if f.suffix in (".obj", ".mtl", ".png", ".jpg"):
            shutil.copy2(f, final / f.name)
    report["stages"]["mesh"] = _mesh_stats(final / tmesh.name)
    report["seconds"] = round(time.time() - t0)
    report["model"] = str(final / tmesh.name)
    (out / "report.json").write_text(json.dumps(report, indent=2))
    return report


def _sfm_stats(colmap: str, model: Path, log: Path) -> dict:
    res = subprocess.run([colmap, "model_analyzer", "--path", str(model)], capture_output=True, text=True)
    stats = {}
    for line in (res.stdout + res.stderr).splitlines():
        for key in ("Registered images", "Points", "Mean reprojection error", "Mean track length"):
            if key in line and ":" in line:
                stats[key] = line.split(":")[-1].strip()
    with open(log, "a", encoding="utf-8") as f:
        f.write(f"[sfm stats] {stats}\n")
    return stats


def _mesh_stats(obj: Path) -> dict:
    v = f = 0
    with open(obj, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            if line.startswith("v "):
                v += 1
            elif line.startswith("f "):
                f += 1
    textures = [p.name for p in obj.parent.glob("*.png")] + [p.name for p in obj.parent.glob("*.jpg")]
    return {"vertices": v, "triangles": f, "textures": textures}
