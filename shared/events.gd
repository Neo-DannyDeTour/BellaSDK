extends Node

@warning_ignore("unused_signal")
signal noclip_toggled(is_flying: bool)

@warning_ignore("unused_signal")
signal noclip_ui_button_pressed

@warning_ignore("unused_signal")
signal noclip_speed_changed(speed: float)

@warning_ignore("unused_signal")
signal fullbright_toggled(is_fullbright: bool)

@warning_ignore("unused_signal")
signal wireframe_toggled(is_on: bool)

@warning_ignore("unused_signal")
signal wireframe_overlay_toggled(is_overlay: bool)

@warning_ignore("unused_signal")
signal debug_menu_toggled(is_open: bool)

@warning_ignore("unused_signal")
signal player_zoomed(is_zooming: bool)

@warning_ignore("unused_signal")
signal player_crouch_changed(is_crouching: bool)

@warning_ignore("unused_signal")
signal terminal_mode_toggled(is_active: bool)

@warning_ignore("unused_signal")
signal photosensitivity_mode_toggled(is_active: bool)

@warning_ignore("unused_signal")
signal subtitles_toggled(is_active: bool)

@warning_ignore("unused_signal")
signal dyslexic_font_toggled(is_active: bool)

@warning_ignore("unused_signal")
signal player_health_changed(new_health: int)

@warning_ignore("unused_signal")
signal screenshake_requested(intensity: float, duration: float)

# --- NEW COLORBLIND SIGNAL ---
@warning_ignore("unused_signal")
signal colorblind_mode_changed(mode: int)


# --- INTERACTION LIFECYCLE SIGNALS ---
@warning_ignore("unused_signal")
signal item_picked_up(item: Node3D, actor: Node3D)

@warning_ignore("unused_signal")
signal item_dropped(item: Node3D, actor: Node3D)

@warning_ignore("unused_signal")
signal keycard_collected(card_id: String)

@warning_ignore("unused_signal")
signal level_event_triggered(event_name: String, is_active: bool)

# --- REPLACED FONT SIGNAL ---
signal font_changed(font_name: String)

# --- FONT SWAPPING LOGIC ---
var fonts: Dictionary[String, Font] = {}

# --- CHAPTER TEXT ANIMATIONS ---
@warning_ignore("unused_signal")
signal chapter_triggered(chapter_name: String, style: int, duration: float, color: Color)

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


func _ready() -> void:
	font_changed.connect(_on_font_changed)

	# Load all your fonts into the dictionary.
	# CRITICAL: Make sure these file extensions and paths match your actual files!
	fonts["dyslexic"] = preload("res://assets/fonts/opendyslexic-0.92/OpenDyslexic-Regular.otf")
	fonts["papyrus"] = preload("res://assets/fonts/papyrus-font/papyrus.ttf")
	fonts["comic"] = preload("res://assets/fonts/Comic Sans MS.ttf")

	# Save Godot's built-in font as "default" so you can always go back
	fonts["default"] = ThemeDB.fallback_font


func _on_font_changed(font_name: String) -> void:
	print("Events: Changing global font to '", font_name, "'.")
	
	if fonts.has(font_name):
		var target_font: Font = fonts[font_name] as Font

		# 1. Update the actual default font for the UI
		if ThemeDB.get_project_theme():
			# If you have a custom theme set in Project Settings, update it
			ThemeDB.get_project_theme().default_font = target_font
		else:
			# Otherwise, apply a new theme override directly to the root window
			var root_window: Window = get_tree().root
			if not root_window.theme:
				root_window.theme = Theme.new()
			root_window.theme.default_font = target_font

		# 2. Update all 3D Text in the world
		get_tree().call_group("3d_text", "set", "font", target_font)
	else:
		push_warning("Events: Attempted to set unknown font - ", font_name)
