# Technical Report: Smoke Hazard Audit & Ground-Up Rewrite Specification

**Target Developer**: Argon
**Subject**: Total Deprecation & Replacement of `SmokeHazard` (`res://environment/smoke_hazard.gd`, `res://environment/smoke_hazard.tscn`)
**Objective**: Complete ground-up redesign of environmental smoke. Do not patch or wrap existing code.

---

## 1. Existing System Anatomy (`smoke_hazard.gd`)

### Architecture & Base Class
* **Node Type**: `Area3D` tagged `@tool`.
* **Class Name**: `SmokeHazard`.
* **Collision Configuration**: Hardcoded mask `2` (Layer 2: Player only; skips Enemies / Layer 5 by default).
* **Child Nodes**:
  1. `CollisionShape3D` (`BoxShape3D` or `SphereShape3D`, dynamically regenerated in `@tool`).
  2. `SmokeParticles` (`GPUParticles3D`, 50 billboard quads running `vfx/smoke_lod.gdshader`).
  3. `EditorTriggerVisualizer` (`MeshInstance3D` running `triggers/editor_trigger_visualizer.gd`).

### Core Execution Flow
1. **Pulsing Cycle (`_process`)**:
   * Alternates between `_is_active = true` for `active_duration` (default: 3.0s) and `_is_active = false` for `pause_duration` (default: 2.0s).
   * Toggles `GPUParticles3D.emitting = active`.
2. **Body Tracking**:
   * Uses `body_entered` and `body_exited` to populate an internal `_targets_in_smoke: Array[Node3D]`.
   * Queries and caches `HealthComponent` via `NodeQuery.find_first_child_of_type()` or ancestor lookups.
3. **Damage Ticking**:
   * While active, accumulates `_tick_timer` against `tick_rate` (default: 0.5s).
   * Runs `_has_line_of_sight()`: Casts a single raycast (`NodeQuery.cast_ray`) from `global_position + hazard_offset + Vector3(0, 0.5, 0)` to `target.global_position + Vector3(0, 0.5, 0)` on `CollisionLayers.MASK_ENVIRONMENT` (Layer 1).
   * Calls `health.take_damage(int(roundf(damage_per_tick)))` directly (default: 25.0 in scene).

---

## 2. Signals & Event Routing

### Local Signals
| Signal | Signature | Triggers |
| :--- | :--- | :--- |
| `damage_ticked` | `(target: Node3D, amount: float)` | Emitted immediately before calling `HealthComponent.take_damage()`. |

*Current Callers/Subscribers*: **Zero external connections**. Only emitted internally.

### Global Signals (`Events`)
| Global Signal | Direction | Payload | Usage in System |
| :--- | :--- | :--- | :--- |
| `Events.steam_hazard_toggled` | **Emitted** | `(is_active: bool)` | Fired when player enters/exits active smoke, or when active state toggles while player is inside. |

### Downstream Receivers / External Dependencies
* **`ui/player_status_hud.gd`** (`_on_steam_hazard_toggled`):
  * Toggles `is_in_steam`.
  * Shows/hides `steam_debuff_container` and `steam_border` overlay.
  * *Critical Bug*: Misnamed semantic signal. Smoke triggers "Steam" UI.
  * *Concurrency Flaw*: Binary toggle without reference counting. If player steps from Smoke A into Smoke B, exiting Smoke A sends `false`, disabling the HUD debuff even while still inside Smoke B.
* **Level Placements**:
  * `levels/testbed2.tscn` (Node `SmokeHazard`, line 11419, instancing `res://environment/smoke_hazard.tscn`).

---

## 3. Why It Must Be Scrapped (Core Deficiencies)

1. **Decoupled Visuals vs. Hitbox**:
   * Visual is a billboard quad particle emitter with rising velocity. Collision is a rigid static `BoxShape3D` or `SphereShape3D`.
   * Smoke visibly blows away or rises, but the invisible damage volume stays anchored to the ground floor.
2. **Primitive 2D Billboard Rendering**:
   * Uses `QuadMesh` billboard quads with simple noise LOD texture lookup.
   * Flat clipping against walls and geometry (no soft depth fading, no 3D volumetric extinction).
   * Zero interaction with scene lights, ambient GI, or volumetric fog.
3. **Zero Gameplay Reactivity / Occlusion**:
   * Does **not** block AI line-of-sight or perception checks.
   * Does **not** affect player vision (no post-process screen overlay, cough/choke vignette, or vision blur).
   * Does **not** react to physical forces: ignores `WindController`, explosive shockwaves (`ShockwaveManager`), weapon bullet holes (unlike `DynamicFogZone` / `SmokeManager`), or draft vents (`UpdraftVent`).
4. **Binary Damage Model (No Gas / Suffocation Dynamics)**:
   * Instant health reduction every 0.5s.
   * No toxic concentration buildup, oxygen depletion meter, coughing state, stamina drain, or dissipation curve.
5. **Architectural Violations**:
   * Polling inside `_process()` instead of clean timer/event-driven scheduling.
   * Scene tree hierarchy walks (`NodeQuery.find_first_child_of_type`) on dynamic bodies.

---

## 4. Ground-Up Rewrite Blueprint for Argon

```
               ┌────────────────────────────────────────────────────────┐
               │              Global Atmosphere / Wind                  │
               │         (WindController / DynamicFogCoordinator)       │
               └───────────────────────────┬────────────────────────────┘
                                           │ wind vector & carve rays
                                           ▼
┌───────────────────────────────────────────────────────────────────────────────────┐
│                           Next-Gen Smoke System                                   │
│                                                                                   │
│  ┌───────────────────────────┐                 ┌───────────────────────────────┐  │
│  │   Volumetric / Visual     │                 │   Physical / Hazard Volume    │  │
│  │   - FogVolume 3D Material │                 │   - Area3D (Layer 2 & 5)      │  │
│  │   - Density gradient      │◄─── synced ────►│   - Radial falloff            │  │
│  │   - Dissipation curve     │                 │   - Suffocation/Gas tracker   │  │
│  │   - Bullet carving hook   │                 │   - AI sight occlusion volume │  │
│  └───────────────────────────┘                 └───────────────┬───────────────┘  │
└────────────────────────────────────────────────────────────────┼──────────────────┘
                                                                 │
                                ┌────────────────────────────────┴──────────────────┐
                                ▼                                                   ▼
                ┌───────────────────────────────┐                   ┌───────────────────────────────┐
                │        Player Effects         │                   │          AI Reaction          │
                │ - Events.smoke_hazard_changed │                   │ - Registers on sight block    │
                │ - Suffocation meter / vignette│                   │ - Causes coughing / blind AI  │
                └───────────────────────────────┘                   └───────────────────────────────┘
```

### Key Pillars for the New Design

#### A. Volumetric & Visual Foundation
* **Native Godot 4 Volumetrics**: Base the cloud on `FogVolume` with custom `FogMaterial` or `fog_volume.gdshader` (matching `assets/weapons/Smoke_Grenade/smokecloud.gd` and `DynamicFogZone`).
* **Interactive Carving**: Integrate with existing `SmokeManager` (`res://environment/DynamicFog/smoke_manager.gd`) so bullets (`add_bullet_hole`) and explosions carve tunnels through the smoke.
* **Wind Drift**: Accept drift vectors from `WindController` to organically displace the fog center.

#### B. Realistic Hazard & Gameplay Mechanics
* **Dual Collision Target**: Mask both Layer 2 (Player) and Layer 5 (Enemies).
* **Concentration Falloff**: Calculate distance from smoke centroid. Center deals high toxicity/coughing; edges deal light obscurity.
* **Suffocation Accumulator**: Rather than crude raw HP reduction, apply a suffocation/toxic exposure buildup over time. Passing a threshold causes coughing, speed reduction, and eventual health damage.
* **Vision & AI Occlusion**: Register the volume into the AI perception manager or raycast obstruction mask so enemies cannot shoot through thick smoke.

#### C. Clean Event Architecture
* **Replace `steam_hazard_toggled`**:
  * Declare dedicated signal in `core/events.gd`:
    ```gdscript
    @warning_ignore("unused_signal")
    signal smoke_hazard_changed(is_inside: bool, density: float)
    ```
  * Implement reference counting in `PlayerStatusHUD` (or a dedicated `HazardManager`) so stepping between overlapping clouds never prematurely clears debuffs.

---

## 5. Scope & Migration Checklist for Argon

1. **Files to Replace / Delete**:
   * `environment/smoke_hazard.gd` (Delete or replace with new implementation).
   * `environment/smoke_hazard.tscn` (Delete or re-author with new node structure).
2. **References to Update**:
   * `levels/testbed2.tscn`: Replace instance node `SmokeHazard` with the new scene.
   * `core/events.gd`: Add clean `smoke_hazard_changed` event.
   * `ui/player_status_hud.gd`: Unhook `steam_hazard_toggled` from smoke logic; hook new dedicated smoke debuff.
3. **No Legacy Glue**:
   * Do **not** keep `EditorTriggerVisualizer` inside the smoke actor unless explicitly needed for non-fog triggers.
   * Do **not** retain the 2D billboard `vfx/smoke_lod.gdshader` particle setup.

---

## 6. Copy-Paste Dispatch Message for Argon

```markdown
Hi Argon,

We need you to build a brand new, next-generation Environmental Smoke System from scratch to replace the legacy `SmokeHazard` (`environment/smoke_hazard.gd` / `smoke_hazard.tscn`).

IMPORTANT: Do NOT attempt to fix, refactor, or preserve the legacy script or its node hierarchy. Delete and replace it with a clean, ground-up implementation.

### Key Flaws in Legacy System (To Avoid):
1. **Decoupled Visuals vs. Hitbox**: It used a rigid static Area3D box/sphere paired with rising 2D billboard GPUParticles (`vfx/smoke_lod.gdshader`), causing visual desync.
2. **Broken Signal Semantics**: It fired `Events.steam_hazard_toggled` (reusing the Steam HUD overlay with binary state, causing multi-hazard race conditions).
3. **Zero Interactivity & Occlusion**: No bullet carving, no wind displacement, and no AI line-of-sight obstruction.
4. **Crude Damage Model**: Flat HP tick deduction in `_process()` instead of a realistic concentration/suffocation curve.

### What the New Smoke System Must Deliver:
1. **Volumetric Foundation**: Native Godot 4 `FogVolume` (with custom shader/material) matching the quality of `FogVolume` / `DynamicFogZone`.
2. **Interactive Environment**: Register with `SmokeManager` (`res://environment/DynamicFog/smoke_manager.gd`) so hitscans (`add_bullet_hole`), projectiles, and explosions carve physical visibility tunnels through the volume.
3. **Hazard Dynamics**:
   - Area3D masking Layer 2 (Player) and Layer 5 (Enemies).
   - Radial density gradient (dense core, dissipated edges).
   - Suffocation/toxicity exposure buildup rather than flat instant HP damage.
4. **AI & Vision Occlusion**: Obstruct AI perception rays passing through the cloud.
5. **Clean Events**:
   - Emit a dedicated signal in `core/events.gd` (e.g. `smoke_hazard_changed(is_inside: bool, density: float)`).
   - Support reference-counted tracking in `PlayerStatusHUD` so multiple overlapping smoke clouds do not prematurely cancel debuffs.
6. **Performance & Standards**: Event-driven (disable `_process` when idle), strict Godot 4 typing, `@onready` caching, and compliant with project `.gdlintrc`.

Check `levels/testbed2.tscn` where `smoke_hazard.tscn` is placed to ensure clean drop-in scene compatibility once the new system is ready.
```
