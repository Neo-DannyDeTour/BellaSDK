@tool
## Volumetric fire manager with embers, lighting, and burn detection area.
class_name VolumetricFire
extends Node3D

## Default light flicker frequency for flame illumination in [method _process].
const FLICKER_FREQUENCY: float = 12.0
## Volumetric render layer mask (Layer 10) for 3D raymarching culling.
const VOLUMETRIC_LAYER_MASK: int = CollisionLayers.RENDER_MASK_VOLUMETRICS
## Environment render layer mask (Layer 1) for ember particle visibility.
const ENVIRONMENT_LAYER_MASK: int = CollisionLayers.RENDER_MASK_ENVIRONMENT
## Default physics mask targeting players, interactables, debris, and enemies.
const DEFAULT_PHYSICS_MASK: int = (
	CollisionLayers.MASK_PLAYER
	| CollisionLayers.MASK_INTERACTIVE
	| CollisionLayers.MASK_DEBRIS
	| CollisionLayers.MASK_ENEMIES
)

## Emitted when [method ignite] enables fire rendering and burn monitoring.
signal ignited
## Emitted when [method extinguish] halts fire rendering and damage triggers.
signal extinguished
## Emitted when [member burn_area] detects a combustible body. Passes [param body].
signal body_ignited(body: Node3D)

## Target [Node3D] ignored by [member burn_area] to prevent self-collision.
@export var ignored_body: Node3D

## Bounding [MeshInstance3D] rendering the volumetric fire shader material.
@export var mesh_instance: MeshInstance3D:
	set(value):
		mesh_instance = value
		if is_inside_tree() and is_instance_valid(mesh_instance):
			_cache_material()
			_update_shader_parameters()
			_update_volume_mesh()

## Dynamic [OmniLight3D] providing flickering ambient fire illumination.
@export var fire_light: OmniLight3D

## System emitting drifting ash and glowing ember particles.
@export var ember_particles: GPUParticles3D:
	set(value):
		ember_particles = value
		if is_inside_tree() and is_instance_valid(ember_particles):
			_update_particle_parameters()

## Trigger [Area3D] detecting combustible physics bodies within the flame.
@export var burn_area: Area3D

## Bounding [CollisionShape3D] synchronized with fire dimensions.
@export var burn_shape: CollisionShape3D

## Vertical height in meters for the raymarched fire bounding volume.
@export_range(0.1, 10.0, 0.05) var fire_height: float = 2.45:
	set = set_fire_height

## Horizontal width in meters for the raymarched fire bounding volume.
@export_range(0.1, 10.0, 0.05) var fire_width: float = 2.25:
	set = set_fire_width

## Convective motion speed driving flame rising turbulence and animation.
@export_range(0.01, 2.0, 0.01) var fire_speed: float = 0.35:
	set = set_fire_speed

## Radiant emission glow multiplier passed into the fire shader material.
@export_range(0.0, 30.0, 0.5) var emission_strength: float = 3.2:
	set = set_emission_strength

## Direction vector of ambient wind blowing flames and drifting embers.
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 0.0):
	set = set_wind_direction

## Wind force magnitude driving flame curvature and particle drift.
@export_range(0.0, 5.0, 0.05) var wind_strength: float = 0.5:
	set = set_wind_strength

## Toggles light energy flickering in [method _process] for ambient realism.
@export var enable_flicker: bool = true

## Base illumination intensity for the attached [member fire_light].
@export_range(0.0, 10.0, 0.1) var base_light_energy: float = 2.5

## Amount of damage dealt to overlapping bodies on each burn interval tick.
@export_range(1, 100, 1) var burn_damage_per_tick: int = 25

## Time interval in seconds between consecutive burn damage ticks.
@export_range(0.05, 5.0, 0.05) var burn_tick_interval: float = 0.3

## Cached [ShaderMaterial] instance assigned to [member mesh_instance].
var _material: ShaderMaterial = null

## Accumulated elapsed time in seconds used for lighting modulation.
var _time_passed: float = 0.0

## Timer accumulating physics delta time toward [member burn_tick_interval].
var _tick_timer: float = 0.0

## Burning state flag indicating whether the fire effect is currently active.
var _is_burning: bool = true

## List of currently overlapping bodies receiving fire burn damage.
var _active_combustible_bodies: Array[Node3D] = []

## Tracks whether the player character is currently inside [member burn_area].
var _is_player_present: bool = false


## Initializes materials, render layers, collision shapes, and uniforms.
func _ready() -> void:
	print("[VolumetricFire] Initializing fire system.")
	_cache_material()
	_apply_render_layer()
	_setup_burn_area()
	_update_shader_parameters()
	_update_particle_parameters()
	_update_burn_shape()
	_update_volume_mesh()


## Updates dynamic light flicker per frame to maintain illumination.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_burning or not enable_flicker:
		return
	if not is_instance_valid(fire_light):
		return

	_time_passed += delta * FLICKER_FREQUENCY
	var noise_factor: float = (sin(_time_passed) * 0.5 + sin(_time_passed * 2.3) * 0.3) * 0.3
	fire_light.light_energy = maxf(0.0, base_light_energy + noise_factor)


## Accumulates burn timer and applies periodic damage to overlapping bodies.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _is_burning or _active_combustible_bodies.is_empty():
		_tick_timer = 0.0
		return

	_tick_timer += delta
	if _tick_timer >= burn_tick_interval:
		_tick_timer = 0.0
		_apply_burn_tick()


## Deals [member burn_damage_per_tick] to all registered overlapping bodies.
func _apply_burn_tick() -> void:
	print("[VolumetricFire] Applying burn tick of ", burn_damage_per_tick, " damage.")
	for i: int in range(_active_combustible_bodies.size() - 1, -1, -1):
		var target_body: Node3D = _active_combustible_bodies[i]
		if not is_instance_valid(target_body):
			_active_combustible_bodies.remove_at(i)
			continue
		_damage_target(target_body, burn_damage_per_tick)


## Inflicts fire damage on [param target] via methods or [HealthComponent].
func _damage_target(target: Node3D, amount: int) -> void:
	print("[VolumetricFire] Dealing ", amount, " damage to: ", target.name)
	if target.has_method(&"take_fire_damage"):
		target.call(&"take_fire_damage", amount)
	elif target.has_method(&"take_damage"):
		target.call(&"take_damage", amount)
	else:
		var health: HealthComponent = _resolve_health_component(target)
		if is_instance_valid(health):
			health.take_damage(amount)


## Resolves [HealthComponent] on [param target] via property or [NodeQuery].
func _resolve_health_component(target: Node3D) -> HealthComponent:
	print("[VolumetricFire] Resolving HealthComponent for: ", target.name)
	if not is_instance_valid(target):
		return null
	if "health_component" in target:
		var comp: Variant = target.get("health_component")
		if comp is HealthComponent:
			return comp
	var found_comp: Node = NodeQuery.find_first_child_of_type(target, HealthComponent)
	if found_comp is HealthComponent:
		return found_comp
	return null


## Checks if [param target] can receive damage or has [HealthComponent].
func _can_take_damage(target: Node3D) -> bool:
	print("[VolumetricFire] Checking damage capability for: ", target.name)
	return (
		target.has_method(&"take_fire_damage")
		or target.has_method(&"take_damage")
		or is_instance_valid(_resolve_health_component(target))
	)


## Returns true if [param body] is the player character.
func _is_player_body(body: Node3D) -> bool:
	var body_name: StringName = body.name if is_instance_valid(body) else &"null"
	print("[VolumetricFire] Checking if body is player: ", body_name)
	if not is_instance_valid(body):
		return false
	if body.is_in_group(&"player"):
		return true
	var health: HealthComponent = _resolve_health_component(body)
	return is_instance_valid(health) and health.is_player_health


## Ignites the fire effect, activating rendering, lighting, and particles.
func ignite() -> void:
	print("[VolumetricFire] Igniting fire and enabling burn trigger.")
	_is_burning = true
	_tick_timer = 0.0
	if is_instance_valid(fire_light):
		fire_light.visible = true
	if is_instance_valid(mesh_instance):
		mesh_instance.visible = true
	if is_instance_valid(ember_particles):
		ember_particles.emitting = true
	if is_instance_valid(burn_area):
		burn_area.monitoring = true
	_update_shader_parameters()
	_update_particle_parameters()
	ignited.emit()


## Extinguishes fire, stopping rendering, lighting, and burn detection.
func extinguish() -> void:
	print("[VolumetricFire] Extinguishing fire and disabling burn trigger.")
	_is_burning = false
	_tick_timer = 0.0
	if is_instance_valid(fire_light):
		fire_light.visible = false
	if is_instance_valid(mesh_instance):
		mesh_instance.visible = false
	if is_instance_valid(ember_particles):
		ember_particles.emitting = false
	if is_instance_valid(burn_area):
		burn_area.monitoring = false

	if _is_player_present:
		Events.fire_hazard_toggled.emit(false)
		_is_player_present = false

	_active_combustible_bodies.clear()
	extinguished.emit()


## Sets vertical fire height and synchronizes shapes and uniforms.
func set_fire_height(value: float) -> void:
	print("[VolumetricFire] Fire height changed to: ", value)
	fire_height = maxf(0.05, value)
	if is_inside_tree():
		if is_instance_valid(mesh_instance):
			_update_shader_parameters()
			_update_volume_mesh()
		if is_instance_valid(burn_shape):
			_update_burn_shape()


## Sets horizontal fire width and synchronizes shapes and uniforms.
func set_fire_width(value: float) -> void:
	print("[VolumetricFire] Fire width changed to: ", value)
	fire_width = maxf(0.05, value)
	if is_inside_tree():
		if is_instance_valid(mesh_instance):
			_update_shader_parameters()
			_update_volume_mesh()
		if is_instance_valid(burn_shape):
			_update_burn_shape()


## Sets flame convection speed and synchronizes with shader time scale.
func set_fire_speed(value: float) -> void:
	print("[VolumetricFire] Fire speed changed to: ", value)
	fire_speed = maxf(0.01, value)
	if is_inside_tree() and is_instance_valid(mesh_instance):
		_update_shader_parameters()


## Sets radiant emission glow and synchronizes with shader uniforms.
func set_emission_strength(value: float) -> void:
	print("[VolumetricFire] Emission strength changed to: ", value)
	emission_strength = maxf(0.0, value)
	if is_inside_tree() and is_instance_valid(mesh_instance):
		_update_shader_parameters()


## Sets ambient wind direction for flame deformation and ember drift.
func set_wind_direction(value: Vector3) -> void:
	print("[VolumetricFire] Wind direction changed to: ", value)
	wind_direction = value.normalized() if value.length_squared() > 0.0001 else Vector3.ZERO
	if is_inside_tree():
		if is_instance_valid(mesh_instance):
			_update_shader_parameters()
			_update_volume_mesh()
		if is_instance_valid(ember_particles):
			_update_particle_parameters()


## Sets wind strength magnitude for flame curvature and particle drift.
func set_wind_strength(value: float) -> void:
	print("[VolumetricFire] Wind strength changed to: ", value)
	wind_strength = maxf(0.0, value)
	if is_inside_tree():
		if is_instance_valid(mesh_instance):
			_update_shader_parameters()
			_update_volume_mesh()
		if is_instance_valid(ember_particles):
			_update_particle_parameters()


## Syncs flame dimensions, speed, emission, and wind uniforms to shader.
func _update_shader_parameters() -> void:
	print("[VolumetricFire] Updating shader parameters.")
	if not is_instance_valid(_material):
		return
	_material.set_shader_parameter("fire_height", fire_height)
	_material.set_shader_parameter("fire_width", fire_width)
	_material.set_shader_parameter("time_scale", fire_speed)
	_material.set_shader_parameter("emission_strength", emission_strength)
	_material.set_shader_parameter("wind_direction", wind_direction)
	_material.set_shader_parameter("wind_strength", wind_strength)


## Adjusts ember particle trajectory and velocity based on wind forces.
func _update_particle_parameters() -> void:
	print("[VolumetricFire] Updating particle parameters.")
	if not is_instance_valid(ember_particles):
		return
	var process_mat: Material = ember_particles.process_material
	if process_mat is ParticleProcessMaterial:
		var particle_mat: ParticleProcessMaterial = process_mat
		var drift_force: Vector3 = wind_direction * (wind_strength * 2.0)
		particle_mat.gravity = Vector3(drift_force.x, 0.8, drift_force.z)


## Synchronizes dimensions of [member burn_shape] to match fire dimensions.
func _update_burn_shape() -> void:
	print("[VolumetricFire] Updating burn collision shape.")
	if not is_instance_valid(burn_shape):
		return
	var shape: Shape3D = burn_shape.shape
	if shape is CylinderShape3D:
		var cyl_shape: CylinderShape3D = shape
		cyl_shape.height = fire_height
		cyl_shape.radius = fire_width * 0.5
		burn_shape.position = Vector3(0.0, fire_height * 0.5, 0.0)


## Resizes and aligns unique [member mesh_instance] bounding box.
func _update_volume_mesh() -> void:
	print("[VolumetricFire] Updating volume mesh boundaries.")
	if not is_instance_valid(mesh_instance):
		return
	mesh_instance.position = Vector3.ZERO
	if not mesh_instance.mesh is BoxMesh:
		return
	var box: BoxMesh = mesh_instance.mesh

	if not box.is_local_to_scene():
		var box_dup: Resource = box.duplicate()
		if box_dup is BoxMesh:
			box = box_dup
			mesh_instance.mesh = box

	var max_reach: float = maxf(fire_width, fire_height) + wind_strength
	var span_xz: float = max_reach * 2.6
	var span_y: float = fire_height * 2.6
	box.size = Vector3(span_xz, span_y, span_xz)


## Connects collision signals and configures physics masks on [member burn_area].
func _setup_burn_area() -> void:
	print("[VolumetricFire] Setting up burn area collision masks.")
	if not is_instance_valid(burn_area):
		return
	burn_area.collision_layer = CollisionLayers.MASK_NONE
	burn_area.collision_mask = DEFAULT_PHYSICS_MASK
	if not burn_area.body_entered.is_connected(_on_burn_area_body_entered):
		burn_area.body_entered.connect(_on_burn_area_body_entered)
	if not burn_area.body_exited.is_connected(_on_burn_area_body_exited):
		burn_area.body_exited.connect(_on_burn_area_body_exited)


## Triggered when a physics body enters [member burn_area].
func _on_burn_area_body_entered(body: Node3D) -> void:
	if body == self or body == ignored_body or body == get_parent():
		return
	print("[VolumetricFire] Body entered burn trigger: ", body.name)
	if not _is_burning:
		return

	if _is_player_body(body):
		_is_player_present = true
		Events.fire_hazard_toggled.emit(true)

	var is_combustible: bool = false
	if body.has_method(&"apply_heat"):
		body.call(&"apply_heat", 35.0)
	elif body.has_method(&"ignite"):
		body.call(&"ignite")
		is_combustible = true
	elif body.get("is_combustible") == true:
		body.set("is_on_fire", true)
		is_combustible = true

	if _can_take_damage(body) and not _active_combustible_bodies.has(body):
		_active_combustible_bodies.append(body)
		_damage_target(body, burn_damage_per_tick)

	if is_combustible:
		body_ignited.emit(body)


## Triggered when a physics body exits [member burn_area].
func _on_burn_area_body_exited(body: Node3D) -> void:
	if body == self or body == ignored_body or body == get_parent():
		return
	print("[VolumetricFire] Body exited burn trigger: ", body.name)

	if _is_player_body(body):
		_is_player_present = false
		Events.fire_hazard_toggled.emit(false)

	_active_combustible_bodies.erase(body)


## Caches shader material through [MaterialCache] to prevent GPU stalls.
func _cache_material() -> void:
	print("[VolumetricFire] Caching shader material via MaterialCache.")
	if not is_instance_valid(mesh_instance):
		_material = null
		return

	var mat: Material = mesh_instance.material_override
	if not is_instance_valid(mat):
		mat = mesh_instance.get_active_material(0)

	if mat is ShaderMaterial:
		var variant_key: String = "fire_%d" % get_instance_id()
		var raw_mat: Material = MaterialCache.get_variant(mat, variant_key)
		_material = raw_mat if raw_mat is ShaderMaterial else null
		mesh_instance.material_override = _material
	else:
		_material = null


## Assigns [member mesh_instance] to Layer 10 and embers to Layer 1.
func _apply_render_layer() -> void:
	print("[VolumetricFire] Applying visual render layers.")
	if is_instance_valid(mesh_instance):
		mesh_instance.layers = VOLUMETRIC_LAYER_MASK
	if is_instance_valid(ember_particles):
		ember_particles.layers = ENVIRONMENT_LAYER_MASK
