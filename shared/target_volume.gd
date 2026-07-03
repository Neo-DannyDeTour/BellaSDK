@tool
extends Area3D
class_name TargetVolume

enum SpawnMode {
	TIME_BASED,
	WAIT_FOR_KILL
}

@export_category("Target Spawner")
@export var target_scene: PackedScene
@export var spawn_mode: SpawnMode = SpawnMode.TIME_BASED
@export var max_active_targets: int = 3
@export var pool_size: int = 10 
@export var spawn_interval_seconds: float = 2.0

@export_category("Volume Bounds")
@export var volume_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		volume_size = value
		_update_volume_size()

@export_category("Behavior")
@export var randomize_position_timer: float = 0.0

@onready var spawn_area: CollisionShape3D = $CollisionShape3D

var active_targets: Array[Node3D] = []
var inactive_targets: Array[Node3D] = []
var spawn_timer: float = 0.0
var jump_timer: float = 0.0


func _ready() -> void:
	# Ensure this volume NEVER blocks turret raycasts
	collision_layer = 0
	collision_mask = 0
	
	_update_volume_size()
	if Engine.is_editor_hint():
		return
		
	print("TargetVolume: _ready() - Volume initialized.")
	_initialize_pool()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	_handle_repositioning(delta)
	_handle_spawning(delta)


func _initialize_pool() -> void:
	print("TargetVolume: _initialize_pool() - Building target pool of size: ", pool_size)
	if target_scene == null:
		return
		
	for i in range(pool_size):
		var new_target: Node3D = target_scene.instantiate()
		get_parent().call_deferred("add_child", new_target)
		
		new_target.set_deferred("visible", false)
		new_target.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
		
		new_target.visibility_changed.connect(func() -> void: 
			if not new_target.visible:
				_on_target_disabled(new_target)
		)
		
		inactive_targets.append(new_target)


func _handle_repositioning(delta: float) -> void:
	if randomize_position_timer <= 0.0 or active_targets.is_empty():
		return
		
	jump_timer += delta
	if jump_timer >= randomize_position_timer:
		jump_timer = 0.0
		print("TargetVolume: _handle_repositioning() - Moving targets.")
		for t: Node3D in active_targets:
			if is_instance_valid(t):
				t.global_position = _get_random_position()


func _handle_spawning(delta: float) -> void:
	if spawn_mode == SpawnMode.TIME_BASED:
		spawn_timer += delta
		
		# Only try to spawn if we have room AND enough time has passed
		if active_targets.size() < max_active_targets and spawn_timer >= spawn_interval_seconds:
			_spawn_target()
			spawn_timer = 0.0
			
	elif spawn_mode == SpawnMode.WAIT_FOR_KILL:
		# Instantly replaces missing targets every frame
		if active_targets.size() < max_active_targets:
			_spawn_target()


func _update_volume_size() -> void:
	if not is_inside_tree():
		return
		
	if spawn_area == null:
		spawn_area = get_node_or_null("CollisionShape3D")
		
	if spawn_area != null:
		if spawn_area.shape == null or not spawn_area.shape is BoxShape3D:
			spawn_area.shape = BoxShape3D.new()
		(spawn_area.shape as BoxShape3D).size = volume_size
		
	var visualizer: Node3D = get_node_or_null("MeshInstance3D")
	if visualizer != null and "trigger_size" in visualizer:
		visualizer.trigger_size = volume_size


func _get_random_position() -> Vector3:
	var extents: Vector3 = volume_size / 2.0
	var rand_x: float = randf_range(-extents.x, extents.x)
	var rand_y: float = randf_range(-extents.y, extents.y)
	var rand_z: float = randf_range(-extents.z, extents.z)
	
	var local_spawn_pos: Vector3 = Vector3(rand_x, rand_y, rand_z)
	return global_transform * local_spawn_pos


func _spawn_target() -> void:
	if inactive_targets.is_empty():
		return
		
	var global_spawn_pos: Vector3 = _get_random_position()
	var target: Node3D = inactive_targets.pop_back()
	
	target.global_position = global_spawn_pos
	target.visible = true
	target.process_mode = Node.PROCESS_MODE_INHERIT
	
	if target.has_method("reset"):
		target.reset()
	else:
		var health_comp: Node = target.find_child("HealthComponent", true, false)
		if health_comp != null and health_comp.has_method("reset"):
			health_comp.reset()
	
	active_targets.append(target)
	print("TargetVolume: _spawn_target() - Spawned from pool at ", global_spawn_pos)


func _on_target_disabled(target_node: Node3D) -> void:
	if active_targets.has(target_node):
		active_targets.erase(target_node)
		inactive_targets.append(target_node)
		print("TargetVolume: _on_target_disabled() - Returned to pool.")
