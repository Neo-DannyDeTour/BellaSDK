## A standalone terminal that allows playtesters to submit feedback via an external web browser.
##
## Animates floating icons when looked at by the player and uses [OS.shell_open] to securely
## redirect to a provided survey URL.
class_name FeedbackStation
extends StaticBody3D

@export_category("Configuration")
## The secure web address opened when the player interacts with the station.
@export var form_url: String = "https://forms.gle/JnrmTWLiLv5Mhzfg8"

@export_category("Node References")
## Interaction component bound to the station's collision mesh.
@export var interact_comp: InteractComponent
## Floating 3D text describing the terminal.
@export var label: Label3D
## Floating 2D icon providing visual focus feedback.
@export var sprite: Sprite3D

## Caches the starting height of the sprite to allow smooth looping bounce animations.
var _sprite_initial_y: float = 0.0
## Active tween controller for managing hover animations.
var _hover_tween: Tween = null


## Stores initial coordinates and binds interaction signals.
func _ready() -> void:
	print("FeedbackStation: Initializing scene.")

	if is_instance_valid(sprite):
		_sprite_initial_y = sprite.position.y

	if is_instance_valid(interact_comp):
		# Connect to the signals emitted by your custom InteractComponent
		interact_comp.interacted.connect(_on_interacted)
		interact_comp.focused.connect(_on_focused)
		interact_comp.unfocused.connect(_on_unfocused)
	else:
		print("FeedbackStation: ERROR - InteractComponent is missing or not assigned!")


## Validates the configured URL scheme and boots the default web browser.
## [param _character]: The player character initiating the interaction.
func _on_interacted(_character: CharacterBody3D) -> void:
	print("FeedbackStation: Player interacted. Attempting to open browser to: ", form_url)

	if not form_url.begins_with("https://"):
		var error_msg: String = (
			"FeedbackStation ERROR: URL must begin with 'https://'. Blocked: " + form_url
		)
		print(error_msg)
		if Console:
			Console.call("log_error", error_msg)
		return

	# OS.shell_open safely boots the user's default web browser
	var err: Error = OS.shell_open(form_url)
	if err != OK:
		print("FeedbackStation: ERROR opening URL. Code: ", err)


## Activates highlight colors and begins the looping bobbing animation when looked at.
func _on_focused() -> void:
	print("FeedbackStation: Player focused on the station. Starting animation.")

	# Provide visual sugar when the player looks at it
	if is_instance_valid(label):
		label.modulate = Color(0.2, 1.0, 0.2)  # Highlight green

	if is_instance_valid(sprite):
		sprite.modulate = Color(0.2, 1.0, 0.2)

		# Kill the previous tween if it's currently running
		if is_instance_valid(_hover_tween):
			_hover_tween.kill()

		# Create a looping animation
		_hover_tween = create_tween()
		_hover_tween.set_loops()

		# Bounce up
		(
			_hover_tween
			. tween_property(sprite, "position:y", _sprite_initial_y + 0.15, 0.4)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)

		# Bounce down
		(
			_hover_tween
			. tween_property(sprite, "position:y", _sprite_initial_y, 0.4)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)


## Reverts colors and smooths the floating icon back to its original resting height.
func _on_unfocused() -> void:
	print("FeedbackStation: Player unfocused from the station. Stopping animation.")

	# Return to normal colors when looking away
	if is_instance_valid(label):
		label.modulate = Color.WHITE

	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

		# Kill the bouncing loop
		if is_instance_valid(_hover_tween):
			_hover_tween.kill()

		# Smoothly return the sprite back to its exact starting height
		_hover_tween = create_tween()
		(
			_hover_tween
			. tween_property(sprite, "position:y", _sprite_initial_y, 0.2)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
