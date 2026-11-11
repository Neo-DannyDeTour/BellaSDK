# E2E Test Infra: Explosion Crysis VFX Hierarchy

## Test Philosophy
- Opaque-box, requirement-driven. Derived strictly from `ORIGINAL_REQUEST.md` and user-facing specs.
- Methodology: Category-Partition + Boundary Value Analysis + Pairwise Interactions + Real-World Workload Testing.
- Command runner: `godot --headless -s addons/gut/gut_cmdln.gd -gdir="" -gtest=res://test/unit/test_explosion_crysis.gd -gexit`

## Feature Inventory
| # | Feature | Source | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
|---|---------|--------|:------:|:------:|:------:|:------:|
| 1 | Scene Instantiation & Root Node3D | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |
| 2 | CoreFireball GPUParticles3D | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |
| 3 | LingeringSmoke GPUParticles3D | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |
| 4 | SparksAndDebris GPUParticles3D | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |
| 5 | DetonationFlash OmniLight3D | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |
| 6 | HeatDistortion Refraction Mesh | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |
| 7 | Controller Trigger & Lifecycle | ORIGINAL_REQUEST §R4 | 5 | 5 | ✓ | ✓ |

## Test Architecture
- Test Runner: `addons/gut/gut_cmdln.gd` running headlessly via Godot 4.7.1.
- Target Script: `res://test/unit/test_explosion_crysis.gd`
- Isolated invocation: `-gdir="" -gtest=res://test/unit/test_explosion_crysis.gd -gexit`
- Pass/Fail semantics: Exit code 0, 0 errors, 0 failures.

## Coverage Goals
- Tier 1: Feature coverage (instantiation, node presence, property assignments, shader/texture assignments).
- Tier 2: Boundary & corner cases (property limits, null safety, rapid reset/re-triggering, immediate free vs deferred free).
- Tier 3: Cross-feature interactions (synchronized one-shot trigger, flash decay simultaneous with particle start, shockwave expansion simultaneous with fireball).
- Tier 4: Real-world scenarios (repeated instantiation/autofree in gameplay loop, disabling auto_play for manual detonation, queue_free lifecycle after duration).
