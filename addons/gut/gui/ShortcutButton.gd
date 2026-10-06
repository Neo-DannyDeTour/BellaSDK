@tool
extends Control


@onready var _ctrls: Variant = {
	shortcut_label = $Layout/lblShortcut,
	set_button = $Layout/SetButton,
	save_button = $Layout/SaveButton,
	cancel_button = $Layout/CancelButton,
	clear_button = $Layout/ClearButton
}

signal changed
signal start_edit
signal end_edit

const NO_SHORTCUT: String = '<None>'

var _source_event: InputEventKey = InputEventKey.new()
var _pre_edit_event: Variant = null
var _key_disp: Variant = NO_SHORTCUT
var _editing: bool = false

var _modifier_keys: Array = [KEY_ALT, KEY_CTRL, KEY_META, KEY_SHIFT]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	set_process_unhandled_key_input(false)


func _display_shortcut() -> void:
	if(_key_disp == ''):
		_key_disp = NO_SHORTCUT
	_ctrls.shortcut_label.text = _key_disp


func _is_shift_only_modifier() -> Variant:
	return _source_event.shift_pressed and \
		!(_source_event.alt_pressed or \
			_source_event.ctrl_pressed or \
			_source_event.meta_pressed) \
		and !_is_modifier(_source_event.keycode)


func _has_modifier(event: Variant) -> Variant:
	return event.alt_pressed or event.ctrl_pressed or \
		event.meta_pressed or event.shift_pressed


func _is_modifier(keycode: Variant) -> Variant:
	return _modifier_keys.has(keycode)


func _edit_mode(should: Variant) -> void:
	_editing = should
	set_process_unhandled_key_input(should)
	_ctrls.set_button.visible = !should
	_ctrls.save_button.visible = should
	_ctrls.save_button.disabled = should
	_ctrls.cancel_button.visible = should
	_ctrls.clear_button.visible = !should

	if(should and to_s() == ''):
		_ctrls.shortcut_label.text = 'press buttons'
	else:
		_ctrls.shortcut_label.text = to_s()

	if(should):
		emit_signal("start_edit")
	else:
		emit_signal("end_edit")

# ---------------
# Events
# ---------------
func _unhandled_key_input(event: Variant) -> void:
	if(event is InputEventKey):
		if(event.pressed):
			if(_has_modifier(event) and !_is_modifier(event.get_keycode_with_modifiers())):
				_source_event = event
				_key_disp = OS.get_keycode_string(event.get_keycode_with_modifiers())
			else:
				_source_event = InputEventKey.new()
				_key_disp = NO_SHORTCUT
			_display_shortcut()
			_ctrls.save_button.disabled = !is_valid()


func _on_SetButton_pressed() -> void:
	_pre_edit_event = _source_event.duplicate(true)
	_edit_mode(true)


func _on_SaveButton_pressed() -> void:
	_edit_mode(false)
	_pre_edit_event = null
	emit_signal('changed')


func _on_CancelButton_pressed() -> void:
	cancel()


func _on_ClearButton_pressed() -> void:
	clear_shortcut()

# ---------------
# Public
# ---------------
func to_s() -> Variant:
	return OS.get_keycode_string(_source_event.get_keycode_with_modifiers())


func is_valid() -> Variant:
	return _has_modifier(_source_event) and !_is_shift_only_modifier()


func get_shortcut() -> Variant:
	var to_return: Shortcut = Shortcut.new()
	to_return.events.append(_source_event)
	return to_return

func get_input_event() -> Variant:
	return _source_event

func set_shortcut(sc: Variant) -> void:
	if(sc == null or sc.events == null or sc.events.size() <= 0):
		clear_shortcut()
	else:
		_source_event = sc.events[0]
		_key_disp = to_s()
		_display_shortcut()


func clear_shortcut() -> void:
	_source_event = InputEventKey.new()
	_key_disp = NO_SHORTCUT
	_display_shortcut()


func disable_set(should: Variant) -> void:
	_ctrls.set_button.disabled = should


func disable_clear(should: Variant) -> void:
	_ctrls.clear_button.disabled = should


func cancel() -> void:
	if(_editing):
		_edit_mode(false)
		_source_event = _pre_edit_event
		_key_disp = to_s()
		_display_shortcut()
