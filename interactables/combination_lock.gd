## Interactive 3D padlock puzzle requiring a 3-character code to unlock.
class_name CombinationLock
extends Node3D

@export_category("Lock Settings")
## The 3-character string required to unlock this puzzle.
@export var secret_code: String = "123"
## If true, the dial uses letters A-Z instead of digits 0-9.
@export var use_letters: bool = false

@export_category("Visuals & Lighting")
## Target transform that the camera tweens toward on interaction.
@export var camera_view_point: Marker3D
## Packed scene for the UI overlay instantiated during interaction.
@export var lock_ui_scene: PackedScene
## Automatically turns on spotlight during interaction.
@export var enable_auto_light: bool = false

## Component handling raycast detection and interaction prompts.
@onready var interact_comp: InteractComponent = $InteractComponent
## Optional spotlight illuminating the lock during interaction.
@onready var puzzle_light: SpotLight3D = $SpotLight3D

## Active instance of the spawned [MachineLockUI] overlay.
var active_ui: MachineLockUI
## Caches player character currently interacting with the lock.
var interacting_player: CharacterBody3D
## Stores initial camera transform before focus tween starts.
var original_cam_transform: Transform3D
## Tween animating camera and puzzle light transitions.
var camera_tween: Tween


## Clamps secret code, resets light energy, and connects interaction.
func _ready() -> void:
	secret_code = secret_code.left(3).to_upper()

	if is_instance_valid(puzzle_light):
		puzzle_light.light_energy = 0.0

	if is_instance_valid(interact_comp):
		interact_comp.interacted.connect(_on_interacted)


## Begins puzzle interaction sequence and locks player movement.
func _on_interacted(character: CharacterBody3D) -> void:
	print("CombinationLock: Player interacted with lock.")
	if interacting_player != null:
		return

	interacting_player = character
	var state_machine: PlayerStateMachine = (
		interacting_player.get_node_or_null("StateMachine") as PlayerStateMachine
	)

	if state_machine:
		state_machine.transition_to("MachineLock")
		_focus_camera_and_ui()


## Tweens camera to target marker and safely instantiates lock UI.
func _focus_camera_and_ui() -> void:
	print("CombinationLock: Focusing camera and displaying lock UI.")
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

	if lock_ui_scene:
		var raw_ui: Node = lock_ui_scene.instantiate()
		if not (raw_ui is MachineLockUI):
			print("CombinationLock: Instantiated UI is not MachineLockUI. Freeing.")
			raw_ui.queue_free()
			return

		active_ui = raw_ui as MachineLockUI
		get_tree().root.add_child(active_ui)

		active_ui.setup(use_letters)
		active_ui.code_submitted.connect(_on_code_submitted)
		active_ui.aborted.connect(_release_player)


## Validates submitted code against [member secret_code].
func _on_code_submitted(code: String) -> void:
	print("CombinationLock: Submitted code evaluated: ", code)
	if code == secret_code:
		print("CombinationLock: Lock Solved!")

		_release_player()

		for child: Node in get_children():
			if child is MeshInstance3D or child is SpotLight3D:
				child.hide()

		if is_instance_valid(interact_comp):
			interact_comp.process_mode = Node.PROCESS_MODE_DISABLED

		if camera_tween and camera_tween.is_valid():
			await camera_tween.finished

		queue_free()
	else:
		print("CombinationLock: Incorrect Code.")


## Restores camera transform, frees UI overlay, and releases player.
func _release_player() -> void:
	print("CombinationLock: Releasing player and resetting camera.")
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
