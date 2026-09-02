## An on-screen graph visualizing recent frame delta times.
##
## [FrameGraph] draws a line graph over time representing frame duration in milliseconds.
## It helps developers quickly identify stutters or drops below the target framerate.
class_name FrameGraph
extends ColorRect

## An array tracking recent frame times in milliseconds.
var history: Array[float] = []

## The maximum number of points to draw on the graph before dropping old frames.
var max_points: int = 100

## The target frame time in milliseconds (16.67ms = 60 FPS).
var target_ms: float = 16.67

## The maximum visible frame time on the Y-axis of the graph (33.33ms = 30 FPS).
var ceiling_ms: float = 33.33

## Pre-allocated line segment point buffer.
var _segment_points: PackedVector2Array = PackedVector2Array()

## Pre-allocated line segment color buffer.
var _segment_colors: PackedColorArray = PackedColorArray()


## Called every frame. Samples the frame time and forces a redraw if visible.
## [param delta] The time elapsed since the previous frame in seconds.
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	history.append(delta * 1000.0)
	if history.size() > max_points:
		history.pop_front()

	queue_redraw()


## Called when the node is forced to redraw. Paints the graph lines and threshold indicators.
func _draw() -> void:
	if history.size() < 2:
		return

	var w: float = size.x
	var h: float = size.y
	var step: float = w / float(max_points)

	_segment_points.clear()
	_segment_colors.clear()

	var green_color: Color = Color(0.2, 0.8, 0.2, 0.8)
	var red_color: Color = Color(0.9, 0.2, 0.2, 0.8)

	for i: int in range(history.size() - 1):
		var x1: float = float(i) * step
		var x2: float = float(i + 1) * step

		var ms1: float = min(history[i], ceiling_ms)
		var ms2: float = min(history[i + 1], ceiling_ms)

		var y1: float = h - (ms1 / ceiling_ms) * h
		var y2: float = h - (ms2 / ceiling_ms) * h

		# Each line segment consists of 2 points...
		_segment_points.append(Vector2(x1, y1))
		_segment_points.append(Vector2(x2, y2))

		# ...and exactly 1 color for that segment
		var segment_color: Color = (
			red_color if (ms2 > target_ms or ms1 > target_ms) else green_color
		)
		_segment_colors.append(segment_color)

	# 1. DRAW ALL GRAPH SEGMENTS IN A SINGLE BATCHED CALL
	draw_multiline_colors(_segment_points, _segment_colors, 2.0)

	# 2. DRAW THE YELLOW 60 FPS TARGET LINE
	var target_y: float = h - (target_ms / ceiling_ms) * h
	draw_line(Vector2(0, target_y), Vector2(w, target_y), Color(1, 1, 0, 0.6), 2.0)

	# 3. DRAW THE TEXT STATUS
	var latest_ms: float = history.back() if not history.is_empty() else 0.0
	var font: Font = ThemeDB.fallback_font
	var text_color: Color = Color.GREEN if latest_ms <= target_ms else Color.RED
	var status_text: String = "16.66ms - Good" if latest_ms <= target_ms else "16.66ms - Problem!"

	var text_pos: Vector2 = Vector2(5.0, target_y - 5.0)
	draw_string(font, text_pos, status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)
