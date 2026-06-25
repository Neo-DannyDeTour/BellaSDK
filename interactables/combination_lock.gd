class_name CombinationLock
extends Node3D

@export_category("Lock Settings")
@export var secret_code: String = "123"
@export var use_letters: bool = false

@export_category("Visuals & Lighting")
@export var camera_view_point: Marker3D
@export var lock_ui_scene: PackedScene
@export var enable_auto_light: bool = false

@onready var interact_comp: Interact_Component = $Interact_Component
@onready var puzzle_light: SpotLight3D = $SpotLight3D

var active_ui: MachineLockUI
var interacting_player: CharacterBody3D
var original_cam_transform: Transform3D
var camera_tween: Tween


func _ready() -> void:
	print("CombinationLock: _ready() called. Formatting secret code.")
	# Enforce the 3 character limit AND force uppercase to prevent mismatch errors
	secret_code = secret_code.left(3).to_upper()
	
	if puzzle_light:
		puzzle_light.light_energy = 0.0
		
	if interact_comp:
		interact_comp.interacted.connect(_on_interacted)


func _on_interacted(character: CharacterBody3D) -> void:
	if interacting_player != null:
		return # Already in use
		
	interacting_player = character
	var state_machine := interacting_player.get_node_or_null("StateMachine") as PlayerStateMachine
	
	if state_machine:
		# Reuse your existing lock state!
		state_machine.transition_to("MachineLock")
		_focus_camera_and_ui()


func _focus_camera_and_ui() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera and camera_view_point:
		original_cam_transform = camera.global_transform
		
		if camera_tween and camera_tween.is_valid():
			camera_tween.kill()
			
		camera_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
		camera_tween.tween_property(camera, "global_transform", camera_view_point.global_transform, 0.4)
		
		if enable_auto_light and puzzle_light:
			camera_tween.tween_property(puzzle_light, "light_energy", 1.5, 0.4)
			
	# Spawn the updated UI
	if lock_ui_scene:
		active_ui = lock_ui_scene.instantiate() as MachineLockUI
		get_tree().root.add_child(active_ui)
		
		# Pass the inspector settings to the UI
		active_ui.setup(use_letters)
		
		active_ui.code_submitted.connect(_on_code_submitted)
		active_ui.aborted.connect(_release_player)


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
		if interact_comp:
			interact_comp.process_mode = Node.PROCESS_MODE_DISABLED
			
		# 3. Wait safely for the camera tween to finish moving the player's view
		if camera_tween and camera_tween.is_valid():
			await camera_tween.finished
			
		# 4. Finally, destroy the node from memory
		queue_free()
		
	else:
		print("Incorrect Code.")


func _release_player() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		if camera_tween and camera_tween.is_valid():
			camera_tween.kill()
			
		camera_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT).set_parallel(true)
		camera_tween.tween_property(camera, "global_transform", original_cam_transform, 0.4)
		
		if puzzle_light:
			camera_tween.tween_property(puzzle_light, "light_energy", 0.0, 0.4)
			
	if active_ui:
		active_ui.queue_free()
		
	if interacting_player:
		var state_machine := interacting_player.get_node_or_null("StateMachine") as PlayerStateMachine
		if state_machine:
			state_machine.transition_to("Ground")
		interacting_player = null
