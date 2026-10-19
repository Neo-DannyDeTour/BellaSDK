# BellaSDK Directory Structure & Domain Architecture

This document defines the project structure of BellaSDK so developers and contributors immediately know where everything belongs and why.

---

## High-Level Layout

```
BellaSDK/
├── assets/          # Static art, audio, textures, 3D models, fonts, and HDRs
├── core/            # Engine architecture, autoloads, singletons, shared components, and utilities
├── enemies/         # AI characters, drones, turrets, and combatants
├── environment/     # World geometry, dynamic props, weather, soundscapes, and terrain
├── interactables/   # Interactive mechanics (doors, buttons, cables, sockets, valves, puzzles)
├── levels/          # Playable level scenes, testbeds, and blockouts
├── player/          # First-person controller, state machines, cameras, and player systems
├── shaders/         # Custom screen/global `.gdshader` files
├── SFX/             # Specialized audio managers (Sonar, Spatial Describer)
├── test/            # GUT unit tests, mocks, and integration test scenes
├── tools/           # In-editor utilities, generators, benchmarks, and automation scripts
├── translations/    # Localization CSVs and compiled `.translation` resources
├── triggers/        # Hazard fields, teleport portals, look triggers, and volume colliders
├── ui/              # User interface panels, HUDs, menus, and debug overlays
└── vfx/             # Visual effects (particles, explosion rigs, trails, shader materials)
```

---

## Domain Breakdown & Guidelines

### 1. `assets/`
Static external game assets organized by media type:
- `assets/decals/`: Decal textures.
- `assets/fonts/`: UI and world fonts.
- `assets/HDR/`: Panoramic skyboxes and environment HDRI maps.
- `assets/images/`: Concept art, UI textures, dev textures.
- `assets/models/`: Static and animated 3D meshes (e.g. `assets/models/godiva/`).
- `assets/music/` & `assets/sounds/`: Background music and audio files.
- `assets/textures/`: Surface textures, normal maps, roughness maps, dev materials.
- `assets/weapons/`: Weapon models and UI icons.

### 2. `core/`
The foundational framework that powers gameplay logic without being coupled to individual entities:
- `core/global.gd`: Global state singleton.
- `core/events.gd`: Global event bus managing typed signals (`Events`).
- `core/components/`: Reusable, modular gameplay components attached to entities:
  - `health_component.gd`: Handles health, damage, and death signals.
  - `health_modifier.gd`: Area/volume damage and healing modifier.
  - `faction_component.gd`: Hostility and team relationship system.
  - `powered_object.gd`: Logic component tracking electrical power requirements.
  - `rotator_component.gd`: Procedural continuous rotation for fans, ventilators, and wheels.
- `core/audio_manager.gd` & `core/audio_pool.gd`: High-performance pooled audio playback.
- `core/graphics_manager.gd` & `core/global_settings.gd`: Video/display configuration and runtime settings.
- `core/save_manager.gd` & `core/save_slot.gd`: Game state persistence and checkpoint restoration.
- `core/state_machine.gd`: Native hierarchical state machine.

### 3. `enemies/`
Hostile AI agents and combat entities:
- `evil_goon.tscn` / `evil_goon.gd`: Melee humanoid enemy.
- `turret.tscn` / `turret.gd`: Stationary projectile turret.
- `elf_drone.tscn`: Aerial drone AI.
- `wave_spawner.gd`: Enemy spawn controller.

### 4. `environment/`
World decoration, interactive dynamic environment volumes, and terrain systems:
- Dynamic volumes: `updraft_vent.*`, `mannequin_volume.*`, `target_volume.*`.
- Environmental props: `ventilator.*`, `cloth.*`, `flag_waving.*`, `torch.*`.
- Weather & atmosphere: `box_clouds.*`, `snow_environment.*`, `ocean.*`, `water_body.*`.
- Soundscapes: `soundscape_zone.*`, `soundscape_data.gd`, ambient audio resources.
- Structural elements: `monke_bar.*`, `procedural_monkey_bars.*`, `procedural_fence_csg.*`, `basalt_generator.*`.

### 5. `interactables/`
Player-manipulable objects, mechanical contraptions, and puzzle elements:
- Switches: `button.*`, `ground_button.*`.
- Puzzle elements: `puzzle_socket.*`, `ui_keypad.*`, `draw_bridge_system.*`, `drawbridge.*`.
- Physical couplings: `pulley_controller.*`, `tethered_plug.*`, `slide_track.*`, `path_stick.*`.
- Targets: `shooting_target.*`.
- Doors & valves: `door_interact.*`, `door_slide.*`, `valve_base.*`.

### 6. `levels/`
Complete scene assemblies loaded directly by the game or editor:
- `testbed2.tscn`: Primary developer staging level with active gameplay features.
- `testbed.tscn`: Legacy mechanics testing ground.
- `vistest_game.tscn`: Visual and lighting test stage.

### 7. `player/`
First-person controller architecture:
- `player.tscn` / `player.gd`: Main player root and camera rig.
- Locomotion state machine: `state_ground.gd`, `state_water.gd`, `state_ladder.gd`, `state_monkey_bars.gd`, `state_zipline.gd`, `state_rope.gd`.
- Player components: `locomotion_component.gd`, `player_interaction_component.gd`, `stats_component.gd`, `weapon_inventory_component.gd`.

### 8. `tools/`
Developer productivity, automated testing, benchmarking, and editor scripts:
- In-Editor Tools: `scene_organizer.gd`, `dev_cylinder.*`, `dev_hologram_tool.gd`, `texture_baker.tscn`.
- Benchmarking: `benchmark_runner.gd`, `benchmark_main.tscn`.
- `tools/scripts/`: Automation shell and python scripts (`format_and_lint.sh`, `publish_release.sh`, `test_syntax.sh`, `update_assets.sh`).
- `tools/maintenance/`: Migration scripts and archived patch scripts (`patch_*.py`).

### 9. `triggers/`
Spatial trigger zones reacting to player or object collisions:
- `killfield.*`: Hazard zone resetting the player to the last checkpoint.
- `teleport.*` & `teleport_destination.*`: Instantaneous portal relocators.
- `fade_trigger.*`, `trigger_look.*`, `trigger_hint.*`, `music_trigger.*`.

### 10. `ui/`
User interface components, menus, and on-screen overlays:
- Navigation: `main_menu.*`, `menu_chapter_screen.*`, `save_load_panel.*`.
- HUD: `player_status_hud.*`, `ammo_hud.*`, `crosshair_hud.*`, `notification_hud.*`.
- In-game diagnostics: `in_game_console.*`, `perf_overlay.*`, `fps_counter.*`.
- Settings panels: `audio_panel.*`, `controls_panel.*`, `video_options_panel.*`, `accessibility_panel.*`.

### 11. `vfx/`
Visual particle systems, decals, and special effects:
- `vfx_blood_burst.tscn`, `dust_puff.*`, `trail_3d.*`, `particle.*`, `phys_explosion_3d.*`.
- Screen shaders: `caustics_shader.gdshader`, `screen_transition.gdshader`.
