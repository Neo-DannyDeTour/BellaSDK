## Characterization tests locking Wave 18 core APIs, constants, signals, and behavior.
class_name TestWave18Characterization
extends GutTest

const FREECAM_SCRIPT: GDScript = preload("res://core/console/freecam_controller.gd")


## Verifies [KeycardSystem] inventory add, check, consume, and signal behavior.
func test_keycard_system_contracts() -> void:
	assert_true(KeycardSystem.has_signal(&"card_picked_up"))
	assert_true(KeycardSystem.has_signal(&"card_used"))

	var test_id: StringName = &"wave18_test_card"
	if KeycardSystem.has_card(test_id):
		KeycardSystem.consume_card(test_id)

	watch_signals(KeycardSystem)
	assert_false(KeycardSystem.has_card(test_id))

	KeycardSystem.add_card(test_id)
	assert_true(KeycardSystem.has_card(test_id))
	assert_signal_emitted_with_parameters(KeycardSystem, &"card_picked_up", [test_id])

	KeycardSystem.add_card(test_id)
	assert_signal_emit_count(KeycardSystem, &"card_picked_up", 1)

	KeycardSystem.consume_card(test_id)
	assert_false(KeycardSystem.has_card(test_id))
	assert_signal_emitted_with_parameters(KeycardSystem, &"card_used", [test_id])


## Verifies [SonarManager] constants, signals, exports, and safe null handling.
func test_sonar_manager_contracts() -> void:
	assert_true(SonarManager.has_signal(&"on_scan_completed"))
	assert_eq(SonarManager.get(&"MAX_AUDIO_PLAYERS"), 16)
	assert_eq(SonarManager.get(&"SFX_BUS_NAME"), &"AccesibilitySFX")
	assert_almost_eq(float(SonarManager.get(&"SPATIAL_DEDUPLICATION_THRESHOLD_SQ")), 1.0, 0.001)
	assert_almost_eq(float(SonarManager.get(&"scan_radius")), 25.0, 0.001)
	assert_almost_eq(float(SonarManager.get(&"wave_speed")), 40.0, 0.001)
	assert_almost_eq(float(SonarManager.get(&"min_cue_separation")), 0.05, 0.001)
	assert_eq(SonarManager.get(&"max_audible_targets"), 8)
	assert_true(SonarManager.has_method(&"trigger_sonar"))

	SonarManager.call(&"trigger_sonar", null)


## Verifies [SpatialDescriber] signals, exports, and safe null handling.
func test_spatial_describer_contracts() -> void:
	assert_true(SpatialDescriber.has_signal(&"on_description_generated"))
	assert_almost_eq(float(SpatialDescriber.get(&"description_radius")), 12.0, 0.001)
	assert_almost_eq(float(SpatialDescriber.get(&"nearby_distance_threshold")), 4.0, 0.001)
	assert_almost_eq(float(SpatialDescriber.get(&"cluster_distance_threshold")), 2.5, 0.001)
	assert_almost_eq(
		float(SpatialDescriber.get(&"spatial_deduplication_threshold_sq")), 0.25, 0.001
	)
	assert_eq(SpatialDescriber.get(&"max_announced_clusters"), 4)
	assert_almost_eq(float(SpatialDescriber.get(&"eye_height_offset")), 1.6, 0.001)
	assert_almost_eq(float(SpatialDescriber.get(&"above_elevation_threshold")), 0.35, 0.001)
	assert_almost_eq(float(SpatialDescriber.get(&"below_ground_threshold")), 0.5, 0.001)
	assert_true(SpatialDescriber.has_method(&"describe_surroundings"))

	SpatialDescriber.call(&"describe_surroundings", null)


## Verifies [AudioPool] constants, player retrieval, and null-stream guards.
func test_audio_pool_contracts() -> void:
	assert_eq(AudioPool.get(&"POOL_SIZE_2D"), 16)
	assert_eq(AudioPool.get(&"POOL_SIZE_3D"), 32)
	assert_true(AudioPool.has_method(&"play_sfx_2d"))
	assert_true(AudioPool.has_method(&"play_sfx_3d"))
	assert_true(AudioPool.has_method(&"get_pooled_player_2d"))
	assert_true(AudioPool.has_method(&"get_pooled_player_3d"))

	assert_null(AudioPool.call(&"play_sfx_2d", null))
	assert_null(AudioPool.call(&"play_sfx_3d", null, Vector3.ZERO))

	var p2d: Variant = AudioPool.call(&"get_pooled_player_2d")
	assert_true(p2d is AudioStreamPlayer)
	var p3d: Variant = AudioPool.call(&"get_pooled_player_3d")
	assert_true(p3d is AudioStreamPlayer3D)


## Verifies [AudioManager] constants, null-stream guards, and throttled playback.
func test_audio_manager_contracts() -> void:
	assert_eq(AudioManager.get(&"DEFAULT_CONCURRENCY_LIMIT"), 4)
	assert_true(AudioManager.has_method(&"play_sfx_2d_throttled"))
	assert_true(AudioManager.has_method(&"play_sfx_3d_throttled"))

	assert_null(AudioManager.call(&"play_sfx_2d_throttled", null))
	assert_null(AudioManager.call(&"play_sfx_3d_throttled", null, Vector3.ZERO))

	var dummy_stream: AudioStreamWAV = AudioStreamWAV.new()
	var p2d: Variant = AudioManager.call(
		&"play_sfx_2d_throttled", dummy_stream, &"SFX", Vector2(1.0, 1.0), 1
	)
	assert_true(p2d is AudioStreamPlayer)
	var suppressed_2d: Variant = AudioManager.call(
		&"play_sfx_2d_throttled", dummy_stream, &"SFX", Vector2(1.0, 1.0), 1
	)
	assert_null(suppressed_2d)
	if p2d is AudioStreamPlayer:
		var player_node: AudioStreamPlayer = p2d as AudioStreamPlayer
		player_node.stop()
		player_node.finished.emit()


## Verifies [CameraShakeManager] exports, trauma, rumble, scaling, and stop behavior.
func test_camera_shake_manager_contracts() -> void:
	var mgr: CameraShakeManager = CameraShakeManager.new()
	add_child_autofree(mgr)

	assert_true(mgr.has_signal(&"shake_updated"))
	assert_true(mgr.has_signal(&"shake_finished"))
	assert_almost_eq(mgr.global_intensity, 1.0, 0.001)
	assert_eq(mgr.max_offset_px, Vector2(32.0, 32.0))
	assert_almost_eq(mgr.max_roll_rad, 0.08, 0.001)
	assert_almost_eq(mgr.noise_frequency, 24.0, 0.001)
	assert_almost_eq(mgr.trauma_decay_rate, 1.2, 0.001)
	assert_almost_eq(mgr.trauma, 0.0, 0.001)
	assert_false(mgr.is_processing())

	var cam: Camera3D = Camera3D.new()
	add_child_autofree(cam)
	mgr.register_camera(cam)

	mgr.add_trauma(0.5)
	assert_almost_eq(mgr.trauma, 0.5, 0.001)
	assert_true(mgr.is_processing())

	mgr.add_trauma(1.0)
	assert_almost_eq(mgr.trauma, 1.0, 0.001)

	mgr.set_accessibility_scale(3.5)
	assert_almost_eq(mgr.global_intensity, 2.0, 0.001)
	mgr.set_accessibility_scale(-1.0)
	assert_almost_eq(mgr.global_intensity, 0.0, 0.001)

	watch_signals(mgr)
	mgr.start_rumble(0.4, 0.5)
	assert_true(mgr.is_processing())
	mgr.stop_all()
	assert_almost_eq(mgr.trauma, 0.0, 0.001)
	assert_false(mgr.is_processing())
	assert_signal_emitted(mgr, &"shake_finished")


## Verifies [ConsoleCommand], [ConsoleCommandRegistry], and [ConsoleHistory] contracts.
func test_console_core_data_contracts() -> void:
	var invoked: Array[bool] = [false]
	var cmd: ConsoleCommand = ConsoleCommand.new(
		"WaveTest",
		"Test command",
		func(_args: PackedStringArray) -> void: invoked[0] = true,
		func() -> Array[String]: return ["alpha", "beta"],
		false
	)
	assert_eq(cmd.name, "WaveTest")
	assert_eq(cmd.description, "Test command")
	assert_false(cmd.is_debug)
	assert_true(cmd.handler.is_valid())
	assert_true(cmd.arg_provider.is_valid())

	var reg: ConsoleCommandRegistry = ConsoleCommandRegistry.new()
	reg.register_command(cmd)
	assert_true(reg.has_command("wavetest"))
	assert_eq(reg.get_command("WAVETEST"), cmd)
	assert_eq(reg.get_valid_commands(), ["wavetest"])

	var matches_cmd: Array[String] = reg.get_autocomplete_matches("wave")
	assert_true(matches_cmd.has("wavetest"))
	var matches_arg: Array[String] = reg.get_autocomplete_matches("wavetest al")
	assert_true(matches_arg.has("wavetest alpha"))

	reg.unregister_command("wavetest")
	assert_false(reg.has_command("wavetest"))
	assert_null(reg.get_command("wavetest"))

	var hist: ConsoleHistory = ConsoleHistory.new(2)
	assert_true(hist.is_empty())
	assert_eq(hist.navigate(-1), "")

	hist.add("   ")
	assert_true(hist.is_empty())

	hist.add("first")
	hist.add("first")
	hist.add("second")
	hist.add("third")
	assert_false(hist.is_empty())
	assert_eq(hist.navigate(-1), "third")
	assert_eq(hist.navigate(-1), "second")
	assert_eq(hist.navigate(1), "third")
	assert_eq(hist.navigate(1), "")
	hist.reset_index()
	assert_eq(hist.navigate(-1), "third")


## Verifies [ConsoleContext] toggle parsing, state lookup, and tree queries.
func test_console_context_contracts() -> void:
	var states: Dictionary = {"god": true}
	var ctx: ConsoleContext = ConsoleContext.new(null, states)

	assert_true(ctx.get_toggle_state("god"))
	assert_false(ctx.get_toggle_state("missing"))
	assert_true(ctx.get_toggle_state("missing", true))
	assert_eq(ctx.get_toggle_options(), ["on", "off", "1", "0"])

	var toggle_flipped: Variant = ctx.parse_toggle_arg(PackedStringArray(), true, "god")
	assert_eq(toggle_flipped, false)
	var toggle_on: Variant = ctx.parse_toggle_arg(PackedStringArray(["on"]), false, "god")
	assert_eq(toggle_on, true)
	var toggle_off: Variant = ctx.parse_toggle_arg(PackedStringArray(["0"]), true, "god")
	assert_eq(toggle_off, false)
	var toggle_invalid: Variant = ctx.parse_toggle_arg(PackedStringArray(["maybe"]), false, "god")
	assert_null(toggle_invalid)

	assert_not_null(ctx.get_tree())
	assert_not_null(ctx.get_viewport())


## Verifies [ConsoleCheatCommands], [ConsoleSettingsCommands], and [ConsoleSystemCommands].
func test_console_command_modules_registration() -> void:
	assert_true(ConsoleCheatCommands.ENEMY_SCENE_PATHS.has("turret"))
	assert_true(ConsoleCheatCommands.WEAPON_SCENE_PATHS.has("revolver"))
	assert_true(ConsoleCheatCommands.ITEM_SCENE_PATHS.has("glider"))
	assert_eq(ConsoleCheatCommands.KEYCARD_CLEARANCE_MAP.get("card_g"), &"G")
	assert_eq(ConsoleCheatCommands.AMMO_TYPE_MAP.get("bullet"), &"revolver")
	assert_not_null(ConsoleCheatCommands.FREECAM_SCRIPT)

	var ctx: ConsoleContext = ConsoleContext.new(null, {})
	var reg: ConsoleCommandRegistry = ConsoleCommandRegistry.new()

	var cheats: ConsoleCheatCommands = ConsoleCheatCommands.new(ctx)
	cheats.register_commands(reg)
	var settings_cmds: ConsoleSettingsCommands = ConsoleSettingsCommands.new(ctx)
	settings_cmds.register_commands(reg)
	var sys_cmds: ConsoleSystemCommands = ConsoleSystemCommands.new(ctx)
	sys_cmds.register_commands(reg)

	assert_true(reg.has_command("help"))
	assert_true(reg.has_command("clear"))
	assert_true(reg.has_command("quit"))
	assert_true(reg.has_command("exit"))
	assert_true(reg.has_command("save"))
	assert_true(reg.has_command("load"))
	assert_true(reg.has_command("colorblind"))
	assert_true(reg.has_command("highcontrast"))
	assert_true(reg.has_command("fov"))
	assert_true(reg.has_command("vsync"))

	if OS.has_feature("debug"):
		assert_true(reg.has_command("god"))
		assert_true(reg.has_command("noclip"))
		assert_true(reg.has_command("teleport"))
		assert_true(reg.has_command("restart"))


## Verifies [FreecamController] constants, setup, and exit restoration.
func test_freecam_controller_contracts() -> void:
	var prev_mouse_mode: Input.MouseMode = Input.mouse_mode
	var freecam_raw: Variant = FREECAM_SCRIPT.new()
	assert_true(freecam_raw is Camera3D)
	var freecam: Camera3D = freecam_raw as Camera3D
	add_child_autofree(freecam)

	assert_almost_eq(float(freecam.get(&"BASE_SPEED")), 12.0, 0.001)
	assert_almost_eq(float(freecam.get(&"FAST_SPEED_MULT")), 3.0, 0.001)
	assert_almost_eq(float(freecam.get(&"MOUSE_SENSITIVITY")), 0.003, 0.0001)
	assert_almost_eq(float(freecam.get(&"JOYPAD_SENSITIVITY")), 2.5, 0.001)
	assert_almost_eq(float(freecam.get(&"JOYPAD_DEADZONE")), 0.15, 0.001)
	assert_eq(freecam.get(&"CONSOLE_NODE_PATH"), ^"/root/InGameConsole")
	assert_almost_eq(float(freecam.get(&"speed_multiplier")), 1.0, 0.001)

	var source_cam: Camera3D = Camera3D.new()
	source_cam.fov = 82.0
	add_child_autofree(source_cam)
	var dummy_player: Node3D = Node3D.new()
	add_child_autofree(dummy_player)

	watch_signals(Events)
	freecam.call(&"setup", source_cam, dummy_player)
	assert_almost_eq(freecam.fov, 82.0, 0.001)
	assert_signal_emitted_with_parameters(Events, &"player_cinematic_lock_requested", [true])

	freecam.call(&"restore_and_exit")
	assert_signal_emitted_with_parameters(Events, &"player_cinematic_lock_requested", [false])
	Input.mouse_mode = prev_mouse_mode


## Verifies [DevMetricsPanel] constants, initial visibility, and toggle behavior.
func test_dev_metrics_panel_contracts() -> void:
	assert_eq(DevMetricsPanel.HISTORY_NUM_FRAMES, 150)
	assert_almost_eq(DevMetricsPanel.METRICS_UPDATE_INTERVAL, 0.2, 0.001)
	assert_almost_eq(DevMetricsPanel.TARGET_FRAME_BUDGET_MS, 16.67, 0.001)

	var panel: DevMetricsPanel = DevMetricsPanel.new()
	var label: RichTextLabel = RichTextLabel.new()
	label.name = "MetricsLabel"
	panel.add_child(label)
	add_child_autofree(panel)

	assert_true(panel.is_enabled)
	assert_false(panel.visible)
	panel.toggle_window()
	assert_true(panel.visible)
	panel.toggle_window()
	assert_false(panel.visible)


## Verifies [Events] singleton constants, properties, and core signal contracts.
func test_events_bus_contracts() -> void:
	assert_true(Events.UI_FONT_TYPES.has(&"Label"))
	assert_true(Events.UI_FONT_TYPES.has(&"RichTextLabel"))
	assert_true(Events.UI_FONT_KEYS.has(&"font"))
	assert_true(Events.UI_FONT_KEYS.has(&"normal_font"))
	assert_false(Events.is_godmode)

	var expected_signals: Array[StringName] = [
		&"sfx_2d_requested",
		&"sfx_3d_requested",
		&"game_started",
		&"game_pause_toggled",
		&"player_died",
		&"player_health_changed",
		&"screenshake_requested",
		&"screen_fade_requested",
		&"sonar_ping_requested",
		&"describe_surroundings_requested",
		&"interaction_focused",
		&"interaction_unfocused",
		&"interacted",
		&"object_focused",
		&"player_camera_registered",
		&"player_cinematic_lock_requested",
		&"screen_blackout_instant_requested",
		&"screen_wake_up_requested",
		&"shockwave_requested",
		&"console_toggled",
	]
	for sig_name: StringName in expected_signals:
		assert_true(Events.has_signal(sig_name), "Missing Events signal: " + String(sig_name))


## Verifies [InteractionManager] constants, signals, focus clearing, and interaction guards.
func test_interaction_manager_contracts() -> void:
	assert_almost_eq(InteractionManager.DEFAULT_MAX_DISTANCE, 3.0, 0.001)
	assert_eq(InteractionManager.METHOD_INTERACT, &"interact")
	assert_eq(InteractionManager.METHOD_GET_PROMPT, &"get_interaction_prompt")
	assert_eq(InteractionManager.METHOD_SET_HIGHLIGHT, &"set_highlight")
	assert_eq(InteractionManager.DEFAULT_PROMPT, "Interact")

	var mgr: InteractionManager = InteractionManager.new()
	add_child_autofree(mgr)

	assert_true(mgr.has_signal(&"focused"))
	assert_true(mgr.has_signal(&"unfocused"))
	assert_true(mgr.has_signal(&"interacted"))
	assert_almost_eq(mgr.max_distance, 3.0, 0.001)
	assert_null(mgr.current_target)
	assert_eq(mgr.current_prompt, "")

	var cam: Camera3D = Camera3D.new()
	add_child_autofree(cam)
	mgr.set_source_camera(cam)
	assert_eq(mgr.source_camera, cam)
	mgr.scan_for_interactable()
	assert_false(mgr.try_interact(null))
	mgr.clear_focus()


## Verifies [ShaderCacheBuilder] constants and EditorScript entrypoint.
func test_shader_cache_builder_contracts() -> void:
	assert_eq(ShaderCacheBuilder.CACHE_PATH, "res://core/shader_cache.tres")
	assert_eq(ShaderCacheBuilder.MATERIALS_DIR, "res://")
	assert_eq(ShaderCacheBuilder.IGNORED_DIRS, [".godot", ".git", "addons"])

	var script_ref: Script = ShaderCacheBuilder as Script
	assert_not_null(script_ref)
	var has_run: bool = false
	for method_info: Dictionary in script_ref.get_script_method_list():
		if str(method_info.get("name", "")) == "_run":
			has_run = true
			break
	assert_true(has_run)


## Verifies [StartScreen] exports, child wiring, and initial button focus.
func test_start_screen_contracts() -> void:
	var screen: StartScreen = StartScreen.new()
	var center: CenterContainer = CenterContainer.new()
	center.name = "CenterContainer"
	var btn: Button = Button.new()
	btn.name = "StartButton"
	center.add_child(btn)
	screen.add_child(center)
	add_child_autofree(screen)

	assert_eq(screen.main_game_scene_path, "res://ui/main_menu.tscn")
	assert_eq(screen.start_button, btn)


## Verifies [TTSInteractComponent] hover speech routing and override precedence.
func test_tts_interact_component_contracts() -> void:
	var tts_comp: TTSInteractComponent = TTSInteractComponent.new()
	var lbl: Label3D = Label3D.new()
	lbl.text = "Power Switch"
	add_child_autofree(lbl)
	tts_comp.target_label = lbl
	add_child_autofree(tts_comp)

	watch_signals(Events)
	tts_comp.hover_cursor(null, Vector3.ZERO)
	assert_signal_emitted_with_parameters(Events, &"object_focused", ["Power Switch", tts_comp])

	tts_comp.hover_cursor(null, Vector3.ZERO)
	assert_signal_emit_count(Events, &"object_focused", 1)

	var tts_override: TTSInteractComponent = TTSInteractComponent.new()
	tts_override.target_label = lbl
	tts_override.alt_text_override = "Phonetic Switch"
	add_child_autofree(tts_override)

	tts_override.hover_cursor(null, Vector3.ZERO)
	assert_signal_emitted_with_parameters(
		Events, &"object_focused", ["Phonetic Switch", tts_override]
	)


## Verifies [ScreenEffectsCore] constants, default state, and public API signatures.
func test_screen_effects_core_contracts() -> void:
	assert_eq(ScreenEffectsCore.SHOCKWAVE_POOL_SIZE, 6)
	assert_almost_eq(ScreenEffectsCore.DEFAULT_TRAUMA_DECAY, 1.0, 0.001)
	assert_not_null(ScreenEffectsCore.SHADER_TRANSITION)

	var fx: ScreenEffectsCore = ScreenEffectsCore.new()
	assert_true(fx.has_method(&"start_screen_fade"))
	assert_true(fx.has_method(&"trigger_shockwave"))
	assert_true(fx.has_method(&"set_screen_black_instant"))
	assert_true(fx.has_method(&"start_wake_up"))
	fx.free()
