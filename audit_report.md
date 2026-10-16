# Godot 4 Engine & Performance Audit Report

## [./ui/chapter_title_container.gd : 182]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS`
- **Underlying Risk:** Running a SubViewport continuously consumes significant GPU and CPU resources, especially when the effect container it belongs to is off-screen, hidden, or docked in inactive UI tabs.
- **Recommended Remediation:** Change the update mode to UPDATE_ONCE or UPDATE_WHEN_VISIBLE, and only set it to UPDATE_ALWAYS when actively animating or visible.
## [./ui/chapter_title_container.gd : 234]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS`
- **Underlying Risk:** Running a SubViewport continuously consumes significant GPU and CPU resources, especially when the effect container it belongs to is off-screen, hidden, or docked in inactive UI tabs.
- **Recommended Remediation:** Change the update mode to UPDATE_ONCE or UPDATE_WHEN_VISIBLE, and only set it to UPDATE_ALWAYS when actively animating or visible.
## [./ui/loading_screen_anim.gd : 166]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `_warmup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS`
- **Underlying Risk:** A warmup viewport running continuously drains performance unnecessarily once the warmup phase is completed or while hidden.
- **Recommended Remediation:** Disable the update mode (UPDATE_DISABLED) after warmup is complete, or use UPDATE_ONCE.
## [./ui/diagnostics_panel.gd : 573]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `SubViewport.UPDATE_ALWAYS:`
- **Underlying Risk:** The diagnostics panel might be running a viewport continuously even when not actively viewing diagnostics.
- **Recommended Remediation:** Ensure the viewport update mode is only UPDATE_ALWAYS when the diagnostics panel is visible.
## [./environment/ribbon_wall.gd : 176]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS)`
- **Underlying Risk:** If the ribbon wall is not visible or far from the player, continuous updates waste rendering resources.
- **Recommended Remediation:** Use UPDATE_WHEN_VISIBLE or manage the update mode based on proximity to the camera.
## [./environment/water_body.gd : 119]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `@export var probe_update_mode: ReflectionProbe.UpdateMode = ReflectionProbe.UPDATE_ALWAYS:`
- **Underlying Risk:** Continuously updating a reflection probe is extremely expensive and kills frame rates on lower-end hardware.
- **Recommended Remediation:** Change the default export to ReflectionProbe.UPDATE_ONCE or tie updates to a specific lower-frequency timer/movement threshold.
## [./ui/chapter_title_container.gd : 226]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `_sub_viewport.size = Vector2i(screen_size)`
- **Underlying Risk:** Directly mutating `SubViewport.size` while its parent `SubViewportContainer.stretch` is true causes engine warnings and conflicting viewport size recalculations.
- **Recommended Remediation:** Remove direct size mutation on the SubViewport and let the parent SubViewportContainer manage the size through stretching.
## [./ui/loading_screen_anim.gd : 166]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `_warmup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS`
- **Underlying Risk:** Missing resource clamps (`positional_shadow_atlas_size`, `msaa_3d`, `scaling_3d_mode`) on secondary or preview viewports.
- **Recommended Remediation:** Add appropriate clamping variables onto the viewport to ensure memory optimization on target hardware.
## [./ui/ui.tscn : 946]
- **Category:** SubViewport & SubViewportContainer Misconfigurations (60 FPS Target)
- **Current State:** `size_2d_override_stretch = true`
- **Underlying Risk:** Missing `stretch_shrink` optimization on full-screen or preview SubViewportContainers.
- **Recommended Remediation:** Ensure `stretch_shrink` is properly set on full-screen or preview SubViewportContainers.
## [./ui/audio_panel.gd : 395]
- **Category:** Duplicate Signal Emissions & Redundant Events
- **Current State:** `slider_node.value = new_val`
- **Underlying Risk:** Setting the native `value` property on a slider automatically emits the `value_changed` signal. Calling `.emit()` right after (if done here) creates duplicate signal overhead.
- **Recommended Remediation:** Remove the redundant explicit `.value_changed.emit()` call following the assignment of slider_node.value.
## [./ui/controls_panel.gd : 715]
- **Category:** Duplicate Signal Emissions & Redundant Events
- **Current State:** `remapping_button.button_pressed = false`
- **Underlying Risk:** Setting the native `button_pressed` property on a button automatically emits the `toggled` signal. Calling `.emit()` right after (if done here) creates duplicate event propagation.
- **Recommended Remediation:** Remove the manual `.toggled.emit()` call immediately following the button state change.
## [./ui/effects_section.gd : 439]
- **Category:** Duplicate Signal Emissions & Redundant Events
- **Current State:** `_glow_btn_map[str(data["glow"])].button_pressed = true`
- **Underlying Risk:** Modifying native UI states like `button_pressed` triggers automated signals in Godot. Firing another `toggled` event wastes processing cycles.
- **Recommended Remediation:** Refactor code to either only assign `button_pressed` or suppress the native signal using `set_pressed_no_signal` if a custom event is needed.
## [./ui/save_load_panel.gd : 103]
- **Category:** Duplicate Signal Emissions & Redundant Events
- **Current State:** `load_btn.pressed.connect(_on_load_pressed.bind(file_name))`
- **Underlying Risk:** Connecting dynamic signals in UI generation (such as file lists) without disconnecting them on container clear or `tree_exited` causes memory leaks and duplicate execution.
- **Recommended Remediation:** Ensure connections are disconnected upon node removal, or attach a `tree_exited` signal clear logic when dealing with dynamic list elements.
## [./ui/save_load_panel.gd : 106]
- **Category:** Duplicate Signal Emissions & Redundant Events
- **Current State:** `del_btn.pressed.connect(_on_delete_pressed.bind(file_name))`
- **Underlying Risk:** Connecting dynamic signals in UI generation (such as file lists) without disconnecting them on container clear or `tree_exited` causes memory leaks and duplicate execution.
- **Recommended Remediation:** Ensure connections are disconnected upon node removal, or attach a `tree_exited` signal clear logic when dealing with dynamic list elements.
## [./test/unit/test_in_game_console.gd : 15]
- **Category:** Node Leaks & Unsafe Type Casts
- **Current State:** `_console = CONSOLE_SCENE.instantiate() as CanvasLayer`
- **Underlying Risk:** Instantiating a scene and casting it without a null check can result in a memory leak if the cast fails, as the unparented node is never queued for deletion.
- **Recommended Remediation:** Assign the instantiated node to a temporary variable, cast it, and if null, call `queue_free()` on the temporary node.
## [./ui/loading_screen_anim.gd : 298]
- **Category:** Node Leaks & Unsafe Type Casts
- **Current State:** `var loader_instance: LoadingScreen = target_scene.instantiate() as LoadingScreen`
- **Underlying Risk:** If the cast to `LoadingScreen` fails and returns null, the unparented node instantiated from `target_scene` is lost and leaks memory.
- **Recommended Remediation:** Hold the instantiated node in an untyped local variable first, check the cast, and `queue_free()` the raw node if the cast fails.
## [./tools/scene_organizer.gd : 233]
- **Category:** Node Leaks & Unsafe Type Casts
- **Current State:** `parent.add_child(container)`
- **Underlying Risk:** Dynamically adding children to a parent without cleaning up existing generated nodes first can cause duplicate hierarchies and massive node bloat over time.
- **Recommended Remediation:** Execute a node cleanup loop (e.g., `queue_free()` on existing generated children) before dynamically adding new container hierarchies.
## [./ui/settings_search.gd : 348]
- **Category:** Node Leaks & Unsafe Type Casts
- **Current State:** `search_results_list.add_child(row)`
- **Underlying Risk:** Generating search list results without clearing the old search container elements first leaks all previously instantiated rows.
- **Recommended Remediation:** Run a loop iterating over `search_results_list.get_children()` and call `queue_free()` on each before populating new rows.
## [./player/player.gd : 276]
- **Category:** Pause State & Process Mode Pitfalls
- **Current State:** `state_machine.process_mode = Node.PROCESS_MODE_INHERIT`
- **Underlying Risk:** If this state machine handles unpausing or critical global logic, setting it to INHERIT will cause it to freeze when the tree is paused, causing input deadlocks.
- **Recommended Remediation:** Set the process mode to PROCESS_MODE_ALWAYS for nodes that need to remain active during pauses.
## [./ui/options_router.gd : 303]
- **Category:** Pause State & Process Mode Pitfalls
- **Current State:** `diorama_viewport.process_mode = Node.PROCESS_MODE_INHERIT`
- **Underlying Risk:** If the options menu is used while the game is paused, inherited process modes will freeze the diorama preview.
- **Recommended Remediation:** Set the diorama viewport and its critical children to PROCESS_MODE_ALWAYS so they function during pause screens.
## [./interactables/heavy_pickable_box.gd : 298]
- **Category:** Pause State & Process Mode Pitfalls
- **Current State:** `interact_comp.process_mode = Node.PROCESS_MODE_INHERIT`
- **Underlying Risk:** Resetting an interaction component to INHERIT mode might break unpause or interaction polling while the tree is paused.
- **Recommended Remediation:** Set the interaction component to PROCESS_MODE_ALWAYS if it's responsible for logic when paused, or manage its state globally.
## [./vfx/ColorGradingVolume.gd : 463]
- **Category:** Destructive Overrides & Expensive Tree Traversal
- **Current State:** `if not is_instance_valid(target_environment) or target_environment.environment == null:`
- **Underlying Risk:** Overwriting camera or world environments directly without caching and restoring the previous state permanently destroys the original environment configuration.
- **Recommended Remediation:** Cache the initial environment resource in a variable before overriding, and restore it from the cache when the volume is exited.
## [./player/player_interaction_component.gd : 79]
- **Category:** Destructive Overrides & Expensive Tree Traversal
- **Current State:** `player.find_child("WeaponInventoryComponent", true, false) as WeaponInventoryComponent`
- **Underlying Risk:** Executing a recursive `find_child` lookup dynamically is extremely expensive and causes frame-time spikes, especially if called during interaction polling or per-frame.
- **Recommended Remediation:** Cache the reference to `WeaponInventoryComponent` in `_ready()` or use exported NodePaths instead of dynamic lookups.
## [./ui/loading_screen_anim.gd : 318]
- **Category:** Destructive Overrides & Expensive Tree Traversal
- **Current State:** `new_scene.find_child("WorldChunkManager", true, false) as WorldChunkManager`
- **Underlying Risk:** Using recursive `find_child` on a newly loaded scene root is slow and can hitch the loading thread or main thread.
- **Recommended Remediation:** Use groups to fetch the manager, or enforce a strict known NodePath relative to the scene root.
## [./ui/vision_section.gd : 294]
- **Category:** Destructive Overrides & Expensive Tree Traversal
- **Current State:** `var camera_nodes: Array[Node] = diorama_root.find_children("Camera_*", "Camera3D", true, false)`
- **Underlying Risk:** Executing `find_children` recursively on a complex scene root generates high CPU cost and can induce stutter.
- **Recommended Remediation:** Use Godot's `Group` system to retrieve all related cameras, or store an array of camera NodePaths explicitly in a manager script.
