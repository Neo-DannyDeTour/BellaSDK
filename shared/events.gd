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

## Tracks whether the player is currently invincible.
var is_godmode: bool = false

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
## [param chapter_name] The localized title or text to display.
## [param style] The [enum ChapterAnimStyle] preset determining the animation effect.
## [param duration] The display duration in seconds.
## [param color] The base font tint [Color].
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

## Dictionary mapping available font identifier keys to their loaded [Font] resources.
var fonts: Dictionary[String, Font] = {}

## Fallback font resource captured on initial boot.
var default_engine_font: Font = null

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


## Lifecycle method connecting signal listeners and caching registry fonts.
func _ready() -> void:
	print("Events: _ready() called. Loading font registry and binding events.")
	font_changed.connect(_on_font_changed)
	call_deferred("_load_registered_fonts")


## Replaces the project's root theme default font and forces an immediate UI redraw.
## [param font_name] The identifier key of the font to apply.
func _on_font_changed(font_name: String) -> void:
	print("Events: Changing global font to '", font_name, "'.")

	if not fonts.has(font_name):
		_load_registered_fonts()

	if not fonts.has(font_name):
		push_warning("Events: Unknown font key '" + font_name + "'. Falling back to default.")
		font_name = "default"

	var target_font: Font = fonts.get(font_name, default_engine_font)
	if not is_instance_valid(target_font):
		push_error("Events: Failed to resolve valid Font instance for: " + font_name)
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
	get_tree().call_group("3d_text", "set", "font", target_font)
	print("Events: Global font '", font_name, "' applied successfully.")


## Dynamically iterates the GlobalSettings font registry and caches loaded resources.
func _load_registered_fonts() -> void:
	var root_window: Window = get_tree().root
	if root_window and root_window.theme and root_window.theme.default_font:
		default_engine_font = root_window.theme.default_font
	else:
		default_engine_font = ThemeDB.fallback_font

	fonts["default"] = default_engine_font

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


## Recursively propagates font theme overrides down all active Control nodes.
## [param parent] Root parent [Node] to traverse.
## [param new_font] The [Font] instance to assign.
func _apply_font_override_recursive(parent: Node, new_font: Font) -> void:
	if not is_instance_valid(parent):
		return

	if parent is Control:
		var ctrl: Control = parent as Control
		ctrl.add_theme_font_override("font", new_font)
		ctrl.add_theme_font_override("normal_font", new_font)
		ctrl.notification(Control.NOTIFICATION_THEME_CHANGED)
		ctrl.queue_redraw()

	for child: Node in parent.get_children():
		_apply_font_override_recursive(child, new_font)
