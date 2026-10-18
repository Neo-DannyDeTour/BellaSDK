@tool
## Procedural CSG volume generating an overhead monkey bar interaction zone.
class_name MonkeyBarVolume
extends CSGBox3D

## The [Area3D] node used to detect player entry for monkey bars.
var interact_area: Area3D

## The [CollisionShape3D] representing the interaction volume.
var col_shape: CollisionShape3D


## Initializes the interaction area and configures its collision properties.
func _ready() -> void:
	print("MonkeyBarVolume: Initializing interaction trigger volume.")
	add_to_group(&"monkey_bars")

	if not Engine.is_editor_hint():
		visible = false

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


## Updates the trigger box size dynamically in the editor when resized.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_trigger_box()


## Resizes the internal [CollisionShape3D] to extend below the CSG geometry.
func _update_trigger_box() -> void:
	if is_instance_valid(col_shape) and is_instance_valid(col_shape.shape):
		var box: BoxShape3D = col_shape.shape if col_shape.shape is BoxShape3D else null
		box.size = Vector3(size.x, size.y + 1.5, size.z)
		col_shape.position.y = -0.75


## Notifies the player that a monkey bar volume is available for grabbing.
func _on_body_entered(body: Node3D) -> void:
	print("MonkeyBarVolume: Body entered trigger -> ", body.name)
	if Engine.is_editor_hint():
		return

	var p: Player = body if body is Player else null
	if is_instance_valid(p):
		p.set_available_monkey_bar(self)


## Clears the player's available monkey bar reference upon exiting volume.
func _on_body_exited(body: Node3D) -> void:
	print("MonkeyBarVolume: Body exited trigger -> ", body.name)
	if Engine.is_editor_hint():
		return

	var p: Player = body if body is Player else null
	if is_instance_valid(p):
		p.clear_available_monkey_bar(self)
