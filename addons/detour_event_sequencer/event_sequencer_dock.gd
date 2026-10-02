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

## Confirmation dialog hosting scene tree node picker.
var node_picker_dialog: ConfirmationDialog = null

## Tree widget inside node picker dialog.
var node_picker_tree: Tree = null

## Currently selected step index for node picking or method assignment.
var active_editing_idx: int = -1

## Step detail drawer container underneath table.
var detail_box: VBoxContainer = null

## Dropdown selecting step execution type.
var type_opt: OptionButton = null

## Button opening target node picker.
var target_btn: Button = null

## Dropdown listing valid candidate methods, signals, or properties.
var action_opt: OptionButton = null

## Input field specifying custom parameter string.
var param_edit: LineEdit = null

## SpinBox defining delay in seconds.
var delay_spin: SpinBox = null

## Container holding logic branch conditions.
var branch_box: HBoxContainer = null

## Dropdown selecting comparison operator for branch.
var op_opt: OptionButton = null

## Input field defining expected comparison value.
var cond_val_edit: LineEdit = null

## SpinBox selecting step index to jump to on condition pass.
var jump_spin: SpinBox = null

## Checkbox indicating if step executes only once.
var fire_once_check: CheckBox = null


## Initializes UI controls, picker dialogs, and event listeners.
func _ready() -> void:
	print("EventSequencerDock: Initializing UI dock.")
	_build_ui()
	_build_picker_dialog()


## Constructs container, toolbar buttons, table, and detail editor drawer.
func _build_ui() -> void:
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
	add_btn.pressed.connect(_on_add_sequence_pressed)
	toolbar.add_child(add_btn)

	remove_btn = Button.new()
	remove_btn.text = "- Delete"
	remove_btn.pressed.connect(_on_delete_step_pressed)
	toolbar.add_child(remove_btn)

	tree_view = Tree.new()
	tree_view.columns = 6
	tree_view.set_column_title(0, "#")
	tree_view.set_column_title(1, "Type")
	tree_view.set_column_title(2, "Target")
	tree_view.set_column_title(3, "Action (Method/Signal/Prop)")
	tree_view.set_column_title(4, "Parameter")
	tree_view.set_column_title(5, "Delay (s)")
	tree_view.column_titles_visible = true
	tree_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_view.custom_minimum_size = Vector2(0, 140)
	tree_view.item_selected.connect(_on_step_row_selected)
	vbox.add_child(tree_view)

	_build_detail_editor(vbox)


## Builds Source-like property panel underneath table.
func _build_detail_editor(parent: VBoxContainer) -> void:
	var sep: HSeparator = HSeparator.new()
	parent.add_child(sep)

	detail_box = VBoxContainer.new()
	parent.add_child(detail_box)

	var row1: HBoxContainer = HBoxContainer.new()
	detail_box.add_child(row1)

	row1.add_child(Label.new())
	(row1.get_child(0) as Label).text = "Step Type:"

	type_opt = OptionButton.new()
	type_opt.add_item("CALL (Method)", int(EventStep.StepType.CALL_METHOD))
	type_opt.add_item("WAIT SIGNAL", int(EventStep.StepType.WAIT_SIGNAL))
	type_opt.add_item("LOGIC BRANCH", int(EventStep.StepType.LOGIC_BRANCH))
	type_opt.item_selected.connect(_on_type_opt_selected)
	row1.add_child(type_opt)

	row1.add_child(Label.new())
	(row1.get_child(2) as Label).text = "Target:"

	target_btn = Button.new()
	target_btn.text = "[ Choose Target Entity... ]"
	target_btn.pressed.connect(_open_node_picker)
	row1.add_child(target_btn)

	var row2: HBoxContainer = HBoxContainer.new()
	detail_box.add_child(row2)

	row2.add_child(Label.new())
	(row2.get_child(0) as Label).text = "Action / Input:"

	action_opt = OptionButton.new()
	action_opt.custom_minimum_size = Vector2(240, 0)
	action_opt.item_selected.connect(_on_action_opt_selected)
	row2.add_child(action_opt)

	row2.add_child(Label.new())
	(row2.get_child(2) as Label).text = "Parameter:"

	param_edit = LineEdit.new()
	param_edit.custom_minimum_size = Vector2(160, 0)
	param_edit.text_changed.connect(_on_param_changed)
	row2.add_child(param_edit)

	row2.add_child(Label.new())
	(row2.get_child(4) as Label).text = "Delay (s):"

	delay_spin = SpinBox.new()
	delay_spin.min_value = 0.0
	delay_spin.max_value = 999.0
	delay_spin.step = 0.1
	delay_spin.value_changed.connect(_on_delay_changed)
	row2.add_child(delay_spin)

	branch_box = HBoxContainer.new()
	detail_box.add_child(branch_box)

	branch_box.add_child(Label.new())
	(branch_box.get_child(0) as Label).text = "Condition:"

	op_opt = OptionButton.new()
	op_opt.add_item("Equal (==)", int(EventStep.ConditionOp.EQUAL))
	op_opt.add_item("Not Equal (!=)", int(EventStep.ConditionOp.NOT_EQUAL))
	op_opt.add_item("Greater (>)", int(EventStep.ConditionOp.GREATER))
	op_opt.add_item("Less (<)", int(EventStep.ConditionOp.LESS))
	op_opt.item_selected.connect(_on_op_selected)
	branch_box.add_child(op_opt)

	cond_val_edit = LineEdit.new()
	cond_val_edit.placeholder_text = "Value (e.g. true)"
	cond_val_edit.text_changed.connect(_on_cond_val_changed)
	branch_box.add_child(cond_val_edit)

	branch_box.add_child(Label.new())
	(branch_box.get_child(3) as Label).text = "Jump to Step #:"

	jump_spin = SpinBox.new()
	jump_spin.min_value = 1.0
	jump_spin.max_value = 64.0
	jump_spin.step = 1.0
	jump_spin.value_changed.connect(_on_jump_changed)
	branch_box.add_child(jump_spin)

	fire_once_check = CheckBox.new()
	fire_once_check.text = "Fire Once Only"
	fire_once_check.toggled.connect(_on_fire_once_toggled)
	row2.add_child(fire_once_check)


## Constructs node picker dialog for selecting scene entities.
func _build_picker_dialog() -> void:
	node_picker_dialog = ConfirmationDialog.new()
	node_picker_dialog.title = "Select Target Entity"
	node_picker_dialog.confirmed.connect(_on_node_picker_confirmed)

	node_picker_tree = Tree.new()
	node_picker_tree.custom_minimum_size = Vector2(350, 400)
	node_picker_dialog.add_child(node_picker_tree)
	add_child(node_picker_dialog)


## Updates dock to inspect and display a given trigger node.
func inspect_trigger(trigger: EventSequenceTrigger) -> void:
	print("EventSequencerDock: Inspecting trigger -> ", trigger)
	current_trigger = trigger
	active_editing_idx = -1
	refresh_view()


## Clears and rebuilds tree rows from [member current_trigger] steps.
func refresh_view() -> void:
	if not is_instance_valid(tree_view):
		return

	tree_view.clear()
	var root: TreeItem = tree_view.create_item()

	if not is_instance_valid(current_trigger) or not current_trigger.is_inside_tree():
		if is_instance_valid(header_label):
			header_label.text = "Event Sequence: (No trigger selected)"
		detail_box.visible = false
		return

	header_label.text = "Event Sequence: " + current_trigger.name
	detail_box.visible = true

	for i: int in range(current_trigger.steps.size()):
		var step: EventStep = current_trigger.steps[i]
		if step == null:
			continue
		var item: TreeItem = tree_view.create_item(root)
		item.set_metadata(0, i)
		item.set_text(0, str(i + 1))

		var type_label: String = "CALL"
		if step.step_type == EventStep.StepType.WAIT_SIGNAL:
			type_label = "WAIT SIGNAL"
		elif step.step_type == EventStep.StepType.LOGIC_BRANCH:
			type_label = "BRANCH"
		item.set_text(1, type_label)

		item.set_text(2, str(step.target_path))
		var action_text: String = String(step.method_name)
		if step.step_type == EventStep.StepType.WAIT_SIGNAL:
			action_text = (
				String(step.signal_name) if not step.signal_name.is_empty()
				else String(step.method_name)
			)
		elif step.step_type == EventStep.StepType.LOGIC_BRANCH:
			action_text = String(step.condition_property)
		item.set_text(3, action_text)

		item.set_text(4, step.parameter)
		item.set_text(5, str(step.delay))

	if active_editing_idx >= 0 and active_editing_idx < current_trigger.steps.size():
		_load_step_into_editor(active_editing_idx)
	elif current_trigger.steps.size() > 0:
		active_editing_idx = 0
		_load_step_into_editor(0)
	else:
		detail_box.visible = false


## Loads selected step properties into bottom property editor.
func _on_step_row_selected() -> void:
	var item: TreeItem = tree_view.get_selected()
	if item == null:
		return
	var idx: int = item.get_metadata(0)
	active_editing_idx = idx
	_load_step_into_editor(idx)


## Fills property panel widgets with data from chosen step index.
func _load_step_into_editor(idx: int) -> void:
	if not is_instance_valid(current_trigger) or idx >= current_trigger.steps.size():
		return

	detail_box.visible = true
	var step: EventStep = current_trigger.steps[idx]
	type_opt.selected = int(step.step_type)
	target_btn.text = str(step.target_path) if not step.target_path.is_empty() else "[ Choose Target... ]"
	param_edit.text = step.parameter
	delay_spin.value = step.delay
	fire_once_check.button_pressed = step.fire_once

	branch_box.visible = (step.step_type == EventStep.StepType.LOGIC_BRANCH)
	op_opt.selected = int(step.condition_operator)
	cond_val_edit.text = step.condition_value
	jump_spin.value = float(step.branch_jump_step + 1)

	_populate_actions_dropdown(step)


## Inspects target entity to fill available candidate methods or signals.
func _populate_actions_dropdown(step: EventStep) -> void:
	action_opt.clear()
	var target: Node = current_trigger.get_node_or_null(step.target_path)
	if not is_instance_valid(target):
		action_opt.add_item("(Select valid target)")
		return

	var current_selection: String = ""
	var id: int = 0

	match step.step_type:
		EventStep.StepType.CALL_METHOD:
			current_selection = String(step.method_name)
			var methods: Array[Dictionary] = target.get_method_list()
			for m: Dictionary in methods:
				var m_name: String = m.get("name", "")
				if not m_name.begins_with("@") and not m_name.begins_with("_"):
					action_opt.add_item("Method: " + m_name, id)
					action_opt.set_item_metadata(id, m_name)
					id += 1

		EventStep.StepType.WAIT_SIGNAL:
			current_selection = (
				String(step.signal_name) if not step.signal_name.is_empty()
				else String(step.method_name)
			)
			var sigs: Array[Dictionary] = target.get_signal_list()
			for s: Dictionary in sigs:
				var s_name: String = s.get("name", "")
				if not s_name.begins_with("@"):
					action_opt.add_item("Signal: " + s_name, id)
					action_opt.set_item_metadata(id, s_name)
					id += 1

		EventStep.StepType.LOGIC_BRANCH:
			current_selection = String(step.condition_property)
			var props: Array[Dictionary] = target.get_property_list()
			for p: Dictionary in props:
				var p_name: String = p.get("name", "")
				var usage: int = p.get("usage", 0)
				if usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					action_opt.add_item("Property: " + p_name, id)
					action_opt.set_item_metadata(id, p_name)
					id += 1

	for i: int in range(action_opt.item_count):
		if String(action_opt.get_item_metadata(i)) == current_selection:
			action_opt.selected = i
			return

	if not current_selection.is_empty():
		action_opt.add_item("Custom: " + current_selection, id)
		action_opt.set_item_metadata(id, current_selection)
		action_opt.selected = id


## Populates and displays scene tree node selection dialog.
func _open_node_picker() -> void:
	print("EventSequencerDock: Opening scene node picker.")
	node_picker_tree.clear()
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(scene_root):
		return
	var tree_root: TreeItem = node_picker_tree.create_item()
	_populate_node_tree(scene_root, tree_root)
	node_picker_dialog.popup_centered(Vector2i(450, 500))


## Recursively adds scene hierarchy nodes into picker tree widget.
func _populate_node_tree(node: Node, parent_item: TreeItem) -> void:
	var item: TreeItem = node_picker_tree.create_item(parent_item)
	item.set_text(0, node.name)
	item.set_metadata(0, node)
	for child: Node in node.get_children():
		_populate_node_tree(child, item)


## Assigns chosen target node relative path to active event step.
func _on_node_picker_confirmed() -> void:
	var selected_item: TreeItem = node_picker_tree.get_selected()
	if selected_item == null or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return

	var picked_node: Node = selected_item.get_metadata(0) as Node
	if not is_instance_valid(picked_node):
		return

	var step: EventStep = current_trigger.steps[active_editing_idx]
	step.target_path = current_trigger.get_path_to(picked_node)
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Handles selection of step type from dropdown menu.
func _on_type_opt_selected(idx: int) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	var step: EventStep = current_trigger.steps[active_editing_idx]
	step.step_type = idx as EventStep.StepType
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Handles selection of method or signal from action dropdown.
func _on_action_opt_selected(idx: int) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	var chosen: StringName = StringName(action_opt.get_item_metadata(idx))
	var step: EventStep = current_trigger.steps[active_editing_idx]
	match step.step_type:
		EventStep.StepType.CALL_METHOD:
			step.method_name = chosen
		EventStep.StepType.WAIT_SIGNAL:
			step.signal_name = chosen
			step.method_name = chosen
		EventStep.StepType.LOGIC_BRANCH:
			step.condition_property = chosen
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates parameter string on active event step.
func _on_param_changed(new_text: String) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].parameter = new_text
	EditorInterface.mark_scene_as_unsaved()


## Updates delay duration on active event step.
func _on_delay_changed(value: float) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].delay = value
	EditorInterface.mark_scene_as_unsaved()


## Updates comparison operator on active logic branch step.
func _on_op_selected(idx: int) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].condition_operator = idx as EventStep.ConditionOp
	EditorInterface.mark_scene_as_unsaved()


## Updates comparison value string on active logic branch step.
func _on_cond_val_changed(new_text: String) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].condition_value = new_text
	EditorInterface.mark_scene_as_unsaved()


## Updates jump target index on active logic branch step.
func _on_jump_changed(value: float) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].branch_jump_step = int(value) - 1
	EditorInterface.mark_scene_as_unsaved()


## Updates fire-once boolean flag on active event step.
func _on_fire_once_toggled(button_pressed: bool) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].fire_once = button_pressed
	EditorInterface.mark_scene_as_unsaved()


## Appends a new blank [EventStep] to the inspected trigger sequence.
func _on_add_sequence_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return
	var step: EventStep = EventStep.new()
	step.target_path = NodePath("..")
	step.method_name = &""
	step.delay = 0.0
	current_trigger.steps.append(step)
	active_editing_idx = current_trigger.steps.size() - 1
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Removes the currently selected row from the trigger sequence.
func _on_delete_step_pressed() -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps.remove_at(active_editing_idx)
	active_editing_idx = maxi(0, active_editing_idx - 1)
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()
