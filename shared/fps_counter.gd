## A UI label that displays the current frames per second (FPS).
##
## Changes text color dynamically based on framerate performance.
class_name FpsCounter
extends Label


## Called every frame by the engine to update the text and color of the label.
##
## @param _delta The time elapsed since the previous frame. Not used in this script.
func _process(_delta: float) -> void:
	var fps: float = Engine.get_frames_per_second()

	text = "FPS: " + str(fps)

	if fps >= 60:
		set("theme_override_colors/font_color", Color.GREEN)
	elif fps >= 30:
		set("theme_override_colors/font_color", Color.YELLOW)
	else:
		set("theme_override_colors/font_color", Color.RED)
