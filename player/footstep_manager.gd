## Plays context-aware footsteps and indents dynamic terrain surfaces.
class_name FootstepManager
extends Node3D

@export_category("Node References")
## Reference to the main player body, used as the origin for downward raycasts.
@export var player_body: CharacterBody3D

@export_category("Audio Players")
## Default footstep sound played when no specific surface is matched.
@export var audio_default: AudioStreamPlayer
## Footstep sound for metal grid/panel surfaces.
@export var audio_metal: AudioStreamPlayer
## Footstep sound for hard stone/concrete surfaces.
@export var audio_stone: AudioStreamPlayer
## Footstep sound for mud or wet dirt surfaces.
@export var audio_wet_dirt: AudioStreamPlayer
## Footstep sound for slippery ice surfaces.
@export var audio_ice: AudioStreamPlayer
## Footstep sound played when traversing deformable snow surfaces.
@export var audio_snow: AudioStreamPlayer
## Climbing sound used specifically while traversing ladders.
@export var audio_ladder: AudioStreamPlayer
## Hand-over-hand looping audio used specifically for monkey bar traversal.
@export var audio_monkey_bar: AudioStreamPlayer

@export_category("Timing Intervals")
## Time gap between footstep sounds while walking normally.
@export var walk_step_interval: float = 0.45
## Time gap between footstep sounds while sprinting.
@export var sprint_step_interval: float = 0.28
## Time gap between footstep sounds while crouch walking.
@export var crouch_step_interval: float = 0.65
## Time gap between climbing sounds while ascending or descending ladders.
@export var ladder_step_interval: float = 0.55
## Time gap between grabbing sounds while on monkey bars (if not looping).
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

## Tracks remaining time before the next footstep sound can trigger.
var step_timer: float = 0.0
## Flags if the player is currently standing on an ice surface.
var is_on_ice: bool = false
## Flags if the player is currently standing on deformable snow.
var is_on_snow: bool = false
## The currently selected audio player based on surface detection.
var active_audio_player: AudioStreamPlayer = null
## Active [SnowGround] node currently beneath the player body.
var _current_snow_ground: SnowGround = null
## World coordinate of the most recent floor raycast collision.
var _last_hit_position: Vector3 = Vector3.ZERO
## World position of the previous slide deformation stamp.
var _last_slide_carve_pos: Vector3 = Vector3.ZERO


## Initializes the default audio stream player on node setup.
func _ready() -> void:
	print("FootstepManager: _ready() initialized.")
	active_audio_player = audio_default


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
		active_audio_player = audio_monkey_bar
		if velocity_length > 0.1:
			if active_audio_player and not active_audio_player.playing:
				print("FootstepManager: Started looping monkey bar sound.")
				active_audio_player.play()
		else:
			if active_audio_player and active_audio_player.playing:
				print("FootstepManager: Stopped monkey bar sound.")
				active_audio_player.stop()
		return

	if is_on_ladder:
		active_audio_player = audio_ladder
		if velocity_length > 0.5:
			step_timer -= delta
			if step_timer <= 0.0:
				print("FootstepManager: Playing ladder climbing sound.")
				if active_audio_player:
					active_audio_player.play()
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
			print("FootstepManager: Playing surface footstep sound.")
			if active_audio_player:
				active_audio_player.play()

			if is_on_snow and is_instance_valid(_current_snow_ground):
				_stamp_snow_footstep(is_sprinting, is_crouching)

			_reset_timer(is_sprinting, is_crouching)
	else:
		step_timer = 0.0


## Projects a downward ray to read surface colliders and hit positions.
func _scan_surface_material() -> void:
	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var ray_start: Vector3 = player_body.global_position + Vector3(0.0, 0.5, 0.0)
	var ray_end: Vector3 = player_body.global_position + Vector3(0.0, -1.0, 0.0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [player_body.get_rid()]
	query.collision_mask = 1

	var result: Dictionary = space_state.intersect_ray(query)

	active_audio_player = audio_default
	is_on_ice = false
	is_on_snow = false
	_current_snow_ground = null

	if result.is_empty():
		return

	var collider: Object = result.get("collider")
	_last_hit_position = result.get("position", Vector3.ZERO)

	if not is_instance_valid(collider):
		return

	var target_node: Node = collider as Node
	var parent_node: Node = target_node.get_parent() if target_node else null

	if target_node is SnowGround:
		_current_snow_ground = target_node as SnowGround
		is_on_snow = true
	elif parent_node is SnowGround:
		_current_snow_ground = parent_node as SnowGround
		is_on_snow = true
	elif (
		target_node.is_in_group(SURFACE_SNOW)
		or (parent_node and parent_node.is_in_group(SURFACE_SNOW))
	):
		is_on_snow = true
		if parent_node is SnowGround:
			_current_snow_ground = parent_node as SnowGround

	if is_on_snow and audio_snow:
		active_audio_player = audio_snow
	elif target_node.is_in_group(SURFACE_ICE):
		is_on_ice = true
		if audio_ice:
			active_audio_player = audio_ice
	elif target_node.is_in_group(SURFACE_METAL) and audio_metal:
		active_audio_player = audio_metal
	elif target_node.is_in_group(SURFACE_STONE) and audio_stone:
		active_audio_player = audio_stone
	elif target_node.is_in_group(SURFACE_WET) and audio_wet_dirt:
		active_audio_player = audio_wet_dirt


## Stamps a footprint depression into active [SnowGround] at impact point.
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

	# Calculate 2D rotation angle.
	# In Godot, the forward vector of a 3D node points down the -Z axis (0, 0, -1).
	# Since deformation happens in the local planar coordinate system of SnowGround (UV space is 2D),
	# we need the rotation in the XZ plane.

	# Extract the rotation around the Y-axis (up vector).
	var travel_basis: Basis = player_body.global_transform.basis
	var travel_forward: Vector3 = travel_basis.z.normalized()  # Extract Z direction
	var rotation_angle: float = atan2(-travel_forward.x, travel_forward.z)

	# atan2 gives the angle from the positive Z axis clockwise toward the positive X axis.
	# Since our texture points +Y 'up' on the canvas, 0 rotation on the canvas is forward.
	# This angle calculation should map player yaw correctly.
	# We negate 'travel_forward.x' because Godot's screen coordinates (used by CanvasPainter)
	# are X-right and Y-down.

	# Apply a +90 degree correction to align the boot texture correctly if necessary.
	# For a texture that points "up", no correction is needed.

	# rotation_angle = wrapf(rotation_angle + PI/2.0, -PI, PI)

	print(
		"FootstepManager: Stamping boot print at ",
		_last_hit_position,
		" angle: ",
		rad_to_deg(rotation_angle)
	)
	# Pass the angle to SnowGround.
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


## Recharges the footstep step timer based on the current movement state.
func _reset_timer(is_sprinting: bool, is_crouching: bool) -> void:
	if is_sprinting:
		step_timer = sprint_step_interval
	elif is_crouching:
		step_timer = crouch_step_interval
	else:
		step_timer = walk_step_interval


## Halts playback of continuous audio streams, such as the monkey bar loop.
func stop_looping_sounds() -> void:
	if audio_monkey_bar and audio_monkey_bar.playing:
		print("FootstepManager: Force stopping looping sounds on state exit.")
		audio_monkey_bar.stop()


## Stamps an impact crater into snow based on vertical landing speed.
func stamp_landing_crater(fall_speed: float) -> void:
	_scan_surface_material()
	if not is_on_snow or not is_instance_valid(_current_snow_ground):
		return

	var speed_factor: float = clampf(absf(fall_speed) / 12.0, 0.5, 2.0)
	var radius: float = snow_stamp_radius * 2.2 * speed_factor
	var intensity: float = clampf(0.5 + (speed_factor * 0.3), 0.5, 1.0)

	print("FootstepManager: Stamping landing crater at ", _last_hit_position)
	_current_snow_ground.deform_at(_last_hit_position, radius, intensity)
