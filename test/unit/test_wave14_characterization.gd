## Characterization tests locking Wave 14 public APIs, constants, signals, and behavior.
class_name TestWave14Characterization
extends GutTest

const ADVISOR_EFFECT_SCRIPT: GDScript = preload("res://ui/advisor_psychic_effect.gd")
const HARSH_CONTRAST_SCRIPT: GDScript = preload("res://ui/harsh_contrast_effect.gd")
const ROAR_EFFECT_SCRIPT: GDScript = preload("res://ui/roar_screen_effect.gd")

const ACCESSIBILITY_PANEL_SCENE: PackedScene = preload("res://ui/accessibility_panel.tscn")
const CONTROLS_PANEL_SCENE: PackedScene = preload("res://ui/controls_panel.tscn")
const DEATH_SCREEN_SCENE: PackedScene = preload("res://ui/death_screen.tscn")
const HORROR_BUTTON_SCENE: PackedScene = preload("res://ui/HorrorButton.tscn")
const UI_SCENE: PackedScene = preload("res://ui/ui.tscn")


## Verifies [AdvisorPsychicEffect] constants, shader setup, sustained intensity, and pulse.
func test_advisor_psychic_effect_contracts() -> void:
	var effect: ColorRect = ADVISOR_EFFECT_SCRIPT.new() as ColorRect
	assert_not_null(effect)
	add_child_autofree(effect)

	assert_eq(effect.get("PARAM_INTENSITY"), &"intensity")
	assert_eq(effect.get("PARAM_CENTER_UV"), &"center_uv")
	assert_eq(effect.get("DEFAULT_CENTER"), Vector2(0.5, 0.5))
	assert_true(effect.has_signal(&"pulse_finished"))
	assert_eq(effect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(effect.visible)
	assert_false(effect.is_processing())
	assert_true(effect.material is ShaderMaterial)

	effect.call("set_sustained_intensity", 0.6)
	assert_true(effect.visible)
	var mat: ShaderMaterial = effect.material as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter(&"intensity")), 0.6, 0.001)

	effect.call("set_sustained_intensity", 0.0)
	assert_false(effect.visible)

	effect.call("set_intensity_from_distance", Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 20.0)
	assert_true(effect.visible)
	assert_almost_eq(float(mat.get_shader_parameter(&"intensity")), 0.75, 0.001)

	effect.call("trigger_psychic_pulse", 0.5, 0.9)
	assert_true(effect.visible)


## Verifies [HarshContrastEffect] constants, shader setup, sustained intensity, and pulse.
func test_harsh_contrast_effect_contracts() -> void:
	var effect: ColorRect = HARSH_CONTRAST_SCRIPT.new() as ColorRect
	assert_not_null(effect)
	add_child_autofree(effect)

	assert_eq(effect.get("PARAM_INTENSITY"), &"intensity")
	assert_eq(effect.get("PARAM_THRESHOLD"), &"threshold")
	assert_eq(effect.get("PARAM_SOFTNESS"), &"softness")
	assert_eq(effect.get("PARAM_JITTER"), &"jitter_strength")
	assert_eq(effect.get("PARAM_FLASH_BOOST"), &"flash_boost")
	assert_true(effect.has_signal(&"pulse_finished"))
	assert_eq(effect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(effect.visible)
	assert_false(effect.is_processing())
	assert_true(effect.material is ShaderMaterial)

	effect.call("set_sustained_intensity", 0.75, 0.35)
	assert_true(effect.visible)
	var mat: ShaderMaterial = effect.material as ShaderMaterial
	assert_almost_eq(float(mat.get_shader_parameter(&"intensity")), 0.75, 0.001)
	assert_almost_eq(float(mat.get_shader_parameter(&"threshold")), 0.35, 0.001)

	effect.call("set_sustained_intensity", 0.0)
	assert_false(effect.visible)

	effect.call("trigger_contrast_pulse", 0.4, 0.8, 0.3)
	assert_true(effect.visible)


## Verifies [RoarScreenEffect] constants, shader requirement, and roar activation.
func test_roar_screen_effect_contracts() -> void:
	var effect: ColorRect = ROAR_EFFECT_SCRIPT.new() as ColorRect
	assert_not_null(effect)
	var shader_mat: ShaderMaterial = ShaderMaterial.new()
	effect.material = shader_mat
	add_child_autofree(effect)

	assert_eq(effect.get("PARAM_INTENSITY"), &"intensity")
	assert_almost_eq(float(effect.get("ATTACK_DURATION")), 0.1, 0.001)
	assert_almost_eq(float(effect.get("DECAY_DURATION")), 0.3, 0.001)
	assert_eq(effect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(effect.visible)
	assert_false(effect.is_processing())

	effect.call("_on_monster_roared", 0.5)
	assert_true(effect.visible)
	effect.call("_on_roar_finished")
	assert_false(effect.visible)


## Verifies [JuicyButton] exports, pivot setup, and hover processing gating.
func test_juicy_button_contracts() -> void:
	var btn: JuicyButton = JuicyButton.new()
	btn.size = Vector2(120.0, 40.0)
	add_child_autofree(btn)

	assert_eq(btn.hover_scale, Vector2(1.08, 1.08))
	assert_almost_eq(btn.max_rotation_degrees, 5.0, 0.001)
	assert_almost_eq(btn.tilt_stiffness, 240.0, 0.001)
	assert_almost_eq(btn.tilt_damping, 18.0, 0.001)
	assert_almost_eq(btn.scale_stiffness, 200.0, 0.001)
	assert_almost_eq(btn.scale_damping, 16.0, 0.001)
	assert_eq(btn.original_scale, Vector2.ONE)
	assert_false(btn.is_hovered)

	btn._on_hover()
	assert_true(btn.is_hovered)
	btn._on_unhover()
	assert_false(btn.is_hovered)


## Verifies [HorrorButton] scene instantiation, exports, sizing, and text/background setters.
func test_horror_button_contracts() -> void:
	var btn: HorrorButton = HORROR_BUTTON_SCENE.instantiate() as HorrorButton
	assert_not_null(btn)
	add_child_autofree(btn)

	assert_almost_eq(btn.corner_cut, 14.0, 0.001)
	assert_eq(btn.card_size, Vector2(240.0, 135.0))
	assert_almost_eq(btn.card_base_brightness, 0.85, 0.001)
	assert_almost_eq(btn.card_hover_brightness, 1.0, 0.001)
	assert_false(btn.is_processing())

	btn.custom_text = "PLAY"
	assert_eq(btn.custom_text, "PLAY")
	if is_instance_valid(btn.text_label):
		assert_eq(btn.text_label.text, "PLAY")

	btn.invisible_background = true
	assert_true(btn.invisible_background)
	if is_instance_valid(btn.bg_rect):
		assert_false(btn.bg_rect.visible)

	var min_size: Vector2 = btn._get_minimum_size()
	assert_true(min_size.x > 0.0 and min_size.y > 0.0)


## Verifies [TagNotification] constants, timer creation, and weapon collection stacking.
func test_tag_notification_contracts() -> void:
	assert_true(TagNotification.TAG_TEXTURES.has("shotgun"))
	assert_true(TagNotification.TAG_TEXTURES.has("revolver"))
	assert_true(TagNotification.TAG_TEXTURES.has("smoke_grenade"))
	assert_almost_eq(TagNotification.TAG_SPREAD_X, 48.0, 0.001)
	assert_almost_eq(TagNotification.ACTIVE_Y, 65.0, 0.001)
	assert_almost_eq(TagNotification.BACKGROUND_Y, 40.0, 0.001)
	assert_almost_eq(TagNotification.DISPLAY_DURATION, 2.5, 0.001)

	var hud: TagNotification = TagNotification.new()
	add_child_autofree(hud)

	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(hud.is_processing())
	assert_not_null(hud._dismiss_timer)

	hud._on_weapon_collected("shotgun")
	assert_true(hud._spawned_tags.has("shotgun"))
	assert_eq(hud._active_weapon, "shotgun")
	assert_eq(hud._collected_order.size(), 1)

	hud._on_weapon_collected("revolver")
	assert_true(hud._spawned_tags.has("revolver"))
	assert_eq(hud._active_weapon, "revolver")
	assert_eq(hud._collected_order.size(), 2)

	hud._on_weapon_swapped("shotgun")
	assert_eq(hud._active_weapon, "shotgun")


## Verifies [ChunkManager] enums, constants, delta tracking, and chunk path resolution.
func test_chunk_manager_contracts() -> void:
	assert_almost_eq(ChunkManager.CHUNK_SIZE, 50.0, 0.001)
	assert_eq(ChunkManager.GRID_MIN, -50)
	assert_eq(ChunkManager.GRID_MAX, 50)
	assert_eq(ChunkManager.LOAD_RADIUS, 12)
	assert_almost_eq(ChunkManager.IMMEDIATE_RADIUS_SQ, 2.0, 0.001)
	assert_almost_eq(ChunkManager.LOAD_RADIUS_SQ, 144.0, 0.001)
	assert_eq(ChunkManager.MAX_CONCURRENT_IO, 4)
	assert_eq(ChunkManager.MAX_ATTACHES_PER_FRAME, 2)
	assert_almost_eq(ChunkManager.IO_POLL_INTERVAL, 0.05, 0.001)
	assert_eq(ChunkManager.DELTA_FREED, &"freed")

	var manager: ChunkManager = ChunkManager.new()
	var dyn_container: Node3D = Node3D.new()
	dyn_container.name = "DynamicContainer"
	add_child_autofree(dyn_container)
	var io_timer: Timer = Timer.new()
	io_timer.name = "IOTimer"
	manager.add_child(io_timer)
	manager.dynamic_container = dyn_container
	add_child_autofree(manager)

	assert_false(manager.is_processing())
	var coord: Vector2i = Vector2i(0, 0)
	assert_false(manager.is_chunk_active(coord))
	assert_false(manager.has_chunk_delta(coord))

	manager.record_delta(coord, &"crate_1", ChunkManager.DELTA_FREED)
	assert_true(manager.has_chunk_delta(coord))
	var snapshot: Dictionary = manager._build_deltas_snapshot(coord)
	assert_eq(snapshot.get(&"crate_1"), ChunkManager.DELTA_FREED)

	var path: String = manager._get_chunk_path(coord)
	assert_eq(path, "res://world/chunks/chunk_0_0.tscn")


## Verifies [PlayerChunkTracker] constants, timer setup, and coordinate evaluation.
func test_player_chunk_tracker_contracts() -> void:
	assert_almost_eq(PlayerChunkTracker.CHUNK_SIZE, 50.0, 0.001)
	assert_almost_eq(PlayerChunkTracker.POLL_INTERVAL, 0.2, 0.001)
	assert_eq(PlayerChunkTracker.INVALID_COORD, Vector2i(999999, 999999))

	var tracker: PlayerChunkTracker = PlayerChunkTracker.new()
	var poll_timer: Timer = Timer.new()
	poll_timer.name = "PollTimer"
	tracker.add_child(poll_timer)
	add_child_autofree(tracker)

	assert_false(tracker.is_processing())
	assert_almost_eq(poll_timer.wait_time, 0.2, 0.001)
	assert_false(poll_timer.one_shot)

	tracker.position = Vector3(120.0, 0.0, -75.0)
	tracker._evaluate_chunk()
	assert_eq(tracker._current_chunk, Vector2i(2, -2))


## Verifies [ChunkDebugHud] constants, pixel coordinate mapping, and chunk signal tracking.
func test_chunk_debug_hud_contracts() -> void:
	assert_eq(ChunkDebugHud.GRID_MIN, -10)
	assert_eq(ChunkDebugHud.GRID_MAX, 9)
	assert_almost_eq(ChunkDebugHud.CELL_SIZE, 12.0, 0.001)
	assert_almost_eq(ChunkDebugHud.CELL_GAP, 2.0, 0.001)
	assert_eq(ChunkDebugHud.HUD_OFFSET, Vector2(16.0, 16.0))
	assert_almost_eq(ChunkDebugHud.CHUNK_SIZE, 250.0, 0.001)

	var manager: ChunkManager = ChunkManager.new()
	var dyn_container: Node3D = Node3D.new()
	add_child_autofree(dyn_container)
	var io_timer: Timer = Timer.new()
	io_timer.name = "IOTimer"
	manager.add_child(io_timer)
	manager.dynamic_container = dyn_container
	add_child_autofree(manager)

	var hud: ChunkDebugHud = ChunkDebugHud.new()
	hud.chunk_manager = manager
	hud.dynamic_container = dyn_container
	add_child_autofree(hud)

	assert_false(hud.is_processing())
	var px: Vector2 = hud._coord_to_pixel(Vector2i(0, 0))
	assert_eq(px, Vector2(16.0 + 10.0 * 14.0, 16.0 + 10.0 * 14.0))

	hud._on_player_chunk_changed(Vector2i(3, -4))
	assert_eq(hud._player_coord, Vector2i(3, -4))


## Verifies [ControlsPanel] constants, instantiation, and key sanitization helper.
func test_controls_panel_contracts() -> void:
	assert_eq(ControlsPanel.ACTION_CATEGORIES.size(), 4)
	assert_true(ControlsPanel.ACTION_CATEGORIES.has("Movement"))
	assert_true(ControlsPanel.ACTION_CATEGORIES.has("Interactions & Combat"))
	assert_almost_eq(ControlsPanel.HOLD_TIME_THRESHOLD, 0.45, 0.001)
	assert_almost_eq(ControlsPanel.MULTI_TAP_TIME_WINDOW, 0.30, 0.001)
	assert_eq(ControlsPanel.MASH_THRESHOLD_COUNT, 3)
	assert_almost_eq(ControlsPanel.CHORD_COMPLETION_WINDOW, 0.25, 0.001)

	var panel: ControlsPanel = CONTROLS_PANEL_SCENE.instantiate() as ControlsPanel
	assert_not_null(panel)
	add_child_autofree(panel)

	assert_eq(panel.prompt_icon_size, Vector2(36.0, 36.0))
	assert_false(panel.is_remapping)
	assert_eq(panel._sanitize_key_name("Space (Physical)"), "Space")


## Verifies [AccessibilityControlsSection] and [AccessibilityVisualsSection] contracts.
func test_accessibility_sections_contracts() -> void:
	assert_almost_eq(AccessibilityControlsSection.DEFAULT_MOUSE_SENSITIVITY, 1.0, 0.001)
	assert_false(AccessibilityControlsSection.DEFAULT_REDUCE_MOTION)
	assert_almost_eq(AccessibilityControlsSection.DEFAULT_VIBRATION, 1.0, 0.001)
	assert_almost_eq(AccessibilityControlsSection.DEFAULT_AIM_ASSIST_AMOUNT, 0.5, 0.001)
	assert_eq(AccessibilityControlsSection.DEFAULT_AIM_ASSIST_MODE, 1)
	assert_true(AccessibilityControlsSection.DEFAULT_CANCEL_CROUCH_ON_JUMP)

	assert_almost_eq(AccessibilityVisualsSection.DEFAULT_BRIGHTNESS, 1.0, 0.001)
	assert_almost_eq(AccessibilityVisualsSection.DEFAULT_CONTRAST, 1.0, 0.001)
	assert_almost_eq(AccessibilityVisualsSection.DEFAULT_SATURATION, 1.0, 0.001)
	assert_eq(AccessibilityVisualsSection.DEFAULT_COLORBLIND_MODE, 0)
	assert_false(AccessibilityVisualsSection.DEFAULT_HIGH_CONTRAST)
	assert_almost_eq(AccessibilityVisualsSection.DEFAULT_FILM_GRAIN, 0.0, 0.001)
	assert_false(AccessibilityVisualsSection.DEFAULT_PHOTOSENSITIVITY)
	assert_eq(AccessibilityVisualsSection.DEFAULT_SCREEN_FILTER, 0)
	assert_almost_eq(AccessibilityVisualsSection.DEFAULT_GAMMA, 1.0, 0.001)

	var acc_panel: Node = ACCESSIBILITY_PANEL_SCENE.instantiate()
	assert_not_null(acc_panel)
	add_child_autofree(acc_panel)

	var controls_sec: AccessibilityControlsSection = (
		acc_panel.find_child("*Controls*", true, false) as AccessibilityControlsSection
	)
	if controls_sec == null:
		var found_ctrl: Array[Node] = acc_panel.find_children("*", "GridContainer", true, false)
		for node: Node in found_ctrl:
			if node is AccessibilityControlsSection:
				controls_sec = node as AccessibilityControlsSection
				break
	assert_not_null(controls_sec)
	assert_not_null(controls_sec._resolve_swim_toggle())
	assert_not_null(controls_sec._resolve_ammo_toggle())

	var visuals_sec: AccessibilityVisualsSection = null
	var found_vis: Array[Node] = acc_panel.find_children("*", "VBoxContainer", true, false)
	for node: Node in found_vis:
		if node is AccessibilityVisualsSection:
			visuals_sec = node as AccessibilityVisualsSection
			break
	assert_not_null(visuals_sec)
	visuals_sec.sync_external_colorblind(0)
	visuals_sec.sync_external_high_contrast(false)
	visuals_sec.sync_external_photosensitivity(false)


## Verifies [DeathScreen] enums, constants, initial hidden state, and audio synthesis.
func test_death_screen_contracts() -> void:
	assert_eq(DeathScreen.DEATH_MESSAGES.size(), 14)
	assert_true(DeathScreen.HEALTHY_POINTS.size() > 0)
	assert_true(DeathScreen.FLATLINE_POINTS.size() > 0)
	assert_eq(DeathScreen.DeathState.CROUCHING, 0)
	assert_eq(DeathScreen.DeathState.WALKING, 1)
	assert_eq(DeathScreen.DeathState.SPRINTING, 2)

	var death_screen: DeathScreen = DEATH_SCREEN_SCENE.instantiate() as DeathScreen
	assert_not_null(death_screen)
	add_child_autofree(death_screen)

	assert_false(death_screen.visible)
	var tone: AudioStreamWAV = death_screen._generate_tone(440.0, 0.05, false, 0.1)
	assert_not_null(tone)
	assert_true(tone.data.size() > 0)

	var noise: AudioStreamWAV = death_screen._generate_white_noise(0.05, false, 0.1)
	assert_not_null(noise)
	assert_true(noise.data.size() > 0)


## Verifies [PlayerStatusHUD] and [ScreenEffectsManager] contracts inside [ui.tscn].
func test_ui_hud_and_screen_effects_contracts() -> void:
	assert_eq(ScreenEffectsManager.PARAM_FULL_LENS_FOG, &"full_lens_fog")
	assert_eq(ScreenEffectsManager.PARAM_EDGE_CONDENSATION, &"edge_condensation")
	assert_eq(ScreenEffectsManager.PARAM_SPEED_LINES_ALPHA, &"effect_alpha")
	assert_eq(ScreenEffectsManager.PARAM_UNEVEN_TIMING, &"uneven_timing")
	assert_eq(ScreenEffectsManager.PARAM_TIMING_RANDOMNESS, &"timing_randomness")
	assert_not_null(ScreenEffectsManager.SCREEN_TRANSITION_SHADER)

	var ui_root: Node = UI_SCENE.instantiate()
	assert_not_null(ui_root)
	add_child_autofree(ui_root)

	var status_hud: PlayerStatusHUD = ui_root.get_node_or_null("PlayerStatusHUD") as PlayerStatusHUD
	assert_not_null(status_hud)
	status_hud.update_health(200)
	assert_eq(status_hud.current_health, 200)
	status_hud._on_card_picked_up(&"red_card")
	assert_true(status_hud.active_card_icons.has(&"red_card"))
	status_hud._on_card_used(&"red_card")
	assert_false(status_hud.active_card_icons.has(&"red_card"))

	var effects: ScreenEffectsManager = (
		ui_root.get_node_or_null("ScreenEffectsManager") as ScreenEffectsManager
	)
	assert_not_null(effects)
	assert_false(effects.is_processing())
	effects.trigger_pain_effect()
	effects.trigger_heal_effect()
	effects.set_rain_screen_active(true, 0.5)
	effects.set_rain_screen_active(false, 0.0)
	effects.set_screen_black_instant(true)
	effects.set_screen_black_instant(false)
