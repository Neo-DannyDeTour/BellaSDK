## Responsive [GridContainer] adjusting column count based on available width.
@tool
extends GridContainer

## Maximum number of columns allowed when expanding horizontally.
@export var target_column_count: int = 1

## Minimum pixel width required per column before wrapping.
@export var minimum_column_size: float = 100.0


## Connects the [signal resized] callback when entering the scene tree.
func _enter_tree() -> void:
	if not resized.is_connected(on_size_change):
		resized.connect(on_size_change)


## Recalculates [member GridContainer.columns] when the container width changes.
func on_size_change() -> void:
	if target_column_count <= 0:
		target_column_count = 1

	var safe_min_size: float = maxf(minimum_column_size, 1.0)
	var new_column_count: int = clampi(
		int(floorf(size.x / safe_min_size)), 1, target_column_count
	)
	columns = new_column_count
