extends GutTest

## The component being tested.
var component: TTSInteractComponent

## A mock label.
var label: Label3D


func before_each() -> void:
	print("test_tts_interact_component: before_each() - Setup.")
	component = TTSInteractComponent.new()
	label = Label3D.new()

	component.target_label = label

	add_child_autofree(component)
	add_child_autofree(label)


func test_hover_cursor_emits_label_text() -> void:
	print("test_tts_interact_component: test_hover_cursor_emits_label_text().")
	label.text = "Hello Test Label"

	watch_signals(Events)

	component.hover_cursor(Node3D.new(), Vector3.ZERO)

	assert_signal_emitted_with_parameters(Events, "object_focused", ["Hello Test Label", component])


func test_hover_cursor_emits_alt_text() -> void:
	print("test_tts_interact_component: test_hover_cursor_emits_alt_text().")
	label.text = "Visual Text"
	component.alt_text_override = "Audio Text"

	watch_signals(Events)

	component.hover_cursor(Node3D.new(), Vector3.ZERO)

	assert_signal_emitted_with_parameters(Events, "object_focused", ["Audio Text", component])
