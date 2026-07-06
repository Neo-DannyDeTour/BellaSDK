class_name PathStick
extends PathFollow3D

# --------------------------------------
# CONFIGURATION VARIABLES
# (These are now populated automatically by the SlideTrack parent)
# --------------------------------------
var move_speed: float = 15.0
var throw_speed_threshold: float = 8.0
var throw_velocity_local: Vector3 = Vector3(0.0, 5.0, -20.0)
var stay_at_end: bool = false
var return_immediately: bool = false

# --------------------------------------
# STATE VARIABLES
# --------------------------------------
var current_player: Player = null
var current_speed: float = 0.0
var is_active: bool = false


# --------------------------------------
# BUILT-IN METHODS
# --------------------------------------
func _ready() -> void:
	print("PathStick: _ready() called.")
	loop = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	progress += current_speed * delta

	if progress_ratio >= 1.0:
		print("PathStick: Reached path endpoint.")
		_handle_endpoint()


# --------------------------------------
# INTERACTION & LOGIC
# --------------------------------------
func _on_interact_component_interacted(character: CharacterBody3D) -> void:
	print("PathStick: _on_interact_component_interacted() called. Triggering path stick action.")
	if is_active or not character is Player:
		return

	is_active = true
	current_player = character as Player
	current_speed = move_speed

	if current_player.has_method("enter_path_slide"):
		current_player.enter_path_slide(self)

	set_physics_process(true)


func _handle_endpoint() -> void:
	is_active = false
	set_physics_process(false)

	if not is_instance_valid(current_player):
		_process_return()
		return

	# 1. Throw the player if fast enough
	if current_speed >= throw_speed_threshold:
		var global_throw_dir: Vector3 = global_transform.basis * throw_velocity_local
		current_player.launch_from_path(global_throw_dir)
		_process_return()

	# 2. Handle low speeds
	else:
		if stay_at_end:
			print("PathStick: Speed too low. Holding player at endpoint.")
		else:
			print("PathStick: Speed too low. Dropping player.")
			current_player.exit_path_slide()
			_process_return()


# Called by StatePathSlide when the player jumps off manually
func release_player() -> void:
	current_player = null
	is_active = false
	set_physics_process(false)
	_process_return()


func _process_return() -> void:
	if return_immediately:
		progress_ratio = 0.0
