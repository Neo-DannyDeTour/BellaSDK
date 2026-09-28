## Tests TTSInteractComponent event emission on hover cursor events.
class_name TestTTSInteractComponent
extends GutTest

## The [TTSInteractComponent] instance under test.
var component: TTSInteractComponent = null

## The mock [Label3D] node providing text for the component.
var label: Label3D = null

## Mock player node passed into hover cursor calls.
var mock_player: Node3D = null


## Sets up component, label, and mock player dependencies before each test.
func before_each() -> void:
	print("TestTTSInteractComponent: before_each() setup started.")
	component = TTSInteractComponent.new()
	label = Label3D.new()
	mock_player = Node3D.new()

	component.target_label = label

	add_child_autofree(component)
	add_child_autofree(label)
	add_child_autofree(mock_player)


## Verifies [method TTSInteractComponent.hover_cursor] emits label text.
func test_hover_cursor_emits_label_text() -> void:
	print("TestTTSInteractComponent: test_hover_cursor_emits_label_text() called.")
	label.text = "Hello Test Label"

	watch_signals(Events)

	component.hover_cursor(mock_player, Vector3.ZERO)

	assert_signal_emitted_with_parameters(Events, "object_focused", ["Hello Test Label", component])


## Verifies [method TTSInteractComponent.hover_cursor] emits alternate text.
func test_hover_cursor_emits_alt_text() -> void:
	print("TestTTSInteractComponent: test_hover_cursor_emits_alt_text() called.")
	label.text = "Visual Text"
	component.alt_text_override = "Audio Text"

	watch_signals(Events)

	component.hover_cursor(mock_player, Vector3.ZERO)

	assert_signal_emitted_with_parameters(Events, "object_focused", ["Audio Text", component])
