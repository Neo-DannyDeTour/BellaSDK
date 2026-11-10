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
			"perf_uncap",
			"Toggles session VSync and FPS cap uncap for performance stress testing.",
			_cmd_perf_uncap,
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
	registry.register_command(
		ConsoleCommand.new(
			"volume",
			"Adjusts audio bus volume (0-100) or displays bus levels.",
			_cmd_volume,
			_get_volume_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"fullscreen",
			"Toggles fullscreen display mode.",
			_cmd_fullscreen,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"resolution",
			"Sets display resolution width and height.",
			_cmd_resolution,
			_get_resolution_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"res", "Sets display resolution (alias).", _cmd_resolution, _get_resolution_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"tts",
			"Toggles text-to-speech accessibility narration.",
			_cmd_tts,
			context.get_toggle_options
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"outline",
			"Configures interactable outline mode (0=Off, 1=First Sight, 2=Periodic).",
			_cmd_outline,
			func() -> Array[String]: return ["0", "1", "2", "off", "simple", "pulse"]
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
	registry.register_command(
		ConsoleCommand.new(
			"render_diagnostics",
			"Toggles in-game render diagnostics overlay panel.",
			_cmd_render_diagnostics,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"diagnostics",
			"Toggles in-game render diagnostics overlay panel (alias).",
			_cmd_render_diagnostics,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"metrics", "Toggles on-screen developer metrics panel.", _cmd_metrics, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"stat_metrics",
			"Toggles on-screen developer metrics panel (alias).",
			_cmd_metrics,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"fps_limit",
			"Sets target engine max FPS (0 = uncapped).",
			_cmd_fps_limit,
			_get_fps_limit_options,
			false
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"max_fps",
			"Sets target engine max FPS (alias).",
			_cmd_fps_limit,
			_get_fps_limit_options,
			false
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"stat_perf",
			"Prints instantaneous hardware, geometry, and render performance snapshot.",
			_cmd_stat_perf,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"perf", "Prints performance snapshot (alias).", _cmd_stat_perf, Callable(), true
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


## Toggles session VSync and max FPS limit without persisting to configuration.
func _cmd_perf_uncap(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_perf_uncap called with args: ", args)
	var currently_uncapped: bool = (
		DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED
		and Engine.max_fps == 0
	)
	var parsed: Variant = context.parse_toggle_arg(args, currently_uncapped, "perf_uncap")
	if parsed == null:
		return
	var should_uncap: bool = parsed == true
	if should_uncap:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		context.write("Performance uncap ACTIVATED: VSync disabled, Engine.max_fps = 0.", "yellow")
	else:
		var vsync_setting: int = GlobalSettings.get_setting_int("Video", "vsync_mode", 1)
		var fps_setting: int = GlobalSettings.get_setting_int("Video", "fps_limit", 60)
		DisplayServer.window_set_vsync_mode(vsync_setting as DisplayServer.VSyncMode)
		Engine.max_fps = fps_setting
		context.write(
			"Performance uncap DEACTIVATED: Restored VSync and FPS limit to %d." % fps_setting,
			"green"
		)


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


## Toggles the render diagnostics panel via global event bus.
func _cmd_render_diagnostics(_args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_render_diagnostics called.")
	Events.render_diagnostics_toggle_requested.emit()
	context.write("Render diagnostics panel toggled.", "cyan")


## Toggles the developer metrics panel via global event bus.
func _cmd_metrics(_args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_metrics called.")
	Events.metrics_panel_toggle_requested.emit()
	context.write("Developer metrics panel toggled.", "cyan")


## Returns autocomplete candidates for the fps_limit command.
func _get_fps_limit_options() -> Array[String]:
	return ["0", "30", "60", "120", "144", "240"]


## Sets and persists engine frame rate cap.
func _cmd_fps_limit(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_fps_limit called with args: ", args)
	if args.is_empty():
		var cur_cap: int = Engine.max_fps
		context.write("Current FPS limit: " + str(cur_cap) + ". Usage: fps_limit <int>", "yellow")
		return

	var raw_str: String = args[0].strip_edges()
	if not raw_str.is_valid_int():
		context.write("Invalid FPS limit. Please provide an integer >= 0.", "red")
		return

	var limit: int = clampi(raw_str.to_int(), 0, 1000)
	Engine.max_fps = limit
	GlobalSettings.save_setting("Settings", "fps_limit", limit, true)
	var label: String = "Uncapped (0)" if limit == 0 else str(limit) + " FPS"
	context.write("Engine max FPS set to: " + label, "green")


## Outputs an instantaneous performance snapshot to the console display.
func _cmd_stat_perf(_args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_stat_perf called.")
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var p_time: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_time: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var ram_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var draws: int = roundi(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = roundi(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs: int = roundi(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))

	context.write("--- Performance Snapshot ---", "cyan")
	context.write(
		"FPS: %d | Frame: %.2f ms | Physics: %.2f ms" % [roundi(fps), p_time, phys_time], "white"
	)
	context.write("RAM: %.2f MB | VRAM: %.2f MB" % [ram_mb, vram_mb], "white")
	context.write("Draw Calls: %d | Primitives: %d | Objects: %d" % [draws, prims, objs], "white")


## Returns autocomplete candidates for available audio buses.
func _get_volume_options() -> Array[String]:
	var count: int = AudioServer.bus_count
	var list: Array[String] = []
	for i: int in range(count):
		list.append(AudioServer.get_bus_name(i).to_lower())
	return list


## Adjusts or queries audio bus volumes.
func _cmd_volume(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_volume called with args: ", args)
	if args.is_empty():
		context.write("--- Audio Bus Volumes ---", "cyan")
		var count: int = AudioServer.bus_count
		for i: int in range(count):
			var b_name: String = AudioServer.get_bus_name(i)
			var is_muted: bool = AudioServer.is_bus_mute(i)
			var db: float = AudioServer.get_bus_volume_db(i)
			var pct: float = db_to_linear(db) * 100.0 if not is_muted else 0.0
			var mute_str: String = " [MUTED]" if is_muted else ""
			context.write("  - %s: %.0f%% (%.1f dB)%s" % [b_name, pct, db, mute_str], "white")
		return

	var bus_arg: String = args[0].strip_edges()
	var bus_idx: int = AudioServer.get_bus_index(bus_arg)
	if bus_idx < 0:
		var count: int = AudioServer.bus_count
		for i: int in range(count):
			if AudioServer.get_bus_name(i).to_lower() == bus_arg.to_lower():
				bus_idx = i
				break

	if bus_idx < 0:
		context.write("Audio bus '" + bus_arg + "' not found.", "red")
		return

	var canonical_name: String = AudioServer.get_bus_name(bus_idx)
	if args.size() == 1:
		var is_muted: bool = AudioServer.is_bus_mute(bus_idx)
		var db: float = AudioServer.get_bus_volume_db(bus_idx)
		var pct: float = db_to_linear(db) * 100.0 if not is_muted else 0.0
		context.write("%s volume: %.0f%% (%.1f dB)" % [canonical_name, pct, db], "cyan")
		return

	var raw_pct: String = args[1].strip_edges()
	if not raw_pct.is_valid_float():
		context.write("Invalid volume level. Please specify 0-100.", "red")
		return

	var pct_val: float = clampf(raw_pct.to_float(), 0.0, 100.0)
	var is_muted: bool = pct_val <= 0.1
	var norm: float = maxf(pct_val / 100.0, 0.0001)
	var target_db: float = linear_to_db(norm)

	AudioServer.set_bus_mute(bus_idx, is_muted)
	AudioServer.set_bus_volume_db(bus_idx, target_db)
	GlobalSettings.save_setting("Audio", canonical_name, pct_val, true)
	context.write("%s volume set to: %.0f%%" % [canonical_name, pct_val], "green")


## Toggles fullscreen display mode on the active window.
func _cmd_fullscreen(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_fullscreen called with args: ", args)
	var win: Window = context.get_viewport().get_window()
	if not is_instance_valid(win):
		context.write("Window reference unavailable.", "red")
		return

	var is_currently_fullscreen: bool = (
		win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	)
	var parsed: Variant = context.parse_toggle_arg(args, is_currently_fullscreen, "fullscreen")
	if parsed == null:
		return
	var set_full: bool = parsed == true
	var target_mode: Window.Mode = (
		Window.MODE_EXCLUSIVE_FULLSCREEN if set_full else Window.MODE_WINDOWED
	)
	win.mode = target_mode
	GlobalSettings.save_setting("Settings", "display_mode", int(target_mode), true)
	context.write("Fullscreen " + ("enabled." if set_full else "disabled."), "green")


## Returns autocomplete candidates for common display resolutions.
func _get_resolution_options() -> Array[String]:
	return ["1280 720", "1920 1080", "2560 1440", "3840 2160"]


## Adjusts active window or viewport content scale resolution.
func _cmd_resolution(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_resolution called with args: ", args)
	var win: Window = context.get_viewport().get_window()
	if not is_instance_valid(win):
		context.write("Window reference unavailable.", "red")
		return

	if args.size() < 2:
		var cur_res: Vector2i = win.size
		context.write(
			(
				"Current window size: %dx%d. Usage: resolution <width> <height>"
				% [cur_res.x, cur_res.y]
			),
			"yellow"
		)
		return

	var w_str: String = args[0].strip_edges()
	var h_str: String = args[1].strip_edges()
	if not w_str.is_valid_int() or not h_str.is_valid_int():
		context.write("Invalid resolution format. Specify positive integers.", "red")
		return

	var w: int = clampi(w_str.to_int(), 640, 7680)
	var h: int = clampi(h_str.to_int(), 360, 4320)
	var new_res: Vector2i = Vector2i(w, h)

	VideoApplier.apply_window_settings(
		win, win.mode as DisplayServer.WindowMode, win.current_screen, new_res
	)
	GlobalSettings.save_setting("Settings", "resolution_x", w, false)
	GlobalSettings.save_setting("Settings", "resolution_y", h, true)
	context.write("Resolution set to: %dx%d" % [w, h], "green")


## Toggles text-to-speech accessibility narration via global event bus.
func _cmd_tts(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_tts called with args: ", args)
	var cur_state: bool = GlobalSettings.get_setting_bool("Accessibility", "tts_enabled", false)
	var parsed: Variant = context.parse_toggle_arg(args, cur_state, "tts")
	if parsed == null:
		return
	var active: bool = parsed == true
	GlobalSettings.save_setting("Accessibility", "tts_enabled", active, true)
	Events.tts_state_changed.emit(active)
	context.write("Text-to-Speech narration " + ("enabled." if active else "disabled."), "green")


## Sets interactive outline highlight mode.
func _cmd_outline(args: PackedStringArray) -> void:
	print("ConsoleSettingsCommands: _cmd_outline called with args: ", args)
	if args.is_empty():
		var cur_mode: int = GlobalSettings.get_setting_int("Accessibility", "outline_mode", 2)
		context.write(
			"Current outline mode: %d. Usage: outline <0|1|2|off|simple|pulse>" % cur_mode, "yellow"
		)
		return

	var token: String = args[0].strip_edges().to_lower()
	var mode_val: int = 2
	match token:
		"0", "off", "disable", "disabled":
			mode_val = 0
		"1", "simple", "first_sight", "sight":
			mode_val = 1
		"2", "pulse", "periodic", "always":
			mode_val = 2
		_:
			if token.is_valid_int():
				mode_val = clampi(token.to_int(), 0, 2)
			else:
				context.write("Invalid mode. Usage: outline <0|1|2|off|simple|pulse>", "red")
				return

	GlobalSettings.save_setting("Accessibility", "outline_mode", mode_val, true)
	Events.outline_mode_changed.emit(mode_val)
	var labels: Array[String] = ["Disabled (0)", "First Sight (1)", "Periodic Pulse (2)"]
	context.write("Outline highlight mode set to: " + labels[mode_val], "green")
