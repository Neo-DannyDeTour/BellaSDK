extends ColorRect

var history: Array[float] = []
var max_points: int = 100 # How many frames to draw across the screen
var target_ms: float = 16.67 # 60 FPS target
var ceiling_ms: float = 33.33 # 30 FPS ceiling (the top of the graph)

# NEW: Padding to push the top of the graph down, leaving room for text
var top_padding: float = 150.0 

func _process(delta: float) -> void:
	# PERFORMANCE: Don't do math if the debug menu is closed
	if not is_visible_in_tree(): 
		return

	# Convert delta (seconds) to milliseconds
	history.append(delta * 1000.0) 
	
	# Keep the array at our max size
	if history.size() > max_points:
		history.pop_front()

	# Tell Godot to trigger _draw() this frame
	queue_redraw()

func _draw() -> void:
	# Don't try to draw a shape if we don't have enough points
	if history.size() < 2: 
		return
		
	var w := size.x
	var h := size.y
	
	# The actual vertical space we are allowed to draw in
	var graph_h := h - top_padding
	var step := w / max_points

	# 1. DRAW THE GRAPH LINE (Segment by Segment for color changing)
	for i in range(history.size() - 1):
		var x1 := i * step
		var x2 := (i + 1) * step
		
		var ms1: float = min(history[i], ceiling_ms)
		var ms2: float = min(history[i + 1], ceiling_ms)
		
		# Calculate Y starting from the bottom (h) and going up
		var y1: float = h - (ms1 / ceiling_ms) * graph_h
		var y2: float = h - (ms2 / ceiling_ms) * graph_h
		
		var p1 := Vector2(x1, y1)
		var p2 := Vector2(x2, y2)
		
		# If the frame exceeds target_ms, draw this segment RED. Otherwise GREEN.
		var line_color := Color(0.2, 0.8, 0.2, 0.8) # Green
		if ms2 > target_ms or ms1 > target_ms:
			line_color = Color(0.9, 0.2, 0.2, 0.8) # Red Spike
			
		# Draw the individual segment
		draw_line(p1, p2, line_color, 2.0, true)

	# 2. DRAW THE YELLOW 60 FPS LINE
	var target_y := h - (target_ms / ceiling_ms) * graph_h
	draw_line(Vector2(0, target_y), Vector2(w, target_y), Color(1, 1, 0, 0.6), 2.0)

	# 3. DRAW THE TEXT STATUS
	var latest_ms: float = history.back() if not history.is_empty() else 0.0
	var font := ThemeDB.fallback_font 
	var text_color := Color.GREEN
	var status_text := "16.66ms - Good"

	if latest_ms > target_ms:
		text_color = Color.RED
		status_text = "16.66ms - Problem!"

	# Draw the text 5 pixels from the left, and 5 pixels above the yellow line
	var text_pos := Vector2(5, target_y - 5)

	# syntax: font, position, text, alignment, max_width, font_size, color
	draw_string(font, text_pos, status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)
