## Bottom panel UI for zero-code configuration of [EventSequenceTrigger] conditions and steps.
@tool
class_name EventSequencerDock
extends PanelContainer

## Node picker destination mode.
enum PickerMode {
	STEP_TARGET,
	STEP_PARAM_NODE,
	COND_TARGET,
}

## Bitmask constant for Layer 2 (Player).
const MASK_PLAYER: int = 2
## Bitmask constant for Layer 3 (Interactive / Box).
const MASK_INTERACTIVE: int = 4
## Bitmask constant for Layer 4 (Debris).
const MASK_DEBRIS: int = 8
## Bitmask constant for Layer 5 (Enemies / NPC).
const MASK_ENEMIES: int = 16
## Combined mask for all standard activator layers.
const MASK_ALL: int = 30

## Currently inspected trigger instance.
var current_trigger: EventSequenceTrigger = null

## Currently selected condition index.
var active_cond_idx: int = -1

## Currently selected step index.
var active_editing_idx: int = -1

## Active target mode for the scene node picker dialog.
var _picker_mode: PickerMode = PickerMode.STEP_TARGET

## Guard preventing feedback loops during UI population.
var _updating_ui: bool = false

## Top bar label showing active trigger name.
var _header_label: Label = null
## Activator layer checkbox for Player (L2).
var _chk_player: CheckBox = null
## Activator layer checkbox for Interactive (L3).
var _chk_interactive: CheckBox = null
## Activator layer checkbox for Debris (L4).
var _chk_debris: CheckBox = null
## Activator layer checkbox for Enemies (L5).
var _chk_enemies: CheckBox = null
## Activator layer checkbox toggling all layers.
var _chk_any: CheckBox = null
## Checkbox toggling trigger_once on the active trigger.
var _chk_trigger_once: CheckBox = null

## Tree displaying pre-trigger [EventCondition] rows.
var _cond_tree: Tree = null
## Container holding condition editor controls.
var _cond_editor_box: HBoxContainer = null
## Dropdown selecting [enum EventCondition.CondType].
var _cond_type_opt: OptionButton = null
## Dropdown selecting required physics layer for VOLUME_HAS_LAYER.
var _cond_layer_opt: OptionButton = null
## Checkbox targeting entering body for PROPERTY_COMPARE.
var _cond_act_chk: CheckBox = null
## Button opening node picker for condition target.
var _cond_target_btn: Button = null
## Dropdown listing target properties for PROPERTY_COMPARE.
var _cond_prop_opt: OptionButton = null
## Dropdown selecting comparison operator for PROPERTY_COMPARE.
var _cond_op_opt: OptionButton = null
## Text field for expected condition comparison value.
var _cond_val_edit: LineEdit = null

## Tree displaying [EventStep] sequence rows.
var _tree_view: Tree = null
## Container holding step property editor controls.
var _detail_box: VBoxContainer = null
## Dropdown selecting [enum EventStep.ExecMode].
var _mode_opt: OptionButton = null
## Dropdown selecting [enum EventStep.StepType].
var _type_opt: OptionButton = null
## Checkbox targeting entering activator body for step execution.
var _step_act_chk: CheckBox = null
## Button opening node picker for step target.
var _target_btn: Button = null
## Checkbox toggling built-in engine methods in action dropdown.
var _engine_chk: CheckBox = null
## Checkbox toggling fire_once on step.
var _fire_once_chk: CheckBox = null
## Dropdown listing script methods or properties on step target.
var _action_opt: OptionButton = null
## Label preceding active parameter input control.
var _param_label: Label = null
## String fallback input for step parameter.
var _param_edit: LineEdit = null
## Boolean checkbox input for step parameter.
var _param_bool_chk: CheckBox = null
## Enum dropdown input for step parameter.
var _param_enum_opt: OptionButton = null
## Numeric SpinBox input for step parameter.
var _param_num_spin: SpinBox = null
## Node picker button input for Object/Node step parameter.
var _param_node_btn: Button = null
## Label preceding wait signal dropdown.
var _wait_sig_label: Label = null
## Dropdown listing signals on target when mode is WAIT_SIGNAL.
var _wait_sig_opt: OptionButton = null
## SpinBox configuring step delay in seconds.
var _delay_spin: SpinBox = null

## Modal dialog for selecting scene tree nodes.
var _node_picker_dialog: ConfirmationDialog = null
## Tree inside modal dialog displaying current edited scene hierarchy.
var _node_picker_tree: Tree = null


## Builds dock layout and disables per-frame processing.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_build_ui()
	_build_picker_dialog()


## Binds dock to [param trigger] and refreshes tables.
func inspect_trigger(trigger: EventSequenceTrigger) -> void:
	current_trigger = trigger
	active_cond_idx = 0 if (is_instance_valid(trigger) and trigger.conditions.size() > 0) else -1
	active_editing_idx = 0 if (is_instance_valid(trigger) and trigger.steps.size() > 0) else -1
	refresh_view()


## Rebuilds toolbar, conditions table, steps table, detail drawers, and 3D gizmos.
func refresh_view() -> void:
	if not is_instance_valid(_tree_view):
		return

	_updating_ui = true
	_cond_tree.clear()
	_tree_view.clear()

	if not is_instance_valid(current_trigger) or not current_trigger.is_inside_tree():
		_header_label.text = "Trigger: (None Selected)"
		_detail_box.visible = false
		_cond_editor_box.visible = false
		_updating_ui = false
		return

	_header_label.text = "Trigger: " + current_trigger.name
	var mask: int = current_trigger.activator_mask
	_chk_player.button_pressed = (mask & MASK_PLAYER) != 0
	_chk_interactive.button_pressed = (mask & MASK_INTERACTIVE) != 0
	_chk_debris.button_pressed = (mask & MASK_DEBRIS) != 0
	_chk_enemies.button_pressed = (mask & MASK_ENEMIES) != 0
	_chk_any.button_pressed = (mask & MASK_ALL) == MASK_ALL
	_chk_trigger_once.button_pressed = current_trigger.trigger_once

	_refresh_conditions_tree()
	_refresh_steps_tree()
	current_trigger.update_gizmos()
	_updating_ui = false


## Constructs root vertical layout, top toolbar, and split pane.
func _build_ui() -> void:
	var root_vbox: VBoxContainer = VBoxContainer.new()
	add_child(root_vbox)

	_build_top_toolbar(root_vbox)

	var sep: HSeparator = HSeparator.new()
	root_vbox.add_child(sep)

	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 340
	root_vbox.add_child(split)

	_build_conditions_pane(split)
	_build_steps_pane(split)


## Builds activator filter bar and trigger-once toggle.
func _build_top_toolbar(parent: VBoxContainer) -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	parent.add_child(bar)

	_header_label = Label.new()
	_header_label.text = "Trigger: (None Selected)"
	bar.add_child(_header_label)

	var sep1: VSeparator = VSeparator.new()
	bar.add_child(sep1)

	var who_lbl: Label = Label.new()
	who_lbl.text = "Who Triggers:"
	bar.add_child(who_lbl)

	_chk_player = _create_mask_check(bar, "Player (L2)", MASK_PLAYER)
	_chk_interactive = _create_mask_check(bar, "Box/Interactive (L3)", MASK_INTERACTIVE)
	_chk_debris = _create_mask_check(bar, "Debris (L4)", MASK_DEBRIS)
	_chk_enemies = _create_mask_check(bar, "NPC/Enemy (L5)", MASK_ENEMIES)

	_chk_any = CheckBox.new()
	_chk_any.text = "Any"
	_chk_any.toggled.connect(_on_any_mask_toggled)
	bar.add_child(_chk_any)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_chk_trigger_once = CheckBox.new()
	_chk_trigger_once.text = "Trigger Once"
	_chk_trigger_once.toggled.connect(_on_trigger_once_toggled)
	bar.add_child(_chk_trigger_once)


## Helper creating an activator layer bitmask checkbox.
func _create_mask_check(parent: HBoxContainer, label_text: String, bit: int) -> CheckBox:
	var chk: CheckBox = CheckBox.new()
	chk.text = label_text
	chk.toggled.connect(_on_layer_mask_toggled.bind(bit))
	parent.add_child(chk)
	return chk


## Builds left pane hosting gate conditions table and inline editor.
func _build_conditions_pane(parent: HSplitContainer) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(300, 0)
	parent.add_child(box)

	var bar: HBoxContainer = HBoxContainer.new()
	box.add_child(bar)

	var title: Label = Label.new()
	title.text = "Conditions (All Must Pass)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	var add_c: Button = Button.new()
	add_c.text = "+ Cond"
	add_c.pressed.connect(_on_add_condition_pressed)
	bar.add_child(add_c)

	var del_c: Button = Button.new()
	del_c.text = "- Del"
	del_c.pressed.connect(_on_del_condition_pressed)
	bar.add_child(del_c)

	_cond_tree = Tree.new()
	_cond_tree.columns = 3
	_cond_tree.set_column_title(0, "#")
	_cond_tree.set_column_title(1, "Check")
	_cond_tree.set_column_title(2, "Rule")
	_cond_tree.set_column_expand(0, false)
	_cond_tree.set_column_custom_minimum_width(0, 28)
	_cond_tree.column_titles_visible = true
	_cond_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cond_tree.custom_minimum_size = Vector2(0, 110)
	_cond_tree.item_selected.connect(_on_cond_row_selected)
	box.add_child(_cond_tree)

	_cond_editor_box = HBoxContainer.new()
	box.add_child(_cond_editor_box)

	_cond_type_opt = OptionButton.new()
	_cond_type_opt.add_item("Has Layer", int(EventCondition.CondType.VOLUME_HAS_LAYER))
	_cond_type_opt.add_item("Has Node", int(EventCondition.CondType.VOLUME_HAS_NODE))
	_cond_type_opt.add_item("Property", int(EventCondition.CondType.PROPERTY_COMPARE))
	_cond_type_opt.item_selected.connect(_on_cond_type_selected)
	_cond_editor_box.add_child(_cond_type_opt)

	_cond_layer_opt = OptionButton.new()
	_cond_layer_opt.add_item("L3: Box/Interactive", MASK_INTERACTIVE)
	_cond_layer_opt.add_item("L2: Player", MASK_PLAYER)
	_cond_layer_opt.add_item("L4: Debris", MASK_DEBRIS)
	_cond_layer_opt.add_item("L5: NPC/Enemy", MASK_ENEMIES)
	_cond_layer_opt.item_selected.connect(_on_cond_layer_selected)
	_cond_editor_box.add_child(_cond_layer_opt)

	_cond_act_chk = CheckBox.new()
	_cond_act_chk.text = "Activator"
	_cond_act_chk.toggled.connect(_on_cond_activator_toggled)
	_cond_editor_box.add_child(_cond_act_chk)

	_cond_target_btn = Button.new()
	_cond_target_btn.text = "[Pick Node]"
	_cond_target_btn.pressed.connect(_open_node_picker.bind(PickerMode.COND_TARGET))
	_cond_editor_box.add_child(_cond_target_btn)

	_cond_prop_opt = OptionButton.new()
	_cond_prop_opt.item_selected.connect(_on_cond_prop_selected)
	_cond_editor_box.add_child(_cond_prop_opt)

	_cond_op_opt = OptionButton.new()
	_cond_op_opt.add_item("==", int(EventCondition.CompareOp.EQUAL))
	_cond_op_opt.add_item("!=", int(EventCondition.CompareOp.NOT_EQUAL))
	_cond_op_opt.add_item(">", int(EventCondition.CompareOp.GREATER))
	_cond_op_opt.add_item("<", int(EventCondition.CompareOp.LESS))
	_cond_op_opt.item_selected.connect(_on_cond_op_selected)
	_cond_editor_box.add_child(_cond_op_opt)

	_cond_val_edit = LineEdit.new()
	_cond_val_edit.custom_minimum_size = Vector2(60, 0)
	_cond_val_edit.text_changed.connect(_on_cond_val_changed)
	_cond_editor_box.add_child(_cond_val_edit)


## Builds right pane hosting action steps table, reorder buttons, and detail drawer.
func _build_steps_pane(parent: HSplitContainer) -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var bar: HBoxContainer = HBoxContainer.new()
	box.add_child(bar)

	var title: Label = Label.new()
	title.text = "Action Steps (Executed When Conditions Pass)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)

	var up_btn: Button = Button.new()
	up_btn.text = "▲ Up"
	up_btn.pressed.connect(_on_move_step_pressed.bind(-1))
	bar.add_child(up_btn)

	var dn_btn: Button = Button.new()
	dn_btn.text = "▼ Down"
	dn_btn.pressed.connect(_on_move_step_pressed.bind(1))
	bar.add_child(dn_btn)

	var add_btn: Button = Button.new()
	add_btn.text = "+ Add Step"
	add_btn.pressed.connect(_on_add_sequence_pressed)
	bar.add_child(add_btn)

	var del_btn: Button = Button.new()
	del_btn.text = "- Delete"
	del_btn.pressed.connect(_on_delete_step_pressed)
	bar.add_child(del_btn)

	_tree_view = Tree.new()
	_tree_view.columns = 6
	_tree_view.set_column_title(0, "#")
	_tree_view.set_column_title(1, "Flow")
	_tree_view.set_column_title(2, "Type")
	_tree_view.set_column_title(3, "Target")
	_tree_view.set_column_title(4, "Action / Value")
	_tree_view.set_column_title(5, "Delay (s)")
	_tree_view.set_column_expand(0, false)
	_tree_view.set_column_custom_minimum_width(0, 28)
	_tree_view.column_titles_visible = true
	_tree_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree_view.custom_minimum_size = Vector2(0, 110)
	_tree_view.item_selected.connect(_on_step_row_selected)
	box.add_child(_tree_view)

	_build_step_detail_editor(box)


## Builds bottom step editor with auto-swapping typed parameter widgets.
func _build_step_detail_editor(parent: VBoxContainer) -> void:
	_detail_box = VBoxContainer.new()
	parent.add_child(_detail_box)

	var row1: HBoxContainer = HBoxContainer.new()
	_detail_box.add_child(row1)

	_add_label(row1, "Flow:")
	_mode_opt = OptionButton.new()
	_mode_opt.add_item("Sequential", int(EventStep.ExecMode.SEQUENTIAL))
	_mode_opt.add_item("Parallel (No Wait)", int(EventStep.ExecMode.PARALLEL))
	_mode_opt.add_item("Wait Signal", int(EventStep.ExecMode.WAIT_SIGNAL))
	_mode_opt.item_selected.connect(_on_mode_opt_selected)
	row1.add_child(_mode_opt)

	_add_label(row1, "Type:")
	_type_opt = OptionButton.new()
	_type_opt.add_item("Call Method", int(EventStep.StepType.CALL_METHOD))
	_type_opt.add_item("Set Property", int(EventStep.StepType.SET_PROPERTY))
	_type_opt.item_selected.connect(_on_type_opt_selected)
	row1.add_child(_type_opt)

	_step_act_chk = CheckBox.new()
	_step_act_chk.text = "Target Activator"
	_step_act_chk.toggled.connect(_on_step_activator_toggled)
	row1.add_child(_step_act_chk)

	_target_btn = Button.new()
	_target_btn.text = "[Pick Target...]"
	_target_btn.pressed.connect(_open_node_picker.bind(PickerMode.STEP_TARGET))
	row1.add_child(_target_btn)

	_engine_chk = CheckBox.new()
	_engine_chk.text = "Engine Methods"
	_engine_chk.toggled.connect(_on_engine_methods_toggled)
	row1.add_child(_engine_chk)

	_fire_once_chk = CheckBox.new()
	_fire_once_chk.text = "Fire Once"
	_fire_once_chk.toggled.connect(_on_fire_once_toggled)
	row1.add_child(_fire_once_chk)

	var row2: HBoxContainer = HBoxContainer.new()
	_detail_box.add_child(row2)

	_add_label(row2, "Action:")
	_action_opt = OptionButton.new()
	_action_opt.custom_minimum_size = Vector2(210, 0)
	_action_opt.item_selected.connect(_on_action_opt_selected)
	row2.add_child(_action_opt)

	_param_label = _add_label(row2, "Value:")

	_param_edit = LineEdit.new()
	_param_edit.custom_minimum_size = Vector2(130, 0)
	_param_edit.text_changed.connect(_on_param_string_changed)
	row2.add_child(_param_edit)

	_param_bool_chk = CheckBox.new()
	_param_bool_chk.text = "Enabled"
	_param_bool_chk.toggled.connect(_on_param_bool_toggled)
	row2.add_child(_param_bool_chk)

	_param_enum_opt = OptionButton.new()
	_param_enum_opt.item_selected.connect(_on_param_enum_selected)
	row2.add_child(_param_enum_opt)

	_param_num_spin = SpinBox.new()
	_param_num_spin.min_value = -99999.0
	_param_num_spin.max_value = 99999.0
	_param_num_spin.step = 0.1
	_param_num_spin.value_changed.connect(_on_param_num_changed)
	row2.add_child(_param_num_spin)

	_param_node_btn = Button.new()
	_param_node_btn.text = "[Pick Node...]"
	_param_node_btn.pressed.connect(_open_node_picker.bind(PickerMode.STEP_PARAM_NODE))
	row2.add_child(_param_node_btn)

	_wait_sig_label = _add_label(row2, "Await Signal:")
	_wait_sig_opt = OptionButton.new()
	_wait_sig_opt.item_selected.connect(_on_wait_sig_selected)
	row2.add_child(_wait_sig_opt)

	_add_label(row2, "Delay (s):")
	_delay_spin = SpinBox.new()
	_delay_spin.min_value = 0.0
	_delay_spin.max_value = 999.0
	_delay_spin.step = 0.1
	_delay_spin.value_changed.connect(_on_delay_changed)
	row2.add_child(_delay_spin)


## Helper adding a [Label] to [param parent] and returning it.
func _add_label(parent: Container, text_val: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text_val
	parent.add_child(lbl)
	return lbl


## Builds reusable scene hierarchy node picker modal dialog.
func _build_picker_dialog() -> void:
	_node_picker_dialog = ConfirmationDialog.new()
	_node_picker_dialog.title = "Select Scene Node"
	_node_picker_dialog.confirmed.connect(_on_node_picker_confirmed)

	_node_picker_tree = Tree.new()
	_node_picker_tree.custom_minimum_size = Vector2(360, 420)
	_node_picker_dialog.add_child(_node_picker_tree)
	add_child(_node_picker_dialog)


## Populates conditions tree and loads active condition into inline editor.
func _refresh_conditions_tree() -> void:
	var root: TreeItem = _cond_tree.create_item()
	for i: int in range(current_trigger.conditions.size()):
		var cond: EventCondition = current_trigger.conditions[i]
		if cond == null:
			continue
		var item: TreeItem = _cond_tree.create_item(root)
		item.set_metadata(0, i)
		item.set_text(0, str(i + 1))

		match cond.cond_type:
			EventCondition.CondType.VOLUME_HAS_LAYER:
				item.set_text(1, "Layer Inside")
				item.set_text(2, "Mask " + str(cond.required_layer_mask))
			EventCondition.CondType.VOLUME_HAS_NODE:
				item.set_text(1, "Node Inside")
				item.set_text(2, str(cond.target_path))
			EventCondition.CondType.PROPERTY_COMPARE:
				item.set_text(1, "Property")
				var tgt: String = "[Activator]" if cond.target_is_activator else str(cond.target_path)
				item.set_text(2, tgt + "." + String(cond.property_name) + " ? " + cond.compare_value)

	if active_cond_idx >= 0 and active_cond_idx < current_trigger.conditions.size():
		_load_condition_into_editor(active_cond_idx)
	else:
		_cond_editor_box.visible = false


## Loads condition at [param idx] into left-pane controls.
func _load_condition_into_editor(idx: int) -> void:
	var cond: EventCondition = current_trigger.conditions[idx]
	_cond_editor_box.visible = true
	_cond_type_opt.selected = int(cond.cond_type)

	var is_layer: bool = cond.cond_type == EventCondition.CondType.VOLUME_HAS_LAYER
	var is_node: bool = cond.cond_type == EventCondition.CondType.VOLUME_HAS_NODE
	var is_prop: bool = cond.cond_type == EventCondition.CondType.PROPERTY_COMPARE

	_cond_layer_opt.visible = is_layer
	_cond_act_chk.visible = is_prop
	_cond_target_btn.visible = is_node or (is_prop and not cond.target_is_activator)
	_cond_prop_opt.visible = is_prop
	_cond_op_opt.visible = is_prop
	_cond_val_edit.visible = is_prop

	if is_layer:
		var layer_idx: int = _cond_layer_opt.get_item_index(cond.required_layer_mask)
		_cond_layer_opt.selected = maxi(0, layer_idx)
	elif is_node or is_prop:
		_cond_act_chk.button_pressed = cond.target_is_activator
		_cond_target_btn.text = (
			str(cond.target_path) if not cond.target_path.is_empty() else "[Pick Node]"
		)
		_cond_op_opt.selected = int(cond.compare_op)
		_cond_val_edit.text = cond.compare_value
		if is_prop:
			_populate_cond_properties(cond)


## Populates property dropdown for condition target node.
func _populate_cond_properties(cond: EventCondition) -> void:
	_cond_prop_opt.clear()
	var target: Node = current_trigger.get_node_or_null(cond.target_path)
	if not is_instance_valid(target):
		_cond_prop_opt.add_item("(Pick Target)")
		return

	var id: int = 0
	for p: Dictionary in target.get_property_list():
		var usage: int = p.get("usage", 0)
		var p_name: String = p.get("name", "")
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and not p_name.begins_with("_"):
			_cond_prop_opt.add_item(p_name, id)
			_cond_prop_opt.set_item_metadata(id, p_name)
			if p_name == String(cond.property_name):
				_cond_prop_opt.selected = id
			id += 1


## Populates steps tree and loads active step into bottom detail drawer.
func _refresh_steps_tree() -> void:
	var root: TreeItem = _tree_view.create_item()
	for i: int in range(current_trigger.steps.size()):
		var step: EventStep = current_trigger.steps[i]
		if step == null:
			continue
		var item: TreeItem = _tree_view.create_item(root)
		item.set_metadata(0, i)
		item.set_text(0, str(i + 1))

		var flow_txt: String = "SEQ"
		if step.exec_mode == EventStep.ExecMode.PARALLEL:
			flow_txt = "PARALLEL"
		elif step.exec_mode == EventStep.ExecMode.WAIT_SIGNAL:
			flow_txt = "WAIT:" + String(step.signal_name)
		item.set_text(1, flow_txt)

		item.set_text(2, "CALL" if step.step_type == EventStep.StepType.CALL_METHOD else "SET")
		item.set_text(3, "[Activator]" if step.target_is_activator else str(step.target_path))

		var act_str: String = String(step.method_name)
		if not step.parameter.is_empty():
			act_str += "(" + step.parameter + ")"
		item.set_text(4, act_str)
		item.set_text(5, str(step.delay))

	if active_editing_idx >= 0 and active_editing_idx < current_trigger.steps.size():
		_load_step_into_editor(active_editing_idx)
	else:
		_detail_box.visible = false


## Populates bottom editor controls from step at [param idx].
func _load_step_into_editor(idx: int) -> void:
	var step: EventStep = current_trigger.steps[idx]
	_detail_box.visible = true
	_mode_opt.selected = int(step.exec_mode)
	_type_opt.selected = int(step.step_type)
	_step_act_chk.button_pressed = step.target_is_activator
	_target_btn.visible = not step.target_is_activator
	_target_btn.text = (
		str(step.target_path) if not step.target_path.is_empty() else "[Pick Target...]"
	)
	_fire_once_chk.button_pressed = step.fire_once
	_delay_spin.value = step.delay

	var wait_vis: bool = step.exec_mode == EventStep.ExecMode.WAIT_SIGNAL
	_wait_sig_label.visible = wait_vis
	_wait_sig_opt.visible = wait_vis

	_populate_step_actions_and_signals(step)


## Inspects step target script to populate methods/properties, signals, and typed parameter input.
func _populate_step_actions_and_signals(step: EventStep) -> void:
	_action_opt.clear()
	_wait_sig_opt.clear()

	var target: Node = current_trigger.get_node_or_null(step.target_path)
	if not is_instance_valid(target):
		_action_opt.add_item("(Select Target Node)")
		_configure_param_widget({})
		return

	var id: int = 0
	var selected_meta: Dictionary = {}
	var scr: Script = target.get_script() as Script

	if step.step_type == EventStep.StepType.CALL_METHOD:
		var methods: Array[Dictionary] = []
		if is_instance_valid(scr):
			methods.append_array(scr.get_script_method_list())
		if _engine_chk.button_pressed:
			methods.append_array(target.get_method_list())

		var seen: Dictionary = {}
		for m: Dictionary in methods:
			var m_name: String = m.get("name", "")
			if m_name.begins_with("_") or m_name.begins_with("@") or seen.has(m_name):
				continue
			seen[m_name] = true
			_action_opt.add_item(m_name, id)
			var args: Array = m.get("args", [])
			var first_arg: Dictionary = args[0] if args.size() > 0 else {}
			_action_opt.set_item_metadata(id, {"name": m_name, "arg": first_arg})
			if m_name == String(step.method_name):
				_action_opt.selected = id
				selected_meta = first_arg
			id += 1
	else:
		var props: Array[Dictionary] = target.get_property_list()
		for p: Dictionary in props:
			var usage: int = p.get("usage", 0)
			var p_name: String = p.get("name", "")
			var is_scr_var: bool = (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
			if (is_scr_var or _engine_chk.button_pressed) and not p_name.begins_with("_"):
				_action_opt.add_item(p_name, id)
				_action_opt.set_item_metadata(id, {"name": p_name, "arg": p})
				if p_name == String(step.method_name):
					_action_opt.selected = id
					selected_meta = p
				id += 1

	if _action_opt.item_count > 0 and step.method_name.is_empty():
		var first_meta: Dictionary = _action_opt.get_item_metadata(0)
		step.method_name = StringName(first_meta.get("name", ""))
		selected_meta = first_meta.get("arg", {})

	_configure_param_widget(selected_meta)

	var sig_id: int = 0
	for s: Dictionary in target.get_signal_list():
		var s_name: String = s.get("name", "")
		if not s_name.begins_with("@"):
			_wait_sig_opt.add_item(s_name, sig_id)
			_wait_sig_opt.set_item_metadata(sig_id, s_name)
			if s_name == String(step.signal_name):
				_wait_sig_opt.selected = sig_id
			sig_id += 1


## Swaps parameter input widget to match the selected method argument or property type.
func _configure_param_widget(arg_meta: Dictionary) -> void:
	_param_label.visible = false
	_param_edit.visible = false
	_param_bool_chk.visible = false
	_param_enum_opt.visible = false
	_param_num_spin.visible = false
	_param_node_btn.visible = false

	if arg_meta.is_empty() or active_editing_idx < 0:
		return

	var step: EventStep = current_trigger.steps[active_editing_idx]
	var v_type: int = arg_meta.get("type", TYPE_NIL)
	var hint: int = arg_meta.get("hint", PROPERTY_HINT_NONE)
	var hint_str: String = arg_meta.get("hint_string", "")

	_param_label.visible = true

	if v_type == TYPE_INT and hint == PROPERTY_HINT_ENUM and not hint_str.is_empty():
		_param_enum_opt.visible = true
		_param_enum_opt.clear()
		var parts: PackedStringArray = hint_str.split(",")
		for i: int in range(parts.size()):
			var kv: PackedStringArray = parts[i].split(":")
			var key_name: String = kv[0]
			var val_int: int = kv[1].to_int() if kv.size() > 1 else i
			_param_enum_opt.add_item(key_name, val_int)
			if step.parameter == str(val_int):
				_param_enum_opt.selected = i
		return

	match v_type:
		TYPE_BOOL:
			_param_bool_chk.visible = true
			_param_bool_chk.button_pressed = (step.parameter.to_lower() == "true")
		TYPE_INT, TYPE_FLOAT:
			_param_num_spin.visible = true
			_param_num_spin.step = 1.0 if v_type == TYPE_INT else 0.1
			_param_num_spin.value = step.parameter.to_float()
		TYPE_OBJECT:
			_param_node_btn.visible = true
			_param_node_btn.text = (
				step.parameter if not step.parameter.is_empty() else "[Pick Node...]"
			)
		_:
			_param_edit.visible = true
			_param_edit.text = step.parameter


## Opens scene tree node picker dialog for [param mode].
func _open_node_picker(mode: PickerMode) -> void:
	_picker_mode = mode
	_node_picker_tree.clear()
	var scene_root: Node = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(scene_root):
		return
	var root_item: TreeItem = _node_picker_tree.create_item()
	_populate_node_tree(scene_root, root_item)
	_node_picker_dialog.popup_centered(Vector2i(420, 480))


## Recursively populates scene tree nodes into picker dialog.
func _populate_node_tree(node: Node, parent_item: TreeItem) -> void:
	var item: TreeItem = _node_picker_tree.create_item(parent_item)
	item.set_text(0, node.name + " (" + node.get_class() + ")")
	item.set_metadata(0, node)
	for child: Node in node.get_children():
		_populate_node_tree(child, item)


## Assigns selected scene node path to active step target, parameter, or condition target.
func _on_node_picker_confirmed() -> void:
	var item: TreeItem = _node_picker_tree.get_selected()
	if item == null or not is_instance_valid(current_trigger):
		return
	var picked: Node = item.get_metadata(0) as Node
	if not is_instance_valid(picked):
		return

	var rel_path: NodePath = current_trigger.get_path_to(picked)
	match _picker_mode:
		PickerMode.STEP_TARGET:
			if active_editing_idx >= 0:
				current_trigger.steps[active_editing_idx].target_path = rel_path
		PickerMode.STEP_PARAM_NODE:
			if active_editing_idx >= 0:
				current_trigger.steps[active_editing_idx].parameter = str(rel_path)
		PickerMode.COND_TARGET:
			if active_cond_idx >= 0:
				current_trigger.conditions[active_cond_idx].target_path = rel_path

	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates activator collision mask bit when a layer checkbox is toggled.
func _on_layer_mask_toggled(pressed: bool, bit: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger):
		return
	if pressed:
		current_trigger.activator_mask |= bit
	else:
		current_trigger.activator_mask &= ~bit
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Toggles all standard activator layers on or off.
func _on_any_mask_toggled(pressed: bool) -> void:
	if _updating_ui or not is_instance_valid(current_trigger):
		return
	current_trigger.activator_mask = MASK_ALL if pressed else MASK_PLAYER
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates trigger_once property on inspected trigger.
func _on_trigger_once_toggled(pressed: bool) -> void:
	if _updating_ui or not is_instance_valid(current_trigger):
		return
	current_trigger.trigger_once = pressed
	EditorInterface.mark_scene_as_unsaved()


## Appends a new [EventCondition] to the current trigger.
func _on_add_condition_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return
	var cond: EventCondition = EventCondition.new()
	current_trigger.conditions.append(cond)
	active_cond_idx = current_trigger.conditions.size() - 1
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Removes the selected [EventCondition] from the current trigger.
func _on_del_condition_pressed() -> void:
	if not is_instance_valid(current_trigger) or active_cond_idx < 0:
		return
	current_trigger.conditions.remove_at(active_cond_idx)
	active_cond_idx = maxi(-1, active_cond_idx - 1)
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Selects a condition row for editing.
func _on_cond_row_selected() -> void:
	var item: TreeItem = _cond_tree.get_selected()
	if item == null:
		return
	active_cond_idx = item.get_metadata(0)
	_load_condition_into_editor(active_cond_idx)


## Updates condition type from dropdown.
func _on_cond_type_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_cond_idx < 0:
		return
	current_trigger.conditions[active_cond_idx].cond_type = idx as EventCondition.CondType
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates required physics layer mask on active condition.
func _on_cond_layer_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_cond_idx < 0:
		return
	var mask: int = _cond_layer_opt.get_item_id(idx)
	current_trigger.conditions[active_cond_idx].required_layer_mask = mask
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates target_is_activator flag on active condition.
func _on_cond_activator_toggled(pressed: bool) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_cond_idx < 0:
		return
	current_trigger.conditions[active_cond_idx].target_is_activator = pressed
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates property_name on active condition.
func _on_cond_prop_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_cond_idx < 0:
		return
	var prop: String = str(_cond_prop_opt.get_item_metadata(idx))
	current_trigger.conditions[active_cond_idx].property_name = StringName(prop)
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates comparison operator on active condition.
func _on_cond_op_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_cond_idx < 0:
		return
	current_trigger.conditions[active_cond_idx].compare_op = idx as EventCondition.CompareOp
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates comparison value string on active condition.
func _on_cond_val_changed(new_text: String) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_cond_idx < 0:
		return
	current_trigger.conditions[active_cond_idx].compare_value = new_text
	EditorInterface.mark_scene_as_unsaved()


## Moves selected step up or down in execution order.
func _on_move_step_pressed(dir: int) -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	var new_idx: int = active_editing_idx + dir
	if new_idx < 0 or new_idx >= current_trigger.steps.size():
		return
	var tmp: EventStep = current_trigger.steps[active_editing_idx]
	current_trigger.steps[active_editing_idx] = current_trigger.steps[new_idx]
	current_trigger.steps[new_idx] = tmp
	active_editing_idx = new_idx
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Appends a new blank [EventStep] to the current trigger.
func _on_add_sequence_pressed() -> void:
	if not is_instance_valid(current_trigger):
		return
	var step: EventStep = EventStep.new()
	current_trigger.steps.append(step)
	active_editing_idx = current_trigger.steps.size() - 1
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Deletes the currently selected [EventStep].
func _on_delete_step_pressed() -> void:
	if not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps.remove_at(active_editing_idx)
	active_editing_idx = maxi(-1, active_editing_idx - 1)
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Selects a step row in the table for editing.
func _on_step_row_selected() -> void:
	var item: TreeItem = _tree_view.get_selected()
	if item == null:
		return
	active_editing_idx = item.get_metadata(0)
	_load_step_into_editor(active_editing_idx)


## Updates execution flow mode on active step.
func _on_mode_opt_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].exec_mode = idx as EventStep.ExecMode
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates step action type (Call Method vs Set Property).
func _on_type_opt_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	var step: EventStep = current_trigger.steps[active_editing_idx]
	step.step_type = idx as EventStep.StepType
	step.method_name = &""
	step.parameter = ""
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates target_is_activator flag on active step.
func _on_step_activator_toggled(pressed: bool) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].target_is_activator = pressed
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Refreshes action dropdown when built-in engine methods toggle changes.
func _on_engine_methods_toggled(_pressed: bool) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	_load_step_into_editor(active_editing_idx)


## Updates fire_once flag on active step.
func _on_fire_once_toggled(pressed: bool) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].fire_once = pressed
	EditorInterface.mark_scene_as_unsaved()


## Updates selected method or property name and reconfigures typed parameter widget.
func _on_action_opt_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	var meta: Dictionary = _action_opt.get_item_metadata(idx)
	var step: EventStep = current_trigger.steps[active_editing_idx]
	step.method_name = StringName(meta.get("name", ""))
	step.parameter = ""
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates string parameter on active step.
func _on_param_string_changed(new_text: String) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].parameter = new_text
	current_trigger.update_gizmos()
	EditorInterface.mark_scene_as_unsaved()


## Updates boolean parameter on active step.
func _on_param_bool_toggled(pressed: bool) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].parameter = "true" if pressed else "false"
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates enum integer parameter on active step.
func _on_param_enum_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	var enum_val: int = _param_enum_opt.get_item_id(idx)
	current_trigger.steps[active_editing_idx].parameter = str(enum_val)
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates numeric parameter on active step.
func _on_param_num_changed(value: float) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].parameter = str(value)
	EditorInterface.mark_scene_as_unsaved()


## Updates awaited signal name on active step.
func _on_wait_sig_selected(idx: int) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	var sig_name: String = str(_wait_sig_opt.get_item_metadata(idx))
	current_trigger.steps[active_editing_idx].signal_name = StringName(sig_name)
	EditorInterface.mark_scene_as_unsaved()
	refresh_view()


## Updates delay duration on active step.
func _on_delay_changed(value: float) -> void:
	if _updating_ui or not is_instance_valid(current_trigger) or active_editing_idx < 0:
		return
	current_trigger.steps[active_editing_idx].delay = value
	EditorInterface.mark_scene_as_unsaved()
