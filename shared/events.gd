## Global event bus singleton for routing cross-system game events, UI toggles, and cheat hooks.
class_name EventsManager
extends Node

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
@warning_ignore("unused_signal")
signal chapter_triggered(chapter_name: String, style: int, duration: float, color: Color)

## Visual presentation styles for chapter title sequences.
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
	LIGHT_SWEEP
}

## Dictionary mapping available font identifier keys to their loaded [Font] resources.
var fonts: Dictionary[String, Font] = {}


## Lifecycle method initializing font mappings and connecting signal listeners.
func _ready() -> void:
	print("Events: _ready() called. Initializing font assets.")
	font_changed.connect(_on_font_changed)

	fonts["dyslexic"] = preload("res://assets/fonts/opendyslexic-0.92/OpenDyslexic-Regular.otf")
	fonts["papyrus"] = preload("res://assets/fonts/papyrus-font/papyrus.ttf")
	fonts["comic"] = preload("res://assets/fonts/Comic Sans MS.ttf")
	fonts["default"] = ThemeDB.fallback_font


## Replaces the project's root theme default font and updates 3D text nodes.
## [param font_name] The identifier key of the font to apply.
func _on_font_changed(font_name: String) -> void:
	print("Events: Changing global font to '", font_name, "'.")

	if fonts.has(font_name):
		var target_font: Font = fonts[font_name] as Font

		if ThemeDB.get_project_theme():
			ThemeDB.get_project_theme().default_font = target_font
		else:
			var root_window: Window = get_tree().root
			if not root_window.theme:
				root_window.theme = Theme.new()
			root_window.theme.default_font = target_font

		get_tree().call_group("3d_text", "set", "font", target_font)
	else:
		push_warning("Events: Attempted to set unknown font - " + font_name)
