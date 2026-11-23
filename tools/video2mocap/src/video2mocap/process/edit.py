"""Declarative, reviewable edits. A human or an AI reviewer looks at the overlays, then writes a JSON
list of operations; applying them is deterministic and every op is recorded in motion.meta.

Example edits.json:
[
  {"op": "rotate", "joint": "LeftForeArm", "frames": [118, 126], "euler_deg": [0, 0, -12],
   "falloff": 6, "space": "local", "note": "elbow over-bent vs video in f120"},
  {"op": "offset_root", "frames": [0, 40], "delta_m": [0, -0.02, 0], "falloff": 5},
  {"op": "set_contact", "joint": "LeftToeBase", "frames": [200, 231], "value": true},
  {"op": "trim", "frames": [12, 640]}
]
`frames` is an inclusive [start, end]; `falloff` eases the edit in/out over that many frames outside
the range so edits never pop.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .. import quat
from ..motion import Motion


def _weights(T: int, start: int, end: int, falloff: int) -> np.ndarray:
    w = np.zeros(T)
    s, e = max(0, start), min(T - 1, end)
    w[s : e + 1] = 1.0
    for k in range(1, falloff + 1):
        v = 0.5 + 0.5 * np.cos(np.pi * k / (falloff + 1))
        if s - k >= 0:
            w[s - k] = max(w[s - k], v)
        if e + k < T:
            w[e + k] = max(w[e + k], v)
    return w


def apply_edits(motion: Motion, edits: list[dict]) -> Motion:
    out = motion.copy()
    for ed in edits:
        op = ed["op"]
        T = out.num_frames
        fr = ed.get("frames", [0, T - 1])
        if isinstance(fr, int):
            fr = [fr, fr]
        w = _weights(T, fr[0], fr[1], int(ed.get("falloff", 0)))
        if op == "rotate":
            j = out.skeleton.index(ed["joint"])
            if "quat" in ed:  # (w, x, y, z), e.g. written by the web editor's rotation gizmo
                delta = quat.normalize(np.asarray(ed["quat"], dtype=float))
            else:
                delta = quat.from_euler(np.array(ed["euler_deg"], dtype=float), ed.get("order", "XYZ"))
            dq = quat.slerp(quat.identity((T,)), np.broadcast_to(delta, (T, 4)), w)
            if ed.get("space", "local") == "local":
                out.local_rot[:, j] = quat.normalize(quat.mul(out.local_rot[:, j], dq))
            else:  # "parent": rotate in the parent's frame
                out.local_rot[:, j] = quat.normalize(quat.mul(dq, out.local_rot[:, j]))
        elif op == "set_rotation":
            j = out.skeleton.index(ed["joint"])
            target = quat.from_euler(np.array(ed["euler_deg"], dtype=float), ed.get("order", "XYZ"))
            out.local_rot[:, j] = quat.slerp(out.local_rot[:, j], np.broadcast_to(target, (T, 4)), w)
        elif op == "offset_root":
            out.root_pos += np.asarray(ed["delta_m"], dtype=float)[None] * w[:, None]
        elif op == "set_contact":
            m = out.contacts.setdefault(ed["joint"], np.zeros(T, dtype=bool))
            m[max(0, fr[0]) : fr[1] + 1] = bool(ed["value"])
        elif op == "trim":
            s, e = fr[0], fr[1] + 1
            out.root_pos = out.root_pos[s:e]
            out.local_rot = out.local_rot[s:e]
            if out.confidence is not None:
                out.confidence = out.confidence[s:e]
            out.contacts = {k: v[s:e] for k, v in out.contacts.items()}
        else:
            raise ValueError(f"unknown edit op: {op}")
        out.meta.setdefault("history", []).append({"op": "edit", "edit": ed})
    return out


def load_edits(path: str | Path) -> list[dict]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return data["edits"] if isinstance(data, dict) else data
