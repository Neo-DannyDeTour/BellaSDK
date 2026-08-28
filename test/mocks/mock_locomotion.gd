## Test mock for PlayerLocomotionComponent tracking
## movement parameters, stance states, and physics flags.
class_name MockLocomotion
extends PlayerLocomotionComponent

## Tracks whether physics simulation loop is enabled for the component.
var is_physics_active: bool = true

## Tracks the simulated timestamp in milliseconds of the last sprint action.
var last_sprint_timestamp: int = 0


## Initializes default locomotion test values and sprint permissions.
func _init() -> void:
	can_sprint = true
	is_active = true
	walking_speed = 5.0
	sprinting_speed = 6.5
	crouching_speed = 3.0
	swimming_speed = 4.0
	swim_up_speed = 5.0


## Stub initialization method caching the owner player reference.
## [param p_player] The root [Player] controller entity.
func initialize(p_player: Player) -> void:
	print("MockLocomotion: initialize() called with player: ", p_player.name)
	player = p_player


## Enables or disables movement physics execution.
## [param active] Target active status boolean.
func set_physics_active(active: bool) -> void:
	print("MockLocomotion: set_physics_active() set to: ", active)
	is_physics_active = active
	is_active = active


## Stub per-frame movement processor.
## [param delta] Physics frame delta time in seconds.
func process_movement(delta: float) -> void:
	if not is_active or not is_instance_valid(player):
		return

	if sprint_active:
		last_sprint_timestamp = Time.get_ticks_msec()
		_last_sprint_time = last_sprint_timestamp

	_interpolate_head_height(delta)


## Evaluates whether the player ran within the specified time window.
## [param time_window_ms] Time threshold in milliseconds.
## [return] True if sprinting occurred recently.
func did_run_recently(time_window_ms: int = 10000) -> bool:
	var ran_recently: bool = (Time.get_ticks_msec() - last_sprint_timestamp) <= time_window_ms
	print("MockLocomotion: did_run_recently() evaluated -> ", ran_recently)
	return ran_recently


## Sets the intended directional vector.
## [param new_dir] Target [Vector3] direction.
func set_direction(new_dir: Vector3) -> void:
	print("MockLocomotion: set_direction() set to: ", new_dir)
	direction = new_dir


## Returns the active intended movement heading.
## [return] Current [Vector3] direction vector.
func get_direction() -> Vector3:
	return direction


## Stub resetting momentum and clearing velocity vectors.
func reset_momentum() -> void:
	print("MockLocomotion: reset_momentum() called.")
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
	last_velocity = Vector3.ZERO
	direction = Vector3.ZERO
