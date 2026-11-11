# BRIEFING — 2026-11-11T05:29:45Z

## Mission
Survey Godot VFX conventions, explosion_shockwave.gdshader, GUT test patterns, and BellaSDK architecture requirements for VFX.

## 🔒 My Identity
- Archetype: Explorer
- Roles: Read-only investigator, synthesizer
- Working directory: /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2
- Original parent: b609ba53-70bb-4664-8ab9-7b4d7b697cfc
- Milestone: Project Survey Phase (Milestone 1)

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Strict adherence to BellaSDK standards (.gdlintrc, GEMINI.md, 60 FPS, strict typing)
- Write only to /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/

## Current Parent
- Conversation ID: b609ba53-70bb-4664-8ab9-7b4d7b697cfc
- Updated: 2026-11-11T05:29:45Z

## Investigation State
- **Explored paths**:
  - `res://vfx/explosion_shockwave.gdshader`
  - `res://vfx/shockwave_refract.gdshader`
  - `res://test/unit/test_smoke_explosion_vfx.gd`
  - `res://test/unit/test_collision_layers.gd`
  - `res://vfx/smoke_explosion.tscn` & `res://vfx/smoke_explosion.gd`
  - `res://vfx/vfx_smoke_flipbook.tscn`
  - `res://vfx/effects/control_explosion.gd`
  - `generate_vertical_smoke_flipbook.py`
  - `tools/generate_explosion_atlas.py`
  - `res://core/utilities.gd`
  - `res://core/collision_layers.gd`
  - `.gdlintrc` & `GEMINI.md`
- **Key findings**:
  - `explosion_shockwave.gdshader` relies on `dot(NORMAL, VIEW)` Fresnel falloff; requires 3D `SphereMesh` (a flat Quad has 0 fresnel and renders transparent).
  - Uses `instance uniform float explosion_progress` and `instance uniform float distortion_strength` via `set_instance_shader_parameter()`.
  - `test_smoke_explosion_vfx.gd` has parse errors due to undeclared properties; new test `test_explosion_crysis.gd` must strictly match declared properties.
  - Flipbook mechanics confirmed via `vfx_smoke_flipbook.tscn` (`StandardMaterial3D` billboard_mode = 3, 8x8 frames, `ParticleProcessMaterial` anim_speed = 1.0).
  - BellaSDK strict rules documented (no `:=`, no leading underscore on locals, tabs only, 100 char limit, `Utilities.reset_tween()`, docstrings).
- **Unexplored areas**: None within assigned survey scope.

## Key Decisions Made
- Detailed technical analysis synthesized in `analysis.md`.
- Complete 5-component hard handoff generated in `handoff.md`.

## Artifact Index
- DISPATCH.md — Log of received dispatches
- progress.md — Liveness heartbeat and step tracking
- analysis.md — Detailed technical survey
- handoff.md — 5-component handoff report
