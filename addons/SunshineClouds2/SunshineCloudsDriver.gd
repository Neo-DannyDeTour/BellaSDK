@tool
@icon("res://addons/SunshineClouds2/CloudsDriverIcon.svg")
class_name SunshineCloudsDriverGD
extends Node

## Controls the update continuously behavior.
@export var update_continuously: bool = false:
	get:
		return update_continuously
	set(value):
		update_continuously = value
		retrieve_texture_data()

## Controls the generate action behavior.
## Generates clouds resource
@export_tool_button("Generate Clouds Resource", "Add")
var generate_action: Callable = build_new_clouds

@export_group("Compositor Resource")
@export var clouds_resource: SunshineCloudsGD:
	get:
		return clouds_resource
	set(value):
		clouds_res_removed()
		clouds_resource = value
		clouds_res_added()

@export_group("Optional World Environment")
@export var ambience_sample_environment: Environment

@export_group("Light Controls")
@export var tracked_directional_lights: Array[DirectionalLight3D] = []:
	get:
		return tracked_directional_lights
	set(value):
		tracked_directional_lights = value
		retrieve_texture_data()

## Controls the tracked directional light shadow steps behavior.
@export var tracked_directional_light_shadow_steps: Array[int] = []:
	get:
		return tracked_directional_light_shadow_steps
	set(value):
		tracked_directional_light_shadow_steps = value
		retrieve_texture_data()

## Controls the tracked point lights behavior.
@export var tracked_point_lights: Array[OmniLight3D] = []:
	get:
		return tracked_point_lights
	set(value):
		tracked_point_lights = value
		retrieve_texture_data()

## Controls the tracked point effectors behavior.
@export var tracked_point_effectors: Array[SunshineCloudsEffector] = []:
	get:
		return tracked_point_effectors
	set(value):
		tracked_point_effectors = value
		retrieve_texture_data()

## The intensity multiplier for the directional light power multiplier effect.
@export var directional_light_power_multiplier: float = 1.0
## The intensity multiplier for the point light power multiplier effect.
@export var point_light_power_multiplier: float = 1.0

@export_group("Wind Controls")
@export var origin_offset: Vector3 = Vector3.ZERO
## Controls the wind direction behavior.
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 1.0)
## The rate at which the extra large structures wind speed changes over time.
@export var extra_large_structures_wind_speed: float = 140.0
## The rate at which the large structures wind speed changes over time.
@export var large_structures_wind_speed: float = 100.0
## The rate at which the medium structures wind speed changes over time.
@export var medium_structures_wind_speed: float = 40.0
## The rate at which the small structures wind speed changes over time.
@export var small_structures_wind_speed: float = 12.0

@export_group("Internal Use")
var extra_large_clouds_pos: Vector3 = Vector3.ZERO
## Controls the large clouds pos behavior.
var large_clouds_pos: Vector3 = Vector3.ZERO
## Controls the medium clouds pos behavior.
var medium_clouds_pos: Vector3 = Vector3.ZERO
## Controls the small clouds pos behavior.
var small_clouds_pos: Vector3 = Vector3.ZERO

## Controls the extralarge clouds domain behavior.
var _extralarge_clouds_domain: float = 0.0
## Controls the large clouds domain behavior.
var _large_clouds_domain: float = 0.0
## Controls the medium clouds domain behavior.
var _medium_clouds_domain: float = 0.0
## Controls the small clouds domain behavior.
var _small_clouds_domain: float = 0.0
## Controls the updating settings behavior.
var _updating_settings: bool = false


func _ready() -> void:
	if update_continuously:
		if clouds_resource == null:
			update_continuously = false
			return
		call_deferred("retrieve_texture_data")


func _process(delta: float) -> void:
	if clouds_resource != null:
		clouds_resource.current_time = wrap(
			clouds_resource.current_time + delta * clouds_resource.dither_speed,
			0.0,
			clouds_resource.dither_speed * 64.0
		)

		if update_continuously:
			_updating_settings = false

			extra_large_clouds_pos += wind_direction * extra_large_structures_wind_speed * delta
			extra_large_clouds_pos = wrap_vector(extra_large_clouds_pos, _extralarge_clouds_domain)

			large_clouds_pos += wind_direction * large_structures_wind_speed * delta
			large_clouds_pos = wrap_vector(large_clouds_pos, _large_clouds_domain)

			medium_clouds_pos += wind_direction * medium_structures_wind_speed * delta
			medium_clouds_pos = wrap_vector(medium_clouds_pos, _medium_clouds_domain)

			## Controls the small wind velocity behavior.
			var small_wind_velocity: Vector3 = (
				(wind_direction * small_structures_wind_speed)
				+ (Vector3.UP * abs(small_structures_wind_speed))
			)
			small_clouds_pos += small_wind_velocity * delta
			small_clouds_pos = wrap_vector(small_clouds_pos, _small_clouds_domain)

			clouds_resource.origin_offset = origin_offset
			clouds_resource.extra_large_scale_clouds_position = (
				origin_offset + extra_large_clouds_pos
			)
			clouds_resource.large_scale_clouds_position = origin_offset + large_clouds_pos
			clouds_resource.medium_scale_clouds_position = origin_offset + medium_clouds_pos
			clouds_resource.detail_clouds_position = origin_offset + small_clouds_pos
			clouds_resource.wind_direction = wind_direction

			if clouds_resource.use_environment_fog > 0.0 and ambience_sample_environment != null:
				clouds_resource.sampled_environment_fog_color = (
					ambience_sample_environment.fog_light_color
				)
	else:
		update_continuously = false


# --- Player Interaction & Public Modifiers ---


func update_origin_offset(new_offset: Vector3) -> void:
	print("SunshineCloudsDriver: Updating origin offset to ", new_offset)
	origin_offset = new_offset


func update_wind_direction(new_direction: Vector3) -> void:
	print("SunshineCloudsDriver: Updating wind direction to ", new_direction)
	wind_direction = new_direction.normalized()


func force_light_update() -> void:
	print("SunshineCloudsDriver: Explicit light update requested by player/system.")
	retrieve_texture_data()


func sample_clouds() -> void:
	print("SunshineCloudsDriver: Sampling clouds data.")
	for i in range(64):
		clouds_resource.add_sample(return_data.bind(), Vector3(i * 1000, 6000.0, 0.0))


# --- Internal Methods ---


func return_data(position: Vector3, sampledensity: float) -> void:
	print("Cloud Sample Output - Position: ", position, " Density: ", sampledensity)


func build_new_clouds() -> void:
	if is_inside_tree():
		## Controls the env behavior.
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if env != null:
			if not ambience_sample_environment:
				ambience_sample_environment = env.environment
			clouds_resource = SunshineCloudsGD.new()
			update_continuously = true
			print("SunshineCloudsDriver: Generated new clouds resource.")
		else:
			printerr("SunshineCloudsDriver: No world environment found.")


func clouds_res_removed() -> void:
	if clouds_resource and is_inside_tree():
		## Controls the env behavior.
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if env and env.compositor != null:
			## Controls the effects behavior.
			var effects: Array = env.compositor.compositor_effects
			if effects.has(clouds_resource):
				effects.erase(clouds_resource)
				env.compositor.compositor_effects = effects


func clouds_res_added() -> void:
	if clouds_resource and is_inside_tree():
		## Controls the env behavior.
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if env != null:
			if not env.compositor:
				env.compositor = Compositor.new()
				env.compositor.compositor_effects = [clouds_resource]
			else:
				## Controls the effects behavior.
				var effects: Array = env.compositor.compositor_effects
				if not effects.has(clouds_resource):
					effects.append(clouds_resource)
					env.compositor.compositor_effects = effects


func recursively_find_env(this_node: Node) -> WorldEnvironment:
	for child in this_node.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
		## Controls the result behavior.
		var result: WorldEnvironment = recursively_find_env(child)
		if result != null:
			return result
	return null


func retrieve_texture_data() -> void:
	if _updating_settings or not is_inside_tree() or clouds_resource == null:
		return

	_updating_settings = true

	_extralarge_clouds_domain = clouds_resource.extra_large_noise_scale / 2.0
	_large_clouds_domain = clouds_resource.large_noise_scale / 2.0
	_medium_clouds_domain = clouds_resource.medium_noise_scale / 2.0
	_small_clouds_domain = clouds_resource.small_noise_scale / 2.0

	## Controls the dir count behavior.
	var dir_count: int = tracked_directional_lights.size()
	## Controls the pt count behavior.
	var pt_count: int = tracked_point_lights.size()
	## Controls the eff count behavior.
	var eff_count: int = tracked_point_effectors.size()

	clouds_resource.directional_lights_data.resize(dir_count * 2)
	clouds_resource.point_lights_data.resize(pt_count * 2)
	clouds_resource.point_effector_data.resize(eff_count * 2)

	if tracked_directional_light_shadow_steps == null:
		tracked_directional_light_shadow_steps = []

	while tracked_directional_light_shadow_steps.size() < dir_count:
		tracked_directional_light_shadow_steps.append(12)

	for i in range(dir_count):
		## Controls the light behavior.
		var light: DirectionalLight3D = tracked_directional_lights[i]
		if light == null:
			continue

		## Controls the look dir behavior.
		var look_dir: Vector3 = light.global_transform.basis.z.normalized()
		clouds_resource.directional_lights_data[i * 2] = Vector4(
			look_dir.x, look_dir.y, look_dir.z, float(tracked_directional_light_shadow_steps[i])
		)

		## Controls the alpha val behavior.
		var alpha_val: float = (
			round(
				light.light_color.a * light.light_energy * directional_light_power_multiplier * 10.0
			)
			/ 10.0
		)

		clouds_resource.directional_lights_data[(i * 2) + 1] = Vector4(
			light.light_color.r, light.light_color.g, light.light_color.b, alpha_val
		)

	for i in range(pt_count):
		## Controls the light behavior.
		var light: OmniLight3D = tracked_point_lights[i]
		if light == null:
			continue

		## Controls the light pos behavior.
		var light_pos: Vector3 = light.global_position
		clouds_resource.point_lights_data[i * 2] = Vector4(
			light_pos.x, light_pos.y, light_pos.z, light.omni_range
		)

		## Controls the alpha val behavior.
		var alpha_val: float = (
			round(light.light_color.a * light.light_energy * point_light_power_multiplier * 10.0)
			/ 10.0
		)

		clouds_resource.point_lights_data[(i * 2) + 1] = Vector4(
			light.light_color.r, light.light_color.g, light.light_color.b, alpha_val
		)

	for i in range(eff_count):
		## Controls the node behavior.
		var node: SunshineCloudsEffector = tracked_point_effectors[i]
		if node == null:
			continue

		## Controls the node pos behavior.
		var node_pos: Vector3 = node.global_position
		clouds_resource.point_effector_data[i * 2] = Vector4(
			node_pos.x, node_pos.y, node_pos.z, node.radius
		)
		clouds_resource.point_effector_data[(i * 2) + 1] = Vector4(node.power, 0.0, 0.0, 0.0)

	clouds_resource.lights_updated = true
	_updating_settings = false


func wrap_vector(target: Vector3, domain_size: float) -> Vector3:
	if target.x > domain_size:
		target.x -= domain_size * 2.0
	elif target.x < -domain_size:
		target.x += domain_size * 2.0

	if target.y > domain_size:
		target.y -= domain_size * 2.0
	elif target.y < -domain_size:
		target.y += domain_size * 2.0

	if target.z > domain_size:
		target.z -= domain_size * 2.0
	elif target.z < -domain_size:
		target.z += domain_size * 2.0

	return target
