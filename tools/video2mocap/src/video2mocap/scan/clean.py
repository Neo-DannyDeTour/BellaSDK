"""Remove people and licence plates from scan photos with an image-editing model (Codex `image_gen`),
WITHOUT letting it change anything else.

Generative editors re-render the whole picture (subtle shifts in sharpness, colour, sometimes framing
or size), which would break photogrammetry. So the edit is never used as-is:
  1. the editor returns a full edited image;
  2. we diff it against the original and keep ONLY the regions that clearly changed (people, plates),
     colour-matched to their surroundings and feathered;
  3. every other pixel is copied from the original, bit-identical;
  4. the edited regions are saved as a mask so reconstruction can ignore invented pixels for geometry
     (the real background comes from the other photos) while the texture uses the clean image.
"""
from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path

import numpy as np

PROMPT = """You are cleaning a photo for 3D photogrammetry of a street. Attached: the photo.
Use your image editing tool (image_gen) to edit THIS attached image:
- REMOVE EVERY PERSON COMPLETELY: whole bodies, also partially visible people, their shadows,
  reflections, and anything they hold or carry (bags, phones, strollers, bikes they are pushing).
- Make every vehicle licence plate BLANK (plain plate, no characters).
- Fill the removed areas with the background that would be behind them, continuing the existing
  surfaces exactly (same pavement pattern, wall, lines, perspective, light and shadows).
- CHANGE NOTHING ELSE: same framing, crop, aspect ratio, perspective, colours, exposure, sharpness,
  every other object, sign, text and detail must stay exactly as in the original. Do not add anything.
- If there are no people and no plates, do not generate anything.
Save the edited image as a PNG at exactly this path: {out}
Then reply with one line: DONE {out}   (or NOTHING_TO_REMOVE)."""


def codex_edit(image: Path, out: Path, timeout_s: int = 600) -> str:
    """One Codex call per image (never in parallel). Returns Codex's last line."""
    out.parent.mkdir(parents=True, exist_ok=True)
    last = out.with_suffix(".codex.txt")
    exe = shutil.which("codex") or shutil.which("codex.cmd")
    if not exe:
        raise FileNotFoundError("codex CLI not found on PATH")
    cmd = [exe, "exec", "--skip-git-repo-check", "-s", "workspace-write", "-C", str(out.parent),
           "-i", str(image), "--output-last-message", str(last), "-"]
    # The prompt goes through stdin ("-"): on Windows the npm .cmd shim truncates multi-line arguments,
    # and `codex exec` waits forever on an open stdin that never closes.
    t_start = time.time()
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="ignore")
    try:
        proc.communicate(input=PROMPT.format(out=out.as_posix()), timeout=timeout_s)
    except subprocess.TimeoutExpired:
        # on Windows codex is a .cmd -> node -> codex.exe chain: kill the whole tree
        subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
        proc.communicate()
    if not out.exists():  # Codex sometimes picks its own file name: take the newest PNG it wrote
        new = [p for p in out.parent.glob("*.png") if p.stat().st_mtime >= t_start and p != out]
        if new:
            max(new, key=lambda p: p.stat().st_mtime).replace(out)
    return last.read_text(encoding="utf-8", errors="ignore").strip() if last.exists() else ""


def _align(orig: np.ndarray, ed: np.ndarray) -> np.ndarray:
    """Register the edited image onto the original with a RANSAC homography from feature matches.
    Editors often re-frame or re-scale slightly; without this every pixel would look "changed"."""
    try:
        import cv2
    except ImportError:
        return ed
    g1, g2 = (cv2.cvtColor(x, cv2.COLOR_RGB2GRAY) for x in (orig, ed))
    orb = cv2.ORB_create(6000)
    k1, d1 = orb.detectAndCompute(g1, None)
    k2, d2 = orb.detectAndCompute(g2, None)
    if d1 is None or d2 is None or len(k1) < 50 or len(k2) < 50:
        return ed
    matches = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True).match(d2, d1)
    if len(matches) < 40:
        return ed
    src = np.float32([k2[m.queryIdx].pt for m in matches])
    dst = np.float32([k1[m.trainIdx].pt for m in matches])
    H, inl = cv2.findHomography(src, dst, cv2.RANSAC, 3.0)
    if H is None or inl.sum() < 30:
        return ed
    return cv2.warpPerspective(ed, H, (orig.shape[1], orig.shape[0]), flags=cv2.INTER_LANCZOS4,
                               borderMode=cv2.BORDER_REPLICATE)


def composite(orig_path: Path, edited_path: Path, out_path: Path, mask_path: Path,
              diff_thr: float = 22.0, dilate_px: int = 9, feather_px: int = 6) -> dict:
    """Keep only clearly changed regions of `edited`; everything else is the original, bit-identical."""
    from PIL import Image, ImageFilter

    orig = Image.open(orig_path).convert("RGB")
    ed = Image.open(edited_path).convert("RGB")
    resized = ed.size != orig.size
    if resized:
        ed = ed.resize(orig.size, Image.LANCZOS)
    o = np.asarray(orig).astype(np.float32)
    e = _align(np.asarray(orig), np.asarray(ed)).astype(np.float32)

    # global colour drift of the editor (estimated where it clearly did NOT edit)
    d0 = np.abs(o - e).mean(axis=2)
    calm = d0 < np.percentile(d0, 60)
    e = e - (e[calm].mean(axis=0) - o[calm].mean(axis=0))

    # change mask: blurred luminance/colour difference, cleaned with morphology
    d = Image.fromarray(np.clip(np.abs(o - e).mean(axis=2), 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(3))
    m = Image.fromarray(((np.asarray(d) > diff_thr) * 255).astype(np.uint8))
    m = m.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(2 * dilate_px + 1))  # open + dilate
    hard = np.asarray(m) > 0
    soft = np.asarray(m.filter(ImageFilter.GaussianBlur(feather_px))).astype(np.float32)[..., None] / 255.0

    # local colour match inside each changed area: align edited mean to a ring of original around it
    if hard.any():
        ring = np.asarray(m.filter(ImageFilter.MaxFilter(31))) > 0
        ring &= ~hard
        if ring.any():
            e[hard] += o[ring].mean(axis=0) - e[ring].mean(axis=0)
    res = o * (1 - soft) + np.clip(e, 0, 255) * soft
    res[soft[..., 0] == 0] = o[soft[..., 0] == 0]  # exact original outside the edit
    Image.fromarray(np.clip(res, 0, 255).round().astype(np.uint8)).save(out_path, quality=97)
    Image.fromarray((hard * 255).astype(np.uint8)).save(mask_path)
    area = float(hard.mean())
    return {"edited_area": round(area, 4), "editor_resized": resized,
            "suspicious": area > 0.35 or area == 0.0}


def clean_folder(images: Path, out: Path, only: list[str] | None = None) -> dict:
    """Run Codex on each image (sequentially), composite, write images_clean/ + masks/ + report."""
    out_img, out_mask, raw = out / "images_clean", out / "masks", out / "codex_raw"
    for d in (out_img, out_mask, raw):
        d.mkdir(parents=True, exist_ok=True)
    report = {}
    files = sorted(p for p in images.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png"))
    for p in files:
        if only and p.name not in only:
            continue
        dst = out_img / (p.stem + ".jpg")
        if dst.exists():
            continue
        t0 = time.time()
        edited = raw / (p.stem + "_edit.png")
        reply = codex_edit(p, edited)
        entry = {"codex": reply[-200:], "seconds": round(time.time() - t0)}
        if edited.exists():
            entry.update(composite(p, edited, dst, out_mask / (p.stem + ".png")))
        else:  # nothing to remove (or the editor failed): keep the original untouched
            shutil.copy2(p, dst)
            entry["edited_area"] = 0.0
        report[p.name] = entry
        (out / "clean_report.json").write_text(json.dumps(report, indent=2))
    return report
