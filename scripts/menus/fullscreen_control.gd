extends CheckBox


func _on_toggled(toggled_on: bool) -> void:
	var window := get_window()

	if toggled_on:
		# EXCLUSIVE mode forcibly bypasses the standard X11/Windows manager rules
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED

		# Snap the window back to our active internal resolution
		window.size = window.content_scale_size

		# Recenter it based on the current screen
		var current_screen: int = window.current_screen

		@warning_ignore("integer_division")
		var screen_center: Vector2i = (
			DisplayServer.screen_get_position(current_screen)
			+ (DisplayServer.screen_get_size(current_screen) / 2)
		)

		@warning_ignore("integer_division")
		window.position = screen_center - (window.size / 2)
