# Survey: monocular video → 3D human motion (state as of October 2026)

Goal: faithful, multi-person, world-grounded motion that a commercial game can ship.

## Findings

1. **Almost every strong open model is unusable commercially.** WHAM, TRAM, GVHMR, PromptHMR,
   CoMotion, NLF, Multi-HMR, 4DHumans/PHALP, SLAHMR, TokenHMR, MotionBERT depend on SMPL/SMPL-X
   (non-commercial body models) and/or were trained on AMASS, BEDLAM, H36M or 3DPW (research-only).
2. **NVIDIA GEM-X (March 2026) is the exception.** Apache-2.0 code, NVIDIA Open Model License weights,
   trained only on NVIDIA-owned synthetic data, SOMA body model (Apache-2.0). It predicts 77 joints
   (body, hands, face) in camera and world space from monocular video with a moving camera
   (built-in visual odometry, or `--static_cam`). It ships an ONNX/TensorRT path.
   - Its demo processes **one track per run**. Multi-person is our job: detect + track everyone,
     run the model per track, then express all tracks in the same world frame (they share the
     camera trajectory).
   - Officially Linux/macOS; we run it in WSL2 on Windows.
3. **Meta SAM 3D Body (Nov 2025)**: per-image, multi-person, MHR body model (Apache-2.0), SAM License
   (commercial allowed with a weapons/military exclusion). GEM-X uses its image features.
4. **MetaHuman Animator Markerless Mocap plugin (June 2026)**: free, local, commercial, outputs
   directly on the MetaHuman skeleton, but UE 5.8 only, single person, static camera. A useful
   reference to compare against for single-person clips.
5. **Commercial tools** (Move.ai, QuickMagic, DeepMotion, Rokoko Vision, Plask) are closed; none lets
   an agent inspect and correct poses with precise edits.

## Quality: what actually makes video mocap look bad, and what we do

| Artefact | Cause | Our treatment |
|---|---|---|
| Foot skating | per-frame errors in root + legs | contact detection (hysteresis, low-passed decision signal) + two-bone IK that pins the **contact point** with eased blends; the ankle follows the foot's own orientation so heel-off is preserved |
| Jitter | per-frame estimation noise | zero-phase Butterworth (filtfilt) with conservative, per-joint-group cut-offs; extremities keep more bandwidth |
| Floating / sinking | unknown ground | ground from stance contacts; stance feet snapped to y=0 |
| Stretching limbs | position-based outputs | impossible by construction: our format is rotations + fixed bone offsets |
| Wrong pose in hard frames | occlusion, ambiguity | key-frame review sheets + declarative edits with falloff |
| Lost identity in multi-person | tracker switches | tracking + per-track review; manual merge/split edits (planned) |

Learned smoothers (SmoothNet…) and physics refiners (PhysPT, PHC) are trained on non-commercial data,
so they are excluded from the default pipeline. Kimodo (NVIDIA) has SOMA weights under the NVIDIA
Open Model License and is a candidate motion prior for a later version.

## Should we train our own model?

Not now. Training a GEM-X-class model from scratch takes several A100s for days, far beyond an 8 GB
consumer GPU. The realistic path, if we need it later, is **fine-tuning GEM-X** (its license allows
derivatives) on synthetic data we render ourselves in Unreal with license-clean bodies (Anny /
MakeHuman CC0, SOMA) and license-clean motion (our own captures, CMU mocap, commercially licensed
sets). MetaHuman assets must **not** be used as training data (their license has prohibited it).

## Sources

- GEM-X: https://github.com/NVlabs/GEM-X · weights https://huggingface.co/nvidia/GEM-X
- SOMA-X: https://github.com/NVlabs/SOMA-X · soma-retargeter: https://github.com/NVIDIA/soma-retargeter
- SAM 3D Body: https://github.com/facebookresearch/sam-3d-body · MHR: https://github.com/facebookresearch/MHR
- RTMPose/RTMW without mmcv: https://github.com/Tau-J/rtmlib
- GVHMR https://github.com/zju3dv/GVHMR · WHAM https://github.com/yohanshin/WHAM · TRAM https://github.com/yufu-wang/tram
- PromptHMR https://github.com/yufu-wang/PromptHMR · CoMotion https://github.com/apple/ml-comotion
- Anny body model: https://github.com/naver/anny · Kimodo: https://github.com/nv-tlabs/kimodo
- MetaHuman markerless plugin: https://www.cgchannel.com/2026/06/get-the-free-metahuman-animator-markerless-mocap-plugin/
