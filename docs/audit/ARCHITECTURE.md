# BellaSDK Architectural & Code Audit (`ARCHITECTURE.md`)

## 1. Executive Summary & Repository Inventory

BellaSDK is a Godot `4.7.1` (`Forward Plus` renderer, `Jolt Physics` 3D engine, `run/max_fps=60`) first-person immersive simulation and physics sandbox SDK. Across its **15 runtime directories** (excluding `addons/`, `.godot/`, and `test/`), the codebase comprises **595 runtime script and shader files** (**385 `.gd` scripts** and **210 `.gdshader` shaders**), plus **7 GLSL compute shaders (`.glsl`)** in `dynamic_ocean/`.

| Directory | Total Files (`.gd` + `.gdshader`) | `.gd` Files | `.gdshader` Files | `wc -l` Lines | Total Lines (`splitlines`) | Primary Responsibility |
|---|---:|---:|---:|---:|---:|---|
| `core/` | 50 | 50 | 0 | 12,235 | 12,235 | Autoloads, event bus, save/settings, pooling, FSM, console, accessibility, profiling |
| `player/` | 47 | 46 | 1 | 13,696 | 13,697 | `Player` controller, 18 `PlayerState` classes, locomotion/interaction/camera components |
| `enemies/` | 21 | 21 | 0 | 7,489 | 7,489 | Multi-state boss/swarm/stalker AI, turrets, traps, shields, hazards |
| `interactables/` | 96 | 83 | 13 | 20,879 | 20,882 | `InteractComponent`, `PickableObject` hierarchy, doors, locks, puzzles, heavy machinery |
| `weapons/` | 7 | 6 | 1 | 1,890 | 1,890 | `ThrowableWeapon` base, `SignalRocketWeapon`, `SmokeGrenadeWeapon`, volumetric smoke cloud |
| `world/` | 5 | 4 | 1 | 780 | 780 | 3x3 grid `ChunkManager`, `ChunkRoot` delta persistence, `PlayerChunkTracker` |
| `environment/` | 100 | 62 | 38 | 21,130 | 21,144 | Water bodies, `SmokeManager`, weather/rain/fog, procedural geometry, soundscapes |
| `dynamic_ocean/` | 8 | 4 | 4 | 1,699 | 1,699 | GPU FFT compute ocean (`WaveGenerator` + 7 `.glsl` shaders = 485 lines), CPU/GPU buoyancy |
| `triggers/` | 15 | 15 | 0 | 2,157 | 2,157 | `BaseTriggerArea3D` contract, `EditorTriggerVisualizer`, 13 spatial trigger volumes |
| `props/` | 7 | 4 | 3 | 857 | 857 | Modular destructible/animated props (`breakable_shelf`, `garage_gate`, `gothic_arch`) |
| `ui/` | 75 | 60 | 15 | 22,053 | 22,058 | 6 UI Autoloads, HUDs, `OptionsRouter`, settings panels, `RenderDiagnosticsPanel` |
| `vfx/` | 140 | 27 | 113 | 11,896 | 11,955 | 4 VFX Autoloads (`ShockwaveManager`, `PostProcessLayer`, `BloodManager`, `ImpactManager`), 113 shaders |
| `levels/` | 2 | 2 | 0 | 861 | 861 | `DevTestbedLoader` (`levels/testbed_loader.gd`), `ProceduralBlockout` (`levels/procedural_blockout.gd`) |
| `scenes/` | 1 | 1 | 0 | 220 | 220 | `ExplosionCrysis` prefab (`scenes/vfx/explosion_crysis.gd`) and glass shader preview scenes |
| `shaders/` | 21 | 0 | 21 | 1,247 | 1,247 | Shared surface, glass, rain particle, and post-processing `.gdshader` programs |
| **TOTAL** | **595** | **385** | **210** | **119,089** | **119,171** | *(82 `.gdshader` files omit a trailing newline: `119,171 - 119,089 = 82`)* |

---

## 2. Entry Points, Autoload Initialization Order & Project Configuration

### 2.1 Project Configuration & Entry Points (`project.godot:1-283`)
- **Primary Boot Entry Scene**: `project.godot:15` sets `run/main_scene="uid://ctplsgipirsn1"` -> `res://levels/testbed_loader.tscn` (`levels/testbed_loader.gd:1-72`, `class_name DevTestbedLoader` at `L2`).
  - `DevTestbedLoader` auto-launches in debug builds (`levels/testbed_loader.gd:26-28`) or on `KEY_F1` (`levels/testbed_loader.gd:18, 36-40`), instantiating `ui/loading_screen_anim.tscn` (via scene export override at `levels/testbed_loader.tscn:8`) and streaming `res://levels/testbed.tscn` (`levels/testbed_loader.tscn:7`, `levels/testbed_loader.gd:71`).
  - **Defect**: `DEFAULT_LOADING_SCREEN_PATH` at `levels/testbed_loader.gd:6` points to `"res://ui/loading_screen.tscn"` (file does not exist on disk; actual scene is `res://ui/loading_screen_anim.tscn`).
- **Engine, Physics & Rendering Settings**:
  - `project.godot:16`: `config/features=PackedStringArray("4.7", "Forward Plus")`
  - `project.godot:17`: `run/max_fps=60`
  - `project.godot:233`: `3d/physics_engine="Jolt Physics"` (under `[physics]`)
  - `project.godot:243`: `anti_aliasing/quality/screen_space_aa=1` (under `[rendering]`)
  - `project.godot:246`: `[shader_globals]`
- **Splash, Icon & Audio Bus Layout**:
  - `project.godot:19`: `boot_splash/image="uid://bjct27ta2nogv"` -> `res://assets/images/Bella_and_Godiva_Logo.png`
  - `project.godot:20`: `config/icon="uid://cijw0jse7sfs8"` -> `res://assets/Bella_SDK_Logo.svg`
  - `project.godot:24`: `buses/default_bus_layout="uid://d3qajd8tvw6tr"` -> `res://core/audio/default_bus_layout.tres`
- **Legacy / Broken Entry Scenes in `core/`**:
  - `core/splash_screen.gd:1-31` (`SplashScreen`, `core/splash_screen.tscn`): Fades logo and calls `get_tree().change_scene_to_file("res://scenes/main_menu.tscn")` at `core/splash_screen.gd:31` (**broken path** — actual menu is `res://ui/main_menu.tscn`).
  - `core/start_screen.gd:1-43` (`StartScreen`, `core/start_screen.tscn`): Declares `@export_file("*.tscn") var main_game_scene_path: String = "res://scenes/MainGame.tscn"` at `core/start_screen.gd:6` (**broken default path** — does not exist on disk).
- **Input Map Key Collision (`project.godot:173-182`)**:
  - `sonar_ping` (`project.godot:173-177`) and `describe_surroundings` (`project.godot:178-182`) both bind physical keycode `84` (`KEY_T`).
- **Physics Layer Configuration & Missing Layer 11 (`project.godot:218-230` & `core/collision_layers.gd:5-29`)**:
  - Named 3D Render Layers: Layer 1 `Environment`, Layer 2 `Player`, Layer 3 `Interactive`, Layer 4 `Portals`, Layer 10 `Volumetrics` (`core/collision_layers.gd:35-44`).
  - Named 3D Physics Layers: Layer 1 `Environment` (`MASK_ENVIRONMENT = 1`), Layer 2 `Player` (`MASK_PLAYER = 2`), Layer 3 `Interactive` (`MASK_INTERACTIVE = 4`), Layer 4 `Debris` (`MASK_DEBRIS = 8`), Layer 5 `Enemies` (`MASK_ENEMIES = 16`) (`core/collision_layers.gd:5-29`).
  - **Defect**: Physics Layer 11 (`Preview/Diorama`) is omitted from both `project.godot:218-230` `[layer_names]` and `core/collision_layers.gd:5-29`, forcing `ui/options_router.gd:278` to hardcode `1 << 10`.

### 2.2 Autoload Initialization Order (26 Autoloads, `project.godot:28-53`)

| Boot Order | Autoload Name | `project.godot` Line | Target Script / Scene | Domain | Primary Role |
|---:|---|---:|---|---|---|
| 1 | `Global` | `project.godot:28` | `res://core/global.gd` (`1-91`) | `core/` | Seeded `RandomNumberGenerator`, `game_seed`, `session_elapsed_seconds`, `_runtime_cache` |
| 2 | `Events` | `project.godot:29` | `res://core/events.gd` (`1-793`) | `core/` | Central signal bus (154 signals) + `apply_dyslexic_font_to_node()` (`L711-793`) |
| 3 | `DebugManager` | `project.godot:30` | `res://ui/debug_manager.gd` (`1-27`) | `ui/` | Tracks `wireframe_enabled` and connects to `Events.wireframe_toggled` (`L14`) |
| 4 | `SaveManager` | `project.godot:31` | `res://core/save_manager.gd` (`1-385`) | `core/` | JSON + HMAC-SHA256 save slots, screenshot capture, threaded save queue |
| 5 | `KeycardSystem` | `project.godot:32` | `res://core/KeycardSystem.gd` (`1-44`) | `core/` | Typed keycard inventory (`var _inventory: Array[StringName] = []` at `L19`) |
| 6 | `GraphicsManager` | `project.godot:33` | `res://core/graphics_manager.gd` (`1-461`) | `core/` | Window/VSync/quality presets, VRS texture, colorblind filter, diorama mode, compositor cache |
| 7 | `GlobalSettings` | `project.godot:34` | `res://core/global_settings.gd` (`1-464`) | `core/` | `user://settings.cfg` persistence, font/palette/filter registries, boot settings applier |
| 8 | `HighContrastManager` | `project.godot:35` | `res://ui/HighContrastManager.gd` (`1-76`) | `ui/` | Applies high-contrast materials to `high_contrast_enemy`/`item`/`hazard` groups |
| 9 | `VisionAssistManager` | `project.godot:36` | `res://ui/VisionAssistManager.gd` (`1-266`) | `ui/` | Applies `ui/VisionAssist.gdshader` variants via `MaterialCache.get_variant()` (`L253`) |
| 11 | `SonarManager` | `project.godot:38` | `res://core/audio/sonar_manager.tscn` (`core/audio/sonar_manager.gd:1-353`) | `core/` | 360-degree physics shape-cast echolocation + sequential 2D harmonic pings |
| 12 | `TTSManager` | `project.godot:39` | `res://addons/piper_tts_extension/tts_manager.tscn` | `addons/` | Neural text-to-speech synthesis manager |
| 13 | `SpatialDescriber` | `project.godot:40` | `res://core/audio/spatial_describer.tscn` (`core/audio/spatial_describer.gd:1-547`) | `core/` | 3D sphere query + LOS raycast + semantic clustering + TTS announcement |
| 14 | `GestureInputManager` | `project.godot:41` | `res://core/gesture_input_manager.gd` (`1-493`) | `core/` | UDP JSON socket (port 5005) gesture-to-`InputMap` bridge |
| 15 | `SubtitleLayer` | `project.godot:42` | `res://ui/SubtitleLayer.tscn` (`ui/subtitle_layer.gd:1-410`) | `ui/` | `CanvasLayer` (`layer = 120`) speaker-colored subtitles and directional indicators |
| 16 | `InputHelper` | `project.godot:43` | `res://ui/InputHelper.gd` (`1-151`) | `ui/` | Maps `InputMap` actions to Kenney prompt icons and readable key names |
| 17 | `ShockwaveManager` | `project.godot:44` | `res://vfx/shockwave_manager.tscn` (`vfx/ShockwaveManager3D.gd:1-103`) | `vfx/` | Pools 8 refractive 3D shockwave meshes (`vfx/3d_shockwave.tscn`) |
| 18 | `PostProcessLayer` | `project.godot:45` | `res://vfx/Post_Process_Layer.gd` (`1-134`) | `vfx/` | `CanvasLayer` (`layer = 100`) full-screen colorblind, high-contrast, grain, and artistic filters |
| 19 | `InGameConsole` | `project.godot:46` | `res://ui/in_game_console.tscn` (`ui/in_game_console.gd:1-509`) | `ui/` | Developer console UI dispatching to `ConsoleSystemCommands`, `ConsoleSettingsCommands`, `ConsoleCheatCommands` |
| 20 | `AudioPool` | `project.godot:47` | `res://core/audio_pool.gd` (`1-131`) | `core/` | 16x `AudioStreamPlayer3D` + 8x `AudioStreamPlayer` ring-buffer pools |
| 21 | `AudioManager` | `project.godot:48` | `res://core/audio_manager.gd` (`1-101`) | `core/` | Audio bus volume/mute control + crossfading music players |
| 22 | `SceneTransition` | `project.godot:49` | `res://core/scene_transition.gd` (`1-142`) | `core/` | Threaded scene transition overlay (`change_scene_to_file()` at `L83`) |
| 23 | `SmokeManager` | `project.godot:50` | `res://environment/DynamicFog/smoke_manager.gd` (`1-258`) | `environment/` | Tracks up to 32 smoke puffs (`MAX_PUFFS = 32` at `L9`), LOS smoke occlusion, `32x2` `ImageTexture` |
| 24 | `BloodManager` | `project.godot:51` | `res://vfx/blood_manager.gd` (`1-398`) | `vfx/` | Ring-buffer pools (16 spray, 16 mist, 64 decals) triggered via `Events.blood_fx_requested` (`L99`) |
| 25 | `ImpactManager` | `project.godot:52` | `res://vfx/impact_manager.gd` (`1-201`) | `vfx/` | Ring-buffer pools (16 sparks, 64 decals) triggered via `Events.bullet_impact_requested` (`L62`) |
| 26 | `SpikeForensics` | `project.godot:53` | `res://core/spike_forensics.gd` (`1-309`) | `core/` | Frame time budget tracker + `user://spike_forensics.jsonl` spike attribution logger |

---

## 3. Subsystem Architecture & Data/Signal Flows

### 3.1 Core Services, Pooling & World Streaming (`core/`, `world/`)
- **Static Core Helpers**:
  - `CollisionLayers` (`core/collision_layers.gd:1-77`), `MaterialCache` (`core/material_cache.gd:1-50`), `MathUtils` (`core/math_utils.gd:1-163`), `NodeQuery` (`core/node_query.gd:1-129`), `ReferenceData` (`core/reference_data.gd:1-38`), `Types` (`core/types.gd:1-133`), `Utilities` (`core/utilities.gd:1-160`), `SystemLocator` (`core/singletons/system_locator.gd:1-105`), `ShaderCacheBuilder` (`core/shader_cache_builder.gd:1-92`).
- **Pooling & State Machines**:
  - `ObjectPool` (`core/object_pool.gd:1-233`): Generic `Node` pool managing inactive/active instances (`spawn()` at `L73`, `recycle()` at `L111`).
  - `State` (`core/state.gd:1-35`) & `StateMachine` (`core/state_machine.gd:1-128`): Hierarchical FSM base classes.
- **Reusable Entity Components**:
  - `FactionComponent` (`core/components/faction_component.gd:1-64`), `HealthComponent` (`core/components/health_component.gd:1-147`), `HealthModifier` (`core/components/health_modifier.gd:1-250`), `PoweredObject` (`core/components/powered_object.gd:1-71`), `RotatorComponent` (`core/components/rotator_component.gd:1-27`), `TTSInteractComponent` (`core/tts_interact_component.gd:1-63`), `InteractionManager` (`core/interaction_manager.gd:1-156`).
- **Developer Console & Profiling**:
  - `ConsoleCommand` (`core/console_command.gd:1-30`), `ConsoleCommandRegistry` (`core/console_command_registry.gd:1-87`), `ConsoleHistory` (`core/console_history.gd:1-56`), `ConsoleContext` (`core/console/console_context.gd:1-91`), `ConsoleSystemCommands` (`core/console/console_system_commands.gd:1-449`), `ConsoleSettingsCommands` (`core/console/console_settings_commands.gd:1-1300`), `ConsoleCheatCommands` (`core/console/console_cheat_commands.gd:1-1698`), `freecam_controller.gd` (`core/console/freecam_controller.gd:1-178`).
  - `DevMetricsPanel` (`core/dev_metrics.gd:1-451`), `FrameGraph` (`core/frame_graph.gd:1-89`), `RenderingContext` (`core/render_context.gd:1-249`), `ShaderCache` (`core/shader_cache.gd:1-14`), `TextureBaker` (`core/texture_baker.gd:1-279`), `SaveSlot` (`core/save_slot.gd:1-137`).
- **World Streaming (`world/`)**:
  - `ChunkManager` (`world/chunk_manager.gd:1-499`): Streams a `3x3` active grid (`ACTIVE_RADIUS = 1`, `CHUNK_SIZE = 64.0` at `world/chunk_manager.gd:9-13`) via `ResourceLoader.load_threaded_request` (`L295`), time-budgeted instantiation (`MAX_INSTANTIATE_MS_PER_FRAME = 2.0` at `L19, 326`), stateful entity delta persistence (`_world_save_state` at `L48, 399-413`), and roaming entity cross-chunk handoffs (`_roaming_entities` at `L55, 211-285, 422-463`).
  - `ChunkRoot` (`world/chunk_root.gd:1-91`): Scans `"stateful"` group children (`L26`), restores state via `load_save_data` (`L39`), connects `state_mutated` (`L43`), and emits `Events.chunk_entity_mutated` (`L74`).
  - `PlayerChunkTracker` (`world/player_chunk_tracker.gd:1-52`): Polls player XZ coordinates every `0.2s` (`L11, 21-26`), calls `chunk_manager.update_player_chunk(new_coord)` (`L49`), and emits `Events.player_chunk_changed` (`L47`).

### 3.2 Gameplay Domains (`player/`, `weapons/`, `enemies/`, `interactables/`, `triggers/`, `props/`)
- **`player/` Subsystem (47 files, 13,696 lines)**:
  - `Player` (`player/player.gd:1-887`, `CharacterBody3D` in group `&"player"` at `L163`): Orchestrates `PlayerLocomotionComponent` (`player/locomotion_component.gd:1-424`), `PlayerInteractionComponent` (`player/player_interaction_component.gd:1-630`), `InteractionScanner` (`player/player_interaction_scanner.gd:1-446` + `player/holographic_scanner.gdshader:1-40`), `PlayerEnvironmentComponent` (`player/environment_component.gd:1-355`), `PlayerStatsComponent` (`player/stats_component.gd:1-61`), `CameraController` (`player/camera_controller.gd:1-629`), `ExtendedCamera3D` (`player/camera_3d.gd:1-358`), `VaultController` (`player/vault_controller.gd:1-402`), `StairController` (`player/stair_controller.gd:1-224`), `WeaponInventoryComponent` (`player/weapon_inventory_component.gd:1-259`), `WeaponProceduralAnimator` (`player/weapon_procedural_animator.gd:1-466`), `FlashlightController` (`player/flashlight_controller.gd:1-171`), `FootstepManager` (`player/footstep_manager.gd:1-323`), `NoteReader` (`player/note_reader.gd:1-496`), `DrunkEffect` (`player/drunk_effect.gd:1-182`), `SystemMenuController` (`player/system_menu_controller.gd:1-362`), and `PhysicsPusher` (`player/physics_pusher.gd:1-80`).
  - `PlayerStateMachine` (`player/player_state_machine.gd:1-51`) & `PlayerState` (`player/player_state.gd:1-68`): Drives **18 concrete `PlayerState` subclasses** (`StateGround`, `StateAir`, `StateSwim`, `StateSlide`, `StateVault`, `StateLadder`, `StateRope`, `StateFastRope`, `StateZipline`, `StateGlide`, `StateMonkeyBars`, `StateWolfClimb`, `StateWolfWallRun`, `StateJibCrane`, `StatePathSlide`, `StateTerminal`, `StateTube`, `PushWheelState`) plus `StateMachineLock` (`player/StateMachineLock.gd:1-50`, which extends `Node`).
- **`weapons/` Subsystem (7 files, 1,890 lines)**:
  - `ThrowableWeapon` (`weapons/throwable_weapon.gd:1-482`) -> extended by `SignalRocketWeapon` (`weapons/signal_rocket/signal_rocket_weapon.gd:1-327`, spawning `SignalRocketProjectile` at `weapons/signal_rocket/signal_rocket_projectile.gd:1-378`) and `SmokeGrenadeWeapon` (`weapons/smoke_grenade/smoke_grenade_weapon.gd:1-31`, spawning `SmokeGrenadeProjectile` at `weapons/smoke_grenade/smoke_grenade_projectile.gd:1-72` -> `SmokeGrenadeCloud` at `weapons/smoke_grenade/smoke_grenade_cloud.gd:1-378` + `weapons/smoke_grenade/smoke_grenade_cloud.gdshader:1-222`).
- **`enemies/` Subsystem (21 files, 7,489 lines)**:
  - `EnemySquid` (`enemies/squid/enemy_squid.gd:1-1030`) + `SquidPuddle` (`enemies/squid/squid_puddle.gd:1-258`), `DroneSwarmController` (`enemies/drone_swarm_controller.gd:1-539`) + `ElfDrone` (`enemies/elf_drone.gd:1-466`), `SpookEncounter` (`enemies/spook_encounter.gd:1-655`), `TentacleEnemy` (`enemies/tentacle_enemy.gd:1-464`) + `ProceduralTentacle3D` (`enemies/tentacle.gd:1-117`), `EvilGoon` (`enemies/evil_goon.gd:1-142`), `DarkManVisuals` (`enemies/dark_man/dark_man_visuals.gd:1-116`), `Turret` (`enemies/turret.gd:1-507`), `sensor_turret.gd` (`enemies/sensor_turret.gd:1-402`), `GuardianPillar` (`enemies/guardian_pillar.gd:1-196`) + `EnergyBlast` (`enemies/guardian_projectile.gd:1-123`), `BearTrap` (`enemies/bear_trap.gd:1-126`), `RookTrap` (`enemies/rook_trap.gd:1-236`), `TripMine` (`enemies/tripmine.gd:1-444`), `FlyingTile` (`enemies/flying_tile.gd:1-139`), `VolumetricFire` (`enemies/fire.gd:1-457`), `HexShield` (`enemies/hex_shield.gd:1-187`), `HexShieldSphere` (`enemies/hex_shield_sphere.gd:1-711`).
- **`interactables/`, `triggers/`, `props/` (118 files, 23,893 lines)**:
  - `InteractComponent` (`interactables/interact_component.gd:1-104`, `Area3D` on `CollisionLayers.MASK_INTERACTIVE` at `L45`), `OutputTransmitter3D` (`interactables/output_transmitter_3d.gd:1-135`), and `PickableObject` (`interactables/pickable_object.gd:1-920`) with 9 subclasses (`EnergyCell`, `HeavyPickableBox`, `LeverStickItem`, `PickableLiquidBottle`, `PickableBox`, `PickableTire`, `PickableValve`, `TetheredPlug`, `CinderBlock`).
  - `BaseTriggerArea3D` (`triggers/base_trigger_area_3d.gd:1-271`) + `EditorTriggerVisualizer` (`triggers/editor_trigger_visualizer.gd:1-341`) + 13 trigger subclasses.

### 3.3 Presentation, Ocean, Environment, UI & VFX (`dynamic_ocean/`, `environment/`, `ui/`, `vfx/`, `shaders/`, `levels/`, `scenes/`)
- **GPU Compute FFT Ocean (`dynamic_ocean/wave_generator.gd:1-357`, `dynamic_ocean/ocean.gd:1-700`)**:
  - `WaveGenerator` dispatches 7 GLSL compute shaders (`spectrum_compute.glsl`, `fft_butterfly.glsl`, `spectrum_modulate.glsl`, `fft_compute.glsl`, `transpose.glsl`, `fft_unpack.glsl`, `downsample_compute.glsl` at `dynamic_ocean/wave_generator.gd:84-104`) via `RenderingContext`.
  - `Ocean` binds `Texture2DArrayRD` RIDs to global shader parameters `&"displacements"` and `&"normals"` (`dynamic_ocean/ocean.gd:552-553`) and performs async GPU readback via `RenderingDevice.texture_get_data_async` (`dynamic_ocean/ocean.gd:655-680`) with analytical `MathUtils.gerstner_wave()` fallback (`L361-365`).
- **Environment & Triplicate Water Systems (`environment/`)**:
  - Contains three parallel water + underwater fog implementations: `WaterBody` (`environment/water_body.gd:1-1538`), `ArgonWaterBody` (`environment/argon_water_body/argon_water_body.gd:1-752`), and `HydrogenWaterBody` (`environment/hydrogen_water_body/hydrogen_water_body.gd:1-1165`).
- **UI Layer (`ui/`)**:
  - **6 UI Autoloads** (`DebugManager`, `HighContrastManager`, `VisionAssistManager`, `SubtitleLayer`, `InputHelper`, `InGameConsole`), `UIController` (`ui/ui.gd:1-280`), `MainMenu` (`ui/main_menu.gd:1-408`), and `OptionsRouter` (`ui/options_router.gd:1-432`).

---

## 4. Dependency Graph, Circular Dependencies & Dead Code Inventory

### 4.1 Dependency Graph Topology & Hub Fan-In
- **Leaf Files (Zero Outbound Runtime Dependencies)**: **310 files** (**210 `.gdshader` files** + **100 `.gd` files**).
- **Connected GDScript Files**: **285 `.gd` files** reference `>= 1` other runtime script/autoload.
- **Top 15 Hub Dependencies (Highest Inbound Runtime Fan-In)**:
  1. `core/events.gd` (`Events`): **115** inbound scripts (`793` lines)
  2. `core/collision_layers.gd` (`CollisionLayers`): **76** inbound scripts (`77` lines)
  3. `core/utilities.gd` (`Utilities`): **67** inbound scripts (`160` lines)
  4. `core/node_query.gd` (`NodeQuery`): **61** inbound scripts (`129` lines)
  5. `player/player.gd` (`Player`): **33** inbound scripts (`887` lines)
  6. `core/global_settings.gd` (`GlobalSettings`): **33** inbound scripts (`464` lines)
  7. `core/gesture_input_manager.gd` (`GestureInputManager`): **32** inbound scripts (`493` lines)
  8. `core/components/health_component.gd` (`HealthComponent`): **26** inbound scripts (`147` lines)
  9. `interactables/interact_component.gd` (`InteractComponent`): **25** inbound scripts (`104` lines)
  10. `core/math_utils.gd` (`MathUtils`): **25** inbound scripts (`163` lines)
  11. `player/locomotion_component.gd` (`PlayerLocomotionComponent`): **20** inbound scripts (`424` lines)
  12. `player/player_state.gd` (`PlayerState`): **19** inbound scripts (`68` lines)
  13. `player/camera_controller.gd` (`CameraController`): **17** inbound scripts (`629` lines)
  14. `interactables/pickable_object.gd` (`PickableObject`): **16** inbound scripts (`920` lines)
  15. `core/types.gd` (`Types`): **15** inbound scripts (`133` lines)

### 4.2 Verified Circular Dependencies & Boot-Order Inversions
1. **`State` <-> `StateMachine` <-> `PlayerStateMachine` Cycle (Base-to-Subclass Violation)**:
   - `core/state.gd:10` declares `var state_machine: StateMachine = null` <-> `core/state_machine.gd:9, 15, 24, 27` references `State`.
   - `core/state_machine.gd:35` checks `if self is PlayerStateMachine:` inside base `StateMachine._ready()`, coupling `core/` directly to subclass `player/player_state_machine.gd:3` (`extends StateMachine`).
2. **`GraphicsManager` (`project.godot:33`) <-> `GlobalSettings` (`project.godot:34`) <-> `VideoApplier` (`ui/video_applier.gd`) <-> `MainMenu` (`ui/main_menu.gd`) Cycle**:
   - `GraphicsManager._ready()` (`core/graphics_manager.gd:39`) calls `load_from_disk()` (`L59-69`), which calls `GlobalSettings.get_setting*` BEFORE `GlobalSettings._ready()` runs (only surviving because `GlobalSettings._init()` loads `settings.cfg` at `core/global_settings.gd:105-107`).
   - `GraphicsManager` (`core/graphics_manager.gd:73, 121, 150, 170, 185-224, 245, 287, 291, 377, 406, 424, 431, 438-439`) calls `VideoApplier` (including private methods `_get_int`, `_get_float`, `_get_str`, `_apply_gameplay_clouds`), while `ui/video_applier.gd:303` looks up `tree.root.get_node_or_null("GraphicsManager")`.
   - `ui/main_menu.gd:85, 217, 246, 270, 322` calls `GraphicsManager.set_diorama_mode`, while `core/graphics_manager.gd:456` queries `tree.root.find_children("*", "MainMenu", true, false)`.
3. **`Events` (`project.godot:29`) <-> `GlobalSettings` (`project.godot:34`) Cycle**:
   - `Events.apply_dyslexic_font_to_node()` (`core/events.gd:744-759`) queries `/root/GlobalSettings`, while `GlobalSettings` (`core/global_settings.gd:349-383`) calls `Events`.
4. **`SonarManager` (`project.godot:38`) -> `AudioPool` (`project.godot:47`) Boot Order Inversion**:
   - `SonarManager._ready()` (`core/audio/sonar_manager.gd:57, 223`) calls `AudioPool.get_pooled_player_2d()` 9 autoload slots before `AudioPool._ready()` runs (`core/audio_pool.gd:20` works around this via lazy `_ensure_pools_allocated()` at `L114`).
5. **Gameplay & Environment Direct 2-Cycles**:
   - `player/player.gd:90` (`PlayerStatsComponent`) <-> `player/stats_component.gd:12` (`Player`).
   - `player/player.gd:145` (`FactionComponent`) <-> `core/components/faction_component.gd:12` (`Player`).
   - `player/player_interaction_component.gd:47` (`InteractionScanner`) <-> `player/player_interaction_scanner.gd:86` (`PlayerInteractionComponent`).
   - `player/environment_component.gd:176` (`StateLadder`) <-> `player/state_ladders.gd:75` (`PlayerEnvironmentComponent`).
   - `player/state_wolf_wall_run.gd:39, 69` (`WolfClimbSurface`) <-> `environment/wolf_climb_surface.gd:334-336` (`sm.has_node("StateWolfWallRun")`).
   - `player/weapon_inventory_component.gd:254` (`ThrowableWeapon`) <-> `weapons/throwable_weapon.gd:165` (`WeaponInventoryComponent`).
   - `enemies/drone_swarm_controller.gd:87` (`ElfDrone`) <-> `enemies/elf_drone.gd:40` (`DroneSwarmController`).
   - `enemies/guardian_pillar.gd:185` (`EnergyBlast`) <-> `enemies/guardian_projectile.gd:64` (`GuardianPillar`).
   - `environment/DynamicFog/smoke_manager.gd:19, 58, 68` (`SmokeGrenadeCloud`) <-> `weapons/smoke_grenade/smoke_grenade_cloud.gd:144, 160` (`get_node_or_null("/root/SmokeManager")`).
   - *(Note: `environment/DynamicFog/smoke_manager.gd:40` and `:76, 83` only mention `DynamicFogZone` and `HitscanWeapon` in docstrings/comments; `environment/water_body.gd:21` and `player/state_swim.gd:166` only mention each other in docstrings; `player/player.gd:770, 776, 779` -> `DeathScreen.DeathState` is one-way static since `ui/death_screen.gd:305` uses `get_first_node_in_group("player")`.)*
6. **Multi-Hop Cycles & 17-File Player/UI/Console SCC**:
   - `player/player.gd:101` -> `player/system_menu_controller.gd:18` (preloads `res://ui/main_menu.tscn`) -> `ui/main_menu.gd:12` (preloads `res://ui/loading_screen_anim.tscn`) -> `ui/loading_screen_anim.gd:512, 522` (`Player`, `PlayerLocomotionComponent`) -> `player/locomotion_component.gd:91` (`PlayerStatsComponent`) -> `player/stats_component.gd:12` (`Player`).
   - `interactables/glider_item.gd:358` (`Player`) -> `player/player.gd:84` (`PlayerInteractionComponent`) -> `player/player_interaction_component.gd:159` (`GliderItem`).
   - `player/camera_controller.gd:301` (`Types`) -> `core/types.gd:103` (`Player`) -> `player/player.gd:98` (`CameraController`).
   - `player/environment_component.gd:24` (`Zipline`) -> `player/zipline.gd:189` (`Player`) -> `player/player.gd:87` (`PlayerEnvironmentComponent`).
   - `player/player.gd:104` (`UIController`) -> `ui/ui.gd:54` (`RenderDiagnosticsPanel`) -> `ui/diagnostics_panel.gd:1492` (`Player`).
7. **Upward Domain Coupling (`core/` -> Gameplay/UI/Triggers)**:
   - `core/audio/sonar_manager.gd:251` & `core/audio/spatial_describer.gd:241, 396` -> `PickableObject` (`interactables/pickable_object.gd`).
   - `core/components/health_modifier.gd:15, 126, 136, 149, 164-171` -> `EditorTriggerVisualizer` (`triggers/editor_trigger_visualizer.gd`).
   - `core/console/console_cheat_commands.gd:654, 688, 779, 803, 851, 858, 998` -> `EditorTriggerVisualizer`, `WeaponInventoryComponent`, `HitscanWeapon`, `ThrowableWeapon`, `ScreenEffectsManager`.
   - `core/console/console_settings_commands.gd:731, 736, 742-757, 1250` -> `DeathScreen`, `VideoApplier`.

### 4.3 Dead Code Inventory (Orphan Scripts/Shaders, Unused Signals & Functions)

#### A. Orphan & Test-Only Runtime Files (30 Completely Unreferenced + 1 Broken-Scene-Path + 6 Test-Only)
- **30 Completely Unreferenced Runtime Files (0 references in `.tscn`, `.tres`, `project.godot`, runtime `.gd`, or `test/`)**:
  1. `core/shader_cache_builder.gd:1-92` (`class_name ShaderCacheBuilder`)
  2. `dynamic_ocean/shaders/oceanwave.gdshader:1-91`
  3. `environment/box_clouds.gd:1-66` (`class_name LowAltitudeWeather`)
  4. `environment/cloth.gd:1-68` (`class_name ClothBaker`)
  5. `environment/deprecated_camera_water_overlay.gdshader:1-43`
  6. `environment/lex_partizan_rain/anti_tile.gdshader:1-37`
  7. `environment/lex_partizan_rain/depth_buffer.gdshader:1-16`
  8. `environment/lex_partizan_rain/screen_space_snow.gdshader:1-81`
  9. `environment/rainy_window_normal.gdshader:1-58`
  10. `environment/water_wipe_overlay.gd:1-43` (`class_name WaterOverlayController`, superseded by `ui/water_wipe_controller.gd:1-214`)
  11. `environment/world_environment.gd:1-51` (`class_name GameWorldEnvironment`)
  12. `interactables/cable_builder.gd:1-74` (`class_name CableBuilderComponent` — referenced only in unit tests, 0 runtime refs)
  13. `interactables/combustible_object.gd:1-183` (`class_name CombustibleObject` — referenced only in unit tests, 0 runtime refs)
  14. `interactables/energy_cell_fill.gdshader:1-24`
  15. `player/procedural_revolver.gd:1-388` (`# class_name ProceduralRevolverRig` — referenced only in unit tests, 0 runtime refs)
  16. `player/screen_vfx_manager.gd:1-260` (`class_name ScreenVFXManager` — referenced only in unit tests, 0 runtime refs)
  17. `ui/fullscreen_control.gd:1-26`
  18. `ui/gel_stream_3d.gd:1-99` (`class_name GelStream3D`)
  19. `ui/juicy_button.gd:1-94` (`class_name JuicyButton`)
  20. `vfx/3DShockwaveTester.gd:1-34` (`class_name ShockwaveTester`)
  21. `vfx/TinnitusEffect.gd:1-49` (`class_name TinnitusEffect`)
  22. `vfx/blood_decal.gd:1-44` (`class_name BloodDecal`)
  23. `vfx/blood_splatter.gd:1-44` (`class_name BloodSplatterVFX`)
  24. `vfx/chapter_text_glow.gdshader:1-49`
  25. `vfx/glass_block.gdshader:1-36`
  26. `vfx/motion_blur.gdshader:1-28`
  27. `vfx/outline_shader.gdshader:1-30`
  28. `vfx/reaction_diffusion.gdshader:1-64`
  29. `vfx/smart_outline_material.gdshader:1-72`
  30. `vfx/turing.gdshader:1-29`
  31. `vfx/waterfall_controller.gd:1-31` (`class_name WaterfallController`)
  *(Note: `props/gothic_arch/gothic_arch_prop.gd:1-59` is NOT an orphan; it is bound by `props/gothic_arch/gothic_arch_post_import.gd:12` and instantiated in `levels/chunks/testbed/chunk_0_-2.scn`. `core/scene_transition.gd:1-142` is NOT an orphan; it is invoked dynamically at `core/console/console_system_commands.gd:229-234`.)*
- **1 Broken-Scene-Path Orphan Script**:
  - `environment/interactive_lightning.gd:1-153` (unreferenced only because `environment/lightning_scene.tscn:3` has broken path `res://interactive_lightning.gd` instead of `res://environment/interactive_lightning.gd`).
- **6 Additional Runtime Files Referenced ONLY in `test/`**:
  1. `core/camera_shake_manager.gd:1-184` (`test/unit/test_camera_shake_manager.gd`)
  2. `core/interaction_manager.gd:1-156` (`test/unit/test_interaction_manager.gd`)
  3. `core/vfx/screen_effects_core.gd:1-434` (`test/unit/test_screen_effects_core.gd`)
  4. `enemies/wave_spawner.gd:1-174` (`test/unit/test_bella_architecture.gd`)
  5. `shaders/fluted_glass.gdshader:1-46` (`test/test_fluted_glass.tscn`)
  6. `world/test_player.gd:1-132` (`test/unit/test_dumpster.gd`, `test/unit/test_sewer_grate.gd`, `test/test_world.tscn`)
  *(Plus `ui/chunk_debug_hud.gd:1-228`, instantiated only in `test/test_world.tscn`.)*

#### B. Unused & Half-Wired Signals
- **Completely Unused Signals in `core/events.gd` (6 signals)**:
  - `core/events.gd:20` (`game_started`), `core/events.gd:24` (`game_pause_toggled`), `core/events.gd:28` (`game_over_triggered`), `core/events.gd:32` (`level_loaded`), `core/events.gd:238` (`dyslexic_font_toggled`), `core/events.gd:596` (`weather_changed`).
- **Half-Wired Signals in `core/events.gd` — Connected but Never Emitted (4 signals)**:
  - `core/events.gd:9` (`sfx_2d_requested` — connected at `core/audio_pool.gd:41`, never emitted).
  - `core/events.gd:207` (`debug_menu_toggled` — connected at `player/system_menu_controller.gd:105` & `ui/debug_overlay.gd:136`, never emitted).
  - `core/events.gd:516` (`smoke_exposure_changed` — connected at `ui/player_status_hud.gd:165` & `ui/screen_effects_manager.gd:147`, never emitted).
  - `core/events.gd:580` (`transition_requested` — shadowed by local `State.transition_requested` at `core/state.gd:7`; never emitted/connected on `Events`).
- **Half-Wired Signals in `core/events.gd` — Emitted but Never Connected on `Events` (12 signals)**:
  - `core/events.gd:79` (`inventory_item_given` — emitted at `core/console/console_cheat_commands.gd:755`).
  - `core/events.gd:87` (`gravity_override_requested` — emitted at `core/console/console_cheat_commands.gd:972`).
  - `core/events.gd:203` (`wireframe_overlay_toggled` — emitted at `core/console/console_settings_commands.gd:678` and `ui/debug_overlay.gd:192`).
  - `core/events.gd:258` (`tts_state_changed` — emitted at `core/console/console_settings_commands.gd:1267` and `ui/subs_audio_section.gd:513`).
  - `core/events.gd:318` (`keycard_collected` — emitted at `core/console/console_cheat_commands.gd:716` and `interactables/keycard_pickup.gd:40`).
  - `core/events.gd:346` (`object_focused` — emitted at `core/tts_interact_component.gd:53`, `interactables/pickable_object.gd:682`, `interactables/puzzle_socket.gd:420`, `interactables/valve_base.gd:675`, and `player/player_interaction_scanner.gd:167`).
  - `core/events.gd:488` (`ammo_collected` — emitted at `core/console/console_cheat_commands.gd:787` and `player/weapon_inventory_component.gd:220`).
  - `core/events.gd:504` (`godmode_toggled` — emitted at `core/console/console_cheat_commands.gd:502`; `ui/gameplay_panel.gd:107` only connects a local button's `.toggled`).
  - `core/events.gd:568, 572, 576` (`interaction_focused`, `interaction_unfocused`, `interacted` — emitted on `Events` at `core/interaction_manager.gd:142, 131, 111`, never connected on `Events`).
  - `core/events.gd:614` (`player_notarget_toggled` — emitted at `core/console/console_cheat_commands.gd:1495`).
- **Dead Domain Signals (Never Emitted or Connected Anywhere)**:
  - `enemies/elf_drone.gd:8`: `signal healing_pulsed(target: Node3D, amount: int)` (with `@warning_ignore("unused_signal")` at `L7`).
  - `interactables/gas_stove.gd:9`: `signal stove_impacted(impulse_sq: float)` (with `@warning_ignore("unused_signal")` at `L8`).
  - `ui/diagnostics_panel.gd:7`: `signal metrics_updated(data: Dictionary)` (with `@warning_ignore("unused_signal")` at `L5`).
- **Unused Public Functions in `core/` (Zero Runtime or Test Callers)**:
  - `core/global_settings.gd:199` (`get_font_index`), `core/graphics_manager.gd:339` (`apply_vrs_state`), `core/node_query.gd:34` (`find_ancestor_with_method`), `core/node_query.gd:68` (`find_children_of_type`), `core/render_context.gd:125` (`create_uniform_buffer`), `core/save_manager.gd:304` (`update_save_meta`), `core/spike_forensics.gd:151` (`get_recent_spikes`), `core/spike_forensics.gd:156` (`get_log_path`), `core/utilities.gd:28` (`clear_children_in_group`).

---

## 5. Consolidated Domain Audit Findings

### 5.1 Deprecated APIs, String-Based Signal Wiring & `@warning_ignore` Violations
- **Zero Godot 3 Legacy APIs**: No `yield`, `Spatial`, `KinematicBody`, `File`, or `funcref` exist in any domain.
- **String-Based `.connect("...", ...)` / `.emit_signal("...", ...)` / `call_deferred("...")` (20+ occurrences)**:
  - **Functional Bug (`ui/HighContrastManager.gd:39`)**: Calls `root_events.connect("high_contrast_changed", _on_high_contrast_toggled)`, whereas `Events` (`core/events.gd:268`) defines `signal high_contrast_toggled(enabled: bool)` — `HighContrastManager` never receives the signal!
  - Other untyped string signal calls: `enemies/tripmine.gd:402, 404`, `enemies/drone_swarm_controller.gd:146`, `interactables/dev_comment/developer_commentary.gd:195, 226`, `interactables/meat_cube.gd:35`, `interactables/valve_base.gd:170, 675`, `player/camera_3d.gd:87`, `triggers/trigger_hint.gd:51`, `ui/VisionAssistManager.gd:100, 102, 104`, `ui/diorama_post_process.gd:23, 25`, `ui/gameplay_panel.gd:160, 181`, `vfx/Post_Process_Layer.gd:65, 67, 69, 71`, `environment/argon_water_body/argon_water_body.gd:745`, `environment/hydrogen_water_body/hydrogen_water_body.gd:1165`.
- **`@warning_ignore` Outside `core/events.gd` (44 occurrences violating Zero-`@warning_ignore` rule)**:
  - Gameplay (29): `enemies/elf_drone.gd:7`, `enemies/wave_spawner.gd:6`, `interactables/breakable_crate.gd:9`, `interactables/door_keypad.gd:9`, `interactables/dumpster/dumpster.gd:7, 11, 15`, `interactables/gas_stove.gd:8`, `interactables/scissor_gate/scissor_gate.gd:7, 11, 15`, `interactables/sewer_grate/sewer_grate.gd:8, 12, 16, 20`, `interactables/ui_circle_keypad.gd:6, 10, 14, 18`, `interactables/ui_keypad.gd:7, 12, 16`, `player/drunk_effect.gd:7`, `player/player.gd:6`, `player/procedural_revolver.gd:7, 10`, `player/weapon_procedural_animator.gd:6, 10`, `props/breakable_shelf/breakable_shelf.gd:10`.
  - Env/UI/VFX (15): `environment/wolf_climb_surface.gd:7`, `ui/diagnostics_panel.gd:5`, `ui/display_section.gd:6`, `ui/effects_section.gd:6`, `ui/fullscreen_control.gd:19, 25` (`integer_division`), `ui/hardware_section.gd:6`, `ui/options_router.gd:6`, `ui/quality_section.gd:6, 10`, `ui/universal_setting_highlighter.gd:6, 10`, `vfx/smoke_explosion.gd:10, 14`, `vfx/wind_wall.gd:8`.
- **Detached Signal Docstrings in `core/events.gd:8-709`**: Places `@warning_ignore("unused_signal")` between the `##` docstring and `signal` declaration on all 154 signals.

### 5.2 Missing Static Types, Untyped Collections & Unsafe `Variant` Access
- **Direct `Variant` -> Typed Assignments & Un-narrowed `dict.get()` / `call()`**:
  - `core/`: `core/audio/sonar_manager.gd:173-174, 177-178, 187-188, 194-197`, `core/audio/spatial_describer.gd:120, 188-191, 289-290`, `core/gesture_input_manager.gd:64`, `core/global_settings.gd:229, 351, 357, 361, 368`, `core/interaction_manager.gd:89`, `core/save_manager.gd:292-293`, `core/console/console_cheat_commands.gd:961`, `core/console/console_settings_commands.gd:784`, `core/console_command_registry.gd:30`.
  - `enemies/`: `enemies/spook_encounter.gd:518` (`wall_hit.get(&"position", desired_rear)`), `enemies/turret.gd:373` (`result.get("collider")`).
  - `dynamic_ocean/`, `environment/`, `ui/`: `dynamic_ocean/waveheight_script.gd:51-55` (`float(water.call(&"get_height", ...))`), `environment/hydrogen_water_body/hydrogen_fog_volume.gd:88`, `ui/diagnostics_panel.gd:879, 880, 1365, 1371, 1375, 1386, 1392, 1396, 1407, 1413, 1415`, `ui/audio_panel.gd:283, 298`, `ui/controls_panel.gd:402, 417`, `ui/controls_section.gd:340`, `ui/display_ui_section.gd:198`, `ui/effects_section.gd:427, 481, 499`, `ui/quality_section.gd:422, 443`, `ui/subs_audio_section.gd:298`, `ui/visuals_section.gd:606`.
- **Duplicate Function Calls Inside Ternary Type Checks (`fn() if fn() is Type else null`)**:
  - `core/state_machine.gd:41, 87`, `core/components/health_modifier.gd:238`, `core/singletons/system_locator.gd:45, 102`, `core/save_manager.gd:248-250`.
- **Untyped `Array` / `Dictionary` Declarations (280+ occurrences)**:
  - `core/` & `world/`: `core/events.gd:580, 751, 756`, `core/math_utils.gd:9, 27`, `core/node_query.gd:120`, `core/utilities.gd:101`, `core/object_pool.gd:36`, `core/state.gd:7, 14`, `core/state_machine.gd:80, 109, 114`, `core/save_manager.gd:93, 156, 174, 180, 187, 192, 241, 262, 280, 291, 317, 349`, `core/save_slot.gd:57`, `core/global_settings.gd:12, 37, 82, 146, 400, 451`, `core/graphics_manager.gd:6, 16, 53, 136, 139, 160`, `core/scene_transition.gd:27`, `core/spike_forensics.gd:6, 63, 151, 161, 176, 180`, `core/interaction_manager.gd:84`, `core/gesture_input_manager.gd:23, 26, 29, 32, 35, 46, 63, 101, 110, 134, 139, 141, 167, 191, 210, 220, 271, 303, 368, 382, 395-396, 405`, `core/audio/sonar_manager.gd:156, 172, 186, 281`, `core/audio/spatial_describer.gd:86, 131, 152, 182, 186, 280, 288, 324, 499`, `core/components/health_modifier.gd:89`, `core/singletons/system_locator.gd:15`, `core/console_command_registry.gd:6`, `core/console/console_context.gd:9, 13`, `core/console/console_system_commands.gd:143, 274, 389, 441`, `core/render_context.gd:50, 228`, `world/chunk_manager.gd:88, 100, 164, 168, 229, 233, 303, 405-406, 411, 423, 430, 497`, `world/chunk_root.gd:37`.
  - Gameplay (79 occurrences across 38 files) and Env/UI/VFX (131 occurrences across 34 files).

### 5.3 Duplicated Logic & Redundant Subsystems
1. **Double Camera Trauma Bug (`core/camera_shake_manager.gd:55` + `core/vfx/screen_effects_core.gd:103`)**:
   - `CameraShakeManager._ready()` (`core/camera_shake_manager.gd:55, 168-179`) connects directly to `Events.screenshake_requested`, AND `ScreenEffectsCore._connect_event_bus()` (`core/vfx/screen_effects_core.gd:100-112, 139-144`) ALSO connects to `Events.screenshake_requested` and calls `_camera_shake_manager.add_trauma(intensity)`.
2. **Triplicate Water Body & Underwater Fog Subsystems (`3,455` lines of `.gd` + `1,361` lines of `.gdshader`)**:
   - `environment/water_body.gd:1-1538`, `environment/hydrogen_water_body/hydrogen_water_body.gd:1-1165`, and `environment/argon_water_body/argon_water_body.gd:1-752` duplicate 24 methods (`get_wave_height_at_pos`, `get_water_surface_normal`, `spawn_ripple`, `_cache_material_rid`, `change_water_level`, etc.).
   - `environment/UnderwaterFogVolume.gd:1-143`, `environment/argon_water_body/argon_underwater_fog_volume.gd:1-133`, and `environment/hydrogen_water_body/hydrogen_fog_volume.gd:1-108` duplicate the flashlight-aware fog fade plane.
3. **Raycast, `HealthComponent`, & Settings Boilerplate Duplication**:
   - Raycast wrappers duplicated across `NodeQuery.cast_ray()` (`core/node_query.gd:113-129`), `Utilities.raycast_3d()` (`core/utilities.gd:94-112`), `InteractionManager._get_Look_at_target()` (`core/interaction_manager.gd:74-84`), and 11 direct `space_state.intersect_ray(query)` calls in gameplay (`enemies/guardian_pillar.gd:125`, `enemies/spook_encounter.gd:482, 516, 634`, `enemies/tripmine.gd:361`, `interactables/glider_item.gd:308`, `interactables/heavy_pickable_box.gd:214`, `player/state_air.gd:366`, `player/state_wolf_climb.gd:142`, `player/state_wolf_wall_run.gd:172`, `triggers/wake_up_trigger.gd:139`).
   - 16 ad-hoc `HealthComponent` lookups in gameplay bypass `NodeQuery.find_health_component()` (e.g., `enemies/drone_swarm_controller.gd:312-315`, `enemies/evil_goon.gd:58`, `enemies/fire.gd:180`, `enemies/squid/enemy_squid.gd:913`, `enemies/turret.gd:290`, `interactables/explosive_barrel.gd:239-240`).
   - `ui/effects_section.gd:167-514` and `ui/quality_section.gd:140-457` duplicate 12 UI binding methods verbatim; `ui/InputHelper.gd:6-118` and `ui/controls_panel.gd:46-103, 980-1034` duplicate the Kenney icon cache.

### 5.4 Undocumented Side Effects, 60 FPS Violations & Resource Safety Defects
1. **Unconditional `print()` Spam Inside Per-Frame Process Loops (18 occurrences)**:
   - 12 `PlayerState` scripts print 60 times/sec: `player/state_fast_rope.gd:53`, `player/state_glide.gd:85`, `player/state_monkey_bars.gd:74`, `player/state_path_slide.gd:49`, `player/state_slide.gd:48`, `player/state_terminal.gd:43`, `player/state_tube.gd:74, 79`, `player/state_vault.gd:42`, `player/state_wolf_climb.gd:62`, `player/state_wolf_wall_run.gd:92`, `player/state_zipline.gd:103`.
   - 5 Env/UI scripts print inside `_process`/`_physics_process`: `environment/highlight_component.gd:146`, `environment/wolf_climb_surface.gd:189, 197`, `ui/loading_screen_anim.gd:205, 228`.
   - Plus `core/gesture_input_manager.gd:335` (`is_action_just_released` polling print) and `core/components/health_modifier.gd:223` (autostart timer tick print).
2. **Per-Frame Object/Array/Dictionary Allocations**:
   - `core/gesture_input_manager.gd:46, 101, 110` allocates 3 `Array`s and 4 `.keys()` arrays every frame; `core/frame_graph.gd:35` calls `history.pop_front()` every frame; `core/math_utils.gd:16, 34` allocates `{&"position": new_position, &"velocity": new_velocity}` on every spring step.
   - `enemies/guardian_pillar.gd:81, 84, 120`, `enemies/spook_encounter.gd:631`, `player/state_air.gd:364`, `player/state_wolf_climb.gd:140`, `player/state_wolf_wall_run.gd:170` allocate `SphereShape3D.new()`, `PhysicsShapeQueryParameters3D.new()`, or `PhysicsRayQueryParameters3D.create()` every frame.
3. **Synchronous Physics/Scene Mutations Inside Physics Callbacks Without `set_deferred()` / `call_deferred()`**:
   - `core/object_pool.gd:143-150, 188-195`, `triggers/crab_shell_trigger.gd:33`, `enemies/flying_tile.gd:139`, `enemies/spook_encounter.gd:606`, `enemies/tentacle_enemy.gd:338`, `interactables/burnable_obstacle.gd:131`, `interactables/cell_recharger.gd:174`, `interactables/lever_stick_item.gd:144`, `interactables/pneumatic_tube.gd:201`, `interactables/puzzle_socket.gd:359`, `interactables/wall_generator.gd:185`.
4. **All 17 Runtime Synchronous `load()` / `ResourceLoader.load()` Occurrences**:
   - `core/events.gd:764`, `core/global_settings.gd:258`, `core/render_context.gd:102`, `core/console/console_cheat_commands.gd:735, 828, 908`, `world/chunk_manager.gd:298`, `interactables/meat_cube.gd:32, 96`, `interactables/ui_circle_keypad.gd:187`, `weapons/signal_rocket/signal_rocket_weapon.gd:69`, `environment/gothic_energy_gate.gd:530`, `environment/supply_shell.gd:238`, `levels/testbed_loader.gd:53`, `ui/InputHelper.gd:103`, `ui/controls_panel.gd:1028`, `vfx/Post_Process_Layer.gd:114`.
5. **Broken/No-Op Console Commands**:
   - `core/console/console_system_commands.gd:184-191` (`_cmd_uiscale` prints without changing scale), `core/console/console_settings_commands.gd:457-466` (`_cmd_mono_audio` prints without changing audio), `core/console/console_settings_commands.gd:849-850` (`_cmd_perf_uncap` reads section `"Video"` instead of `"Settings"`).
