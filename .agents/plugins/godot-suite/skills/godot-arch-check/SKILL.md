---
name: godot-arch-check
description: Audit Godot 4 scripts and scenes for 60 FPS performance rules, physics safety, and clean event architecture.
---

# Godot 4 Architecture & Performance Audit

Use this skill before approving or executing GDScript refactors or new features.

## Checkpoint Checklist

### 1. 60 FPS Event Architecture
- [ ] Is `_process()` and `_physics_process()` disabled in `_ready()` unless continuously needed?
- [ ] Are expensive updates gated using `VisibleOnScreenNotifier3D` or distance checks?
- [ ] Are proximity checks using `distance_squared_to()` instead of `distance_to()`?
- [ ] Are node references cached in `@onready` variables?
- [ ] Are inputs and shader uniforms pre-allocated with `StringName` (`&"param"`)?
- [ ] Zero allocations (`Array`, `Dictionary`, `Object.new()`) inside per-frame loops (`_process`, `_physics_process`).

### 2. Physics & Mutation Safety
- [ ] Are physics states or scene tree modifications deferred inside physics callbacks via `set_deferred()` or `call_deferred()`?
- [ ] Are existing Tweens killed before respawning?

### 3. Layer Assignment Audit
Verify layer conventions are strictly respected:
- **3D Render**:
  - Layer 1: Environment
  - Layer 2: Player
  - Layer 3: Interactive
  - Layer 4: Portals
  - Layer 10: Volumetrics
- **3D Physics**:
  - Layer 1: Environment
  - Layer 2: Player
  - Layer 3: Interactive
  - Layer 4: Debris
  - Layer 5: Enemies
  - Layer 11: Preview/Diorama
