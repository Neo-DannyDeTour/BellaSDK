extends Button

@export var hover_scale := Vector2(1.08, 1.08)
@export var max_rotation_degrees := 5.0  # Maximum tilt amount
@export var tilt_speed := 15.0  # How snappy it reacts to your mouse

var original_scale: Vector2
var is_hovered := false


func _ready() -> void:
	original_scale = scale
	pivot_offset = size / 2

	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	resized.connect(_on_resized)


func _on_resized() -> void:
	pivot_offset = size / 2


func _on_hover() -> void:
	is_hovered = true


func _on_unhover() -> void:
	is_hovered = false


func _process(delta: float) -> void:
	if is_hovered:
		# 1. Smoothly scale up
		scale = scale.lerp(hover_scale, tilt_speed * delta)

		# 2. Find where the mouse is inside the button
		var mouse_pos := get_local_mouse_position()
		var center_x := size.x / 2.0

		# 3. Create a ratio from -1.0 (far left) to 1.0 (far right)
		var normalized_x := (mouse_pos.x - center_x) / center_x
		normalized_x = clamp(normalized_x, -1.0, 1.0)

		# 4. Calculate target rotation
		# If mouse is left (-1), rotation is negative (lowers left side)
		# If mouse is right (1), rotation is positive (lowers right side)
		var target_rotation := deg_to_rad(max_rotation_degrees * normalized_x)

		# 5. Smoothly rotate towards the target
		rotation = lerpf(rotation, target_rotation, tilt_speed * delta)

	else:
		# Smoothly return everything to normal when the mouse leaves
		scale = scale.lerp(original_scale, tilt_speed * delta)
		rotation = lerpf(rotation, 0.0, tilt_speed * delta)
