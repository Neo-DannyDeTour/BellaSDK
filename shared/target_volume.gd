@tool
## Volume managing pooled target instantiation, proximity sleep, and spawn cycling.
## Integrates [EditorTriggerVisualizer] for in-editor wireframe and bounds display.
class_name TargetVolume
extends Area3D

## Defines target replenishment triggers based on time or elimination.
enum SpawnMode { TIME_BASED, WAIT_FOR_KILL }

## Alias for the editor trigger visualizer geometry type enum.
const SHAPE_TYPE: Variant = EditorTriggerVisualizer.ShapeType

@export_category("Target Spawner")

## The scene to instantiate and pool for targets.
@export var target_scene: PackedScene

## Determines if targets spawn based on a timer or only when previous targets are killed.
@export var spawn_mode: SpawnMode = SpawnMode.TIME_BASED

## The maximum number of targets allowed to be active at once in this volume.
@export var max_active_targets: int = 3

## Total target instances created at startup to recycle without runtime instantiation.
@export var pool_size: int = 10

## How long to wait before cycling or spawning new targets in TIME_BASED mode.
@export var spawn_interval_seconds: float = 2.0

@export_category("Spawn Limits")

## If true, ignores total_targets_to_spawn and keeps spawning targets infinitely.
@export var spawn_infinitely: bool = true

## The absolute maximum number of targets this volume will ever spawn if not infinite.
@export var total_targets_to_spawn: int = 10

@export_category("Volume Bounds")
## The shape drawn in the editor to represent the spawn volume.
@export var visualizer_shape_type: int = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		visualizer_shape_type = value
		if is_inside_tree():
			_update_visuals()

## The 3D boundaries defining the area where targets can spawn.
@export var volume_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		volume_size = value
		if is_inside_tree():
			_update_visuals()

## Local offset applied to both the collision shape and the visualizer node.
@export var volume_offset: Vector3 = Vector3.ZERO:
	set(value):
		volume_offset = value
		if is_inside_tree():
			_update_visuals()

@export_category("Visualizer Controls")

## Controls whether the visualizer mesh and label remain visible during gameplay.
@export var show_visualizer_in_game: bool = false:
	set(value):
		show_visualizer_in_game = value
		if is_inside_tree():
			_update_visuals()

## Base tint and opacity applied to the volumetric inner fill in the editor.
@export var visualizer_color: Color = Color(0.9, 0.5, 0.1, 0.25):
	set(value):
		visualizer_color = value
		if is_inside_tree():
			_update_visuals()

## Edge color applied to the wireframe bounding cage and orientation arrow.
@export var outline_color: Color = Color(1.0, 0.8, 0.3, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_visuals()

## Allows the visualizer to remain visible through walls and level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_visuals()

## Displays an arrow pointing along -Z indicating spawner orientation.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_visuals()

## Appends metric dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_visuals()

## The label shown on the visualizer in the editor.
@export var visualizer_text: String = "TARGET SPAWNER":
	set(value):
		visualizer_text = value
		if is_inside_tree():
			_update_visuals()

@export_category("Behavior")

## Distance in meters beyond which this volume halts target spawning.
@export var active_distance: float = 40.0

## If greater than zero, active targets will teleport to a new location on this interval.
@export var randomize_position_timer: float = 0.0

## Cached player instance for proximity checks.
var _player_ref: Node3D = null

## Proximity countdown timer.
var _dist_timer: float = 0.0

## Tracks if the spawner is dormant due to player distance.
var _is_dormant: bool = false

## A list of targets currently spawned and active in the world.
var active_targets: Array[Node3D] = []

## A list of pooled targets waiting to be spawned.
var inactive_targets: Array[Node3D] = []

## Tracks elapsed time for TIME_BASED spawning.
var spawn_timer: float = 0.0

## Tracks elapsed time for target repositioning.
var jump_timer: float = 0.0

## A running counter of how many targets have been spawned by this volume.
var targets_spawned_so_far: int = 0


## Initializes pool, sets collision layers, and synchronizes visual state.
func _ready() -> void:
	_update_visuals()
	if Engine.is_editor_hint():
		return

	var editor_mesh: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(editor_mesh) and not show_visualizer_in_game:
		print("TargetVolume: Removing editor visualizer for gameplay.")
		editor_mesh.queue_free()

	collision_layer = 0
	collision_mask = 0

	spawn_timer = spawn_interval_seconds
	_initialize_pool()


## Frame lifecycle method monitoring player proximity and managing spawns.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_dist_timer += delta
	if _dist_timer >= 0.5:
		_dist_timer = 0.0
		if not is_instance_valid(_player_ref):
			var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
			if not players.is_empty() and players[0] is Node3D:
				_player_ref = players[0] as Node3D

		if is_instance_valid(_player_ref):
			var p_pos: Vector3 = _player_ref.global_position
			var dist_sq: float = global_position.distance_squared_to(p_pos)
			_is_dormant = dist_sq > (active_distance * active_distance)

	if _is_dormant:
		return

	_handle_repositioning(delta)
	_handle_spawning(delta)


## Rebuilds collision shapes and visualizer meshes matching volume settings.
func _update_visuals() -> void:
	if not is_inside_tree():
		return

	var col: CollisionShape3D = _get_collision_shape()
	if is_instance_valid(col):
		if visualizer_shape_type == EditorTriggerVisualizer.ShapeType.BOX:
			if not col.shape is BoxShape3D:
				col.shape = BoxShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			var box_shape: BoxShape3D = col.shape as BoxShape3D
			box_shape.size = volume_size
		elif visualizer_shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not col.shape is SphereShape3D:
				col.shape = SphereShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			var sphere_shape: SphereShape3D = col.shape as SphereShape3D
			sphere_shape.radius = volume_size.x * 0.5

		col.position = volume_offset

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(visual):
		visual.shape_type = visualizer_shape_type
		visual.trigger_size = volume_size
		visual.trigger_color = visualizer_color
		visual.outline_color = outline_color
		visual.x_ray_mode = x_ray_mode
		visual.show_orientation = show_orientation
		visual.show_metric_dimensions = show_metric_dimensions
		visual.trigger_text = visualizer_text
		visual.show_in_game = show_visualizer_in_game
		visual.position = volume_offset


## Safely resolves the child [CollisionShape3D] instance.
func _get_collision_shape() -> CollisionShape3D:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		for child: Node in get_children():
			if child is CollisionShape3D:
				return child as CollisionShape3D
	return col


## Safely retrieves the child [EditorTriggerVisualizer] node.
func _get_visualizer() -> EditorTriggerVisualizer:
	var visual: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visual):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
	return visual


## Pre-instantiates targets into the inactive pool.
func _initialize_pool() -> void:
	print("TargetVolume: _initialize_pool() - Pool size: ", pool_size)
	if target_scene == null:
		return

	for i: int in range(pool_size):
		var new_target: Node3D = target_scene.instantiate() as Node3D
		get_parent().call_deferred(&"add_child", new_target)

		new_target.set_deferred(&"visible", false)
		new_target.set_deferred(&"process_mode", Node.PROCESS_MODE_DISABLED)

		new_target.visibility_changed.connect(
			func() -> void:
				if not new_target.visible:
					_on_target_disabled(new_target)
		)

		inactive_targets.append(new_target)


## Periodically relocates active targets within the volume boundaries.
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


## Evaluates timers and target counts to deploy pooled targets.
func _handle_spawning(delta: float) -> void:
	var limit_hit: bool = not spawn_infinitely and targets_spawned_so_far >= total_targets_to_spawn
	if limit_hit:
		if active_targets.is_empty():
			print("TargetVolume: All targets depleted. Shutting down volume.")
			set_process(false)
		return

	if spawn_mode == SpawnMode.TIME_BASED:
		spawn_timer += delta

		if spawn_timer >= spawn_interval_seconds:
			spawn_timer = 0.0
			print("TargetVolume: Interval reached. Cycling TIME_BASED targets.")

			var targets_to_disable: Array[Node3D] = active_targets.duplicate()
			for t: Node3D in targets_to_disable:
				if is_instance_valid(t):
					t.visible = false

			var spawn_count: int = max_active_targets
			if not spawn_infinitely:
				var rem: int = total_targets_to_spawn - targets_spawned_so_far
				spawn_count = mini(spawn_count, rem)

			for i: int in range(spawn_count):
				_spawn_target()

	elif spawn_mode == SpawnMode.WAIT_FOR_KILL:
		while active_targets.size() < max_active_targets:
			var kill_limit: bool = (
				not spawn_infinitely and targets_spawned_so_far >= total_targets_to_spawn
			)
			if kill_limit:
				break
			_spawn_target()


## Calculates a randomized global point located inside the volume bounds.
func _get_random_position() -> Vector3:
	var local_spawn_pos: Vector3 = volume_offset
	if visualizer_shape_type == EditorTriggerVisualizer.ShapeType.BOX:
		var extents: Vector3 = volume_size * 0.5
		var rand_x: float = randf_range(-extents.x, extents.x)
		var rand_y: float = randf_range(-extents.y, extents.y)
		var rand_z: float = randf_range(-extents.z, extents.z)
		local_spawn_pos += Vector3(rand_x, rand_y, rand_z)
	elif visualizer_shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
		var radius: float = volume_size.x * 0.5
		var u: float = randf()
		var v: float = randf()
		var theta: float = u * TAU
		var phi: float = acos(2.0 * v - 1.0)
		var r: float = pow(randf(), 1.0 / 3.0) * radius
		var sin_phi: float = sin(phi)
		local_spawn_pos += Vector3(r * sin_phi * cos(theta), r * sin_phi * sin(theta), r * cos(phi))

	return global_transform * local_spawn_pos


## Retrieves an inactive target from the pool and deploys it to the world.
func _spawn_target() -> void:
	if inactive_targets.is_empty():
		print("TargetVolume: WARNING - Pool is empty! Increase pool_size.")
		return

	var global_spawn_pos: Vector3 = _get_random_position()
	var target: Node3D = inactive_targets.pop_back()

	target.global_position = global_spawn_pos
	target.visible = true
	target.process_mode = Node.PROCESS_MODE_INHERIT

	if target.has_method(&"reset"):
		target.call(&"reset")
	elif "health_component" in target:
		var health_comp: Node = target.get("health_component") as Node
		if is_instance_valid(health_comp) and health_comp.has_method(&"reset"):
			health_comp.call(&"reset")

	active_targets.append(target)
	targets_spawned_so_far += 1
	print(
		"TargetVolume: Spawned target at ",
		global_spawn_pos,
		". Total spawned: ",
		targets_spawned_so_far
	)


## Recycles an inactive target back into the object pool.
func _on_target_disabled(target_node: Node3D) -> void:
	if active_targets.has(target_node):
		active_targets.erase(target_node)
		inactive_targets.append(target_node)
		print("TargetVolume: Target returned to pool.")
