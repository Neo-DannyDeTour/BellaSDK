extends Area3D

# This will create a slot in the Inspector to select your building
@export var target_building: Node3D


func _ready() -> void:
	# Connect both enter and exit signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	# Ensure it's the player triggering this
	if body is CharacterBody3D:
		if target_building:
			target_building.hide()
			# PRO TIP: hide() only stops rendering.
			# If you want to disable physics and scripts too (for performance):
			target_building.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			push_error("Hide Trigger: No target building assigned!")


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		if target_building:
			target_building.show()
			# If you disabled the process mode above, re-enable it here:
			target_building.process_mode = Node.PROCESS_MODE_INHERIT
