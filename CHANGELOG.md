# Changelog

All notable changes to BellaSDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.5.3] - 2026-11-05

### Added

#### Enemies & Hazards
- **Enemy Squid (`res://enemies/squid/`)**:
  - Procedural 3D tentacle mesh displacement shader (`squid_tentacle.gdshader`).
  - Ink and mucus puddle hazard (`squid_puddle.tscn`) dynamically spawned under target.
  - Ink puddles apply temporary sprint debuff and slippery/sand hazard locomotion slowdowns.
- **Sensor Turret (`res://enemies/sensor_turret.tscn`)**:
  - Event-driven visual/audio detection cone with state transitions and alarm broadcast.
- **Pressurized Fire Jet (`res://vfx/pressurized_fire_jet/`)**:
  - Timed burst flame hazard emitting cyclic area damage and light flicker.

#### Weapons & Combat
- **Signal Rocket Flare (`res://weapons/signal_rocket/`)**:
  - Handheld single-shot launcher with ignite, burnout, and dynamic drop mechanics.
  - Projectile physics rocket with trailing particle spark flare and terrain sticking.
  - Re-pickable flare pickup entity when dropped or discarded.
- **Impact Manager (`res://vfx/impact_manager.gd`)**:
  - Global autoload orchestrating hitscan particle bursts, spark decals, and surface normals.
  - Event `Events.bullet_impact_requested` for decoupled impact rendering.
- **Health Component Randomization**:
  - Added `random_health_range` (`Vector2i`) to `HealthComponent` for organic enemy spawns.

#### Locomotion & Player
- **Hazard Surface Integration**:
  - Connected `LocomotionComponent` to `Events.sand_surface_toggled`, `ice_surface_toggled`,
    and `sprint_debuff_applied`.
  - Added arbitration logic to recalculate sprint permission dynamically.
- **Weapon Inventory Management**:
  - Added `clear_slot(index)` and `remove_weapon(weapon)` to `WeaponInventoryComponent`.
  - Automatically dispatches `on_unequip()` callables before deactivating weapons.

#### Interactables & Environment
- **Timber Jib Crane (`res://interactables/timber_jib_crane.tscn`)**:
  - Rotating crane boom controlled via push wheel capstan and physical grab rails.
- **Engine Ramp (`res://interactables/engine_ramp.tscn`)**:
  - Heavy mechanical boarding and elevation ramp with physical collision gating.
- **Tagged Prop & Scanner Shader (`res://shaders/tagged_prop.gdshader`)**:
  - Highlight and scan overlay with frequency-based pulse and tag notifications.
- **Pickable Liquid Bottle**:
  - Glass bottle container with procedural liquid wobble shader.
- **Heavy Metal Fence & Cage Light**:
  - Modular security fence barrier and cage lights with flicker animations.
- **Pickable Wheel & Sewer Grate**:
  - Detachable rotating physics wheel and interactive drainage grate mechanism.

#### Developer Tooling & Console
- **Freecam Controller (`res://player/freecam_controller.gd`)**:
  - Debug 6-DOF flying camera toggled via console with smooth velocity damping.
- **In-Game Console Cheats & Settings**:
  - Commands for godmode, fly, time scaling, ammo refill, and graphics toggles.
- **Event Sequencer Dock**:
  - In-engine inspector dock for authoring scripted cutscenes and cinematic camera beats.
- **Blender Asset Generators (`res://tools/blender/`)**:
  - Python scripts (`build_wall_panel.py`, etc.) for generating modular destructible meshes.

### Changed
- Reorganized gesture input manager under `core/` architecture.
- Re-architected Universal Setting Highlighter with row hover shader and panel transitions.
- Standardized test suites for weapons, impact manager, squid enemy, and console commands.

### Fixed
- Fixed unequipped weapon remaining visible or active during hotbar swaps.
- Fixed virtual chunk spawn readiness and safe console call inside feedback station.
- Cleaned up scene node leaks and dangling Callables across unit test suites.

### Performance
- Eliminated runtime material duplications by routing instance parameters to shader uniforms.
- Zero per-frame object allocations inside locomotion hazard detection.
- Headless GUT suite validation achieving 100% test pass rates across new subsystems.

---

## [0.5.2] - 2026-10-19

### Changed
- Enabled VRAM compression and mipmaps across all world textures.
- Updated import caches and path references following modular directory reorganization.

---

## [0.5.1] - 2026-10-19

### Changed
- Reconciled modular repository reorganization with event sequencer additions.
- Consolidated core modules under `res://core/` (`CollisionLayers`, `NodeQuery`, `MaterialCache`).

---

## [0.5.0] - 2026-10-15

### Added
- Standardized scene definitions, interactable base classes, and keycard system.
- Modular component framework (`HealthComponent`, `StatsComponent`, `InteractComponent`).
