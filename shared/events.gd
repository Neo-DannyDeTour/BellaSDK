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

## Emitted when the player's health points change.
@warning_ignore("unused_signal")
signal player_health_changed(new_health: int)

## Emitted when the player enters or leaves the crouch state.
@warning_ignore("unused_signal")
signal player_crouch_changed(is_crouching: bool)

## Emitted when the player zooms their view in or out.
@warning_ignore("unused_signal")
signal player_zoomed(is_zooming: bool)

## Emitted when the player sustains shock or electric hazard damage.
@warning_ignore("unused_signal")
signal player_electrocuted

@warning_ignore("unused_signal")
## Emitted when the underwater visual effect state changes.
## [param is_underwater] Whether the camera is submerged.
## [param wash_intensity] Ripple distortion strength (0.0 to 1.0).
## [param drop_intensity] Droplet lens effect strength (0.0 to 1.0).
## [param clear_progress] Resurface screen wipe transition progress (0.0 to 1.5).
signal underwater_vfx_toggled(
	is_underwater: bool, wash_intensity: float, drop_intensity: float, clear_progress: float
)

@warning_ignore("unused_signal")
## Emitted when the screen rain droplet VFX changes.
## [param intensity] Rain droplet effect intensity (0.0 to 1.0).
signal rain_vfx_toggled(intensity: float)

@warning_ignore("unused_signal")
## Emitted when the waterfall screen wash effect changes.
## [param is_active] Whether the player is inside the waterfall stream.
## [param wash_intensity] Waterfall distortion strength (0.0 to 1.0).
## [param clear_progress] Wipe mask transition progress (0.0 to 1.5).
signal waterfall_vfx_toggled(is_active: bool, wash_intensity: float, clear_progress: float)

# --- CHEAT & DEBUG SIGNALS ---
## Emitted when noclip fly mode is enabled or disabled.
@warning_ignore("unused_signal")
signal noclip_toggled(is_flying: bool)

## Emitted when the noclip button is pressed in debug interfaces.
@warning_ignore("unused_signal")
signal noclip_ui_button_pressed

## Emitted when the flight speed multiplier for noclip is modified.
@warning_ignore("unused_signal")
signal noclip_speed_changed(speed: float)

## Emitted when fullbright rendering mode is toggled.
@warning_ignore("unused_signal")
signal fullbright_toggled(is_fullbright: bool)

## Emitted when wireframe rendering mode is toggled.
@warning_ignore("unused_signal")
signal wireframe_toggled(is_on: bool)

## Emitted when the wireframe shader overlay is toggled on scene geometry.
@warning_ignore("unused_signal")
signal wireframe_overlay_toggled(is_overlay: bool)

## Emitted when the debug drawer interface is toggled open or closed.
@warning_ignore("unused_signal")
signal debug_menu_toggled(is_open: bool)

## Emitted when the developer console UI is opened or closed.
@warning_ignore("unused_signal")
signal console_toggled(is_open: bool)

## Emitted when a toggle request for the developer console is triggered by user input.
@warning_ignore("unused_signal")
signal console_toggle_requested

# --- ACCESSIBILITY & VISUAL SETTINGS ---
## Emitted when high contrast shader mode is toggled on or off.
@warning_ignore("unused_signal")
signal high_contrast_toggled(is_active: bool)

## Emitted when the active colorblind correction mode index is changed.
@warning_ignore("unused_signal")
signal colorblind_mode_changed(mode: int)

## Emitted when photosensitivity filter protections are toggled on or off.
@warning_ignore("unused_signal")
signal photosensitivity_mode_toggled(is_active: bool)

## Emitted when subtitle displays are toggled globally.
@warning_ignore("unused_signal")
signal subtitles_toggled(is_active: bool)

## Emitted when dyslexic-friendly text font is toggled.
@warning_ignore("unused_signal")
signal dyslexic_font_toggled(is_active: bool)

## Emitted when the active global UI and 3D text font is changed.
@warning_ignore("unused_signal")
signal font_changed(font_name: String)

## Emitted when vision assist high-visibility highlighting is toggled.
@warning_ignore("unused_signal")
signal vision_assist_toggled(is_active: bool)

## Emitted to change the background style of the vision assist shader.
@warning_ignore("unused_signal")
signal vision_assist_mode_changed(mode_name: String)

## Emitted to modify the highlight tint of target group elements in vision assist.
@warning_ignore("unused_signal")
signal vision_assist_color_changed(target_group: String, color_name: String)

## Emitted when text-to-speech engine state is changed.
@warning_ignore("unused_signal")
signal tts_state_changed(enabled: bool)

# --- GAMEPLAY FEEDBACK & UI SIGNALS ---
## Emitted when terminal interaction mode is entered or exited.
@warning_ignore("unused_signal")
signal terminal_mode_toggled(is_active: bool)

## Emitted to trigger a camera trauma screenshake effect.
@warning_ignore("unused_signal")
signal screenshake_requested(intensity: float, duration: float)

## Emitted when an interactable item is collected by an actor.
@warning_ignore("unused_signal")
signal item_picked_up(item: Node3D, actor: Node3D)

## Emitted when an item is dropped by an actor.
@warning_ignore("unused_signal")
signal item_dropped(item: Node3D, actor: Node3D)

## Emitted when a keycard is picked up.
@warning_ignore("unused_signal")
signal keycard_collected(card_id: String)

## Emitted when a named narrative or scripted map event is triggered.
@warning_ignore("unused_signal")
signal level_event_triggered(event_name: String, is_active: bool)

## Emitted when a sprint-blocking debuff is applied to the player.
@warning_ignore("unused_signal")
signal sprint_debuff_applied(duration: float)

## Emitted when a movement-blocking debuff is applied to the player.
@warning_ignore("unused_signal")
signal immobilize_debuff_applied(duration: float)

## Emitted to request a temporary banner hint message on screen.
@warning_ignore("unused_signal")
signal hint_requested(message: String, duration: float)

## Emitted when a note item is opened for reading.
@warning_ignore("unused_signal")
signal note_opened(note_text: String)

## Emitted when a note reading overlay is dismissed.
@warning_ignore("unused_signal")
signal note_closed

## Emitted when a player focuses on a 3D interactable object.
@warning_ignore("unused_signal")
signal object_focused(text: String, caller: Node)

## Emitted to request a timed subtitle on screen.
@warning_ignore("unused_signal")
signal subtitle_requested(speaker: String, text: String, duration: float)

## Emitted when a currently playing subtitle should be stopped early.
@warning_ignore("unused_signal")
signal subtitle_canceled

## Emitted when the player triggers a spatial sonar scan.
@warning_ignore("unused_signal")
signal sonar_ping_requested(origin_node: Node3D)

## Emitted to request verbal narration of nearby interactables.
@warning_ignore("unused_signal")
signal describe_surroundings_requested(origin_node: Node3D)

## Emitted when a chapter title card sequence is triggered.
@warning_ignore("unused_signal")
signal chapter_triggered(
	chapter_name: String, style: ChapterAnimStyle, duration: float, color: Color
)

## Emitted when post-process screen filters are selected.
@warning_ignore("unused_signal")
signal screen_filter_changed(filter_name: String)

## Emitted when film grain effect intensity is adjusted.
@warning_ignore("unused_signal")
signal film_grain_changed(intensity: float)

## Emitted when the subtitle font size is adjusted. Passes font size in pixels.
@warning_ignore("unused_signal")
signal subtitle_size_changed(font_size: float)

## Emitted when the subtitle background opacity is adjusted. Passes opacity (0.0 - 1.0).
@warning_ignore("unused_signal")
signal subtitle_bg_opacity_changed(opacity: float)

## Emitted when the default subtitle dialogue body text color is changed.
@warning_ignore("unused_signal")
signal subtitle_text_color_changed(color_key: String)

## Emitted when the subtitle background color is changed.
@warning_ignore("unused_signal")
signal subtitle_bg_color_changed(color_key: String)

## Emitted when showing speaker names is toggled.
@warning_ignore("unused_signal")
signal subtitle_show_names_toggled(enabled: bool)

## Emitted when the primary speaker label color is changed.
@warning_ignore("unused_signal")
signal subtitle_speaker_color_changed(color_key: String)

## Emitted when the player enters or exits a surface that blocks sprinting (e.g., sand).
@warning_ignore("unused_signal")
signal sand_surface_toggled(is_active: bool)

## Emitted when the player enters or exits a low-friction surface (e.g., ice).
@warning_ignore("unused_signal")
signal ice_surface_toggled(is_active: bool)

## Emitted when the player toggles item interaction text prompts in settings.
@warning_ignore("unused_signal")
signal item_prompts_toggled(enabled: bool)

@warning_ignore("unused_signal")
## Emitted when the global font scale multiplier is modified by the player.
## [param scale_factor] Multiplier applied to base UI font sizes.
signal font_scale_changed(scale_factor: float)

## Emitted when the primary player camera initializes and becomes active.
## Passes [param camera] reference to listening systems like portals and UI viewports.
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

## Emitted when heavy carrying state changes.
## [param is_active] True if the player is currently carrying a heavy object.
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

		if id == "" or id == "default":
			continue

		if path != "" and ResourceLoader.exists(path):
			var loaded_res: Resource = load(path)
			if loaded_res is Font:
				fonts[id] = loaded_res as Font
				print("Events: Successfully cached font '", id, "' from ", path)
			else:
				push_warning("Events: Resource at " + path + " is not a valid Font.")
		else:
			push_warning("Events: Font file path does not exist on disk: " + path)

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
