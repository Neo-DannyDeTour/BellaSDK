# Godiva Mocap Pipeline

Drop `.fbx`, `.bvh`, or `.glb` animation clips into `assets/mocap/godiva/`.
Filename stem maps directly to Godot clip name (e.g., `walk.fbx` -> `walk`, `run.bvh` -> `run`).
Existing clips in `assets/models/godiva/godiva_rigged.glb` not overridden here stay preserved.

## 1. Mixamo `.fbx` Drops

1. Export from Mixamo as **FBX Binary (.fbx)**, **Without Skin** (or With Skin), **60 FPS**, **In Place** for loops.
2. Rename file to target Godot clip name (e.g., `assets/mocap/godiva/walk.fbx`, `run.fbx`, `idle.fbx`, `crouch_walk.fbx`).
3. Retarget onto Godiva:

```bash
/snap/bin/blender --background --python tools/blender/retarget_godiva_mocap.py -- \
  --mocap-dir assets/mocap/godiva \
  --output assets/models/godiva/godiva_rigged.glb
```

Optional filename remapping via `--clip-map map.json` (e.g., `{"Walking_In_Place": "walk"}`).

## 2. Rokoko Video `.fbx` Drops

1. Export animation from Rokoko Video / Studio as **FBX (Mixamo or Newton/Humanoid skeleton)** at **60 FPS**.
2. Place `.fbx` in `assets/mocap/godiva/<clip_name>.fbx`.
3. Run retargeter:

```bash
/snap/bin/blender --background --python tools/blender/retarget_godiva_mocap.py -- \
  --mocap-dir assets/mocap/godiva \
  --output assets/models/godiva/godiva_rigged.glb
```

## 3. Local Ubuntu Video-to-BVH (`video_to_bvh.py`)

Convert any local `.mp4` reference video into a standard `.bvh` via MediaPipe PoseLandmarker (runs locally in `.venv_mocap`), then retarget onto Godiva:

```bash
.venv_mocap/bin/python tools/scripts/video_to_bvh.py \
  --input /path/to/reference.mp4 \
  --output assets/mocap/godiva/walk.bvh \
  --fps 60 \
  --smooth 0.35

/snap/bin/blender --background --python tools/blender/retarget_godiva_mocap.py -- \
  --mocap-dir assets/mocap/godiva \
  --output assets/models/godiva/godiva_rigged.glb
```

## Retargeting Behavior

- **In-Place Root XY Zeroing**: Automatically applied to `idle`, `walk`, `run`, `crouch_idle`, `crouch_walk`, `prone_idle`, `prone_crawl`, `wall_hug_idle`, `sidestep_left`, `sidestep_right`.
- **Loop Seam Trimming**: Cyclic clips trim duplicate wrap frame (`N-1`).
- **Height Scaling**: Hip vertical translation scales automatically by Godiva / source leg-length ratio.
- **Arm Rest Alignment**: T-pose source rigs compensate cleanly onto Godiva's A-pose rest rig.
