@tool
extends Node3D
class_name RookTrap

enum State { IDLE, ATTACKING, RETURNING }

@export var attack_speed: float = 25.0
@export var return_speed: float = 5.0
@export var damage_amount: int = 20
@export var knockback_force: float = 15.0
@export var track_y_offset: float = -0.48

@export var markers: Array[Marker3D] = []:
	set(value):
		markers = value
		if is_node_ready():
			_draw_path_lines()

var _state: State = State.IDLE
var _origin_position: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO

@onready var moving_body: AnimatableBody3D = $MovingBody
@onready var player_hitbox: Area3D = $MovingBody/PlayerHitbox
@onready var path_lines_container: Node3D = $PathLines


func _ready() -> void:
	print("RookTrap: _ready() - Initializing trap.")
	
	if moving_body:
		_origin_position = moving_body.global_position
		
	_draw_path_lines()
	
	if not Engine.is_editor_hint():
		_setup_trigger_areas()
		if player_hitbox and not player_hitbox.body_entered.is_connected(_on_player_hitbox_body_entered):
			player_hitbox.body_entered.connect(_on_player_hitbox_body_entered)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _state == State.IDLE:
		return
		
	var current_pos: Vector3 = moving_body.global_position
	var direction: Vector3
	var distance_to_target: float
	var move_step: float
	
	if _state == State.ATTACKING:
		direction = current_pos.direction_to(_target_position)
		distance_to_target = current_pos.distance_to(_target_position)
		move_step = attack_speed * delta
		
		if distance_to_target <= move_step:
			moving_body.global_position = _target_position
			_state = State.RETURNING
			print("RookTrap: Reached target. Returning slowly.")
		else:
			moving_body.global_position += direction * move_step
			
	elif _state == State.RETURNING:
		direction = current_pos.direction_to(_origin_position)
		distance_to_target = current_pos.distance_to(_origin_position)
		move_step = return_speed * delta
		
		if distance_to_target <= move_step:
			moving_body.global_position = _origin_position
			_state = State.IDLE
			print("RookTrap: Returned to origin. Awaiting input.")
		else:
			moving_body.global_position += direction * move_step


func trigger_trap(marker_index: int) -> void:
	print("RookTrap: trigger_trap() called with index ", marker_index)
	if _state != State.IDLE:
		print("RookTrap: Ignored trigger - trap is currently moving.")
		return
		
	if marker_index < 0 or marker_index >= markers.size():
		push_warning("RookTrap: Invalid marker index provided.")
		return
		
	if markers[marker_index] != null:
		_target_position = markers[marker_index].global_position
		_state = State.ATTACKING
		print("RookTrap: Activated! Rushing toward marker ", marker_index)
		_check_immediate_overlap()


func _check_immediate_overlap() -> void:
	print("RookTrap: _check_immediate_overlap() - Checking for already overlapping bodies.")
	if not player_hitbox:
		return
		
	var overlapping_bodies: Array[Node3D] = player_hitbox.get_overlapping_bodies()
	for body in overlapping_bodies:
		_on_player_hitbox_body_entered(body)


func _draw_path_lines() -> void:
	print("RookTrap: _draw_path_lines() - Generating flat track meshes.")
	if not path_lines_container:
		return
		
	for child in path_lines_container.get_children():
		child.queue_free()
		
	for marker in markers:
		if marker == null:
			continue
			
		var mesh_instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		var mat := StandardMaterial3D.new()
		
		mat.albedo_color = Color.BLACK
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box_mesh.material = mat
		
		var start_pos: Vector3 = _origin_position if _origin_position != Vector3.ZERO else global_position
		
		# Lock the Y axis to the start position + track offset to ensure it's perfectly flat
		var flat_start := Vector3(start_pos.x, start_pos.y + track_y_offset, start_pos.z)
		var flat_marker := Vector3(marker.global_position.x, flat_start.y, marker.global_position.z)
		
		var dist: float = flat_start.distance_to(flat_marker)
		
		box_mesh.size = Vector3(0.2, 0.05, dist) 
		mesh_instance.mesh = box_mesh
		path_lines_container.add_child(mesh_instance)
		
		mesh_instance.global_position = flat_start.lerp(flat_marker, 0.5)
		
		# Prevent look_at errors if the marker is exactly on top of the origin
		if not flat_start.is_equal_approx(flat_marker):
			mesh_instance.look_at(flat_marker, Vector3.UP)


func _setup_trigger_areas() -> void:
	print("RookTrap: _setup_trigger_areas() - Creating flat player detection zones.")
	for i in range(markers.size()):
		var marker: Marker3D = markers[i]
		if marker == null:
			continue

		var trigger_area := Area3D.new()
		trigger_area.collision_layer = 0
		trigger_area.collision_mask = 2 # Player mask

		var coll_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		
		var start_pos: Vector3 = _origin_position if _origin_position != Vector3.ZERO else global_position
		
		# Flatten trigger areas exactly like the track meshes
		var flat_start := Vector3(start_pos.x, start_pos.y + track_y_offset, start_pos.z)
		var flat_marker := Vector3(marker.global_position.x, flat_start.y, marker.global_position.z)
		
		var dist: float = flat_start.distance_to(flat_marker)
		
		# Size the trigger box to catch the player (0.8m wide, 2.0m tall, length of path)
		box.size = Vector3(0.8, 2.0, dist)
		coll_shape.shape = box
		
		trigger_area.add_child(coll_shape)
		add_child(trigger_area)
		
		# Center and rotate the Area3D along the flat path
		trigger_area.global_position = flat_start.lerp(flat_marker, 0.5)
		if not flat_start.is_equal_approx(flat_marker):
			trigger_area.look_at(flat_marker, Vector3.UP)
		
		trigger_area.body_entered.connect(func(body: Node3D) -> void:
			if body.is_in_group("player"):
				print("RookTrap: Player entered detection zone ", i)
				trigger_trap(i)
		)


func _on_player_hitbox_body_entered(body: Node3D) -> void:
	# Only hurt/push the player if the trap is actively rushing forward
	if _state != State.ATTACKING:
		return
		
	if body.is_in_group("player"):
		print("RookTrap: Player hit while attacking! Applying damage and knockback.")
		
		if body.has_node("HealthComponent"):
			var health: Node = body.get_node("HealthComponent")
			if health.has_method("take_damage"):
				health.take_damage(damage_amount)
		elif body.has_method("take_damage"):
			body.take_damage(damage_amount)
			
		if body.has_method("apply_knockback"):
			var push_dir: Vector3 = global_position.direction_to(body.global_position)
			push_dir.y = 0.5 
			push_dir = push_dir.normalized()
			
			var force: Vector3 = push_dir * knockback_force
			body.apply_knockback(force)
