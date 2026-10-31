## A UI label that displays the current frames per second (FPS).
##
## Changes text color dynamically based on framerate performance at a throttled rate.
class_name FpsCounter
extends Label

## Update interval in seconds (4 Hz) to throttle string churn and canvas redraws.
const UPDATE_INTERVAL: float = 0.25

## Accumulator timer tracking time elapsed since last UI text update.
var _timer: float = 0.0


## Called every frame by the engine; updates label text and color at throttled intervals.
func _process(delta: float) -> void:
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0

	var fps: float = Engine.get_frames_per_second()
	text = "FPS: %d" % int(roundf(fps))

	if fps >= 60.0:
		add_theme_color_override(&"font_color", Color.GREEN)
	elif fps >= 30.0:
		add_theme_color_override(&"font_color", Color.YELLOW)
	else:
		add_theme_color_override(&"font_color", Color.RED)
