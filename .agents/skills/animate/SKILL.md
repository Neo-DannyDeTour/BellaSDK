---
name: animate
description: Rigging, mocap cleanup, procedural bpy animation, and Godot 4 SkeletonProfileHumanoid retargeting pipeline using AccuRIG, Mixamo, and headless Blender GLB export.
metadata:
  icon: activity
---

# Character Rigging & Animation Skill (`/animate`)

Standardizes humanoid rigging, mocap clip cleanup, procedural `bpy` animation, and 60 FPS Godot 4 `AnimationLibrary` / `AnimationTree` setup.

## Activation
- Slash command: `/animate`
- Mention: `@animate`
- Prompt: `rig character`, `retarget animation`, `mixamo to godot`, `animate prop`

---

## Track Decision (Ask 1 Tight Round)
Confirm track + specs with defaults before rigging/scripting:
1. **Track**: `Track A (Humanoid Character)` vs `Track B (Mechanical/Prop/Creature via Blender bpy)`.
2. **Clip List & Timing**: e.g. `idle` (loop), `walk` (loop, in-place), `run` (loop, in-place), `attack` (one-shot), `hit_react` (one-shot).
3. **Root Motion**: `In-Place` (Godot `CharacterBody3D` drives velocity — default) vs `Root Motion` (extracted to ground `Root` bone `Y=0`).
4. **Target Rig**: `AccuRIG` (A-pose AI/TRELLIS meshes) vs `Mixamo` (clean T-pose meshes).

---

## Track A: Humanoid Rigging & Mocap Pipeline

### 1. Pre-Rig Mesh Gate (Fixes Auto-Rig Slop)
Before uploading TRELLIS/AI meshes to AccuRIG or Mixamo:
- Tri count `6,000–12,000`, remove doubles (`dist <= 0.0005`), recalculate outward normals.
- Orientation: facing `-Y` in Blender (`-Z` in Godot), feet resting cleanly at `Z = 0` (`Y = 0` in Godot), uniform scale `1.0`.
- **De-fuse limbs**: Thighs, armpits, and fingers MUST have clearance gaps. If fingers are fused into mittens, map as 1-joint mitten or separate toes/fingers in Blender first.
- **Detach rigid gear**: Holsters, pouches, helmets, and weapons belong on `BoneAttachment3D` in Godot — remove from skinned body mesh to avoid rubbery bending.

### 2. Auto-Rigging & Clip Capture
- **A-Pose (`bella_hero` style)**: Use **AccuRIG** (free desktop) -> set shoulder/wrist/elbow/hip/knee/ankle markers -> export base FBX (`With Skin`, T-pose rest or A-pose preserved).
- **T-Pose**: Upload `.fbx`/`.obj` to **Mixamo** (`mixamo.com`).
  - Base character: `With Skin`.
  - Animation clips: `Without Skin`, `60 fps`, `Keyframe Reduction: Uniform`.
  - **CRITICAL**: Check **`In Place`** on `walk` / `run` / `strafe` clips (unless explicitly using root-motion extraction) to prevent rubber-band snapping on loop reset.

### 3. Headless Blender Cleanup -> Single `AnimationLibrary` `.glb`
Never export the full character mesh 10 times for 10 clips. Combine all animations onto ONE rig using `tools/blender/common/armature.py` + `tools/blender/common/exporter.py`:
1. Import base rigged `.fbx` once (`Ctrl+A` -> apply Rotation & Scale if needed).
2. Import each animation `.fbx`, retarget/copy `Action` to base armature, delete temporary duplicate armatures.
3. **Loop Seam Trim (Anti-Hitch Rule)**: For cyclic clips (`idle`, `walk`, `run`), `frame_end = original_end - 1` because frame `0` and frame `N` are identical poses (keeping both causes a 2-frame stutter every loop!).
4. Push each cleaned action to an NLA track via `push_action_to_nla(arm_obj, action, track_name=clip_name)`.
5. Export one `.glb` via `export_godot_glb(filepath, export_animations=True)`.

### 4. Godot 4 `SkeletonProfileHumanoid` Retargeting
1. Double-click `.glb` in Godot FileSystem -> **Import** dock.
2. Select `Skeleton3D` -> **Retarget** -> assign shared `BoneMap` resource (`SkeletonProfileHumanoid`) and save it as `.tres` so future packs reuse the same map.
3. Verify all primary bones map green; check `Fix Silhouette` if A-pose -> T-pose shoulder offsets twist.
4. Set `Loop Mode = Linear` on cyclic tracks (`idle`, `walk`, `run`), keep `None` on one-shots (`jump`, `attack`, `death`).
5. **Reimport** -> extract animations into a shared `AnimationLibrary` `.res` for modular player/enemy scenes.

---

## Track B: Mechanical / Creature / Interactive Props (`bpy`)

Use headless Blender pipeline instead of manual keyframes when building doors, valves, turrets, pistons, or custom rigs:
```bash
python3 tools/blender/run.py <generator_script>
```
Reuse [armature.py](file:///home/dkd/Documents/BellaSDK/tools/blender/common/armature.py) (`create_armature`, `add_bone`, `parent_mesh_to_armature`, `create_action`, `push_action_to_nla`) and [exporter.py](file:///home/dkd/Documents/BellaSDK/tools/blender/common/exporter.py) (`export_godot_glb`).

### Motion Anti-Slop Checklist (For `bpy` Keyframes & Review)
- **No linear robotic arcs**: Use `BEZIER` interpolation with ease-in/ease-out; reserve `LINEAR` only for continuous spinning motors/fans.
- **Anticipation & Follow-Through**: Heavy doors, valves, levers, and melee swings need `2–4` frames windup and `5–10%` settle overshoot at stops.
- **Weight Shift & Overlap**: On bipeds/creatures, hips lead chest by `2–3` frames, arms counter-rotate shoulders, head stabilizes gaze.
- **Foot Lock**: Planted foot world position stays flat on floor `Y = 0` throughout stance phase (zero ice-skating).

---

## Prompt Templates (Motion Specs & Video-to-Mocap Reference)

### Template A: `bpy` Procedural / Keyframe Action Prompt
```text
Animate [RIG/PROP NAME] in Blender 5.3 using tools/blender/common/armature.py + exporter.py at 60 FPS:
- Clips: [clip_name: frames, loop=true/false]
- Mechanics: [e.g. heavy iron lever pulls down 45 deg over 14 frames with 3-frame resistance anticipation, snaps past latch, rebounds 4 deg and settles over 8 frames]
- Axis & Pivot: [hinge axis, bottom-center origin, +Y up / -Z forward in Godot]
- Interpolation: Bezier ease-in/out on impacts, trim duplicate loop end frame (N-1), push all actions to NLA strips, export single GLB.
```

### Template B: AI Video Reference Prompt (For Video-to-Mocap / Pose Reference)
```text
Full-body motion study of a single [CHARACTER/SOLDIER] performing [EXACT ACTION, e.g. cautious crouched tactical walk holding heavy rifle], locked static tripod camera at chest height, clean three-quarter front view showing full body from head to boots with generous floor margin, flat studio gray background, steady uniform tempo, zero camera pan, zero zoom, zero cuts, crisp silhouette with clear foot contacts on flat ground.
```

---

## 60 FPS Godot `AnimationTree` Rules
- Drive transitions via `AnimationTree` (`AnimationNodeStateMachine` + `BlendSpace1D`/`2D` with `0.10–0.18s` crossfade) — never manually swap animations in `_process()`.
- Gate distant `AnimationTree` evaluation via `VisibleOnScreenNotifier3D` or `distance_squared_to()` checks.
- Trigger footsteps, mechanical clunks, and hitboxes via **Call Method Tracks** inside the clip -> route audio through `AudioPool.play_sfx_3d()`.
