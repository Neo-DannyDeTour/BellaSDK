extends Label


func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()

	text = "FPS: " + str(fps)

	if fps >= 60:
		set("theme_override_colors/font_color", Color.GREEN)
	elif fps >= 30:
		set("theme_override_colors/font_color", Color.YELLOW)
	else:
		set("theme_override_colors/font_color", Color.RED)
