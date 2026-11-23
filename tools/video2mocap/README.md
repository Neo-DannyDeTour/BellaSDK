# video2mocap

**Video → production-quality skeletal animation for Blender and Unreal Engine.**
Multi-person, world-grounded, foot-locked, and reviewable by a human *or an AI agent* that can look at
key frames and correct the motion with precise, declarative edits.

<p align="center">
  <img src="docs/media/viewer-walk.gif" alt="Solved walk cycle in the video2mocap web viewer" width="520"><br>
  <sub>A walk solved from a single video, played back in the built-in web viewer (<code>v2m view</code>). Green = foot in contact with the ground.</sub>
</p>

Built first for **cinematics**: scenes with one or several characters interacting (a hug, a
goodbye, carrying someone, a conversation), recorded with a phone and turned into animation that
keeps the timing and intent of the performance.

> Status: **early (v0.2)**. Video → per-person animation works end to end with NVIDIA GEM-X,
> with post-processing, review sheets, a web viewer and BVH/FBX export. Fingers and faces are next.

## Why another one?

Video mocap tools exist (Move.ai, QuickMagic, DeepMotion, Rokoko Vision, FreeMoCap, …) but either
they are closed/cloud, or the open research models behind them (WHAM, GVHMR, TRAM, PromptHMR…) are
built on the SMPL body model and research datasets whose licenses **forbid commercial use**. Games
need motion they can ship. Our goals, in order:

1. **Faithful.** The animation must be what the video shows: no foot skating, no jitter, correct
   world trajectory and root motion. Quality is measured, not eyeballed (see *Metrics*).
2. **License-clean by default.** The default pipeline only uses code and weights that allow
   commercial use. Research-only backends can be plugged in, but are clearly marked.
3. **Multi-person.** Every person in the video gets their own track and animation, in one shared
   world frame.
4. **Correctable.** Every result comes with key-frame review sheets and can be fixed with a JSON list
   of edits that is applied deterministically and recorded in the file's history.
5. **Engine-ready.** BVH and FBX that import cleanly in Blender and Unreal (verified by an automated
   round-trip test), plus Unreal retargeting helpers.

## Pipeline

```
video ─► detect + track people ─► per-person 3D estimator (backend) ─► raw motion (.npz)
                                                                          │
           ┌──────────────────────────────────────────────────────────────┘
           ▼
   smooth (zero-phase) ─► contacts ─► ground ─► foot lock (IK) ─► metrics
           │
           ▼
   key-frame review sheet (video + skeleton overlay, front/side views)
           │            ▲
           ▼            │  edits.json  (human or AI reviewer)
       apply edits ─────┘
           │
           ▼
   BVH ─► Blender ─► FBX ─► Unreal (IK Retargeter → your skeleton)
```

The estimator always sees **every** frame (temporal models need dense input; that is what keeps the
motion faithful). *Key frames* are chosen for **review**: extreme poses, low-confidence frames and
frames with high reprojection error.

## Backends

| Backend | Code / weights / body model | Commercial use | Notes |
|---|---|---|---|
| **GEM-X** (NVIDIA, default) | Apache-2.0 / NVIDIA Open Model License / SOMA (Apache-2.0) | ✅ | 77 joints incl. hands & face, world-space, moving camera. Its image-feature stage uses SAM-3D-Body weights (SAM License — read the note in [docs/LICENSES.md](docs/LICENSES.md)); a keypoint-only mode avoids them. |
| research backends (planned: GVHMR, PromptHMR) | SMPL/SMPL-X based | ❌ research only | For comparison and prototyping. Outputs are tagged `license: research-only`. |

See [docs/RESEARCH.md](docs/RESEARCH.md) for the full survey (2024–2026) and why we chose this.

## Quick start

### 1. Install
```bash
# core (Windows / Linux / macOS), Python 3.10+
uv venv && uv pip install -e ".[dev,video]"
pytest

# GEM-X backend (Linux, or WSL2 on Windows, NVIDIA GPU with 8 GB+). No sudo needed.
bash backends/gemx/install_wsl.sh          # inside WSL / Linux
```
Blender (for FBX export) is auto-detected, or set `BLENDER=/path/to/blender`.

### 2. Video → animation
```bash
v2m run my_clip.mp4 --out runs/my_clip --fbx
```
- Every person in the video is detected, tracked and solved separately, then placed in one shared
  world (static camera).
- `--fast` skips the SAM-3D-Body image features: much less GPU/RAM, lower quality.
- `--max-people N` limits how many people are solved (largest/longest first).

Output (`runs/my_clip/`):
```
run.json, summary.json           what was found, metrics per person
track_00/  track_01/ ...         one folder per person
  clean.npz                      clean motion (v2m format)
  clean.bvh / clean.fbx          for Blender / Unreal
  metrics.json                   raw vs final: foot skate, jitter, ground penetration, reprojection px
  review.png                     key-frame review sheet (video + projected skeleton, front/side views)
  clip.mp4, motion_raw.npz       the person's clip and the raw estimator output
```

### 3. Look at it
```bash
v2m view runs/my_clip        # opens http://127.0.0.1:8765
```
The viewer shows the source video with a coloured stick figure on every person and, next to it, the
3D animation of everyone in the same world, in sync. Click a person's chip to hide/show it; space =
play/pause, ←/→ = frame by frame, `1×/0.5×/0.25×` = speed; drag to orbit the 3D view. Feet in
contact with the ground light up green.

**Keyframe editor** (same page): go to a frame, click a joint in the 3D view and rotate it with the
gizmo (`R`); the hips can also be moved (`T`). Each change becomes a keyframe that eases in/out over
"Transición" frames, previewed live in 3D *and* over the video. Keyframes are listed (click to jump,
✕ to delete) and marked on the timeline; `Ctrl+Z` undoes. **Guardar** writes, per person,
`edits.json` (the same edit format as `v2m edit`) plus `edited.npz` and `edited.bvh`.

### 4. Face (expressions)
Faces come from MediaPipe Face Landmarker (Apache-2.0): 52 ARKit-style curves per frame (brows, eyes,
blinks, jaw, lips, cheeks…) plus head rotation. CPU only.

**Recommended: a separate face take** (phone in front of your face, face filling the frame, even
light, sound on, **clap at the start** of both the body and the face take):
```bash
v2m face capture face_take.mp4 --out runs/my_clip/face_take.npz
v2m face attach runs/my_clip --person 0 --take runs/my_clip/face_take.npz          # syncs by clap/audio
v2m face attach runs/my_clip --person 0 --take ... --offset 1.25 --time-scale 1.0  # or set it by hand
```
The body keeps the head's overall orientation; the face take adds the expression curves and the
small head motion on top. **From the body video itself** (head crops, only when faces are visible
enough): `v2m face from-body runs/my_clip --person 0`.
Each person gets `face.npz` and `face_curves.csv` (frame × 52 curves); the viewer shows a live face
panel for the selected person.

### 5. Fix and export
```bash
v2m edit   runs/my_clip/track_00/clean.npz edits.json --out fixed.npz   # see docs/REVIEW_LOOP.md
v2m export fixed.npz --bvh fixed.bvh --fbx fixed.fbx
```

### Tips for recording
- Tripod or a still phone (moving cameras are not supported yet).
- Whole bodies in frame, **feet visible**, good light; people crossing in front of each other is
  the hardest case.
- For faces and fingers, get closer (see [docs/ROADMAP.md](docs/ROADMAP.md)).

### Hardware notes
Tested on an RTX 3050 (8 GB) + 16 GB RAM through WSL2: ~5 min per 10 s of video per person, peaks
close to the RAM limit, so close heavy apps while it runs.

## Metrics

Every run writes `metrics.json` (raw → before foot-lock → final):

| metric | meaning |
|---|---|
| `foot_skate_cm_s` | horizontal speed of feet while in contact (0 = perfect) |
| `jitter_m_s3` | mean jerk of all joints (compare runs; lower = smoother) |
| `hf_energy_ratio` | share of motion energy above 12 Hz (estimator noise lives there) |
| `penetration_ratio` | frames with a foot more than 1 cm under the ground |
| `reproj_px` | 2D reprojection error against detected keypoints (faithfulness to the video) |

Tests use synthetic motions with known ground truth, e.g. a clean motion must come out of the
filters essentially unchanged (< 1.5 cm anywhere), and foot locking must reduce skating by > 10× on a
drifting stance.

## The review loop (human or AI)

`v2m review` renders a contact sheet of key frames. A reviewer compares them with the video and
writes edits:

```json
[
  {"op": "rotate", "joint": "LeftForeArm", "frames": [118, 126], "euler_deg": [0, 0, -12], "falloff": 6,
   "note": "elbow over-bent vs video at f120"},
  {"op": "set_contact", "joint": "LeftToeBase", "frames": [200, 231], "value": true},
  {"op": "trim", "frames": [12, 640]}
]
```

Edits ease in/out (`falloff`) so they never pop, and each one is stored in the motion's history.
See [docs/REVIEW_LOOP.md](docs/REVIEW_LOOP.md).

## Repository layout

```
src/video2mocap/   core library (motion format, filters, contacts, IK, foot lock, edits, QA, BVH, CLI)
backends/gemx/     installer + runner for NVIDIA GEM-X (runs in its own venv, Linux/WSL2)
scripts/blender/   headless Blender scripts (BVH→FBX, verification)
scripts/unreal/    Unreal Editor Python helpers (import + retarget)
tests/             unit + integration tests (synthetic ground truth, Blender round-trip)
docs/              research survey, architecture, licenses, review loop
```

## License

Apache-2.0 for this repository. Backends and model weights keep their own licenses — see
[docs/LICENSES.md](docs/LICENSES.md). You are responsible for checking them for your use.
