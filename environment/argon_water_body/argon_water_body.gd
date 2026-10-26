@tool
class_name ArgonWaterBody
extends MeshInstance3D
## Controls 3D water volume geometry, CPU/GPU waves, buoyancy, wakes, and camera submersion.

## Emitted when a body impacts or exits the water surface with sufficient vertical speed.
signal splashed(global_pos: Vector3, velocity: float)

## Group assigned to the swimmable [Area3D].
const GROUP_WATER_AREA: StringName = &"water_area"
## Target audio bus for surface and underwater audio players.
const BUS_SFX: StringName = &"SFX"
## Callback method invoked on bodies entering water.
const METHOD_ENTER_WATER: StringName = &"enter_water"
## Callback method invoked on bodies exiting water.
const METHOD_EXIT_WATER: StringName = &"exit_water"
## Property set on bodies referencing this [ArgonWaterBody] node.
const PROP_CURRENT_WATER_NODE: StringName = &"current_water_node"
## Property set on bodies indicating water submersion status.
const PROP_IS_IN_WATER: StringName = &"is_in_water"
## Property checked on [RigidBody3D] to detect custom multi-probe buoyancy.
const PROP_PROBES: StringName = &"_probes"
## Maximum circular buffer capacity for dynamic surface ripples.
const MAX_RIPPLES: int = 16
## Minimum squared horizontal speed (0.7 m/s)^2 required to emit wake ripples.
const MIN_WAKE_SPEED_SQ: float = 0.49
## Minimum time interval in seconds between wake spawns per body.
const WAKE_COOLDOWN_SEC: float = 0.16
## Minimum squared XZ distance (0.3 m)^2 before spawning a new wake ripple.
const WAKE_MIN_DIST_SQ: float = 0.09
## Primary trochoidal wave propagation direction.
const WAVE_DIR_0: Vector2 = Vector2(0.924678, 0.380749)
## Secondary trochoidal wave propagation direction.
const WAVE_DIR_1: Vector2 = Vector2(-0.451481, 0.892281)
## Tertiary trochoidal wave propagation direction.
const WAVE_DIR_2: Vector2 = Vector2(0.319222, -0.947680)
## Shader parameter for synchronized water simulation time.
const PARAM_WATER_TIME: StringName = &"water_time"
## Shader parameter for the 16-slot ripple ring buffer.
const PARAM_RIPPLES: StringName = &"ripples"
## Shader parameter for wave amplitude.
const PARAM_WAVE_AMP: StringName = &"wave_amplitude"
## Shader parameter for wave frequency.
const PARAM_WAVE_FREQ: StringName = &"wave_frequency"
## Shader parameter for wave speed.
const PARAM_WAVE_SPEED: StringName = &"wave_speed"
## Shader parameter for wave steepness.
const PARAM_WAVE_STEEP: StringName = &"wave_steepness"
## Signal name on Events autoload for waterfall VFX.
const SIG_WATERFALL_VFX: StringName = &"waterfall_vfx_toggled"
## Signal name on Events autoload for underwater post-processing VFX.
const SIG_UNDERWATER_VFX: StringName = &"underwater_vfx_toggled"
## Signal name on Events autoload for screen water sheet wipe effect.
const SIG_WATER_SHEET_WIPE: StringName = &"water_sheet_wipe_requested"
## Ripple lifetime in seconds before slot expiration.
const RIPPLE_MAX_AGE: float = 4.0

## Dimensions of the water volume box in meters.
@export var water_size: Vector3 = Vector3(16.0, 4.0, 16.0):
	set = _set_water_size
## Subdivision density multiplier per meter on X and Z axes.
@export var vertex_density: float = 2.0:
	set = _set_vertex_density
## Primary trochoidal wave amplitude in meters.
@export var wave_amplitude: float = 0.14:
	set = _set_wave_amplitude
## Primary trochoidal wave spatial frequency.
@export var wave_frequency: float = 1.15:
	set = _set_wave_frequency
## Primary trochoidal wave temporal speed.
@export var wave_speed: float = 1.6:
	set = _set_wave_speed
## Trochoidal crest sharpness factor (0.0 to 1.0).
@export_range(0.0, 1.0, 0.01) var wave_steepness: float = 0.45:
	set = _set_wave_steepness
## Radial frequency of impact ripples.
@export var ripple_frequency: float = 10.0
## Expansion speed of impact ripples in meters per second.
@export var ripple_speed: float = 4.5
## Temporal decay rate for dynamic ripples.
@export var ripple_decay: float = 1.8
## Spatial decay rate for dynamic ripples.
@export var ripple_spatial_decay: float = 0.85
## Upward Archimedes buoyancy acceleration multiplier for submerged rigid bodies.
@export var buoyancy_force: float = 18.0
## Horizontal linear drag coefficient applied in water.
@export var water_linear_drag: float = 2.2
## Vertical damping drag coefficient applied in water.
@export var water_vertical_drag: float = 3.8
## Rotational damping drag coefficient applied in water.
@export var water_angular_drag: float = 2.5
## Minimum vertical speed required to trigger an entry or exit splash.
@export var min_splash_velocity: float = 2.2
## Fallback non-volumetric underwater fog color when volumetric fog is disabled.
@export var fallback_fog_color: Color = Color(0.03, 0.11, 0.13, 1.0)
## Maximum camera distance squared before shader time updates pause.
@export var max_active_dist_sq: float = 6400.0

var _material_rid: RID = RID()
var _ripples: Array[Vector4] = []
var _ripple_packed: PackedVector4Array = PackedVector4Array()
var _ripple_head: int = 0
var _active_ripple_count: int = 0
var _rigid_bodies: Array[RigidBody3D] = []
var _character_bodies: Array[CharacterBody3D] = []
var _wake_cooldowns: Dictionary[int, float] = {}
var _wake_last_pos: Dictionary[int, Vector2] = {}
var _is_camera_submerged: bool = false
var _last_cam_y: float = 0.0
var _env_backup_valid: bool = false
var _saved_fog_enabled: bool = false
var _saved_fog_mode: Environment.FogMode = Environment.FOG_MODE_EXPONENTIAL
var _saved_fog_color: Color = Color.WHITE
var _saved_fog_density: float = 0.01
var _saved_fog_sky_affect: float = 1.0
var _saved_fog_begin: float = 10.0
var _saved_fog_end: float = 100.0

@onready var _swimmable_area: Area3D = %SwimmableArea3D
@onready var _collision_shape: CollisionShape3D = %CollisionShape3D
@onready var _camera_cast: ShapeCast3D = %CameraPosShapeCast3D
@onready var _fog_volume: FogVolume = %FogVolume
@onready var _surface_audio: AudioStreamPlayer3D = %SurfaceAudio
@onready var _underwater_audio: AudioStreamPlayer3D = %UnderwaterAudio


## Initializes geometry, shader RID cache, ripple ring buffer, and area signals.
func _ready() -> void:
	_init_ripple_buffers()
	_cache_material_rid()
	_rebuild_water_geometry()
	_sync_wave_uniforms()
	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		return
	assert(_swimmable_area != null, "ArgonWaterBody: %SwimmableArea3D missing.")
	assert(_collision_shape != null, "ArgonWaterBody: %CollisionShape3D missing.")
	assert(_camera_cast != null, "ArgonWaterBody: %CameraPosShapeCast3D missing.")
	assert(_fog_volume != null, "ArgonWaterBody: %FogVolume missing.")
	assert(_surface_audio != null, "ArgonWaterBody: %SurfaceAudio missing.")
	assert(_underwater_audio != null, "ArgonWaterBody: %UnderwaterAudio missing.")
	_configure_audio_buses()
	if not _swimmable_area.is_in_group(GROUP_WATER_AREA):
		_swimmable_area.add_to_group(GROUP_WATER_AREA)
	if not _swimmable_area.body_entered.is_connected(_on_body_entered):
		_swimmable_area.body_entered.connect(_on_body_entered)
	if not _swimmable_area.body_exited.is_connected(_on_body_exited):
		_swimmable_area.body_exited.connect(_on_body_exited)
	set_process(true)
	set_physics_process(true)


## Restores any overridden environment fog state and disconnects signals when leaving tree.
func _exit_tree() -> void:
	if _is_camera_submerged:
		_restore_fallback_environment_fog()
	if is_instance_valid(_swimmable_area):
		if _swimmable_area.body_entered.is_connected(_on_body_entered):
			_swimmable_area.body_entered.disconnect(_on_body_entered)
		if _swimmable_area.body_exited.is_connected(_on_body_exited):
			_swimmable_area.body_exited.disconnect(_on_body_exited)


## Updates GPU shader clock and expires finished ripples when within camera range.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if is_instance_valid(cam):
		var dist_sq: float = global_position.distance_squared_to(cam.global_position)
		if dist_sq > max_active_dist_sq and not _is_camera_submerged:
			return
	var now: float = _get_water_time()
	if _material_rid.is_valid():
		RenderingServer.material_set_param(_material_rid, PARAM_WATER_TIME, now)
	if _active_ripple_count > 0:
		_expire_old_ripples(now)


## Evaluates buoyancy forces, wake generation, and camera submersion state at 60 Hz.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var cam_near: bool = _update_camera_submersion(delta)
	var has_bodies: bool = not _rigid_bodies.is_empty() or not _character_bodies.is_empty()
	if not has_bodies and not cam_near and not _is_camera_submerged:
		set_physics_process(false)
		return
	var now: float = _get_water_time()
	_process_rigid_bodies(delta, now)
	_process_character_bodies(now)


## Evaluates world-space Y surface elevation at [param global_pos] matching shader math 1:1.
func get_wave_height_at_pos(global_pos: Vector3) -> float:
	var base_y: float = global_position.y + water_size.y * 0.5
	var xz: Vector2 = Vector2(global_pos.x, global_pos.z)
	var t: float = _get_water_time()
	var h: float = 0.0
	h += _eval_octave_height(
		xz, WAVE_DIR_0, wave_amplitude, wave_frequency, wave_speed, wave_steepness, t
	)
	h += _eval_octave_height(
		xz,
		WAVE_DIR_1,
		wave_amplitude * 0.5,
		wave_frequency * 1.85,
		wave_speed * 1.35,
		wave_steepness * 0.8,
		t
	)
	h += _eval_octave_height(
		xz,
		WAVE_DIR_2,
		wave_amplitude * 0.25,
		wave_frequency * 3.4,
		wave_speed * 1.75,
		wave_steepness * 0.6,
		t
	)
	if _active_ripple_count > 0:
		for i: int in range(MAX_RIPPLES):
			var r: Vector4 = _ripples[i]
			if r.w > 0.001:
				var age: float = t - r.z
				if age >= 0.0 and age < RIPPLE_MAX_AGE:
					var dx: float = xz.x - r.x
					var dz: float = xz.y - r.y
					var dist: float = sqrt(dx * dx + dz * dz + 0.0001)
					var radius: float = age * ripple_speed
					if dist < radius:
						var front: float = clampf(1.0 - dist / maxf(radius, 0.001), 0.0, 1.0)
						var env: float = (
							r.w
							* exp(-age * ripple_decay)
							* exp(-dist * ripple_spatial_decay)
							* front
						)
						h += sin((dist - radius) * ripple_frequency) * env
	return base_y + h


## Reconstructs the normalized 3D surface normal at [param global_pos] using analytical derivatives.
func get_water_surface_normal(global_pos: Vector3) -> Vector3:
	var xz: Vector2 = Vector2(global_pos.x, global_pos.z)
	var t: float = _get_water_time()
	var grad: Vector2 = Vector2.ZERO
	grad += _eval_octave_grad(
		xz, WAVE_DIR_0, wave_amplitude, wave_frequency, wave_speed, wave_steepness, t
	)
	grad += _eval_octave_grad(
		xz,
		WAVE_DIR_1,
		wave_amplitude * 0.5,
		wave_frequency * 1.85,
		wave_speed * 1.35,
		wave_steepness * 0.8,
		t
	)
	grad += _eval_octave_grad(
		xz,
		WAVE_DIR_2,
		wave_amplitude * 0.25,
		wave_frequency * 3.4,
		wave_speed * 1.75,
		wave_steepness * 0.6,
		t
	)
	if _active_ripple_count > 0:
		for i: int in range(MAX_RIPPLES):
			var r: Vector4 = _ripples[i]
			if r.w > 0.001:
				var age: float = t - r.z
				if age >= 0.0 and age < RIPPLE_MAX_AGE:
					var delta_xz: Vector2 = xz - Vector2(r.x, r.y)
					var dist: float = sqrt(delta_xz.length_squared() + 0.0001)
					var radius: float = age * ripple_speed
					if dist < radius:
						var front: float = clampf(1.0 - dist / maxf(radius, 0.001), 0.0, 1.0)
						var env: float = (
							r.w
							* exp(-age * ripple_decay)
							* exp(-dist * ripple_spatial_decay)
							* front
						)
						var d_val: float = (
							cos((dist - radius) * ripple_frequency) * ripple_frequency * env
						)
						grad += (delta_xz / dist) * d_val
	return Vector3(-grad.x, 1.0, -grad.y).normalized()


## Writes a new ripple into the 16-slot ring buffer and flushes the array to the GPU.
func spawn_ripple(global_pos: Vector3, impact_strength: float) -> void:
	if _ripples.size() < MAX_RIPPLES:
		_init_ripple_buffers()
	var clamped_amp: float = clampf(impact_strength, 0.01, 0.65)
	var now: float = _get_water_time()
	var slot_vec: Vector4 = Vector4(global_pos.x, global_pos.z, now, clamped_amp)
	_ripples[_ripple_head] = slot_vec
	_ripple_packed[_ripple_head] = slot_vec
	_ripple_head = (_ripple_head + 1) % MAX_RIPPLES
	_active_ripple_count = mini(_active_ripple_count + 1, MAX_RIPPLES)
	_flush_ripples_to_gpu()


## Updates [member water_size] and rebuilds geometry and collision bounds.
func _set_water_size(val: Vector3) -> void:
	water_size = Vector3(maxf(val.x, 0.5), maxf(val.y, 0.5), maxf(val.z, 0.5))
	if is_inside_tree():
		_rebuild_water_geometry()


## Updates [member vertex_density] and rebuilds subdivided [BoxMesh].
func _set_vertex_density(val: float) -> void:
	vertex_density = clampf(val, 0.25, 16.0)
	if is_inside_tree():
		_rebuild_water_geometry()


## Updates [member wave_amplitude], culling AABB, and GPU shader uniform.
func _set_wave_amplitude(val: float) -> void:
	wave_amplitude = maxf(val, 0.0)
	if is_inside_tree():
		_update_custom_aabb()
		_sync_wave_uniforms()


## Updates [member wave_frequency] and GPU shader uniform.
func _set_wave_frequency(val: float) -> void:
	wave_frequency = maxf(val, 0.01)
	if is_inside_tree():
		_sync_wave_uniforms()


## Updates [member wave_speed] and GPU shader uniform.
func _set_wave_speed(val: float) -> void:
	wave_speed = maxf(val, 0.0)
	if is_inside_tree():
		_sync_wave_uniforms()


## Updates [member wave_steepness] and GPU shader uniform.
func _set_wave_steepness(val: float) -> void:
	wave_steepness = clampf(val, 0.0, 1.0)
	if is_inside_tree():
		_sync_wave_uniforms()


## Pre-allocates the 16-slot ripple ring buffers to avoid runtime allocations.
func _init_ripple_buffers() -> void:
	_ripples.clear()
	_ripple_packed.resize(MAX_RIPPLES)
	for i: int in range(MAX_RIPPLES):
		_ripples.append(Vector4.ZERO)
		_ripple_packed[i] = Vector4.ZERO
	_ripple_head = 0
	_active_ripple_count = 0


## Caches the [RID] of the active surface or override material for direct server calls.
func _cache_material_rid() -> void:
	var mat: Material = material_override
	if mat == null and mesh != null and mesh.get_surface_count() > 0:
		mat = get_active_material(0)
	if mat != null:
		_material_rid = mat.get_rid()
	else:
		_material_rid = RID()


## Rebuilds the subdivided [BoxMesh], [CollisionShape3D], [FogVolume], and culling AABB.
func _rebuild_water_geometry() -> void:
	var sub_w: int = clampi(int(roundf(water_size.x * vertex_density * 0.5)), 8, 64)
	var sub_d: int = clampi(int(roundf(water_size.z * vertex_density * 0.5)), 8, 64)
	var box_mesh: BoxMesh = mesh as BoxMesh
	if box_mesh == null:
		box_mesh = BoxMesh.new()
		mesh = box_mesh
	box_mesh.size = water_size
	box_mesh.subdivide_width = sub_w
	box_mesh.subdivide_height = 0
	box_mesh.subdivide_depth = sub_d
	_update_custom_aabb()

	var col_node: CollisionShape3D = get_node_or_null(^"%CollisionShape3D") as CollisionShape3D
	if is_instance_valid(col_node):
		var box_shape: BoxShape3D = col_node.shape as BoxShape3D
		if box_shape == null:
			box_shape = BoxShape3D.new()
			col_node.shape = box_shape
		box_shape.size = water_size

	var fog_node: FogVolume = get_node_or_null(^"%FogVolume") as FogVolume
	if is_instance_valid(fog_node):
		fog_node.size = water_size
	_cache_material_rid()


## Pads [member GeometryInstance3D.custom_aabb] vertically by wave and ripple height margin.
func _update_custom_aabb() -> void:
	var pad_y: float = wave_amplitude * 2.0 + 0.65
	var pos: Vector3 = Vector3(
		-water_size.x * 0.5, -water_size.y * 0.5 - pad_y, -water_size.z * 0.5
	)
	var sz: Vector3 = Vector3(water_size.x, water_size.y + pad_y * 2.0, water_size.z)
	custom_aabb = AABB(pos, sz)


## Pushes exported wave parameters to the cached material [RID].
func _sync_wave_uniforms() -> void:
	_cache_material_rid()
	if not _material_rid.is_valid():
		return
	RenderingServer.material_set_param(_material_rid, PARAM_WAVE_AMP, wave_amplitude)
	RenderingServer.material_set_param(_material_rid, PARAM_WAVE_FREQ, wave_frequency)
	RenderingServer.material_set_param(_material_rid, PARAM_WAVE_SPEED, wave_speed)
	RenderingServer.material_set_param(_material_rid, PARAM_WAVE_STEEP, wave_steepness)


## Assigns SFX audio bus if available in [AudioServer], otherwise keeps default bus.
func _configure_audio_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) != -1:
		_surface_audio.bus = BUS_SFX
		_underwater_audio.bus = BUS_SFX


## Evaluates height contribution of one trochoidal wave octave.
func _eval_octave_height(
	xz: Vector2, dir: Vector2, amp: float, freq: float, spd: float, steep: float, t: float
) -> float:
	var phase: float = dir.dot(xz) * freq + t * spd
	var u: float = phase + steep * cos(phase)
	return amp * sin(u)


## Evaluates 2D XZ partial derivatives of one trochoidal wave octave.
func _eval_octave_grad(
	xz: Vector2, dir: Vector2, amp: float, freq: float, spd: float, steep: float, t: float
) -> Vector2:
	var phase: float = dir.dot(xz) * freq + t * spd
	var s: float = sin(phase)
	var c: float = cos(phase)
	var u: float = phase + steep * c
	var du_dphase: float = 1.0 - steep * s
	var dh_dphase: float = amp * cos(u) * du_dphase
	return dir * (dh_dphase * freq)


## Zeroes expired ripples and flushes the buffer to the GPU in a single call if changed.
func _expire_old_ripples(now: float) -> void:
	var dirty: bool = false
	var remaining: int = 0
	for i: int in range(MAX_RIPPLES):
		var r: Vector4 = _ripples[i]
		if r.w > 0.001:
			if now - r.z >= RIPPLE_MAX_AGE:
				_ripples[i] = Vector4.ZERO
				_ripple_packed[i] = Vector4.ZERO
				dirty = true
			else:
				remaining += 1
	_active_ripple_count = remaining
	if dirty:
		_flush_ripples_to_gpu()


## Sends the packed 16-slot ripple array to the shader via [RenderingServer].
func _flush_ripples_to_gpu() -> void:
	if _material_rid.is_valid():
		RenderingServer.material_set_param(_material_rid, PARAM_RIPPLES, _ripple_packed)


## Handles bodies entering [member _swimmable_area], registering physics and triggering splashes.
func _on_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	set_physics_process(true)
	var id: int = body.get_instance_id()
	_wake_cooldowns[id] = 0.0
	_wake_last_pos[id] = Vector2(body.global_position.x, body.global_position.z)

	var v_speed: float = 0.0
	if body is RigidBody3D:
		var rb: RigidBody3D = body as RigidBody3D
		if not _rigid_bodies.has(rb):
			_rigid_bodies.append(rb)
		v_speed = absf(rb.linear_velocity.y)
	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body as CharacterBody3D
		if not _character_bodies.has(cb):
			_character_bodies.append(cb)
		v_speed = absf(cb.velocity.y)

	_notify_body_water_state(body, true)
	if v_speed >= min_splash_velocity:
		var strength: float = clampf(v_speed * 0.06, 0.08, 0.55)
		spawn_ripple(body.global_position, strength)
		splashed.emit(body.global_position, v_speed)


## Handles bodies exiting [member _swimmable_area], cleaning up registries and wake state.
func _on_body_exited(body: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	_wake_cooldowns.erase(id)
	_wake_last_pos.erase(id)

	var v_speed: float = 0.0
	if body is RigidBody3D:
		var rb: RigidBody3D = body as RigidBody3D
		_rigid_bodies.erase(rb)
		v_speed = absf(rb.linear_velocity.y)
	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body as CharacterBody3D
		_character_bodies.erase(cb)
		v_speed = absf(cb.velocity.y)

	_notify_body_water_state(body, false)
	if v_speed >= min_splash_velocity:
		spawn_ripple(body.global_position, clampf(v_speed * 0.05, 0.06, 0.4))
		splashed.emit(body.global_position, v_speed)


## Updates water state properties or invokes water entry/exit callbacks on [param body].
func _notify_body_water_state(body: Node3D, entered: bool) -> void:
	if PROP_CURRENT_WATER_NODE in body:
		body.set(PROP_CURRENT_WATER_NODE, self if entered else null)
	if PROP_IS_IN_WATER in body:
		body.set(PROP_IS_IN_WATER, entered)
	if entered and body.has_method(METHOD_ENTER_WATER):
		body.call(METHOD_ENTER_WATER, self)
	elif not entered and body.has_method(METHOD_EXIT_WATER):
		body.call(METHOD_EXIT_WATER, self)


## Returns true if [param body] defines a non-empty [constant PROP_PROBES] array.
func _has_custom_multi_probe_buoyancy(body: RigidBody3D) -> bool:
	if not (PROP_PROBES in body):
		return false
	var val: Variant = body.get(PROP_PROBES)
	if typeof(val) == TYPE_ARRAY:
		return true
	return val != null


## Applies central buoyancy and drag to registered [RigidBody3D] nodes and spawns wakes.
func _process_rigid_bodies(delta: float, now: float) -> void:
	for i: int in range(_rigid_bodies.size() - 1, -1, -1):
		var rb: RigidBody3D = _rigid_bodies[i]
		if not is_instance_valid(rb):
			_rigid_bodies.remove_at(i)
			continue
		var pos: Vector3 = rb.global_position
		var surf_y: float = get_wave_height_at_pos(pos)
		if not _has_custom_multi_probe_buoyancy(rb):
			var depth: float = surf_y - pos.y
			if depth > 0.0:
				var sub_ratio: float = clampf(depth, 0.0, 1.5)
				var lift: float = rb.mass * buoyancy_force * sub_ratio
				rb.apply_central_force(Vector3.UP * lift)
				var vel: Vector3 = rb.linear_velocity
				var h_drag: Vector3 = Vector3(-vel.x, 0.0, -vel.z) * (water_linear_drag * rb.mass)
				var v_drag: Vector3 = Vector3(0.0, -vel.y * water_vertical_drag * rb.mass, 0.0)
				rb.apply_central_force(h_drag + v_drag)
				var ang_damp: float = clampf(1.0 - water_angular_drag * delta, 0.0, 1.0)
				rb.angular_velocity *= ang_damp
		_try_spawn_wake(rb.get_instance_id(), pos, rb.linear_velocity, surf_y, now)


## Evaluates wake ripple spawning for registered [CharacterBody3D] nodes.
func _process_character_bodies(now: float) -> void:
	for i: int in range(_character_bodies.size() - 1, -1, -1):
		var cb: CharacterBody3D = _character_bodies[i]
		if not is_instance_valid(cb):
			_character_bodies.remove_at(i)
			continue
		var pos: Vector3 = cb.global_position
		var surf_y: float = get_wave_height_at_pos(pos)
		_try_spawn_wake(cb.get_instance_id(), pos, cb.velocity, surf_y, now)


## Spawns a wake ripple if horizontal speed, surface proximity, cooldown, and distance pass.
func _try_spawn_wake(id: int, pos: Vector3, vel: Vector3, surf_y: float, now: float) -> void:
	if absf(pos.y - surf_y) > 1.6:
		return
	var h_speed_sq: float = vel.x * vel.x + vel.z * vel.z
	if h_speed_sq < MIN_WAKE_SPEED_SQ:
		return
	var next_time: float = _wake_cooldowns.get(id, 0.0)
	if now < next_time:
		return
	var cur_xz: Vector2 = Vector2(pos.x, pos.z)
	var prev_xz: Vector2 = _wake_last_pos.get(id, cur_xz)
	if cur_xz.distance_squared_to(prev_xz) < WAKE_MIN_DIST_SQ:
		return
	_wake_cooldowns[id] = now + WAKE_COOLDOWN_SEC
	_wake_last_pos[id] = cur_xz
	var wake_amp: float = clampf(sqrt(h_speed_sq) * 0.035, 0.04, 0.25)
	spawn_ripple(Vector3(pos.x, surf_y, pos.z), wake_amp)


## Checks camera submersion via [ShapeCast3D] and wave height; returns true if camera is near.
func _update_camera_submersion(delta: float) -> bool:
	var vp: Viewport = get_viewport()
	if vp == null:
		return false
	var cam: Camera3D = vp.get_camera_3d()
	if not is_instance_valid(cam):
		return false
	var cam_pos: Vector3 = cam.global_position
	var cam_vel_y: float = absf(cam_pos.y - _last_cam_y) / maxf(delta, 0.0001)
	_last_cam_y = cam_pos.y

	var half_ext: Vector3 = water_size * 0.5 + Vector3(2.0, 3.0, 2.0)
	var local_cam: Vector3 = to_local(cam_pos)
	var near_bounds: bool = (
		absf(local_cam.x) <= half_ext.x
		and absf(local_cam.y) <= half_ext.y
		and absf(local_cam.z) <= half_ext.z
	)
	if not near_bounds and not _is_camera_submerged:
		return false

	_camera_cast.global_position = cam_pos
	_camera_cast.force_shapecast_update()
	var hit_this_water: bool = false
	var count: int = _camera_cast.get_collision_count()
	for i: int in range(count):
		var col: Object = _camera_cast.get_collider(i)
		if col == _swimmable_area:
			hit_this_water = true
			break

	var surf_y: float = get_wave_height_at_pos(cam_pos)
	var should_submerge: bool = hit_this_water and (cam_pos.y < surf_y)
	if should_submerge and not _is_camera_submerged:
		_on_camera_submerged(cam)
	elif not should_submerge and _is_camera_submerged:
		_on_camera_surfaced(cam_pos, cam_vel_y)
	return near_bounds


## Handles transition into underwater state: swaps audio, emits VFX events, and sets fog.
func _on_camera_submerged(cam: Camera3D) -> void:
	_is_camera_submerged = true
	print("ArgonWaterBody: Camera submerged in ", name)
	_surface_audio.stream_paused = true
	if not _underwater_audio.playing:
		_underwater_audio.play()
	_underwater_audio.stream_paused = false

	_emit_events_signal(SIG_WATERFALL_VFX, [false, 0.0, 1.5])
	_emit_events_signal(SIG_UNDERWATER_VFX, [true, 0.85, 0.0, 0.0])

	var env: Environment = _resolve_active_environment(cam)
	var uw_fog: ArgonUnderwaterFogVolume = _fog_volume as ArgonUnderwaterFogVolume
	if is_instance_valid(uw_fog):
		uw_fog.set_edge_fade_value(0.05)
		uw_fog.set_submerged_state(true, env)
	if is_instance_valid(env) and not env.volumetric_fog_enabled:
		_apply_fallback_environment_fog(env)


## Handles transition back to surface: restores audio, fog, wipe VFX, and exit splash.
func _on_camera_surfaced(cam_pos: Vector3, vertical_speed: float) -> void:
	_is_camera_submerged = false
	print("ArgonWaterBody: Camera surfaced from ", name)
	_underwater_audio.stream_paused = true
	_surface_audio.stream_paused = false
	if not _surface_audio.playing:
		_surface_audio.play()

	_emit_events_signal(SIG_UNDERWATER_VFX, [false, 0.0, 0.0, 1.5])
	_emit_events_signal(SIG_WATER_SHEET_WIPE, [1.2])

	var uw_fog: ArgonUnderwaterFogVolume = _fog_volume as ArgonUnderwaterFogVolume
	if is_instance_valid(uw_fog):
		uw_fog.set_edge_fade_value(0.1)
		uw_fog.set_submerged_state(false, null)
	_restore_fallback_environment_fog()

	if vertical_speed >= min_splash_velocity:
		spawn_ripple(cam_pos, clampf(vertical_speed * 0.05, 0.08, 0.45))
		splashed.emit(cam_pos, vertical_speed)


## Resolves the active [Environment] from [Camera3D] or [World3D].
func _resolve_active_environment(cam: Camera3D) -> Environment:
	if is_instance_valid(cam) and is_instance_valid(cam.environment):
		return cam.environment
	var w3d: World3D = get_world_3d()
	if is_instance_valid(w3d):
		return w3d.environment
	return null


## Overrides [Environment] depth fog when volumetric fog is disabled so underwater stays murky.
func _apply_fallback_environment_fog(env: Environment) -> void:
	if not _env_backup_valid:
		_saved_fog_enabled = env.fog_enabled
		_saved_fog_mode = env.fog_mode
		_saved_fog_color = env.fog_light_color
		_saved_fog_density = env.fog_density
		_saved_fog_sky_affect = env.fog_sky_affect
		_saved_fog_begin = env.fog_depth_begin
		_saved_fog_end = env.fog_depth_end
		_env_backup_valid = true
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = fallback_fog_color
	env.fog_density = 1.0
	env.fog_sky_affect = 1.0
	env.fog_depth_begin = 0.45
	env.fog_depth_end = 3.0


## Restores baseline [Environment] fog settings captured prior to submersion.
func _restore_fallback_environment_fog() -> void:
	if not _env_backup_valid:
		return
	var w3d: World3D = get_world_3d()
	var env: Environment = w3d.environment if is_instance_valid(w3d) else null
	if is_instance_valid(env):
		env.fog_enabled = _saved_fog_enabled
		env.fog_mode = _saved_fog_mode
		env.fog_light_color = _saved_fog_color
		env.fog_density = _saved_fog_density
		env.fog_sky_affect = _saved_fog_sky_affect
		env.fog_depth_begin = _saved_fog_begin
		env.fog_depth_end = _saved_fog_end
	_env_backup_valid = false


## Emits a signal on the `/root/Events` autoload safely without untyped property access.
func _emit_events_signal(sig_name: StringName, args: Array[Variant]) -> void:
	var events_node: Node = get_node_or_null(^"/root/Events")
	if not is_instance_valid(events_node) or not events_node.has_signal(sig_name):
		return
	if args.size() == 1:
		events_node.emit_signal(sig_name, args[0])
	elif args.size() == 3:
		events_node.emit_signal(sig_name, args[0], args[1], args[2])
	elif args.size() == 4:
		events_node.emit_signal(sig_name, args[0], args[1], args[2], args[3])


## Returns current engine clock in seconds for deterministic CPU/GPU wave synchronization.
func _get_water_time() -> float:
	return float(Time.get_ticks_msec()) * 0.001
