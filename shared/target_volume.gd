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

@export_category("Spawn Limits")
@export var spawn_infinitely: bool = true
@export var total_targets_to_spawn: int = 10

@export_category("Volume Bounds")
@export var volume_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		volume_size = value
		_update_volume_size()
		_update_visualizer()

@export_category("Behavior")
@export var randomize_position_timer: float = 0.0

@export_category("Visualizer Controls")
@export var visualizer_shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		visualizer_shape_type = value
		_update_visualizer()

@export var visualizer_color: Color = Color(0.9, 0.5, 0.1, 0.4):
	set(value):
		visualizer_color = value
		_update_visualizer()

@export var visualizer_text: String = "TRIGGER":
	set(value):
		visualizer_text = value
		_update_visualizer()

@export var show_visualizer_in_game: bool = false:
	set(value):
		show_visualizer_in_game = value
		_update_visualizer()

@onready var spawn_area: CollisionShape3D = $CollisionShape3D

var active_targets: Array[Node3D] = []
var inactive_targets: Array[Node3D] = []
var spawn_timer: float = 0.0
var jump_timer: float = 0.0
var targets_spawned_so_far: int = 0


func _ready() -> void:
	# Ensure this volume NEVER blocks turret raycasts
	collision_layer = 0
	collision_mask = 0
	
	_update_volume_size()
	_update_visualizer()
	
	if Engine.is_editor_hint():
		return
		
	print("TargetVolume: _ready() - Volume initialized.")
	# Initialize the spawn timer so the first wave spawns instantly
	spawn_timer = spawn_interval_seconds
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
		
	for i: int in range(pool_size):
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
	# Check if we have hit our maximum spawn limit
	if not spawn_infinitely and targets_spawned_so_far >= total_targets_to_spawn:
		if active_targets.is_empty():
			print("TargetVolume: All targets depleted. Shutting down volume.")
			set_process(false)
		return

	if spawn_mode == SpawnMode.TIME_BASED:
		spawn_timer += delta
		
		if spawn_timer >= spawn_interval_seconds:
			spawn_timer = 0.0
			print("TargetVolume: Interval reached. Cycling TIME_BASED targets.")
			
			# 1. Despawn current targets (make them disappear)
			# We duplicate the array to safely modify the original while looping
			var targets_to_disable: Array[Node3D] = active_targets.duplicate()
			for t: Node3D in targets_to_disable:
				if is_instance_valid(t):
					t.visible = false 
			
			# 2. Determine how many new ones we are allowed to spawn
			var spawn_count: int = max_active_targets
			if not spawn_infinitely:
				var remaining: int = total_targets_to_spawn - targets_spawned_so_far
				spawn_count = mini(spawn_count, remaining)
				
			# 3. Spawn the new wave
			for i: int in range(spawn_count):
				_spawn_target()
				
	elif spawn_mode == SpawnMode.WAIT_FOR_KILL:
		# Instantly replaces missing targets in a single frame using a while loop
		while active_targets.size() < max_active_targets:
			if not spawn_infinitely and targets_spawned_so_far >= total_targets_to_spawn:
				break # Stop filling if we hit the hard limit
			_spawn_target()


func _update_volume_size() -> void:
	if not is_inside_tree():
		return
		
	if spawn_area == null:
		spawn_area = get_node_or_null("CollisionShape3D") as CollisionShape3D
		
	if spawn_area != null:
		if spawn_area.shape == null or not spawn_area.shape is BoxShape3D:
			spawn_area.shape = BoxShape3D.new()
		(spawn_area.shape as BoxShape3D).size = volume_size


func _update_visualizer() -> void:
	if not is_inside_tree():
		return
		
	# Find the visualizer child dynamically rather than relying on a hardcoded name
	var visualizer: EditorTriggerVisualizer = null
	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			visualizer = child
			break
			
	if visualizer != null:
		visualizer.shape_type = visualizer_shape_type
		visualizer.trigger_size = volume_size
		visualizer.trigger_color = visualizer_color
		visualizer.trigger_text = visualizer_text
		visualizer.show_in_game = show_visualizer_in_game


func _get_random_position() -> Vector3:
	var extents: Vector3 = volume_size / 2.0
	var rand_x: float = randf_range(-extents.x, extents.x)
	var rand_y: float = randf_range(-extents.y, extents.y)
	var rand_z: float = randf_range(-extents.z, extents.z)
	
	var local_spawn_pos: Vector3 = Vector3(rand_x, rand_y, rand_z)
	return global_transform * local_spawn_pos


func _spawn_target() -> void:
	if inactive_targets.is_empty():
		print("TargetVolume: WARNING - Pool is empty! Increase pool_size.")
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
	targets_spawned_so_far += 1
	print("TargetVolume: Spawned target at ", global_spawn_pos, ". Total spawned: ", targets_spawned_so_far)


func _on_target_disabled(target_node: Node3D) -> void:
	if active_targets.has(target_node):
		active_targets.erase(target_node)
		inactive_targets.append(target_node)
		print("TargetVolume: Target returned to pool.")
