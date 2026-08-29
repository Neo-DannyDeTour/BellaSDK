## Manages footstep audio synthesis based on physics material and player velocity.
##
## [FootstepManager] casts a ray downwards to determine the floor material and plays
## the corresponding sound effects. It also adjusts pacing based on locomotion states.
class_name FootstepManager
extends Node3D

@export_category("Node References")
## Reference to the main [CharacterBody3D] to cast rays from.
@export var player_body: CharacterBody3D

@export_category("Audio Players")
## Generic footstep audio fallback.
@export var audio_default: AudioStreamPlayer
## Metallic surface footstep audio.
@export var audio_metal: AudioStreamPlayer
## Stone surface footstep audio.
@export var audio_stone: AudioStreamPlayer
## Wet dirt or mud footstep audio.
@export var audio_wet_dirt: AudioStreamPlayer
## Ice or snow footstep audio.
@export var audio_ice: AudioStreamPlayer
## Metallic ladder climbing audio.
@export var audio_ladder: AudioStreamPlayer
## Overhead bar grabbing and swinging audio.
@export var audio_monkey_bar: AudioStreamPlayer

@export_category("Timing Intervals")
## Time between steps when walking.
@export var walk_step_interval: float = 0.45
## Time between steps when sprinting.
@export var sprint_step_interval: float = 0.28
## Time between steps when crouch walking.
@export var crouch_step_interval: float = 0.65
## Time between movements when climbing a ladder.
@export var ladder_step_interval: float = 0.55
## Time between movements on monkey bars.
@export var monkey_bar_step_interval: float = 0.65

## Group identifier for ice physics surfaces.
const SURFACE_ICE: StringName = &"ice"
## Group identifier for metal physics surfaces.
const SURFACE_METAL: StringName = &"metal"
## Group identifier for stone physics surfaces.
const SURFACE_STONE: StringName = &"stone"
## Group identifier for wet physics surfaces.
const SURFACE_WET: StringName = &"wet_dirt"

## Tracks time remaining until the next footstep sound should play.
var step_timer: float = 0.0
## Evaluated dynamically; true if the player is standing on the [constant SURFACE_ICE] group.
var is_on_ice: bool = false
## The currently selected audio stream based on traversal state and floor material.
var active_audio_player: AudioStreamPlayer = null


## Preloads the default audio player when the node enters the scene.
func _ready() -> void:
	active_audio_player = audio_default


## Drives footstep logic based on the player's active state and downward raycast hits.
## [param delta] Engine frame physics delta.
## [param is_grounded] True if the player is currently touching the floor.
## [param velocity_length] Current speed of the player in meters per second.
## [param is_sprinting] True if the player is running.
## [param is_crouching] True if the player is crouch-walking.
## [param is_on_ladder] True if the player is attached to a ladder.
## [param is_on_monkey_bar] True if the player is traversing monkey bars.
func process_surface_and_footsteps(
	delta: float,
	is_grounded: bool,
	velocity_length: float,
	is_sprinting: bool,
	is_crouching: bool,
	is_on_ladder: bool = false,
	is_on_monkey_bar: bool = false
) -> void:
	# --- FIXED: Monkey Bar Looping Logic ---
	if is_on_monkey_bar:
		active_audio_player = audio_monkey_bar
		if velocity_length > 0.1:
			# Player is moving. Play the sound if it's not already playing.
			if active_audio_player and not active_audio_player.playing:
				print("FootstepManager: Started looping monkey bar sound.")
				active_audio_player.play()
		else:
			# Player stopped. Stop the sound.
			if active_audio_player and active_audio_player.playing:
				print("FootstepManager: Stopped monkey bar sound.")
				active_audio_player.stop()

		# Return early so we bypass the rest of the footstep logic
		return

	# --- EXISTING: Ladder Logic ---
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

	# --- EXISTING: Ground Logic ---
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


## Casts a short raycast downward from the player to detect the floor surface group.
func _scan_surface_material() -> void:
	var space_state: PhysicsDirectSpaceState3D = player_body.get_world_3d().direct_space_state
	var ray_start: Vector3 = player_body.global_position + Vector3(0.0, 0.5, 0.0)
	var ray_end: Vector3 = player_body.global_position + Vector3(0.0, -1.0, 0.0)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.exclude = [player_body.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)

	# Reset defaults before checking
	active_audio_player = audio_default
	is_on_ice = false

	if result:
		var collider: Object = result.get("collider")

		if is_instance_valid(collider):
			# Check Ice (Also updates physics state)
			if collider.is_in_group(SURFACE_ICE):
				is_on_ice = true
				if audio_ice:
					active_audio_player = audio_ice
			# Check Metal
			elif collider.is_in_group(SURFACE_METAL) and audio_metal:
				active_audio_player = audio_metal
			# Check Stone
			elif collider.is_in_group(SURFACE_STONE) and audio_stone:
				active_audio_player = audio_stone
			# Check Wet Dirt
			elif collider.is_in_group(SURFACE_WET) and audio_wet_dirt:
				active_audio_player = audio_wet_dirt


## Configures the delay until the next footstep audio based on locomotion mode.
## [param is_sprinting] True if the sprint threshold is reached.
## [param is_crouching] True if the player is sneaking.
func _reset_timer(is_sprinting: bool, is_crouching: bool) -> void:
	if is_sprinting:
		step_timer = sprint_step_interval
	elif is_crouching:
		step_timer = crouch_step_interval
	else:
		step_timer = walk_step_interval


## Immediately ceases playback of all continuous or looping traversal audio (e.g., monkey bars).
func stop_looping_sounds() -> void:
	if audio_monkey_bar and audio_monkey_bar.playing:
		print("FootstepManager: Force stopping looping sounds on state exit.")
		audio_monkey_bar.stop()
