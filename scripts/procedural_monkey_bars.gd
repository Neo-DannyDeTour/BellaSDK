@tool
extends CSGBox3D
class_name MonkeyBarVolume

var interact_area: Area3D
var col_shape: CollisionShape3D


func _ready() -> void:
	add_to_group("monkey_bars")

	# Instantly hide the red box when the game actually starts
	if not Engine.is_editor_hint():
		visible = false

	# Generate the invisible catch-net below the box
	if not interact_area or not is_instance_valid(interact_area):
		interact_area = get_node_or_null("InteractArea") as Area3D
		if not interact_area:
			interact_area = Area3D.new()
			interact_area.name = "InteractArea"
			interact_area.collision_layer = 0
			interact_area.collision_mask = 2
			add_child(interact_area)

			col_shape = CollisionShape3D.new()
			col_shape.shape = BoxShape3D.new()
			interact_area.add_child(col_shape)

			interact_area.body_entered.connect(_on_body_entered)
			interact_area.body_exited.connect(_on_body_exited)

	_update_trigger_box()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_trigger_box()


func _update_trigger_box() -> void:
	if col_shape and col_shape.shape:
		var box := col_shape.shape as BoxShape3D
		# The trigger box is identical to your CSG box,
		#but extends 1.5m downward to catch the player's head
		box.size = Vector3(size.x, size.y + 1.5, size.z)
		col_shape.position.y = -0.75


func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	print("Monkey Bar Trigger touched by: ", body.name)  # Add this!

	if body.has_method("set_available_monkey_bar"):
		body.set_available_monkey_bar(self)


func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	# FIXED: Call the clear function so we don't accidentally grab thin air later!
	if body.has_method("clear_available_monkey_bar"):
		body.clear_available_monkey_bar(self)
