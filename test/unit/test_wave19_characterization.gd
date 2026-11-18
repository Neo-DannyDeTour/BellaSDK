## Characterization tests locking Wave 19 autoload APIs, constants, signals, and behavior.
class_name TestWave19Characterization
extends GutTest


## Verifies [Global] autoload signals, RNG seeding, runtime cache, and main scene tracking.
func test_global_contracts() -> void:
	assert_true(Global.has_signal(&"main_scene_registered"))
	assert_true(Global.has_signal(&"game_seed_changed"))
	assert_eq(Global.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(Global.rng is RandomNumberGenerator)

	var prev_seed: int = Global.current_seed
	var prev_main: Node = Global.main

	watch_signals(Global)
	Global.set_game_seed(123456)
	assert_eq(Global.current_seed, 123456)
	assert_eq(Global.rng.seed, 123456)
	assert_signal_emitted_with_parameters(Global, &"game_seed_changed", [123456])

	Global.cache_value(&"wave19_key", 42)
	assert_eq(Global.get_cached_value(&"wave19_key"), 42)
	assert_eq(Global.get_cached_value(&"wave19_missing", "fallback"), "fallback")
	Global.clear_cache()
	assert_null(Global.get_cached_value(&"wave19_key"))

	var dummy_main: Node = Node.new()
	add_child_autofree(dummy_main)
	Global.set_main(dummy_main)
	assert_eq(Global.main, dummy_main)
	assert_signal_emitted_with_parameters(Global, &"main_scene_registered", [dummy_main])

	Global.set_main(prev_main)
	Global.set_game_seed(prev_seed)


## Verifies [GestureInputManager] constants, signals, and safe action query defaults.
func test_gesture_input_manager_contracts() -> void:
	assert_true(GestureInputManager.has_signal(&"action_triggered"))
	assert_almost_eq(float(GestureInputManager.get(&"HOLD_THRESHOLD")), 0.45, 0.001)
	assert_almost_eq(float(GestureInputManager.get(&"MULTI_TAP_WINDOW")), 0.30, 0.001)
	assert_eq(GestureInputManager.get(&"MASH_TAP_COUNT"), 3)
	assert_almost_eq(float(GestureInputManager.get(&"BUFFER_DURATION")), 0.20, 0.001)

	assert_false(GestureInputManager.consume_buffered_action("w19_nonexistent"))
	assert_false(GestureInputManager.is_action_just_triggered("w19_nonexistent"))
	assert_false(GestureInputManager.is_action_active("w19_nonexistent"))
	assert_false(GestureInputManager.is_action_pressed("w19_nonexistent"))
	assert_false(GestureInputManager.is_action_just_pressed("w19_nonexistent"))
	assert_false(GestureInputManager.is_action_just_released("w19_nonexistent"))
	assert_true(GestureInputManager.has_method(&"get_vector"))
	assert_true(GestureInputManager.has_method(&"get_axis"))


## Verifies [GlobalSettings] registries, typed getters, and default InputMap bindings.
func test_global_settings_contracts() -> void:
	assert_eq(GlobalSettings.get(&"SAVE_PATH"), "user://settings.cfg")
	assert_almost_eq(float(GlobalSettings.get(&"SAVE_DEBOUNCE_DELAY")), 0.35, 0.001)

	var font_ids: Array[String] = GlobalSettings.get_font_ids()
	var font_names: Array[String] = GlobalSettings.get_font_display_names()
	assert_eq(font_ids.size(), 9)
	assert_eq(font_names.size(), 9)
	assert_eq(GlobalSettings.get_font_index("dyslexic"), 1)
	assert_eq(GlobalSettings.get_font_index("w19_missing"), 0)
	assert_eq(GlobalSettings.get_font_path("kramola"), "res://assets/fonts/kramola/Kramola.otf")
	assert_eq(GlobalSettings.get_font_path("w19_missing"), "")

	var filter_ids: Array[String] = GlobalSettings.get_screen_filter_ids()
	var filter_names: Array[String] = GlobalSettings.get_screen_filter_display_names()
	assert_eq(filter_ids.size(), 26)
	assert_eq(filter_names.size(), 26)
	assert_eq(GlobalSettings.get_screen_filter_index("crt"), 1)
	assert_eq(GlobalSettings.get_screen_filter_index("w19_missing"), 0)
	assert_eq(GlobalSettings.get_screen_filter_path("crt"), "res://vfx/crt.gdshader")
	assert_eq(GlobalSettings.get_screen_filter_path("w19_missing"), "")

	assert_eq(GlobalSettings.get_setting("W19_Missing", "key", "def"), "def")
	assert_true(GlobalSettings.get_setting_bool("W19_Missing", "b", true))
	assert_eq(GlobalSettings.get_setting_int("W19_Missing", "i", 7), 7)
	assert_almost_eq(GlobalSettings.get_setting_float("W19_Missing", "f", 2.5), 2.5, 0.001)

	GlobalSettings.ensure_default_actions()
	assert_true(InputMap.has_action(&"weapon_slot_1"))
	assert_true(InputMap.has_action(&"debug_toggle_metrics"))


## Verifies [GraphicsManager] signals, config cache, compositor helper, and diorama toggle.
func test_graphics_manager_contracts() -> void:
	assert_true(GraphicsManager.has_signal(&"settings_changed"))
	assert_true(GraphicsManager.has_signal(&"diorama_mode_changed"))
	assert_eq(GraphicsManager.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(GraphicsManager.is_processing())
	assert_false(GraphicsManager.is_physics_processing())

	var comp_raw: Variant = GraphicsManager.call(&"get_empty_subviewport_compositor")
	assert_true(comp_raw is Compositor)

	var cfg_raw: Variant = GraphicsManager.get(&"active_config")
	assert_true(cfg_raw is Dictionary)
	if cfg_raw is Dictionary:
		var cfg: Dictionary = cfg_raw
		assert_true(cfg.has("preset"))
	assert_eq(GraphicsManager.get_setting("w19_missing", "fallback"), "fallback")

	assert_true(GraphicsManager.has_method(&"load_from_disk"))
	assert_true(GraphicsManager.has_method(&"set_setting"))
	assert_true(GraphicsManager.has_method(&"apply_preset"))
	assert_true(GraphicsManager.has_method(&"reset_to_defaults"))
	assert_true(GraphicsManager.has_method(&"commit_full_pipeline"))

	var prev_killed: bool = GraphicsManager.is_diorama_killed
	GraphicsManager.set_diorama_killed(true)
	assert_true(GraphicsManager.is_diorama_killed)
	GraphicsManager.set_diorama_killed(prev_killed)


## Verifies [SaveManager] constants, signals, path validation, and state schema checks.
func test_save_manager_contracts() -> void:
	assert_true(SaveManager.has_signal(&"save_completed"))
	assert_eq(SaveManager.get(&"ENCRYPTION_KEY"), "bella_sec_v1_99238")
	assert_eq(SaveManager.get(&"ENCRYPTED_MAGIC"), 0x43455447)
	assert_eq(SaveManager.get(&"SAVES_DIR"), "user://saves/")
	assert_eq(SaveManager.get(&"THUMB_WIDTH"), 320)
	assert_eq(SaveManager.get(&"THUMB_HEIGHT"), 180)
	assert_eq(SaveManager.process_mode, Node.PROCESS_MODE_ALWAYS)

	assert_true(SaveManager.is_valid_level_path(""))
	assert_true(SaveManager.is_valid_level_path("res://levels/test.tscn"))
	assert_true(SaveManager.is_valid_level_path("res://test/vis_test.tscn"))
	assert_true(SaveManager.is_valid_level_path("res://player/settings_level.tscn"))
	assert_false(SaveManager.is_valid_level_path("res://levels/../evil.tscn"))
	assert_false(SaveManager.is_valid_level_path("user://evil.tscn"))
	assert_false(SaveManager.is_valid_level_path("res://levels/test.gd"))

	assert_false(SaveManager.validate_state_dictionary("invalid"))
	assert_false(SaveManager.validate_state_dictionary({"Main": {"hp": 10}}))
	assert_false(SaveManager.validate_state_dictionary({"/root/Main": "invalid"}))
	assert_true(SaveManager.validate_state_dictionary({"/root/Main": {"hp": 10}}))

	assert_eq(SaveManager.compute_file_sha256("res://w19_nonexistent.bin"), "")
	var project_hash: String = SaveManager.compute_file_sha256("res://project.godot")
	assert_eq(project_hash.length(), 64)

	assert_true(SaveManager.has_method(&"has_saves"))
	assert_true(SaveManager.has_method(&"create_save"))
	assert_true(SaveManager.has_method(&"get_all_saves"))
	assert_true(SaveManager.has_method(&"update_save_meta"))
	assert_true(SaveManager.has_method(&"load_save_game"))
	assert_true(SaveManager.has_method(&"load_game"))


## Verifies [SceneTransition] layer, signals, overlay rect, and transition entrypoint.
func test_scene_transition_contracts() -> void:
	assert_true(SceneTransition.has_signal(&"transition_halfway"))
	assert_true(SceneTransition.has_signal(&"transition_completed"))
	assert_true(SceneTransition.has_signal(&"loading_progress_updated"))
	assert_eq(SceneTransition.layer, 100)
	assert_eq(SceneTransition.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(SceneTransition.is_processing())
	assert_true(SceneTransition.get_node_or_null("TransitionOverlay") is ColorRect)
	assert_true(SceneTransition.has_method(&"change_scene_to_file"))


## Verifies [SpikeForensics] constants, signals, scope markers, and sample filtering.
func test_spike_forensics_contracts() -> void:
	assert_true(SpikeForensics.has_signal(&"spike_detected"))
	assert_eq(SpikeForensics.get(&"LOG_DIR"), "user://logs")
	assert_eq(SpikeForensics.get(&"LOG_PATH"), "user://logs/spike_forensics.jsonl")
	assert_eq(SpikeForensics.get(&"BACKUP_LOG_PATH"), "user://logs/spike_forensics.jsonl.bak")
	assert_eq(SpikeForensics.get(&"MAX_LOG_BYTES"), 5242880)
	assert_almost_eq(float(SpikeForensics.get(&"SPIKE_THRESHOLD_MS")), 20.0, 0.001)
	assert_almost_eq(float(SpikeForensics.get(&"HITCH_THRESHOLD_MS")), 33.333, 0.001)
	assert_almost_eq(float(SpikeForensics.get(&"FLUSH_INTERVAL_SEC")), 2.0, 0.001)
	assert_eq(SpikeForensics.get(&"MAX_RECENT_SPIKES"), 20)
	assert_eq(SpikeForensics.get(&"MAX_FRAME_NODES"), 24)
	assert_almost_eq(float(SpikeForensics.get(&"BYTES_PER_MB")), 1048576.0, 0.1)

	assert_eq(SpikeForensics.get_log_path(), "user://logs/spike_forensics.jsonl")
	SpikeForensics.begin_scope(&"wave19_scope")
	SpikeForensics.end_scope(&"wave19_scope")
	SpikeForensics.set_suppressed(true)
	SpikeForensics.set_suppressed(false)
	assert_eq(SpikeForensics.evaluate_frame_sample(5.0), {})
	assert_true(SpikeForensics.get_recent_spikes() is Array)


## Verifies [SmokeManager] constants, processing state, and safe empty-registry queries.
func test_smoke_manager_contracts() -> void:
	assert_almost_eq(float(SmokeManager.get(&"DEFAULT_BULLET_RADIUS")), 0.55, 0.001)
	assert_almost_eq(float(SmokeManager.get(&"MAX_HITSCAN_RADIUS")), 1.5, 0.001)
	assert_almost_eq(float(SmokeManager.get(&"LOS_OPTICAL_DEPTH_THRESHOLD")), 1.15, 0.001)
	assert_false(SmokeManager.is_processing())
	assert_false(SmokeManager.is_physics_processing())

	SmokeManager.register_zone(null)
	SmokeManager.unregister_zone(null)
	SmokeManager.register_cloud(null)
	SmokeManager.unregister_cloud(null)
	SmokeManager.add_bullet_hole(Vector3.ZERO, Vector3.FORWARD, 10.0)
	SmokeManager.process_bullet_trajectory(Vector3.ZERO, Vector3.FORWARD)
	SmokeManager.carve_segment(Vector3.ZERO, Vector3.FORWARD)
	SmokeManager.carve_explosion(Vector3.ZERO, 2.0)
	assert_false(SmokeManager.is_line_of_sight_obscured(Vector3.ZERO, Vector3.FORWARD))
	assert_true(SmokeManager.has_method(&"clear_all"))


## Verifies [HighContrastManager] stylebox configuration and active state flag.
func test_high_contrast_manager_contracts() -> void:
	var style_raw: Variant = HighContrastManager.get(&"high_contrast_style")
	assert_true(style_raw is StyleBoxFlat)
	if style_raw is StyleBoxFlat:
		var style: StyleBoxFlat = style_raw
		assert_eq(style.bg_color, Color(0.0, 0.0, 0.0, 1.0))
		assert_almost_eq(style.content_margin_left, 6.0, 0.001)
		assert_almost_eq(style.content_margin_right, 6.0, 0.001)
		assert_almost_eq(style.content_margin_top, 4.0, 0.001)
		assert_almost_eq(style.content_margin_bottom, 4.0, 0.001)
	assert_true(HighContrastManager.get(&"is_active") is bool)


## Verifies [InputHelper] icon base path, key name sanitization, and missing action fallback.
func test_input_helper_contracts() -> void:
	assert_eq(
		InputHelper.get(&"ICON_BASE_PATH"),
		"res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"
	)
	assert_eq(InputHelper.sanitize_key_name("W (Physical)"), "W")
	assert_eq(InputHelper.sanitize_key_name("Left Mouse Button"), "LMB")
	assert_eq(InputHelper.sanitize_key_name("Right Mouse Button"), "RMB")
	assert_eq(InputHelper.sanitize_key_name("Middle Mouse Button"), "MMB")
	assert_eq(InputHelper.get_action_key_label(&"w19_nonexistent_action"), "???")
	assert_true(InputHelper.has_method(&"get_event_icon"))


## Verifies [VisionAssistManager] color palette, shader code, groups, and null-safe helpers.
func test_vision_assist_manager_contracts() -> void:
	var palette_raw: Variant = VisionAssistManager.get(&"COLOR_PALETTE")
	assert_true(palette_raw is Dictionary)
	if palette_raw is Dictionary:
		var palette: Dictionary = palette_raw
		assert_eq(palette.size(), 8)
		assert_true(palette.has("cyan"))
		assert_true(palette.has("red"))

	var shader_code_raw: Variant = VisionAssistManager.get(&"OVERLAY_SHADER_CODE")
	assert_true(shader_code_raw is String)
	assert_false(str(shader_code_raw).is_empty())

	var groups_raw: Variant = VisionAssistManager.get(&"group_colors")
	assert_true(groups_raw is Dictionary)
	if groups_raw is Dictionary:
		var groups: Dictionary = groups_raw
		assert_true(groups.has("friends"))
		assert_true(groups.has("enemies"))
		assert_true(groups.has("interactables"))
		assert_true(groups.has("traversal"))
		assert_true(groups.has("clues"))
		assert_true(groups.has("cover"))

	assert_true(VisionAssistManager.get(&"is_active") is bool)
	assert_true(VisionAssistManager.get(&"diorama_preview_active") is bool)
	assert_true(VisionAssistManager.get(&"current_mode") is String)

	VisionAssistManager.set_diorama_overlays_active(null, false)
	VisionAssistManager.apply_diorama_overlays(null)


## Verifies [DebugManager] autoload presence and wireframe toggle handling.
func test_debug_manager_contracts() -> void:
	assert_true(is_instance_valid(DebugManager))
	assert_true(DebugManager.has_method(&"_on_events_wireframe_toggled"))
	var vp: Viewport = DebugManager.get_viewport()
	assert_not_null(vp)
	var prev_draw: Viewport.DebugDraw = vp.debug_draw
	if OS.is_debug_build():
		DebugManager.call(&"_on_events_wireframe_toggled", true)
		assert_eq(vp.debug_draw, Viewport.DEBUG_DRAW_WIREFRAME)
		DebugManager.call(&"_on_events_wireframe_toggled", false)
		assert_eq(vp.debug_draw, prev_draw)


## Verifies [InGameConsole] state, registry wiring, keybind helpers, and toggle options.
func test_in_game_console_contracts() -> void:
	assert_eq(InGameConsole.layer, 128)
	assert_eq(InGameConsole.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_false(InGameConsole.visible)
	assert_true(InGameConsole.is_ui_ready)
	assert_true(InGameConsole.registry is ConsoleCommandRegistry)
	assert_true(InGameConsole.history is ConsoleHistory)
	assert_true(InGameConsole.context is ConsoleContext)
	assert_true(InGameConsole.system_commands is ConsoleSystemCommands)
	assert_true(InGameConsole.cheat_commands is ConsoleCheatCommands)
	assert_true(InGameConsole.settings_commands is ConsoleSettingsCommands)
	assert_true(InGameConsole.registry.has_command("help"))
	assert_eq(InGameConsole.call(&"_get_toggle_options"), ["on", "off", "1", "0"])

	var keybinds_copy: Dictionary[String, String] = InGameConsole.get_keybinds()
	assert_true(keybinds_copy is Dictionary)
	assert_true(InGameConsole.has_method(&"write"))
	assert_true(InGameConsole.has_method(&"log_info"))
	assert_true(InGameConsole.has_method(&"log_warn"))
	assert_true(InGameConsole.has_method(&"log_error"))
	assert_true(InGameConsole.has_method(&"bind_key"))
	assert_true(InGameConsole.has_method(&"unbind_key"))
	assert_true(InGameConsole.has_method(&"unbind_all_keys"))
	assert_true(InGameConsole.has_method(&"execute_command_string"))


## Verifies [SubtitleLayer] constants, layer configuration, and safe show/hide calls.
func test_subtitle_layer_contracts() -> void:
	assert_almost_eq(float(SubtitleLayer.get(&"READING_GRACE_PERIOD")), 3.0, 0.001)
	assert_almost_eq(float(SubtitleLayer.get(&"DEFAULT_CPS")), 25.0, 0.001)
	assert_almost_eq(float(SubtitleLayer.get(&"FADE_DURATION")), 0.2, 0.001)
	assert_eq(SubtitleLayer.get(&"SUBTITLE_LAYER_INDEX"), 125)
	assert_eq(SubtitleLayer.layer, 125)
	assert_eq(SubtitleLayer.process_mode, Node.PROCESS_MODE_ALWAYS)

	var prev_enabled: bool = SubtitleLayer.is_subtitles_enabled
	SubtitleLayer.is_subtitles_enabled = false
	SubtitleLayer.show_subtitle("Wave19", "Test line", 0.5)
	SubtitleLayer.hide_subtitle()
	SubtitleLayer.is_subtitles_enabled = prev_enabled


## Verifies [PostProcessLayer] layer, overlay rects, shaders, and toggle methods.
func test_post_process_layer_contracts() -> void:
	assert_eq(PostProcessLayer.layer, 127)
	assert_eq(PostProcessLayer.process_mode, Node.PROCESS_MODE_ALWAYS)
	assert_true(PostProcessLayer.colorblind_rect is ColorRect)
	assert_true(PostProcessLayer.high_contrast_rect is ColorRect)
	assert_true(PostProcessLayer.screen_filter_rect is ColorRect)
	assert_true(PostProcessLayer.colorblind_rect.material is ShaderMaterial)
	assert_false(PostProcessLayer.high_contrast_rect.visible)
	assert_false(PostProcessLayer.screen_filter_rect.visible)

	PostProcessLayer.set_high_contrast(true)
	assert_true(PostProcessLayer.high_contrast_rect.visible)
	PostProcessLayer.set_high_contrast(false)
	assert_false(PostProcessLayer.high_contrast_rect.visible)

	PostProcessLayer.set_colorblind_mode(0)
	PostProcessLayer.set_screen_filter("off")
	assert_false(PostProcessLayer.screen_filter_rect.visible)
	PostProcessLayer.set_film_grain(0.0)


## Verifies [ShockwaveManager] pool constant and safe shockwave trigger.
func test_shockwave_manager_contracts() -> void:
	assert_eq(ShockwaveManager.get(&"POOL_SIZE"), 6)
	assert_true(ShockwaveManager.has_method(&"trigger_shockwave"))
	ShockwaveManager.trigger_shockwave(Vector3.ZERO, 5.0, 2.0)


## Verifies [BloodManager] constants, shaders, processing state, and pre-warmed pool nodes.
func test_blood_manager_contracts() -> void:
	assert_true(BloodManager.get(&"SPRAY_SHADER") is Shader)
	assert_true(BloodManager.get(&"MIST_SHADER") is Shader)
	assert_eq(BloodManager.get(&"PROP_MODULATE_ALPHA"), ^"modulate:a")
	assert_eq(BloodManager.get(&"HIT_POOL_SIZE"), 32)
	assert_eq(BloodManager.get(&"DEATH_POOL_SIZE"), 10)
	assert_eq(BloodManager.get(&"DECAL_POOL_SIZE"), 40)
	assert_eq(BloodManager.get(&"SPLATTER_VARIATIONS"), 4)
	assert_eq(BloodManager.get(&"TEX_SIZE"), 128)
	assert_eq(BloodManager.get(&"ENV_COLLISION_MASK"), 1)
	assert_eq(BloodManager.get(&"ENV_RENDER_LAYER"), 1)
	assert_almost_eq(float(BloodManager.get(&"CAPSULE_SURFACE_OFFSET")), 0.58, 0.001)
	assert_almost_eq(float(BloodManager.get(&"DECAL_FADE_DURATION")), 8.0, 0.001)
	assert_false(BloodManager.is_processing())
	assert_false(BloodManager.is_physics_processing())
	assert_gte(BloodManager.get_child_count(), 82)


## Verifies [ImpactManager] constants, processing state, and pre-warmed decal pool.
func test_impact_manager_contracts() -> void:
	assert_eq(ImpactManager.get(&"POOL_SIZE"), 64)
	assert_eq(ImpactManager.get(&"VARIANT_COUNT"), 4)
	assert_eq(ImpactManager.get(&"TEX_SIZE"), 64)
	assert_almost_eq(float(ImpactManager.get(&"PROJECTION_DEPTH")), 0.1, 0.001)
	assert_almost_eq(float(ImpactManager.get(&"NORMAL_FADE")), 0.5, 0.001)
	assert_almost_eq(float(ImpactManager.get(&"HOLE_SIZE_MIN")), 0.08, 0.001)
	assert_almost_eq(float(ImpactManager.get(&"HOLE_SIZE_MAX")), 0.12, 0.001)
	assert_almost_eq(float(ImpactManager.get(&"FADE_BEGIN")), 25.0, 0.001)
	assert_almost_eq(float(ImpactManager.get(&"FADE_LENGTH")), 5.0, 0.001)
	assert_false(ImpactManager.is_processing())
	assert_false(ImpactManager.is_physics_processing())
	assert_eq(ImpactManager.get_child_count(), 64)
