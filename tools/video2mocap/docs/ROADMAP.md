# Roadmap

Target: complete performances for cinematics — **body + fingers + face**, for one or several
characters — faithful to the video and editable.

## v0.1 (done)
- Neutral motion format, FK, BVH, FBX via Blender (round-trip verified < 0.5 mm)
- Zero-phase smoothing, contact detection, contact-point foot locking with IK
- Metrics, key-frame review sheets, declarative edits

## v0.2 — body from video (in progress)
- GEM-X backend in WSL2: detection + tracking of **all** people (GEM-X's demo keeps only the largest)
- One GEM-X pass per track; per-person SOMA skeleton with that person's proportions
- All tracks placed in one shared world frame (static camera first)
- Review sheets with the video frame + projected skeleton + 2D keypoints, reprojection error

## v0.3 — fingers
- GEM-X already predicts finger joints (SOMA 77 includes hands). Hands are small in a wide shot, so:
  - per-hand crops at full resolution, 2D finger keypoints with RTMW (Apache-2.0, 133 whole-body
    keypoints) for **verification** (reprojection error per finger)
  - refinement: optimise finger rotations against the 2D keypoints with joint limits and temporal
    smoothness (our own solver; no MANO, whose license is non-commercial)
  - review sheets with hand close-ups; edits can target fingers like any joint
- Recommended capture for hero shots: a second, closer camera on the hands (multi-view later)

## v0.4 — face (in progress: capture, sync, attach and viewer panel done; Unreal curve import and LLM fill-in next)
Two paths:
1. **MetaHuman Animator (mono video, Unreal 5.6+)** — best quality on MetaHuman faces. v2m exports,
   per person, a **stabilised, cropped face video** (from the head track) at the best available
   resolution, plus the timecode/frame offset so the face animation lines up with the body.
2. **Automatic ARKit-52 curves** — MediaPipe Face Landmarker blendshapes (code Apache-2.0; model-card license to be verified before use) per frame on
   the same face crops, filtered, exported as animation curves (CSV/JSON + FBX curves) that drive a
   MetaHuman through the ARKit mapping pose asset. Fast, fully automatic, editable like any curve.
- Gaze and head: eye/head rotation from the face track blended with the body's neck/head.
- **Separate face take** merged with the body (clap / audio sync, manual offset + time scale).
- **LLM fill-in** where the face is occluded or too small: a vision-language model reads key frames and
  scene context and writes *intent keyframes* (emotion, intensity, eyes, timing), converted to curves
  through an expression library with procedural blinks/breathing; every segment tagged
  `measured` / `generated`. The model also reviews measured curves against the video.
- Lip-sync from dialogue audio as a third source.
- Face review sheets: crop + detected landmarks + resulting curve values at key frames; edits on
  curves (`set_curve`, `scale_curve`) with falloff.

## v0.5 — interactions between characters
- Contact constraints between people (hands on shoulders, hugs, carrying): reviewer marks contact
  pairs, solver keeps them attached (IK) — monocular depth between people is the weakest point
- Relative placement refinement from contacts and ground plane

## Later
- Moving camera (visual odometry precomputed and fed to GEM-X)
- Unreal Editor helpers: import + IK Retargeter SOMA → Manny/UEFN/MetaHuman, LevelSequence assembly
- Fine-tuning on our own synthetic data (license-clean bodies only)
