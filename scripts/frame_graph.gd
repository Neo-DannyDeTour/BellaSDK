extends ColorRect

var history: Array[float] = []
var max_points: int = 100
var target_ms: float = 16.67
var ceiling_ms: float = 33.33

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return

	history.append(delta * 1000.0)

	if history.size() > max_points:
		history.pop_front()

	queue_redraw()

func _draw() -> void:
	if history.size() < 2:
		return

	var w := size.x
	var h := size.y
	var step := w / max_points

	# 1. DRAW THE GRAPH LINE
	for i in range(history.size() - 1):
		var x1 := i * step
		var x2 := (i + 1) * step

		var ms1: float = min(history[i], ceiling_ms)
		var ms2: float = min(history[i + 1], ceiling_ms)

		# Calculate Y starting from the bottom (h) and going up
		var y1: float = h - (ms1 / ceiling_ms) * h
		var y2: float = h - (ms2 / ceiling_ms) * h

		var p1 := Vector2(x1, y1)
		var p2 := Vector2(x2, y2)

		var line_color := Color(0.2, 0.8, 0.2, 0.8)
		if ms2 > target_ms or ms1 > target_ms:
			line_color = Color(0.9, 0.2, 0.2, 0.8)

		draw_line(p1, p2, line_color, 2.0, true)

	# 2. DRAW THE YELLOW 60 FPS TARGET LINE
	var target_y := h - (target_ms / ceiling_ms) * h
	draw_line(Vector2(0, target_y), Vector2(w, target_y), Color(1, 1, 0, 0.6), 2.0)

	# 3. DRAW THE TEXT STATUS
	var latest_ms: float = history.back() if not history.is_empty() else 0.0
	var font := ThemeDB.fallback_font
	var text_color := Color.GREEN
	var status_text := "16.66ms - Good"

	if latest_ms > target_ms:
		text_color = Color.RED
		status_text = "16.66ms - Problem!"

	var text_pos := Vector2(5, target_y - 5)
	draw_string(font, text_pos, status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)	
