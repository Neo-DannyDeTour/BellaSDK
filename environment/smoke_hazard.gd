@tool
## Pulsing hazard dealing periodic damage to overlapping bodies via HealthComponent.
## Integrates [EditorTriggerVisualizer] for in-editor wireframe and bounds display.
class_name SmokeHazard
extends Area3D

## Emitted when an entity takes a tick of damage inside the smoke cloud.
## Passes the damaged target [Node3D] and the numeric damage dealt.
signal damage_ticked(target: Node3D, amount: float)

@export_group("Hazard Damage & Timers")
## Base damage dealt per tick to bodies inside smoke cloud.
@export var damage_per_tick: float = 5.0

## Time in seconds between consecutive damage ticks.
@export var tick_rate: float = 0.5

## Radius for particle distribution and fallback sphere collision.
@export var cloud_radius: float = 2.0:
	set(value):
		cloud_radius = value
		if is_inside_tree():
			_update_cloud_bounds()
			_update_collision_and_visualizer()

## Time in seconds hazard remains active and emitting.
@export var active_duration: float = 3.0

## Time in seconds hazard pauses between active bursts.
@export var pause_duration: float = 2.0

## Enables environment raycast occlusion to stop damage through walls.
@export var check_wall_occlusion: bool = true

@export_group("Trigger Volume")
## Geometric shape displayed in visualizer and synced to collision.
@export
var visualizer_shape: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		visualizer_shape = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## 3D dimensions of hazard collision box and visualizer box.
@export var visualizer_size: Vector3 = Vector3(4.0, 4.0, 4.0):
	set(value):
		visualizer_size = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## 3D position offset for collision shape and visualizer mesh.
@export var hazard_offset: Vector3 = Vector3.ZERO:
	set(value):
		hazard_offset = value
		if is_inside_tree():
			_update_collision_and_visualizer()

@export_group("Trigger Debug Visualizer")
## Toggles visibility of debug trigger shape in runtime builds.
@export var show_visualizer_in_game: bool = false:
	set(value):
		show_visualizer_in_game = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## Color and transparency of editor debug trigger shape.
@export var visualizer_color: Color = Color(0.9, 0.2, 0.1, 0.25):
	set(value):
		visualizer_color = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## Edge color applied to the wireframe bounding cage and orientation arrow.
@export var outline_color: Color = Color(1.0, 0.4, 0.2, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## Allows the visualizer to remain visible through walls and level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## Displays an arrow pointing along -Z indicating hazard emission heading.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## Appends metric dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_collision_and_visualizer()

## Text label displayed on editor debug shape.
@export var visualizer_text: String = "SMOKE HAZARD":
	set(value):
		visualizer_text = value
		if is_inside_tree():
			_update_collision_and_visualizer()

@export_group("Particle Settings")
## Base tint applied to smoke particles.
@export var smoke_color: Color = Color(0.9, 0.9, 0.9, 0.85):
	set(value):
		smoke_color = value
		if is_inside_tree():
			_update_particle_visuals()

## Overall lifetime in seconds for individual smoke puffs.
@export var particle_lifetime: float = 2.0:
	set(value):
		particle_lifetime = maxf(0.1, value)
		if is_inside_tree():
			_update_particle_lifetime()

## Overall velocity scaling factor for emission system.
@export var particle_speed: float = 4.0:
	set(value):
		particle_speed = value
		if is_inside_tree():
			_update_particle_velocity()

## Minimum initial upward ejection speed.
@export var velocity_min: float = 3.0:
	set(value):
		velocity_min = value
		if is_inside_tree():
			_update_particle_velocity()

## Maximum initial upward ejection speed.
@export var velocity_max: float = 6.0:
	set(value):
		velocity_max = value
		if is_inside_tree():
			_update_particle_velocity()

## Angle in degrees for emission cone spread.
@export_range(0.0, 180.0) var spread: float = 25.0:
	set(value):
		spread = value
		if is_inside_tree():
			_update_particle_velocity()

## Minimum randomized uniform scale multiplier.
@export var scale_min: float = 0.8:
	set(value):
		scale_min = value
		if is_inside_tree():
			_update_particle_scale()

## Maximum randomized uniform scale multiplier.
@export var scale_max: float = 2.0:
	set(value):
		scale_max = value
		if is_inside_tree():
			_update_particle_scale()

## Internal interval timer used to trigger damage cycles.
var _tick_timer: float = 0.0

## Tracks time spent in current active or paused phase.
var _phase_timer: float = 0.0

## Flag indicating whether hazard is actively venting smoke.
var _is_active: bool = true

## Cache of overlapping bodies currently inside hazard radius.
var _targets_in_smoke: Array[Node3D] = []

## Cache mapping overlapping bodies to detected [HealthComponent].
var _health_cache: Dictionary = {}

## Tracks whether player is currently inside this hazard instance.
var _is_player_inside: bool = false

## Direct reference to collision shape node.
@onready
var _collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D

## Direct reference to particle system node.
@onready var _particles: GPUParticles3D = get_node_or_null("SmokeParticles") as GPUParticles3D

## Direct reference to trigger visualizer helper node.
@onready var _visualizer: EditorTriggerVisualizer = (
	get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
)


## Connects collision callbacks and synchronizes parameters on ready.
func _ready() -> void:
	print("SmokeHazard: Initialized at ", global_position)
	_update_collision_and_visualizer()
	_update_cloud_bounds()
	_update_particle_visuals()
	_update_particle_lifetime()
	_update_particle_velocity()
	_update_particle_scale()
	_set_hazard_state(true)

	if not Engine.is_editor_hint():
		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)
		if not body_exited.is_connected(_on_body_exited):
			body_exited.connect(_on_body_exited)


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


## Registers entering bodies into active targets list.
func _on_body_entered(body: Node3D) -> void:
	if not _targets_in_smoke.has(body):
		_targets_in_smoke.append(body)
		print("SmokeHazard: Target entered smoke -> ", body.name)

		var health: HealthComponent = _find_health_component(body)
		if is_instance_valid(health):
			_health_cache[body] = health

		if body.is_in_group(&"player"):
			_is_player_inside = true
			if _is_active:
				Events.steam_hazard_toggled.emit(true)


## Unregisters exiting bodies from active targets list.
func _on_body_exited(body: Node3D) -> void:
	_targets_in_smoke.erase(body)
	_health_cache.erase(body)
	print("SmokeHazard: Target exited smoke -> ", body.name)

	if body.is_in_group(&"player"):
		_is_player_inside = false
		Events.steam_hazard_toggled.emit(false)


## Applies periodic damage to targets having a valid [HealthComponent].
func _apply_tick_damage() -> void:
	print("SmokeHazard: Ticking damage on ", _targets_in_smoke.size(), " target(s).")
	for target: Node3D in _targets_in_smoke:
		if not is_instance_valid(target):
			continue

		if check_wall_occlusion and not _has_line_of_sight(target):
			print("SmokeHazard: Target occluded by wall -> ", target.name)
			continue

		var health: HealthComponent = _health_cache.get(target) as HealthComponent
		if not is_instance_valid(health):
			health = _find_health_component(target)
			if is_instance_valid(health):
				_health_cache[target] = health

		if is_instance_valid(health):
			print("SmokeHazard: Damaging HealthComponent on ", target.name)
			damage_ticked.emit(target, damage_per_tick)
			health.take_damage(int(roundf(damage_per_tick)))


## Validates clear line of sight avoiding floor clipping against Layer 1.
func _has_line_of_sight(target: Node3D) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var start_pos: Vector3 = global_position + hazard_offset + Vector3(0.0, 0.5, 0.0)
	var end_pos: Vector3 = target.global_position + Vector3(0.0, 0.5, 0.0)

	var result: Dictionary = NodeQuery.cast_ray(
		space_state, start_pos, end_pos, CollisionLayers.MASK_ENVIRONMENT
	)
	return result.is_empty()


## Resolves [HealthComponent] on target via properties or [NodeQuery].
func _find_health_component(target: Node) -> HealthComponent:
	print("SmokeHazard: Resolving HealthComponent on -> ", target.name)
	if not is_instance_valid(target):
		return null

	if target is HealthComponent:
		return target as HealthComponent

	if "health_component" in target:
		var comp: Variant = target.get("health_component")
		if comp is HealthComponent:
			return comp as HealthComponent

	var found_child: Node = NodeQuery.find_first_child_of_type(target, HealthComponent)
	if found_child is HealthComponent:
		return found_child as HealthComponent

	var ancestor: Node = NodeQuery.find_ancestor_of_type(target, HealthComponent)
	if ancestor is HealthComponent:
		return ancestor as HealthComponent

	return null


## Changes emission state while preserving body tracking and collision.
func _set_hazard_state(active: bool) -> void:
	_is_active = active
	_phase_timer = 0.0
	_tick_timer = 0.0
	print("SmokeHazard: State changed -> active = ", active)

	if _is_player_inside:
		Events.steam_hazard_toggled.emit(active)

	if not is_inside_tree():
		return

	var parts: GPUParticles3D = _get_particles()
	if is_instance_valid(parts):
		parts.emitting = active


## Updates collision shape and visualizer mesh in editor and runtime.
func _update_collision_and_visualizer() -> void:
	if not is_inside_tree():
		return

	var col: CollisionShape3D = _get_collision_shape()
	if is_instance_valid(col):
		if visualizer_shape == EditorTriggerVisualizer.ShapeType.BOX:
			if not col.shape is BoxShape3D:
				col.shape = BoxShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = visualizer_size
		elif visualizer_shape == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not col.shape is SphereShape3D:
				col.shape = SphereShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			var sphere: SphereShape3D = col.shape as SphereShape3D
			sphere.radius = cloud_radius

		col.position = hazard_offset

	var vis: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(vis):
		vis.shape_type = visualizer_shape
		if visualizer_shape == EditorTriggerVisualizer.ShapeType.BOX:
			vis.trigger_size = visualizer_size
		else:
			vis.trigger_size = Vector3.ONE * (cloud_radius * 2.0)

		vis.trigger_color = visualizer_color
		vis.outline_color = outline_color
		vis.x_ray_mode = x_ray_mode
		vis.show_orientation = show_orientation
		vis.show_metric_dimensions = show_metric_dimensions
		vis.trigger_text = visualizer_text
		vis.show_in_game = show_visualizer_in_game
		vis.position = hazard_offset


## Updates particle system process material emission radius.
func _update_cloud_bounds() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = _get_particles()
	if is_instance_valid(parts) and parts.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = parts.process_material as ParticleProcessMaterial
		mat.emission_sphere_radius = cloud_radius * 0.35


## Updates shader uniform color parameter on draw pass quad material.
func _update_particle_visuals() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = _get_particles()
	if is_instance_valid(parts) and parts.draw_pass_1:
		if parts.draw_pass_1.material is ShaderMaterial:
			var mat: ShaderMaterial = parts.draw_pass_1.material as ShaderMaterial
			mat.set_shader_parameter(&"smoke_color", smoke_color)


## Updates lifetime value on particle node.
func _update_particle_lifetime() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = _get_particles()
	if is_instance_valid(parts):
		parts.lifetime = particle_lifetime


## Configures process material initial velocity, direction, and spread.
func _update_particle_velocity() -> void:
	if not is_inside_tree():
		return

	var parts: GPUParticles3D = _get_particles()
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

	var parts: GPUParticles3D = _get_particles()
	if is_instance_valid(parts) and parts.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = parts.process_material as ParticleProcessMaterial
		mat.scale_min = scale_min
		mat.scale_max = scale_max


## Safely resolves child [CollisionShape3D] node.
func _get_collision_shape() -> CollisionShape3D:
	if is_instance_valid(_collision_shape):
		return _collision_shape
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		for child: Node in get_children():
			if child is CollisionShape3D:
				return child as CollisionShape3D
	return col


## Safely resolves child [EditorTriggerVisualizer] node.
func _get_visualizer() -> EditorTriggerVisualizer:
	if is_instance_valid(_visualizer):
		return _visualizer
	var vis: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(vis):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
	return vis


## Safely resolves child [GPUParticles3D] node.
func _get_particles() -> GPUParticles3D:
	if is_instance_valid(_particles):
		return _particles
	return get_node_or_null("SmokeParticles") as GPUParticles3D
