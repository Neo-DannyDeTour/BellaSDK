"""BVH read/write. BVH is the lowest common denominator: Blender imports it natively and from there
it goes to FBX for Unreal. Units: we write centimetres (scale=100) by default, which is what both
Blender's "scale 0.01" import preset and Unreal expect."""
from __future__ import annotations

from pathlib import Path

import numpy as np

from .. import quat
from ..motion import Motion, Skeleton

ORDER = "ZXY"  # rotation channel order; ZXY is the most widely supported


def write_bvh(motion: Motion, path: str | Path, scale: float = 100.0, order: str = ORDER) -> None:
    sk = motion.skeleton
    # BVH has no rest rotations: bake them into the animated rotation.
    loc = quat.mul(np.broadcast_to(sk.rest_rot, motion.local_rot.shape), motion.local_rot)
    loc = quat.make_continuous(loc)
    euler = quat.to_euler(loc, order)  # (T,J,3)
    euler = _unwrap_degrees(euler)
    lines: list[str] = ["HIERARCHY"]
    chans = " ".join(f"{a}rotation" for a in order)

    def emit(j: int, depth: int) -> None:
        ind = "  " * depth
        kids = sk.children(j)
        off = sk.offsets[j] * scale
        if sk.parents[j] < 0:
            lines.append(f"{ind}ROOT {sk.names[j]}")
        else:
            lines.append(f"{ind}JOINT {sk.names[j]}")
        lines.append(f"{ind}{{")
        lines.append(f"{ind}  OFFSET {off[0]:.6f} {off[1]:.6f} {off[2]:.6f}")
        if sk.parents[j] < 0:
            lines.append(f"{ind}  CHANNELS 6 Xposition Yposition Zposition {chans}")
        else:
            lines.append(f"{ind}  CHANNELS 3 {chans}")
        for c in kids:
            emit(c, depth + 1)
        if not kids:
            lines.append(f"{ind}  End Site")
            lines.append(f"{ind}  {{")
            lines.append(f"{ind}    OFFSET 0.000000 0.000000 0.000000")
            lines.append(f"{ind}  }}")
        lines.append(f"{ind}}}")

    emit(0, 0)
    dfs = _dfs_order(sk)
    lines.append("MOTION")
    lines.append(f"Frames: {motion.num_frames}")
    lines.append(f"Frame Time: {1.0 / motion.fps:.8f}")
    for t in range(motion.num_frames):
        vals = list(motion.root_pos[t] * scale)
        for j in dfs:
            vals.extend(euler[t, j])
        lines.append(" ".join(f"{v:.6f}" for v in vals))
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def read_bvh(path: str | Path, scale: float = 100.0) -> Motion:
    tokens = Path(path).read_text(encoding="utf-8").split()
    names: list[str] = []
    parents: list[int] = []
    offsets: list[list[float]] = []
    channels: list[list[str]] = []
    stack: list[int] = []
    i = 0
    pending_end = False
    while tokens[i] != "MOTION":
        tok = tokens[i]
        if tok in ("ROOT", "JOINT"):
            names.append(tokens[i + 1])
            parents.append(stack[-1] if stack else -1)
            offsets.append([0.0, 0.0, 0.0])
            channels.append([])
            i += 2
        elif tok == "End":
            pending_end = True
            i += 2
        elif tok == "{":
            stack.append(-2 if pending_end else len(names) - 1)
            pending_end = False
            i += 1
        elif tok == "}":
            stack.pop()
            i += 1
        elif tok == "OFFSET":
            if stack[-1] >= 0:
                offsets[stack[-1]] = [float(x) / scale for x in tokens[i + 1 : i + 4]]
            i += 4
        elif tok == "CHANNELS":
            n = int(tokens[i + 1])
            channels[stack[-1]] = tokens[i + 2 : i + 2 + n]
            i += 2 + n
        else:
            i += 1
    nframes = int(tokens[i + 2])
    ftime = float(tokens[i + 5])
    data = np.array(tokens[i + 6 :], dtype=float).reshape(nframes, -1)
    sk = Skeleton(names, np.array(parents), np.array(offsets))
    J = len(names)
    root_pos = np.zeros((nframes, 3))
    local = quat.identity((nframes, J))
    col = 0
    for j in range(J):
        ch = channels[j]
        rot_axes = ""
        rot_cols = []
        for c in ch:
            if c.endswith("position"):
                if j == 0:
                    root_pos[:, "XYZ".index(c[0])] = data[:, col] / scale
            else:
                rot_axes += c[0]
                rot_cols.append(col)
            col += 1
        if rot_axes:
            local[:, j] = quat.from_euler(data[:, rot_cols], rot_axes)
    return Motion(sk, 1.0 / ftime, root_pos, local)


def _dfs_order(sk: Skeleton) -> list[int]:
    out: list[int] = []

    def rec(j: int) -> None:
        out.append(j)
        for c in sk.children(j):
            rec(c)

    rec(0)
    return out


def _unwrap_degrees(e: np.ndarray) -> np.ndarray:
    """Avoid 360-degree jumps between frames (DCC curve editors and filters hate them)."""
    return np.degrees(np.unwrap(np.radians(e), axis=0))
