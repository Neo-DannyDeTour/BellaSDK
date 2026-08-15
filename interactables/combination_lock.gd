## A 3D interactive padlock that requires a 3-character code to unlock.
##
## Traps the player in a cinematic lock state, smoothly animates the camera to focus on the object,
## and spawns a dedicated UI overlay to input numbers or letters.
class_name CombinationLock
extends Node3D

@export_category("Lock Settings")
## The 3-character correct string required to solve the lock.
@export var secret_code: String = "123"
## If true, the lock UI dial will scroll through letters A-Z instead of numbers 0-9.
@export var use_letters: bool = false

@export_category("Visuals & Lighting")
## The target 3D transform that the player's camera will tween to upon interaction.
@export var camera_view_point: Marker3D
## The packed scene representing the UI overlay spawned during lock interaction.
@export var lock_ui_scene: PackedScene
## Automatically turns on an attached spotlight to illuminate the lock while interacting.
@export var enable_auto_light: bool = false

## Handles raycast detection and interaction prompts.
@onready var interact_comp: InteractComponent = $InteractComponent
## Optional spotlight that toggles on during interaction for visibility.
@onready var puzzle_light: SpotLight3D = $SpotLight3D

## A reference to the instantiated UI overlay.
var active_ui: MachineLockUI
## Caches the character currently engaged with the lock.
var interacting_player: CharacterBody3D
## Saves the player's camera position before moving it, allowing for a smooth return.
var original_cam_transform: Transform3D
## Tween responsible for animating the camera and lighting interpolations.
var camera_tween: Tween


## Clamps the code and binds the interaction component.
func _ready() -> void:
	# Enforce the 3 character limit AND force uppercase to prevent mismatch errors
	secret_code = secret_code.left(3).to_upper()

	if is_instance_valid(puzzle_light):
		puzzle_light.light_energy = 0.0

	if is_instance_valid(interact_comp):
		interact_comp.interacted.connect(_on_interacted)


## Begins the cinematic sequence locking the player into the puzzle.
## [param character]: The player character initiating the interaction.
func _on_interacted(character: CharacterBody3D) -> void:
	print("CombinationLock: _on_interacted() called. Processing lock interaction.")
	if interacting_player != null:
		return  # Already in use

	interacting_player = character
	var state_machine: PlayerStateMachine = (
		interacting_player.get_node_or_null("StateMachine") as PlayerStateMachine
	)

	if state_machine:
		# Reuse your existing lock state!
		state_machine.transition_to("MachineLock")
		_focus_camera_and_ui()


## Tweens the camera towards the lock and instantiates the code entry UI.
func _focus_camera_and_ui() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera and camera_view_point:
		original_cam_transform = camera.global_transform

		if camera_tween and camera_tween.is_valid():
			camera_tween.kill()

		camera_tween = (
			create_tween()
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN_OUT)
			. set_parallel(true)
		)
		camera_tween.tween_property(
			camera, "global_transform", camera_view_point.global_transform, 0.4
		)

		if enable_auto_light and is_instance_valid(puzzle_light):
			camera_tween.tween_property(puzzle_light, "light_energy", 1.5, 0.4)

	# Spawn the updated UI
	if lock_ui_scene:
		active_ui = lock_ui_scene.instantiate() as MachineLockUI
		get_tree().root.add_child(active_ui)

		# Pass the inspector settings to the UI
		active_ui.setup(use_letters)

		active_ui.code_submitted.connect(_on_code_submitted)
		active_ui.aborted.connect(_release_player)


## Validates the submitted sequence against the expected [member secret_code].
## [param code]: The 3-character string passed from the UI.
func _on_code_submitted(code: String) -> void:
	if code == secret_code:
		print("Lock Solved!")

		# 1. Trigger the normal release sequence (handles UI and camera tween)
		_release_player()

		# 2. Make the lock visually disappear instantly
		for child: Node in get_children():
			if child is MeshInstance3D or child is SpotLight3D:
				child.hide()

		# Disable interactions so the player can't click the invisible lock
		if is_instance_valid(interact_comp):
			interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

		# 3. Wait safely for the camera tween to finish moving the player's view
		if camera_tween and camera_tween.is_valid():
			await camera_tween.finished

		# 4. Finally, destroy the node from memory
		queue_free()

	else:
		print("Incorrect Code.")


## Restores the camera's original transform, deletes the UI overlay, and frees player movement.
func _release_player() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		if camera_tween and camera_tween.is_valid():
			camera_tween.kill()

		camera_tween = (
			create_tween()
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN_OUT)
			. set_parallel(true)
		)
		camera_tween.tween_property(camera, "global_transform", original_cam_transform, 0.4)

		if is_instance_valid(puzzle_light):
			camera_tween.tween_property(puzzle_light, "light_energy", 0.0, 0.4)

	if is_instance_valid(active_ui):
		active_ui.queue_free()

	if is_instance_valid(interacting_player):
		var state_machine: PlayerStateMachine = (
			interacting_player.get_node_or_null("StateMachine") as PlayerStateMachine
		)
		if state_machine:
			state_machine.transition_to("Ground")
		interacting_player = null
