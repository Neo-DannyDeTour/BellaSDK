## Dedicated settings search coordinator.
## Scans panel structures, generates live synced mirrors for search matches,
## and routes navigation callbacks to the active menu container.
class_name SettingsSearch
extends HBoxContainer

## Emitted when the player selects an indexed search entry.
## Passes the target category tab index and the [Control] node to focus.
signal setting_navigated(tab_index: int, target: Control)

## Maximum column step inspected when pairing labels to interactive inputs.
const MAX_SEARCH_INSPECT_STEP: int = 6

## Default fallback width assigned to the popup results panel.
const DEFAULT_RESULTS_WIDTH: float = 620.0

## Vertical separation offset between search bar and dropdown results.
const DROPDOWN_OFFSET_Y: float = 6.0

## Padding offset used when clamping dropdown bounds inside the viewport.
const DROPDOWN_VIEWPORT_PADDING: float = 16.0

## Target input field where player queries are entered.
@onready var search_bar: LineEdit = %SettingsSearchEdit

## Detached popup window holding dynamically generated query matches.
@onready var search_results_panel: Control = %SearchResultsPanel

## Scroll container hosting search result rows.
@onready var search_scroll: ScrollContainer = %SearchResultsPanel/ScrollContainer

## Vertical stack where matching rows are populated.
@onready var search_results_list: VBoxContainer = %SearchResultsList

## Cached list of indexed settings metadata entries.
var _search_index: Array[Dictionary] = []


## Lifecycle method configuring dropdown positioning and input bindings.
func _ready() -> void:
	print("UI: SettingsSearch component initialized.")
	_configure_search_nodes()


## Evaluates clicks outside dropdown boundaries to collapse popup window.
## [param event] Input event captured by the viewport.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.is_pressed()):
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	var mouse_pos: Vector2 = mouse_event.global_position

	if is_instance_valid(search_bar):
		if search_bar.get_global_rect().has_point(mouse_pos):
			if not search_bar.text.strip_edges().is_empty():
				_on_search_text_changed(search_bar.text)
			return

	if is_instance_valid(search_results_panel) and search_results_panel.visible:
		if not search_results_panel.get_global_rect().has_point(mouse_pos):
			print("UI: Mouse clicked outside search results panel. Dismissing.")
			hide_search_results()


## Configures anchors, flags, and event bindings for search UI widgets.
func _configure_search_nodes() -> void:
	if not is_instance_valid(search_bar):
		return

	print("UI: Configuring search bar listeners and panel anchors.")
	search_bar.placeholder_text = "Search settings..."
	search_bar.text_changed.connect(_on_search_text_changed)
	search_bar.focus_entered.connect(_on_search_bar_focused)

	if is_instance_valid(search_results_panel):
		search_results_panel.top_level = true
		search_results_panel.visible = false
		search_results_panel.z_index = 100
		search_results_panel.custom_minimum_size.x = DEFAULT_RESULTS_WIDTH

	if is_instance_valid(search_scroll):
		search_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		search_scroll.horizontal_scroll_mode = (ScrollContainer.SCROLL_MODE_DISABLED)


## Closes the floating search popup and clears any pending query text.
func hide_search_results() -> void:
	print("UI: Dismissing settings search dropdown.")
	_clear_result_rows()
	if is_instance_valid(search_results_panel):
		search_results_panel.visible = false
	if is_instance_valid(search_bar):
		search_bar.text = ""


## Parses registered panel trees to populate the cached search catalog.
## [param option_panels] Array of option panels to parse.
## [param tab_buttons] Array of buttons providing category names.
func build_index(option_panels: Array[Control], tab_buttons: Array[Button]) -> void:
	print("UI: SettingsSearch -> Rebuilding index catalog.")
	_search_index.clear()

	for tab_idx: int in range(option_panels.size()):
		var panel: Control = option_panels[tab_idx]
		if not is_instance_valid(panel):
			continue

		var tab_name: String = ""
		if tab_idx < tab_buttons.size() and is_instance_valid(tab_buttons[tab_idx]):
			tab_name = tab_buttons[tab_idx].text.strip_edges()
		if tab_name.is_empty():
			tab_name = panel.name.replace("Panel", "").replace("Options", "")

		_scan_node_recursively(panel, tab_idx, tab_name)

	print("UI: SettingsSearch -> Indexed ", _search_index.size(), " entries.")


## Scans container nodes to extract interactive controls and paired labels.
## [param root_node] Root container node to parse.
## [param tab_idx] Tab category index.
## [param tab_name] Tab category string name.
func _scan_node_recursively(root_node: Node, tab_idx: int, tab_name: String) -> void:
	if not is_instance_valid(root_node):
		return

	if root_node is Label:
		var label: Label = root_node as Label
		var label_text: String = label.text.strip_edges()
		var is_header: bool = (
			label.name == "HeaderLabel"
			or label.name.begins_with("SectionHeader")
			or label.theme_type_variation == "HeaderMedium"
		)
		if not label_text.is_empty() and not is_header:
			var parent: Node = label.get_parent()
			if parent:
				_inspect_row_siblings(parent, label, tab_idx, tab_name)

	for child: Node in root_node.get_children():
		if child != search_results_panel and child.name != "HeaderLabel":
			_scan_node_recursively(child, tab_idx, tab_name)


## Identifies control inputs grouped together beside a [Label].
## [param parent] Common parent node holding the row.
## [param label_node] Reference row title label.
## [param tab_idx] Target tab index.
## [param tab_name] Target tab name.
func _inspect_row_siblings(parent: Node, label_node: Label, tab_idx: int, tab_name: String) -> void:
	var label_idx: int = label_node.get_index(true)
	if label_idx < 0:
		return

	var child_count: int = parent.get_child_count(true)
	var max_step: int = MAX_SEARCH_INSPECT_STEP
	if parent is GridContainer:
		var grid: GridContainer = parent as GridContainer
		max_step = max(grid.columns, 4)

	var found_slider: HSlider = null
	var found_readout_lbl: Label = null
	var found_line_edit: LineEdit = null
	var found_primary_btn: Button = null
	var found_secondary_btn: Button = null
	var found_clear_btn: Button = null
	var generic_interactive: Control = null

	for step: int in range(1, max_step + 1):
		var target_idx: int = label_idx + step
		if target_idx >= child_count:
			break
		var sibling: Node = parent.get_child(target_idx, true)
		if not is_instance_valid(sibling):
			continue

		if sibling is HSeparator or sibling is VSeparator:
			continue

		if sibling is Button and (sibling as Button).has_meta("action"):
			var action_btn: Button = sibling as Button
			var slot: int = action_btn.get_meta("slot", 0) as int
			if slot == 0:
				found_primary_btn = action_btn
			elif slot == 1:
				found_secondary_btn = action_btn
			continue

		if found_primary_btn != null and sibling is Button:
			if (sibling as Button).text == "✕":
				found_clear_btn = sibling as Button
				continue

		if sibling is LineEdit:
			found_line_edit = sibling as LineEdit
			continue

		if sibling is HSlider:
			found_slider = sibling as HSlider
			continue

		if sibling is Label:
			var test_lbl: Label = sibling as Label
			var txt: String = test_lbl.text.strip_edges()
			var is_numeric: bool = (
				txt.is_valid_float()
				or txt.is_valid_int()
				or txt.ends_with("%")
				or txt.ends_with("px")
				or txt.length() <= 8
			)
			if is_numeric:
				found_readout_lbl = test_lbl
				continue
			else:
				break

		if _is_interactive(sibling) and generic_interactive == null:
			generic_interactive = sibling as Control

	_register_inspected_row(
		label_node.text.strip_edges().replace(":", ""),
		tab_idx,
		tab_name,
		found_primary_btn,
		found_secondary_btn,
		found_clear_btn,
		found_slider,
		found_readout_lbl,
		found_line_edit,
		generic_interactive
	)


## Stores an inspected control item dictionary into the catalog.
## [param title] Cleaned setting label string.
## [param tab_idx] Tab category index.
## [param tab_name] Tab category string name.
## [param p_btn] Primary binding button if paired.
## [param s_btn] Secondary binding button if paired.
## [param c_btn] Clear binding button if paired.
## [param slider] Slider control if paired.
## [param readout] Readout numerical label if paired.
## [param line_edit] LineEdit control if paired.
## [param generic] Generic focusable control if paired.
func _register_inspected_row(
	title: String,
	tab_idx: int,
	tab_name: String,
	p_btn: Button,
	s_btn: Button,
	c_btn: Button,
	slider: HSlider,
	readout: Label,
	line_edit: LineEdit,
	generic: Control
) -> void:
	if title.is_empty():
		return

	if p_btn != null:
		_append_search_entry(
			{
				"title": title,
				"tab_index": tab_idx,
				"tab_name": tab_name,
				"type": "action",
				"target": p_btn,
				"action": p_btn.get_meta("action", "") as String,
				"primary_btn": p_btn,
				"secondary_btn": s_btn,
				"clear_btn": c_btn
			}
		)
	elif slider != null:
		_append_search_entry(
			{
				"title": title,
				"tab_index": tab_idx,
				"tab_name": tab_name,
				"type": "slider",
				"target": line_edit as Control if line_edit != null else slider as Control,
				"slider": slider,
				"readout_lbl": readout,
				"line_edit": line_edit
			}
		)
	elif line_edit != null:
		_append_search_entry(
			{
				"title": title,
				"tab_index": tab_idx,
				"tab_name": tab_name,
				"type": "line_edit",
				"target": line_edit,
				"line_edit": line_edit
			}
		)
	elif generic != null:
		_append_search_entry(
			{
				"title": title,
				"tab_index": tab_idx,
				"tab_name": tab_name,
				"type": "generic",
				"target": generic
			}
		)


## Adds an item dictionary to [_search_index] avoiding redundant duplicate keys.
## [param data] Item data dictionary to register.
func _append_search_entry(data: Dictionary) -> void:
	var clean_title: String = data["title"] as String
	for item: Dictionary in _search_index:
		if item["title"] == clean_title and item["tab_index"] == data["tab_index"]:
			return
	_search_index.append(data)


## Checks whether a given node accepts interactive user manipulation.
## [param node] Node to inspect.
## [return] True if input events are accepted.
func _is_interactive(node: Node) -> bool:
	return (
		node is OptionButton
		or node is CheckButton
		or node is CheckBox
		or node is HSlider
		or node is LineEdit
		or (
			node is Button
			and not (node is CheckButton or node is CheckBox or node is OptionButton)
			and node.name != "MasterBackButton"
		)
	)


## Updates dropdown list items based on active text input.
## [param query] Search string query provided by the user.
func _on_search_text_changed(query: String) -> void:
	var clean_query: String = query.strip_edges().to_lower()
	print("UI: Processing search query -> '", clean_query, "'")

	if clean_query.is_empty():
		_clear_result_rows()
		if is_instance_valid(search_results_panel):
			search_results_panel.visible = false
		return

	if not is_instance_valid(search_results_list):
		return

	_clear_result_rows()

	for child: Node in search_results_list.get_children():
		child.queue_free()

	var matched_count: int = 0
	for item: Dictionary in _search_index:
		var title_str: String = item["title"] as String
		var category_str: String = item["tab_name"] as String

		if clean_query in title_str.to_lower() or clean_query in category_str.to_lower():
			matched_count += 1
			var row: HBoxContainer = _create_result_row(item)
			search_results_list.add_child(row)

	_align_dropdown_panel()
	if is_instance_valid(search_results_panel):
		search_results_panel.visible = (matched_count > 0)


## Refreshes dropdown results when the player focuses the LineEdit.
func _on_search_bar_focused() -> void:
	print("UI: Search input focused.")
	if is_instance_valid(search_bar):
		if not search_bar.text.strip_edges().is_empty():
			_on_search_text_changed(search_bar.text)


## Dynamically positions the dropdown list directly beneath the search field.
func _align_dropdown_panel() -> void:
	if not is_instance_valid(search_bar) or not is_instance_valid(search_results_panel):
		return

	var bar_pos: Vector2 = search_bar.global_position
	var bar_size: Vector2 = search_bar.size
	var width: float = maxf(bar_size.x, DEFAULT_RESULTS_WIDTH)

	search_results_panel.custom_minimum_size.x = width
	search_results_panel.size.x = width

	if is_instance_valid(search_scroll):
		search_scroll.custom_minimum_size.x = width
		search_scroll.size.x = width

	var target_x: float = bar_pos.x
	var vp_width: float = get_viewport().get_visible_rect().size.x
	if target_x + width > vp_width:
		target_x = maxf(0.0, vp_width - width - DROPDOWN_VIEWPORT_PADDING)

	search_results_panel.global_position = Vector2(
		target_x, bar_pos.y + bar_size.y + DROPDOWN_OFFSET_Y
	)


## Constructs a synchronized horizontal control row for an indexed item.
## [param item] Metadata dictionary holding references to the real control.
## [return] The constructed [HBoxContainer] widget.
func _create_result_row(item: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 34.0
	row.add_theme_constant_override("separation", 10)

	var title: String = item["title"] as String
	var category: String = item["tab_name"] as String
	var tab_idx: int = item["tab_index"] as int
	var target: Control = item["target"] as Control
	var row_type: String = item["type"] as String

	var link_btn: Button = Button.new()
	link_btn.text = "%s  [%s]" % [title, category]
	link_btn.flat = true
	link_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	link_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link_btn.pressed.connect(
		func() -> void:
			print("UI: Selected search row: ", title)
			hide_search_results()
			setting_navigated.emit(tab_idx, target)
	)
	row.add_child(link_btn)

	match row_type:
		"slider":
			_build_mirrored_slider_row(row, item)
		"line_edit":
			_build_mirrored_line_edit_row(row, item)
		"action":
			_build_mirrored_action_row(row, item, tab_idx)
		"generic":
			if is_instance_valid(target):
				_build_mirrored_generic_row(row, target)

	return row


## Generates and attaches a mirrored synchronized slider control.
## [param row] Container to append cloned elements into.
## [param item] Metadata item holding original slider references.
func _build_mirrored_slider_row(row: HBoxContainer, item: Dictionary) -> void:
	var orig_sl: HSlider = item["slider"] as HSlider
	var orig_readout: Label = item.get("readout_lbl", null) as Label
	var orig_le: LineEdit = item.get("line_edit", null) as LineEdit
	var cloned_le: LineEdit = null
	var readout_lbl: Label = null

	if is_instance_valid(orig_le):
		cloned_le = LineEdit.new()
		cloned_le.text = orig_le.text
		cloned_le.placeholder_text = orig_le.placeholder_text
		cloned_le.alignment = orig_le.alignment
		cloned_le.custom_minimum_size.x = maxf(orig_le.custom_minimum_size.x, 56.0)
		cloned_le.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var sync_le: Callable = func(text: String) -> void:
			if is_instance_valid(cloned_le) and cloned_le.text != text:
				cloned_le.text = text

		cloned_le.text_submitted.connect(
			func(submitted: String) -> void:
				print("UI: Mirrored LineEdit submitted -> ", submitted)
				if orig_le.text != submitted:
					orig_le.text = submitted
					orig_le.text_submitted.emit(submitted)
				if submitted.is_valid_float() and is_instance_valid(orig_sl):
					var val: float = submitted.to_float()
					orig_sl.value = val
					orig_sl.value_changed.emit(val)
		)
		cloned_le.text_changed.connect(
			func(changed: String) -> void:
				if orig_le.text != changed:
					orig_le.text = changed
					orig_le.text_changed.emit(changed)
		)
		orig_le.text_changed.connect(sync_le)
		cloned_le.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_le) and orig_le.text_changed.is_connected(sync_le):
					orig_le.text_changed.disconnect(sync_le)
		)
		row.add_child(cloned_le)
	elif is_instance_valid(orig_readout):
		readout_lbl = Label.new()
		readout_lbl.custom_minimum_size.x = 48.0
		readout_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout_lbl.text = orig_readout.text
		row.add_child(readout_lbl)

	if is_instance_valid(orig_sl):
		var cloned_sl: HSlider = HSlider.new()
		cloned_sl.min_value = orig_sl.min_value
		cloned_sl.max_value = orig_sl.max_value
		cloned_sl.step = orig_sl.step
		cloned_sl.value = orig_sl.value
		cloned_sl.custom_minimum_size.x = 180.0
		cloned_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var sync_sl: Callable = func(val: float) -> void:
			if is_instance_valid(cloned_sl):
				cloned_sl.value = val
			if is_instance_valid(readout_lbl):
				readout_lbl.text = (
					orig_readout.text if is_instance_valid(orig_readout) else ("%.2f" % val)
				)
			if is_instance_valid(cloned_le):
				cloned_le.text = (orig_le.text if is_instance_valid(orig_le) else ("%.2f" % val))

		cloned_sl.value_changed.connect(
			func(val: float) -> void:
				print("UI: Mirrored HSlider changed -> ", val)
				if not is_equal_approx(orig_sl.value, val):
					orig_sl.value = val  # Setting value natively emits value_changed

				if is_instance_valid(readout_lbl):
					readout_lbl.text = (
						orig_readout.text if is_instance_valid(orig_readout) else ("%.2f" % val)
					)
				if is_instance_valid(cloned_le):
					cloned_le.text = (
						orig_le.text if is_instance_valid(orig_le) else ("%.2f" % val)
					)
		)
		orig_sl.value_changed.connect(sync_sl)
		cloned_sl.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_sl) and orig_sl.value_changed.is_connected(sync_sl):
					orig_sl.value_changed.disconnect(sync_sl)
		)
		row.add_child(cloned_sl)


## Generates and attaches a mirrored standalone LineEdit control.
## [param row] Container to append cloned elements into.
## [param item] Metadata item holding original LineEdit references.
func _build_mirrored_line_edit_row(row: HBoxContainer, item: Dictionary) -> void:
	var orig_le: LineEdit = item["line_edit"] as LineEdit
	if not is_instance_valid(orig_le):
		return

	var cloned_le: LineEdit = LineEdit.new()
	cloned_le.text = orig_le.text
	cloned_le.placeholder_text = orig_le.placeholder_text
	cloned_le.alignment = orig_le.alignment
	cloned_le.custom_minimum_size.x = 180.0
	cloned_le.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var sync_le: Callable = func(text: String) -> void:
		if is_instance_valid(cloned_le) and cloned_le.text != text:
			cloned_le.text = text

	cloned_le.text_submitted.connect(
		func(submitted: String) -> void:
			print("UI: Mirrored Standalone LineEdit submitted -> ", submitted)
			if orig_le.text != submitted:
				orig_le.text = submitted
				orig_le.text_submitted.emit(submitted)
	)
	cloned_le.text_changed.connect(
		func(changed: String) -> void:
			if orig_le.text != changed:
				orig_le.text = changed
				orig_le.text_changed.emit(changed)
	)
	orig_le.text_changed.connect(sync_le)
	cloned_le.tree_exited.connect(
		func() -> void:
			if is_instance_valid(orig_le) and orig_le.text_changed.is_connected(sync_le):
				orig_le.text_changed.disconnect(sync_le)
	)
	row.add_child(cloned_le)


## Generates mirrored action trigger and clear buttons for keybinding rows.
## [param row] Container to append cloned elements into.
## [param item] Metadata item holding button references.
## [param tab_idx] Tab category index.
func _build_mirrored_action_row(row: HBoxContainer, item: Dictionary, tab_idx: int) -> void:
	var orig_p: Button = item["primary_btn"] as Button
	var orig_s: Button = item["secondary_btn"] as Button
	var orig_c: Button = item["clear_btn"] as Button

	if is_instance_valid(orig_p):
		var cloned_p: Button = Button.new()
		cloned_p.text = orig_p.text if not orig_p.text.is_empty() else "Primary"
		cloned_p.custom_minimum_size.x = 90.0
		cloned_p.pressed.connect(
			func() -> void:
				hide_search_results()
				setting_navigated.emit(tab_idx, orig_p)
		)
		row.add_child(cloned_p)

	if is_instance_valid(orig_s):
		var cloned_s: Button = Button.new()
		cloned_s.text = orig_s.text if not orig_s.text.is_empty() else "Secondary"
		cloned_s.custom_minimum_size.x = 90.0
		cloned_s.pressed.connect(
			func() -> void:
				hide_search_results()
				setting_navigated.emit(tab_idx, orig_s)
		)
		row.add_child(cloned_s)

	if is_instance_valid(orig_c):
		var cloned_c: Button = Button.new()
		cloned_c.text = "✕"
		cloned_c.custom_minimum_size.x = 32.0
		cloned_c.pressed.connect(
			func() -> void:
				print("UI: Mirrored action clear button pressed -> ", item["action"])
				orig_c.pressed.emit()
		)
		row.add_child(cloned_c)


## Generates mirrored generic checkbox or option buttons.
## [param row] Container to append cloned elements into.
## [param target] Target interactive control to clone.
func _build_mirrored_generic_row(row: HBoxContainer, target: Control) -> void:
	if target is OptionButton:
		var orig_ob: OptionButton = target as OptionButton
		var cloned_ob: OptionButton = OptionButton.new()
		for i: int in range(orig_ob.item_count):
			cloned_ob.add_item(orig_ob.get_item_text(i), orig_ob.get_item_id(i))
		cloned_ob.selected = orig_ob.selected
		cloned_ob.custom_minimum_size.x = 180.0

		var sync_ob: Callable = func(idx: int) -> void:
			if is_instance_valid(cloned_ob):
				cloned_ob.selected = idx

		cloned_ob.item_selected.connect(
			func(idx: int) -> void:
				print("UI: Mirrored OptionButton changed -> ", idx)
				if orig_ob.selected != idx:
					orig_ob.selected = idx
					orig_ob.item_selected.emit(idx)
		)
		orig_ob.item_selected.connect(sync_ob)
		cloned_ob.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_ob) and orig_ob.item_selected.is_connected(sync_ob):
					orig_ob.item_selected.disconnect(sync_ob)
		)
		row.add_child(cloned_ob)
	elif target is CheckButton:
		var orig_cb: CheckButton = target as CheckButton
		var cloned_cb: CheckButton = CheckButton.new()
		cloned_cb.button_pressed = orig_cb.button_pressed

		var sync_cb: Callable = func(pressed: bool) -> void:
			if is_instance_valid(cloned_cb):
				cloned_cb.button_pressed = pressed

		cloned_cb.toggled.connect(
			func(pressed: bool) -> void:
				print("UI: Mirrored CheckButton toggled -> ", pressed)
				if orig_cb.button_pressed != pressed:
					orig_cb.button_pressed = pressed
					orig_cb.toggled.emit(pressed)
		)
		orig_cb.toggled.connect(sync_cb)
		cloned_cb.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_cb) and orig_cb.toggled.is_connected(sync_cb):
					orig_cb.toggled.disconnect(sync_cb)
		)
		row.add_child(cloned_cb)
	elif target is CheckBox:
		var orig_chk: CheckBox = target as CheckBox
		var cloned_chk: CheckBox = CheckBox.new()
		cloned_chk.button_pressed = orig_chk.button_pressed

		var sync_chk: Callable = func(pressed: bool) -> void:
			if is_instance_valid(cloned_chk):
				cloned_chk.button_pressed = pressed

		cloned_chk.toggled.connect(
			func(pressed: bool) -> void:
				print("UI: Mirrored CheckBox toggled -> ", pressed)
				if orig_chk.button_pressed != pressed:
					orig_chk.button_pressed = pressed
					orig_chk.toggled.emit(pressed)
		)
		orig_chk.toggled.connect(sync_chk)
		cloned_chk.tree_exited.connect(
			func() -> void:
				if is_instance_valid(orig_chk) and orig_chk.toggled.is_connected(sync_chk):
					orig_chk.toggled.disconnect(sync_chk)
		)
		row.add_child(cloned_chk)


## Clears current search results rows immediately to avoid signal ghosts.
func _clear_result_rows() -> void:
	if not is_instance_valid(search_results_list):
		return
	for child: Node in search_results_list.get_children():
		search_results_list.remove_child(child)
		child.queue_free()
