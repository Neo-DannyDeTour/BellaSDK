@tool
class_name AccessibleLabel
extends StaticBody3D

## The text displayed visually on the in-game Label3D.
@export_multiline var display_text: String = "Accessible Label":
	set(value):
		display_text = value
		if is_node_ready():
			$Label3D.text = display_text

## The phonetic text read by the TTS engine. If empty, the system reads display_text.
@export_multiline var tts_alt_text: String = "":
	set(value):
		tts_alt_text = value
		if is_node_ready():
			$InteractComponent.alt_text_override = tts_alt_text

## Controls whether the label automatically faces the camera.
@export var billboard_mode: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_DISABLED:
	set(value):
		billboard_mode = value
		if is_node_ready():
			$Label3D.billboard = billboard_mode


func _ready() -> void:
	# Ensures the child nodes sync up with the exported variables
	# when the scene loads in-game or is first instanced in the editor.
	$Label3D.text = display_text
	$Label3D.billboard = billboard_mode

	# Safely assign the alt text to your interact component
	if has_node("InteractComponent"):
		$InteractComponent.alt_text_override = tts_alt_text
