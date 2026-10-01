## Bottom panel UI managing editable Source-like [EventStep] sequence actions.
@tool
class_name EventSequencerDock
extends PanelContainer

## Reference to the currently inspected [EventSequenceTrigger].
var current_trigger: EventSequenceTrigger = null

## Tree control rendering event steps as rows and editable columns.
var tree_view: Tree = null

## Label displaying selected trigger node name.
var header_label: Label = null

## Button to add a new event step to sequence.
var add_btn: Button = null

## Button to remove the selected step.
var remove_btn: Button = null

## Button to move the selected step up.
var up_btn: Button = null

## Button to move the selected step down.
var down_btn: Button = null

## Button to trigger the sequence for testing.
var test_btn: Button = null


## [method _ready] builds the interactive toolbar and tree UI.
func _ready() -> void:
	print("EventSequencerDock: Ready initialized.")
	_build_ui()


## Constructs the container, toolbar buttons, and editable table columns.
func _build_ui() -> void:
	print("EventSequencerDock: Building UI controls.")
	var vbox: VBoxContainer = VBoxContainer.new()
	add_child(vbox)

	var toolbar: HBoxContainer = HBoxContainer.new()
	vbox.add_child(toolbar)

	header_label = Label.new()
	header_label.text = "Event Sequence: (No trigger selected)"
	toolbar.add_child(header_label)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	add_btn = Button.new()
	add_btn.text = "+ Add Step"
	add_btn.pressed.connect(_on_add_step_pressed)
	toolbar.add_child(add_btn)

	remove_btn = Button.new()
	remove_btn.text = "- Delete"
	remove_btn.pressed.connect(_on_delete_step_pressed)
	toolbar.add_child(remove_btn)

	up_btn = Button.new()
	up_btn.text = "▲ Up"
	up_btn.pressed.connect(_on_move_up_pressed)
	toolbar.add_child(up_btn)

	down_btn = Button.new()
	down_btn.text = "▼ Down"
	down_btn.pressed.connect(_on_move_down_pressed)
	toolbar.add_child(down_btn)

	test_btn = Button.new()
	test_btn.text = "► Test Fire"
	test_btn.pressed.connect(_on_test_fire_pressed)
	toolbar.add_child(test_btn)

	tree_view = Tree.new()
	tree_view.columns = 5
	tree_view.set_column_title(0, "#")
	tree_view.set_column_title(1, "Delay (sec)")
	tree_view.set_column_title(2, "Target NodePath")
	tree_view.set_column_title(3, "Input / Method")
	tree_view.set_column_title(4, "Parameter")
	tree_view.column_titles_visible = true
	tree_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_view.custom_minimum_size = Vector2(0, 180)
	tree_view.item_edited.connect(_on_tree_item_edited)
	vbox.add_child(tree_view)


## Updates the dock to inspect and display a given trigger node.
func inspect_trigger(trigger: EventSequenceTrigger) -> void:
	print("EventSequencerDock: Inspecting trigger -> ", trigger)
	current_trigger = trigger
	refresh_view()


## Clears and rebuilds tree rows from [member current_trigger] steps.
func refresh_view() -> void:
	print("EventSequencerDock: Refreshing table rows.")
	if not is_instance_valid(tree_view):
		return

	tree_view.clear()
	var root: TreeItem = tree_view.create_item()

	if not is_instance_valid(current_trigger) or not current_trigger.is_inside_tree():
		if is_instance_valid(header_label):
			header_label.text = "Event Sequence: (No trigger selected)"
		return

	if is_instance_valid(header_label):
		header_label.text = "Event Sequence: " + current_trigger.name

	for i: int in range(current_trigger.steps.size()):
		var step: EventStep = current_trigger.steps[i]
		if step == null:
			continue
		var item: TreeItem = tree_view.create_item(root)
		item.set_metadata(0, i)
		item.set_text(0, str(i + 1))

		item.set_text(1, str(step.delay))
		item.set_editable(1, true)

		item.set_text(2, str(step.target_path))
		item.set_editable(2, true)

		item.set_text(3, String(step.method_name))
		item.set_editable(3, true)

		item.set_text(4, step.parameter)
		item.set_editable(4, true)


## Handles modifications made inside the tree column text cells.
func _on_tree_item_edited() -> void:
	if not is_instance_valid(current_trigger):
		return

	var item: TreeItem = tree_view.get_edited()
	var col: int = tree_view.get_edited_column()
	var idx: int = item.get_metadata(0)

	if idx < 0 or idx >= current_trigger.steps.size():
		return

	var step: EventStep = current_trigger.steps[idx]
	print("EventSequencerDock: Editing step ", idx, " col ", col)

	match col:
		1:
			step.delay = item.get_text(1).to_float()
		2:
			step.target_path = NodePath(item.get_text(2))
		3:
			step.method_name = StringName(item.get_text(3))
		4:
			step.parameter = item.get_text(4)

	EditorInterface.mark_scene_as_unsaved()


## Appends a new blank [EventStep] to the inspected trigger sequence.
func _on_add_step_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return

	print("EventSequencerDock: Adding new step to trigger.")
	var step: EventStep = EventStep.new()
	step.target_path = NodePath("..")
	step.method_name = &""
	step.delay = 0.0
	current_trigger.steps.append(step)

	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Removes the currently selected row from the trigger sequence.
func _on_delete_step_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return

	var selected: TreeItem = tree_view.get_selected()
	if selected == null:
		return

	var idx: int = selected.get_metadata(0)
	print("EventSequencerDock: Deleting step at index: ", idx)
	current_trigger.steps.remove_at(idx)

	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Shifts the selected event step upward in execution order.
func _on_move_up_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return

	var selected: TreeItem = tree_view.get_selected()
	if selected == null:
		return

	var idx: int = selected.get_metadata(0)
	if idx > 0:
		print("EventSequencerDock: Moving step ", idx, " up.")
		var item: EventStep = current_trigger.steps.pop_at(idx)
		current_trigger.steps.insert(idx - 1, item)
		EditorInterface.mark_scene_as_unsaved()
		refresh_view()


## Shifts the selected event step downward in execution order.
func _on_move_down_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return

	var selected: TreeItem = tree_view.get_selected()
	if selected == null:
		return

	var idx: int = selected.get_metadata(0)
	if idx < current_trigger.steps.size() - 1:
		print("EventSequencerDock: Moving step ", idx, " down.")
		var item: EventStep = current_trigger.steps.pop_at(idx)
		current_trigger.steps.insert(idx + 1, item)
		EditorInterface.mark_scene_as_unsaved()
		refresh_view()


## Executes sequence directly from editor for testing triggers.
func _on_test_fire_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return

	print("EventSequencerDock: Test firing trigger: ", current_trigger.name)
	current_trigger.trigger_sequence()
