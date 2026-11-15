# BellaSDK Reconstructed Architectural History & Implicit Contracts (`RECONSTRUCTED_HISTORY.md`)

## 1. Chronological Design Evolution (`1,109` Commits: `76a7f48d` -> `290152af`)

BellaSDK evolved across **7 distinct architectural eras** between `2026-03-19` and `2026-11-14`, growing from a 2-autoload Godot 4.6 Jolt Physics prototype into a 26-autoload, 595-file (`119,089` `wc -l` / `119,171` `splitlines`) Godot 4.7.1 SDK.

### Phase 1: Foundation, Jolt Physics & Prototype Mechanics (`2026-03-19` to `2026-05-31`, Initial -> pre-`v0.3.1`)
- **Bootstrap (`76a7f48d`, `6b62753b`, `2026-03-19`)**: Initialized on Godot `4.6` (`Forward Plus`), `3d/physics_engine="Jolt Physics"` (`project.godot:233`), `run/max_fps=60` (`project.godot:17`), with only 2 initial autoloads (`Events` at `core/events.gd:1-793` and `DebugManager` at `ui/debug_manager.gd:1-27`).
- **Early Traversal & Physics Sandbox (`51cef2f7` -> `a43033e1`)**:
  - Water swimming (`51cef2f7`), monkey bars (`482f25d8`), ziplines (`e79444a3`).
  - Real-time diagnostics OSD & frame graph (`94be6b6b`, `21ea6803` -> `core/frame_graph.gd:1-89`, `ui/diagnostics_panel.gd:1-1829`).
  - Universal cables, ropes, and drawbridge (`83dd8795` -> `interactables/universal_cable_3d.gd:1-79`, `interactables/drawbridge.gd:1-231`).
  - Valves & pickables (`42d49aed`, `d4b21396` -> `interactables/valve_base.gd:1-675`, `interactables/pickable_object.gd:1-920`).
  - Checkpoint/killfield (`0edbfdf7` -> `interactables/checkpoint.gd:1-357`, `triggers/killfield.gd:1-43`), plug/socket puzzles (`2d0c41e6` -> `interactables/puzzle_socket.gd:1-500`, `interactables/tethered_plug.gd:1-192`), 3D keypad (`904094ce` -> `interactables/door_keypad.gd:1-291`).
  - GPU compute-shader dynamic ocean (`3d8ee4fd`, `2026-04-21` -> `dynamic_ocean/ocean.gd:1-700`, `dynamic_ocean/wave_generator.gd:1-357`).
  - Volumetric smoke (`301bfd3c`, `2026-04-30`, registering `SmokeManager` autoload at `environment/DynamicFog/smoke_manager.gd:1-258`) and real-time planar mirrors (`a43033e1`, `2026-05-30` -> `interactables/mirror.gd:1-327`).
- **First Static Type Gate (`77609b14`, `2026-04-01`)**: Enabled `gdscript/warnings/untyped_declaration=2` in `project.godot`.

### Phase 2: Component Pattern, Save/Graphics Singletons & Godot 4.7 Upgrade (`2026-06-01` to `2026-07-31`, `v0.3.1` -> `v0.4`)
- **Player State Machine & Component Decomposition (`f64216ae`, `2026-06-01`)**: Split the monolithic player script into finite state machines (`core/state_machine.gd:1-128`, `player/player_state_machine.gd:1-51`) and modular components (`player/locomotion_component.gd:1-424`, `player/player_interaction_component.gd:1-630`, `player/stats_component.gd:1-61`, `player/environment_component.gd:1-355`, `player/camera_controller.gd:1-629`).
- **Core Persistence & Rendering Autoloads (`d0424295` -> `fab57430`)**:
  - Added `SaveManager` (`d0424295`, `2026-06-04`; background-threaded in `6998d419`, `2026-07-04`; HMAC-SHA256 signed in `227e2933` & `5fbbc8e3` -> `core/save_manager.gd:1-385`).
  - Added `KeycardSystem` (`core/KeycardSystem.gd:1-44`) & `GraphicsManager` (`core/graphics_manager.gd:1-461`) in `c72b0077` (`2026-06-24`).
  - Added `ShockwaveManager` (`2ea8e236`, `2026-06-30` -> `vfx/ShockwaveManager3D.gd:1-103`) and `GlobalSettings` (`fab57430`, `2026-07-06` -> `core/global_settings.gd:1-464`).
- **Feature Releases `v0.3.1`–`v0.4`**: Pulley controller (`60088e85`, `v0.3.2` -> `interactables/pulley_controller.gd:1-113`), glider (`224eb668`, `v0.3.3` -> `interactables/glider_item.gd:1-393`, `player/state_glide.gd:1-232`), shader chapter animations (`a66651f4`, `v0.3.4` -> `ui/chapter_title_container.gd:1-573`), turret/targets (`32f7ca5f`, `v0.3.5` -> `enemies/turret.gd:1-507`, `interactables/shooting_target.gd:1-126`), and physics chain system (`e839a4c8`, `v0.4`).
- **Godot 4.7 Upgrade & Clouds (`d07c8ec6`, `f90c4de7`, `2026-07-16`–`07-17`)**: Upgraded `config/features` to `"4.7", "Forward Plus"` (`project.godot:16`), padded compute shader push constants to 16-byte alignment (`d07c8ec6`), and integrated `SunshineClouds2` (`f90c4de7`).
- **First GDLint & Formatting Sweeps (`3cd1592e`, `5b9404ba`, `ae2ab571`, `f5a8e9e0`)**: Enforced `gdlint` and `gdformat` across legacy scripts.

### Phase 3: Accessibility Suite, Input Abstraction & GUT Testing (`2026-08-01` to `2026-09-24`, `v0.4.1` -> `v0.4.4`)
- **Accessibility Autoload Wave (`96f35cf9` -> `d87e280d`)**:
  - `HighContrastManager` (`96f35cf9`, `2026-07-20` -> `ui/HighContrastManager.gd:1-76`).
  - `VisionAssistManager` (`6a6658d2`, `2026-08-04` -> `ui/VisionAssistManager.gd:1-266`).
  - `TTSManager` (`edeba2e7`, `2026-08-10`).
  - `SonarManager` & `SpatialDescriber` (`a03cfd57`, `2026-08-17` -> `core/audio/sonar_manager.gd:1-353`, `core/audio/spatial_describer.gd:1-547`).
  - `GestureInputManager` (`546aa591`, `2026-08-18` -> `core/gesture_input_manager.gd:1-493`).
  - `SubtitleLayer` (`a188bba7`, `2026-08-24` -> `ui/subtitle_layer.gd:1-410`) and `InputHelper` (`d87e280d`, `2026-08-26` -> `ui/InputHelper.gd:1-151`).
- **GUT 9.7.1 Unit Test Framework & CI (`88eef412`, `73ef4926`, `93e9fa64`, `2026-08-13`–`08-20`)**: Added headless GUT test runner and GitHub Actions verification.
- **Autoload `class_name` Stripping (`3ebe6d37`, `7278f13b`, `504ebdbb`, `5c32becf`, `1742ed2d`)**: Removed or commented out `# class_name` on Autoload scripts after Godot 4 parser errors when `class_name` matched Autoload singleton names.
- **Console & Post-Processing Autoloads (`e7958916`, `2026-09-21`)**: Added `PostProcessLayer` (`vfx/Post_Process_Layer.gd:1-134`) and `InGameConsole` (`ui/in_game_console.gd:1-509`).

### Phase 4: Core Helpers Consolidation & Zero-Tolerance Strict Typing (`2026-09-25` to `2026-10-17`, `v0.5.0`)
- **Core Helper Suite Creation (`46bb8c25` -> `463fa57d`, `2026-09-25`–`10-01`)**:
  - `46bb8c25` (`2026-09-25`): Created `Utilities` (`core/utilities.gd:1-160`).
  - `85f9b8f5` (`2026-09-28`): Created `CollisionLayers` (`core/collision_layers.gd:1-77`), `NodeQuery` (`core/node_query.gd:1-129`), `MaterialCache` (`core/material_cache.gd:1-50`), `MathUtils` (`core/math_utils.gd:1-163`), and `AudioPool` (`core/audio_pool.gd:1-131`, registered as autoload in `f5706efa`).
  - `d72d45e5` (`2026-09-30`): Added `Global` (`core/global.gd:1-91`), `AudioManager` (`core/audio_manager.gd:1-101`), and `SceneTransition` (`core/scene_transition.gd:1-142`) autoloads.
  - `463fa57d` (`2026-10-01`): Added `ObjectPool` (`core/object_pool.gd:1-233`) and `StateMachine` (`core/state_machine.gd:1-128`).
- **Zero-Tolerance GDScript Compiler Warnings (`6651f362`, `12cd9ec1`, `34383c97`, `ae90451c`, `2026-10-05`–`10-07`)**: Enabled `inferred_declaration=1`, `unsafe_property_access=2`, `unsafe_method_access=2`, `unsafe_cast=1`, `unsafe_call_argument=1` in `project.godot` (`6651f362`) and stripped `:=` inferred declarations across the repository.

### Phase 5: Domain Reorganization, Pooling & `BaseTriggerArea3D` (`2026-10-18` to `2026-10-31`, `v0.5.1` -> `v0.5.2`)
- **Modular 15-Directory Reorganization (`a36c56b7`, `42649b99`, `3261400e`, `652a27bf`)**: Moved root/scattered feature scripts into `core/`, `player/`, `enemies/`, `interactables/`, `weapons/`, `world/`, `environment/`, `dynamic_ocean/`, `triggers/`, `props/`, `ui/`, `vfx/`, `levels/`, `scenes/`, and `shaders/`.
  - *Artifact of Reorganization*: Left behind broken hard-coded `res://` strings in `core/splash_screen.gd:31` (`"res://scenes/main_menu.tscn"`), `core/start_screen.gd:6` (`"res://scenes/MainGame.tscn"`), `levels/testbed_loader.gd:6` (`"res://ui/loading_screen.tscn"`), `environment/lightning_scene.tscn:3` (`"res://interactive_lightning.gd"`), `environment/mat_ocean.tres:3`, and `environment/monke_bar.tscn:3`.
- **Trigger & Helper Standardization (`bd8d6318`, `d2fbc36e`, `0761fff4`, `ffa871d3`, `2026-10-19`)**: Extracted `BaseTriggerArea3D` (`triggers/base_trigger_area_3d.gd:1-271`) and `EditorTriggerVisualizer` (`triggers/editor_trigger_visualizer.gd:1-341`).
- **Pooled Gore VFX (`b234233e`, `3999cea6`, `2026-10-22`)**: Added `BloodManager` (`vfx/blood_manager.gd:1-398`), superseding legacy unreferenced `vfx/blood_decal.gd:1-44` and `vfx/blood_splatter.gd:1-44`.
- **VRAM Compression (`ab757091`, `2026-10-30`, `v0.5.2`)**: Enabled S3TC/BPTC & ETC2/ASTC VRAM compression and mipmaps.

### Phase 6: Combat Expansion, World Streaming & 60 FPS Gating (`2026-11-01` to `2026-11-09`, `v0.5.3`)
- **Combat & Hazards (`1123e3d7` -> `1fb8acc2`, `2026-11-03`–`11-05`)**: Added `ImpactManager` (`vfx/impact_manager.gd:1-201`, `1123e3d7`), `EnemySquid` (`enemies/squid/enemy_squid.gd:1-1030`) & `SensorTurret` (`enemies/sensor_turret.gd:1-402`, `1e341f4f`), `SignalRocketWeapon` (`weapons/signal_rocket/signal_rocket_weapon.gd:1-327`, `df6063a4`), and `FreecamController` (`core/console/freecam_controller.gd:1-178`, `ca9f2d14`). Tagged release `v0.5.3` (annotated tag object `8a083f3e` -> commit `fa7cbb6c`).
- **60 FPS Event Gating Sweep (`7aeb557c`, `2026-11-07`)**: Enforced `set_process(false)` / `set_physics_process(false)` gating, `distance_squared_to()`, and cached `NodeQuery` lookups across `core/`, `enemies/`, and `interactables/`.
- **250m World Chunk Streaming (`39c8e370`, `2026-11-09`)**: Replaced legacy virtual chunk manager (`bbd25403`) with `world/chunk_manager.gd:1-499`, `world/player_chunk_tracker.gd:1-52`, `world/chunk_root.gd:1-91`, and `ui/chunk_debug_hud.gd:1-228`.

### Phase 7: Asset Generation Skills, Forensics & CI Hardening (`2026-11-10` to `2026-11-14`, HEAD `290152af`)
- **AI/Blender Asset Pipelines (`1447a7b1`, `17831a76`, `f02d341c`, `a2af771c`, `5328e6ec`)**: Added `/pbr`, `/audio-generation`, `/3d`, `/animate`, and `/automation` pipelines plus modular props (`props/garage_gate/garage_gate.gd:1-345`, `props/gothic_arch/gothic_arch_post_import.gd:1-143`, `props/breakable_shelf/breakable_shelf.gd:1-157`) and `DarkManVisuals` (`enemies/dark_man/dark_man_visuals.gd:1-116`, `66fd8b89`).
- **Spike Forensics Autoload & CI Stubs (`353e06f6`, `c9c6b871`, `290152af`, `2026-11-14`)**: Added `SpikeForensics` (`core/spike_forensics.gd:1-309`) autoload in `290152af` (`project.godot:53`) to log frame budget overruns to `user://spike_forensics.jsonl`.

---

## 2. Implicit Architectural Contracts & Legacy Divergences

Because `core/utilities.gd` (`46bb8c25`), `core/collision_layers.gd` / `core/node_query.gd` / `core/material_cache.gd` / `core/audio_pool.gd` (`85f9b8f5`), zero-tolerance compiler warnings (`6651f362`), and the 60 FPS event-gating sweep (`7aeb557c`) were introduced in **Phases 4–6** (late September to November 2026), modules authored in **Phases 1–3** (March to September 2026) frequently diverge from newer architectural contracts.

### Contract 1: 60 FPS Event-Driven Execution & Process Gating
- **Canonical Standard**: Disable `_process()` and `_physics_process()` in `_ready()` (`set_process(false)` / `set_physics_process(false)`); wake nodes only via signals, `Area3D` overlap events, or `VisibleOnScreenNotifier3D`. Never allocate objects/arrays or call `print()` inside per-frame loops.
- **Where Legacy Modules Diverge**:
  - **Un-gated `_process()` (53 `.gd` files) and `_physics_process()` (28 `.gd` files)**:
    - `core/`: `core/global.gd:39-40` (runs every frame forever to increment `session_elapsed_seconds`), `core/gesture_input_manager.gd:45-118` (runs every frame even without UDP clients and allocates 3 `Array`s at `L46, 101, 110` + 4 `.keys()` arrays per frame), `core/interaction_manager.gd:58-59`, `core/state_machine.gd:62-70`, `core/components/rotator_component.gd:19-27`, `core/tts_interact_component.gd:29-35`, `core/dev_metrics.gd:83-85`, `core/frame_graph.gd:29-35` (calls `history.pop_front()` every frame at `L35`).
    - `enemies/`: `enemies/drone_swarm_controller.gd:151`, `enemies/elf_drone.gd:144`, `enemies/fire.gd:123, 137`, `enemies/flying_tile.gd:63`, `enemies/guardian_pillar.gd:57`, `enemies/guardian_projectile.gd:51`, `enemies/rook_trap.gd:67`, `enemies/spook_encounter.gd:188`, `enemies/tentacle.gd:42`, `enemies/tentacle_enemy.gd:99`.
    - `interactables/`: `interactables/PulleyCableVisual3D.gd:56`, `interactables/cable_builder.gd:31`, `interactables/combustible_object.gd:64`, `interactables/dev_comment/auto_scroll_container.gd:65`, `interactables/heavy_pickable_box.gd:170`, `interactables/jump_pad.gd:105`, `interactables/meat_cube.gd:52`, `interactables/output_transmitter_3d.gd:41`, `interactables/physics_cable3_d.gd:118, 130`, `interactables/player_drone.gd:132`, `interactables/pulley_controller.gd:53`, `interactables/push_wheel.gd:147`, `interactables/reflector_mirror.gd:74`, `interactables/stationary_laser_stand.gd:289`, `interactables/valve_base.gd:201`.
    - `environment/`, `dynamic_ocean/`, `player/`, `triggers/`, `ui/`, `vfx/`: `dynamic_ocean/waveheight_script.gd:46`, `environment/box_clouds.gd:58`, `environment/basalt_generator.gd:109`, `environment/citadel_core.gd:98`, `environment/electrified_floor.gd:45`, `environment/graphics_cctv_camera.gd:44`, `environment/interactive_lightning.gd:54`, `environment/lightning_orb.gd:80`, `environment/oil_spill_path.gd:166`, `environment/rotating_lamp.gd:56`, `environment/smoke_hazard.gd:230`, `environment/torch.gd:63`, `environment/twisted_hallway_logic.gd:31`, `environment/water_cube_test.gd:28`, `environment/wind_controller.gd:43`, `environment/wolf_climb_surface.gd:165`, `player/breakable_rope.gd:104`, `player/fast_rope.gd:170`, `player/flashlight_controller.gd:98`, `player/note_reader.gd:182`, `player/vault_controller.gd:95`, `player/weapon_procedural_animator.gd:185`, `player/zipline.gd:124`, `triggers/music_trigger.gd:167`, `ui/controls_panel.gd:175`, `ui/death_screen.gd:191`, `ui/diagnostics_panel.gd:229`, `ui/fps_counter.gd:15`, `ui/juicy_button.gd:67`, `ui/magnifying_glass_ui.gd:76`, `ui/notification_hud.gd:85`, `vfx/TinnitusEffect.gd:35`, `vfx/gel_emitter.gd:164`, `vfx/phys_explosion_3d.gd:60`.
  - **Per-Frame `print()` Statements (18 occurrences)**:
    - `player/state_fast_rope.gd:53`, `player/state_glide.gd:85`, `player/state_monkey_bars.gd:74`, `player/state_path_slide.gd:49`, `player/state_slide.gd:48`, `player/state_terminal.gd:43`, `player/state_tube.gd:74, 79`, `player/state_vault.gd:42`, `player/state_wolf_climb.gd:62`, `player/state_wolf_wall_run.gd:92`, `player/state_zipline.gd:103`, `environment/highlight_component.gd:146`, `environment/wolf_climb_surface.gd:189, 197`, `ui/loading_screen_anim.gd:205, 228`.
  - **Per-Frame Physics Query Allocations**:
    - `enemies/guardian_pillar.gd:81, 84, 120`, `enemies/spook_encounter.gd:631`, `player/state_air.gd:364`, `player/state_wolf_climb.gd:140`, `player/state_wolf_wall_run.gd:170`.

### Contract 2: Squared Proximity Checks (`distance_squared_to()`)
- **Canonical Standard**: Use `distance_squared_to()` instead of `distance_to()` to avoid `sqrt()` overhead in spatial queries and update loops.
- **Where Legacy Modules Diverge (35 occurrences across 20 files)**:
  - `core/audio/spatial_describer.gd:156, 192, 291, 292, 338`, `enemies/elf_drone.gd:442`, `enemies/rook_trap.gd:164, 197`, `environment/DynamicFog/dynamic_fog_zone.gd:318`, `environment/oil_spill_path.gd:276`, `environment/waypoint_3d.gd:206`, `interactables/cable_builder.gd:53`, `interactables/health_dispenser.gd:588`, `interactables/stationary_laser_stand.gd:592, 612`, `levels/procedural_blockout.gd:219, 289`, `player/breakable_rope.gd:171, 267, 268`, `player/flashlight_controller.gd:141`, `player/state_zipline.gd:68`, `ui/vrs_texture_generator.gd:24`, `vfx/phys_explosion_3d.gd:94`, `vfx/water_leak.gd:245, 246`.

### Contract 3: Jolt Physics Deferred Mutations (`set_deferred()` / `call_deferred()`)
- **Canonical Standard**: Never mutate `RigidBody3D.freeze`, `collision_layer`, `collision_mask`, `global_position`, `process_mode`, or call `queue_free()` synchronously inside Jolt Physics collision callbacks (`body_entered`, `body_exited`, `area_entered`). Always use `set_deferred(&"prop", val)` (with pre-allocated `StringName`) or `Callable.call_deferred()`.
- **Where Legacy Modules Diverge**:
  - **Synchronous Mutations Inside Collision Callbacks**:
    - `core/object_pool.gd:143-150, 188-195` (`_activate_instance` / `_deactivate_instance` mutate `RigidBody3D` state synchronously).
    - `triggers/crab_shell_trigger.gd:33` (`queue_free()` in `_on_body_entered`).
    - `enemies/flying_tile.gd:139` (`queue_free()` via `_on_body_entered`).
    - `enemies/spook_encounter.gd:606` (`queue_free()` via `_on_body_exited`).
    - `enemies/tentacle_enemy.gd:338` (`projectile.freeze = false` via `_on_detection_area_body_entered`).
    - `interactables/burnable_obstacle.gd:131` (`torch.queue_free()` via `_on_trigger_area_entered`).
    - `interactables/cell_recharger.gd:174` (`cell.freeze = true` via `_on_dock_area_body_entered`).
    - `interactables/lever_stick_item.gd:144` (`queue_free()` via `_on_detector_body_entered` / `_on_detector_area_entered`).
    - `interactables/pneumatic_tube.gd:201` (`rb.freeze = true` via `_on_intake_body_entered`).
    - `interactables/puzzle_socket.gd:359` (`rb_plug.freeze = false` via `_on_body_exited`).
    - `interactables/wall_generator.gd:185` (`cell.freeze = true` via `_on_socket_area_body_entered`).
  - **Raw `String` Instead of `StringName` in `set_deferred("...", ...)`**:
    - `enemies/hex_shield.gd:152, 154`, `interactables/burnable_obstacle.gd:163`, `interactables/drawbridge.gd:218, 219, 231`, `interactables/heavy_pickable_box.gd:125, 296`, `interactables/lever_stick_item.gd:50, 59, 69, 131`, `interactables/wall_generator.gd:190`, `player/breakable_rope.gd:254`.

### Contract 4: Physics & Render Layer Centralization (`CollisionLayers`)
- **Canonical Standard**: Reference named bitmasks and layer indices from `CollisionLayers` (`core/collision_layers.gd:1-77`) rather than raw integer literals. Physics Layer 11 is reserved for `Preview/Diorama`.
- **Where Legacy Modules Diverge (43 raw integer assignments)**:
  - Missing Layer 11 definition in `project.godot:218-230` and `core/collision_layers.gd:5-29` (`ui/options_router.gd:278, 279` hardcodes `1 << 10`).
  - Raw integer literals assigned to `collision_layer` / `collision_mask`: `enemies/dark_man/dark_man_visuals.gd:71`, `enemies/hex_shield.gd:84`, `enemies/hex_shield_sphere.gd:99`, `enemies/spook_encounter.gd:174`, `enemies/squid/enemy_squid.gd:500, 513`, `enemies/squid/squid_puddle.gd:78`, `environment/DynamicFog/dynamic_fog_zone.gd:225`, `environment/rain_controller.gd:203`, `environment/target_volume.gd:151, 152`, `interactables/combustible_object.gd:148`, `interactables/drawbridge.gd:79, 80`, `interactables/physics_magnet.gd:62, 64`, `interactables/pneumatic_tube.gd:83`, `interactables/rope/climb_rope.gd:729, 740`, `levels/procedural_blockout.gd:343, 344, 506, 507, 547, 548`, `player/breakable_rope.gd:95, 253, 287, 288`, `props/breakable_shelf/breakable_shelf.gd:111, 112`, `vfx/water_leak.gd:103`.

### Contract 5: Zero-Tolerance Strict Static Typing & Variant Narrowing
- **Canonical Standard**: Explicit types on all variables, collections (`Array[T]`, `Dictionary[K, V]`), and returns; narrow `Variant` values (such as `dict.get()`) with `is` into a typed local before calling `int(v)`/`float(v)`/`str(v)`/`bool(v)` or passing to typed parameters; never duplicate function calls in ternary type checks; zero `@warning_ignore` outside `core/events.gd`.
- **Where Legacy Modules Diverge**:
  - **0 `:=` inferred declarations remain**, confirming Phase 4 (`6651f362`) succeeded on `:=`.
  - **280+ untyped `Array` / `Dictionary` declarations** remain across `core/`, `world/`, gameplay, and UI/environment (mostly state machine `msg: Dictionary = {}`, raycast result `hit: Dictionary`, and JSON/config dictionaries).
  - **Un-narrowed `dict.get()` / `Variant` conversions** in `core/audio/sonar_manager.gd:173-174, 177-178, 187-188, 194-197`, `core/audio/spatial_describer.gd:120, 188-191, 289-290`, `enemies/spook_encounter.gd:518`, `enemies/turret.gd:373`, `dynamic_ocean/waveheight_script.gd:51-55`, `ui/diagnostics_panel.gd:879, 880, 1365-1415`, etc.
  - **6 duplicated function calls in ternary type checks** (`core/state_machine.gd:41, 87`, `core/components/health_modifier.gd:238`, `core/singletons/system_locator.gd:45, 102`, `core/save_manager.gd:248-250`).
  - **44 `@warning_ignore` annotations** outside `core/events.gd`.

### Contract 6: Resource Caching, Material Sharing & Zero Runtime Synchronous `load()`
- **Canonical Standard**: Never call synchronous `load()` / `ResourceLoader.load()` at runtime (use `preload()` or `ResourceLoader.load_threaded_request()`). Share materials via `MaterialCache` (`core/material_cache.gd:1-50`) or `set_instance_shader_parameter()` with pre-allocated `&"StringName"` uniform keys.
- **Where Legacy Modules Diverge**:
  - **17 Runtime Synchronous `load()` / `ResourceLoader.load()` Calls**:
    1. `core/events.gd:764` (`load(res_path)` in `apply_dyslexic_font_to_node`)
    2. `core/global_settings.gd:258` (`load(path)` in `_load_font`)
    3. `core/render_context.gd:102` (`load(shader_filename)` in `load_compute_shader`)
    4. `core/console/console_cheat_commands.gd:735` (`load(scene_path)` in `_cmd_spawn`)
    5. `core/console/console_cheat_commands.gd:828` (`load(scene_path)` in `_cmd_give`)
    6. `core/console/console_cheat_commands.gd:908` (`load(scene_path)` in `_cmd_summon`)
    7. `world/chunk_manager.gd:298` (`load(scene_path)` fallback in `_start_loading_chunk`)
    8. `interactables/meat_cube.gd:32` (`ResourceLoader.load(meat_cube_scene_path)` in `_ready`)
    9. `interactables/meat_cube.gd:96` (`ResourceLoader.load(meat_cube_scene_path)` in `_respawn_cube`)
    10. `interactables/ui_circle_keypad.gd:187` (`load(path)` in `_load_button_icon`)
    11. `weapons/signal_rocket/signal_rocket_weapon.gd:69` (`ResourceLoader.load(PROJECTILE_SCENE_PATH)` in `_ready`)
    12. `environment/gothic_energy_gate.gd:530` (`load(SHADER_PATH)`)
    13. `environment/supply_shell.gd:238` (`ResourceLoader.load(default_ammo_box_path)`)
    14. `levels/testbed_loader.gd:53` (`load(DEFAULT_LOADING_SCREEN_PATH)`)
    15. `ui/InputHelper.gd:103` (`load(full_path)`)
    16. `ui/controls_panel.gd:1028` (`load(p)`)
    17. `vfx/Post_Process_Layer.gd:114` (`load(shader_path)`)
  - **3 Runtime Material `.duplicate()` Calls**: `environment/DynamicFog/dynamic_fog_zone.gd:207`, `environment/powered_light_3d.gd:367`, `interactables/tethered_plug.gd:183`.
  - **78 Un-cached String Shader Parameter Calls (`set_shader_parameter("...", ...)`)** across `environment/`, `ui/`, and `vfx/`.

### Contract 7: Tween Lifecycle Management & Global Signal Cleanup
- **Canonical Standard**: Kill active tweens via `Utilities.reset_tween()` before creating new tweens. Non-persistent nodes connecting to `Events` or `GlobalSettings` must disconnect in `_exit_tree()`.
- **Where Legacy Modules Diverge**:
  - **96 raw `create_tween()` calls** in scripts that never invoke `Utilities.reset_tween()` (e.g., `core/scene_transition.gd:98, 133`, `core/vfx/screen_effects_core.gd:179, 245, 394`, `enemies/guardian_projectile.gd:82`, `enemies/hex_shield.gd:111, 168`, `enemies/hex_shield_sphere.gd:166, 238, 292, 342, 371`, `enemies/squid/squid_puddle.gd:128, 156`, `ui/screen_effects_manager.gd:208, 224, 335, 549, 580, 597, 669, 696, 736, 800, 839, 902, 924`, `ui/tag_notification.gd:132, 188`).
  - **Missing or Partial `_exit_tree()` Signal Disconnects**:
    - Non-persistent scripts with no `_exit_tree()` at all: `core/camera_shake_manager.gd:55-56`, `core/vfx/screen_effects_core.gd:88, 102-111, 123`, `environment/gothic_energy_gate.gd:302`, `environment/world_environment.gd:11`, `interactables/pickable_object.gd:215-216`, `interactables/puzzle_socket.gd:139`, `interactables/valve_base.gd:170`, `player/camera_3d.gd:89-101`, `player/player_interaction_component.gd:134`, `player/state_swim.gd:65`, `player/system_menu_controller.gd:105-108`, `player/vault_controller.gd:90`, `triggers/editor_trigger_visualizer.gd:103`, `ui/accessibility_panel.gd:111-115`, `ui/death_screen.gd:178`, `ui/debug_overlay.gd:136-142`, `ui/diorama_post_process.gd:23, 25`, `ui/magnifying_glass_ui.gd:42, 44`, `ui/notification_hud.gd:122-135`, `ui/subs_audio_section.gd:158-162`.
    - Scripts with partial `_exit_tree()` that leave `Events` signals connected: `enemies/drone_swarm_controller.gd:146`, `environment/highlight_component.gd:249-281`, `interactables/portal.gd:77, 88`, `ui/chapter_title_container.gd:104, 108`, `ui/player_status_hud.gd:258-270`, `ui/screen_effects_manager.gd:492-514`, `ui/ui.gd:85-93`.
