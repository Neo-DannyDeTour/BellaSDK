## Utility singleton managing keybind formatting and icon texture resolution.
# class_name InputHelperClass
extends Node

## Base directory path where Kenney input prompt icons are stored.
const ICON_BASE_PATH: String = "res://assets/kenney_input-prompts_1.5/Keyboard & Mouse/Default/"

## Cached textures mapped to avoid redundant disk I/O at 60 FPS.
var _icon_cache: Dictionary = {}


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
		var candidate_paths: Array[String] = [
			ICON_BASE_PATH + file_name,
			ICON_BASE_PATH + "Keyboard/" + file_name,
			ICON_BASE_PATH + "Mouse/" + file_name
		]

		for full_path: String in candidate_paths:
			if _icon_cache.has(full_path):
				var cached_val: Variant = _icon_cache[full_path]
				if cached_val is Texture2D:
					return cached_val
				return null

			if ResourceLoader.exists(full_path):
				var loaded_res: Resource = load(full_path)
				if loaded_res is Texture2D:
					var tex: Texture2D = loaded_res
					_icon_cache[full_path] = tex
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
