@tool
extends Control

var GutEditorGlobals = load('res://addons/gut/gui/editor_globals.gd')

var _interface: Variant = null
var _output_control: Variant = null

@onready var _ctrls: Variant = {
	tree = $VBox/Output/Scroll/Tree,
	toolbar = {
		toolbar = $VBox/Toolbar,
		collapse = $VBox/Toolbar/Collapse,
		collapse_all = $VBox/Toolbar/CollapseAll,
		expand = $VBox/Toolbar/Expand,
		expand_all = $VBox/Toolbar/ExpandAll,
		hide_passing = $VBox/Toolbar/HidePassing,
		show_script = $VBox/Toolbar/ShowScript,
		scroll_output = $VBox/Toolbar/ScrollOutput
	}
}

func _ready() -> void:
	if(get_parent() is SubViewport):
		return

	var f: Variant = null
	if ($FontSampler.get_label_settings() == null) :
		f = get_theme_default_font()
	else :
		f = $FontSampler.get_label_settings().font
	var s_size: Variant = f.get_string_size("000 of 000 passed")
	_ctrls.tree.set_summary_min_width(s_size.x)

	_set_toolbutton_icon(_ctrls.toolbar.collapse, 'CollapseTree', 'c')
	_set_toolbutton_icon(_ctrls.toolbar.collapse_all, 'CollapseTree', 'c')
	_set_toolbutton_icon(_ctrls.toolbar.expand, 'ExpandTree', 'e')
	_set_toolbutton_icon(_ctrls.toolbar.expand_all, 'ExpandTree', 'e')
	_set_toolbutton_icon(_ctrls.toolbar.show_script, 'Script', 'ss')
	_set_toolbutton_icon(_ctrls.toolbar.scroll_output, 'Font', 'so')

	_ctrls.tree.hide_passing = true
	_ctrls.toolbar.hide_passing.button_pressed = false
	_ctrls.tree.show_orphans = true
	_ctrls.tree.selected.connect(_on_item_selected)

	if(get_parent() == get_tree().root):
		_test_running_setup()

	call_deferred('_update_min_width')


func _test_running_setup() -> void:
	_ctrls.tree.hide_passing = true
	_ctrls.tree.show_orphans = true

	_ctrls.toolbar.hide_passing.text = '[hp]'
	_ctrls.tree.load_json_file(GutEditorGlobals.editor_run_json_results_path)


func _set_toolbutton_icon(btn: Variant, icon_name: Variant, text: Variant) -> void:
	if(Engine.is_editor_hint()):
		btn.icon = get_theme_icon(icon_name, 'EditorIcons')
	else:
		btn.text = str('[', text, ']')


func _update_min_width() -> void:
	custom_minimum_size.x = _ctrls.toolbar.toolbar.size.x


func _open_script_in_editor(path: Variant, line_number: Variant) -> void:
	if(_interface == null):
		print('Too soon, wait a bit and try again.')
		return

	var r: Variant = load(path)
	if(line_number != null and line_number != -1):
		_interface.edit_script(r, line_number)
	else:
		_interface.edit_script(r)

	if(_ctrls.toolbar.show_script.pressed):
		_interface.set_main_screen_editor('Script')


# starts at beginning of text edit and searches for each search term, moving
# through the text as it goes; ensuring that, when done, it found the first
# occurance of the last srting that happend after the first occurance of
# each string before it.  (Generic way of searching for a method name in an
# inner class that may have be a duplicate of a method name in a different
# inner class)
func _get_line_number_for_seq_search(search_strings: Variant, te: Variant) -> Variant:
	if(te == null):
		print("No Text editor to get line number for")
		return 0;

	var result: Variant = null
	var line: Vector2i = Vector2i(0, 0)
	var s_flags: int = 0

	var i: int = 0
	var string_found: bool = true
	while(i < search_strings.size() and string_found):
		result = te.search(search_strings[i], s_flags, line.y, line.x)
		if(result.x != -1):
			line = result
		else:
			string_found = false
		i += 1

	return line.y


func _goto_code(path: Variant, line: Variant, method_name: String = '', inner_class: String = '') -> void:
	if(_interface == null):
		print('going to ', [path, line, method_name, inner_class])
		return

	_open_script_in_editor(path, line)
	if(line == -1):
		var search_strings: Array = []
		if(inner_class != ''):
			search_strings.append(inner_class)

		if(method_name != ''):
			search_strings.append(method_name)

		await get_tree().process_frame
		line = _get_line_number_for_seq_search(search_strings,
			_interface.get_script_editor().get_current_editor().get_base_editor())
		if(line != null and line != -1):
			_interface.get_script_editor().goto_line(line)


func _goto_output(path: Variant, method_name: Variant, inner_class: Variant) -> void:
	if(_output_control == null):
		return

	var search_strings: Array = [path]

	if(inner_class != ''):
		search_strings.append(inner_class)

	if(method_name != ''):
		search_strings.append(method_name)

	var line: Variant = _get_line_number_for_seq_search(search_strings, _output_control.get_rich_text_edit())
	if(line != null and line != -1):
		_output_control.scroll_to_line(line)




# --------------
# Events
# --------------
func _on_Collapse_pressed() -> void:
	collapse_selected()


func _on_Expand_pressed() -> void:
	expand_selected()


func _on_CollapseAll_pressed() -> void:
	collapse_all()


func _on_ExpandAll_pressed() -> void:
	expand_all()


func _on_Hide_Passing_pressed() -> void:
	_ctrls.tree.hide_passing = !_ctrls.toolbar.hide_passing.button_pressed
	_ctrls.tree.load_json_file(GutEditorGlobals.editor_run_json_results_path)


func _on_item_selected(script_path: Variant, inner_class: Variant, test_name: Variant, line: Variant) -> void:
	if(_ctrls.toolbar.show_script.button_pressed):
		_goto_code(script_path, line, test_name, inner_class)
	if(_ctrls.toolbar.scroll_output.button_pressed):
		_goto_output(script_path, test_name, inner_class)




# --------------
# Public
# --------------
func add_centered_text(t: Variant) -> void:
	_ctrls.tree.add_centered_text(t)


func clear_centered_text() -> void:
	_ctrls.tree.clear_centered_text()


func clear() -> void:
	_ctrls.tree.clear()
	clear_centered_text()


func set_interface(which: Variant) -> void:
	_interface = which


func collapse_all() -> void:
	_ctrls.tree.collapse_all()


func expand_all() -> void:
	_ctrls.tree.expand_all()


func collapse_selected() -> void:
	var item: Variant = _ctrls.tree.get_selected()
	if(item != null):
		_ctrls.tree.set_collapsed_on_all(item, true)


func expand_selected() -> void:
	var item: Variant = _ctrls.tree.get_selected()
	if(item != null):
		_ctrls.tree.set_collapsed_on_all(item, false)


func set_show_orphans(should: Variant) -> void:
	_ctrls.tree.show_orphans = should


func set_font(font_name: Variant, size: Variant) -> void:
	pass
#	var dyn_font = FontFile.new()
#	var font_data = FontFile.new()
#	font_data.font_path = 'res://addons/gut/fonts/' + font_name + '-Regular.ttf'
#	font_data.antialiased = true
#	dyn_font.font_data = font_data
#
#	_font = dyn_font
#	_font.size = size
#	_font_size = size


func set_output_control(value: Variant) -> void:
	_output_control = value


func load_json_results(j: Variant) -> void:
	_ctrls.tree.load_json_results(j)
