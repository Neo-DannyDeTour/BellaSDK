## Global event bus singleton routing cross-system game events and typography.
extends Node

# --------------------------------------
# AUDIO & SOUND EFFECT SIGNALS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted to play a 2D sound effect. Passes [param stream] and [param bus].
signal sfx_2d_requested(stream: AudioStream, bus: StringName)

@warning_ignore("unused_signal")
## Emitted to play a 3D spatial sound. Passes [param stream], [param global_pos], [param bus].
signal sfx_3d_requested(stream: AudioStream, global_pos: Vector3, bus: StringName)

# --------------------------------------
# GAME LIFECYCLE & SESSION SIGNALS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted when the game match or level loop starts.
signal game_started

@warning_ignore("unused_signal")
## Emitted when game execution is paused. Passes [param is_paused].
signal game_pause_toggled(is_paused: bool)

@warning_ignore("unused_signal")
## Emitted when player dies or level objective fails. Passes [param reason].
signal game_over_triggered(reason: String)

@warning_ignore("unused_signal")
## Emitted when a new map or level load completes. Passes [param level_name].
signal level_loaded(level_name: String)

# --------------------------------------
# WAVE SPAWNER & ENEMY LIFECYCLE SIGNALS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted when an enemy wave begins. Passes [param wave_number].
signal wave_started(wave_number: int)

@warning_ignore("unused_signal")
## Emitted when an enemy wave is cleared. Passes [param wave_number].
signal wave_completed(wave_number: int)

@warning_ignore("unused_signal")
## Emitted when an enemy unit spawns into the world. Passes [param enemy_node].
signal enemy_spawned(enemy_node: Node3D)

@warning_ignore("unused_signal")
## Emitted when an enemy is slain. Passes [param enemy_node] and [param killer_node].
signal enemy_killed(enemy_node: Node3D, killer_node: Node3D)

@warning_ignore("unused_signal")
## Emitted when a monster triggers a screen-space roar shockwave.
## Payloads: [param duration] sustain time in seconds.
signal monster_roared(duration: float)

# --------------------------------------
# PLAYER STATE & COMMAND SIGNALS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted when the player's health reaches zero.
signal player_died

@warning_ignore("unused_signal")
## Emitted when player health points change. Passes [param new_health].
signal player_health_changed(new_health: int)

@warning_ignore("unused_signal")
## Emitted to forcefully set player health. Passes [param health_amount].
signal player_health_set_requested(health_amount: int)

@warning_ignore("unused_signal")
## Emitted to trigger instant player death from debug terminal.
signal player_kill_requested

@warning_ignore("unused_signal")
## Emitted to grant an item to inventory. Passes [param item_name] and [param amount].
signal inventory_item_given(item_name: String, amount: int)

@warning_ignore("unused_signal")
## Emitted to toggle flight navigation mode. Passes [param is_flying].
signal flight_mode_toggled(is_flying: bool)

@warning_ignore("unused_signal")
## Emitted to override world gravity scalar. Passes [param gravity].
signal gravity_override_requested(gravity: float)

@warning_ignore("unused_signal")
## Emitted to request player teleportation. Passes [param target_position].
signal teleport_requested(target_position: Vector3)

@warning_ignore("unused_signal")
## Emitted when the player enters or leaves crouch. Passes [param is_crouching].
signal player_crouch_changed(is_crouching: bool)

@warning_ignore("unused_signal")
## Emitted when the player zooms their view in or out. Passes [param is_zooming].
signal player_zoomed(is_zooming: bool)

@warning_ignore("unused_signal")
## Emitted when the player sustains shock or electric hazard damage.
signal player_electrocuted

@warning_ignore("unused_signal")
## Emitted when proximity to an electric field changes vignette [param intensity].
signal electricity_vignette_changed(intensity: float)

@warning_ignore("unused_signal")
## Emitted when underwater visual effects toggle with state and intensity.
signal underwater_vfx_toggled(
	is_underwater: bool, wash_intensity: float, drop_intensity: float, clear_progress: float
)

@warning_ignore("unused_signal")
## Emitted when screen rain droplet VFX changes. Passes [param intensity].
signal rain_vfx_toggled(intensity: float)

@warning_ignore("unused_signal")
## Emitted when camera lens dirt effect is toggled or adjusted.
## Passes [param enabled] and [param intensity].
signal lens_dirt_changed(enabled: bool, intensity: float)

@warning_ignore("unused_signal")
## Emitted when waterfall screen wash effect changes with active state and alpha.
signal waterfall_vfx_toggled(is_active: bool, wash_intensity: float, clear_progress: float)

@warning_ignore("unused_signal")
## Emitted when the camera surfaces from water or exits a waterfall to play the meniscus wipe.
signal water_sheet_wipe_requested(duration: float)

@warning_ignore("unused_signal")
## Emitted when a security camera detects the player and captures an in-RAM [param mugshot].
## Payloads: [param mugshot] low-res [Texture2D], [param camera_pos] world [Vector3].
signal player_spotted_by_camera(mugshot: Texture2D, camera_pos: Vector3)

@warning_ignore("unused_signal")
## Emitted to trigger an Advisor psychic distortion wave pulse across the screen.
signal advisor_psychic_pulse_requested(duration: float, peak: float, center_uv: Vector2)

@warning_ignore("unused_signal")
## Emitted to trigger an Advisor psychic pulse anchored to [param source_node] in 3D space.
signal advisor_psychic_pulse_from_requested(source_node: Node3D, duration: float, peak: float)

@warning_ignore("unused_signal")
## Emitted to set sustained Advisor psychic screen distortion [param intensity] directly.
signal advisor_psychic_intensity_requested(intensity: float)

@warning_ignore("unused_signal")
## Emitted when an Advisor psychic distortion pulse animation finishes.
signal advisor_psychic_pulse_finished

@warning_ignore("unused_signal")
## Emitted to change screen drunk distortion and camera sway weight.
## Passes [param intensity] and [param duration].
signal drunk_intensity_changed(intensity: float, duration: float)

@warning_ignore("unused_signal")
## Emitted to trigger an HL2-style harsh black & white contrast transition pulse across the screen.
signal harsh_contrast_pulse_requested(
	duration: float, peak: float, target_threshold: float, peak_flash: float
)

@warning_ignore("unused_signal")
## Emitted to set sustained harsh black & white contrast [param intensity] directly.
signal harsh_contrast_intensity_requested(
	intensity: float, custom_threshold: float, custom_softness: float
)

@warning_ignore("unused_signal")
## Emitted when a harsh black & white contrast pulse animation finishes.
signal harsh_contrast_pulse_finished

# --------------------------------------
# CHEAT & DEBUG SIGNALS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted when noclip fly mode is toggled. Passes [param is_flying].
signal noclip_toggled(is_flying: bool)

@warning_ignore("unused_signal")
## Emitted when trigger visibility is toggled. Passes [param is_active].
signal trigger_visibility_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when the noclip button is pressed in debug interfaces.
signal noclip_ui_button_pressed

@warning_ignore("unused_signal")
## Emitted when the flight speed multiplier for noclip is modified.
signal noclip_speed_changed(speed: float)

@warning_ignore("unused_signal")
## Emitted when fullbright rendering mode is toggled. Passes [param is_fullbright].
signal fullbright_toggled(is_fullbright: bool)

@warning_ignore("unused_signal")
## Emitted when wireframe rendering mode is toggled. Passes [param is_on].
signal wireframe_toggled(is_on: bool)

@warning_ignore("unused_signal")
## Emitted when wireframe shader overlay is toggled on scene geometry.
signal wireframe_overlay_toggled(is_overlay: bool)

@warning_ignore("unused_signal")
## Emitted when the debug drawer interface is toggled. Passes [param is_open].
signal debug_menu_toggled(is_open: bool)

@warning_ignore("unused_signal")
## Emitted when the developer console UI is toggled. Passes [param is_open].
signal console_toggled(is_open: bool)

@warning_ignore("unused_signal")
## Emitted when a toggle request for the developer console is triggered.
signal console_toggle_requested

# --------------------------------------
# ACCESSIBILITY & VISUAL SETTINGS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted when high contrast shader mode is toggled. Passes [param is_active].
signal high_contrast_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when active colorblind correction mode changes. Passes [param mode].
signal colorblind_mode_changed(mode: int)

@warning_ignore("unused_signal")
## Emitted when photosensitivity filter protections toggle. Passes [param is_active].
signal photosensitivity_mode_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when subtitle displays are toggled globally. Passes [param is_active].
signal subtitles_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when dyslexic-friendly text font is toggled. Passes [param is_active].
signal dyslexic_font_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when the active global UI font changes. Passes [param font_name].
signal font_changed(font_name: String)

@warning_ignore("unused_signal")
## Emitted when vision assist highlighting is toggled. Passes [param is_active].
signal vision_assist_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted to change vision assist background style. Passes [param mode_name].
signal vision_assist_mode_changed(mode_name: String)

@warning_ignore("unused_signal")
## Emitted to modify highlight tint in vision assist for [param target_group].
signal vision_assist_color_changed(target_group: String, color_name: String)

@warning_ignore("unused_signal")
## Emitted when text-to-speech engine state is changed. Passes [param enabled].
signal tts_state_changed(enabled: bool)

@warning_ignore("unused_signal")
## Emitted when aim assist mode is modified. Passes [param mode] (0=Off, 1=Mid, 2=Full).
signal aim_assist_mode_changed(mode: int)

@warning_ignore("unused_signal")
## Emitted when target enters or exits aim assist lock range. Passes status and screen pos.
signal aim_assist_target_acquired(has_target: bool, screen_pos: Vector2)

@warning_ignore("unused_signal")
## Emitted when aim assist strength slider is adjusted. Passes [param amount] (0.0 to 1.0).
signal aim_assist_amount_changed(amount: float)

# --------------------------------------
# GAMEPLAY FEEDBACK & UI SIGNALS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted when directional blood spray, mist, and surface decals are requested.
signal blood_fx_requested(hit_position: Vector3, shot_direction: Vector3, is_fatal: bool)

@warning_ignore("unused_signal")
## Emitted per hitscan ray hit. Passes [param position], surface [param normal], [param collider].
signal bullet_impact_requested(position: Vector3, normal: Vector3, collider: Object)

@warning_ignore("unused_signal")
## Emitted when a screen fade transition is requested by a trigger or console.
signal screen_fade_requested(
	fade_color: Color,
	fade_in_duration: float,
	hold_duration: float,
	fade_out_duration: float,
	use_blur: bool,
	max_blur: float,
	use_blink: bool,
	blink_count: int
)

@warning_ignore("unused_signal")
## Emitted to trigger a 3D visual shockwave at [param position].
signal shockwave_requested(position: Vector3, radius: float, speed: float)

@warning_ignore("unused_signal")
## Emitted when terminal interaction mode is toggled. Passes [param is_active].
signal terminal_mode_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted to trigger a camera screenshake effect with intensity and duration.
signal screenshake_requested(intensity: float, duration: float)

@warning_ignore("unused_signal")
## Emitted when an interactable item is picked up by [param actor].
signal item_picked_up(item: Node3D, actor: Node3D)

@warning_ignore("unused_signal")
## Emitted when an item is dropped by [param actor]. Passes [param item].
signal item_dropped(item: Node3D, actor: Node3D)

@warning_ignore("unused_signal")
## Emitted when a keycard is picked up. Passes [param card_id].
signal keycard_collected(card_id: String)

@warning_ignore("unused_signal")
## Emitted when a scripted map event is triggered. Passes [param event_name].
signal level_event_triggered(event_name: String, is_active: bool)

@warning_ignore("unused_signal")
## Emitted when a sprint-blocking debuff is applied. Passes [param duration].
signal sprint_debuff_applied(duration: float)

@warning_ignore("unused_signal")
## Emitted when a movement-blocking debuff is applied. Passes [param duration].
signal immobilize_debuff_applied(duration: float)

@warning_ignore("unused_signal")
## Emitted to request a temporary banner hint message on screen.
signal hint_requested(message: String, duration: float)

@warning_ignore("unused_signal")
## Emitted when a note item is opened for reading. Passes [param note_text].
signal note_opened(note_text: String)

@warning_ignore("unused_signal")
## Emitted when a note reading overlay is dismissed.
signal note_closed

@warning_ignore("unused_signal")
## Emitted when a player focuses on a 3D interactable object.
signal object_focused(text: String, caller: Node)

@warning_ignore("unused_signal")
## Emitted to request a timed subtitle with speaker, text, and duration.
signal subtitle_requested(speaker: String, text: String, duration: float)

@warning_ignore("unused_signal")
## Emitted when a currently playing subtitle should be stopped early.
signal subtitle_canceled

@warning_ignore("unused_signal")
## Emitted when the player triggers a spatial sonar scan from [param origin_node].
signal sonar_ping_requested(origin_node: Node3D)

@warning_ignore("unused_signal")
## Emitted to request verbal narration of nearby interactables.
signal describe_surroundings_requested(origin_node: Node3D)

@warning_ignore("unused_signal")
## Emitted when a chapter title card sequence is triggered with visual style.
signal chapter_triggered(
	chapter_name: String, style: ChapterAnimStyle, duration: float, color: Color
)

@warning_ignore("unused_signal")
## Emitted when post-process screen filters are selected. Passes [param filter_name].
signal screen_filter_changed(filter_name: String)

@warning_ignore("unused_signal")
## Emitted when film grain intensity is adjusted. Passes [param intensity].
signal film_grain_changed(intensity: float)

@warning_ignore("unused_signal")
## Emitted when subtitle font size is adjusted. Passes [param font_size] in px.
signal subtitle_size_changed(font_size: float)

@warning_ignore("unused_signal")
## Emitted when subtitle background opacity is adjusted. Passes [param opacity].
signal subtitle_bg_opacity_changed(opacity: float)

@warning_ignore("unused_signal")
## Emitted when default subtitle dialogue body text color is changed.
signal subtitle_text_color_changed(color_key: String)

@warning_ignore("unused_signal")
## Emitted when subtitle background color is changed. Passes [param color_key].
signal subtitle_bg_color_changed(color_key: String)

@warning_ignore("unused_signal")
## Emitted when showing speaker names is toggled. Passes [param enabled].
signal subtitle_show_names_toggled(enabled: bool)

@warning_ignore("unused_signal")
## Emitted when primary speaker label color is changed. Passes [param color_key].
signal subtitle_speaker_color_changed(color_key: String)

@warning_ignore("unused_signal")
## Emitted when player enters or exits a sprint-blocking sand surface.
signal sand_surface_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when player enters or exits a low-friction ice surface.
signal ice_surface_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when player toggles item interaction text prompts in settings.
signal item_prompts_toggled(enabled: bool)

@warning_ignore("unused_signal")
## Emitted when the global font scale multiplier is modified by the player.
signal font_scale_changed(scale_factor: float)

@warning_ignore("unused_signal")
## Emitted when the primary player camera initializes and becomes active.
signal player_camera_registered(camera: Camera3D)

@warning_ignore("unused_signal")
## Emitted when user interface elements should be toggled visible or hidden.
signal ui_visibility_toggle_requested

@warning_ignore("unused_signal")
## Emitted to toggle the metrics and frame statistics profiling panel.
signal metrics_panel_toggle_requested

@warning_ignore("unused_signal")
## Emitted to toggle the deep render hierarchy diagnostics panel.
signal render_diagnostics_toggle_requested

@warning_ignore("unused_signal")
## Emitted when heavy carrying state changes. Passes [param is_active].
signal heavy_carry_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when vault availability or screen position updates.
signal vault_prompt_updated(is_available: bool, screen_pos: Vector2, is_on_screen: bool)

@warning_ignore("unused_signal")
## Emitted when player grabs or drops any carried item. Passes [param is_holding].
signal held_item_changed(is_holding: bool)

@warning_ignore("unused_signal")
## Emitted when an interactive physics prop impacts a surface above velocity threshold.
signal prop_impacted(prop: RigidBody3D, collider: Node, impact_speed_sq: float)

@warning_ignore("unused_signal")
## Emitted when the player enters or exits a water volume. Passes [param is_active].
signal swim_surface_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when the player submerges their head. Passes [param duration].
signal oxygen_timer_started(duration: float)

@warning_ignore("unused_signal")
## Emitted when the player surfaces their head from water.
signal oxygen_timer_stopped

@warning_ignore("unused_signal")
## Emitted when infinite swim mode is toggled in accessibility settings.
signal infinite_swim_toggled(is_enabled: bool)

@warning_ignore("unused_signal")
## Emitted when infinite ammo mode is toggled in accessibility settings or console.
signal infinite_ammo_toggled(is_enabled: bool)

@warning_ignore("unused_signal")
## Emitted when a weapon tag popup is triggered for [param weapon_id].
signal weapon_tag_displayed(weapon_id: String)

@warning_ignore("unused_signal")
## Emitted when the active weapon slot changes. Passes [param weapon_id].
signal active_weapon_changed(weapon_id: String)

@warning_ignore("unused_signal")
## Emitted when active weapon ammunition count updates.
signal weapon_ammo_changed(current: int, reserve: int, capacity: int)

@warning_ignore("unused_signal")
## Emitted when active weapon completes a reload sequence.
signal weapon_reloaded(weapon_tag: String)

@warning_ignore("unused_signal")
## Emitted when an ammo box is gathered. Passes [param ammo_type] and [param amount].
signal ammo_collected(ammo_type: StringName, amount: int)

@warning_ignore("unused_signal")
## Emitted when wolf vision post-processing is enabled or disabled.
signal wolf_vision_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when wolf wall run begins or ends to drive anime speed lines VFX.
signal wolf_wall_run_vfx_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when wolf claw target availability or 3D world position updates.
signal claw_target_updated(is_available: bool, world_pos: Vector3)

@warning_ignore("unused_signal")
## Emitted when god mode invincibility is toggled. Passes [param is_active].
signal godmode_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when player enters or stops taking steam hazard damage.
signal steam_hazard_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when player enters or exits a volumetric smoke hazard.
signal smoke_hazard_changed(is_inside: bool, density: float)

@warning_ignore("unused_signal")
## Emitted when player suffocation exposure changes inside a volumetric smoke hazard.
signal smoke_exposure_changed(exposure: float)

@warning_ignore("unused_signal")
## Emitted when player enters or stops taking fire hazard damage.
signal fire_hazard_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when the player sustains damage. Passes [param amount] taken.
signal player_damaged(amount: int)

@warning_ignore("unused_signal")
## Emitted when the player restores health. Passes [param amount] restored.
signal player_healed(amount: int)

@warning_ignore("unused_signal")
## Emitted when outline highlight mode changes (0=Off, 1=Always, 2=Focus).
signal outline_mode_changed(mode: int)

@warning_ignore("unused_signal")
## Emitted when target outline color is modified in accessibility settings.
signal outline_color_changed(color: Color)

@warning_ignore("unused_signal")
## Emitted when target outline blink speed is adjusted.
signal outline_blink_speed_changed(speed: float)

@warning_ignore("unused_signal")
## Emitted when target outline minimum pulse intensity is modified.
signal outline_min_intensity_changed(intensity: float)

@warning_ignore("unused_signal")
## Emitted when target outline maximum pulse intensity is modified.
signal outline_max_intensity_changed(intensity: float)

@warning_ignore("unused_signal")
## Emitted when first sight highlight mode is toggled. Passes [param enabled].
signal outline_first_sight_toggled(enabled: bool)

@warning_ignore("unused_signal")
## Emitted when periodic highlight mode is toggled. Passes [param enabled].
signal outline_periodic_toggled(enabled: bool)

@warning_ignore("unused_signal")
## Emitted when outline periodic interval is adjusted. Passes [param interval] in seconds.
signal outline_interval_changed(interval: float)

@warning_ignore("unused_signal")
## Emitted when outline pulse duration is adjusted. Passes [param duration] in seconds.
signal outline_duration_changed(duration: float)

@warning_ignore("unused_signal")
## Emitted when reticle acquires an interactable target with its HUD prompt.
signal interaction_focused(target: CollisionObject3D, prompt: String)

@warning_ignore("unused_signal")
## Emitted when reticle loses focus from an active interactable target.
signal interaction_unfocused(previous_target: CollisionObject3D)

@warning_ignore("unused_signal")
## Emitted when an interaction action completes between target and interactor.
signal interacted(target: CollisionObject3D, interactor: Node3D)

@warning_ignore("unused_signal")
## Emitted to request a state machine transition with target state and payload.
signal transition_requested(target_state_name: StringName, message: Dictionary)

@warning_ignore("unused_signal")
## Emitted to toggle player movement and camera controls during cutscenes.
signal player_cinematic_lock_requested(is_locked: bool)

@warning_ignore("unused_signal")
## Emitted to snap screen overlay to solid black with blur and color.
signal screen_blackout_instant_requested(is_black: bool, blur: float, fade_color: Color)

@warning_ignore("unused_signal")
## Emitted when wolf form state changes. Passes [param is_active].
signal wolf_mode_toggled(is_active: bool)

@warning_ignore("unused_signal")
## Emitted when a level or gameplay trigger requests a volumetric cloud weather transition.
signal weather_changed(weather: Resource, duration: float)

@warning_ignore("unused_signal")
## Emitted to request wake-up eyelid opening and blur clear transition.
signal screen_wake_up_requested(
	fade_color: Color,
	eye_open_time: float,
	max_blur: float,
	blink_count: int,
	blur_clear_time: float
)

@warning_ignore("unused_signal")
## Emitted when cinematic narrative or chapter text needs to be displayed.
signal wake_up_text_requested(text: String, fade_in: float, hold: float, fade_out: float)

@warning_ignore("unused_signal")
## Emitted when notarget cheat is toggled to ignore or detect player entity.
signal player_notarget_toggled(active: bool)

# --------------------------------------
# CHUNK STREAMING SIGNALS
# --------------------------------------
@warning_ignore("unused_signal")
## Emitted by [PlayerChunkTracker] when player crosses a 250m chunk boundary.
signal player_chunk_changed(coord: Vector2i)

@warning_ignore("unused_signal")
## Emitted when persistent chunk entity is modified or destroyed at runtime.
signal chunk_entity_mutated(coord: Vector2i, entity_id: StringName, data: Variant)

# --------------------------------------
# ENUMS
# --------------------------------------
## Visual animation style presets for chapter title card sequences.
enum ChapterAnimStyle {
	SIMPLE,
	WAVE,
	GLOW,
	GLITCH,
	REVEAL,
	CHROMATIC,
	DRIFT,
	DISSOLVE,
	LIQUID,
	HOLOGRAM,
	TYPEWRITER,
	SLAM,
	SPRING,
	NEON,
	SHATTER,
	BLUR,
	DOOM_MELT,
	HEARTBEAT,
	VHS,
	LIGHT_SWEEP,
}

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Standard Control type names that render typography in Godot UI.
const UI_FONT_TYPES: Array[StringName] = [
	&"Label",
	&"Button",
	&"CheckButton",
	&"CheckBox",
	&"OptionButton",
	&"LineEdit",
	&"TextEdit",
	&"RichTextLabel",
	&"TabBar",
	&"Tree",
	&"PopupMenu",
	&"MenuButton"
]

## Standard font theme property keys to override on UI controls.
const UI_FONT_KEYS: Array[StringName] = [
	&"font", &"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"
]

## Preloaded font resources keyed by typography identifier.
const PRELOADED_FONTS: Dictionary[String, Font] = {
	"kramola": preload("res://assets/fonts/kramola/Kramola.otf"),
	"dyslexic": preload("res://assets/fonts/opendyslexic-0.92/OpenDyslexic-Regular.otf"),
	"papyrus": preload("res://assets/fonts/papyrus-font/papyrus.ttf"),
	"comic": preload("res://assets/fonts/Comic Sans MS.ttf"),
	"futura": preload("res://assets/fonts/FuturaHandwritten.ttf"),
	"help_me": preload("res://assets/fonts/HelpMe.ttf"),
	"olde_english": preload("res://assets/fonts/OldeEnglish.ttf"),
	"stalinist": preload("res://assets/fonts/StalinistOne-Regular.ttf"),
	"super_funky": preload("res://assets/fonts/Super Funky.ttf"),
}

# --------------------------------------
# VARIABLES
# --------------------------------------
## Tracks whether the player character is currently invincible.
var is_godmode: bool = false

## Dictionary mapping font identifier keys to loaded [Font] resources.
var fonts: Dictionary[String, Font] = {}

## Fallback built-in engine font captured directly from [ThemeDB].
var engine_fallback_font: Font = null

## Guard to ensure disk fonts are only loaded and parsed once.
var _is_cached: bool = false


## Lifecycle constructor initializing baseline event bus logging.
func _init() -> void:
	print("Events: Initialized.")


## Lifecycle method connecting signal listeners for global typography.
func _ready() -> void:
	font_changed.connect(_on_font_changed)


## Replaces root theme default font and forces an immediate UI redraw.
## [param font_name] Identifier key of the newly selected font.
func _on_font_changed(font_name: String) -> void:
	if not _is_cached:
		_load_registered_fonts()

	var lookup_key: String = (
		"kramola" if (font_name.is_empty() or font_name == "default") else font_name
	)
	var target_font: Font = fonts.get(lookup_key, null)
	if not is_instance_valid(target_font):
		target_font = fonts.get("kramola", null)
	if not is_instance_valid(target_font):
		return

	var root_window: Window = get_tree().root
	if not is_instance_valid(root_window):
		return

	if not root_window.theme:
		root_window.theme = Theme.new()

	var active_theme: Theme = root_window.theme
	active_theme.default_font = target_font

	for type_name: StringName in UI_FONT_TYPES:
		active_theme.set_font("font", type_name, target_font)

	_apply_font_override_recursive(root_window, target_font)
	get_tree().call_group(&"3d_text", "set", "font", target_font)
	print("Events: Global font changed to '", lookup_key, "'.")


## Populates the runtime font cache from [constant PRELOADED_FONTS].
func _load_registered_fonts() -> void:
	if _is_cached:
		return

	engine_fallback_font = ThemeDB.fallback_font
	for font_id: String in PRELOADED_FONTS:
		var font_res: Font = PRELOADED_FONTS[font_id]
		if is_instance_valid(font_res):
			fonts[font_id] = font_res

	if fonts.has("kramola"):
		fonts["default"] = fonts["kramola"]

	_is_cached = true


## Recursively propagates explicit font overrides down active Control nodes.
## [param parent] Root control node receiving font replacements.
## [param new_font] Selected font resource applied to children.
func _apply_font_override_recursive(parent: Node, new_font: Font) -> void:
	if not is_instance_valid(parent):
		return

	if parent is Control:
		var ctrl: Control = parent as Control
		for font_key: StringName in UI_FONT_KEYS:
			ctrl.add_theme_font_override(font_key, new_font)
		ctrl.notification(Control.NOTIFICATION_THEME_CHANGED)
		ctrl.queue_redraw()

	for child: Node in parent.get_children():
		_apply_font_override_recursive(child, new_font)
