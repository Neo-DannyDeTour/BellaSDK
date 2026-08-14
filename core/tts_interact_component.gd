class_name TTSInteractComponent
extends Node

## Reference to the Label3D node containing the visual text in the level.
@export var target_label: Label3D = null

## Phonetic text override. If provided, the TTS engine reads this instead of the raw label text.
@export_multiline var alt_text_override: String = ""

## Prevents the TTS engine from being spammed every single frame the player looks at the label.
var _has_spoken: bool = false

## Tracks the engine frame to naturally determine when the player looks away.
var _last_hover_frame: int = 0


func _ready() -> void:
	print("TTSInteractComponent: Initialized and waiting for scanner.")


## Called by the InteractionScanner when the player's crosshair hits the object's physics body.
func hover_cursor(_player: Node3D, _hit_point: Vector3) -> void:
	var current_frame: int = Engine.get_process_frames()

	if not _has_spoken:
		_has_spoken = true
		var text_to_speak: String = (
			alt_text_override if alt_text_override != "" else _get_label_text()
		)
		print("TTSInteractComponent: Focus gained. Routing text to TTS: ", text_to_speak)

		if text_to_speak != "":
			# Pass 'self' as the caller reference
			Events.object_focused.emit(text_to_speak, self)

	_last_hover_frame = current_frame


func _process(_delta: float) -> void:
	# If the scanner stops calling hover_cursor, the frame count will slip behind.
	# We use this to cheaply detect focus loss without using heavy Area3D overlap checks.
	if _has_spoken and Engine.get_process_frames() > _last_hover_frame + 1:
		_has_spoken = false
		print("TTSInteractComponent: Focus lost. Resetting TTS trigger.")


## Safely attempts to retrieve the text from the target Label3D.
func _get_label_text() -> String:
	if is_instance_valid(target_label):
		return target_label.text
	return ""
