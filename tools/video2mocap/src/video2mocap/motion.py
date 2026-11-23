"""The neutral motion format every stage reads and writes.

A `Motion` is a skeleton (hierarchy + rest offsets) plus, per frame, the root translation and the
local rotation of every joint. Bone lengths are therefore constant by construction: a recovered
motion can never stretch limbs.

Internal convention: right-handed, +Y up, metres, quaternions (w,x,y,z). No facing direction is
assumed.
Exporters convert to each target's convention.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

from . import quat

FORMAT_VERSION = 1


@dataclass
class Skeleton:
    names: list[str]
    parents: np.ndarray  # (J,) int, -1 for root; parents[j] < j is required
    offsets: np.ndarray  # (J,3) rest translation of each joint relative to its parent, metres
    rest_rot: np.ndarray | None = None  # (J,4) optional rest local rotation (pre-rotation)

    def __post_init__(self):
        self.parents = np.asarray(self.parents, dtype=int)
        self.offsets = np.asarray(self.offsets, dtype=float)
        if self.rest_rot is None:
            self.rest_rot = quat.identity((len(self.names),))
        assert self.parents[0] == -1, "joint 0 must be the root"
        assert all(self.parents[j] < j for j in range(1, len(self.names))), "parents must precede children"

    @property
    def num_joints(self) -> int:
        return len(self.names)

    def index(self, name: str) -> int:
        return self.names.index(name)

    def children(self, j: int) -> list[int]:
        return [c for c in range(self.num_joints) if self.parents[c] == j]

    def chain(self, end: str, length: int) -> list[int]:
        """Joint indices [ancestor_{length-1}, ..., parent, end]."""
        out = [self.index(end)]
        while len(out) < length:
            out.insert(0, int(self.parents[out[0]]))
        return out


@dataclass
class Motion:
    skeleton: Skeleton
    fps: float
    root_pos: np.ndarray  # (T,3) world position of the root joint, metres
    local_rot: np.ndarray  # (T,J,4) local joint rotations (applied after rest_rot)
    confidence: np.ndarray | None = None  # (T,J) in [0,1], from the estimator
    contacts: dict[str, np.ndarray] = field(default_factory=dict)  # joint name -> (T,) bool
    meta: dict = field(default_factory=dict)

    def __post_init__(self):
        self.root_pos = np.asarray(self.root_pos, dtype=float)
        self.local_rot = quat.normalize(np.asarray(self.local_rot, dtype=float))
        assert self.local_rot.shape[:2] == (self.root_pos.shape[0], self.skeleton.num_joints)

    @property
    def num_frames(self) -> int:
        return self.root_pos.shape[0]

    def copy(self) -> "Motion":
        return Motion(
            skeleton=self.skeleton,
            fps=self.fps,
            root_pos=self.root_pos.copy(),
            local_rot=self.local_rot.copy(),
            confidence=None if self.confidence is None else self.confidence.copy(),
            contacts={k: v.copy() for k, v in self.contacts.items()},
            meta=json.loads(json.dumps(self.meta)),
        )

    def fk(self) -> tuple[np.ndarray, np.ndarray]:
        """Forward kinematics -> (global positions (T,J,3), global rotations (T,J,4))."""
        sk = self.skeleton
        T, J = self.num_frames, sk.num_joints
        gpos = np.zeros((T, J, 3))
        grot = np.zeros((T, J, 4))
        loc = quat.mul(np.broadcast_to(sk.rest_rot, (T, J, 4)), self.local_rot)
        for j in range(J):
            p = sk.parents[j]
            if p < 0:
                grot[:, j] = loc[:, j]
                gpos[:, j] = self.root_pos
            else:
                grot[:, j] = quat.mul(grot[:, p], loc[:, j])
                gpos[:, j] = gpos[:, p] + quat.rotate(grot[:, p], np.broadcast_to(sk.offsets[j], (T, 3)))
        return gpos, grot

    # ---------------------------------------------------------------- persistence
    def save(self, path: str | Path) -> None:
        path = Path(path)
        sk = self.skeleton
        np.savez_compressed(
            path,
            format_version=FORMAT_VERSION,
            names=np.array(sk.names),
            parents=sk.parents,
            offsets=sk.offsets,
            rest_rot=sk.rest_rot,
            fps=self.fps,
            root_pos=self.root_pos,
            local_rot=self.local_rot,
            confidence=self.confidence if self.confidence is not None else np.zeros((0,)),
            contact_names=np.array(list(self.contacts.keys()), dtype=str),
            contacts=np.stack(list(self.contacts.values())) if self.contacts else np.zeros((0, 0), bool),
            meta=json.dumps(self.meta),
        )

    @classmethod
    def load(cls, path: str | Path) -> "Motion":
        d = np.load(path, allow_pickle=False)
        sk = Skeleton([str(n) for n in d["names"]], d["parents"], d["offsets"], d["rest_rot"])
        conf = d["confidence"]
        names = [str(n) for n in d["contact_names"]]
        return cls(
            skeleton=sk,
            fps=float(d["fps"]),
            root_pos=d["root_pos"],
            local_rot=d["local_rot"],
            confidence=conf if conf.size else None,
            contacts={n: d["contacts"][i].astype(bool) for i, n in enumerate(names)},
            meta=json.loads(str(d["meta"])),
        )
