@tool
extends GridContainer
@export var target_column_count : int = 1
@export var minimum_column_size : float = 100.0
func _enter_tree() -> void:
	if (!self.resized.is_connected(on_size_change.bind())):
		self.resized.connect(on_size_change.bind())
func on_size_change() -> void:
	if (target_column_count <= 0):
		target_column_count = 0

	var width: Variant = size.x
	var new_column_count : int = clamp(floor(width / minimum_column_size), 1, target_column_count)
	columns = new_column_count
