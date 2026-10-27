## Registers and executes audio, video, accessibility, and render debug console commands.
class_name ConsoleSettingsCommands
extends RefCounted

## Context reference providing output logging and scene tree access.
var context: ConsoleContext = null


## Constructs a new [ConsoleSettingsCommands] module with the given [param p_context].
func _init(p_context: ConsoleContext) -> void:
	context = p_context


## Registers audio, visual, and accessibility commands into the provided [param registry].
func register_commands(registry: ConsoleCommandRegistry) -> void:
	print("ConsoleSettingsCommands: Registering settings commands.")
	registry.register_command(
		ConsoleCommand.new(
			"colorblind",
			"Applies accessibility colorblind shader.",
			_cmd_colorblind,
			_get_colorblind_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"highcontrast",
			"Toggles high contrast overlay mode.",
			_cmd_highcontrast,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new("screenshake", "Triggers a screenshake event.", _cmd_screenshake)
	)
	registry.register_command(
		ConsoleCommand.new(
			"subtitles", "Toggles dialogue subtitles.", _cmd_subtitles, context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"mono_audio",
			"Toggles mono audio downmixing.",
			_cmd_mono_audio,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"photosensitivity",
			"Toggles photosensitive safety filter.",
			_cmd_photosensitivity,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new("setfont", "Changes global font style.", _cmd_setfont, _get_font_options)
	)
	registry.register_command(
		ConsoleCommand.new(
			"screenfilter",
			"Applies fullscreen post-processing filter.",
			_cmd_screenfilter,
			_get_screen_filter_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"visionassist",
			"Configures vision assist highlights.",
			_cmd_visionassist,
			func() -> Array[String]: return ["on", "off", "1", "0", "mode", "color"]
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"wolfvision", "Toggles wolf vision mode.", _cmd_wolfvision, context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"wolfmode",
			"Toggles player wolf form transformation.",
			_cmd_wolfmode,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"togglecrouch",
			"Switches crouch input between hold and toggle.",
			_cmd_togglecrouch,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"togglesprint",
			"Switches sprint input between hold and toggle.",
			_cmd_togglesprint,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"aimassist",
			"Toggles controller aim friction and magnetism.",
			_cmd_aimassist,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"textspeed", "Sets dialogue text reveal speed multiplier.", _cmd_textspeed
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"audio_spatial",
			"Toggles positional 3D audio downmixing.",
			_cmd_audio_spatial,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new("fov", "Overrides camera field of view.", _cmd_fov)
	)
	registry.register_command(
		ConsoleCommand.new(
			"shadows", "Toggles global shadow casting.", _cmd_shadows, context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"vsync",
			"Toggles vertical synchronization mode.",
			_cmd_vsync,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"hidehud", "Toggles HUD visibility.", _cmd_hidehud, context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new("gamma", "Adjusts environment tonemap exposure.", _cmd_gamma)
	)
	registry.register_command(
		ConsoleCommand.new(
			"noshake",
			"Disables camera screenshake triggers.",
			_cmd_noshake,
			context.get_toggle_options
		)
	)
	_register_render_debug(registry)


## Registers visual and render debug commands.
func _register_render_debug(registry: ConsoleCommandRegistry) -> void:
	registry.register_command(
		ConsoleCommand.new(
			"fullbright",
			"Toggles fullbright unshaded render mode.",
			_cmd_fullbright,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"wireframe",
			"Toggles wireframe rendering mode.",
			_cmd_wireframe,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"wireframeoverlay",
			"Toggles green wireframe overlay.",
			_cmd_wireframe_overlay,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"collision",
			"Toggles debug collision shape visibility.",
			_cmd_collision,
			context.get_toggle_options,
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"normals", "Toggles normal buffer debug view.", _cmd_normals, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"deathscreen", "Previews death sequence.", _cmd_deathscreen, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"diorama",
			"Controls 3D options diorama (kill/0/disabled to stop, live/1/enabled to restore).",
			_cmd_diorama,
			_get_diorama_options,
			false
		)
	)


## Returns autocomplete candidates for colorblind shader modes.
func _get_colorblind_options() -> Array[String]:
	return ["normal", "protanopia", "deuteranopia", "tritanopia", "mono", "achromatopsia", "split"]


## Returns available font identifiers from [GlobalSettings].
func _get_font_options() -> Array[String]:
	if is_instance_valid(GlobalSettings):
		return GlobalSettings.get_font_ids()
	return []


## Returns available screen filter identifiers from [GlobalSettings].
func _get_screen_filter_options() -> Array[String]:
	if is_instance_valid(GlobalSettings):
		return GlobalSettings.get_screen_filter_ids()
	return []


## Handles colorblind command execution and dispatches event signals.
func _cmd_colorblind(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_colorblind called with args: ", args)
	if args.is_empty():
		var hint: String = (
			"Usage: colorblind <normal|protanopia|deuteranopia|" + "tritanopia|mono|split>"
		)
		context.write(hint, "yellow")
		return

	var mode_arg: String = args[0].to_lower()
	var mode_int: int = -1
	match mode_arg:
		"off", "normal":
			mode_int = 0
		"protanopia":
			mode_int = 1
		"deuteranopia":
			mode_int = 2
		"tritanopia":
			mode_int = 3
		"achromatopsia", "mono":
			mode_int = 4
		"split", "all", "debug":
			mode_int = 5
		_:
			var err: String = (
				"Unknown type. Try: normal, protanopia, deuteranopia, " + "tritanopia, mono, split"
			)
			context.write(err, "red")
			return

	Events.colorblind_mode_changed.emit(mode_int)
	context.write("Colorblind mode set to: " + mode_arg, "green")


## Handles high contrast command toggling.
func _cmd_highcontrast(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("highcontrast", false), "highcontrast"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["highcontrast"] = active
	print("ConsoleSettingsCommands: Toggled highcontrast to: ", active)
	Events.high_contrast_toggled.emit(active)
	context.write("High contrast " + ("activated." if active else "deactivated."), "green")


## Handles screenshake command requests.
func _cmd_screenshake(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_screenshake called with args: ", args)
	if context.get_toggle_state("noshake", false):
		context.write("Screenshake suppressed via noshake.", "yellow")
		return

	if args.is_empty():
		var hint: String = "Usage: screenshake <intensity 0.0-16.0> [duration_in_seconds]"
		context.write(hint, "yellow")
		return

	var amount: float = args[0].to_float()
	var duration: float = 1.0
	if args.size() > 1:
		duration = args[1].to_float()

	Events.screenshake_requested.emit(amount, duration)
	var msg: String = (
		"Screenshake: Intensity "
		+ str(clampf(amount, 0.0, 16.0))
		+ ", Duration "
		+ str(duration)
		+ "s"
	)
	context.write(msg, "green")


## Handles subtitle toggling.
func _cmd_subtitles(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("subtitles", false), "subtitles"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["subtitles"] = active
	print("ConsoleSettingsCommands: Toggled subtitles to: ", active)
	Events.subtitles_toggled.emit(active)
	context.write("Subtitles " + ("activated." if active else "deactivated."), "green")


## Handles mono audio downmixing toggling.
func _cmd_mono_audio(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("mono_audio", false), "mono_audio"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["mono_audio"] = active
	print("ConsoleSettingsCommands: Toggled mono_audio to: ", active)
	context.write("Mono audio " + ("activated." if active else "deactivated."), "green")


## Handles photosensitivity mode toggling.
func _cmd_photosensitivity(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("photosensitivity", false), "photosensitivity"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["photosensitivity"] = active
	print("ConsoleSettingsCommands: Toggled photosensitivity to: ", active)
	Events.photosensitivity_mode_toggled.emit(active)
	var status_str: String = "activated." if active else "deactivated."
	context.write("Photosensitivity mode " + status_str, "green")


## Handles setfont command requests.
func _cmd_setfont(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_setfont called with args: ", args)
	var valid_fonts: Array[String] = []
	if is_instance_valid(GlobalSettings):
		valid_fonts = GlobalSettings.get_font_ids()

	if args.is_empty():
		var hint: String = "Usage: setfont <font_name>\nAvailable: " + ", ".join(valid_fonts)
		context.write(hint, "yellow")
		return

	var font_choice: String = args[0].to_lower()
	if font_choice in valid_fonts:
		Events.font_changed.emit(font_choice)
		context.write("Global font set to: " + font_choice, "green")
	else:
		context.write("Unknown font. Available: " + ", ".join(valid_fonts), "red")


## Handles screenfilter command requests.
func _cmd_screenfilter(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_screenfilter called with args: ", args)
	var valid_filters: Array[String] = []
	if is_instance_valid(GlobalSettings):
		valid_filters = GlobalSettings.get_screen_filter_ids()

	if args.is_empty():
		var hint: String = "Usage: screenfilter <type>\nAvailable: " + ", ".join(valid_filters)
		context.write(hint, "yellow")
		return

	var filter_type: String = args[0].to_lower()
	if filter_type == "off" or filter_type in valid_filters:
		Events.screen_filter_changed.emit(filter_type)
		context.write("Screen filter: " + filter_type, "green")
	else:
		context.write("Unknown filter. Available: " + ", ".join(valid_filters), "red")


## Handles visionassist command configurations and toggles.
func _cmd_visionassist(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_visionassist called with args: ", args)
	if (
		args.is_empty()
		or (
			args[0].to_lower()
			in ["1", "on", "true", "enable", "enabled", "0", "off", "false", "disable", "disabled"]
		)
	):
		var parsed: Variant = context.parse_toggle_arg(
			args, context.get_toggle_state("visionassist", false), "visionassist"
		)
		if parsed == null:
			return
		var active: bool = parsed == true
		context.toggle_states["visionassist"] = active
		print("ConsoleSettingsCommands: Vision assist toggled to: ", active)
		Events.vision_assist_toggled.emit(active)
		var stat: String = "activated." if active else "deactivated."
		context.write("Vision assist " + stat, "green")
		return

	var arg1: String = args[0].to_lower()
	if arg1 == "mode" and args.size() == 2:
		var mode_name: String = args[1].to_lower()
		if mode_name in ["black_and_white", "aaa_blue", "pure_black"]:
			Events.vision_assist_mode_changed.emit(mode_name)
			context.write("Vision Assist mode set to: " + mode_name, "green")
		else:
			var err: String = "Invalid mode. Use 'black_and_white', 'aaa_blue', or 'pure_black'."
			context.write(err, "yellow")
	elif arg1 == "color" and args.size() == 3:
		var target_group: String = args[1].to_lower()
		var color_name: String = args[2].to_lower()
		Events.vision_assist_color_changed.emit(target_group, color_name)
		var msg: String = "Vision Assist: Changed " + target_group + " to " + color_name
		context.write(msg, "green")
	else:
		var hint: String = (
			"Usage: visionassist [on/off | 1/0] OR visionassist mode <mode> OR "
			+ "visionassist color <group> <color>"
		)
		context.write(hint, "yellow")


## Handles wolfvision toggling.
func _cmd_wolfvision(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("wolfvision", false), "wolfvision"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["wolfvision"] = active
	print("InGameConsole: Wolf vision toggled to: ", active)
	Events.wolf_vision_toggled.emit(active)
	context.write("Wolf vision " + ("activated." if active else "deactivated."), "green")


## Handles fullbright render mode toggling.
func _cmd_fullbright(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("fullbright", false), "fullbright"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["fullbright"] = active
	print("ConsoleSettingsCommands: Toggled fullbright to: ", active)
	Events.fullbright_toggled.emit(active)
	context.write("Fullbright " + ("activated." if active else "deactivated."), "green")


## Handles wireframe render mode toggling.
func _cmd_wireframe(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("wireframe", false), "wireframe"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["wireframe"] = active
	print("ConsoleSettingsCommands: Toggled wireframe to: ", active)
	Events.wireframe_toggled.emit(active)
	context.write("Wireframe " + ("activated." if active else "deactivated."), "green")


## Handles wireframe overlay material toggling.
func _cmd_wireframe_overlay(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("wireframeoverlay", false), "wireframeoverlay"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["wireframeoverlay"] = active
	print("ConsoleSettingsCommands: Toggled wireframe overlay to: ", active)
	Events.wireframe_overlay_toggled.emit(active)
	var status_str: String = "activated." if active else "deactivated."
	context.write("Wireframe overlay " + status_str, "green")


## Handles debug collision shape visibility toggling.
func _cmd_collision(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("collision", false), "collision"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["collision"] = active
	print("ConsoleSettingsCommands: Toggled collisions to: ", active)
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		tree.debug_collisions_hint = active
		var colliders: Array[Node] = tree.get_nodes_in_group(&"debug_colliders")
		for col: Node in colliders:
			if col is CanvasItem:
				(col as CanvasItem).visible = active
			elif col is Node3D:
				(col as Node3D).visible = active
	var stat: String = "activated." if active else "deactivated."
	context.write("Collision shapes " + stat, "green")


## Handles normal buffer visualization debug mode toggling.
func _cmd_normals(_args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: Action Toggled Normal View")
	var vp: Viewport = context.get_viewport()
	if not is_instance_valid(vp):
		return
	if vp.debug_draw == Viewport.DEBUG_DRAW_NORMAL_BUFFER:
		vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		context.write("Normal view deactivated.", "yellow")
	else:
		vp.debug_draw = Viewport.DEBUG_DRAW_NORMAL_BUFFER
		context.write("Normal view activated.", "green")


## Handles deathscreen preview command via group and scene lookups.
func _cmd_deathscreen(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: Action Executing 'deathscreen' preview.")
	if args.is_empty():
		context.write("Usage: deathscreen <ecg|cave|lava|static|glass|jitter>", "yellow")
		return

	var screen_name: String = args[0].to_lower()
	var tree: SceneTree = context.get_tree()
	if not is_instance_valid(tree):
		return
	var ds: DeathScreen = NodeQuery.get_single_node_in_group(tree, &"death_screen") as DeathScreen

	if not is_instance_valid(ds):
		var curr_scene: Node = tree.current_scene
		if is_instance_valid(curr_scene):
			ds = NodeQuery.find_first_child_of_type(curr_scene, DeathScreen) as DeathScreen

	if not is_instance_valid(ds):
		context.write("DeathScreen node not found in scene tree.", "red")
		return

	var chosen_effect: DeathScreen.EffectType = DeathScreen.EffectType.ECG
	match screen_name:
		"ecg":
			chosen_effect = DeathScreen.EffectType.ECG
		"lava":
			chosen_effect = DeathScreen.EffectType.LAVA
		"cave":
			chosen_effect = DeathScreen.EffectType.CAVE_TUNNEL
		"static":
			chosen_effect = DeathScreen.EffectType.TV_STATIC
		"glass":
			chosen_effect = DeathScreen.EffectType.GLASS
		"jitter":
			chosen_effect = DeathScreen.EffectType.JITTER
		"burn":
			chosen_effect = DeathScreen.EffectType.BURN
		_:
			var err: String = "Unknown screen. Available: ecg, cave, lava, static, glass, jitter, burn"
			context.write(err, "red")
			return

	if is_instance_valid(context.host) and context.host.has_method(&"_on_console_toggle_requested"):
		context.host.call(&"_on_console_toggle_requested")
	ds.play_death_sequence(chosen_effect)
	context.write("Previewing death screen: " + screen_name.to_upper(), "green")


## Updates the camera field of view setting.
func _cmd_fov(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_fov called with args: ", args)
	if args.is_empty():
		context.write("Usage: fov <degrees 30-130>", "yellow")
		return

	var fov_val: float = clampf(args[0].to_float(), 30.0, 130.0)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Settings", "base_fov", fov_val)

	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		var player_node: Node = NodeQuery.get_single_node_in_group(tree, &"player")
		if is_instance_valid(player_node) and &"camera_controller" in player_node:
			var cam_ctrl: Node = player_node.get(&"camera_controller")
			if is_instance_valid(cam_ctrl):
				cam_ctrl.set(&"base_fov", fov_val)
				cam_ctrl.set(&"target_fov", fov_val)
				var cam_val: Variant = cam_ctrl.get(&"camera")
				var cam: Camera3D = cam_val if cam_val is Camera3D else null
				if is_instance_valid(cam):
					cam.fov = fov_val

	context.write("Field of view set to: " + str(fov_val), "green")


## Configures runtime shadow rendering across 3D lights.
func _cmd_shadows(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_shadows called with args: ", args)
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("shadows", false), "shadows"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["shadows"] = active
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		var lights: Array[Node] = tree.get_nodes_in_group(&"lights")
		for light_node: Node in lights:
			if light_node is Light3D:
				(light_node as Light3D).shadow_enabled = active

	context.write("Dynamic shadows " + ("enabled." if active else "disabled."), "green")


## Configures runtime V-Sync display mode.
func _cmd_vsync(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_vsync called with args: ", args)
	var current_enabled: bool = (
		DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	)
	var parsed: Variant = context.parse_toggle_arg(args, current_enabled, "vsync")
	if parsed == null:
		return
	var enable: bool = parsed == true
	var mode: DisplayServer.VSyncMode = (
		DisplayServer.VSYNC_ENABLED if enable else DisplayServer.VSYNC_DISABLED
	)
	DisplayServer.window_set_vsync_mode(mode)
	context.write("V-Sync " + ("enabled." if enable else "disabled."), "green")


## Toggles player HUD layer node visibility via event bus.
func _cmd_hidehud(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("hidehud", false), "hidehud"
	)
	if parsed == null:
		return
	var is_hidden: bool = parsed == true
	context.toggle_states["hidehud"] = is_hidden
	print("ConsoleSettingsCommands: Toggled hidehud -> ", is_hidden)
	Events.ui_visibility_toggle_requested.emit()
	context.write("HUD " + ("hidden." if is_hidden else "revealed."), "green")


## Sets global environment tonemap exposure value.
func _cmd_gamma(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_gamma called with args: ", args)
	if args.is_empty():
		context.write("Usage: gamma <value 0.1-3.0>", "yellow")
		return

	var gamma_val: float = clampf(args[0].to_float(), 0.1, 3.0)
	var env: Environment = null
	var tree: SceneTree = context.get_tree()

	if is_instance_valid(tree):
		var env_node: Node = NodeQuery.get_single_node_in_group(tree, &"world_environment")
		if is_instance_valid(env_node) and env_node is WorldEnvironment:
			env = (env_node as WorldEnvironment).environment
		else:
			var curr_scene: Node = tree.current_scene
			if is_instance_valid(curr_scene):
				var direct_env: Node = NodeQuery.find_first_child_of_type(
					curr_scene, WorldEnvironment
				)
				if direct_env is WorldEnvironment:
					env = (direct_env as WorldEnvironment).environment

	if env == null:
		var vp: Viewport = context.get_viewport()
		if is_instance_valid(vp):
			var world_3d: World3D = vp.find_world_3d()
			if is_instance_valid(world_3d):
				env = world_3d.environment

	if is_instance_valid(env):
		env.tonemap_exposure = gamma_val
		context.write("Tonemap exposure set to: " + str(gamma_val), "green")
	else:
		context.write("Active Environment resource not found.", "yellow")


## Prevents screenshake events from firing on the event bus.
func _cmd_noshake(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("noshake", false), "noshake"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["noshake"] = active
	print("ConsoleSettingsCommands: Toggled noshake -> ", active)
	context.write("Screenshake suppression " + ("enabled." if active else "disabled."), "green")


## Toggles crouch input behavior between hold and toggle.
func _cmd_togglecrouch(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("togglecrouch", false), "togglecrouch"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["togglecrouch"] = active
	print("ConsoleSettingsCommands: Toggled togglecrouch -> ", active)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Controls", "toggle_crouch", active)
	var stat: String = "enabled." if active else "disabled (hold)."
	context.write("Toggle crouch " + stat, "green")


## Toggles sprint input behavior between hold and toggle.
func _cmd_togglesprint(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("togglesprint", false), "togglesprint"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["togglesprint"] = active
	print("ConsoleSettingsCommands: Toggled togglesprint -> ", active)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Controls", "toggle_sprint", active)
	var stat: String = "enabled." if active else "disabled (hold)."
	context.write("Toggle sprint " + stat, "green")


## Configures aim friction and bullet magnetism assists (0=off, 1=mid, 2=full).
func _cmd_aimassist(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_aimassist called with args: ", args)
	var current_mode: int = 1
	if is_instance_valid(GlobalSettings):
		current_mode = GlobalSettings.get_setting_int("Gameplay", "aim_assist_mode", 1)

	var target_mode: int = current_mode
	if args.is_empty():
		target_mode = 0 if current_mode > 0 else 1
	else:
		var arg_str: String = args[0].to_lower()
		match arg_str:
			"0", "off", "disable", "false":
				target_mode = 0
			"1", "mid", "friction", "glue":
				target_mode = 1
			"2", "full", "magnetism", "bullet", "true":
				target_mode = 2
			_:
				context.write("Usage: aimassist <off|mid|full|0|1|2>", "yellow")
				return

	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Gameplay", "aim_assist_mode", target_mode)
		GlobalSettings.save_setting("Gameplay", "aim_assist", target_mode > 0)
	if Events.has_signal(&"aim_assist_mode_changed"):
		Events.aim_assist_mode_changed.emit(target_mode)

	var mode_name: String = "disabled (off)."
	if target_mode == 1:
		mode_name = "enabled (mid - friction/glue)."
	elif target_mode == 2:
		mode_name = "enabled (full - bullet magnetism)."
	context.write("Aim assist " + mode_name, "green")


## Sets subtitle text reveal speed rate.
func _cmd_textspeed(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_textspeed called with args: ", args)
	if args.is_empty():
		context.write("Usage: textspeed <multiplier 0.5-3.0>", "yellow")
		return

	var speed_val: float = clampf(args[0].to_float(), 0.5, 3.0)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Accessibility", "text_speed", speed_val)
	context.write("Text speed multiplier set to: " + str(speed_val), "green")


## Configures 3D spatial audio downmixing to stereo 2D.
func _cmd_audio_spatial(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_audio_spatial called with args: ", args)
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("audio_spatial", false), "audio_spatial"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["audio_spatial"] = active
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Audio", "spatial_audio", active)
	var stat: String = "enabled." if active else "disabled (2D stereo)."
	context.write("Spatial 3D audio " + stat, "green")


## Toggles player wolf mode state and broadcasts to event bus.
func _cmd_wolfmode(args: PackedStringArray) -> void:
	var parsed: Variant = context.parse_toggle_arg(
		args, context.get_toggle_state("wolfmode", false), "wolfmode"
	)
	if parsed == null:
		return
	var active: bool = parsed == true
	context.toggle_states["wolfmode"] = active
	print("ConsoleSettingsCommands: Toggled wolfmode -> ", active)
	Events.wolf_mode_toggled.emit(active)
	var stat: String = "activated." if active else "deactivated."
	context.write("Wolf form " + stat, "green")


## Returns autocomplete candidates for diorama command.
func _get_diorama_options() -> Array[String]:
	return ["kill", "live", "0", "1", "disabled", "enabled", "status"]


## Controls 3D options diorama activity.
func _cmd_diorama(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_diorama called with args: ", args)
	if args.is_empty():
		var is_killed: bool = GraphicsManager.is_diorama_killed
		var stat: String = "KILLED (disabled)" if is_killed else "LIVE (normal)"
		var hint: String = (
			"Diorama state: " + stat + ". Usage: diorama <kill|live|0|1|disabled|enabled>"
		)
		context.write(hint, "yellow")
		return

	var arg: String = args[0].to_lower()
	match arg:
		"kill", "0", "disabled", "disable", "off", "stop":
			GraphicsManager.set_diorama_killed(true)
			context.write("Diorama KILLED: Options menu 3D diorama will not render.", "red")
		"live", "1", "enabled", "enable", "on", "start":
			GraphicsManager.set_diorama_killed(false)
			var msg: String = "Diorama LIVE: Options diorama restored to normal operation."
			context.write(msg, "green")
		"status":
			var is_killed: bool = GraphicsManager.is_diorama_killed
			var stat: String = "KILLED" if is_killed else "LIVE"
			context.write("Diorama current state: " + stat, "cyan")
		_:
			context.write(
				"Unknown argument. Usage: diorama <kill|live|0|1|disabled|enabled>", "yellow"
			)
