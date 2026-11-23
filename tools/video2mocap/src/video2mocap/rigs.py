"""Rig profiles: which joints are legs/feet for a given source skeleton.
Post-processing is skeleton-agnostic; a profile only names the joints it needs."""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .motion import Skeleton
from .process.footlock import Leg


@dataclass
class RigProfile:
    name: str
    legs: list[Leg]
    contact_joints: list[str] = field(default_factory=list)

    def __post_init__(self):
        if not self.contact_joints:
            self.contact_joints = [leg.toe or leg.ankle for leg in self.legs]


# A small humanoid used by tests and examples (Y-up, metres, character faces +Z).
TEST_HUMANOID_NAMES = [
    "Hips", "Spine", "Chest", "Neck", "Head",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
    "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
    "LeftArm", "LeftForeArm", "LeftHand",
    "RightArm", "RightForeArm", "RightHand",
]
TEST_HUMANOID_PARENTS = [-1, 0, 1, 2, 3, 0, 5, 6, 7, 0, 9, 10, 11, 2, 13, 14, 2, 16, 17]
TEST_HUMANOID_OFFSETS = [
    [0, 0.95, 0], [0, 0.12, 0], [0, 0.25, 0], [0, 0.18, 0], [0, 0.12, 0],
    [0.09, -0.05, 0], [0, -0.42, 0], [0, -0.42, 0], [0, -0.07, 0.13],
    [-0.09, -0.05, 0], [0, -0.42, 0], [0, -0.42, 0], [0, -0.07, 0.13],
    [0.18, 0.12, 0], [0.28, 0, 0], [0.25, 0, 0],
    [-0.18, 0.12, 0], [-0.28, 0, 0], [-0.25, 0, 0],
]


def test_humanoid() -> Skeleton:
    return Skeleton(list(TEST_HUMANOID_NAMES), np.array(TEST_HUMANOID_PARENTS), np.array(TEST_HUMANOID_OFFSETS, float))


TEST_HUMANOID_PROFILE = RigProfile(
    "test_humanoid",
    legs=[Leg("LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"),
          Leg("RightUpLeg", "RightLeg", "RightFoot", "RightToeBase")],
)

# NVIDIA SOMA (GEM-X), 77 joints after dropping the dummy "Root". Beware the naming: in SOMA
# "LeftLeg" is the THIGH and "LeftShin" the knee/lower leg (Mixamo uses LeftUpLeg/LeftLeg).
SOMA77_PROFILE = RigProfile(
    "soma77",
    legs=[Leg("LeftLeg", "LeftShin", "LeftFoot", "LeftToeBase"),
          Leg("RightLeg", "RightShin", "RightFoot", "RightToeBase")],
)

PROFILES: dict[str, RigProfile] = {p.name: p for p in (TEST_HUMANOID_PROFILE, SOMA77_PROFILE)}
