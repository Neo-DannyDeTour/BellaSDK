## 2026-11-11T05:23:06Z
Headless Blender Mantaflow explosion simulation bake, 8x8 flipbook spritesheet assembly, and synchronized multi-emitter Godot 4 explosion hierarchy with screen-space heat distortion.

Working directory: /home/dkd/Documents/BellaSDK
Integrity mode: development

## Requirements

### R1. Environment Verification
Verify availability of CLI binaries: `blender`, `python3`, and `montage` (ImageMagick) or `ffmpeg`. If ImageMagick is missing, fall back to a Python Pillow script for spritesheet assembly.

### R2. Blender Headless Automation Script
Implement `tools/generate_explosion_flipbook.py` executable via `blender --background --python tools/generate_explosion_flipbook.py`:
- Clear default scene.
- Emitter: Sphere mesh (radius 0.4m) at origin. Mantaflow Flow Type = Fire + Smoke, Flow Behavior = Inflow (active frames 1 to 3 only, then shut off). Initial velocity: Normal = 8.0 m/s with Randomize = 2.5. Fuel amount = 1.8, Surface emission = 1.0.
- Mantaflow Domain: Cubic bounding box (6m x 6m x 6m) centered at (0, 0, 2.0m). Resolution divisions = 128. Time scale = 1.3. Fire settings: Reaction speed = 0.65, Flame smoke = 3.0, Vorticity = 0.45. Dissolve enabled, Time = 45, Slow dissolve checked. Cache type = ALL, Frame range = 1 to 64.
- Render & Material: Orthographic camera positioned at (0, -7.5m, 2.0m), Rotation (90°, 0°, 0°), Orthographic scale fitted to capture full expansion without edge clipping. Principled Volume Shader with blackbody intensity/emission driven by `flame` attribute and density driven by `density` attribute. Render engine: BLENDER_EEVEE_NEXT (fallback: CYCLES). Resolution: 256x256 per frame, PNG RGBA, `render.film_transparent = True`.
- Run simulation bake (`bpy.ops.ptcache.bake_all()`) and render 64 animation frames.

### R3. Spritesheet Assembly
Assemble the 64 rendered frames into an 8x8 grid (2048x2048 px total, transparent RGBA PNG) named `explosion_core_8x8.png` and output to `res://assets/vfx/explosion/explosion_core_8x8.png`.

### R4. Godot 4 Composite Explosion Hierarchy
Create root `Node3D` at `res://scenes/vfx/explosion_crysis.tscn` with controller script `res://scenes/vfx/explosion_crysis.gd` and synchronized child nodes:
- `CoreFireball` (GPUParticles3D): Amount = 1, Lifetime = 1.1s, one_shot = true, explosiveness = 1.0. QuadMesh (5.0m x 5.0m), unshaded StandardMaterial3D billboard using `res://assets/vfx/explosion/explosion_core_8x8.png` (H_frames = 8, V_frames = 8). ProcessMaterial with anim_speed = 1.0, rapid scale-up (1.0 -> 3.2), alpha fade-out during final 20%.
- `LingeringSmoke` (GPUParticles3D): Amount = 12, Lifetime = 3.5s, one_shot = true, explosiveness = 0.85. QuadMesh billboarded with soft particle blend. Initial radial velocity 3.0 m/s with linear damp = 4.0, gravity = Vector3(0, 0.8, 0).
- `SparksAndDebris` (GPUParticles3D): Amount = 60, Lifetime = 1.8s, one_shot = true, explosiveness = 0.98. QuadMesh (0.08m x 0.4m), particle billboard BILLBOARD_PARTICLES_ACCEL_Y. Unshaded StandardMaterial3D with HDR albedo Color(5.0, 2.2, 0.4, 1.0). Directional spread with +Z bias, initial velocity = 22.0 m/s, gravity = Vector3(0, -18.0, 0), collision mode = COLLIDE_RIGID (or ground bounce).
- `DetonationFlash` (OmniLight3D): Warm orange Color(1.0, 0.6, 0.2), Energy = 16.0, Range = 25.0m. Tween collapses energy from 16.0 to 0.0 in 0.15s.
- `HeatDistortion`: Child node utilizing `res://vfx/explosion_shockwave.gdshader` to produce screen refraction distortion during the initial blast phase.
- Controller script `res://scenes/vfx/explosion_crysis.gd`: Coordinates one-shot emission triggers, handles the `DetonationFlash` tween, and manages lifecycle cleanup after all particle emitters complete.

### R5. Cleanup and Asset Import
Purge intermediate frame folders and Blender simulation cache files. Execute `godot --headless --editor --quit` to generate `.import` artifacts and UIDs.

## Verification Resources
- Existing reference shockwave shader: `res://vfx/explosion_shockwave.gdshader`
- Existing reference test: `test/unit/test_smoke_explosion_vfx.gd`
