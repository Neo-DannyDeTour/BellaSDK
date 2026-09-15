extends GutTest

## The LogicButton instance under test.
var button: LogicButton = null
## Mock player character body to trigger interactions.
var mock_player: CharacterBody3D = null
## Mock mesh instance for highlighting tests.
var mock_mesh: MeshInstance3D = null
## Mock interact label for UI tests.
var mock_label: Label3D = null
## Mock interact component.
var mock_interact_comp: InteractComponent = null


func before_each() -> void:
	print("TestButton: before_each() setup.")

	button = load("res://shared/button.gd").new()
	add_child_autofree(button)

	mock_mesh = MeshInstance3D.new()
	button.add_child(mock_mesh)
	button.mesh_to_highlight = mock_mesh

	mock_label = Label3D.new()
	button.add_child(mock_label)
	button.label_interact = mock_label

	mock_interact_comp = load("res://interactables/interact_component.gd").new()
	button.add_child(mock_interact_comp)
	button.interact_component = mock_interact_comp

	mock_player = CharacterBody3D.new()
	add_child_autofree(mock_player)

	button._ready()


func test_on_focus() -> void:
	print("TestButton: test_on_focus() called.")
	button.outline_material = ShaderMaterial.new()
	button._on_focus()

	assert_true(mock_label.visible, "Interact label should be visible on focus.")
	assert_not_null(mock_mesh.material_overlay, "Mesh should have material overlay on focus.")


func test_on_unfocus() -> void:
	print("TestButton: test_on_unfocus() called.")
	mock_label.show()
	mock_mesh.material_overlay = ShaderMaterial.new()

	button._on_unfocus()

	assert_false(mock_label.visible, "Interact label should be hidden on unfocus.")
	assert_null(mock_mesh.material_overlay, "Mesh material overlay should be cleared on unfocus.")


func test_global_event_broadcast() -> void:
	print("TestButton: test_global_event_broadcast() called.")
	button.global_event_name = "test_event"
	button.can_press = true

	var mock_pressable: Node3D = Node3D.new()
	button.add_child(mock_pressable)
	button.pressable_part = mock_pressable

	watch_signals(Events)

	button._on_interact(mock_player)

	assert_signal_emitted_with_parameters(Events, "level_event_triggered", ["test_event", true])
