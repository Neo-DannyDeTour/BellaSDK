## Driver node orchestrating scene lights, wind motion, and compositor synchronization.
##
## Tracks [DirectionalLight3D], [OmniLight3D], and [SunshineCloudsEffector] instances,
## manages continuous wind coordinate wrapping, and hooks into [WorldEnvironment].
@tool
@icon("res://addons/SunshineClouds2/CloudsDriverIcon.svg")
class_name SunshineCloudsDriverGD
extends Node

## Enables continuous real-time wind coordinate integration and light tracking updates.
@export var update_continuously: bool = false:
	get:
		return update_continuously
	set(value):
		update_continuously = value
		if is_inside_tree():
			retrieve_texture_data()

## Triggers generation and automatic binding of a new [SunshineCloudsGD] compositor resource.
@export_tool_button("Generate Clouds Resource", "Add")
var generate_action: Callable = build_new_clouds

@export_group("Compositor Resource")
## The active [SunshineCloudsGD] compositor resource driven by this node.
@export var clouds_resource: SunshineCloudsGD:
	get:
		return clouds_resource
	set(value):
		clouds_res_removed()
		clouds_resource = value
		clouds_res_added()

@export_group("Optional World Environment")
## Optional environment from which background fog colors and ambient parameters are sampled.
@export var ambience_sample_environment: Environment

@export_group("Light Controls")
## Directional lights illuminating the cloud volume and casting volumetric light shafts.
@export var tracked_directional_lights: Array[DirectionalLight3D] = []:
	get:
		return tracked_directional_lights
	set(value):
		tracked_directional_lights = value
		if is_inside_tree():
			retrieve_texture_data()

## Raymarching shadow step counts evaluated for each tracked directional light.
@export var tracked_directional_light_shadow_steps: Array[int] = []:
	get:
		return tracked_directional_light_shadow_steps
	set(value):
		tracked_directional_light_shadow_steps = value
		if is_inside_tree():
			retrieve_texture_data()

## Point and omni lights casting local illumination within the cloud volume.
@export var tracked_point_lights: Array[OmniLight3D] = []:
	get:
		return tracked_point_lights
	set(value):
		tracked_point_lights = value
		if is_inside_tree():
			retrieve_texture_data()

## Local density effectors pushing or carving holes into the cloud volume.
@export var tracked_point_effectors: Array[SunshineCloudsEffector] = []:
	get:
		return tracked_point_effectors
	set(value):
		tracked_point_effectors = value
		if is_inside_tree():
			retrieve_texture_data()

## Global power multiplier applied to all tracked directional lights.
@export_range(0.0, 10.0, 0.05) var directional_light_power_multiplier: float = 1.0

## Global power multiplier applied to all tracked point lights.
@export_range(0.0, 10.0, 0.05) var point_light_power_multiplier: float = 1.0

@export_group("Wind Controls")
## World-space translation offset applied to the entire cloud volume.
@export var origin_offset: Vector3 = Vector3.ZERO

## Normalized horizontal wind movement direction vector.
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 1.0)

## Movement speed in meters per second for extra-large macro noise structures.
@export_range(0.0, 1000.0, 1.0, "suffix:m/s")
var extra_large_structures_wind_speed: float = 140.0

## Movement speed in meters per second for large primary cloud shape structures.
@export_range(0.0, 1000.0, 1.0, "suffix:m/s")
var large_structures_wind_speed: float = 100.0

## Movement speed in meters per second for medium erosion noise structures.
@export_range(0.0, 500.0, 1.0, "suffix:m/s")
var medium_structures_wind_speed: float = 40.0

## Movement speed in meters per second for small detail noise structures.
@export_range(0.0, 200.0, 1.0, "suffix:m/s")
var small_structures_wind_speed: float = 12.0

@export_group("Internal Use")
## Accumulated offset for extra-large scale noise sampling.
var extra_large_clouds_pos: Vector3 = Vector3.ZERO

## Accumulated offset for large scale noise sampling.
var large_clouds_pos: Vector3 = Vector3.ZERO

## Accumulated offset for medium scale noise sampling.
var medium_clouds_pos: Vector3 = Vector3.ZERO

## Accumulated offset for small detail noise sampling.
var small_clouds_pos: Vector3 = Vector3.ZERO

## Domain wrapping boundary for extra-large noise coordinates.
var _extralarge_clouds_domain: float = 0.0

## Domain wrapping boundary for large noise coordinates.
var _large_clouds_domain: float = 0.0

## Domain wrapping boundary for medium noise coordinates.
var _medium_clouds_domain: float = 0.0

## Domain wrapping boundary for small noise coordinates.
var _small_clouds_domain: float = 0.0

## Mutex flag preventing concurrent texture and uniform updates.
var _updating_settings: bool = false


## Initializes light tracking and schedules texture data synchronization.
func _ready() -> void:
	if update_continuously:
		if clouds_resource == null:
			update_continuously = false
			return
		call_deferred(&"retrieve_texture_data")


## Integrates continuous wind displacement and synchronizes parameters every frame.
func _process(delta: float) -> void:
	if clouds_resource != null:
		clouds_resource.current_time = wrapf(
			clouds_resource.current_time + delta * clouds_resource.dither_speed,
			0.0,
			clouds_resource.dither_speed * 64.0
		)

		if update_continuously:
			_updating_settings = false

			extra_large_clouds_pos += (
				wind_direction * extra_large_structures_wind_speed * delta
			)
			extra_large_clouds_pos = wrap_vector(
				extra_large_clouds_pos, _extralarge_clouds_domain
			)

			large_clouds_pos += (
				wind_direction * large_structures_wind_speed * delta
			)
			large_clouds_pos = wrap_vector(
				large_clouds_pos, _large_clouds_domain
			)

			medium_clouds_pos += (
				wind_direction * medium_structures_wind_speed * delta
			)
			medium_clouds_pos = wrap_vector(
				medium_clouds_pos, _medium_clouds_domain
			)

			var small_wind_velocity: Vector3 = (
				(wind_direction * small_structures_wind_speed)
				+ (Vector3.UP * absf(small_structures_wind_speed))
			)
			small_clouds_pos += small_wind_velocity * delta
			small_clouds_pos = wrap_vector(
				small_clouds_pos, _small_clouds_domain
			)

			clouds_resource.origin_offset = origin_offset
			clouds_resource.extra_large_scale_clouds_position = (
				origin_offset + extra_large_clouds_pos
			)
			clouds_resource.large_scale_clouds_position = (
				origin_offset + large_clouds_pos
			)
			clouds_resource.medium_scale_clouds_position = (
				origin_offset + medium_clouds_pos
			)
			clouds_resource.detail_clouds_position = (
				origin_offset + small_clouds_pos
			)
			clouds_resource.wind_direction = wind_direction

			if (
				clouds_resource.use_environment_fog > 0.0
				and ambience_sample_environment != null
			):
				clouds_resource.sampled_environment_fog_color = (
					ambience_sample_environment.fog_light_color
				)
	else:
		update_continuously = false


# --- Player Interaction & Public Methods ---


## Updates the cloud coordinate system origin offset [param new_offset].
func update_origin_offset(new_offset: Vector3) -> void:
	print("SunshineCloudsDriver: Updating origin offset to ", new_offset)
	origin_offset = new_offset


## Updates the horizontal wind velocity direction vector [param new_direction].
func update_wind_direction(new_direction: Vector3) -> void:
	print("SunshineCloudsDriver: Updating wind direction to ", new_direction)
	wind_direction = new_direction.normalized()


## Forces an immediate repack and GPU upload of all tracked light buffers.
func force_light_update() -> void:
	print("SunshineCloudsDriver: Explicit light update requested by player/system.")
	retrieve_texture_data()


## Enqueues a batch of 64 diagnostic cloud density queries across altitude levels.
func sample_clouds() -> void:
	print("SunshineCloudsDriver: Sampling clouds data.")
	if clouds_resource == null:
		return
	for i: int in range(64):
		clouds_resource.add_sample(
			return_data.bind(), Vector3(i * 1000.0, 6000.0, 0.0)
		)


## Diagnostic callback receiving sampled world [param position] and cloud [param sampledensity].
func return_data(position: Vector3, sampledensity: float) -> void:
	print("Cloud Sample Output - Position: ", position, " Density: ", sampledensity)


# --- Internal Setup & Compositor Management ---


## Instantiates a new [SunshineCloudsGD] resource and attaches it to the [WorldEnvironment].
func build_new_clouds() -> void:
	if not is_inside_tree():
		return

	var env: WorldEnvironment = recursively_find_env(get_tree().root)
	if env != null:
		if not ambience_sample_environment:
			ambience_sample_environment = env.environment
		clouds_resource = SunshineCloudsGD.new()
		update_continuously = true
		print("SunshineCloudsDriver: Generated new clouds resource.")
	else:
		printerr("SunshineCloudsDriver: No WorldEnvironment found in scene tree.")


## Detaches the active [SunshineCloudsGD] compositor effect from the [WorldEnvironment].
func clouds_res_removed() -> void:
	if clouds_resource and is_inside_tree():
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if env and env.compositor != null:
			var effects: Array[CompositorEffect] = (
				env.compositor.compositor_effects
			)
			if effects.has(clouds_resource):
				effects.erase(clouds_resource)
				env.compositor.compositor_effects = effects


## Attaches the active [SunshineCloudsGD] compositor effect to the [WorldEnvironment].
func clouds_res_added() -> void:
	if clouds_resource and is_inside_tree():
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if env != null:
			if not env.compositor:
				env.compositor = Compositor.new()
				env.compositor.compositor_effects = [clouds_resource]
			else:
				var effects: Array[CompositorEffect] = (
					env.compositor.compositor_effects
				)
				if not effects.has(clouds_resource):
					effects.append(clouds_resource)
					env.compositor.compositor_effects = effects


## Recursively searches down scene tree node [param this_node] to locate a [WorldEnvironment].
func recursively_find_env(this_node: Node) -> WorldEnvironment:
	if not is_instance_valid(this_node):
		return null
	for child: Node in this_node.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
		var result: WorldEnvironment = recursively_find_env(child)
		if result != null:
			return result
	return null


## Repacks directional lights, point lights, and effectors into std140 arrays for [SunshineCloudsGD].
func retrieve_texture_data() -> void:
	if _updating_settings or not is_inside_tree() or clouds_resource == null:
		return

	_updating_settings = true

	_extralarge_clouds_domain = clouds_resource.extra_large_noise_scale * 0.5
	_large_clouds_domain = clouds_resource.large_noise_scale * 0.5
	_medium_clouds_domain = clouds_resource.medium_noise_scale * 0.5
	_small_clouds_domain = clouds_resource.small_noise_scale * 0.5

	var dir_count: int = tracked_directional_lights.size()
	var pt_count: int = tracked_point_lights.size()
	var eff_count: int = tracked_point_effectors.size()

	clouds_resource.directional_lights_data.resize(dir_count * 2)
	clouds_resource.point_lights_data.resize(pt_count * 2)
	clouds_resource.point_effector_data.resize(eff_count * 2)

	while tracked_directional_light_shadow_steps.size() < dir_count:
		tracked_directional_light_shadow_steps.append(12)

	# 1. Pack Directional Lights (Pairs of Vector4)
	for i: int in range(dir_count):
		var light: DirectionalLight3D = tracked_directional_lights[i]
		if not is_instance_valid(light):
			continue

		var look_dir: Vector3 = light.global_transform.basis.z.normalized()
		clouds_resource.directional_lights_data[i * 2] = Vector4(
			look_dir.x,
			look_dir.y,
			look_dir.z,
			float(tracked_directional_light_shadow_steps[i])
		)

		var intensity: float = (
			light.light_color.a
			* light.light_energy
			* directional_light_power_multiplier
		)
		clouds_resource.directional_lights_data[(i * 2) + 1] = Vector4(
			light.light_color.r,
			light.light_color.g,
			light.light_color.b,
			snappedf(intensity, 0.1)
		)

	# 2. Pack Point/Omni Lights (Pairs of Vector4)
	for i: int in range(pt_count):
		var light: OmniLight3D = tracked_point_lights[i]
		if not is_instance_valid(light):
			continue

		var light_pos: Vector3 = light.global_position
		clouds_resource.point_lights_data[i * 2] = Vector4(
			light_pos.x, light_pos.y, light_pos.z, light.omni_range
		)

		var intensity: float = (
			light.light_color.a
			* light.light_energy
			* point_light_power_multiplier
		)
		clouds_resource.point_lights_data[(i * 2) + 1] = Vector4(
			light.light_color.r,
			light.light_color.g,
			light.light_color.b,
			snappedf(intensity, 0.1)
		)

	# 3. Pack Point Effectors (Pairs of Vector4: Pos+Radius, Power+Attenuation)
	for i: int in range(eff_count):
		var effector: SunshineCloudsEffector = tracked_point_effectors[i]
		if not is_instance_valid(effector):
			continue

		var eff_pos: Vector3 = effector.global_position
		clouds_resource.point_effector_data[i * 2] = Vector4(
			eff_pos.x, eff_pos.y, eff_pos.z, effector.radius
		)
		clouds_resource.point_effector_data[(i * 2) + 1] = Vector4(
			effector.power, effector.attenuation, 0.0, 0.0
		)

	clouds_resource.lights_updated = true
	_updating_settings = false


## Smoothly wraps vector [param target] within symmetric boundary [param domain_size].
func wrap_vector(target: Vector3, domain_size: float) -> Vector3:
	if domain_size <= 0.001:
		return target
	return Vector3(
		wrapf(target.x, -domain_size, domain_size),
		wrapf(target.y, -domain_size, domain_size),
		wrapf(target.z, -domain_size, domain_size)
	)
