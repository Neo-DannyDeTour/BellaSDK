## Global event bus singleton for routing cross-system game events, UI toggles, and font overrides.
extends Node

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

## Tracks whether the player is currently invincible.
var is_godmode: bool = false

## Dictionary mapping available font identifier keys to their loaded [Font] resources.
var fonts: Dictionary[String, Font] = {}

## Fallback built-in engine font captured directly from ThemeDB.
var engine_fallback_font: Font = null

## Guard to ensure disk fonts are only loaded and parsed once.
var _is_cached: bool = false

# --- PLAYER STATE SIGNALS ---
## Emitted when the player's health reaches zero.
@warning_ignore("unused_signal")
signal player_died

## Emitted when player health points change. Passes [param new_health].
@warning_ignore("unused_signal")
signal player_health_changed(new_health: int)

## Emitted when the player enters or leaves crouch. Passes [param is_crouching].
@warning_ignore("unused_signal")
signal player_crouch_changed(is_crouching: bool)

## Emitted when the player zooms their view in or out. Passes [param is_zooming].
@warning_ignore("unused_signal")
signal player_zoomed(is_zooming: bool)

## Emitted when the player sustains shock or electric hazard damage.
@warning_ignore("unused_signal")
signal player_electrocuted

## Emitted when underwater visual effects toggle with state and intensity params.
@warning_ignore("unused_signal")
signal underwater_vfx_toggled(
	is_underwater: bool, wash_intensity: float, drop_intensity: float, clear_progress: float
)

## Emitted when screen rain droplet VFX changes. Passes [param intensity].
@warning_ignore("unused_signal")
signal rain_vfx_toggled(intensity: float)

## Emitted when waterfall screen wash effect changes with active state and alpha.
@warning_ignore("unused_signal")
signal waterfall_vfx_toggled(is_active: bool, wash_intensity: float, clear_progress: float)

# --- CHEAT & DEBUG SIGNALS ---
## Emitted when noclip fly mode is toggled. Passes [param is_flying].
@warning_ignore("unused_signal")
signal noclip_toggled(is_flying: bool)

## Emitted when the noclip button is pressed in debug interfaces.
@warning_ignore("unused_signal")
signal noclip_ui_button_pressed

## Emitted when the flight speed multiplier for noclip is modified.
@warning_ignore("unused_signal")
signal noclip_speed_changed(speed: float)

## Emitted when fullbright rendering mode is toggled. Passes [param is_fullbright].
@warning_ignore("unused_signal")
signal fullbright_toggled(is_fullbright: bool)

## Emitted when wireframe rendering mode is toggled. Passes [param is_on].
@warning_ignore("unused_signal")
signal wireframe_toggled(is_on: bool)

## Emitted when wireframe shader overlay is toggled on scene geometry.
@warning_ignore("unused_signal")
signal wireframe_overlay_toggled(is_overlay: bool)

## Emitted when the debug drawer interface is toggled. Passes [param is_open].
@warning_ignore("unused_signal")
signal debug_menu_toggled(is_open: bool)

## Emitted when the developer console UI is toggled. Passes [param is_open].
@warning_ignore("unused_signal")
signal console_toggled(is_open: bool)

## Emitted when a toggle request for the developer console is triggered.
@warning_ignore("unused_signal")
signal console_toggle_requested

# --- ACCESSIBILITY & VISUAL SETTINGS ---
## Emitted when high contrast shader mode is toggled. Passes [param is_active].
@warning_ignore("unused_signal")
signal high_contrast_toggled(is_active: bool)

## Emitted when active colorblind correction mode changes. Passes [param mode].
@warning_ignore("unused_signal")
signal colorblind_mode_changed(mode: int)

## Emitted when photosensitivity filter protections toggle. Passes [param is_active].
@warning_ignore("unused_signal")
signal photosensitivity_mode_toggled(is_active: bool)

## Emitted when subtitle displays are toggled globally. Passes [param is_active].
@warning_ignore("unused_signal")
signal subtitles_toggled(is_active: bool)

## Emitted when dyslexic-friendly text font is toggled. Passes [param is_active].
@warning_ignore("unused_signal")
signal dyslexic_font_toggled(is_active: bool)

## Emitted when the active global UI font changes. Passes [param font_name].
@warning_ignore("unused_signal")
signal font_changed(font_name: String)

## Emitted when vision assist highlighting is toggled. Passes [param is_active].
@warning_ignore("unused_signal")
signal vision_assist_toggled(is_active: bool)

## Emitted to change vision assist background style. Passes [param mode_name].
@warning_ignore("unused_signal")
signal vision_assist_mode_changed(mode_name: String)

## Emitted to modify highlight tint in vision assist for [param target_group].
@warning_ignore("unused_signal")
signal vision_assist_color_changed(target_group: String, color_name: String)

## Emitted when text-to-speech engine state is changed. Passes [param enabled].
@warning_ignore("unused_signal")
signal tts_state_changed(enabled: bool)

# --- GAMEPLAY FEEDBACK & UI SIGNALS ---
## Emitted when terminal interaction mode is toggled. Passes [param is_active].
@warning_ignore("unused_signal")
signal terminal_mode_toggled(is_active: bool)

## Emitted to trigger a camera screenshake effect with intensity and duration.
@warning_ignore("unused_signal")
signal screenshake_requested(intensity: float, duration: float)

## Emitted when an interactable item is picked up by [param actor].
@warning_ignore("unused_signal")
signal item_picked_up(item: Node3D, actor: Node3D)

## Emitted when an item is dropped by [param actor]. Passes [param item].
@warning_ignore("unused_signal")
signal item_dropped(item: Node3D, actor: Node3D)

## Emitted when a keycard is picked up. Passes [param card_id].
@warning_ignore("unused_signal")
signal keycard_collected(card_id: String)

## Emitted when a scripted map event is triggered. Passes [param event_name].
@warning_ignore("unused_signal")
signal level_event_triggered(event_name: String, is_active: bool)

## Emitted when a sprint-blocking debuff is applied. Passes [param duration].
@warning_ignore("unused_signal")
signal sprint_debuff_applied(duration: float)

## Emitted when a movement-blocking debuff is applied. Passes [param duration].
@warning_ignore("unused_signal")
signal immobilize_debuff_applied(duration: float)

## Emitted to request a temporary banner hint message on screen.
@warning_ignore("unused_signal")
signal hint_requested(message: String, duration: float)

## Emitted when a note item is opened for reading. Passes [param note_text].
@warning_ignore("unused_signal")
signal note_opened(note_text: String)

## Emitted when a note reading overlay is dismissed.
@warning_ignore("unused_signal")
signal note_closed

## Emitted when a player focuses on a 3D interactable object.
@warning_ignore("unused_signal")
signal object_focused(text: String, caller: Node)

## Emitted to request a timed subtitle with speaker, text, and duration.
@warning_ignore("unused_signal")
signal subtitle_requested(speaker: String, text: String, duration: float)

## Emitted when a currently playing subtitle should be stopped early.
@warning_ignore("unused_signal")
signal subtitle_canceled

## Emitted when the player triggers a spatial sonar scan from [param origin_node].
@warning_ignore("unused_signal")
signal sonar_ping_requested(origin_node: Node3D)

## Emitted to request verbal narration of nearby interactables.
@warning_ignore("unused_signal")
signal describe_surroundings_requested(origin_node: Node3D)

## Emitted when a chapter title card sequence is triggered with visual style.
@warning_ignore("unused_signal")
signal chapter_triggered(
	chapter_name: String, style: ChapterAnimStyle, duration: float, color: Color
)

## Emitted when post-process screen filters are selected. Passes [param filter_name].
@warning_ignore("unused_signal")
signal screen_filter_changed(filter_name: String)

## Emitted when film grain intensity is adjusted. Passes [param intensity].
@warning_ignore("unused_signal")
signal film_grain_changed(intensity: float)

## Emitted when subtitle font size is adjusted. Passes [param font_size] in px.
@warning_ignore("unused_signal")
signal subtitle_size_changed(font_size: float)

## Emitted when subtitle background opacity is adjusted. Passes [param opacity].
@warning_ignore("unused_signal")
signal subtitle_bg_opacity_changed(opacity: float)

## Emitted when default subtitle dialogue body text color is changed.
@warning_ignore("unused_signal")
signal subtitle_text_color_changed(color_key: String)

## Emitted when subtitle background color is changed. Passes [param color_key].
@warning_ignore("unused_signal")
signal subtitle_bg_color_changed(color_key: String)

## Emitted when showing speaker names is toggled. Passes [param enabled].
@warning_ignore("unused_signal")
signal subtitle_show_names_toggled(enabled: bool)

## Emitted when primary speaker label color is changed. Passes [param color_key].
@warning_ignore("unused_signal")
signal subtitle_speaker_color_changed(color_key: String)

## Emitted when player enters or exits a sprint-blocking sand surface.
@warning_ignore("unused_signal")
signal sand_surface_toggled(is_active: bool)

## Emitted when player enters or exits a low-friction ice surface.
@warning_ignore("unused_signal")
signal ice_surface_toggled(is_active: bool)

## Emitted when player toggles item interaction text prompts in settings.
@warning_ignore("unused_signal")
signal item_prompts_toggled(enabled: bool)

## Emitted when the global font scale multiplier is modified by the player.
@warning_ignore("unused_signal")
signal font_scale_changed(scale_factor: float)

## Emitted when the primary player camera initializes and becomes active.
@warning_ignore("unused_signal")
signal player_camera_registered(camera: Camera3D)

## Emitted when user interface elements should be toggled visible or hidden.
@warning_ignore("unused_signal")
signal ui_visibility_toggle_requested

## Emitted to toggle the metrics and frame statistics profiling panel.
@warning_ignore("unused_signal")
signal metrics_panel_toggle_requested

## Emitted to toggle the deep render hierarchy diagnostics panel.
@warning_ignore("unused_signal")
signal render_diagnostics_toggle_requested

## Emitted when heavy carrying state changes. Passes [param is_active].
@warning_ignore("unused_signal")
signal heavy_carry_toggled(is_active: bool)

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


## Lifecycle constructor initializing baseline font mappings.
func _init() -> void:
	print("Events: _init() called.")


## Lifecycle method connecting signal listeners.
func _ready() -> void:
	print("Events: _ready() called. Binding event listeners.")
	font_changed.connect(_on_font_changed)


## Replaces the project's root theme default font and forces an immediate UI redraw.
## [param font_name] The identifier key of the font to apply.
func _on_font_changed(font_name: String) -> void:
	print("Events: Changing global font to '", font_name, "'.")

	if not _is_cached:
		_load_registered_fonts()

	var target_font: Font = fonts.get(font_name, engine_fallback_font)
	if not is_instance_valid(target_font):
		target_font = engine_fallback_font

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
	get_tree().call_group("3d_text", "set", "font", target_font)
	print("Events: Global font '", font_name, "' applied successfully.")


## Dynamically iterates the GlobalSettings font registry and caches loaded resources once.
func _load_registered_fonts() -> void:
	if _is_cached:
		return

	engine_fallback_font = ThemeDB.fallback_font
	fonts["default"] = engine_fallback_font

	var global_settings_node: Node = get_node_or_null("/root/GlobalSettings")
	if not is_instance_valid(global_settings_node):
		return

	var registry: Array = global_settings_node.get("FONT_REGISTRY") as Array
	if registry == null:
		return

	for entry_variant: Variant in registry:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var id: String = entry.get("id", "") as String
		var path: String = entry.get("path", "") as String

		if id.is_empty() or id == "default":
			continue

		if not path.is_empty() and ResourceLoader.exists(path):
			var loaded_res: Resource = load(path)
			if loaded_res is Font:
				fonts[id] = loaded_res as Font
				print("Events: Cached font '", id, "' from ", path)
			else:
				push_warning("Events: Resource at " + path + " is not Font.")
		else:
			push_warning("Events: Font file path does not exist: " + path)

	_is_cached = true


## Recursively propagates explicit font overrides down all active Control nodes.
## [param parent] Root parent [Node] to traverse.
## [param new_font] The [Font] instance to assign.
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
