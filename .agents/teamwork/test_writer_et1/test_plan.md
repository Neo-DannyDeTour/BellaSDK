# Test Plan: Explosion Crysis VFX Hierarchy & Controller Unit Test Suite

Working Directory: `/home/dkd/Documents/BellaSDK/.agents/teamwork/test_writer_et1/`
Target Deliverable: `/home/dkd/Documents/BellaSDK/test/unit/test_explosion_crysis.gd`
Target Scene Under Test: `res://scenes/vfx/explosion_crysis.tscn`
Target Controller Under Test: `res://scenes/vfx/explosion_crysis.gd`
Framework: GUT (Godot Unit Test) Headless Runner
Command: `godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=res://test/unit/test_explosion_crysis.gd -gexit`

---

## Architecture & Test Methodology

Derivation Source: `ORIGINAL_REQUEST.md` (§R4, §Acceptance), `PROJECT.md` (§Interface Contracts, §Feature Inventory), and `TEST_INFRA.md` (Tiers 1–4).

The test suite exercises the complete multi-emitter composite explosion system across four progressive validation tiers:

### Tier 1: Feature Coverage (Static Hierarchy & Default Properties)
- **T1.1 Scene Instantiation & Root Contract**:
  - `PackedScene` loads cleanly from `res://scenes/vfx/explosion_crysis.tscn`.
  - Instantiates as a valid `Node3D`.
  - Has controller script attached (`explosion_crysis.gd`).
  - Exports `auto_play == true` and `free_on_finish == true` by default.
- **T1.2 Node Hierarchy Presence & Exact Types**:
  - `CoreFireball` exists and is `GPUParticles3D`.
  - `LingeringSmoke` exists and is `GPUParticles3D`.
  - `SparksAndDebris` exists and is `GPUParticles3D`.
  - `DetonationFlash` exists and is `OmniLight3D`.
  - `HeatDistortion` exists and is `MeshInstance3D`.
- **T1.3 CoreFireball Emitter Properties**:
  - `amount == 1`, `lifetime == 1.1`, `one_shot == true`, `explosiveness == 1.0`.
  - `draw_pass_1` is `QuadMesh` with `size == Vector2(5.0, 5.0)`.
  - `StandardMaterial3D`: unshaded, `billboard_mode == BILLBOARD_PARTICLES (3)`, 8x8 frames, loop disabled.
  - `ParticleProcessMaterial`: `anim_speed_min == 1.0`, `anim_speed_max == 1.0`.
- **T1.4 LingeringSmoke Emitter Properties**:
  - `amount == 12`, `lifetime == 3.5`, `one_shot == true`, `explosiveness == 0.85`.
  - `draw_pass_1` is `QuadMesh`.
  - `ParticleProcessMaterial`: buoyant gravity `Vector3(0.0, 0.8, 0.0)`, linear damp `4.0`, radial velocity `3.0`.
- **T1.5 SparksAndDebris Emitter Properties**:
  - `amount == 60`, `lifetime == 1.8`, `one_shot == true`, `explosiveness == 0.98`.
  - `draw_pass_1` is `QuadMesh(0.08, 0.4)`.
  - `StandardMaterial3D`: HDR albedo `Color(5.0, 2.2, 0.4, 1.0)`, unshaded.
  - `ParticleProcessMaterial`: gravity `Vector3(0.0, -18.0, 0.0)`, `collision_mode == COLLISION_RIGID (1)`.
- **T1.6 DetonationFlash Properties**:
  - `light_color == Color(1.0, 0.6, 0.2)` (warm orange).
  - `omni_range == 25.0` m.
  - Peak energy == `16.0` (property or controller constant `FLASH_PEAK_ENERGY`).
- **T1.7 HeatDistortion Properties**:
  - Geometry is `SphereMesh` (essential for radial fresnel normal distortion).
  - Material is `ShaderMaterial` with shader `res://vfx/explosion_shockwave.gdshader`.

---

### Tier 2: Boundary & Corner Cases
- **T2.1 Auto-Play Disable Guard**:
  - Setting `auto_play = false` before adding to scene tree prevents automatic firing.
  - Particle emitters remain `emitting == false`.
  - DetonationFlash is not actively emitting light.
- **T2.2 Manual Detonation Trigger (`explode()` / `detonate()`)**:
  - Explicit manual invocation activates all particle emitters (`emitting = true`).
  - Activates DetonationFlash visibility and energy.
  - Activates HeatDistortion visibility.
- **T2.3 Reset to Baseline (`reset()`)**:
  - Invoking `reset()` turns off particle emissions (`emitting = false`).
  - Restores DetonationFlash to hidden/zero energy.
  - Restores HeatDistortion to hidden/zero progress.
- **T2.4 Early Freeing Safety**:
  - Rapidly freeing the explosion node (`queue_free()`) shortly after detonation does not trigger engine crashes, orphaned tweens, or invalid timer callback panics.

---

### Tier 3: Cross-Feature Interactions
- **T3.1 Synchronized Detonation Timing**:
  - Detonation instantly activates all three particle passes (`CoreFireball`, `LingeringSmoke`, `SparksAndDebris`), the flash light, and the shockwave mesh in the exact same frame.
- **T3.2 Flash Energy Decay Tween**:
  - Upon detonation, `DetonationFlash` light energy starts at 16.0.
  - As time elapses (0.08s, 0.15s), light energy collapses down towards 0.0 via C++ Tween.
- **T3.3 Event Signal Dispatching**:
  - Controller declares and emits `detonation_started` and `detonation_finished`.

---

### Tier 4: Real-World Scenarios
- **T4.1 Gameplay Burst Simulation**:
  - Instantiates 5 sequential explosion nodes at staggered spatial offsets using `add_child_autofree()`.
  - Validates that concurrent explosion instances run independently without state pollution.
- **T4.2 Lifecycle Auto-Free Toggle**:
  - Validates that `free_on_finish` can be configured dynamically to retain or discard the node.

---

## Strict Typing & Engine Standards Verification
1. Strictly no `:=` variant inference (`inferred_declaration = 1`).
2. Strictly typed declarations (`untyped_declaration = 2`).
3. Safe downcasting from statically typed `Object` classes (`as GPUParticles3D`, `as OmniLight3D`, `as MeshInstance3D`).
4. No leading underscores on local variables.
5. Max line length <= 100 characters, strict tabs, zero trailing whitespace (`.gdlintrc`).
6. Complete BBCode `##` docstrings above every declaration.
