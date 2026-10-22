## Central video controller autoload managing graphics state, diorama isolation, and level parity.
extends Node

## Emitted when the active video configuration state is updated or reset.
@warning_ignore("unused_signal")
signal settings_changed(active_config: Dictionary)

## Emitted when the diorama sandbox switches between active and dormant states.
@warning_ignore("unused_signal")
signal diorama_mode_changed(is_active: bool)

## In-memory normalized dictionary storing the player's active video configuration.
var active_config: Dictionary = {}

## Tracks whether the options menu diorama preview is currently active.
var is_diorama_active: bool = false

## Override flag allowing developer or player to completely inhibit the diorama preview.
var is_diorama_killed: bool = false


## Initializes the central video controller, loads saved settings, and hooks SceneTree events.
func _ready() -> void:
	print("GraphicsManager: Initializing central video controller.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_physics_process(false)

	load_from_disk()
	get_tree().node_added.connect(_on_node_added)
	call_deferred(&"commit_full_pipeline")


## Cleanly disconnects SceneTree observer on exit.
func _exit_tree() -> void:
	if is_instance_valid(get_tree()) and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## Loads all video settings from [GlobalSettings], defaulting missing keys to "Ultra" preset.
func load_from_disk() -> void:
	print("GraphicsManager: Loading video configuration into state cache.")
	var defaults: Dictionary = VideoConfig.get_default_settings_dict()
	active_config.clear()

	for key_var: Variant in defaults.keys():
		var key: String = str(key_var)
		var def_val: Variant = defaults[key]
		var saved_val: Variant = GlobalSettings.get_setting("Settings", key, def_val)

		if def_val is bool:
			var def_bool: bool = def_val
			active_config[key] = GlobalSettings.get_setting_bool("Settings", key, def_bool)
		elif def_val is int:
			var def_int: int = def_val
			active_config[key] = GlobalSettings.get_setting_int("Settings", key, def_int)
		elif def_val is float:
			var def_float: float = def_val
			active_config[key] = GlobalSettings.get_setting_float("Settings", key, def_float)
		else:
			active_config[key] = str(saved_val)


## Returns a value from the cached active configuration or [param default_val].
func get_setting(key: String, default_val: Variant = null) -> Variant:
	return active_config.get(key, default_val)


## Updates a single setting in cache, persists via [GlobalSettings], and applies live feedback.
func set_setting(key: String, value: Variant, apply_immediately: bool = true) -> void:
	var current: Variant = active_config.get(key, null)
	if typeof(current) == typeof(value) and current == value:
		return

	print("GraphicsManager: Updating setting [", key, "] -> ", value)
	active_config[key] = value
	GlobalSettings.save_setting("Settings", key, value)

	if apply_immediately:
		if (
			key
			in [
				"display_mode",
				"screen_index",
				"resolution_x",
				"resolution_y",
				"vsync_mode",
				"fps_limit",
				"ui_scale",
			]
		):
			apply_display_settings()
		elif is_diorama_active:
			update_diorama_preview()
		else:
			commit_gameplay_pipeline()

	settings_changed.emit(active_config)


## Applies a master quality preset ("Low", "Medium", "High", "Ultra") atomically.
func apply_preset(preset_name: String) -> void:
	if not VideoConfig.PRESETS.has(preset_name):
		push_warning("GraphicsManager: Unknown quality preset requested: " + preset_name)
		return

	print("GraphicsManager: Applying master quality preset -> ", preset_name)
	var raw_preset: Variant = VideoConfig.PRESETS[preset_name]
	var preset_dict: Dictionary = raw_preset if raw_preset is Dictionary else {}

	active_config["preset"] = preset_name
	var bulk_save: Dictionary = {"preset": preset_name}
	for key_var: Variant in preset_dict.keys():
		var key: String = str(key_var)
		active_config[key] = preset_dict[key]
		bulk_save[key] = preset_dict[key]

	GlobalSettings.save_settings_bulk("Settings", bulk_save, true)

	if is_diorama_active:
		update_diorama_preview()
	else:
		commit_gameplay_pipeline()

	settings_changed.emit(active_config)


## Resets all video settings to the canonical "Ultra" preset and default display values.
func reset_to_defaults() -> void:
	print("GraphicsManager: Resetting all video settings to 'Ultra' defaults.")
	var defaults: Dictionary = VideoConfig.get_default_settings_dict()
	active_config = defaults.duplicate(true)
	GlobalSettings.save_settings_bulk("Settings", active_config, true)

	apply_display_settings()
	if is_diorama_active:
		update_diorama_preview()
	else:
		commit_gameplay_pipeline()

	settings_changed.emit(active_config)


## Applies window mode, monitor index, resolution, VSync, FPS cap, and UI scale.
func apply_display_settings() -> void:
	if not is_inside_tree():
		return
	var win: Window = get_window()
	if not is_instance_valid(win):
		return

	var mode_int: int = VideoApplier._get_int(
		active_config, "display_mode", VideoConfig.DEFAULT_DISPLAY
	)
	var screen_idx: int = VideoApplier._get_int(active_config, "screen_index", 0)
	var res_x: int = VideoApplier._get_int(active_config, "resolution_x", VideoConfig.DEFAULT_RES_X)
	var res_y: int = VideoApplier._get_int(active_config, "resolution_y", VideoConfig.DEFAULT_RES_Y)
	VideoApplier.apply_window_settings(
		win, mode_int as DisplayServer.WindowMode, screen_idx, Vector2i(res_x, res_y)
	)

	var vsync_int: int = VideoApplier._get_int(
		active_config, "vsync_mode", VideoConfig.DEFAULT_VSYNC
	)
	var fps_cap: int = VideoApplier._get_int(active_config, "fps_limit", VideoConfig.DEFAULT_FPS)
	VideoApplier.apply_engine_limits(vsync_int as DisplayServer.VSyncMode, fps_cap)

	var ui_scale: float = VideoApplier._get_float(
		active_config, "ui_scale", VideoConfig.DEFAULT_UI_SCALE
	)
	if not is_equal_approx(win.content_scale_factor, ui_scale):
		win.content_scale_factor = ui_scale


## Updates the isolated diorama environment synchronously for real-time menu preview.
func update_diorama_preview() -> void:
	if not is_inside_tree():
		return
	var diorama_vp: SubViewport = VideoApplier.resolve_diorama_viewport(get_tree())
	if is_instance_valid(diorama_vp):
		VideoApplier.apply_diorama_preview(diorama_vp, active_config)


## Atomically commits the full 3D rendering pipeline to the gameplay viewport and world.
func commit_gameplay_pipeline() -> void:
	if not is_inside_tree():
		return
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return
	VideoApplier.apply_gameplay_pipeline(tree, tree.root, active_config)


## Applies both display/window settings and the active 3D rendering pipeline.
func commit_full_pipeline() -> void:
	apply_display_settings()
	if is_diorama_active:
		update_diorama_preview()
	else:
		commit_gameplay_pipeline()


## Switches between isolated Diorama Preview mode and active Gameplay rendering mode.
## Guarantees zero concurrent SDFGI or volumetric fog compute between viewports.
func set_diorama_mode(active: bool) -> void:
	if not is_inside_tree():
		is_diorama_active = active
		return

	var tree: SceneTree = get_tree()
	var root_vp: Window = tree.root
	var diorama_vp: SubViewport = VideoApplier.resolve_diorama_viewport(tree)
	var scene_name: StringName = (
		tree.current_scene.name if is_instance_valid(tree.current_scene) else &"Unknown"
	)

	if active and is_diorama_killed:
		is_diorama_active = false
		print("[Pipeline] DIORAMA KILLED: Preview suppressed. Main (", scene_name, ") active.")
		if is_instance_valid(diorama_vp):
			_disable_diorama_gi(diorama_vp)
			diorama_vp.disable_3d = true
			diorama_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			diorama_vp.process_mode = Node.PROCESS_MODE_DISABLED
		if is_instance_valid(root_vp):
			root_vp.disable_3d = false
		if is_instance_valid(tree.current_scene) and tree.current_scene != diorama_vp:
			tree.current_scene.process_mode = Node.PROCESS_MODE_INHERIT
		diorama_mode_changed.emit(false)
		return

	if is_diorama_active == active and is_instance_valid(diorama_vp):
		if active:
			update_diorama_preview()
		return

	is_diorama_active = active

	if active:
		print(
			"[Pipeline] MAIN LEVEL (",
			scene_name,
			") FROZEN (process_mode=DISABLED) | DIORAMA ACTIVE (update=WHEN_VISIBLE)"
		)
		_suspend_gameplay_gi(tree, diorama_vp)
		if is_instance_valid(root_vp):
			root_vp.disable_3d = true
		if is_instance_valid(tree.current_scene) and tree.current_scene != diorama_vp:
			tree.current_scene.process_mode = Node.PROCESS_MODE_DISABLED
		if is_instance_valid(diorama_vp):
			VideoApplier.configure_diorama_sandbox(diorama_vp)
			diorama_vp.disable_3d = false
			diorama_vp.process_mode = Node.PROCESS_MODE_ALWAYS
			diorama_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
			VideoApplier.apply_diorama_preview(diorama_vp, active_config)
	else:
		if is_instance_valid(diorama_vp):
			_disable_diorama_gi(diorama_vp)
			diorama_vp.disable_3d = true
			diorama_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
			diorama_vp.process_mode = Node.PROCESS_MODE_DISABLED
			var dio_cams: Array[Node] = diorama_vp.find_children("*", "Camera3D", true, false)
			for c_node: Node in dio_cams:
				var c: Camera3D = c_node as Camera3D
				if is_instance_valid(c):
					c.current = false
					c.process_mode = Node.PROCESS_MODE_DISABLED

		var menu_open: bool = _is_menu_visible()
		if menu_open:
			print(
				"[Pipeline] DIORAMA SLEEPING | MAIN LEVEL (", scene_name, ") KEPT FROZEN (in menu)"
			)
			if is_instance_valid(root_vp):
				root_vp.disable_3d = true
			if is_instance_valid(tree.current_scene) and tree.current_scene != diorama_vp:
				tree.current_scene.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			print(
				"[Pipeline] DIORAMA SLEEPING (update=DISABLED) | MAIN LEVEL (",
				scene_name,
				") RESUMED"
			)
			if is_instance_valid(root_vp):
				root_vp.disable_3d = false
			if is_instance_valid(tree.current_scene) and tree.current_scene != diorama_vp:
				tree.current_scene.process_mode = Node.PROCESS_MODE_INHERIT
			commit_gameplay_pipeline()

	_assert_single_sdfgi_invariant()
	diorama_mode_changed.emit(active)


## Sets the diorama kill override switch.
func set_diorama_killed(killed: bool) -> void:
	is_diorama_killed = killed
	print("GraphicsManager: set_diorama_killed -> ", killed)
	if killed and is_diorama_active:
		set_diorama_mode(false)


## Configures Variable Rate Shading state on the root gameplay [Viewport].
func apply_vrs_state(enabled: bool) -> void:
	set_setting("vrs_mode", "Texture" if enabled else "Disabled")


## Suspends SDFGI and volumetric fog on gameplay environments while the diorama is open.
func _suspend_gameplay_gi(tree: SceneTree, diorama_vp: SubViewport) -> void:
	var we_nodes: Array[Node] = tree.root.find_children("*", "WorldEnvironment", true, false)
	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if not is_instance_valid(we) or not is_instance_valid(we.environment):
			continue
		if is_instance_valid(diorama_vp) and diorama_vp.is_ancestor_of(we):
			continue
		we.environment.sdfgi_enabled = false
		we.environment.volumetric_fog_enabled = false


## Disables SDFGI and volumetric fog on the diorama environment when sleeping.
func _disable_diorama_gi(diorama_vp: SubViewport) -> void:
	diorama_vp.disable_3d = true
	var dio_w: World3D = diorama_vp.find_world_3d()
	if is_instance_valid(dio_w) and is_instance_valid(dio_w.environment):
		dio_w.environment.sdfgi_enabled = false
		dio_w.environment.volumetric_fog_enabled = false

	var we_nodes: Array[Node] = diorama_vp.find_children("*", "WorldEnvironment", true, false)
	for node: Node in we_nodes:
		var we: WorldEnvironment = node as WorldEnvironment
		if is_instance_valid(we) and is_instance_valid(we.environment):
			we.environment.sdfgi_enabled = false
			we.environment.volumetric_fog_enabled = false


## Asserts that gameplay SDFGI and diorama SDFGI are never active concurrently.
func _assert_single_sdfgi_invariant() -> void:
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return
	var diorama_vp: SubViewport = VideoApplier.resolve_diorama_viewport(tree)
	var diorama_sdfgi: bool = false
	if is_instance_valid(diorama_vp) and not diorama_vp.disable_3d:
		var dio_w: World3D = diorama_vp.find_world_3d()
		if is_instance_valid(dio_w) and is_instance_valid(dio_w.environment):
			diorama_sdfgi = dio_w.environment.sdfgi_enabled

	var gameplay_sdfgi: bool = false
	if not tree.root.disable_3d:
		var target_we: WorldEnvironment = (
			tree.get_first_node_in_group(&"level_environment") as WorldEnvironment
		)
		if is_instance_valid(target_we) and is_instance_valid(target_we.environment):
			gameplay_sdfgi = target_we.environment.sdfgi_enabled

	assert(
		not (diorama_sdfgi and gameplay_sdfgi),
		"GraphicsManager: Concurrent SDFGI invariant violated!"
	)


## SceneTree observer ensuring newly added gameplay environments, lights, and cameras
## inherit parity.
func _on_node_added(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if node is WorldEnvironment:
		var we: WorldEnvironment = node as WorldEnvironment
		if we.is_in_group(&"ignore_global_video_settings") or _is_inside_diorama(we):
			return
		var is_level_env: bool = we.is_in_group(&"level_environment")
		if not is_level_env:
			var tree: SceneTree = get_tree()
			var current: Node = tree.current_scene if is_instance_valid(tree) else null
			if not is_instance_valid(current) or we.get_parent() != current:
				return
		print("GraphicsManager: Gameplay WorldEnvironment entered tree -> ", we.name)
		VideoApplier.apply_to_world_environment(we, active_config)
		if is_diorama_active and is_instance_valid(we.environment):
			we.environment.sdfgi_enabled = false
			we.environment.volumetric_fog_enabled = false
	elif node is Light3D:
		var light: Light3D = node as Light3D
		var is_dio: bool = _is_inside_diorama(light)
		VideoApplier.apply_to_light(light, active_config, is_dio)
	elif node is Camera3D:
		var cam: Camera3D = node as Camera3D
		var is_dio: bool = _is_inside_diorama(cam)
		if is_dio or VideoApplier.is_player_camera(cam):
			VideoApplier.apply_to_camera(cam, active_config, is_dio)


## Returns true if [param node] resides inside the preview diorama [SubViewport].
func _is_inside_diorama(node: Node) -> bool:
	if not is_instance_valid(node):
		return false
	return node.find_parent("DioramaViewport") != null


## Returns true if the main or pause menu is currently present and visible in the tree.
func _is_menu_visible() -> bool:
	if not is_inside_tree():
		return false
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.root):
		return false
	var menu_nodes: Array[Node] = tree.root.find_children("*", "MainMenu", true, false)
	for m_node: Node in menu_nodes:
		var menu: CanvasLayer = m_node as CanvasLayer
		if is_instance_valid(menu) and menu.visible:
			return true
	return false
