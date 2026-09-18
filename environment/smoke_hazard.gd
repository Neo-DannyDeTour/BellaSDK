## Autonomous pulsing hazard dealing damage via [HealthComponent] with visualizer sync.
@tool
class_name SmokeHazard
extends Area3D

## Emitted when an entity takes a tick of damage inside the smoke cloud.
signal damage_ticked(target: Node3D, amount: float)

@export_group("Hazard Damage & Timers")

## Base damage dealt per tick to bodies inside the smoke cloud.
@export var damage_per_tick: float = 5.0

## Time in seconds between consecutive damage ticks.
@export var tick_rate: float = 0.5

## Radius for particle distribution and fallback sphere collision.
@export var cloud_radius: float = 2.0:
	set(value):
		cloud_radius = value
		_update_cloud_bounds()
		_update_collision_and_visualizer()

## Time in seconds the hazard remains active and emitting.
@export var active_duration: float = 3.0

## Time in seconds the hazard pauses between active bursts.
@export var pause_duration: float = 2.0

## Enables environment raycast occlusion to stop damage through walls.
@export var check_wall_occlusion: bool = true

@export_group("Hazard Shape & Transform")

## Geometric shape displayed in the visualizer and synced to collision.
@export
var visualizer_shape: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		visualizer_shape = value
		_update_collision_and_visualizer()

## 3D dimensions of the hazard collision box and visualizer box.
@export var visualizer_size: Vector3 = Vector3(4.0, 4.0, 4.0):
	set(value):
		visualizer_size = value
		_update_collision_and_visualizer()

## 3D position offset for both collision shape and visualizer mesh.
@export var hazard_offset: Vector3 = Vector3.ZERO:
	set(value):
		hazard_offset = value
		_update_collision_and_visualizer()

## Toggles visibility of the debug trigger shape in runtime builds.
@export var show_visualizer_in_game: bool = false:
	set(value):
		show_visualizer_in_game = value
		_update_collision_and_visualizer()

## Color and transparency of the editor debug trigger shape.
@export var visualizer_color: Color = Color(0.9, 0.2, 0.1, 0.3):
	set(value):
		visualizer_color = value
		_update_collision_and_visualizer()

## Text label displayed on the editor debug shape.
@export var visualizer_text: String = "SMOKE HAZARD":
	set(value):
		visualizer_text = value
		_update_collision_and_visualizer()

@export_group("Particle Settings")

## Base tint applied to the smoke particles.
@export var smoke_color: Color = Color(0.9, 0.9, 0.9, 0.85):
	set(value):
		smoke_color = value
		_update_particle_visuals()

## Overall lifetime in seconds for individual smoke puffs.
@export var particle_lifetime: float = 2.0:
	set(value):
		particle_lifetime = maxf(0.1, value)
		_update_particle_lifetime()

## Overall velocity scaling factor for the emission system.
@export var particle_speed: float = 4.0:
	set(value):
		particle_speed = value
		_update_particle_velocity()

## Minimum initial upward ejection speed.
@export var velocity_min: float = 3.0:
	set(value):
		velocity_min = value
		_update_particle_velocity()

## Maximum initial upward ejection speed.
@export var velocity_max: float = 6.0:
	set(value):
		velocity_max = value
		_update_particle_velocity()

## Angle in degrees for the emission cone spread.
@export_range(0.0, 180.0) var spread: float = 25.0:
	set(value):
		spread = value
		_update_particle_velocity()

## Minimum randomized uniform scale multiplier.
@export var scale_min: float = 0.8:
	set(value):
		scale_min = value
		_update_particle_scale()

## Maximum randomized uniform scale multiplier.
@export var scale_max: float = 2.0:
	set(value):
		scale_max = value
		_update_particle_scale()

## Internal interval timer used to trigger damage cycles.
var _tick_timer: float = 0.0

## Tracks time spent in current active or paused phase.
var _phase_timer: float = 0.0

## Flag indicating whether hazard is actively venting smoke.
var _is_active: bool = true

## Cache of overlapping bodies currently inside the hazard radius.
var _targets_in_smoke: Array[Node3D] = []

## Direct reference to the collision shape node.
@onready
var _collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D

## Direct reference to the particle system node.
@onready var _particles: GPUParticles3D = get_node_or_null("SmokeParticles") as GPUParticles3D

## Direct reference to the trigger visualizer helper node.
@onready var _visualizer: EditorTriggerVisualizer = (
	get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
)


## Connects collision callbacks and synchronizes parameters on ready.
func _ready() -> void:
	print("SmokeHazard: Initialized at ", global_position)
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

	_update_collision_and_visualizer()
	_update_cloud_bounds()
	_update_particle_visuals()
	_update_particle_lifetime()
	_update_particle_velocity()
	_update_particle_scale()
	_set_hazard_state(true)
	_align_collision_to_base(_collision_shape)


## Advances cycle timers and handles damage ticks during active phases.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_phase_timer += delta

	if _is_active:
		if _phase_timer >= active_duration:
			_set_hazard_state(false)
			return

		if _targets_in_smoke.is_empty():
			_tick_timer = 0.0
			return

		_tick_timer += delta
		if _tick_timer >= tick_rate:
			_tick_timer -= tick_rate
			_apply_tick_damage()
	else:
		if _phase_timer >= pause_duration:
			_set_hazard_state(true)


## Registers entering bodies into the active targets list.
func _on_body_entered(body: Node3D) -> void:
	if not _targets_in_smoke.has(body):
		_targets_in_smoke.append(body)
		print("SmokeHazard: Target entered smoke -> ", body.name)


## Unregisters exiting bodies from the active targets list.
func _on_body_exited(body: Node3D) -> void:
	_targets_in_smoke.erase(body)
	print("SmokeHazard: Target exited smoke -> ", body.name)


## Applies periodic damage to targets having a valid [HealthComponent].
func _apply_tick_damage() -> void:
	print("SmokeHazard: Ticking damage on ", _targets_in_smoke.size(), " target(s).")
	for target: Node3D in _targets_in_smoke:
		if not is_instance_valid(target):
			continue

		if check_wall_occlusion and not _has_line_of_sight(target):
			print("SmokeHazard: Target occluded by wall -> ", target.name)
			continue

		var health: HealthComponent = _find_health_component(target)
		if is_instance_valid(health):
			print("SmokeHazard: Damaging HealthComponent on ", target.name)
			damage_ticked.emit(target, damage_per_tick)
			health.take_damage(int(roundf(damage_per_tick)))
		else:
			print("SmokeHazard: No HealthComponent found on target -> ", target.name)


## Validates clear line of sight avoiding floor clipping against Layer 1.
func _has_line_of_sight(target: Node3D) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = global_position + hazard_offset + Vector3(0.0, 0.5, 0.0)
	var end_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		start_pos, end_pos, 1
	)
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()


## Traverses node hierarchy to find [HealthComponent] on target or children.
func _find_health_component(target: Node) -> HealthComponent:
	if not is_instance_valid(target):
		return null

	if target is HealthComponent:
		return target as HealthComponent

	# Check children recursively
	for child: Node in target.find_children("*", "HealthComponent", true, false):
		if child is HealthComponent:
			return child as HealthComponent

	# Check parent hierarchy as fallback
	var curr_parent: Node = target.get_parent()
	while curr_parent != null:
		if curr_parent is HealthComponent:
			return curr_parent as HealthComponent
		for sibling: Node in curr_parent.get_children():
			if sibling is HealthComponent:
				return sibling as HealthComponent
		curr_parent = curr_parent.get_parent()

	return null


## Changes emission state while preserving body tracking and collision.
func _set_hazard_state(active: bool) -> void:
	_is_active = active
	_phase_timer = 0.0
	_tick_timer = 0.0
	print("SmokeHazard: State changed -> active = ", active)

	if not is_inside_tree():
		return

	var parts: GPUParticles3D = (
		_particles if is_instance_valid(_particles) else get_node_or_null("SmokeParticles")
		as GPUParticles3D
	)
	if is_instance_valid(parts):
		parts.emitting = active


## Updates collision shape and visualizer mesh in editor and runtime.
func _update_collision_and_visualizer() -> void:
	if not is_inside_tree():
		return

	var col: CollisionShape3D = (
		(
			_collision_shape
			if is_instance_valid(_collision_shape)
			else get_node_or_null("CollisionShape3D")
		)
		as CollisionShape3D
	)
	var vis: EditorTriggerVisualizer = (
		(
			_visualizer
			if is_instance_valid(_visualizer)
			else get_node_or_null("EditorTriggerVisualizer")
		)
		as EditorTriggerVisualizer
	)

	# Update Collision
	if is_instance_valid(col):
		col.position = hazard_offset
		if visualizer_shape == EditorTriggerVisualizer.ShapeType.BOX:
			if not col.shape is BoxShape3D:
				col.shape = BoxShape3D.new()
			(col.shape as BoxShape3D).size = visualizer_size
		elif visualizer_shape == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not col.shape is SphereShape3D:
				col.shape = SphereShape3D.new()
			(col.shape as SphereShape3D).radius = cloud_radius

	# Update Visualizer
	if is_instance_valid(vis):
		vis.position = hazard_offset
		vis.shape_type = visualizer_shape
		if visualizer_shape == EditorTriggerVisualizer.ShapeType.BOX:
			vis.trigger_size = visualizer_size
		else:
			vis.trigger_size = Vector3.ONE * (cloud_radius * 2.0)

		vis.trigger_color = visualizer_color
		vis.trigger_text = visualizer_text
		vis.show_in_game = show_visualizer_in_game
		# Explicitly trigger visualizer mesh recreation in editor
		vis._update_mesh()
		vis._update_material()


## Updates particle system process material emission radius.
func _update_cloud_bounds() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = (
		_particles if is_instance_valid(_particles) else get_node_or_null("SmokeParticles")
		as GPUParticles3D
	)
	if is_instance_valid(parts) and parts.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = parts.process_material as ParticleProcessMaterial
		mat.emission_sphere_radius = cloud_radius * 0.35


## Updates shader uniform color parameter on the draw pass quad material.
func _update_particle_visuals() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = (
		_particles if is_instance_valid(_particles) else get_node_or_null("SmokeParticles")
		as GPUParticles3D
	)
	if is_instance_valid(parts) and parts.draw_pass_1:
		if parts.draw_pass_1.material is ShaderMaterial:
			var mat: ShaderMaterial = parts.draw_pass_1.material as ShaderMaterial
			mat.set_shader_parameter("smoke_color", smoke_color)


## Updates the lifetime value on the particle node.
func _update_particle_lifetime() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = (
		_particles if is_instance_valid(_particles) else get_node_or_null("SmokeParticles")
		as GPUParticles3D
	)
	if is_instance_valid(parts):
		parts.lifetime = particle_lifetime


## Configures process material initial velocity, direction, and spread.
func _update_particle_velocity() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = (
		_particles if is_instance_valid(_particles) else get_node_or_null("SmokeParticles")
		as GPUParticles3D
	)
	if is_instance_valid(parts) and parts.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = parts.process_material as ParticleProcessMaterial
		mat.direction = Vector3.UP
		mat.spread = spread
		mat.initial_velocity_min = velocity_min * (particle_speed / 4.0)
		mat.initial_velocity_max = velocity_max * (particle_speed / 4.0)


## Configures min and max random particle scaling bounds.
func _update_particle_scale() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = (
		_particles if is_instance_valid(_particles) else get_node_or_null("SmokeParticles")
		as GPUParticles3D
	)
	if is_instance_valid(parts) and parts.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = parts.process_material as ParticleProcessMaterial
		mat.scale_min = scale_min
		mat.scale_max = scale_max


## Offsets the collision shape upward so its bottom aligns with the origin.
func _align_collision_to_base(col_shape: CollisionShape3D) -> void:
	print("SmokeHazard: Aligning collision base on ", name)
	if not is_instance_valid(col_shape) or not col_shape.shape is BoxShape3D:
		return

	var box: BoxShape3D = col_shape.shape as BoxShape3D
	col_shape.position.y = box.size.y * 0.5
