@tool
## 3D water volume with Gerstner waves, rigid body buoyancy, and dynamic interactive 3D ripples.
class_name WaterBody
extends MeshInstance3D

## Emitted when an object splashes into or out of the water volume with impact velocity.
signal splashed(global_pos: Vector3, velocity: float)

## Total number of active dynamic ripples stored in the GPU uniform buffer array.
const MAX_RIPPLES: int = 16

## Horizontal propagation velocity of dynamic impact ripples in meters per second.
const RIPPLE_SPEED: float = 3.0

## Spatial wavelength of concentric impact ripples along the surface plane in meters.
const RIPPLE_WAVELENGTH: float = 1.0

## Total lifespan in seconds before dynamic impact ripples completely dissipate.
const RIPPLE_LIFETIME: float = 2.5

## Dimensions of the water volume in meters (X: length, Y: depth, Z: width).
@export var water_size: Vector3 = Vector3(10.0, 3.0, 10.0):
	set(value):
		water_size = value
		_update_bounds()

## Target density of mesh vertices per meter along horizontal axes for waves.
@export_range(1.0, 8.0, 0.5) var vertex_density: float = 3.5:
	set(value):
		vertex_density = value
		_update_bounds()

## Primary tint albedo color for surface water rendering.
@export var shallow_color: Color = Color(0.28, 0.58, 0.85, 0.45)

## Deep water absorption color for deep volumetric optical shading.
@export var deep_color: Color = Color(0.01, 0.06, 0.18, 0.95)

## Light absorption coefficient controlling underwater murkiness via Beer's Law.
@export_range(0.1, 10.0, 0.1) var beers_law: float = 2.2

## Maximum water depth in meters where absorption gradient reaches deep color.
@export_range(0.5, 50.0, 0.5) var depth_distance: float = 4.5

## Steepness factor of Gerstner wave crests between 0.0 (sine) and 1.0 (crested).
@export_range(0.0, 1.0, 0.05) var wave_steepness: float = 0.35

## Primary Gerstner wave amplitude peak in meters.
@export var wave_amplitude: float = 0.1

## Primary Gerstner wave length in meters.
@export var wave_length: float = 4.5

## Global playback speed scalar of wave motion over time.
@export var wave_speed: float = 1.4

## Buoyant upward acceleration multiplier applied to submerged rigid bodies.
@export var buoyancy_power: float = 2.2

## Linear drag damping coefficient slowing submerged bodies in water.
@export var water_drag: float = 2.8

## Vertical oscillation drag damping vertical bobbing motion in water.
@export var vertical_drag: float = 1.6

## Angular drag damping coefficient rotational momentum inside water.
@export var angular_drag: float = 1.2

## Minimum movement speed required to spawn dynamic movement ripples.
@export var min_ripple_speed: float = 0.7

## Cooldown interval in seconds between consecutive movement ripple spawns.
@export var ripple_cooldown: float = 0.16

## Minimum impact speed required to play entry and exit splash sounds.
@export var min_splash_velocity: float = 4.0

## Audio stream resource played during entry, exit, or resurface splashes.
@export var splash_sound: AudioStream

## Maximum vertical 3D displacement amplitude for dynamic ripples in meters.
@export var ripple_mesh_height: float = 0.22

## Whether vertical perimeter side walls of the water mesh should render.
@export var show_side_walls: bool = false

## Underwater volumetric fog tint color applied when submerged.
@export var fog_color: Color = Color(0.0, 0.04, 0.16)

## Distance in meters before underwater volumetric fog reaches full density.
@export_range(0.0, 250.0) var fog_fade_dist: float = 5.0

## Active rigid bodies currently submerged and simulated inside this water volume.
var floating_bodies: Array[RigidBody3D] = []

## Active character bodies currently submerged inside this water volume.
var character_bodies: Array[CharacterBody3D] = []

## Preceding frame positions of submerged bodies for ripple movement tracking.
var _last_body_positions: Dictionary = {}

## Timestamp tracking last ripple emission time for each tracked submerged body.
var _last_body_ripple_times: Dictionary = {}

## Rate-limiter flag preventing duplicate splash audio playback during load.
var can_splash: bool = true

## Submerged state of the active camera during the preceding frame.
var _was_underwater: bool = false

## Y coordinate of the camera from the preceding frame for velocity tracking.
var _last_camera_y: float = 0.0

## Active tween driving screen-space resurface wash and droplets animation.
var _resurface_tween: Tween

## Cyclic ring buffer write pointer for dynamic ripple allocation.
var _ripple_index: int = 0

## Frame counter cache preventing duplicate underwater view evaluations.
static var last_frame_drew_underwater_effect: int = -999

## Dynamic ripple ring buffer storing [pos_x, pos_z, spawn_time, amplitude].
var _ripples_buffer: Array[Vector4] = []


## Resolves the active [ShaderMaterial] from material override or mesh surface.
func _get_water_material() -> ShaderMaterial:
	if material_override is ShaderMaterial:
		return material_override as ShaderMaterial
	if get_surface_override_material(0) is ShaderMaterial:
		return get_surface_override_material(0) as ShaderMaterial
	if mesh and mesh.material is ShaderMaterial:
		return mesh.material as ShaderMaterial
	return null


## Rebuilds [BoxMesh] subdivisions and updates child [CollisionShape3D] sizes.
func _update_bounds() -> void:
	if not is_inside_tree():
		return

	print("WaterBody: Updating mesh subdivisions and collision volume bounds.")
	if scale != Vector3.ONE:
		scale = Vector3.ONE

	if not (mesh is BoxMesh):
		mesh = BoxMesh.new()

	var box: BoxMesh = mesh as BoxMesh
	box.size = water_size
	box.subdivide_width = clampi(int(water_size.x * vertex_density), 8, 256)
	box.subdivide_depth = clampi(int(water_size.z * vertex_density), 8, 256)
	box.subdivide_height = 0

	var swimmable_area: Area3D = get_node_or_null("%SwimmableArea3D") as Area3D
	if is_instance_valid(swimmable_area):
		var col: CollisionShape3D = (
			swimmable_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		)
		if is_instance_valid(col):
			if not (col.shape is BoxShape3D):
				col.shape = BoxShape3D.new()
			(col.shape as BoxShape3D).size = water_size

	var fog_vol: FogVolume = get_node_or_null("%FogVolume") as FogVolume
	if is_instance_valid(fog_vol):
		fog_vol.size = water_size


## Lifecycle method configuring collision masks, timer delays, and bounds.
func _ready() -> void:
	print("WaterBody: Initializing water volume and physics listeners.")
	process_priority = 999
	_ripples_buffer.resize(MAX_RIPPLES)
	for i: int in range(MAX_RIPPLES):
		_ripples_buffer[i] = Vector4.ZERO

	_update_bounds()

	var swimmable_area: Area3D = get_node_or_null("%SwimmableArea3D") as Area3D
	if is_instance_valid(swimmable_area):
		# Layer 2 (Player = 2) and Layer 3 (Interactables = 4)
		swimmable_area.collision_mask |= (1 << 1) | (1 << 2)
		if not swimmable_area.body_entered.is_connected(_on_swimmable_area_body_entered):
			swimmable_area.body_entered.connect(_on_swimmable_area_body_entered)
		if not swimmable_area.body_exited.is_connected(_on_swimmable_area_body_exited):
			swimmable_area.body_exited.connect(_on_swimmable_area_body_exited)

	await get_tree().create_timer(1.0).timeout
	can_splash = true


## Simulates realistic buoyancy forces and generates continuous movement ripples.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	var cur_time: float = float(Time.get_ticks_msec()) / 1000.0

	# Physics simulation for floating RigidBody3D objects
	for i: int in range(floating_bodies.size() - 1, -1, -1):
		var body: RigidBody3D = floating_bodies[i]
		if not is_instance_valid(body):
			floating_bodies.remove_at(i)
			continue

		var surface_y: float = get_wave_height_at_pos(body.global_position)
		var depth: float = surface_y - body.global_position.y

		if depth > 0.0:
			var submersion_ratio: float = clampf(depth / 1.2, 0.0, 1.5)
			var gravity_mag: float = 9.8
			var upward_accel: float = gravity_mag * buoyancy_power * submersion_ratio
			var upward_force: Vector3 = Vector3.UP * upward_accel

			var linear_damping: Vector3 = -body.linear_velocity * water_drag
			var vert_damping: Vector3 = Vector3.UP * (-body.linear_velocity.y * vertical_drag)
			body.apply_central_force((upward_force + linear_damping + vert_damping) * body.mass)
			body.angular_velocity *= (1.0 - clampf(angular_drag * delta, 0.0, 0.9))

		# Continuous movement ripples when dragging or propelling across water
		var speed_h: float = Vector2(body.linear_velocity.x, body.linear_velocity.z).length()
		var body_id: int = body.get_instance_id()
		var last_time: float = _last_body_ripple_times.get(body_id, 0.0)
		var last_pos: Vector3 = _last_body_positions.get(body_id, body.global_position)

		if speed_h >= min_ripple_speed and (cur_time - last_time) >= ripple_cooldown:
			if body.global_position.distance_to(last_pos) >= 0.3:
				spawn_ripple(body.global_position, clampf(speed_h * 0.25, 0.2, 0.8))
				_last_body_ripple_times[body_id] = cur_time
				_last_body_positions[body_id] = body.global_position

	# Movement ripples for swimming characters (Player / NPCs)
	for i: int in range(character_bodies.size() - 1, -1, -1):
		var character: CharacterBody3D = character_bodies[i]
		if not is_instance_valid(character):
			character_bodies.remove_at(i)
			continue

		var char_speed: float = character.velocity.length()
		var char_id: int = character.get_instance_id()
		var last_char_time: float = _last_body_ripple_times.get(char_id, 0.0)
		var last_char_pos: Vector3 = _last_body_positions.get(char_id, character.global_position)

		if char_speed >= min_ripple_speed and (cur_time - last_char_time) >= ripple_cooldown:
			if character.global_position.distance_to(last_char_pos) >= 0.35:
				spawn_ripple(character.global_position, clampf(char_speed * 0.2, 0.25, 0.75))
				_last_body_ripple_times[char_id] = cur_time
				_last_body_positions[char_id] = character.global_position


## Syncs shader parameters, evaluates camera submersion, and drives screen wipe.
func _process(delta: float) -> void:
	var mat: ShaderMaterial = _get_water_material()
	var current_time: float = float(Time.get_ticks_msec()) / 1000.0

	if is_instance_valid(mat):
		mat.set_shader_parameter(&"water_time", current_time)
		mat.set_shader_parameter(&"water_size", water_size)
		mat.set_shader_parameter(&"shallow_color", shallow_color)
		mat.set_shader_parameter(&"deep_color", deep_color)
		mat.set_shader_parameter(&"beers_law", beers_law)
		mat.set_shader_parameter(&"depth_distance", depth_distance)
		mat.set_shader_parameter(&"wave_amplitude", wave_amplitude)
		mat.set_shader_parameter(&"wave_length", wave_length)
		mat.set_shader_parameter(&"wave_speed", wave_speed)
		mat.set_shader_parameter(&"wave_steepness", wave_steepness)
		mat.set_shader_parameter(&"ripple_mesh_height", ripple_mesh_height)
		mat.set_shader_parameter(&"show_side_walls", show_side_walls)
		mat.set_shader_parameter(&"ripples", _ripples_buffer)

	var fog_volume: FogVolume = get_node_or_null("%FogVolume") as FogVolume
	if is_instance_valid(fog_volume) and fog_volume.material is ShaderMaterial:
		var fog_mat: ShaderMaterial = fog_volume.material as ShaderMaterial
		fog_mat.set_shader_parameter(&"albedo", fog_color)
		fog_mat.set_shader_parameter(&"emission", fog_color)
		fog_volume.base_fade_dist = fog_fade_dist

	if not Engine.is_editor_hint():
		var viewport: Viewport = get_viewport()
		var camera: Camera3D = viewport.get_camera_3d() if viewport else null
		var cam_velocity_y: float = 0.0

		if is_instance_valid(camera):
			cam_velocity_y = (camera.global_position.y - _last_camera_y) / maxf(delta, 0.001)
			_last_camera_y = camera.global_position.y

		var is_underwater: bool = should_draw_camera_underwater_effect()

		if is_underwater:
			if is_instance_valid(fog_volume) and fog_volume.material is ShaderMaterial:
				(fog_volume.material as ShaderMaterial).set_shader_parameter(&"edge_fade", 0.1)

			last_frame_drew_underwater_effect = Engine.get_process_frames()

			if not _was_underwater:
				print("WaterBody: Camera submerged into water volume.")
				_was_underwater = true
				if _resurface_tween and _resurface_tween.is_valid():
					_resurface_tween.kill()

				Events.underwater_vfx_toggled.emit(true, 0.85, 0.0, 0.0)

				var surface_audio: AudioStreamPlayer = (
					get_node_or_null("%SurfaceAudio") as AudioStreamPlayer
				)
				var underwater_audio: AudioStreamPlayer = (
					get_node_or_null("%UnderwaterAudio") as AudioStreamPlayer
				)

				if is_instance_valid(surface_audio) and surface_audio.playing:
					surface_audio.stream_paused = true

				if is_instance_valid(underwater_audio):
					if not underwater_audio.playing:
						underwater_audio.play()
					elif underwater_audio.stream_paused:
						underwater_audio.stream_paused = false
		else:
			if is_instance_valid(fog_volume) and fog_volume.material is ShaderMaterial:
				(fog_volume.material as ShaderMaterial).set_shader_parameter(&"edge_fade", 1.1)

			if _was_underwater:
				print("WaterBody: Camera surfaced. Triggering waterfall wipe and droplets.")
				_was_underwater = false

				if _resurface_tween and _resurface_tween.is_valid():
					_resurface_tween.kill()

				_resurface_tween = create_tween().set_parallel(false)

				# Phase 1: Waterfall sheet wipe cascades down the lens
				(
					_resurface_tween
					. tween_method(
						func(prog: float) -> void:
							var wipe_pct: float = clampf(prog / 1.5, 0.0, 1.0)
							var wash: float = (1.0 - wipe_pct) * 0.95
							# Mode 2 (Waterfall), wash streams down, wipe curtain descends
							Events.waterfall_vfx_toggled.emit(true, wash, prog),
						0.0,
						1.5,
						0.9
					)
					. set_trans(Tween.TRANS_CUBIC)
					. set_ease(Tween.EASE_OUT)
				)

				# Transition into Phase 2: Water sheet clears, droplets cling to lens
				_resurface_tween.tween_callback(
					func() -> void:
						Events.waterfall_vfx_toggled.emit(false, 0.0, 1.5)
						Events.underwater_vfx_toggled.emit(false, 0.0, 1.0, 1.5)
				)

				# Phase 2: Droplets linger on the lens and smoothly dry up
				(
					_resurface_tween
					. tween_method(
						func(drop_val: float) -> void:
							Events.underwater_vfx_toggled.emit(false, 0.0, drop_val, 1.5),
						1.0,
						0.0,
						2.5
					)
					. set_trans(Tween.TRANS_SINE)
					. set_ease(Tween.EASE_OUT)
				)

				# Cleanup once fully dry
				_resurface_tween.tween_callback(
					func() -> void: Events.underwater_vfx_toggled.emit(false, 0.0, 0.0, 1.5)
				)

				var surface_audio: AudioStreamPlayer = (
					get_node_or_null("%SurfaceAudio") as AudioStreamPlayer
				)
				var underwater_audio: AudioStreamPlayer = (
					get_node_or_null("%UnderwaterAudio") as AudioStreamPlayer
				)

				if is_instance_valid(underwater_audio) and underwater_audio.playing:
					underwater_audio.stream_paused = true

				if is_instance_valid(surface_audio):
					if not surface_audio.playing:
						surface_audio.play()
					elif surface_audio.stream_paused:
						surface_audio.stream_paused = false

				if is_instance_valid(camera) and cam_velocity_y >= min_splash_velocity:
					play_splash_sound(camera.global_position, cam_velocity_y)


## Computes dynamic surface water height combining Gerstner waves and ripples.
func get_wave_height_at_pos(global_pos: Vector3) -> float:
	var cur_time: float = (float(Time.get_ticks_msec()) / 1000.0) * wave_speed
	var k: float = TAU / maxf(wave_length, 0.1)

	# Gerstner Wave 1 (Dominant)
	var dir1: Vector2 = Vector2(1.0, 0.2).normalized()
	var phase1: float = (dir1.x * global_pos.x + dir1.y * global_pos.z) * k + cur_time
	var h1: float = sin(phase1) * wave_amplitude

	# Gerstner Wave 2 (Secondary Cross Wave)
	var dir2: Vector2 = Vector2(-0.6, 0.8).normalized()
	var k2: float = k * 1.6
	var phase2: float = (dir2.x * global_pos.x + dir2.y * global_pos.z) * k2 - (cur_time * 1.15)
	var h2: float = sin(phase2) * (wave_amplitude * 0.45)

	# Gerstner Wave 3 (Detail Wave)
	var dir3: Vector2 = Vector2(0.3, -0.95).normalized()
	var k3: float = k * 2.8
	var phase3: float = (dir3.x * global_pos.x + dir3.y * global_pos.z) * k3 + (cur_time * 0.8)
	var h3: float = sin(phase3) * (wave_amplitude * 0.2)

	# Concentric Dynamic Ripples
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var total_rip_h: float = 0.0

	for rip: Vector4 in _ripples_buffer:
		var amp: float = rip.w
		if amp <= 0.001:
			continue
		var elapsed: float = now - rip.z
		if elapsed < 0.0 or elapsed > RIPPLE_LIFETIME:
			continue
		var dist: float = Vector2(global_pos.x - rip.x, global_pos.z - rip.y).length()
		var d_wave: float = dist - (elapsed * RIPPLE_SPEED)
		var envelope: float = exp(-0.5 * (d_wave * d_wave) / (RIPPLE_WAVELENGTH * 1.2))
		var decay: float = clampf(1.0 - (elapsed / RIPPLE_LIFETIME), 0.0, 1.0)
		var k_rip: float = TAU / RIPPLE_WAVELENGTH
		total_rip_h += sin(k_rip * d_wave) * amp * envelope * decay

	var base_surface_y: float = global_position.y + (water_size.y * 0.5)
	return base_surface_y + h1 + h2 + h3 + (total_rip_h * ripple_mesh_height)


## Computes surface normal vector at [param global_pos] using finite differences.
func get_water_surface_normal(global_pos: Vector3) -> Vector3:
	var step: float = 0.15
	var h_center: float = get_wave_height_at_pos(global_pos)
	var h_right: float = get_wave_height_at_pos(global_pos + Vector3(step, 0.0, 0.0))
	var h_forward: float = get_wave_height_at_pos(global_pos + Vector3(0.0, 0.0, step))

	var tangent_x: Vector3 = Vector3(step, h_right - h_center, 0.0).normalized()
	var tangent_z: Vector3 = Vector3(0.0, h_forward - h_center, step).normalized()
	return tangent_z.cross(tangent_x).normalized()


## Checks if active [Camera3D] is positioned beneath the dynamic water surface.
func should_draw_camera_underwater_effect() -> bool:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null

	if not is_instance_valid(camera):
		return false
	if last_frame_drew_underwater_effect == Engine.get_process_frames():
		return false

	# Transform camera position to local water volume space
	var local_cam_pos: Vector3 = to_local(camera.global_position)
	var half_x: float = water_size.x * 0.5
	var half_z: float = water_size.z * 0.5
	var bottom_y: float = -water_size.y * 0.5

	# Bounding box test inside horizontal and vertical boundaries
	var is_inside_box: bool = (
		absf(local_cam_pos.x) <= half_x
		and absf(local_cam_pos.z) <= half_z
		and local_cam_pos.y >= bottom_y
	)

	if is_inside_box:
		var wave_surface_y: float = get_wave_height_at_pos(camera.global_position)
		if camera.global_position.y < wave_surface_y:
			return true

	return false


## Registers entering bodies, triggers impact ripples, and plays splash audio.
func _on_swimmable_area_body_entered(body: Node3D) -> void:
	print("WaterBody: Submerged object entered water volume -> ", body.name)
	var impact_speed: float = 0.0

	if body is RigidBody3D:
		var rb: RigidBody3D = body as RigidBody3D
		if not floating_bodies.has(rb):
			floating_bodies.append(rb)
		impact_speed = rb.linear_velocity.length()
		_last_body_positions[rb.get_instance_id()] = rb.global_position
		_last_body_ripple_times[rb.get_instance_id()] = float(Time.get_ticks_msec()) / 1000.0

	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body as CharacterBody3D
		if not character_bodies.has(cb):
			character_bodies.append(cb)
		impact_speed = cb.velocity.length()
		_last_body_positions[cb.get_instance_id()] = cb.global_position
		_last_body_ripple_times[cb.get_instance_id()] = float(Time.get_ticks_msec()) / 1000.0
		if body.has_method("enter_water"):
			body.enter_water(self)

	var ripple_power: float = clampf(maxf(impact_speed * 0.35, 1.2), 0.3, 2.0)
	spawn_ripple(body.global_position, ripple_power)

	if impact_speed >= min_splash_velocity:
		play_splash_sound(body.global_position, impact_speed)
		splashed.emit(body.global_position, impact_speed)


## Unregisters exiting bodies, triggers exit ripples, and plays exit splashes.
func _on_swimmable_area_body_exited(body: Node3D) -> void:
	print("WaterBody: Submerged object exited water volume -> ", body.name)
	var exit_speed: float = 0.0

	if body is RigidBody3D:
		var rb: RigidBody3D = body as RigidBody3D
		floating_bodies.erase(rb)
		_last_body_positions.erase(rb.get_instance_id())
		_last_body_ripple_times.erase(rb.get_instance_id())
		exit_speed = rb.linear_velocity.length()

	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body as CharacterBody3D
		character_bodies.erase(cb)
		_last_body_positions.erase(cb.get_instance_id())
		_last_body_ripple_times.erase(cb.get_instance_id())
		exit_speed = cb.velocity.length()
		if body.has_method("exit_water"):
			body.exit_water(self)

	spawn_ripple(body.global_position, clampf(maxf(exit_speed * 0.25, 0.8), 0.3, 1.5))
	if exit_speed >= min_splash_velocity:
		play_splash_sound(body.global_position, exit_speed)
		splashed.emit(body.global_position, exit_speed)


## Spawns an instanced [AudioStreamPlayer3D] playing splash audio at surface.
func play_splash_sound(impact_pos: Vector3, speed: float) -> void:
	if not can_splash or not splash_sound:
		return

	print("WaterBody: Playing 3D splash audio at ", impact_pos, " speed: ", speed)
	var audio_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	audio_player.stream = splash_sound

	var volume_multiplier: float = clampf(speed / 8.0, 0.25, 1.8)
	audio_player.volume_db = linear_to_db(volume_multiplier)
	audio_player.max_distance = 15.0
	audio_player.unit_size = 1.2

	add_child(audio_player)
	var surface_y: float = get_wave_height_at_pos(impact_pos)
	audio_player.global_position = Vector3(impact_pos.x, surface_y, impact_pos.z)
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()


## Allocates a dynamic ripple at [param global_pos] into the uniform ring buffer.
func spawn_ripple(global_pos: Vector3, impact_strength: float = 1.0) -> void:
	print("WaterBody: Spawning 3D ripple at ", global_pos, " strength: ", impact_strength)
	var spawn_time: float = float(Time.get_ticks_msec()) / 1000.0
	var ripple_amp: float = clampf(impact_strength * 0.3, 0.2, 1.0)

	_ripples_buffer[_ripple_index] = Vector4(global_pos.x, global_pos.z, spawn_time, ripple_amp)
	_ripple_index = (_ripple_index + 1) % MAX_RIPPLES

	var mat: ShaderMaterial = _get_water_material()
	if is_instance_valid(mat):
		mat.set_shader_parameter(&"ripples", _ripples_buffer)
