"""Viewer / keyframe editor backend for a run folder produced by `v2m run`.

viewer.json carries, per person, the skeleton (parents, offsets, rest rotations) and the clean
animation as local rotations + root position, plus the camera, so the browser does FK itself: edits
made in the browser are previewed live in 3D and over the video. Saving POSTs the edit list; the
server applies it with the same code as `v2m edit` and writes edits.json, edited.npz and edited.bvh.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import numpy as np

from ..backends.gemx import load_track
from ..io.bvh import write_bvh
from ..motion import Motion
from ..process.edit import apply_edits

COLORS = ["#ff5a4e", "#3fa2ff", "#ffc23d", "#53d18b", "#c27dff", "#ff8fd0", "#5ee0e0", "#c9c9c9"]


def _r(a: np.ndarray, d: int) -> list:
    return np.round(np.asarray(a, float), d).tolist()


def _source_video(run: dict, run_dir: Path) -> str:
    v = run["video"]
    src = Path(v)
    if not src.exists() and v.startswith("/mnt/"):  # path recorded inside WSL
        src = Path(f"{v[5].upper()}:/{v[7:]}")
    name = "source" + (src.suffix or ".mp4")
    if src.exists() and not (run_dir / name).exists():
        shutil.copy2(src, run_dir / name)
    return name


def build_viewer_data(run_dir: str | Path) -> Path:
    run_dir = Path(run_dir).resolve()
    run = json.loads((run_dir / "run.json").read_text())
    people = []
    for i, tr in enumerate(run["tracks"]):
        tdir = run_dir / tr["dir"]
        clean = Motion.load(tdir / "clean.npz")
        _, cam, _ = load_track(tdir)
        shift = np.zeros(3)
        for h in clean.meta.get("history", []):
            if h.get("op") == "place_on_ground":
                shift += np.asarray(h["shift"], float)
        sw = clean.meta.get("shared_world", {"M": np.eye(3).tolist(), "b": [0, 0, 0]})
        sk = clean.skeleton
        edits_file = tdir / "edits.json"
        face = None
        if (tdir / "face.npz").exists():
            fd = np.load(tdir / "face.npz")
            face = {"names": [str(n) for n in fd["names"]], "curves": _r(fd["curves"], 3),
                    "valid": fd["valid"].astype(int).tolist()}
        people.append({
            "id": i, "track": tr["dir"], "name": f"Persona {i + 1}", "color": COLORS[i % len(COLORS)],
            "frame_start": tr["start"], "frame_end": tr["end"],
            "names": sk.names, "parents": sk.parents.tolist(),
            "offsets": _r(sk.offsets, 5), "rest": _r(sk.rest_rot, 6),
            "local": _r(clean.local_rot, 4), "root": _r(clean.root_pos, 4),
            "contacts": {k: v.astype(int).tolist() for k, v in clean.contacts.items()},
            # x_track = M^T (x - shift - b);  uv ~ K (R x_track + t)
            "cam": {"K": _r(cam.K.reshape(-1, 9), 3), "R": _r(cam.R.reshape(-1, 9), 6), "t": _r(cam.t, 5),
                    "M": sw["M"], "b": sw["b"], "shift": shift.tolist()},
            "face": face,
            "edits": json.loads(edits_file.read_text()) if edits_file.exists() else [],
            "metrics": json.loads((tdir / "metrics.json").read_text())["final"] if (tdir / "metrics.json").exists() else {},
        })
    data = {"video": _source_video(run, run_dir), "fps": run["fps"], "frames": run["frames"],
            "width": run["width"], "height": run["height"], "people": people}
    out = run_dir / "viewer.json"
    out.write_text(json.dumps(data, separators=(",", ":")))
    shutil.copy2(Path(__file__).with_name("index.html"), run_dir / "index.html")
    return out


def save_edits(run_dir: Path, track: str, edits: list[dict]) -> dict:
    """Persist edits for one person and export the edited motion."""
    tdir = (run_dir / track).resolve()
    if tdir.parent != run_dir.resolve() or not (tdir / "clean.npz").exists():
        raise ValueError(f"unknown track {track}")
    (tdir / "edits.json").write_text(json.dumps(edits, indent=1))
    edited = apply_edits(Motion.load(tdir / "clean.npz"), edits)
    edited.save(tdir / "edited.npz")
    write_bvh(edited, tdir / "edited.bvh")
    return {"ok": True, "edits": len(edits), "files": ["edits.json", "edited.npz", "edited.bvh"]}


def serve(run_dir: str | Path, port: int = 8765, open_browser: bool = True) -> None:
    import http.server
    import webbrowser

    run_dir = Path(run_dir).resolve()
    build_viewer_data(run_dir)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(run_dir), **kw)

        def do_POST(self):  # noqa: N802
            if self.path != "/api/edits":
                self.send_error(404)
                return
            try:
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                res = save_edits(run_dir, body["track"], body["edits"])
                code = 200
            except Exception as e:  # report to the page, keep serving
                res, code = {"ok": False, "error": str(e)}, 400
            payload = json.dumps(res).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    with http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler) as httpd:
        url = f"http://127.0.0.1:{port}/index.html"
        print(f"[v2m] viewer at {url}  (Ctrl+C to stop)")
        if open_browser:
            webbrowser.open(url)
        httpd.serve_forever()
