---
name: animate
description: Rigging, mocap cleanup, and Godot 4 SkeletonProfileHumanoid retargeting pipeline using Mixamo, AccuRIG, and Blender GLB export.
metadata:
  icon: activity
---

# Character Rigging & Animation Skill (`/animate`)

Standardizes humanoid rigging, mocap clip cleanup, and 60 FPS Godot 4 retargeting.

## Activation
- Slash command: `/animate`
- Mention: `@animate`
- Prompt: `rig character`, `retarget animation`, `mixamo to godot`

---

## Pipeline

### 1. Auto-Rigging & Mocap Source
- **Standard Humanoid**: Upload `.obj`/`.fbx` T-pose mesh to **Mixamo** (`mixamo.com`). Download `.fbx` (`With Skin` for base rig, `Without Skin` for animation clips, `60 fps`, `Keyframe Reduction: Uniform`).
- **Stylized / Non-Standard Proportions**: Use **AccuRIG** (free desktop) for cleaner joint placement and weights, then export `.fbx`.

### 2. Blender Cleanup -> `.glb`
1. Import base `.fbx` and animation `.fbx` clips into Blender.
2. Apply transforms (`Ctrl+A` -> Rotation & Scale), ensure `Y-up` / `-Z forward` orientation.
3. Push each clip to NLA tracks (strip naming: `idle`, `walk`, `run`, `jump`, `attack`).
4. Export single `.glb` (`+Y Up`, `Apply Modifiers`, `NLA Strips` enabled, `Skinning` enabled).

### 3. Godot 4 Retargeting (`SkeletonProfileHumanoid`)
1. Double-click imported `.glb` in Godot FileSystem -> **Import** dock.
2. Select `Skeleton3D` node -> **Retarget** -> `Bone Map`: New `BoneMap` -> `Profile`: `SkeletonProfileHumanoid`.
3. Verify bone mapping (green = mapped). Fix any unmapped twist/finger bones.
4. Enable **Loop Mode** (`Linear`) on cyclic clips (`idle`, `walk`, `run`).
5. Click **Reimport**.

### 4. 60 FPS `AnimationTree` Rules
- Use `AnimationTree` with `AnimationNodeStateMachine` or `BlendSpace1D`/`2D` — never poll or swap animations manually in `_process()`.
- Gate distant character `AnimationTree` updates using `VisibleOnScreenNotifier3D` or `distance_squared_to()` checks.
- Trigger discrete SFX/VFX via **Call Method Tracks** inside the animation timeline, routed through `AudioPool.play_sfx_3d()`.
