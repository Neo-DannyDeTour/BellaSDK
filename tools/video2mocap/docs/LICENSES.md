# Licenses of everything the pipeline touches

This file is part of the product: a motion is only usable in a commercial game if **every** stage
that produced it allows it. Each output records which backend produced it (`meta.backend`,
`meta.license`).

Last reviewed: 2026-10-06. Not legal advice — re-check before shipping.

| Component | Role | License | Commercial? |
|---|---|---|---|
| video2mocap (this repo) | post-processing, review, export | Apache-2.0 | ✅ |
| [NVlabs/GEM-X](https://github.com/NVlabs/GEM-X) code | 3D estimator | Apache-2.0 | ✅ |
| GEM-X weights (`gem_soma.ckpt`, ONNX) | 3D estimator | [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/) | ✅ (derivatives allowed) |
| [SOMA-X](https://github.com/NVlabs/SOMA-X) body model | skeleton / mesh | Apache-2.0 | ✅ |
| [SAM 3D Body](https://github.com/facebookresearch/sam-3d-body) weights | image features inside GEM-X | SAM License | ⚠️ commercial use allowed, but the license excludes use for developing guns/illegal weapons and military/ITAR uses. Fictional weapons in a video game are very likely outside that exclusion, but have it read by counsel. GEM-X's `--no-imgfeat` mode skips these weights (keypoints only, lower quality). |
| YOLOX (detection) | person boxes | Apache-2.0 | ✅ |
| ByteTrack (tracking) | person identities | MIT | ✅ |
| [MHR](https://github.com/facebookresearch/MHR) | body model used by SAM 3D Body | Apache-2.0 | ✅ |
| Blender | BVH→FBX conversion (tool only) | GPL (does not apply to exported data) | ✅ |

## Not allowed in the default pipeline

| Component | Why |
|---|---|
| SMPL / SMPL-X / SMPL-H body models | non-commercial license (commercial only through Meshcapade/Epic) |
| WHAM, GVHMR, TRAM, PromptHMR, CoMotion, NLF, Multi-HMR, 4DHumans… | SMPL-based and/or non-commercial weights |
| AMASS, BEDLAM/BEDLAM2, Human3.6M, 3DPW | research-only datasets (matters for training) |
| Sapiens (Meta) | CC BY-NC |
| Ultralytics YOLOv8/11-pose | AGPL |
| MetaHuman assets as AI training data | the MetaHuman license has prohibited use for training/testing ML; do not use them to build training sets |

Research backends may be added behind an explicit flag; their outputs carry
`meta.license = "research-only"` and the exporters print a warning.
