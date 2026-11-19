---
name: animate
description: Rigging, mocap cleanup, procedural bpy animation, visual motion-strip QA, tiered Swarm review, and Godot 4 SkeletonProfileHumanoid retargeting using UniRig, AccuRIG, Mixamo, and headless Blender GLB export.
metadata:
  icon: activity
---

# Character Rigging & Animation Skill (`/animate`)

Standardizes humanoid/creature rigging, mocap clip cleanup, procedural `bpy` animation, visual keyframe contact-sheet QA, and 60 FPS Godot 4 `AnimationLibrary` / `AnimationTree` setup.

## Activation
- Slash command: `/animate`
- Mention: `@animate`
- Prompt: `rig character`, `retarget animation`, `mixamo to godot`, `animate prop`

---

## Execution Tier & Swarm Policy
- **Solo (Default — 1 clip or simple mechanical prop)**: 1 agent authors/cleans clip + inspects 5-frame motion strip (`render_qa_sheet.py anim` or Blender MCP `look`).
- **Swarm — Multi-Clip Pack or Hero Rig**:
  - `animator` (owns rig, keyframes, and NLA assembly) + `critic` (inspects rendered 5-frame motion strips against the Motion Anti-Slop Checklist for clipping, knee flips, foot sliding, and loop seam pops).
  - For large clip packs (`>= 4` clips), parallel headless `clip-*` workers author independent action scripts/FBX cleanups -> `animator` merges into one `.glb` -> `critic` verifies all strips.
- **Hard Rule**: Never run 2 workers concurrently on live Blender MCP (`execute_blender_code`). Serialize live viewport work through 1 `animator`.

---

## Track Decision (Ask 1 Tight Round)
Confirm track + specs with defaults before rigging/scripting:
1. **Track**: `Track A (Humanoid/Creature Character)` vs `Track B (Mechanical/Prop/Creature via Blender bpy)`.
2. **Execution Tier**: `Solo` (1–2 clips) vs `Swarm` (Hero rig or `>= 4` clip pack).
3. **Clip List & Timing**: e.g. `idle` (loop), `walk` (loop, in-place), `run` (loop, in-place), `attack` (one-shot), `hit_react` (one-shot).
4. **Root Motion**: `In-Place` (Godot `CharacterBody3D` drives velocity — default) vs `Root Motion` (extracted to ground `Root` bone `Y=0`).
5. **Target Auto-Rigger (Track A)**:
   - `AccuRIG`: Fast default for clean A-pose humanoids (`bella_hero` style).
   - `UniRig / SkinTokens`: Preferred for non-humanoids, creatures, quadrupeds, or asymmetric AI topologies where AccuRIG markers fail.
   - `Mixamo`: Clean T-pose humanoids + standard mocap library clips.

---

## Track A: Humanoid / Creature Rigging & Mocap Pipeline

### 1. Pre-Rig Mesh Gate (Fixes Auto-Rig Slop)
Before uploading TRELLIS/AI meshes to UniRig, AccuRIG, or Mixamo:
- Tri count `6,000–12,000`, remove doubles (`dist <= 0.0005`), recalculate outward normals.
- Orientation: facing `-Y` in Blender (`-Z` in Godot), feet resting cleanly at `Z = 0` (`Y = 0` in Godot), uniform scale `1.0`.
- **De-fuse limbs**: Thighs, armpits, and fingers MUST have clearance gaps. If fingers are fused into mittens, map as 1-joint mitten or separate toes/fingers in Blender first.
- **Detach rigid gear**: Holsters, pouches, helmets, and weapons belong on `BoneAttachment3D` in Godot — remove from skinned body mesh to avoid rubbery bending.

### 2. Auto-Rigging & Clip Capture
- **A-Pose Humanoid**: **AccuRIG** -> set shoulder/wrist/elbow/hip/knee/ankle markers -> export base FBX (`With Skin`, T-pose rest or A-pose preserved).
- **Non-Humanoid / Creature / Weird Topology**: **UniRig / SkinTokens** -> predict skeleton hierarchy -> inspect bone placement in Blender before committing skin weights -> export `.glb`/`.fbx`.
- **T-Pose Humanoid**: **Mixamo** (`mixamo.com`).
  - Base character: `With Skin`.
  - Animation clips: `Without Skin`, `60 fps`, `Keyframe Reduction: Uniform`.
  - **CRITICAL**: Check **`In Place`** on `walk` / `run` / `strafe` clips (unless explicitly using root-motion extraction) to prevent rubber-band snapping on loop reset.

### 3. Headless Blender Cleanup -> Single `AnimationLibrary` `.glb`
Never export the full character mesh 10 times for 10 clips. Combine all animations onto ONE rig using `tools/blender/common/armature.py` + `tools/blender/common/exporter.py`:
1. Import base rigged `.fbx`/`.glb` once (`Ctrl+A` -> apply Rotation & Scale if needed).
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

### Motion Anti-Slop Checklist (For `bpy` Keyframes & Critic Review)
- **No linear robotic arcs**: Use `BEZIER` interpolation with ease-in/ease-out; reserve `LINEAR` only for continuous spinning motors/fans.
- **Anticipation & Follow-Through**: Heavy doors, valves, levers, and melee swings need `2–4` frames windup and `5–10%` settle overshoot at stops.
- **Weight Shift & Overlap**: On bipeds/creatures, hips lead chest by `2–3` frames, arms counter-rotate shoulders, head stabilizes gaze.
- **Foot Lock**: Planted foot world position stays flat on floor `Y = 0` throughout stance phase (zero ice-skating).

---

## Mandatory Visual Motion-Strip QA Gate
Before importing `.glb` into Godot, render a 5-frame (`0%, 25%, 50%, 75%, 100%`) contact strip for each key clip (or inspect poses via Blender MCP `look`) and verify with `read_file`:
```bash
/snap/bin/blender --background --python tools/blender/render_qa_sheet.py -- \
  anim --input assets/models/<slug>/<slug>.glb \
  --action <clip_name> \
  --output /tmp/<slug>_<clip_name>_qa.png
```
**Reject and fix** if limbs clip through torso/floor, knees/elbows invert, rest pose explodes, or loop start/end poses visibly jump. Delete `/tmp/<slug>_<clip_name>_qa.png` after pass.

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
