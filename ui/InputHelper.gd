## Utility singleton managing keybind formatting and icon texture resolution.
# class_name InputHelperClass
extends Node

## Base directory path where Kenney input prompt icons are stored.
const ICON_BASE_PATH: String = "res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"

## Preloaded Kenney prompt icons mapped by filename to avoid runtime disk I/O.
const PRELOADED_ICONS: Dictionary[String, Texture2D] = {
	"keyboard_space.png": preload(ICON_BASE_PATH + "keyboard_space.png"),
	"keyboard_space_icon.png": preload(ICON_BASE_PATH + "keyboard_space_icon.png"),
	"keyboard_return.png": preload(ICON_BASE_PATH + "keyboard_return.png"),
	"keyboard_enter.png": preload(ICON_BASE_PATH + "keyboard_enter.png"),
	"keyboard_shift.png": preload(ICON_BASE_PATH + "keyboard_shift.png"),
	"keyboard_ctrl.png": preload(ICON_BASE_PATH + "keyboard_ctrl.png"),
	"keyboard_alt.png": preload(ICON_BASE_PATH + "keyboard_alt.png"),
	"keyboard_tab.png": preload(ICON_BASE_PATH + "keyboard_tab.png"),
	"keyboard_escape.png": preload(ICON_BASE_PATH + "keyboard_escape.png"),
	"keyboard_backspace.png": preload(ICON_BASE_PATH + "keyboard_backspace.png"),
	"keyboard_capslock.png": preload(ICON_BASE_PATH + "keyboard_capslock.png"),
	"keyboard_slash_forward.png": preload(ICON_BASE_PATH + "keyboard_slash_forward.png"),
	"keyboard_slash_back.png": preload(ICON_BASE_PATH + "keyboard_slash_back.png"),
	"keyboard_semicolon.png": preload(ICON_BASE_PATH + "keyboard_semicolon.png"),
	"keyboard_period.png": preload(ICON_BASE_PATH + "keyboard_period.png"),
	"keyboard_comma.png": preload(ICON_BASE_PATH + "keyboard_comma.png"),
	"keyboard_minus.png": preload(ICON_BASE_PATH + "keyboard_minus.png"),
	"keyboard_equals.png": preload(ICON_BASE_PATH + "keyboard_equals.png"),
	"mouse_left.png": preload(ICON_BASE_PATH + "mouse_left.png"),
	"mouse_left_outline.png": preload(ICON_BASE_PATH + "mouse_left_outline.png"),
	"mouse_right.png": preload(ICON_BASE_PATH + "mouse_right.png"),
	"mouse_right_outline.png": preload(ICON_BASE_PATH + "mouse_right_outline.png"),
	"mouse_scroll.png": preload(ICON_BASE_PATH + "mouse_scroll.png"),
	"mouse_scroll_up.png": preload(ICON_BASE_PATH + "mouse_scroll_up.png"),
	"mouse_scroll_down.png": preload(ICON_BASE_PATH + "mouse_scroll_down.png"),
	"keyboard_0.png": preload(ICON_BASE_PATH + "keyboard_0.png"),
	"keyboard_1.png": preload(ICON_BASE_PATH + "keyboard_1.png"),
	"keyboard_2.png": preload(ICON_BASE_PATH + "keyboard_2.png"),
	"keyboard_3.png": preload(ICON_BASE_PATH + "keyboard_3.png"),
	"keyboard_4.png": preload(ICON_BASE_PATH + "keyboard_4.png"),
	"keyboard_5.png": preload(ICON_BASE_PATH + "keyboard_5.png"),
	"keyboard_6.png": preload(ICON_BASE_PATH + "keyboard_6.png"),
	"keyboard_7.png": preload(ICON_BASE_PATH + "keyboard_7.png"),
	"keyboard_8.png": preload(ICON_BASE_PATH + "keyboard_8.png"),
	"keyboard_9.png": preload(ICON_BASE_PATH + "keyboard_9.png"),
	"keyboard_a.png": preload(ICON_BASE_PATH + "keyboard_a.png"),
	"keyboard_b.png": preload(ICON_BASE_PATH + "keyboard_b.png"),
	"keyboard_c.png": preload(ICON_BASE_PATH + "keyboard_c.png"),
	"keyboard_d.png": preload(ICON_BASE_PATH + "keyboard_d.png"),
	"keyboard_e.png": preload(ICON_BASE_PATH + "keyboard_e.png"),
	"keyboard_f.png": preload(ICON_BASE_PATH + "keyboard_f.png"),
	"keyboard_g.png": preload(ICON_BASE_PATH + "keyboard_g.png"),
	"keyboard_h.png": preload(ICON_BASE_PATH + "keyboard_h.png"),
	"keyboard_i.png": preload(ICON_BASE_PATH + "keyboard_i.png"),
	"keyboard_j.png": preload(ICON_BASE_PATH + "keyboard_j.png"),
	"keyboard_k.png": preload(ICON_BASE_PATH + "keyboard_k.png"),
	"keyboard_l.png": preload(ICON_BASE_PATH + "keyboard_l.png"),
	"keyboard_m.png": preload(ICON_BASE_PATH + "keyboard_m.png"),
	"keyboard_n.png": preload(ICON_BASE_PATH + "keyboard_n.png"),
	"keyboard_o.png": preload(ICON_BASE_PATH + "keyboard_o.png"),
	"keyboard_p.png": preload(ICON_BASE_PATH + "keyboard_p.png"),
	"keyboard_q.png": preload(ICON_BASE_PATH + "keyboard_q.png"),
	"keyboard_r.png": preload(ICON_BASE_PATH + "keyboard_r.png"),
	"keyboard_s.png": preload(ICON_BASE_PATH + "keyboard_s.png"),
	"keyboard_t.png": preload(ICON_BASE_PATH + "keyboard_t.png"),
	"keyboard_u.png": preload(ICON_BASE_PATH + "keyboard_u.png"),
	"keyboard_v.png": preload(ICON_BASE_PATH + "keyboard_v.png"),
	"keyboard_w.png": preload(ICON_BASE_PATH + "keyboard_w.png"),
	"keyboard_x.png": preload(ICON_BASE_PATH + "keyboard_x.png"),
	"keyboard_y.png": preload(ICON_BASE_PATH + "keyboard_y.png"),
	"keyboard_z.png": preload(ICON_BASE_PATH + "keyboard_z.png"),
}

## Cached textures mapped to avoid redundant lookups at 60 FPS.
var _icon_cache: Dictionary[String, Texture2D] = {}


## Resolves an [InputEvent] to a matching default Kenney prompt icon texture.
func get_event_icon(event: InputEvent) -> Texture2D:
	print("InputHelper: Resolving icon for input event -> ", event.as_text())
	var possible_filenames: Array[String] = []

	if event is InputEventKey:
		var key_event: InputEventKey = event
		var code: Key = (
			key_event.physical_keycode
			if key_event.physical_keycode != KEY_NONE
			else key_event.keycode
		)
		var key_str: String = OS.get_keycode_string(code).to_lower()

		match code:
			KEY_SPACE:
				possible_filenames.append("keyboard_space.png")
				possible_filenames.append("keyboard_space_icon.png")
			KEY_ENTER:
				possible_filenames.append("keyboard_return.png")
				possible_filenames.append("keyboard_enter.png")
			KEY_SHIFT:
				possible_filenames.append("keyboard_shift.png")
			KEY_CTRL:
				possible_filenames.append("keyboard_ctrl.png")
			KEY_ALT:
				possible_filenames.append("keyboard_alt.png")
			KEY_TAB:
				possible_filenames.append("keyboard_tab.png")
			KEY_ESCAPE:
				possible_filenames.append("keyboard_escape.png")
			KEY_BACKSPACE:
				possible_filenames.append("keyboard_backspace.png")
			KEY_CAPSLOCK:
				possible_filenames.append("keyboard_capslock.png")
			KEY_SLASH:
				possible_filenames.append("keyboard_slash_forward.png")
			KEY_BACKSLASH:
				possible_filenames.append("keyboard_slash_back.png")
			KEY_SEMICOLON:
				possible_filenames.append("keyboard_semicolon.png")
			KEY_PERIOD:
				possible_filenames.append("keyboard_period.png")
			KEY_COMMA:
				possible_filenames.append("keyboard_comma.png")
			KEY_MINUS:
				possible_filenames.append("keyboard_minus.png")
			KEY_EQUAL:
				possible_filenames.append("keyboard_equals.png")
			_:
				if key_str.length() == 1:
					possible_filenames.append("keyboard_%s.png" % key_str)
					possible_filenames.append("keyboard_%s_outline.png" % key_str)

	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT:
				possible_filenames.append("mouse_left.png")
				possible_filenames.append("mouse_left_click.png")
				possible_filenames.append("mouse_left_outline.png")
			MOUSE_BUTTON_RIGHT:
				possible_filenames.append("mouse_right.png")
				possible_filenames.append("mouse_right_click.png")
				possible_filenames.append("mouse_right_outline.png")
			MOUSE_BUTTON_MIDDLE:
				possible_filenames.append("mouse_middle.png")
				possible_filenames.append("mouse_scroll.png")
			MOUSE_BUTTON_WHEEL_UP:
				possible_filenames.append("mouse_scroll_up.png")
			MOUSE_BUTTON_WHEEL_DOWN:
				possible_filenames.append("mouse_scroll_down.png")

	if possible_filenames.is_empty():
		return null

	for file_name: String in possible_filenames:
		if _icon_cache.has(file_name):
			return _icon_cache[file_name]
		if PRELOADED_ICONS.has(file_name):
			var tex: Texture2D = PRELOADED_ICONS[file_name]
			_icon_cache[file_name] = tex
			return tex

	return null


## Formats a hardware input key into a clean string stripped of internal tags.
func sanitize_key_name(raw_text: String) -> String:
	print("InputHelper: Sanitizing raw key label string -> ", raw_text)
	var clean: String = raw_text
	clean = clean.replace(" (Physical)", "")
	clean = clean.replace(" - Physical", "")
	clean = clean.replace(" (Physics)", "")
	clean = clean.replace(" - Physics", "")
	clean = clean.replace("Physical ", "")
	clean = clean.replace("Left Mouse Button", "LMB")
	clean = clean.replace("Right Mouse Button", "RMB")
	clean = clean.replace("Middle Mouse Button", "MMB")
	return clean.strip_edges()


## Retrieves the primary keybind label for [param action] formatted for UI display.
func get_action_key_label(action: StringName) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return "???"
	var primary_ev: InputEvent = events[0]
	if primary_ev.has_meta("chord_keys"):
		var raw_keys: Variant = primary_ev.get_meta("chord_keys")
		if raw_keys is Array:
			var parts: PackedStringArray = PackedStringArray()
			for item: Variant in raw_keys:
				if item is int:
					var key_id: int = item
					if key_id >= 100000:
						var mb: InputEventMouseButton = InputEventMouseButton.new()
						mb.button_index = (key_id - 100000) as MouseButton
						parts.append(sanitize_key_name(mb.as_text()))
					else:
						parts.append(sanitize_key_name(OS.get_keycode_string(key_id as Key)))
			if not parts.is_empty():
				var gesture_meta: Variant = primary_ev.get_meta("gesture", "")
				var sep: String = " → " if str(gesture_meta) == "ordered_chord" else " + "
				return sep.join(parts)
	return sanitize_key_name(primary_ev.as_text())
