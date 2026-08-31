## Controls and plays context-aware footstep audio based on surface materials.
##
## Scans geometry below the player via raycasts and maps group names to
## corresponding audio stream players. Also handles dynamic step intervals
## for sprinting, walking, crouching, and ladders.
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

## Fast lookup string for ice surface group checks.
const SURFACE_ICE: StringName = &"ice"
## Fast lookup string for metal surface group checks.
const SURFACE_METAL: StringName = &"metal"
## Fast lookup string for stone surface group checks.
const SURFACE_STONE: StringName = &"stone"
## Fast lookup string for wet dirt surface group checks.
const SURFACE_WET: StringName = &"wet_dirt"

## Tracks remaining time before the next footstep sound can trigger.
var step_timer: float = 0.0

## Flags if the player is currently standing on an ice surface (used by physics).
var is_on_ice: bool = false
## The currently selected audio player based on surface detection.
var active_audio_player: AudioStreamPlayer = null


## Initializes the default audio stream player on node setup.
func _ready() -> void:
	active_audio_player = audio_default


## Main loop evaluating movement speed and surface type to trigger audio.
## [param delta] The frame time delta in seconds.
## [param is_grounded] Whether the player is touching the floor.
## [param velocity_length] Current speed magnitude of the player.
## [param is_sprinting] True if sprint locomotion is active.
## [param is_crouching] True if crouch locomotion is active.
## [param is_on_ladder] True if the player is attached to a ladder.
## [param is_on_monkey_bar] True if the player is attached to monkey bars.
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
		return

	_scan_surface_material()

	if velocity_length > 0.5:
		step_timer -= delta
		if step_timer <= 0.0:
			print("FootstepManager: Playing surface footstep sound.")
			if active_audio_player:
				active_audio_player.play()
			_reset_timer(is_sprinting, is_crouching)
	else:
		step_timer = 0.0


## Projects a short raycast down from the player to read floor node groups.
func _scan_surface_material() -> void:
	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var ray_start: Vector3 = player_body.global_position + Vector3(0.0, 0.5, 0.0)
	var ray_end: Vector3 = player_body.global_position + Vector3(0.0, -1.0, 0.0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [player_body.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)

	active_audio_player = audio_default
	is_on_ice = false

	if result:
		var collider: Object = result.get("collider")

		if is_instance_valid(collider):
			if collider.is_in_group(SURFACE_ICE):
				is_on_ice = true
				if audio_ice:
					active_audio_player = audio_ice
			elif collider.is_in_group(SURFACE_METAL) and audio_metal:
				active_audio_player = audio_metal
			elif collider.is_in_group(SURFACE_STONE) and audio_stone:
				active_audio_player = audio_stone
			elif collider.is_in_group(SURFACE_WET) and audio_wet_dirt:
				active_audio_player = audio_wet_dirt


## Recharges the footstep step timer based on the current movement state.
## [param is_sprinting] True if sprint locomotion is active.
## [param is_crouching] True if crouch locomotion is active.
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
