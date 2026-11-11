## 2026-11-11T05:35:54Z
You are the Test Writer for E2E Testing Track (ET1).

Working directory: /home/dkd/Documents/BellaSDK/.agents/teamwork/test_writer_et1/
Create your files (progress.md, test_plan.md, handoff.md) inside this working directory.

MANDATORY FIRST STEPS:
1. Read /home/dkd/Documents/BellaSDK/.agents/teamwork/ORIGINAL_REQUEST.md
2. Read /home/dkd/Documents/BellaSDK/.agents/teamwork/orchestrator/PROJECT.md and /home/dkd/Documents/BellaSDK/.agents/teamwork/orchestrator/TEST_INFRA.md
3. Read /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_2/handoff.md and /home/dkd/Documents/BellaSDK/.agents/teamwork/explorer_survey_3/handoff.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Write ownership:
You exclusively own and may create/modify:
- /home/dkd/Documents/BellaSDK/test/unit/test_explosion_crysis.gd
Do NOT modify implementation scenes or scripts.

Objective:
Implement comprehensive GUT unit tests for `res://scenes/vfx/explosion_crysis.tscn` and controller `res://scenes/vfx/explosion_crysis.gd` at `res://test/unit/test_explosion_crysis.gd`.

Design Methodology (Tiers 1-4 per TEST_INFRA.md):
- Tier 1: Feature coverage
  - Scene loads and instantiates headlessly without errors.
  - Node hierarchy presence: `CoreFireball` (GPUParticles3D), `LingeringSmoke` (GPUParticles3D), `SparksAndDebris` (GPUParticles3D), `DetonationFlash` (OmniLight3D), `HeatDistortion` (MeshInstance3D).
  - Check default properties:
    - CoreFireball: amount == 1, lifetime == 1.1, one_shot == true, explosiveness == 1.0.
    - LingeringSmoke: amount == 12, lifetime == 3.5, one_shot == true, explosiveness == 0.85.
    - SparksAndDebris: amount == 60, lifetime == 1.8, one_shot == true, explosiveness == 0.98.
    - DetonationFlash: energy == 16.0, range == 25.0, color == Color(1.0, 0.6, 0.2).
    - HeatDistortion: SphereMesh geometry, shockwave shader material attached.
- Tier 2: Boundary & Corner cases
  - Test disabling `auto_play`: instance doesn't immediately fire if auto_play is false.
  - Test manual `explode()` call triggering particle emission and flash tween.
  - Test `reset()` returning particles and flash to baseline.
  - Test freeing safety (no crashes when freed before lifecycle timer finishes).
- Tier 3: Cross-Feature Combinations
  - Synchronized detonation: verify all particle systems have `emitting = true` after `explode()`.
  - Flash energy collapses towards 0.0 during tween.
- Tier 4: Real-World Scenarios
  - Gameplay burst simulation: instantiate multiple explosion instances in sequence with `add_child_autofree()`.

BellaSDK Strict Typing & Standards:
- Must comply with `.gdlintrc` (max line length 100, tab indent, no trailing whitespace).
- Static typing required: `untyped_declaration = 2`, `inferred_declaration = 1` (do NOT use `:=`), `unsafe_property_access = 2`.
- Local variables must NEVER start with a leading underscore.
- GUT runner command: `godot --headless -s addons/gut/gut_cmdln.gd -gdir="" -gtest=res://test/unit/test_explosion_crysis.gd -gexit`. Note: tests will be runnable once Milestone 2 creates the scene, but test file syntax and parse validity can be checked right away.

When finished:
1. Write handoff report in your working directory (/home/dkd/Documents/BellaSDK/.agents/teamwork/test_writer_et1/handoff.md).
2. Report results and coverage summary to orchestrator.
