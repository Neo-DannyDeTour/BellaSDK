"""Post-processing pipeline: raw estimator motion -> clean, grounded, skate-free motion.

Order matters:
1. smooth          remove estimator jitter (conservative, zero-phase)
2. contacts        detect stance on the smoothed motion (raw jitter causes false contacts)
3. ground          put stance feet on y=0
4. foot lock       pin planted feet with IK, eased in/out
5. metrics         before/after numbers for every run
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .motion import Motion
from .process.contacts import ContactConfig, detect_contacts
from .process.filters import SmoothingConfig, smooth_motion
from .process.footlock import FootLockConfig, lock_feet, place_on_ground
from .qa.metrics import report
from .rigs import RigProfile


@dataclass
class PostConfig:
    smoothing: SmoothingConfig = field(default_factory=SmoothingConfig)
    contacts: ContactConfig = field(default_factory=ContactConfig)
    foot_lock: FootLockConfig = field(default_factory=FootLockConfig)
    do_smooth: bool = True
    do_ground: bool = True
    do_foot_lock: bool = True


def postprocess(raw: Motion, rig: RigProfile, cfg: PostConfig | None = None) -> tuple[Motion, dict]:
    cfg = cfg or PostConfig()
    m = smooth_motion(raw, cfg.smoothing) if cfg.do_smooth else raw.copy()
    contacts = detect_contacts(m, rig.contact_joints, cfg.contacts)
    m.contacts = contacts
    ground = None
    if cfg.do_ground:
        m, ground = place_on_ground(m, rig.contact_joints, contacts)
    before = report(m, ground or 0.0)
    if cfg.do_foot_lock:
        m = lock_feet(m, rig.legs, contacts, cfg.foot_lock, ground_height=ground)
    raw_eval = raw.copy()
    raw_eval.contacts = contacts
    metrics = {"raw": report(raw_eval), "before_foot_lock": before, "final": report(m, ground or 0.0)}
    return m, metrics
