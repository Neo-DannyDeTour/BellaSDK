@tool
## Interactive 3D water surface with wave displacement, buoyancy, and camera submerged detection.
class_name WaterBody
extends MeshInstance3D

## Primary tint albedo color for surface water rendering.
@export var water_color: Color = Color(0.31, 0.54, 0.87, 0.38)

## Color tint applied to underwater volumetric fog.
@export var fog_color: Color = Color(0.0, 0.04, 0.16)

## Maximum distance in meters before volumetric fog reaches full density.
@export_range(0.0, 250.0) var fog_fade_dist: float = 5.0

## Vertical amplitude peak of the surface wave oscillation.
@export var wave_amplitude: float = 0.2

## Spatial frequency density of the surface waves.
@export var wave_frequency: float = 2.0

## Playback speed scalar of wave motion over time.
@export var wave_speed: float = 1.0

## Audio stream played on rapid water entry/exit.
@export var splash_sound: AudioStream

## Velocity threshold required to trigger an entry or exit splash sound.
@export var min_splash_velocity: float = 5.0

## Tracks rigid bodies currently floating in the water volume.
var floating_bodies: Array[RigidBody3D] = []

## Rate-limiter flag preventing duplicate splash audio playback during load.
var can_splash: bool = true

## Previous frame submerged state of the primary active camera.
var _was_underwater: bool = false

## Y coordinate of the camera from the preceding frame for velocity tracking.
var _last_camera_y: float = 0.0

## Active tween driving the screen wipe transition when surfacing.
var _resurface_tween: Tween

## Frame counter cache to avoid duplicate submerged checks within a single frame.
static var last_frame_drew_underwater_effect: int = -999


## Lifecycle method configuring process priority, area triggers, and splash initialization.
func _ready() -> void:
	print("WaterBody: _ready() called. Initializing water volume.")
	process_priority = 999

	if get_node_or_null("%SwimmableArea3D"):
		var swimmable_area: Area3D = get_node("%SwimmableArea3D") as Area3D
		swimmable_area.body_entered.connect(_on_swimmable_area_body_entered)
		swimmable_area.body_exited.connect(_on_swimmable_area_body_exited)

	await get_tree().create_timer(1.0).timeout
	can_splash = true


## Calculates wave surface height at a specific world coordinate matching shader math.
## [param global_pos] The 3D world position to evaluate.
## [return] The computed surface elevation in world coordinates.
func get_wave_height_at_pos(global_pos: Vector3) -> float:
	var local_pos: Vector3 = to_local(global_pos)
	var time: float = (Time.get_ticks_msec() / 1000.0) * wave_speed

	var h1: float = sin(local_pos.x * wave_frequency + time) * wave_amplitude
	var h2: float = (
		sin((local_pos.x * 0.8 + local_pos.z * 0.6) * (wave_frequency * 1.5) - time * 1.2)
		* (wave_amplitude * 0.6)
	)
	var h3: float = (
		cos((local_pos.z * 1.2 - local_pos.x * 0.3) * (wave_frequency * 0.8) + time * 0.7)
		* (wave_amplitude * 0.4)
	)

	var box_height: float = 1.0
	if mesh is BoxMesh:
		box_height = (mesh as BoxMesh).size.y

	var local_surface_y: float = (box_height / 2.0) + h1 + h2 + h3
	var surface_global_pos: Vector3 = to_global(Vector3(local_pos.x, local_surface_y, local_pos.z))
	return surface_global_pos.y


## Checks whether the active camera is submerged below the calculated wave surface.
## [return] True if camera is submerged in the swimmable area.
func should_draw_camera_underwater_effect() -> bool:
	var viewport: Viewport = get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport else null

	if not is_instance_valid(camera):
		return false
	if last_frame_drew_underwater_effect == Engine.get_process_frames():
		return false

	var shape_cast: ShapeCast3D = get_node_or_null("%CameraPosShapeCast3D") as ShapeCast3D
	var swimmable_area: Area3D = get_node_or_null("%SwimmableArea3D") as Area3D

	if not is_instance_valid(shape_cast) or not is_instance_valid(swimmable_area):
		return false

	shape_cast.global_position = camera.global_position
	shape_cast.force_shapecast_update()

	var in_swimmable_area: bool = false
	for i: int in range(shape_cast.get_collision_count()):
		if shape_cast.get_collider(i) == swimmable_area:
			in_swimmable_area = true
			break

	if in_swimmable_area:
		if camera.global_position.y < get_wave_height_at_pos(camera.global_position):
			return true

	return false


## Drives material shader updates, fog transitions, audio tracks, and underwater VFX triggers.
## [param delta] The physics/render frame delta in seconds.
func _process(delta: float) -> void:
	if material_override is ShaderMaterial:
		var mat: ShaderMaterial = material_override as ShaderMaterial
		mat.set_shader_parameter(&"albedo", water_color)
		mat.set_shader_parameter(&"wave_amplitude", wave_amplitude)
		mat.set_shader_parameter(&"wave_frequency", wave_frequency)
		mat.set_shader_parameter(&"wave_speed", wave_speed)

	var fog_volume: FogVolume = get_node_or_null("%FogVolume") as FogVolume
	if is_instance_valid(fog_volume) and fog_volume.material is ShaderMaterial:
		(fog_volume.material as ShaderMaterial).set_shader_parameter(&"albedo", fog_color)
		(fog_volume.material as ShaderMaterial).set_shader_parameter(&"emission", fog_color)
		fog_volume.base_fade_dist = fog_fade_dist

	if not Engine.is_editor_hint():
		var viewport: Viewport = get_viewport()
		var camera: Camera3D = viewport.get_camera_3d() if viewport else null
		var cam_velocity_y: float = 0.0

		if is_instance_valid(camera):
			cam_velocity_y = (camera.global_position.y - _last_camera_y) / delta
			_last_camera_y = camera.global_position.y

		var is_underwater: bool = should_draw_camera_underwater_effect()

		if is_underwater:
			if is_instance_valid(fog_volume) and fog_volume.material is ShaderMaterial:
				(fog_volume.material as ShaderMaterial).set_shader_parameter(&"edge_fade", 0.1)

			last_frame_drew_underwater_effect = Engine.get_process_frames()

			if not _was_underwater:
				print("WaterBody: Camera submerged. Broadcasting underwater VFX enabled.")
				_was_underwater = true
				if _resurface_tween and _resurface_tween.is_valid():
					_resurface_tween.kill()

				# Zero droplets while submerged; only thick underwater wash
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
				print("WaterBody: Camera surfaced. Playing screen wipe transition.")
				_was_underwater = false

				if _resurface_tween and _resurface_tween.is_valid():
					_resurface_tween.kill()

				_resurface_tween = (create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(
					Tween.EASE_OUT
				))
				_resurface_tween.tween_method(
					func(prog: float) -> void:
						var wipe_pct: float = prog / 1.5
						var wash: float = maxf(0.0, 0.85 * (1.0 - wipe_pct))
						var drops: float = maxf(0.0, 0.7 * (1.0 - wipe_pct))
						Events.underwater_vfx_toggled.emit(true, wash, drops, prog),
					0.0,
					1.5,
					1.4
				)
				_resurface_tween.finished.connect(
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
					print(
						"WaterBody: Surface break splash triggered at velocity -> ", cam_velocity_y
					)
					play_splash_sound(camera.global_position, cam_velocity_y)


## Handles physical objects and characters entering the swimmable water volume.
## [param body] The intersecting [Node3D] body.
func _on_swimmable_area_body_entered(body: Node3D) -> void:
	print("WaterBody: Body entered swimmable volume -> ", body.name)
	if body is PickableObject:
		var pickable: PickableObject = body as PickableObject
		if not floating_bodies.has(pickable):
			floating_bodies.append(pickable)
			pickable.is_in_water = true
			pickable.current_water_node = self

	var impact_speed: float = 0.0
	if body is RigidBody3D:
		impact_speed = (body as RigidBody3D).linear_velocity.length()
	elif body is CharacterBody3D:
		impact_speed = (body as CharacterBody3D).velocity.length()
		if body.has_method("enter_water"):
			body.enter_water(self)

	if impact_speed >= min_splash_velocity:
		play_splash_sound(body.global_position, impact_speed)


## Spawns an instanced 3D spatial splash audio node at the surface contact point.
## [param impact_pos] World coordinates of the splash impact.
## [param speed] Velocity scalar used to scale audio playback volume.
func play_splash_sound(impact_pos: Vector3, speed: float) -> void:
	if not can_splash or not splash_sound:
		return

	print("WaterBody: Playing splash audio with speed -> ", speed)
	var audio_player: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	audio_player.stream = splash_sound

	var volume_multiplier: float = clampf(speed / 10.0, 0.2, 1.5)
	audio_player.volume_db = linear_to_db(volume_multiplier)
	audio_player.max_distance = 10.0
	audio_player.unit_size = 1.0

	add_child(audio_player)

	var surface_y: float = get_wave_height_at_pos(impact_pos)
	audio_player.global_position = Vector3(impact_pos.x, surface_y, impact_pos.z)
	audio_player.finished.connect(audio_player.queue_free)
	audio_player.play()


## Handles physical objects and characters exiting the swimmable water volume.
## [param body] The exiting [Node3D] body.
func _on_swimmable_area_body_exited(body: Node3D) -> void:
	print("WaterBody: Body exited swimmable volume -> ", body.name)

	if body is PickableObject:
		var pickable: PickableObject = body as PickableObject
		if floating_bodies.has(pickable):
			floating_bodies.erase(pickable)
			pickable.is_in_water = false
			pickable.current_water_node = null
	elif body.has_method("exit_water"):
		body.exit_water(self)
