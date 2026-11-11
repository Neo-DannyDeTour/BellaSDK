# Project: Headless Mantaflow Explosion & Crysis VFX Hierarchy

## Architecture
- **Offline VFX Pipeline**: Headless Blender Python script (`tools/generate_explosion_flipbook.py`) drives Mantaflow physics domain, EEVEE renderer, and 8x8 montage/Pillow packing into `res://assets/vfx/explosion/explosion_core_8x8.png`.
- **Engine Asset Layer**: Godot 4 imports the spritesheet with `.import` / `.uid` artifacts (`uid://mpc6axbfwyt3`).
- **Real-Time VFX Layer**: `res://scenes/vfx/explosion_crysis.tscn` integrates:
  - `CoreFireball`: GPUParticles3D with 8x8 flipbook material.
  - `LingeringSmoke`: GPUParticles3D with soft billboard blend.
  - `SparksAndDebris`: GPUParticles3D with ballistic alignment and HDR albedo.
  - `DetonationFlash`: OmniLight3D with rapid energy decay tween.
  - `HeatDistortion`: MeshInstance3D with SphereMesh and `res://vfx/explosion_shockwave.gdshader`.
- **Control & Lifecycle Layer**: `res://scenes/vfx/explosion_crysis.gd` coordinates triggers, tweens, and lifecycle destruction.
- **Testing Layer**: GUT test `res://test/unit/test_explosion_crysis.gd` executed via `godot --headless -s addons/gut/gut_cmdln.gd -gconfig= -gtest=... -gexit`.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | F1: Environment Verification | Verify blender, python3, montage/ffmpeg/pillow, godot, gdlint | M1 (DONE) | ORIGINAL_REQUEST §R1 |
| 2 | F2: Blender Mantaflow Bake Script | `tools/generate_explosion_flipbook.py` with emitter, domain, shader | M1 (DONE) | ORIGINAL_REQUEST §R2 |
| 3 | F3: 64-Frame Transparent Render | Headless EEVEE render, 256x256 RGBA, transparent film | M1 (DONE) | ORIGINAL_REQUEST §R2 |
| 4 | F4: 8x8 Spritesheet Assembly | 2048x2048 RGBA PNG at `res://assets/vfx/explosion/explosion_core_8x8.png` | M1 (DONE) | ORIGINAL_REQUEST §R3 |
| 5 | F5: Cache Purge & Asset Import | Purge intermediate frames/cache, `godot --headless --editor --quit` | M1 (DONE) | ORIGINAL_REQUEST §R5 |
| 6 | F6: Composite Explosion Scene | Root Node3D `res://scenes/vfx/explosion_crysis.tscn` | M2 (DONE) | ORIGINAL_REQUEST §R4 |
| 7 | F7: CoreFireball Emitter | GPUParticles3D, 8x8 flipbook, scale 1.0->3.2, alpha fade | M2 (DONE) | ORIGINAL_REQUEST §R4 |
| 8 | F8: LingeringSmoke Emitter | GPUParticles3D, soft blend, radial velocity 3.0, damping 4.0 | M2 (DONE) | ORIGINAL_REQUEST §R4 |
| 9 | F9: SparksAndDebris Emitter | GPUParticles3D, 60 particles, HDR albedo, +Z bias, bounce | M2 (DONE) | ORIGINAL_REQUEST §R4 |
| 10 | F10: DetonationFlash Light | OmniLight3D, 16.0->0.0 energy tween in 0.15s | M2 (DONE) | ORIGINAL_REQUEST §R4 |
| 11 | F11: HeatDistortion Refraction | SphereMesh, layer 10, shockwave shader instance uniforms | M2 (DONE) | ORIGINAL_REQUEST §R4 |
| 12 | F12: Explosion Controller Script | `res://scenes/vfx/explosion_crysis.gd` with triggers and cleanup | M2 (DONE) | ORIGINAL_REQUEST §R4 |
| 13 | F13: GUT Automated Test Suite | `res://test/unit/test_explosion_crysis.gd` passing headless | ET1 & M3 (DONE) | ORIGINAL_REQUEST §Acceptance |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Blender Flipbook Pipeline | `tools/generate_explosion_flipbook.py`, spritesheet assembly, asset import | none | DONE |
| 2 | ET1: E2E Testing Track | `test/unit/test_explosion_crysis.gd` (Tiers 1-4) | none | DONE |
| 3 | M2: Explosion Scene & Controller | `res://scenes/vfx/explosion_crysis.tscn` and `res://scenes/vfx/explosion_crysis.gd` | M1 | DONE |
| 4 | M3: Final Milestone & Hardening | Pass 100% E2E tests, Tier 5 adversarial coverage hardening | M2, ET1 | DONE |

## Interface Contracts
### tools/generate_explosion_flipbook.py ↔ Godot Engine
- Output path: `res://assets/vfx/explosion/explosion_core_8x8.png` (2048x2048 RGBA, uid://mpc6axbfwyt3). [VERIFIED]

### res://scenes/vfx/explosion_crysis.tscn ↔ res://scenes/vfx/explosion_crysis.gd
- Root type: `Node3D`, class_name `ExplosionCrysis`.
- Mandatory child nodes:
  - `CoreFireball`: `GPUParticles3D`
  - `LingeringSmoke`: `GPUParticles3D`
  - `SparksAndDebris`: `GPUParticles3D`
  - `DetonationFlash`: `OmniLight3D`
  - `HeatDistortion`: `MeshInstance3D`
- Public properties / exports:
  - `@export var auto_play: bool = true`
  - `@export var free_on_finish: bool = true`
- Public methods:
  - `func explode() -> void`
  - `func reset() -> void`

## Code Layout
- `tools/generate_explosion_flipbook.py` — Blender headless automation script [DONE]
- `assets/vfx/explosion/explosion_core_8x8.png` — Generated 8x8 flipbook texture [DONE]
- `scenes/vfx/explosion_crysis.tscn` — Explosion composite scene [DONE]
- `scenes/vfx/explosion_crysis.gd` — Explosion controller script [DONE]
- `test/unit/test_explosion_crysis.gd` — GUT unit test script [DONE]
- `vfx/explosion_shockwave.gdshader` — Existing shockwave shader (read-only reference)
