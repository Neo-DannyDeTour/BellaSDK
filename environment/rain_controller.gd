@tool
## Self-contained GPU rain and storm controller with Inspector live tuning, Layer 1 roof
## occlusion, Layer 2 player zone detection, and [Events.rain_vfx_toggled] eye droplet dispatch.
# class_name RainController
extends Node3D

## Emitted when a runtime weather transition Tween finishes.
signal weather_transition_completed(final_intensity: float)

## Shader uniform name for half-size boundary extents.
const _PARAM_EXTENTS: StringName = &"box_extents"

## Shader uniform name for storm turbulence and vortex population ratio.
const _PARAM_SWIRL: StringName = &"swirl_intensity"

## Shader uniform name for directional wind velocity vector.
const _PARAM_WIND: StringName = &"wind_velocity"

## Shader uniform name for radial camera-proximity spawn concentration.
const _PARAM_NEAR_BIAS: StringName = &"near_camera_bias"

## Minimum squared camera movement (1.5m) before snapping volume and re-testing roof occlusion.
const _SNAP_DIST_SQ: float = 2.25

## Render Layer 1 bitmask for static environment roof heightfield occlusion.
const _ENV_RENDER_LAYER: int = 1

## Physics Layer 1 bitmask for static environment roof raycast checks.
const _ENV_PHYSICS_MASK: int = 1

## Physics Layer 2 bitmask for player body zone detection.
const _PLAYER_PHYSICS_MASK: int = 2

@export_group("Rain State")
@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_inside_tree():
			_sync_state()

@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_sync_state()

@export_range(0.0, 1.0, 0.01) var swirl: float = 0.35:
	set(value):
		swirl = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_sync_state()

@export_group("Boundaries & Volume")
@export var volume_size: Vector3 = Vector3(30.0, 20.0, 30.0):
	set(value):
		volume_size = value.max(Vector3(2.0, 2.0, 2.0))
		if is_inside_tree():
			_sync_volume()

@export_range(1024, 65536, 512) var max_particles: int = 25088:
	set(value):
		max_particles = maxi(value, 1024)
		if is_inside_tree() and is_instance_valid(_particles):
			_particles.amount = max_particles

@export var follow_camera: bool = true:
	set(value):
		follow_camera = value
		if is_inside_tree():
			_sync_state()

@export_range(0.0, 1.0, 0.05) var near_camera_bias: float = 0.65:
	set(value):
		near_camera_bias = clampf(value, 0.0, 1.0)
		if is_inside_tree():
			_sync_state()

@export_group("Wind & Shaders")
@export var base_wind: Vector3 = Vector3(2.0, 0.0, 1.0):
	set(value):
		base_wind = value
		if is_inside_tree():
			_sync_state()

@export var storm_wind_multiplier: float = 4.5:
	set(value):
		storm_wind_multiplier = maxf(value, 1.0)
		if is_inside_tree():
			_sync_state()

@export var process_shader: Shader:
	set(value):
		process_shader = value
		if is_inside_tree():
			_rebuild_materials()

@export var drop_shader: Shader:
	set(value):
		drop_shader = value
		if is_inside_tree():
			_rebuild_materials()

var _particles: GPUParticles3D
var _heightfield: GPUParticlesCollisionHeightField3D
var _zone_area: Area3D
var _zone_shape: CollisionShape3D
var _process_mat: ShaderMaterial
var _weather_tween: Tween
var _active_camera: Camera3D
var _player_body: Node3D
var _is_player_inside_zone: bool = false
var _last_emitted_vfx: float = -1.0
var _last_check_pos: Vector3 = Vector3(99999.0, 99999.0, 99999.0)


## Initializes child particle, heightfield, and Area3D nodes and applies initial Inspector state.
func _ready() -> void:
	_ensure_nodes()
	assert(is_instance_valid(_particles), "RainController: _particles failed to initialize.")
	assert(is_instance_valid(_heightfield), "RainController: _heightfield failed to initialize.")
	assert(is_instance_valid(_zone_area), "RainController: _zone_area failed to initialize.")
	_sync_volume()
	_sync_state()


## Clears screen rain droplets and disconnects signals when removed from the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(_weather_tween):
		_weather_tween.kill()
	if not Engine.is_editor_hint() and _last_emitted_vfx > 0.0:
		Events.rain_vfx_toggled.emit(0.0)
		if is_instance_valid(_player_body) and _player_body.has_method(&"exit_rain_volume"):
			_player_body.call(&"exit_rain_volume")


## Snaps camera-following rain volume and updates roof-occluded eye droplet VFX on movement.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not is_instance_valid(_active_camera):
		var vp: Viewport = get_viewport()
		_active_camera = vp.get_camera_3d() if is_instance_valid(vp) else null
		if not is_instance_valid(_active_camera):
			return

	var cam_pos: Vector3 = _active_camera.global_position
	if follow_camera:
		var target_pos: Vector3 = Vector3(cam_pos.x, cam_pos.y + volume_size.y * 0.25, cam_pos.z)
		if global_position.distance_squared_to(target_pos) >= _SNAP_DIST_SQ:
			global_position = target_pos

	if cam_pos.distance_squared_to(_last_check_pos) >= _SNAP_DIST_SQ:
		_last_check_pos = cam_pos
		_update_screen_rain_vfx()


## Smoothly transitions rain intensity and storm swirl over [param duration].
func set_weather(target_intensity: float, target_swirl: float, duration: float = 4.0) -> void:
	var clamped_int: float = clampf(target_intensity, 0.0, 1.0)
	var clamped_swirl: float = clampf(target_swirl, 0.0, 1.0)
	print("RainController: Transitioning intensity=%.2f, swirl=%.2f" % [clamped_int, clamped_swirl])

	if clamped_int > 0.0 and not enabled:
		enabled = true

	if is_instance_valid(_weather_tween):
		_weather_tween.kill()
	_weather_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_weather_tween.tween_method(
		_apply_tween_step, Vector2(intensity, swirl), Vector2(clamped_int, clamped_swirl), duration
	)
	_weather_tween.chain().tween_callback(_on_weather_tween_finished.bind(clamped_int))


## Creates or retrieves internal particle, heightfield, and player trigger zone nodes.
func _ensure_nodes() -> void:
	_particles = get_node_or_null("RainParticles") as GPUParticles3D
	if not is_instance_valid(_particles):
		_particles = GPUParticles3D.new()
		_particles.name = "RainParticles"
		add_child(_particles)

	_heightfield = get_node_or_null("RoofHeightField") as GPUParticlesCollisionHeightField3D
	if not is_instance_valid(_heightfield):
		_heightfield = GPUParticlesCollisionHeightField3D.new()
		_heightfield.name = "RoofHeightField"
		add_child(_heightfield)

	_heightfield.cull_mask = _ENV_RENDER_LAYER
	_heightfield.follow_camera_enabled = false
	_heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED

	_zone_area = get_node_or_null("RainZoneArea") as Area3D
	if not is_instance_valid(_zone_area):
		_zone_area = Area3D.new()
		_zone_area.name = "RainZoneArea"
		add_child(_zone_area)

	_zone_area.collision_layer = 0
	_zone_area.collision_mask = _PLAYER_PHYSICS_MASK
	_zone_area.monitorable = false
	_zone_area.monitoring = true

	if not _zone_area.body_entered.is_connected(_on_body_entered):
		_zone_area.body_entered.connect(_on_body_entered)
	if not _zone_area.body_exited.is_connected(_on_body_exited):
		_zone_area.body_exited.connect(_on_body_exited)

	_zone_shape = _zone_area.get_node_or_null("ZoneCollisionShape") as CollisionShape3D
	if not is_instance_valid(_zone_shape):
		_zone_shape = CollisionShape3D.new()
		_zone_shape.name = "ZoneCollisionShape"
		var box: BoxShape3D = BoxShape3D.new()
		box.size = volume_size
		_zone_shape.shape = box
		_zone_area.add_child(_zone_shape)

	_rebuild_materials()
	_particles.amount = max_particles
	_particles.lifetime = 1.35
	_particles.preprocess = 0.5
	_particles.local_coords = false


## Binds assigned [member process_shader] and [member drop_shader] to the particle node.
func _rebuild_materials() -> void:
	if not is_instance_valid(_particles):
		return
	if not is_instance_valid(process_shader):
		process_shader = (
			preload("res://shaders/rain_process.gdshader")
			if ResourceLoader.exists("res://shaders/rain_process.gdshader")
			else null
		)
	if not is_instance_valid(drop_shader):
		drop_shader = (
			preload("res://shaders/rain_drop.gdshader")
			if ResourceLoader.exists("res://shaders/rain_drop.gdshader")
			else null
		)

	_process_mat = _particles.process_material as ShaderMaterial
	if not is_instance_valid(_process_mat):
		_process_mat = ShaderMaterial.new()
		_particles.process_material = _process_mat
	if is_instance_valid(process_shader):
		_process_mat.shader = process_shader

	var quad: QuadMesh = _particles.draw_pass_1 as QuadMesh
	if not is_instance_valid(quad):
		quad = QuadMesh.new()
		_particles.draw_pass_1 = quad
	var d_mat: ShaderMaterial = quad.material as ShaderMaterial
	if not is_instance_valid(d_mat):
		d_mat = ShaderMaterial.new()
		quad.material = d_mat
	if is_instance_valid(drop_shader):
		d_mat.shader = drop_shader


## Synchronizes particle box extents, visibility AABB, heightfield, and Area3D collision bounds.
func _sync_volume() -> void:
	if not is_instance_valid(_particles) or not is_instance_valid(_heightfield):
		return
	var half_extents: Vector3 = volume_size * 0.5
	_particles.visibility_aabb = AABB(-half_extents, volume_size)
	_heightfield.size = volume_size
	if is_instance_valid(_zone_shape) and _zone_shape.shape is BoxShape3D:
		(_zone_shape.shape as BoxShape3D).size = volume_size
	if is_instance_valid(_process_mat):
		_process_mat.set_shader_parameter(_PARAM_EXTENTS, half_extents)


## Synchronizes emission state, particle shader uniforms, and player screen droplets.
func _sync_state() -> void:
	if not is_instance_valid(_particles) or not is_instance_valid(_process_mat):
		return
	var active_rain: bool = enabled and intensity > 0.001
	_particles.emitting = active_rain
	_particles.amount_ratio = intensity if active_rain else 0.0

	var wind_vec: Vector3 = base_wind * lerpf(1.0, storm_wind_multiplier, swirl)
	_process_mat.set_shader_parameter(_PARAM_SWIRL, swirl)
	_process_mat.set_shader_parameter(_PARAM_WIND, wind_vec)
	_process_mat.set_shader_parameter(_PARAM_NEAR_BIAS, near_camera_bias if follow_camera else 0.0)

	if not Engine.is_editor_hint():
		_update_screen_rain_vfx()
		var needs_loop: bool = active_rain and (follow_camera or _is_player_inside_zone)
		set_process(needs_loop)
	else:
		set_process(false)
	set_physics_process(false)


## Tracks player entry into the rain volume and updates screen rain droplets.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if body.is_in_group(&"player") or body.is_class("Player"):
		print("RainController: Player entered rain zone -> ", body.name)
		_player_body = body
		_is_player_inside_zone = true
		_last_check_pos = Vector3(99999.0, 99999.0, 99999.0)
		_update_screen_rain_vfx()
		set_process(enabled and intensity > 0.001)


## Tracks player exit from the rain volume and clears screen rain droplets.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if body == _player_body or body.is_in_group(&"player") or body.is_class("Player"):
		print("RainController: Player exited rain zone -> ", body.name)
		_is_player_inside_zone = false
		_update_screen_rain_vfx()
		if not follow_camera:
			set_process(false)


## Checks upward Layer 1 roof occlusion and emits [signal Events.rain_vfx_toggled].
func _update_screen_rain_vfx() -> void:
	if Engine.is_editor_hint():
		return
	var active_rain: bool = enabled and intensity > 0.001
	var in_rain_space: bool = follow_camera or _is_player_inside_zone
	var target_vfx: float = 0.0

	if active_rain and in_rain_space:
		var occluded: bool = _is_camera_under_roof()
		if not occluded:
			# Boost droplet intensity during storms (up to 1.35 for heavy swirling gusts)
			target_vfx = clampf(intensity * lerpf(0.85, 1.35, swirl), 0.0, 1.35)

	if not is_equal_approx(target_vfx, _last_emitted_vfx):
		var was_wet: bool = _last_emitted_vfx > 0.001
		var is_wet: bool = target_vfx > 0.001
		_last_emitted_vfx = target_vfx
		Events.rain_vfx_toggled.emit(target_vfx)
		if is_instance_valid(_player_body):
			if is_wet and not was_wet and _player_body.has_method(&"enter_rain_volume"):
				_player_body.call(&"enter_rain_volume")
			elif not is_wet and was_wet and _player_body.has_method(&"exit_rain_volume"):
				_player_body.call(&"exit_rain_volume")


## Raycasts upward on Physics Layer 1 (Environment) to check if a roof blocks rain above camera.
func _is_camera_under_roof() -> bool:
	var check_node: Node3D = _active_camera if is_instance_valid(_active_camera) else _player_body
	if not is_instance_valid(check_node) or not is_inside_tree():
		return false
	var world: World3D = get_world_3d()
	if not is_instance_valid(world):
		return false
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if not is_instance_valid(space):
		return false

	var from_pos: Vector3 = check_node.global_position + Vector3(0.0, 0.25, 0.0)
	var to_pos: Vector3 = from_pos + Vector3(0.0, volume_size.y, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_pos, to_pos, _ENV_PHYSICS_MASK
	)
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.is_empty()


## Applies interpolated intensity and swirl values during runtime Tween transitions.
func _apply_tween_step(state: Vector2) -> void:
	intensity = state.x
	swirl = state.y


## Halts particle emission when a transition Tween reaches zero intensity.
func _on_weather_tween_finished(final_intensity: float) -> void:
	if is_zero_approx(final_intensity):
		enabled = false
		print("RainController: Rain halted.")
	weather_transition_completed.emit(final_intensity)
