extends StaticBody3D
class_name FeedbackStation

@export_category("Configuration")
## Form url.
@export var form_url: String = "https://forms.gle/JnrmTWLiLv5Mhzfg8"

@export_category("Node References")
## Interact comp.
@export var interact_comp: InteractComponent
## Label.
@export var label: Label3D
## Sprite.
@export var sprite: Sprite3D

## Sprite initial y.
var _sprite_initial_y: float = 0.0
## Hover tween.
var _hover_tween: Tween = null


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


func _on_interacted(_character: CharacterBody3D) -> void:
	print("FeedbackStation: Player interacted. Attempting to open browser to: ", form_url)

	if not form_url.begins_with("https://"):
		var error_msg: String = (
			"FeedbackStation ERROR: URL must begin with 'https://'. Blocked: " + form_url
		)
		print(error_msg)
		if Console:
			Console.log_error(error_msg)
		return

	# OS.shell_open safely boots the user's default web browser
	var err: Error = OS.shell_open(form_url)
	if err != OK:
		print("FeedbackStation: ERROR opening URL. Code: ", err)


func _on_focused() -> void:
	print("FeedbackStation: Player focused on the station. Starting animation.")

	# Provide visual sugar when the player looks at it
	if is_instance_valid(label):
		label.modulate = Color(0.2, 1.0, 0.2)  # Highlight green

	if is_instance_valid(sprite):
		sprite.modulate = Color(0.2, 1.0, 0.2)

		# Kill the previous tween if it's currently running
		if _hover_tween and _hover_tween.is_valid():
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


func _on_unfocused() -> void:
	print("FeedbackStation: Player unfocused from the station. Stopping animation.")

	# Return to normal colors when looking away
	if is_instance_valid(label):
		label.modulate = Color.WHITE

	if is_instance_valid(sprite):
		sprite.modulate = Color.WHITE

		# Kill the bouncing loop
		if _hover_tween and _hover_tween.is_valid():
			_hover_tween.kill()

		# Smoothly return the sprite back to its exact starting height
		_hover_tween = create_tween()
		(
			_hover_tween
			. tween_property(sprite, "position:y", _sprite_initial_y, 0.2)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
