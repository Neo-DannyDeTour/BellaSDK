#!/usr/bin/env python3
"""Headless ComfyUI Hunyuan3D-2 CLI generator for BellaSDK (/3d).

Connects to (or temporarily boots) local ComfyUI (`~/Documents/ComfyUI --lowvram`),
strips backgrounds cleanly with `rembg`, runs Hunyuan3D-2mv (multi-view) or
Hunyuan3D-2.0 (single-view), and optionally invokes headless Blender cleanup.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Dict, Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
COMFY_DIR = Path(os.environ.get("COMFYUI_DIR", str(Path.home() / "Documents" / "ComfyUI")))
COMFY_PYTHON = COMFY_DIR / "venv" / "bin" / "python"
WORKFLOW_DIR = REPO_ROOT / "tools" / "comfyui" / "workflows"
BLENDER_POST_SCRIPT = REPO_ROOT / "tools" / "blender" / "postprocess_trellis.py"


def _find_blender() -> Optional[str]:
    for cand in ("/snap/bin/blender", "/usr/bin/blender", "/usr/local/bin/blender"):
        if Path(cand).is_file() and os.access(cand, os.X_OK):
            return cand
    return shutil.which("blender")


def _http_json(url: str, data: Optional[bytes] = None, content_type: Optional[str] = None) -> Any:
    headers: Dict[str, str] = {}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _server_ready(base_url: str) -> bool:
    try:
        _http_json(f"{base_url}/system_stats")
        return True
    except Exception:
        return False


def _ensure_comfy_server(host: str, port: int, vram_mode: str) -> Optional[subprocess.Popen[bytes]]:
    base_url = f"http://{host}:{port}"
    if _server_ready(base_url):
        print(f"[Comfy3D] Connected to running ComfyUI at {base_url}")
        return None
    if not COMFY_PYTHON.is_file():
        raise RuntimeError(f"ComfyUI venv python not found: {COMFY_PYTHON}")

    cmd = [
        str(COMFY_PYTHON),
        str(COMFY_DIR / "main.py"),
        f"--{vram_mode}",
        "--listen",
        host,
        "--port",
        str(port),
    ]
    print(f"[Comfy3D] Booting local ComfyUI ({vram_mode}) on {base_url}...")
    proc = subprocess.Popen(cmd, cwd=str(COMFY_DIR), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    deadline = time.time() + 90.0
    while time.time() < deadline:
        if proc.poll() is not None:
            out = proc.stdout.read().decode("utf-8", errors="replace") if proc.stdout else ""
            raise RuntimeError(f"ComfyUI exited early (code={proc.returncode}):\n{out[-1500:]}")
        if _server_ready(base_url):
            print("[Comfy3D] ComfyUI ready.")
            return proc
        time.sleep(1.5)
    proc.terminate()
    raise RuntimeError("Timed out waiting for ComfyUI server to boot.")


def _strip_bg_with_rembg(src: Path, dst: Path) -> Path:
    """Use ComfyUI's venv rembg to produce a clean RGBA cutout for 3D conditioning."""
    code = (
        "from PIL import Image; from rembg import remove; "
        f"img = Image.open({str(src)!r}).convert('RGBA'); "
        f"remove(img).save({str(dst)!r}, format='PNG')"
    )
    res = subprocess.run([str(COMFY_PYTHON), "-c", code], capture_output=True, text=True)
    if res.returncode != 0 or not dst.is_file():
        print(f"[Comfy3D] rembg skipped/failed ({res.stderr.strip()[:200]}); using raw image.")
        shutil.copy2(src, dst)
    return dst


def _upload_image(base_url: str, image_path: Path) -> str:
    boundary = f"----BellaSDK{uuid.uuid4().hex}"
    body = bytearray()
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(
        f'Content-Disposition: form-data; name="image"; filename="{image_path.name}"\r\n'.encode()
    )
    body.extend(b"Content-Type: image/png\r\n\r\n")
    body.extend(image_path.read_bytes())
    body.extend(b"\r\n")
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(b'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n')
    body.extend(f"--{boundary}--\r\n".encode())

    resp = _http_json(
        f"{base_url}/upload/image",
        data=bytes(body),
        content_type=f"multipart/form-data; boundary={boundary}",
    )
    return str(resp["name"])


def _queue_and_wait(base_url: str, prompt: Dict[str, Any], timeout_s: float = 900.0) -> Dict[str, Any]:
    client_id = uuid.uuid4().hex
    payload = json.dumps({"prompt": prompt, "client_id": client_id}).encode("utf-8")
    resp = _http_json(f"{base_url}/prompt", data=payload, content_type="application/json")
    prompt_id = str(resp["prompt_id"])
    print(f"[Comfy3D] Queued prompt_id={prompt_id}")

    deadline = time.time() + timeout_s
    while time.time() < deadline:
        hist = _http_json(f"{base_url}/history/{prompt_id}")
        if prompt_id in hist:
            entry = hist[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                raise RuntimeError(f"ComfyUI execution failed: {json.dumps(status)[:1200]}")
            if status.get("completed"):
                return entry
        time.sleep(2.0)
    raise RuntimeError(f"Timed out after {timeout_s}s waiting for ComfyUI prompt {prompt_id}")


def _extract_glb_path(history_entry: Dict[str, Any]) -> Path:
    outputs = history_entry.get("outputs", {})
    for node_out in outputs.values():
        for key in ("glb_path", "text", "string"):
            vals = node_out.get(key)
            if isinstance(vals, list) and vals:
                cand = Path(str(vals[0]))
                if cand.is_file():
                    return cand
                alt = COMFY_DIR / "output" / str(vals[0])
                if alt.is_file():
                    return alt
    out_dir = COMFY_DIR / "output" / "3D"
    if out_dir.is_dir():
        glbs = sorted(out_dir.glob("*.glb"), key=lambda p: p.stat().st_mtime, reverse=True)
        if glbs:
            return glbs[0]
    raise RuntimeError("Could not locate exported GLB in ComfyUI output directory.")


def main() -> int:
    parser = argparse.ArgumentParser(description="BellaSDK ComfyUI Hunyuan3D-2 CLI (/3d)")
    parser.add_argument("--front", type=Path, required=True, help="Primary front image plate")
    parser.add_argument("--left", type=Path, default=None, help="Optional left-side profile plate")
    parser.add_argument("--back", type=Path, default=None, help="Optional back elevation plate")
    parser.add_argument("--slug", type=str, required=True, help="Asset slug under assets/models/")
    parser.add_argument("--target-height", type=float, default=1.68, help="Target height in meters")
    parser.add_argument("--tri-budget", type=int, default=45000, help="Target max triangle count")
    parser.add_argument("--steps", type=int, default=30, help="Diffusion sampling steps")
    parser.add_argument("--octree-res", type=int, default=384, help="VAE marching-cubes octree res")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed")
    parser.add_argument("--vram-mode", choices=["lowvram", "medvram", "normalvram"], default="lowvram")
    parser.add_argument("--host", type=str, default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8188)
    parser.add_argument("--skip-rembg", action="store_true", help="Skip rembg background removal")
    parser.add_argument("--skip-postprocess", action="store_true", help="Save raw GLB only")
    parser.add_argument("--keep-separate", action="store_true", help="Preserve sub-meshes in Blender")
    parser.add_argument("--output-dir", type=Path, default=None)
    args = parser.parse_args()

    if not args.front.is_file():
        print(f"Error: front image not found: {args.front}", file=sys.stderr)
        return 1

    multiview = args.left is not None or args.back is not None
    wf_path = WORKFLOW_DIR / (
        "hunyuan3d_multiview_api.json" if multiview else "hunyuan3d_singleview_api.json"
    )
    workflow: Dict[str, Any] = json.loads(wf_path.read_text(encoding="utf-8"))

    target_dir = args.output_dir or (REPO_ROOT / "assets" / "models" / args.slug)
    target_dir.mkdir(parents=True, exist_ok=True)
    tmp_dir = Path("/tmp") / f"comfy3d_{args.slug}_{uuid.uuid4().hex[:6]}"
    tmp_dir.mkdir(parents=True, exist_ok=True)

    proc: Optional[subprocess.Popen[bytes]] = None
    try:
        proc = _ensure_comfy_server(args.host, args.port, args.vram_mode)
        base_url = f"http://{args.host}:{args.port}"

        def _prep_and_upload(src: Path, tag: str) -> str:
            cut = tmp_dir / f"{tag}.png"
            if args.skip_rembg:
                shutil.copy2(src, cut)
            else:
                _strip_bg_with_rembg(src, cut)
            return _upload_image(base_url, cut)

        workflow["2"]["inputs"]["image"] = _prep_and_upload(args.front, "front")
        if multiview:
            if args.left and args.left.is_file():
                workflow["3"]["inputs"]["image"] = _prep_and_upload(args.left, "left")
            else:
                workflow.pop("3", None)
                workflow["5"]["inputs"].pop("left", None)
            if args.back and args.back.is_file():
                workflow["4"]["inputs"]["image"] = _prep_and_upload(args.back, "back")
            else:
                workflow.pop("4", None)
                workflow["5"]["inputs"].pop("back", None)

        workflow["5"]["inputs"]["steps"] = args.steps
        workflow["5"]["inputs"]["seed"] = args.seed
        workflow["6"]["inputs"]["octree_resolution"] = args.octree_res
        workflow["7"]["inputs"]["max_facenum"] = max(args.tri_budget, 20000)
        workflow["8"]["inputs"]["filename_prefix"] = f"3D/{args.slug}"

        hist = _queue_and_wait(base_url, workflow)
        raw_glb = _extract_glb_path(hist)
        dest_raw = target_dir / f"{args.slug}_raw.glb"
        shutil.copy2(raw_glb, dest_raw)
        print(f"[Comfy3D] Raw GLB saved: {dest_raw}")

        if args.skip_postprocess:
            return 0

        blender = _find_blender()
        if not blender:
            raise RuntimeError("Blender binary not found for post-processing.")

        final_glb = target_dir / f"{args.slug}.glb"
        meta_out = target_dir / "postprocess_meta.json"
        cmd = [
            blender,
            "--background",
            "--python",
            str(BLENDER_POST_SCRIPT),
            "--",
            "--input",
            str(dest_raw),
            "--output",
            str(final_glb),
            "--slug",
            args.slug,
            "--tri-budget",
            str(args.tri_budget),
            "--target-height",
            str(args.target_height),
            "--tex-dir",
            str(target_dir),
            "--meta-out",
            str(meta_out),
            "--preserve-materials",
        ]
        if args.keep_separate:
            cmd.append("--keep-separate")
        res = subprocess.run(cmd, check=False)
        if res.returncode != 0:
            raise RuntimeError(f"Blender postprocess failed (code={res.returncode})")
        print(f"[Comfy3D] Clean GLB ready: {final_glb}")
        return 0
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main())
