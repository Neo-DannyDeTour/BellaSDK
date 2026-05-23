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

# --- REPLACED FONT SIGNAL ---
signal font_changed(font_name: String)

# --- FONT SWAPPING LOGIC ---
var fonts: Dictionary[String, Font] = {}


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
	if fonts.has(font_name):
		# We explicitly state this is a Font, and cast the dictionary item 'as Font'
		var target_font: Font = fonts[font_name] as Font

		# 1. Update all standard UI
		ThemeDB.fallback_font = target_font

		# 2. Update all 3D Text
		get_tree().call_group("3d_text", "set", "font", target_font)
