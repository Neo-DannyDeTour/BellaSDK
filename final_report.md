# Architecture and Codebase Standardization Report

Based on an exhaustive analysis of the BellaSDK repository (excluding `addons/`, `Player_OLD.gd`, and `playerENUM_TEST.gd`), here is the strategic breakdown of inconsistencies and areas requiring standardization.

## 1. Strict Static Typing
*Godot 4 introduces strict typing which improves performance and readability. The following files are missing type definitions for variables or return types for functions:*

- **./environment/wave_generator.gd**: Missing return type for functions (`->`).
- **./interactables/destructible_glass/destructible_glass.gd**: Missing return type for functions (`->`).
- **./player/camera_controller.gd**: Missing return type for functions (`->`).
- **./player/footstep_manager.gd**: Missing return type for functions (`->`).
- **./player/physics_pusher.gd**: Missing return type for functions (`->`).
- **./player/state_rope.gd**: Missing return type for functions (`->`).
- **./player/vault_controller.gd**: Missing return type for functions (`->`).
- **./shared/render_context.gd**: Missing return type for functions (`->`).
- **./shared/soundscape_zone.gd**: Missing return type for functions (`->`).
- **./ui/chapter_title_container.gd**: Missing return type for functions (`->`).
- **./ui/main_menu.gd**: Missing return type for functions (`->`).
- **./vfx/particle.gd**: Missing return type for functions (`->`).
- **./vfx/smoke_manager.gd**: Missing return type for functions (`->`).
- **./environment/highlight_component.gd**: Missing static typing for `var` declarations.
- **./player/physics_pusher.gd**: Missing static typing for `var` declarations.
- **./player/state_rope.gd**: Missing static typing for `var` declarations.
- **./shared/cloth.gd**: Missing static typing for `var` declarations.
- **./shared/fade_trigger.gd**: Missing static typing for `var` declarations.
- **./shared/trigger_look.gd**: Missing static typing for `var` declarations.
- **./shared/updraft_volume.gd**: Missing static typing for `var` declarations.
- **./interactables/push_wheel.gd**: Missing static typing for `var` declarations.

**Recommendation:** Enforce `: Type` for all variables and `-> Type` (or `-> void`) for all function definitions.

## 2. GDLint Compliance
*Formatting inconsistencies, line length violations, and naming convention mismatches.*

- **./core/dev_metrics.gd**: Linting errors - Formatting inconsistencies.
- **./core/fuzzer.gd**: Linting errors - Formatting inconsistencies.
- **./core/save_slot.gd**: Linting errors - Formatting inconsistencies.
- **./environment/ocean.gd**: Linting errors - Formatting inconsistencies.
- **./environment/rain_particles.gd**: Linting errors - Formatting inconsistencies.
- **./environment/water_maker3_d.gd**: Linting errors - Formatting inconsistencies.
- **./environment/wave_cascade_parameters.gd**: Linting errors - Formatting inconsistencies.
- **./environment/wave_generator.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/cable_builder.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/cable_point_3d.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/checkpoint.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/combination_lock.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/destructible_glass/destructible_glass.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/dev_comment/auto_scroll_container.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/dev_comment/developer_commentary.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/door_interact.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/door_keypad.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/glider_item.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/interact_component.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/physics_cable3_d.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/pickable_object.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/player_drone.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/spike_trap.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/static_cable.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/universal_cable_3d.gd**: Linting errors - Formatting inconsistencies.
- **./interactables/valve.gd**: Linting errors - Formatting inconsistencies.
- **./player/camera_controller.gd**: Linting errors - Formatting inconsistencies.
- **./player/fast_rope.gd**: Linting errors - Formatting inconsistencies.
- **./player/footstep_manager.gd**: Linting errors - Formatting inconsistencies.
- **./player/locomotion_component.gd**: Linting errors - Formatting inconsistencies.
- **./player/player.gd**: Linting errors - Formatting inconsistencies.
- **./player/procedural_spiral_stairs_csg.gd**: Linting errors - Formatting inconsistencies.
- **./player/procedural_stairs_csg.gd**: Linting errors - Formatting inconsistencies.
- **./player/stair_controller.gd**: Linting errors - Formatting inconsistencies.
- **./player/state_ground.gd**: Linting errors - Formatting inconsistencies.
- **./player/state_zipline.gd**: Linting errors - Formatting inconsistencies.
- **./player/system_menu_controller.gd**: Linting errors - Formatting inconsistencies.
- **./player/vault_controller.gd**: Linting errors - Formatting inconsistencies.
- **./player/zipline.gd**: Linting errors - Formatting inconsistencies.
- **./shared/UIkeypad.gd**: Linting errors - Formatting inconsistencies.
- **./shared/box_clouds.gd**: Linting errors - Formatting inconsistencies.
- **./shared/editor_trigger_visualizer.gd**: Linting errors - Formatting inconsistencies.
- **./shared/events.gd**: Linting errors - Formatting inconsistencies.
- **./shared/ground_button.gd**: Linting errors - Formatting inconsistencies.
- **./shared/procedural_fence_csg.gd**: Linting errors - Formatting inconsistencies.
- **./shared/procedural_monkey_bars.gd**: Linting errors - Formatting inconsistencies.
- **./shared/pulley_controller.gd**: Linting errors - Formatting inconsistencies.
- **./shared/render_context.gd**: Linting errors - Formatting inconsistencies.
- **./shared/soundscape_zone.gd**: Linting errors - Formatting inconsistencies.
- **./texture_baker.gd**: Linting errors - Formatting inconsistencies.
- **./ui/CCTV.gd**: Linting errors - Formatting inconsistencies.
- **./ui/chapter_title_container.gd**: Linting errors - Formatting inconsistencies.
- **./ui/danny_cast_screen.gd**: Linting errors - Formatting inconsistencies.
- **./ui/in_game_console.gd**: Linting errors - Formatting inconsistencies.
- **./ui/machine_lock_ui.gd**: Linting errors - Formatting inconsistencies.
- **./ui/main_menu.gd**: Linting errors - Formatting inconsistencies.
- **./ui/menu_chapter_screen.gd**: Linting errors - Formatting inconsistencies.
- **./ui/ui.gd**: Linting errors - Formatting inconsistencies.
- **./vfx/phys_explosion_3d.gd**: Linting errors - Formatting inconsistencies.
- **./vfx/smoke_manager.gd**: Linting errors - Formatting inconsistencies.
- **./vfx_volume.gd**: Linting errors - Formatting inconsistencies.

**Recommendation:** Run `gdformat` across the entire codebase to unify indentation, spacing, and line lengths. Address manually any structural constraints identified by `gdlint` (like exceeding maximum function returns or lines).

## 3. Execution Traceability
*Major logic or player-called functions missing print() statements. The target is that every active player function should have a print log of its execution.*

- **./interactables/player_drone.gd**: Missing `print()` statement in player/action function.
- **./player/StateMachineLock.gd**: Missing `print()` statement in player/action function.
- **./player/camera_3d.gd**: Missing `print()` statement in player/action function.
- **./player/camera_controller.gd**: Missing `print()` statement in player/action function.
- **./player/climable_rope.gd**: Missing `print()` statement in player/action function.
- **./player/environment_component.gd**: Missing `print()` statement in player/action function.
- **./player/fast_rope.gd**: Missing `print()` statement in player/action function.
- **./player/flashlight_controller.gd**: Missing `print()` statement in player/action function.
- **./player/footstep_manager.gd**: Missing `print()` statement in player/action function.
- **./player/locomotion_component.gd**: Missing `print()` statement in player/action function.
- **./player/physics_pusher.gd**: Missing `print()` statement in player/action function.
- **./player/player.gd**: Missing `print()` statement in player/action function.
- **./player/player_interaction_component.gd**: Missing `print()` statement in player/action function.
- **./player/player_interaction_scanner.gd**: Missing `print()` statement in player/action function.
- **./player/player_state.gd**: Missing `print()` statement in player/action function.
- **./player/player_state_machine.gd**: Missing `print()` statement in player/action function.
- **./player/procedural_spiral_stairs_csg.gd**: Missing `print()` statement in player/action function.
- **./player/procedural_stairs_csg.gd**: Missing `print()` statement in player/action function.
- **./player/push_wheel.gd**: Missing `print()` statement in player/action function.
- **./player/screen_vfx_manager.gd**: Missing `print()` statement in player/action function.
- **./player/stair_controller.gd**: Missing `print()` statement in player/action function.
- **./player/state_air.gd**: Missing `print()` statement in player/action function.
- **./player/state_fast_rope.gd**: Missing `print()` statement in player/action function.
- **./player/state_glide.gd**: Missing `print()` statement in player/action function.
- **./player/state_ground.gd**: Missing `print()` statement in player/action function.
- **./player/state_ladders.gd**: Missing `print()` statement in player/action function.
- **./player/state_monkey_bars.gd**: Missing `print()` statement in player/action function.
- **./player/state_path_slide.gd**: Missing `print()` statement in player/action function.
- **./player/state_rope.gd**: Missing `print()` statement in player/action function.
- **./player/state_slide.gd**: Missing `print()` statement in player/action function.
- **./player/state_swim.gd**: Missing `print()` statement in player/action function.
- **./player/state_vault.gd**: Missing `print()` statement in player/action function.
- **./player/state_zipline.gd**: Missing `print()` statement in player/action function.
- **./player/system_menu_controller.gd**: Missing `print()` statement in player/action function.
- **./player/vault_controller.gd**: Missing `print()` statement in player/action function.
- **./player/zipline.gd**: Missing `print()` statement in player/action function.

**Recommendation:** Traverse through all action-oriented classes within the `player` directories and ensure `print("Action: <Action Name> Executed")` or similar debug logs are injected at the start of these functions to trace game states precisely.

## 4. Performance Bottlenecks
*Inefficient loops, heavy _process logic, or suboptimal node lookups jeopardizing the 60 FPS target.*

- **./core/graphics_manager.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./environment/wave_generator.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./environment/waveheight_script.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./interactables/interact_component.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./interactables/mirror.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./interactables/physics_cable3_d.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./interactables/pickable_object.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./interactables/valve.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./physics_magnet.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./player/climable_rope.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./shared/puzzle_socket.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./ui/horror_button.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./ui/in_game_console.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.
- **./vfx/smoke_manager.gd**: Contains loops in `_process`/`_physics_process` which could impact 60 FPS target.

**Recommendation:** Review these loops and refactor by either caching required values outside `_process`, using Timer nodes for logic that doesn't need to run every frame, or moving intensive calculations to C++ via GDExtension if necessary. Look out for `get_node()` inside `_process` and swap to cached `@onready` variables. Also, ensure any destructibles like glass pre-fracture on `_ready()` instead of real-time CSG processing.

## 5. Structural Consistency
*Differing architectural approaches across scenes (e.g., using signals vs direct node references).*

- The project currently exhibits a mixed approach to inter-node communication.
- **Example Files using Direct References (Tight Coupling):** `interactables/pickable_object.gd`, `interactables/keycard_pickup.gd`, `shared/button.gd`
- **Example Files using Event-Driven Signals (Loose Coupling):** `shared/events.gd`, `player/player.gd`

**Recommendation:** Unify the architecture by adopting an **Event Bus pattern**. Since `shared/events.gd` already appears to exist, standardizing its usage as a global Autoload/Singleton across all decoupled systems is recommended. This avoids cross-scene `.get_node()` dependencies which make refactoring fragile and leads to messy architecture.
