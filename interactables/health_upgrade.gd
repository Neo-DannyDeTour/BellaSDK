extends StaticBody3D
class_name HealthUpgrade

## The total amount of maximum health capacity granted to the player upon collection.
@export var health_bonus: int = 25

## The MeshInstance3D node representing the visual heart item in the world.
@export var heart_visual: MeshInstance3D

## The Node responsible for detecting player interaction and focus events.
@export var interact_component: Node

## The 3D text label that displays the interaction prompt to the player.
@export var prompt_label: Label3D

## The active tween responsible for managing the heartbeat scaling animation.
var _beat_tween: Tween


func _ready() -> void:
	print("HealthUpgrade: _ready() - Initializing upgrade.")

	if is_instance_valid(prompt_label):
		prompt_label.hide()

	if is_instance_valid(interact_component):
		if interact_component.has_signal("hover_cursor"):
			interact_component.hover_cursor.connect(_on_focused)
		elif interact_component.has_signal("focused"):
			interact_component.focused.connect(_on_focused)

		if interact_component.has_signal("unhover_cursor"):
			interact_component.unhover_cursor.connect(_on_unfocused)
		elif interact_component.has_signal("unfocused"):
			interact_component.unfocused.connect(_on_unfocused)

		if interact_component.has_signal("interacted"):
			interact_component.interacted.connect(_on_interacted)
	else:
		print("HealthUpgrade: _ready() - Missing InteractComponent reference!")


func interact_with(character: CharacterBody3D) -> void:
	print("HealthUpgrade: interact_with() - Called on root. Passing to component...")
	if is_instance_valid(interact_component) and interact_component.has_method("interact_with"):
		interact_component.interact_with(character)


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


func _on_focused() -> void:
	print(
		"HealthUpgrade: _on_focused() - Player focused. Starting beat animation and showing label."
	)

	if is_instance_valid(prompt_label):
		_update_label_text()
		prompt_label.show()

	if _beat_tween and _beat_tween.is_valid():
		_beat_tween.kill()

	_beat_tween = create_tween().set_loops()

	_beat_tween.tween_property(heart_visual, "scale", Vector3(1.3, 1.3, 1.3), 0.2).set_trans(
		Tween.TRANS_SINE
	)

	_beat_tween.tween_property(heart_visual, "scale", Vector3(1.0, 1.0, 1.0), 0.2).set_trans(
		Tween.TRANS_SINE
	)

	_beat_tween.tween_interval(0.5)


func _on_unfocused() -> void:
	print(
		"HealthUpgrade: _on_unfocused() - Player unfocused. Stopping beat animation and hiding label."
	)

	if is_instance_valid(prompt_label):
		prompt_label.hide()

	if _beat_tween and _beat_tween.is_valid():
		_beat_tween.kill()

	if is_instance_valid(heart_visual):
		heart_visual.scale = Vector3.ONE


func _on_interacted(character: CharacterBody3D) -> void:
	print("HealthUpgrade: _on_interacted() - Signal received. Searching for HealthComponent...")

	var health_comp: Node = character.find_child("HealthComponent", true, false)

	if is_instance_valid(health_comp) and health_comp.has_method("increase_max_health"):
		print("HealthUpgrade: _on_interacted() - Success! Granting ", health_bonus, " max health.")
		health_comp.increase_max_health(health_bonus)
		queue_free()
	else:
		print(
			"HealthUpgrade: _on_interacted() - ERROR: No HealthComponent found on ", character.name
		)
