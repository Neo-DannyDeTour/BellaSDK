const PanelControls = preload("res://addons/gut/gui/panel_controls.gd")

# All titles so we can free them when we want.
var _all_titles: Array = []


var base_container: Variant = null
# All the various PanelControls indexed by thier keys.
var controls: Dictionary = {}


func _init(cont: Variant) -> void:
	base_container = cont


func add_title(text: Variant) -> Variant:
	var row: Variant = PanelControls.BaseGutPanelControl.new(text, text)
	base_container.add_child(row)
	row.connect('draw', _on_title_cell_draw.bind(row))
	_all_titles.append(row)
	return row


func add_ctrl(key: Variant, ctrl: Variant) -> void:
	controls[key] = ctrl
	base_container.add_child(ctrl)


func add_number(key: Variant, value: Variant, disp_text: Variant, v_min: Variant, v_max: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcNumber.new(disp_text, value, v_min, v_max, hint)
	add_ctrl(key, ctrl)
	return ctrl


func add_float(key: Variant, value: Variant, disp_text: Variant, step: Variant, v_min: Variant, v_max: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcFloat.new(disp_text, value, step, v_min, v_max, hint)
	add_ctrl(key, ctrl)
	return ctrl


func add_select(key: Variant, value: Variant, values: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcSelect.new(disp_text, value, values, hint)
	add_ctrl(key, ctrl)
	return ctrl


func add_value(key: Variant, value: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcString.new(disp_text, value, hint)
	add_ctrl(key, ctrl)
	return ctrl

func add_multiline_text(key: Variant, value: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcMultiLineString.new(disp_text, value, hint)
	add_ctrl(key, ctrl)
	return ctrl

func add_boolean(key: Variant, value: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcBoolean.new(disp_text, value, hint)
	add_ctrl(key, ctrl)
	return ctrl


func add_directory(key: Variant, value: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcDirectory.new(disp_text, value, hint)
	add_ctrl(key, ctrl)
	ctrl.dialog.title = disp_text
	return ctrl


func add_file(key: Variant, value: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcDirectory.new(disp_text, value, hint)
	add_ctrl(key, ctrl)
	ctrl.dialog.file_mode = ctrl.dialog.FILE_MODE_OPEN_FILE
	ctrl.dialog.title = disp_text
	return ctrl


func add_save_file_anywhere(key: Variant, value: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcDirectory.new(disp_text, value, hint)
	add_ctrl(key, ctrl)
	ctrl.dialog.file_mode = ctrl.dialog.FILE_MODE_SAVE_FILE
	ctrl.dialog.access = ctrl.dialog.ACCESS_FILESYSTEM
	ctrl.dialog.title = disp_text
	return ctrl


func add_color(key: Variant, value: Variant, disp_text: Variant, hint: String = '') -> Variant:
	var ctrl: Variant = PanelControls.GpcColor.new(disp_text, value, hint)
	add_ctrl(key, ctrl)
	return ctrl


var _blurbs: int = 0
func add_blurb(text: Variant) -> Variant:
	var ctrl: RichTextLabel = RichTextLabel.new()
	ctrl.fit_content = true
	ctrl.bbcode_enabled = true
	ctrl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl.text = text
	add_ctrl(str("blurb_", _blurbs), ctrl)
	return ctrl


# ------------------
# Events
# ------------------
func _on_title_cell_draw(which: Variant) -> void:
	which.draw_rect(Rect2(Vector2(0, 0), which.size), Color(0, 0, 0, .15))


# ------------------
# Public
# ------------------

func clear() -> void:
	for key in controls:
		controls[key].free()

	controls.clear()

	for entry in _all_titles:
		entry.free()

	_all_titles.clear()
