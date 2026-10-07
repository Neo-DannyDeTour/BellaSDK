## Plays context-aware footsteps and stamps snow using [CollisionLayers] and [AudioPool].
class_name FootstepManager
extends Node3D

@export_category("Node References")
## Reference to main player body used as origin for downward raycasts.
@export var player_body: CharacterBody3D

@export_category("Audio Streams")
## Default footstep sound played when no surface matches.
@export var sound_default: AudioStream
## Footstep sound for metal grid and panel surfaces.
@export var sound_metal: AudioStream
## Footstep sound for hard stone and concrete surfaces.
@export var sound_stone: AudioStream
## Footstep sound for mud or wet dirt surfaces.
@export var sound_wet_dirt: AudioStream
## Footstep sound for slippery ice surfaces.
@export var sound_ice: AudioStream
## Footstep sound played when traversing snow surfaces.
@export var sound_snow: AudioStream
## Climbing sound used while traversing ladders.
@export var sound_ladder: AudioStream
## Audio stream used for monkey bar traversal.
@export var sound_monkey_bar: AudioStream

@export_category("Timing Intervals")
## Time gap between footstep sounds while walking normally.
@export var walk_step_interval: float = 0.45
## Time gap between footstep sounds while sprinting.
@export var sprint_step_interval: float = 0.28
## Time gap between footstep sounds while crouch walking.
@export var crouch_step_interval: float = 0.65
## Time gap between climbing sounds while ascending or descending ladders.
@export var ladder_step_interval: float = 0.55
## Time gap between grabbing sounds while on monkey bars.
@export var monkey_bar_step_interval: float = 0.65

@export_category("Deformation Settings")
## Base radius in pixels stamped into snow terrain during footsteps.
@export var snow_stamp_radius: float = 24.0
## Radius in pixels stamped into snow terrain while sliding.
@export var snow_slide_radius: float = 34.0

## Fast lookup string for ice surface group checks.
const SURFACE_ICE: StringName = &"ice"
## Fast lookup string for metal surface group checks.
const SURFACE_METAL: StringName = &"metal"
## Fast lookup string for stone surface group checks.
const SURFACE_STONE: StringName = &"stone"
## Fast lookup string for wet dirt surface group checks.
const SURFACE_WET: StringName = &"wet_dirt"
## Fast lookup string for snow surface group checks.
const SURFACE_SNOW: StringName = &"snow"

## Tracks remaining time before next footstep sound can trigger.
var step_timer: float = 0.0
## Flags if player is currently standing on ice surface.
var is_on_ice: bool = false
## Flags if player is currently standing on deformable snow.
var is_on_snow: bool = false
## Currently selected audio stream based on surface detection.
var active_stream: AudioStream = null
## Active [SnowGround] node currently beneath player body.
var _current_snow_ground: SnowGround = null
## World coordinate of most recent floor raycast collision.
var _last_hit_position: Vector3 = Vector3.ZERO
## World position of previous slide deformation stamp.
var _last_slide_carve_pos: Vector3 = Vector3.ZERO
## Reference to pooled looping player used for monkey bar traversal.
var _looping_player: AudioStreamPlayer = null


## Initializes footstep manager and verifies audio dependencies.
func _ready() -> void:
	print("FootstepManager: _ready() initialized.")
	active_stream = sound_default


## Evaluates speed and surface material to trigger audio and snow stamps.
func process_surface_and_footsteps(
	delta: float,
	is_grounded: bool,
	velocity_length: float,
	is_sprinting: bool,
	is_crouching: bool,
	is_on_ladder: bool = false,
	is_on_monkey_bar: bool = false
) -> void:
	if is_on_monkey_bar:
		active_stream = sound_monkey_bar
		if velocity_length > 0.1:
			if _looping_player == null or not _looping_player.playing:
				print("FootstepManager: Playing monkey bar traversal sound.")
				_looping_player = AudioPool.play_sfx_2d(active_stream)
		else:
			stop_looping_sounds()
		return

	stop_looping_sounds()

	if is_on_ladder:
		active_stream = sound_ladder
		if velocity_length > 0.5:
			step_timer -= delta
			if step_timer <= 0.0:
				print("FootstepManager: Playing ladder climbing sound.")
				AudioPool.play_sfx_2d(active_stream)
				step_timer = ladder_step_interval
		else:
			step_timer = 0.0
		return

	if not is_grounded:
		step_timer = 0.0
		is_on_ice = false
		is_on_snow = false
		_current_snow_ground = null
		return

	_scan_surface_material()

	if velocity_length > 0.5:
		step_timer -= delta
		if step_timer <= 0.0:
			print("FootstepManager: Playing surface footstep sound via AudioPool.")
			if active_stream != null:
				AudioPool.play_sfx_2d(active_stream)

			if is_on_snow and is_instance_valid(_current_snow_ground):
				_stamp_snow_footstep(is_sprinting, is_crouching)

			_reset_timer(is_sprinting, is_crouching)
	else:
		step_timer = 0.0


## Projects downward ray using [CollisionLayers] and identifies ground.
func _scan_surface_material() -> void:
	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var ray_start: Vector3 = player_body.global_position + Vector3(0.0, 0.5, 0.0)
	var ray_end: Vector3 = player_body.global_position + Vector3(0.0, -1.0, 0.0)

	var result: Dictionary = NodeQuery.cast_ray(
		space_state, ray_start, ray_end, CollisionLayers.MASK_ENVIRONMENT, [player_body.get_rid()]
	)

	active_stream = sound_default
	is_on_ice = false
	is_on_snow = false
	_current_snow_ground = null

	if result.is_empty():
		return

	var collider: Object = result.get("collider")
	_last_hit_position = result.get("position", Vector3.ZERO)

	if not is_instance_valid(collider) or not (collider is Node):
		return

	var target_node: Node = collider if collider is Node else null
	var snow_node: Node = NodeQuery.find_ancestor_of_type(target_node, SnowGround)

	if target_node is SnowGround:
		_current_snow_ground = target_node as SnowGround
		is_on_snow = true
	elif is_instance_valid(snow_node):
		_current_snow_ground = snow_node as SnowGround
		is_on_snow = true
	elif (
		NodeQuery.find_ancestor_in_group(target_node, SURFACE_SNOW) != null
		or target_node.is_in_group(SURFACE_SNOW)
	):
		is_on_snow = true
		if is_instance_valid(snow_node):
			_current_snow_ground = snow_node as SnowGround

	if is_on_snow and sound_snow:
		active_stream = sound_snow
	elif (
		target_node.is_in_group(SURFACE_ICE)
		or NodeQuery.find_ancestor_in_group(target_node, SURFACE_ICE) != null
	):
		is_on_ice = true
		if sound_ice:
			active_stream = sound_ice
	elif (
		(
			target_node.is_in_group(SURFACE_METAL)
			or NodeQuery.find_ancestor_in_group(target_node, SURFACE_METAL) != null
		)
		and sound_metal
	):
		active_stream = sound_metal
	elif (
		(
			target_node.is_in_group(SURFACE_STONE)
			or NodeQuery.find_ancestor_in_group(target_node, SURFACE_STONE) != null
		)
		and sound_stone
	):
		active_stream = sound_stone
	elif (
		(
			target_node.is_in_group(SURFACE_WET)
			or NodeQuery.find_ancestor_in_group(target_node, SURFACE_WET) != null
		)
		and sound_wet_dirt
	):
		active_stream = sound_wet_dirt


## Stamps footprint depression into active [SnowGround] at impact point.
func _stamp_snow_footstep(is_sprinting: bool, is_crouching: bool) -> void:
	if not is_instance_valid(_current_snow_ground):
		return

	var radius: float = snow_stamp_radius
	var intensity: float = 0.6
	if is_sprinting:
		radius *= 1.25
		intensity = 0.85
	elif is_crouching:
		radius *= 0.85
		intensity = 0.45

	var travel_basis: Basis = player_body.global_transform.basis
	var travel_forward: Vector3 = travel_basis.z.normalized()
	var rotation_angle: float = atan2(-travel_forward.x, travel_forward.z)

	print("FootstepManager: Stamping boot print at ", _last_hit_position)
	_current_snow_ground.deform_at(_last_hit_position, radius, intensity, rotation_angle)


## Carves continuous displacement impressions into [SnowGround] while sliding.
func carve_slide(_delta: float, speed_ratio: float) -> void:
	if not is_on_snow or not is_instance_valid(_current_snow_ground):
		return

	var dist: float = player_body.global_position.distance_to(_last_slide_carve_pos)
	if dist < 0.3:
		return

	_last_slide_carve_pos = player_body.global_position
	var radius: float = snow_slide_radius * clampf(speed_ratio, 0.7, 1.3)
	print("FootstepManager: Carving snow slide groove at ", _last_hit_position)
	_current_snow_ground.deform_at(_last_hit_position, radius, 0.9)


## Recharges footstep step timer based on movement state.
func _reset_timer(is_sprinting: bool, is_crouching: bool) -> void:
	if is_sprinting:
		step_timer = sprint_step_interval
	elif is_crouching:
		step_timer = crouch_step_interval
	else:
		step_timer = walk_step_interval


## Halts playback of continuous audio streams like monkey bar sound.
func stop_looping_sounds() -> void:
	if is_instance_valid(_looping_player) and _looping_player.playing:
		print("FootstepManager: Stopping looping audio player.")
		_looping_player.stop()
		_looping_player = null


## Stamps landing crater into snow based on vertical fall speed.
func stamp_landing_crater(fall_speed: float) -> void:
	_scan_surface_material()
	if not is_on_snow or not is_instance_valid(_current_snow_ground):
		return

	var speed_factor: float = clampf(absf(fall_speed) / 12.0, 0.5, 2.0)
	var radius: float = snow_stamp_radius * 2.2 * speed_factor
	var intensity: float = clampf(0.5 + (speed_factor * 0.3), 0.5, 1.0)

	print("FootstepManager: Stamping landing crater at ", _last_hit_position)
	_current_snow_ground.deform_at(_last_hit_position, radius, intensity)
