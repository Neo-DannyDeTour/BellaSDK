## Collapsible accordion button toggling visibility of sibling [Control] nodes.
@tool
class_name AccordionButton
extends Button

## Icon displayed when the accordion section is collapsed.
const ICON_CLOSED: Texture2D = preload(
	"res://addons/SunshineClouds2/Dock/Icons/caret-down-solid.svg"
)

## Icon displayed when the accordion section is expanded.
const ICON_OPEN: Texture2D = preload(
	"res://addons/SunshineClouds2/Dock/Icons/caret-up-solid.svg"
)

## Tracks whether the sibling controls are currently visible.
var curvisible: bool = false


## Configures button icon alignment and connects the [signal pressed] signal.
func _enter_tree() -> void:
	icon = ICON_CLOSED
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not pressed.is_connected(on_button_pressed):
		pressed.connect(on_button_pressed)


## Toggles the accordion open/closed state when clicked.
func on_button_pressed() -> void:
	curvisible = not curvisible
	print("AccordionButton: Toggled visibility to ", curvisible)
	_handle_visibility()


## Expands the accordion and reveals sibling [Control] nodes.
func open_accordion() -> void:
	curvisible = true
	print("AccordionButton: Opening accordion.")
	_handle_visibility()


## Collapses the accordion and hides sibling [Control] nodes.
func close_accordion() -> void:
	curvisible = false
	print("AccordionButton: Closing accordion.")
	_handle_visibility()


## Updates the caret icon and applies [member curvisible] to sibling controls.
func _handle_visibility() -> void:
	icon = ICON_OPEN if curvisible else ICON_CLOSED
	var parent: Node = get_parent()
	if not is_instance_valid(parent):
		return

	for child: Node in parent.get_children():
		if child != self and child is Control:
			(child as Control).visible = curvisible
