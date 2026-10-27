## Drives [SunshineCloudsGD] compositor parameters, wind offsets, light buffers, quality tiers,
## and weather transitions.
@tool
@icon("res://addons/SunshineClouds2/CloudsDriverIcon.svg")
class_name SunshineCloudsDriverGD
extends Node3D

## SceneTree group used by [VideoApplier] and [GraphicsManager] to broadcast quality and suspend states.
const CLOUDS_GROUP: StringName = &"sunshine_clouds"

## Signal name listened to on `/root/Events` if present at runtime.
const WEATHER_SIGNAL: StringName = &"weather_changed"

## Quality tier parameter table mapping tier names to resolution scale, step counts, and shadow steps.
const TIER_SETTINGS: Dictionary = {
	&"Off": {"enabled": false},
	&"Low":
	{
		"enabled": true,
		"resolution_scale": 2,
		"max_step_count": 96.0,
		"max_lighting_steps": 8.0,
		"shadow_steps": 0,
	},
	&"Medium":
	{
		"enabled": true,
		"resolution_scale": 1,
		"max_step_count": 160.0,
		"max_lighting_steps": 16.0,
		"shadow_steps": 4,
	},
	&"High":
	{
		"enabled": true,
		"resolution_scale": 1,
		"max_step_count": 300.0,
		"max_lighting_steps": 32.0,
		"shadow_steps": 6,
	},
}

@export var update_continuously: bool = false:
	get:
		return update_continuously
	set(value):
		update_continuously = value
		if is_inside_tree() and is_instance_valid(clouds_resource):
			_refresh_enabled()
			retrieve_texture_data()

@export_tool_button("Generate Clouds Resource", "Add") var generate_action = build_new_clouds

@export_group("Compositor Resource")
@export var clouds_resource: SunshineCloudsGD:
	get:
		return clouds_resource
	set(value):
		if is_inside_tree() and is_instance_valid(clouds_resource):
			clouds_res_removed()
		clouds_resource = value
		if is_inside_tree() and is_instance_valid(clouds_resource):
			clouds_res_added()
			_apply_tier_parameters()
			_refresh_enabled()
			retrieve_texture_data()

@export_group("Optional World Environment")
@export var ambience_sample_environment: Environment

@export_group("Light Controls")
@export var tracked_directional_lights: Array[DirectionalLight3D] = []:
	get:
		return tracked_directional_lights
	set(value):
		tracked_directional_lights = value
		if is_inside_tree() and is_instance_valid(clouds_resource):
			retrieve_texture_data()

@export var tracked_directional_light_shadow_steps: Array[int] = []:
	get:
		return tracked_directional_light_shadow_steps
	set(value):
		tracked_directional_light_shadow_steps = value
		if is_inside_tree() and is_instance_valid(clouds_resource):
			retrieve_texture_data()

@export var tracked_point_lights: Array[OmniLight3D] = []:
	get:
		return tracked_point_lights
	set(value):
		tracked_point_lights = value
		if is_inside_tree() and is_instance_valid(clouds_resource):
			retrieve_texture_data()

@export var tracked_point_effectors: Array[SunshineCloudsEffector] = []:
	get:
		return tracked_point_effectors
	set(value):
		tracked_point_effectors = value
		if is_inside_tree() and is_instance_valid(clouds_resource):
			retrieve_texture_data()

@export var directional_light_power_multiplier: float = 1.0
@export var point_light_power_multiplier: float = 1.0

@export_group("Wind Controls")
@export var origin_offset: Vector3 = Vector3.ZERO
@export var wind_direction: Vector3 = Vector3(1.0, 0.0, 1.0)
@export var extra_large_structures_wind_speed: float = 140.0
@export var large_structures_wind_speed: float = 100.0
@export var medium_structures_wind_speed: float = 40.0
@export var small_structures_wind_speed: float = 12.0

@export_group("Internal Use")
var extra_large_clouds_pos: Vector3 = Vector3.ZERO
var large_clouds_pos: Vector3 = Vector3.ZERO
var medium_clouds_pos: Vector3 = Vector3.ZERO
var small_clouds_pos: Vector3 = Vector3.ZERO

var _extralarge_clouds_domain: float = 0.0
var _large_clouds_domain: float = 0.0
var _medium_clouds_domain: float = 0.0
var _small_clouds_domain: float = 0.0

var _updating_settings: bool = false
var _quality_tier: StringName = &"High"
var _diorama_suspended: bool = false
var _weather_tween: Tween = null

var _dir_data_cache: Array[Vector4] = []
var _point_data_cache: Array[Vector4] = []
var _effector_data_cache: Array[Vector4] = []


## Joins the [constant CLOUDS_GROUP] group upon entering the SceneTree.
func _enter_tree() -> void:
	add_to_group(CLOUDS_GROUP)


## Ensures compositor wiring, applies initial visibility/tier state, and connects weather events.
func _ready() -> void:
	if not Engine.is_editor_hint():
		_connect_events_signal()

	if not is_instance_valid(clouds_resource):
		update_continuously = false
		set_process(false)
		return

	_ensure_compositor_wiring()
	_apply_tier_parameters()
	_refresh_enabled()

	if is_visible_in_tree() and update_continuously:
		call_deferred(&"retrieve_texture_data")


## Disconnects global weather signals and kills any active weather tween on exit.
func _exit_tree() -> void:
	if is_instance_valid(_weather_tween):
		_weather_tween.kill()
		_weather_tween = null
	if not Engine.is_editor_hint():
		_disconnect_events_signal()


## Responds to visibility changes to toggle the compositor effect and process loop.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_inside_tree():
			return
		_refresh_enabled()
		if is_visible_in_tree() and is_instance_valid(clouds_resource):
			retrieve_texture_data()


## Advances wind offsets and polls tracked lights for transform or color updates.
func _process(delta: float) -> void:
	if is_instance_valid(clouds_resource):
		clouds_resource.current_time = wrapf(
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
			small_clouds_pos += (
				(wind_direction * small_structures_wind_speed)
				+ (Vector3.UP * absf(small_structures_wind_speed))
			) * delta
			small_clouds_pos = wrap_vector(small_clouds_pos, _small_clouds_domain)

			clouds_resource.origin_offset = origin_offset
			clouds_resource.extra_large_scale_clouds_position = (
				origin_offset + extra_large_clouds_pos
			)
			clouds_resource.large_scale_clouds_position = origin_offset + large_clouds_pos
			clouds_resource.medium_scale_clouds_position = origin_offset + medium_clouds_pos
			clouds_resource.detail_clouds_position = origin_offset + small_clouds_pos

			clouds_resource.wind_direction = wind_direction

			if (
				clouds_resource.use_environment_fog > 0.0
				and is_instance_valid(ambience_sample_environment)
			):
				clouds_resource.sampled_environment_fog_color = (
					ambience_sample_environment.fog_light_color
				)

			if (
				tracked_directional_lights.size() * 2 != _dir_data_cache.size()
				or tracked_point_lights.size() * 2 != _point_data_cache.size()
				or tracked_directional_lights.size() != tracked_directional_light_shadow_steps.size()
			):
				retrieve_texture_data()
				return

			for i: int in range(tracked_directional_lights.size()):
				if tracked_directional_lights[i] == null:
					continue
				if direction_light_data_changed(
					tracked_directional_lights[i],
					tracked_directional_light_shadow_steps[i],
					_dir_data_cache[i * 2],
					_dir_data_cache[i * 2 + 1]
				):
					retrieve_texture_data()
					return

			for i: int in range(tracked_point_lights.size()):
				if tracked_point_lights[i] == null:
					continue
				if point_light_data_changed(
					tracked_point_lights[i], _point_data_cache[i * 2], _point_data_cache[i * 2 + 1]
				):
					retrieve_texture_data()
					return

			for i: int in range(tracked_point_effectors.size()):
				if tracked_point_effectors[i] == null:
					continue
				if point_effector_data_changed(
					tracked_point_effectors[i],
					_effector_data_cache[i * 2],
					_effector_data_cache[i * 2 + 1]
				):
					retrieve_texture_data()
					return
	else:
		update_continuously = false
		set_process(false)


## Applies the active quality tier ("Off", "Low", "Medium", "High") to [member clouds_resource].
func set_quality_tier(tier: StringName) -> void:
	var resolved_tier: StringName = tier if TIER_SETTINGS.has(tier) else &"High"
	_quality_tier = resolved_tier
	print("SunshineCloudsDriverGD: Setting quality tier -> ", _quality_tier)
	_apply_tier_parameters()
	_refresh_enabled()


## Returns the currently active quality tier name.
func get_quality_tier() -> StringName:
	return _quality_tier


## Suspends or resumes cloud rendering while the options diorama menu is active.
func set_suspended(value: bool) -> void:
	if _diorama_suspended == value:
		return
	_diorama_suspended = value
	print("SunshineCloudsDriverGD: Diorama suspend -> ", _diorama_suspended)
	_refresh_enabled()


## Returns true if cloud rendering is currently suspended by the diorama menu.
func is_suspended() -> bool:
	return _diorama_suspended


## Transitions cloud coverage, densities, height gradient, and wind speeds to [param weather]
## over [param duration] seconds, killing any in-flight weather [Tween] first.
func transition_to(weather: SunshineCloudsWeather, duration: float = 0.0) -> void:
	if not is_instance_valid(weather) or not is_instance_valid(clouds_resource):
		return

	if is_instance_valid(_weather_tween):
		_weather_tween.kill()
		_weather_tween = null

	print("SunshineCloudsDriverGD: Transitioning weather (duration=", duration, "s).")

	if (
		is_instance_valid(weather.height_gradient)
		and clouds_resource.height_gradient != weather.height_gradient
	):
		clouds_resource.height_gradient = weather.height_gradient
		clouds_resource.refresh_compute()

	if duration <= 0.0 or not is_inside_tree():
		clouds_resource.clouds_coverage = weather.clouds_coverage
		clouds_resource.clouds_density = weather.clouds_density
		clouds_resource.atmospheric_density = weather.atmospheric_density
		extra_large_structures_wind_speed = weather.extra_large_structures_wind_speed
		large_structures_wind_speed = weather.large_structures_wind_speed
		medium_structures_wind_speed = weather.medium_structures_wind_speed
		small_structures_wind_speed = weather.small_structures_wind_speed
		return

	_weather_tween = create_tween().set_parallel(true)
	_weather_tween.tween_property(
		clouds_resource, ^"clouds_coverage", weather.clouds_coverage, duration
	)
	_weather_tween.tween_property(
		clouds_resource, ^"clouds_density", weather.clouds_density, duration
	)
	_weather_tween.tween_property(
		clouds_resource, ^"atmospheric_density", weather.atmospheric_density, duration
	)
	_weather_tween.tween_property(
		self,
		^"extra_large_structures_wind_speed",
		weather.extra_large_structures_wind_speed,
		duration
	)
	_weather_tween.tween_property(
		self, ^"large_structures_wind_speed", weather.large_structures_wind_speed, duration
	)
	_weather_tween.tween_property(
		self, ^"medium_structures_wind_speed", weather.medium_structures_wind_speed, duration
	)
	_weather_tween.tween_property(
		self, ^"small_structures_wind_speed", weather.small_structures_wind_speed, duration
	)


## Returns the currently active weather [Tween], if any (used by unit tests).
func get_weather_tween() -> Tween:
	return _weather_tween


func sample_clouds() -> void:
	if not is_instance_valid(clouds_resource):
		return
	for i: int in range(64):
		clouds_resource.add_sample(return_data.bind(), Vector3(i * 1000.0, 6000.0, 0.0))


func return_data(pos: Vector3, sampledensity: float) -> void:
	print(pos, " ", sampledensity)


func build_new_clouds() -> void:
	if is_inside_tree():
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if is_instance_valid(env):
			if not is_instance_valid(ambience_sample_environment):
				ambience_sample_environment = env.environment
			clouds_resource = SunshineCloudsGD.new()
			update_continuously = true
		else:
			printerr("No world environment found.")


func clouds_res_removed() -> void:
	if is_instance_valid(clouds_resource) and is_inside_tree():
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if is_instance_valid(env) and is_instance_valid(env.compositor):
			var effects: Array[CompositorEffect] = env.compositor.compositor_effects
			effects.erase(clouds_resource)
			env.compositor.compositor_effects = effects


func clouds_res_added() -> void:
	if is_instance_valid(clouds_resource) and is_inside_tree():
		var env: WorldEnvironment = recursively_find_env(get_tree().root)
		if is_instance_valid(env):
			if not is_instance_valid(env.compositor):
				env.compositor = Compositor.new()
				env.compositor.compositor_effects = [clouds_resource]
			else:
				var effects: Array[CompositorEffect] = env.compositor.compositor_effects
				if not effects.has(clouds_resource):
					effects.append(clouds_resource)
					env.compositor.compositor_effects = effects


func recursively_find_env(this_node: Node) -> WorldEnvironment:
	for child: Node in this_node.get_children():
		if child is WorldEnvironment:
			return child as WorldEnvironment
		var result: WorldEnvironment = recursively_find_env(child)
		if is_instance_valid(result):
			return result
	return null


func retrieve_texture_data() -> void:
	if _updating_settings or not is_inside_tree():
		return
	_updating_settings = true
	if is_instance_valid(clouds_resource):
		_extralarge_clouds_domain = clouds_resource.extra_large_noise_scale / 2.0
		_large_clouds_domain = clouds_resource.large_noise_scale / 2.0
		_medium_clouds_domain = clouds_resource.medium_noise_scale / 2.0
		_small_clouds_domain = clouds_resource.small_noise_scale / 2.0

		var new_dir_data: Array[Vector4] = []
		var new_point_data: Array[Vector4] = []
		var new_effector_data: Array[Vector4] = []

		if not tracked_directional_light_shadow_steps:
			tracked_directional_light_shadow_steps = []

		if tracked_directional_light_shadow_steps.size() < tracked_directional_lights.size():
			for i: int in range(
				tracked_directional_lights.size() - tracked_directional_light_shadow_steps.size()
			):
				tracked_directional_light_shadow_steps.append(12)

		for i: int in range(tracked_directional_lights.size()):
			if is_instance_valid(tracked_directional_lights[i]):
				var light: DirectionalLight3D = tracked_directional_lights[i]
				var look_dir: Vector3 = light.global_transform.basis.z.normalized()
				new_dir_data.append(
					Vector4(
						look_dir.x,
						look_dir.y,
						look_dir.z,
						float(tracked_directional_light_shadow_steps[i])
					)
				)
				new_dir_data.append(
					Vector4(
						light.light_color.r,
						light.light_color.g,
						light.light_color.b,
						roundf(
							light.light_color.a
							* light.light_energy
							* directional_light_power_multiplier
							* 10.0
						) / 10.0
					)
				)

		for i: int in range(tracked_point_lights.size()):
			if is_instance_valid(tracked_point_lights[i]):
				var light: OmniLight3D = tracked_point_lights[i]
				var light_pos: Vector3 = light.global_position
				new_point_data.append(
					Vector4(light_pos.x, light_pos.y, light_pos.z, light.omni_range)
				)
				new_point_data.append(
					Vector4(
						light.light_color.r,
						light.light_color.g,
						light.light_color.b,
						roundf(
							light.light_color.a
							* light.light_energy
							* point_light_power_multiplier
							* 10.0
						) / 10.0
					)
				)

		for i: int in range(tracked_point_effectors.size()):
			if is_instance_valid(tracked_point_effectors[i]):
				var node: SunshineCloudsEffector = tracked_point_effectors[i]
				var node_pos: Vector3 = node.global_position
				new_effector_data.append(Vector4(node_pos.x, node_pos.y, node_pos.z, node.Radius))
				new_effector_data.append(Vector4(node.Power, 0.0, 0.0, 0.0))

		_dir_data_cache = new_dir_data.duplicate()
		_point_data_cache = new_point_data.duplicate()
		_effector_data_cache = new_effector_data.duplicate()

		RenderingServer.call_on_render_thread(
			_apply_lights_data.bind(new_dir_data, new_point_data, new_effector_data)
		)

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


func direction_light_data_changed(
	light: DirectionalLight3D, shadow_count: int, dir_data: Vector4, color_data: Vector4
) -> bool:
	var look_dir: Vector3 = light.global_transform.basis.z.normalized()
	return (
		not is_equal_approx(look_dir.x, dir_data.x)
		or not is_equal_approx(look_dir.y, dir_data.y)
		or not is_equal_approx(look_dir.z, dir_data.z)
		or float(shadow_count) != dir_data.w
		or light.light_color.r != color_data.x
		or light.light_color.g != color_data.y
		or light.light_color.b != color_data.z
		or (
			roundf(
				light.light_color.a
				* light.light_energy
				* directional_light_power_multiplier
				* 10.0
			) / 10.0
			!= roundf(color_data.w * 10.0) / 10.0
		)
	)


func point_light_data_changed(
	light: OmniLight3D, dir_data: Vector4, color_data: Vector4
) -> bool:
	return (
		light.global_position.x != dir_data.x
		or light.global_position.y != dir_data.y
		or light.global_position.z != dir_data.z
		or light.omni_range != dir_data.w
		or light.light_color.r != color_data.x
		or light.light_color.g != color_data.y
		or light.light_color.b != color_data.z
		or (
			roundf(
				light.light_color.a
				* light.light_energy
				* point_light_power_multiplier
				* 10.0
			) / 10.0
			!= roundf(color_data.w * 10.0) / 10.0
		)
	)


func point_effector_data_changed(
	node: SunshineCloudsEffector, dir_data: Vector4, color_data: Vector4
) -> bool:
	return (
		node.global_position.x != dir_data.x
		or node.global_position.y != dir_data.y
		or node.global_position.z != dir_data.z
		or node.Radius != dir_data.w
		or node.Power != color_data.x
	)


## Evaluates the single source of truth for [member CompositorEffect.enabled] and process state.
func _refresh_enabled() -> void:
	var vis: bool = is_visible_in_tree() if is_inside_tree() else visible
	var should_enable: bool = vis and (_quality_tier != &"Off") and (not _diorama_suspended)
	if is_instance_valid(clouds_resource):
		clouds_resource.enabled = should_enable
	set_process(should_enable and is_instance_valid(clouds_resource))


## Writes tier resolution scale, raymarch step limits, and shadow steps into [member clouds_resource].
func _apply_tier_parameters() -> void:
	if not is_instance_valid(clouds_resource):
		return
	var raw_tier: Variant = TIER_SETTINGS.get(_quality_tier, TIER_SETTINGS[&"High"])
	var tier_dict: Dictionary = raw_tier if raw_tier is Dictionary else {}
	if tier_dict.has("resolution_scale"):
		var target_scale: int = int(tier_dict["resolution_scale"])
		if clouds_resource.resolution_scale != target_scale:
			clouds_resource.resolution_scale = target_scale
	if tier_dict.has("max_step_count"):
		clouds_resource.max_step_count = float(tier_dict["max_step_count"])
	if tier_dict.has("max_lighting_steps"):
		clouds_resource.max_lighting_steps = float(tier_dict["max_lighting_steps"])
	if tier_dict.has("shadow_steps"):
		clouds_resource.shadow_steps = int(tier_dict["shadow_steps"])


## Connects dynamically to `/root/Events.weather_changed` if the autoload exists.
func _connect_events_signal() -> void:
	if not is_inside_tree():
		return
	var events_node: Node = get_tree().root.get_node_or_null("Events")
	if is_instance_valid(events_node) and events_node.has_signal(WEATHER_SIGNAL):
		var cb: Callable = _on_weather_changed
		if not events_node.is_connected(WEATHER_SIGNAL, cb):
			events_node.connect(WEATHER_SIGNAL, cb)


## Disconnects dynamically from `/root/Events.weather_changed` on tree exit.
func _disconnect_events_signal() -> void:
	if not is_inside_tree():
		return
	var events_node: Node = get_tree().root.get_node_or_null("Events")
	if is_instance_valid(events_node) and events_node.has_signal(WEATHER_SIGNAL):
		var cb: Callable = _on_weather_changed
		if events_node.is_connected(WEATHER_SIGNAL, cb):
			events_node.disconnect(WEATHER_SIGNAL, cb)


## Handles global weather transition signals emitted by `/root/Events`.
func _on_weather_changed(weather: Resource, duration: float = 0.0) -> void:
	var clouds_weather: SunshineCloudsWeather = weather as SunshineCloudsWeather
	if is_instance_valid(clouds_weather):
		transition_to(clouds_weather, duration)


## Ensures the scene [WorldEnvironment] compositor references [member clouds_resource]
## and warns if a different [SunshineCloudsGD] instance is already present.
func _ensure_compositor_wiring() -> void:
	if not is_inside_tree() or not is_instance_valid(clouds_resource):
		return
	var search_root: Node = (
		get_tree().current_scene
		if is_instance_valid(get_tree().current_scene)
		else get_tree().root
	)
	var env: WorldEnvironment = recursively_find_env(search_root)
	if not is_instance_valid(env):
		return
	if not is_instance_valid(env.compositor):
		env.compositor = Compositor.new()

	var effects: Array[CompositorEffect] = env.compositor.compositor_effects
	var has_same: bool = false
	for eff: CompositorEffect in effects:
		if eff == clouds_resource:
			has_same = true
		elif eff is SunshineCloudsGD:
			push_warning(
				"SunshineCloudsDriverGD: WorldEnvironment compositor already contains a different SunshineCloudsGD instance!"
			)

	if not has_same:
		effects.append(clouds_resource)
		env.compositor.compositor_effects = effects


func _apply_lights_data(
	dir_data: Array[Vector4], point_data: Array[Vector4], effector_data: Array[Vector4]
) -> void:
	if not is_instance_valid(clouds_resource):
		return
	clouds_resource.directional_lights_data = dir_data
	clouds_resource.point_lights_data = point_data
	clouds_resource.point_effector_data = effector_data
	clouds_resource.lights_updated = true
