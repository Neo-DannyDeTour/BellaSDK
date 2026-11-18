## Characterization tests locking Wave 13 public APIs, constants, signals, and behavior.
class_name TestWave13Characterization
extends GutTest

const AUDIO_PANEL_SCENE: PackedScene = preload("res://ui/audio_panel.tscn")
const GAMEPLAY_PANEL_SCENE: PackedScene = preload("res://ui/GameplayPanel.tscn")
const MAGNIFYING_GLASS_SCENE: PackedScene = preload("res://ui/magnifying_glass_ui.tscn")
const SAVE_LOAD_PANEL_SCENE: PackedScene = preload("res://ui/save_load_panel.tscn")
const VIDEO_OPTIONS_SCENE: PackedScene = preload("res://ui/video_options_panel.tscn")
const SAVE_LOAD_PANEL_SCRIPT: Script = preload("res://ui/save_load_panel.gd")

var _saved_locale: String = ""


## Captures active locale before each test.
func before_each() -> void:
	_saved_locale = TranslationServer.get_locale()


## Restores active locale after each test.
func after_each() -> void:
	if not _saved_locale.is_empty():
		TranslationServer.set_locale(_saved_locale)


## Verifies [AmmoHUD] initial state, signal-driven visibility, and infinite ammo toggle.
func test_ammo_hud_contracts() -> void:
	var hud: AmmoHUD = AmmoHUD.new()
	add_child_autofree(hud)

	assert_false(hud.visible)
	hud._on_weapon_ammo_changed(12, 36, 12)
	assert_true(hud.visible)
	assert_eq(hud._cached_reserve, 36)

	hud.hide()
	hud._on_active_weapon_changed("revolver")
	assert_true(hud.visible)

	hud._on_infinite_ammo_toggled(true)
	assert_true(hud.is_infinite_ammo)
	hud._on_infinite_ammo_toggled(false)
	assert_false(hud.is_infinite_ammo)


## Verifies [AudioPanel] constants, output profile dropdowns, and config section helper.
func test_audio_panel_contracts() -> void:
	assert_eq(AudioPanel.DEFAULT_VOLUME, 100.0)
	assert_eq(AudioPanel.DB_CHANGE_EPSILON, 0.05)

	var panel: AudioPanel = AUDIO_PANEL_SCENE.instantiate() as AudioPanel
	assert_not_null(panel)
	add_child_autofree(panel)

	assert_eq(panel.section_name("Master"), "Audio")
	assert_eq(panel.section_name("SFX"), "Audio")
	if is_instance_valid(panel.output_profile_option):
		assert_eq(panel.output_profile_option.get_item_count(), 3)


## Verifies [ChapterDisplay] shader constants, material cache, and viewport sleep state.
func test_chapter_display_contracts() -> void:
	assert_not_null(ChapterDisplay.SHADER_GLITCH)
	assert_not_null(ChapterDisplay.SHADER_BLUR)
	assert_eq(ChapterDisplay.SHADER_ANIM_STYLES.size(), 11)

	var display: ChapterDisplay = ChapterDisplay.new()
	assert_not_null(display)
	var effect_container: SubViewportContainer = SubViewportContainer.new()
	effect_container.name = "EffectContainer"
	var sub_viewport: SubViewport = SubViewport.new()
	sub_viewport.name = "ChapterLabelSubViewport"
	var label: RichTextLabel = RichTextLabel.new()
	label.name = "ChapterLabel"
	sub_viewport.add_child(label)
	effect_container.add_child(sub_viewport)
	display.add_child(effect_container)
	add_child_autofree(display)

	assert_eq(display.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(effect_container.visible)
	assert_false(label.visible)
	assert_eq(sub_viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)


## Verifies [CrosshairHUD] constants, initial reticle state, zoom, and terminal mode.
func test_crosshair_hud_contracts() -> void:
	assert_eq(CrosshairHUD.PARAM_TARGET_TINT, &"shader_parameter/target_tint_weight")

	var hud: CrosshairHUD = CrosshairHUD.new()
	var dot: TextureRect = TextureRect.new()
	dot.name = "CenterDot"
	dot.custom_minimum_size = Vector2(4.0, 4.0)
	var zoom_outer: TextureRect = TextureRect.new()
	zoom_outer.name = "UICircleZoom"
	var zoom_inner: TextureRect = TextureRect.new()
	zoom_inner.name = "UICircleZoomInner"
	hud.add_child(dot)
	hud.add_child(zoom_outer)
	hud.add_child(zoom_inner)
	add_child_autofree(hud)

	assert_false(hud.is_processing())
	assert_false(zoom_outer.visible)
	assert_false(zoom_inner.visible)
	assert_eq(hud.default_crosshair_size, Vector2(4.0, 4.0))

	hud._on_player_zoomed(true)
	assert_false(dot.visible)
	assert_true(zoom_outer.visible)
	assert_true(zoom_inner.visible)

	hud._on_terminal_mode_toggled(true)
	assert_not_null(hud.crosshair_tween)


## Verifies [DebugOverlay] initial flags, button labels, and noclip/fullbright handlers.
func test_debug_overlay_contracts() -> void:
	var overlay: DebugOverlay = DebugOverlay.new()
	var noclip_margin: MarginContainer = MarginContainer.new()
	noclip_margin.name = "NoclipAlertContainer"
	var noclip_panel: PanelContainer = PanelContainer.new()
	noclip_panel.name = "NoclipMessageContainer"
	var noclip_label: Label = Label.new()
	noclip_label.name = "NoclipLabelMessage"
	noclip_panel.add_child(noclip_label)
	noclip_margin.add_child(noclip_panel)
	overlay.add_child(noclip_margin)

	var debug_root: Control = Control.new()
	debug_root.name = "DebugPanel"
	var debug_panel: PanelContainer = PanelContainer.new()
	debug_panel.name = "PanelContainer"
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	var unique_btns: Array[Button] = []
	for btn_name: String in [
		"NoclipButton",
		"MetricsButton",
		"CollisionButton",
		"FullbrightButton",
		"WireframeButton",
		"WireframeOverlayButton",
		"HideUIButton",
		"RenderDiagnosticButton",
	]:
		var btn: Button = Button.new()
		btn.name = btn_name
		vbox.add_child(btn)
		if btn_name in ["WireframeOverlayButton", "RenderDiagnosticButton"]:
			unique_btns.append(btn)
	debug_panel.add_child(vbox)
	debug_root.add_child(debug_panel)
	overlay.add_child(debug_root)
	for btn: Button in unique_btns:
		btn.owner = overlay
		btn.unique_name_in_owner = true
	add_child_autofree(overlay)

	assert_false(overlay.is_fullbright)
	assert_false(overlay.is_wireframe)
	assert_false(overlay.is_wireframe_overlay)
	assert_false(overlay.is_collision_visible)
	assert_true(is_instance_valid(overlay.green_wireframe_material))
	assert_eq(overlay.noclip_button.text, "Noclip OFF")
	assert_eq(overlay.fullbright_button.text, "Fullbright OFF")

	overlay._on_noclip_toggled(true)
	assert_true(noclip_panel.visible)
	assert_eq(overlay.noclip_button.text, "Noclip ON")
	overlay._on_noclip_speed_changed(2.5)
	assert_eq(noclip_label.text, "Noclip ON: 2.5x speed")

	overlay._on_fullbright_button_pressed()
	assert_true(overlay.is_fullbright)
	assert_eq(overlay.fullbright_button.text, "Fullbright ON")


## Verifies [RenderDiagnosticsPanel] constants and public method surface.
func test_diagnostics_panel_contracts() -> void:
	assert_eq(RenderDiagnosticsPanel.UPDATE_INTERVAL, 0.25)
	assert_almost_eq(RenderDiagnosticsPanel.TARGET_FRAME_BUDGET_MS, 16.666, 0.001)
	assert_eq(RenderDiagnosticsPanel.CPU_OVERLOAD_THRESHOLD_MS, 18.0)
	assert_eq(RenderDiagnosticsPanel.OFFENDER_THRESHOLD_MS, 0.5)
	assert_eq(RenderDiagnosticsPanel.MAX_HITCH_RECORDS, 5)
	assert_eq(RenderDiagnosticsPanel.LOG_READ_WINDOW_BYTES, 16384)
	assert_eq(RenderDiagnosticsPanel.GROUP_SUNSHINE_CLOUDS, &"sunshine_clouds")
	assert_eq(RenderDiagnosticsPanel.GROUP_SCREEN_EFFECTS, &"screen_effects_manager")
	assert_eq(RenderDiagnosticsPanel.UPDATE_MODE_LABELS.size(), 5)
	assert_gt(RenderDiagnosticsPanel.BUTTON_HOVER_DOCS.size(), 0)

	var panel: RenderDiagnosticsPanel = RenderDiagnosticsPanel.new()
	assert_not_null(panel)
	autofree(panel)
	assert_true(panel.has_method(&"toggle_window"))
	assert_true(panel.has_method(&"scan_scene_geometry"))
	assert_true(panel.has_method(&"scan_orphan_nodes"))
	assert_true(panel.has_method(&"sync_toggle_button_labels"))
	assert_true(panel.has_method(&"cycle_debug_draw_mode"))


## Verifies [DioramaPostProcess] overlay setup and shader parameter updates.
func test_diorama_post_process_contracts() -> void:
	var post: DioramaPostProcess = DioramaPostProcess.new()
	var mat: ShaderMaterial = ShaderMaterial.new()
	post.material = mat
	add_child_autofree(post)

	assert_eq(post.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	post._on_film_grain_changed(0.35)
	assert_almost_eq(float(mat.get_shader_parameter(&"grain_amount")), 0.35, 0.001)
	post._on_screen_filter_changed("none")
	assert_true(mat.get_shader_parameter(&"filter_mode") is int)


## Verifies [DisplaySection] and [HardwareSection] inside the video options panel scene.
func test_display_and_hardware_section_contracts() -> void:
	var panel: Control = VIDEO_OPTIONS_SCENE.instantiate() as Control
	assert_not_null(panel)
	add_child_autofree(panel)

	var display_sec: DisplaySection = panel.find_child("*", true, false) as DisplaySection
	for child: Node in panel.find_children("*", "DisplaySection", true, false):
		display_sec = child as DisplaySection
		break
	assert_not_null(display_sec)
	assert_has_signal(display_sec, &"display_settings_changed")
	assert_false(display_sec.is_processing())
	assert_false(display_sec.is_physics_processing())
	assert_eq(display_sec._parse_resolution_label("1920 x 1080"), Vector2i(1920, 1080))
	assert_eq(display_sec._parse_resolution_label("1280 x 720"), Vector2i(1280, 720))

	var hw_sec: HardwareSection = null
	for child: Node in panel.find_children("*", "HardwareSection", true, false):
		hw_sec = child as HardwareSection
		break
	assert_not_null(hw_sec)
	assert_has_signal(hw_sec, &"restart_required")
	assert_false(hw_sec.is_processing())
	assert_false(hw_sec.is_physics_processing())
	assert_gt(hw_sec.gpu_options.get_item_count(), 0)


## Verifies [AccessibilityDisplayUISection] constants and standalone safe methods.
func test_display_ui_section_contracts() -> void:
	assert_eq(AccessibilityDisplayUISection.BASE_FONT_SIZES.size(), 6)
	assert_eq(AccessibilityDisplayUISection.DEFAULT_FOV, 75.0)
	assert_false(AccessibilityDisplayUISection.DEFAULT_DISABLE_SPRINT_FOV)
	assert_eq(AccessibilityDisplayUISection.DEFAULT_UI_SCALE, 1.0)
	assert_eq(AccessibilityDisplayUISection.DEFAULT_FONT_MODE, 0)
	assert_eq(AccessibilityDisplayUISection.DEFAULT_FONT_SCALE, 1.0)

	var section: AccessibilityDisplayUISection = AccessibilityDisplayUISection.new()
	add_child_autofree(section)
	section.load_settings()
	section.apply_current_fov_to_preview()
	section.apply_font_scale_to_theme(1.0)


## Verifies [GameplayPanel] locale list and language application.
func test_gameplay_panel_contracts() -> void:
	var expected_locales: Array[String] = ["en", "es", "ru"]
	assert_eq(GameplayPanel.SUPPORTED_LOCALES, expected_locales)

	var panel: GameplayPanel = GAMEPLAY_PANEL_SCENE.instantiate() as GameplayPanel
	assert_not_null(panel)
	add_child_autofree(panel)
	panel._apply_language(1)
	assert_eq(TranslationServer.get_locale(), "es")
	panel._apply_language(0)
	assert_eq(TranslationServer.get_locale(), "en")


## Verifies [GelStream3D] material initialization, clamping, and particle amount scaling.
func test_gel_stream_3d_contracts() -> void:
	var gel: GelStream3D = GelStream3D.new()
	add_child_autofree(gel)

	assert_true(gel.trail_enabled)
	assert_true(gel.process_material is ParticleProcessMaterial)
	assert_true(gel.draw_pass_1 is TubeTrailMesh)

	gel.stream_unity = 1.0
	assert_eq(gel.amount, 60)
	gel.drop_scale = 0.0
	assert_almost_eq(gel.drop_scale, 0.01, 0.0001)
	gel.drop_length = -1.0
	assert_almost_eq(gel.drop_length, 0.01, 0.0001)


## Verifies [MagnifyingGlassUI] exports, note gating, and zoom clamping.
func test_magnifying_glass_ui_contracts() -> void:
	var glass: MagnifyingGlassUI = MAGNIFYING_GLASS_SCENE.instantiate() as MagnifyingGlassUI
	assert_not_null(glass)
	add_child_autofree(glass)

	assert_eq(glass.min_zoom, 1.5)
	assert_eq(glass.max_zoom, 5.0)
	assert_eq(glass.zoom_step, 0.5)
	assert_eq(glass.min_radius, 0.1)
	assert_eq(glass.max_radius, 0.4)
	assert_eq(glass.radius_step, 0.05)
	assert_false(glass.glass_rect.visible)

	glass._on_note_opened("Test note")
	glass._toggle_glass()
	assert_true(glass.glass_rect.visible)
	glass._adjust_glass(100.0)
	assert_eq(glass._current_zoom, glass.max_zoom)
	assert_eq(glass._current_radius, glass.max_radius)
	glass._on_note_closed()
	assert_false(glass.glass_rect.visible)


## Verifies [NotificationHUD] constants, exports, claw mark setup, and warning messages.
func test_notification_hud_contracts() -> void:
	assert_not_null(NotificationHUD.CLAW_ATTACK_TEXTURE)
	assert_not_null(NotificationHUD.CLAW_FIRE_SHADER)

	var hud: NotificationHUD = NotificationHUD.new()
	var warning_container: Control = Control.new()
	warning_container.name = "WarningContainer"
	var warning_label: Label = Label.new()
	warning_label.name = "WarningLabel"
	warning_container.add_child(warning_label)
	hud.add_child(warning_container)
	var note_layer: CanvasLayer = CanvasLayer.new()
	note_layer.name = "NoteOverlayUI"
	var note_text: RichTextLabel = RichTextLabel.new()
	note_text.name = "NoteText"
	note_layer.add_child(note_text)
	hud.add_child(note_layer)
	var vault_container: Control = Control.new()
	vault_container.name = "VaultPromptContainer"
	var vault_icon: TextureRect = TextureRect.new()
	vault_icon.name = "VaultKeyIcon"
	vault_container.add_child(vault_icon)
	hud.add_child(vault_container)
	add_child_autofree(hud)

	assert_eq(hud.prompt_size, Vector2(64.0, 64.0))
	assert_eq(hud.center_dot_offset_y, 40.0)
	assert_eq(hud.claw_mark_size, Vector2(128.0, 128.0))
	assert_true(is_instance_valid(hud.claw_mark_container))
	assert_true(is_instance_valid(hud.claw_mark_icon))

	hud.show_warning_message("Alert!", 0.25)
	assert_eq(warning_label.text, "Alert!")


## Verifies save/load panel constants, template hiding, and filename validation.
func test_save_load_panel_contracts() -> void:
	assert_eq(SAVE_LOAD_PANEL_SCRIPT.SAVES_DIR, "user://saves/")

	var panel: Panel = SAVE_LOAD_PANEL_SCENE.instantiate() as Panel
	assert_not_null(panel)
	add_child_autofree(panel)

	var template: Control = panel.get_node_or_null("%SaveSlotTemplate") as Control
	assert_not_null(template)
	assert_false(template.visible)
	assert_true(bool(panel.call(&"_is_valid_save_filename", "slot_01.save")))
	assert_false(bool(panel.call(&"_is_valid_save_filename", "../hack.save")))
	assert_false(bool(panel.call(&"_is_valid_save_filename", "slot_01.txt")))


## Verifies [AccessibilitySubsAudioSection] constants and external sync helpers.
func test_subs_audio_section_contracts() -> void:
	assert_eq(AccessibilitySubsAudioSection.COLOR_NAMES.size(), 8)
	assert_eq(AccessibilitySubsAudioSection.DEFAULT_SUB_SIZE, 24.0)
	assert_eq(AccessibilitySubsAudioSection.DEFAULT_SUB_BG_OPACITY, 50.0)
	assert_eq(AccessibilitySubsAudioSection.DEFAULT_SUB_COLOR_INDEX, 6)
	assert_eq(AccessibilitySubsAudioSection.DEFAULT_SUB_BG_COLOR_INDEX, 7)
	assert_eq(AccessibilitySubsAudioSection.DEFAULT_SUB_SPEAKER_COLOR_INDEX, 0)
	assert_true(AccessibilitySubsAudioSection.DEFAULT_SUB_COLORS)
	assert_true(AccessibilitySubsAudioSection.DEFAULT_SUB_SHOW_NAMES)
	assert_true(AccessibilitySubsAudioSection.DEFAULT_SUBTITLES_ENABLED)
	assert_false(AccessibilitySubsAudioSection.DEFAULT_TTS_ENABLED)
	assert_false(AccessibilitySubsAudioSection.DEFAULT_MONO_AUDIO)

	var section: AccessibilitySubsAudioSection = AccessibilitySubsAudioSection.new()
	add_child_autofree(section)
	section.load_settings()
	section.sync_external_subtitles_enabled(false)
	section.sync_external_subtitle_size(30.0)
	section.sync_external_subtitle_opacity(0.8)


## Verifies [AccessibilityVisionSection] constants and diorama helper methods.
func test_vision_section_contracts() -> void:
	assert_eq(AccessibilityVisionSection.COLOR_NAMES.size(), 8)
	assert_eq(AccessibilityVisionSection.VISION_MODES.size(), 5)
	assert_eq(AccessibilityVisionSection.VISION_MODE_KEYS.size(), 5)
	assert_false(AccessibilityVisionSection.DEFAULT_VISION_ASSIST)
	assert_eq(AccessibilityVisionSection.DEFAULT_VISION_ASSIST_MODE, 1)

	var section: AccessibilityVisionSection = AccessibilityVisionSection.new()
	add_child_autofree(section)
	section.load_settings()
	section.sync_external_vision_assist(true)
	section.invalidate_camera_cache()
	section.cache_diorama_cameras()
	section.set_preview_effects_active(false)


## Verifies [WaterWipeController] constants, surfacing wipe, waterfall clamp, and stop_immediate.
func test_water_wipe_controller_contracts() -> void:
	assert_not_null(WaterWipeController.WATER_WIPE_SHADER)
	assert_eq(WaterWipeController.PARAM_WIPE_PROGRESS, &"wipe_progress")
	assert_eq(WaterWipeController.PARAM_WASH_INTENSITY, &"wash_intensity")
	assert_eq(WaterWipeController.PARAM_VISIBILITY, &"visibility")
	assert_eq(WaterWipeController.DEFAULT_WIPE_DURATION, 1.4)
	assert_eq(WaterWipeController.WIPE_WASH_INTENSITY, 0.3)
	assert_eq(WaterWipeController.MAX_WATERFALL_INTENSITY, 0.4)

	var controller: WaterWipeController = WaterWipeController.new()
	add_child_autofree(controller)

	assert_false(controller.is_processing())
	assert_false(controller.is_physics_processing())
	assert_false(controller.visible)
	assert_eq(controller.mouse_filter, Control.MOUSE_FILTER_IGNORE)

	controller.start_waterfall_wash(1.0)
	assert_true(controller.visible)
	var mat: ShaderMaterial = controller.material as ShaderMaterial
	assert_not_null(mat)
	assert_almost_eq(
		float(mat.get_shader_parameter(WaterWipeController.PARAM_WASH_INTENSITY)), 0.4, 0.001
	)

	controller.start_surfacing_wipe(0.5)
	assert_true(controller.visible)

	controller.stop_immediate()
	assert_false(controller.visible)
	assert_almost_eq(
		float(mat.get_shader_parameter(WaterWipeController.PARAM_WIPE_PROGRESS)), 1.5, 0.001
	)
	assert_almost_eq(
		float(mat.get_shader_parameter(WaterWipeController.PARAM_VISIBILITY)), 0.0, 0.001
	)


## Verifies [ChunkRoot] constants, coord calculation, roaming metadata, deltas, and mutation.
func test_chunk_root_contracts() -> void:
	assert_eq(ChunkRoot.CHUNK_SIZE, 50.0)
	assert_eq(ChunkRoot.DELTA_FREED, &"freed")
	assert_eq(ChunkRoot.GROUP_ROAMING, &"roaming")
	assert_eq(ChunkRoot.META_ORIGIN_CHUNK, &"origin_chunk")
	assert_eq(ChunkRoot.META_ENTITY_ID, &"entity_id")
	assert_eq(ChunkRoot.METHOD_ENTITY_DELTA, &"apply_delta")

	var chunk: ChunkRoot = ChunkRoot.new()
	chunk.position = Vector3(100.0, 0.0, -50.0)

	var mover: Node3D = Node3D.new()
	mover.name = "Mover"
	mover.unique_name_in_owner = true
	mover.add_to_group(ChunkRoot.GROUP_ROAMING)
	chunk.add_child(mover)
	mover.owner = chunk

	var doomed: Node3D = Node3D.new()
	doomed.name = "Doomed"
	doomed.unique_name_in_owner = true
	chunk.add_child(doomed)
	doomed.owner = chunk

	add_child_autofree(chunk)

	assert_false(chunk.is_processing())
	assert_false(chunk.is_physics_processing())
	assert_eq(chunk.chunk_coord, Vector2i(2, -1))
	assert_eq(mover.get_meta(ChunkRoot.META_ORIGIN_CHUNK), Vector2i(2, -1))
	assert_eq(mover.get_meta(ChunkRoot.META_ENTITY_ID), &"Mover")

	var moved_xform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(3.0, 4.0, 5.0))
	chunk.apply_chunk_deltas({&"Mover": moved_xform, &"Doomed": ChunkRoot.DELTA_FREED})
	assert_eq(mover.transform, moved_xform)
	assert_false(is_instance_valid(doomed))

	watch_signals(Events)
	chunk.report_entity_mutation(mover, {"hp": 5})
	assert_signal_emitted_with_parameters(
		Events, &"chunk_entity_mutated", [Vector2i(2, -1), &"Mover", {"hp": 5}]
	)
