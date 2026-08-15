## A collectible item that permanently expands the player's maximum health pool.
##
## Animates a visual heartbeat effect when looked at and dynamically binds to the global
## interact keymapping to display a contextual prompt label.
class_name HealthUpgrade
extends StaticBody3D

## The total amount of maximum health capacity granted to the player upon collection.
@export var health_bonus: int = 25

## The [MeshInstance3D] node representing the visual heart item in the world.
@export var heart_visual: MeshInstance3D

## The [InteractComponent] responsible for detecting player interaction and focus events.
@export var interact_component: Node

## The 3D text label that displays the interaction prompt to the player.
@export var prompt_label: Label3D

## The active [Tween] responsible for managing the heartbeat scaling animation.
var _beat_tween: Tween


## Disables the prompt label and connects all required signals from the [member interact_component].
func _ready() -> void:
	print("HealthUpgrade: _ready() - Initializing upgrade.")

	if is_instance_valid(prompt_label):
		prompt_label.hide()

	if is_instance_valid(interact_component):
		if interact_component.has_signal("hover_cursor"):
			interact_component.connect("hover_cursor", _on_focused)
		elif interact_component.has_signal("focused"):
			interact_component.connect("focused", _on_focused)

		if interact_component.has_signal("unhover_cursor"):
			interact_component.connect("unhover_cursor", _on_unfocused)
		elif interact_component.has_signal("unfocused"):
			interact_component.connect("unfocused", _on_unfocused)

		if interact_component.has_signal("interacted"):
			interact_component.connect("interacted", _on_interacted)
	else:
		print("HealthUpgrade: _ready() - Missing InteractComponent reference!")


## Redirects parent-level interaction calls directly to the assigned [member interact_component].
## [param character]: The player character initiating the interaction.
func interact_with(character: CharacterBody3D) -> void:
	print("HealthUpgrade: interact_with() - Called on root. Passing to component...")
	if is_instance_valid(interact_component) and interact_component.has_method("interact_with"):
		interact_component.call("interact_with", character)


## Parses the global input map to display the exact key bound to the "interact" action.
func _update_label_text() -> void:
	print("HealthUpgrade: _update_label_text() - Fetching dynamic interact key.")
	if not is_instance_valid(prompt_label):
		return

	var events: Array[InputEvent] = InputMap.action_get_events("interact")
	var key_name: String = "???"

	if events.size() > 0:
		var raw_text: String = events[0].as_text()
		key_name = (
			raw_text
			. replace(" (Physical)", "")
			. replace(" - Physical", "")
			. replace(" (Physics)", "")
			. replace(" - Physics", "")
			. replace("Left Mouse Button", "LMB")
			. replace("Right Mouse Button", "RMB")
			. replace("Middle Mouse Button", "MMB")
			. strip_edges()
		)

	prompt_label.text = "Press [%s] to Interact" % [key_name]


## Initiates the looping heartbeat scaling animation when the player's crosshair hovers the mesh.
func _on_focused() -> void:
	print(
		"HealthUpgrade: _on_focused() - Player focused. ",
		"Starting beat animation and showing label."
	)

	if is_instance_valid(prompt_label):
		_update_label_text()
		prompt_label.show()

	if is_instance_valid(_beat_tween):
		_beat_tween.kill()

	_beat_tween = create_tween().set_loops()

	_beat_tween.tween_property(heart_visual, "scale", Vector3(1.3, 1.3, 1.3), 0.2).set_trans(
		Tween.TRANS_SINE
	)

	_beat_tween.tween_property(heart_visual, "scale", Vector3(1.0, 1.0, 1.0), 0.2).set_trans(
		Tween.TRANS_SINE
	)

	_beat_tween.tween_interval(0.5)


## Cancels the heartbeat animation and restores the base mesh scale when the player looks away.
func _on_unfocused() -> void:
	print(
		"HealthUpgrade: _on_unfocused() - Player unfocused. ",
		"Stopping beat animation and hiding label."
	)

	if is_instance_valid(prompt_label):
		prompt_label.hide()

	# Safely kill the tween to prevent errors
	if is_instance_valid(_beat_tween):
		_beat_tween.kill()
		_beat_tween = null

	# Reset the heart visual back to its default state
	if is_instance_valid(heart_visual):
		heart_visual.scale = Vector3(1.0, 1.0, 1.0)


## Verifies the interacting player has a valid health component and applies the upgrade.
## [param character]: The player character node.
func _on_interacted(character: CharacterBody3D) -> void:
	print("HealthUpgrade: _on_interacted() - Signal received. Searching for HealthComp...")

	var health_comp: Node = character.find_child("HealthComponent", true, false)

	if is_instance_valid(health_comp) and health_comp.has_method("increase_max_health"):
		print("HealthUpgrade: _on_interacted() - Success! Granting ", health_bonus, " max hp.")
		health_comp.call("increase_max_health", health_bonus)
		queue_free()
	else:
		print(
			"HealthUpgrade: _on_interacted() - ERROR: No HealthComponent found on ", character.name
		)
