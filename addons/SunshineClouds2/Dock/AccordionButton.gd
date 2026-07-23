# gdlint: ignore=class-definitions-order
@tool
class_name AccordionButton
extends Button

var curvisible : bool = false

func _enter_tree() -> void:
	# gdlint: disable=max-line-length
	icon = ResourceLoader.load("res://addons/SunshineClouds2/Dock/Icons/caret-down-solid.svg")
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if (!pressed.is_connected(on_button_pressed.bind())):
		pressed.connect(on_button_pressed.bind())

func on_button_pressed() -> void:
	curvisible = !curvisible
	_handle_visibility()

func open_accordion() -> void:
	curvisible = true
	_handle_visibility()

func close_accordion() -> void:
	curvisible = false
	_handle_visibility()

func _handle_visibility() -> void:
	if (!curvisible):
		# gdlint: disable=max-line-length
		icon = ResourceLoader.load("res://addons/SunshineClouds2/Dock/Icons/caret-down-solid.svg")
	else:
		# gdlint: disable=max-line-length
		icon = ResourceLoader.load("res://addons/SunshineClouds2/Dock/Icons/caret-up-solid.svg")

	for child in get_parent().get_children():
		if (child != self and child is Control):
			child.visible = curvisible
