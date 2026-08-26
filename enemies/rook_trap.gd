@tool
## A dynamic trap entity that quickly attacks players crossing its generated paths.
##
## [RookTrap] watches dynamically generated straight-line triggers pointing towards
## an array of connected [Marker3D] nodes. When the player crosses a line, the body
## rapidly slides toward that marker, then slowly returns to its origin position.
class_name RookTrap
extends Node3D

## Defines the sequential operational phases of the moving trap body.
enum State { IDLE, ATTACKING, RETURNING }

## Speed in meters per second during the forward attack rush.
@export var attack_speed: float = 25.0

## Speed in meters per second while returning to the starting position.
@export var return_speed: float = 5.0

## Amount of health points deducted from the player on impact.
@export var damage_amount: int = 20

## The impulse force magnitude applied to the player on collision.
@export var knockback_force: float = 15.0

## The vertical offset used to draw the black track lines flush with the floor.
@export var track_y_offset: float = -0.48

## Array of destination points. The trap will generate paths and triggers toward these nodes.
@export var markers: Array[Marker3D] = []:
	set(value):
		markers = value
		if is_inside_tree() and Engine.is_editor_hint():
			_draw_path_lines()

## Tracks the current operational phase of the trap.
var _state: State = State.IDLE

## The cached starting position of the moving body.
var _origin_position: Vector3 = Vector3.ZERO

## The current destination marker's global position.
var _target_position: Vector3 = Vector3.ZERO

## The kinematic body representing the physical moving part of the trap.
@onready var moving_body: AnimatableBody3D = $MovingBody

## The trigger volume attached to the moving body responsible for dealing damage.
@onready var player_hitbox: Area3D = $MovingBody/PlayerHitbox

## The container node where dynamically generated black track meshes are placed.
@onready var path_lines_container: Node3D = $PathLines


## Initializes the trap, saving the origin position and dynamically building triggers.
func _ready() -> void:
	if is_instance_valid(moving_body):
		_origin_position = moving_body.global_position

	_draw_path_lines()

	if not Engine.is_editor_hint():
		_setup_trigger_areas()
		if (
			is_instance_valid(player_hitbox)
			and not player_hitbox.body_entered.is_connected(_on_player_hitbox_body_entered)
		):
			player_hitbox.body_entered.connect(_on_player_hitbox_body_entered)


## Processes the movement interpolation based on the current active state.
## [param delta] The physics step duration in seconds.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _state == State.IDLE or not is_instance_valid(moving_body):
		return

	var current_pos: Vector3 = moving_body.global_position
	var direction: Vector3
	var dist_sq: float
	var move_step: float
	var move_step_sq: float

	if _state == State.ATTACKING:
		direction = current_pos.direction_to(_target_position)
		dist_sq = current_pos.distance_squared_to(_target_position)
		move_step = attack_speed * delta
		move_step_sq = move_step * move_step

		if dist_sq <= move_step_sq:
			moving_body.global_position = _target_position
			_state = State.RETURNING
			print("RookTrap: Reached target. Returning slowly.")
		else:
			moving_body.global_position += direction * move_step

	elif _state == State.RETURNING:
		direction = current_pos.direction_to(_origin_position)
		dist_sq = current_pos.distance_squared_to(_origin_position)
		move_step = return_speed * delta
		move_step_sq = move_step * move_step

		if dist_sq <= move_step_sq:
			moving_body.global_position = _origin_position
			_state = State.IDLE
			print("RookTrap: Returned to origin. Awaiting input.")
		else:
			moving_body.global_position += direction * move_step


## Manually triggers the trap to rush toward a specific marker in the array.
## [param marker_index] The zero-based array index of the target [Marker3D].
func trigger_trap(marker_index: int) -> void:
	print("RookTrap: trigger_trap() called with index ", marker_index)
	if _state != State.IDLE:
		print("RookTrap: Ignored trigger - trap is currently moving.")
		return

	if marker_index < 0 or marker_index >= markers.size():
		push_warning("RookTrap: Invalid marker index provided.")
		return

	if is_instance_valid(markers[marker_index]):
		_target_position = markers[marker_index].global_position
		_state = State.ATTACKING
		print("RookTrap: Activated! Rushing toward marker ", marker_index)
		_check_immediate_overlap()


## Checks if the player is already touching the trap body when it first activates.
func _check_immediate_overlap() -> void:
	print("RookTrap: _check_immediate_overlap() - Checking for already overlapping bodies.")
	if not is_instance_valid(player_hitbox):
		return

	var overlapping_bodies: Array[Node3D] = player_hitbox.get_overlapping_bodies()
	for body: Variant in overlapping_bodies:
		_on_player_hitbox_body_entered(body as Node3D)


## Dynamically generates flat black mesh boxes representing the floor tracks.
func _draw_path_lines() -> void:
	print("RookTrap: _draw_path_lines() - Generating flat track meshes.")
	if not is_instance_valid(path_lines_container):
		return

	for child: Node in path_lines_container.get_children():
		child.queue_free()

	for marker: Marker3D in markers:
		if not is_instance_valid(marker):
			continue

		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		var box_mesh: BoxMesh = BoxMesh.new()
		var mat: StandardMaterial3D = StandardMaterial3D.new()

		mat.albedo_color = Color.BLACK
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box_mesh.material = mat

		var start_pos: Vector3 = (
			_origin_position if _origin_position != Vector3.ZERO else global_position
		)

		var flat_start: Vector3 = Vector3(start_pos.x, start_pos.y + track_y_offset, start_pos.z)
		var flat_marker: Vector3 = Vector3(
			marker.global_position.x, flat_start.y, marker.global_position.z
		)

		var dist: float = flat_start.distance_to(flat_marker)

		box_mesh.size = Vector3(0.2, 0.05, dist)
		mesh_instance.mesh = box_mesh
		path_lines_container.add_child(mesh_instance)

		mesh_instance.global_position = flat_start.lerp(flat_marker, 0.5)

		if not flat_start.is_equal_approx(flat_marker):
			mesh_instance.look_at(flat_marker, Vector3.UP)


## Dynamically generates physics areas along the track lines to detect player crossings.
func _setup_trigger_areas() -> void:
	print("RookTrap: _setup_trigger_areas() - Creating flat player detection zones.")
	for i: int in range(markers.size()):
		var marker: Marker3D = markers[i]
		if not is_instance_valid(marker):
			continue

		var trigger_area: Area3D = Area3D.new()
		trigger_area.collision_layer = 0
		trigger_area.collision_mask = 2

		var coll_shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()

		var start_pos: Vector3 = (
			_origin_position if _origin_position != Vector3.ZERO else global_position
		)

		var flat_start: Vector3 = Vector3(start_pos.x, start_pos.y + track_y_offset, start_pos.z)
		var flat_marker: Vector3 = Vector3(
			marker.global_position.x, flat_start.y, marker.global_position.z
		)

		var dist: float = flat_start.distance_to(flat_marker)

		box.size = Vector3(0.8, 2.0, dist)
		coll_shape.shape = box

		trigger_area.add_child(coll_shape)
		add_child(trigger_area)

		trigger_area.global_position = flat_start.lerp(flat_marker, 0.5)
		if not flat_start.is_equal_approx(flat_marker):
			trigger_area.look_at(flat_marker, Vector3.UP)

		trigger_area.body_entered.connect(
			func(body: Node3D) -> void:
				if body.is_in_group("player"):
					print("RookTrap: Player entered detection zone ", i)
					trigger_trap(i)
		)


## Deals damage and applies knockback when the moving body impacts the player.
## [param body] The [Node3D] struck by the trap's hitbox.
func _on_player_hitbox_body_entered(body: Node3D) -> void:
	if _state != State.ATTACKING:
		return

	if body.is_in_group("player"):
		print("RookTrap: Player hit while attacking! Applying damage and knockback.")

		if body.has_node("HealthComponent"):
			var health: Node = body.get_node("HealthComponent")
			if health.has_method("take_damage"):
				health.call("take_damage", damage_amount)
		elif body.has_method("take_damage"):
			body.call("take_damage", damage_amount)

		if body.has_method("apply_knockback"):
			var push_dir: Vector3 = global_position.direction_to(body.global_position)
			push_dir.y = 0.5
			push_dir = push_dir.normalized()

			var force: Vector3 = push_dir * knockback_force
			body.call("apply_knockback", force)
