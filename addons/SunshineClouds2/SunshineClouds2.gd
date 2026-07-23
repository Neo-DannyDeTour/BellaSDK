@tool
extends EditorPlugin
var dock : CloudsEditorController
func _handles(object: Object) -> bool:
	return object is SunshineCloudsDriverGD
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if dock.current_draw_mode == CloudsEditorController.DRAWINGMODE.NONE:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if (Input.is_key_pressed(KEY_ESCAPE)):
		dock.draw_mode_cancel()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if (Input.is_key_pressed(KEY_CTRL)):
		dock.set_draw_invert(true)
	else:
		dock.set_draw_invert(false)

	if event is InputEventMouse:
		dock.iterate_cursor_location(viewport_camera, event)

	if (event is InputEventMouseButton):
		if (event.button_index == MOUSE_BUTTON_LEFT):
			if event.is_pressed():
				dock.begin_cursor_draw()
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if dock.drawing_currently:
				dock.end_cursor_draw()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if !Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if (event.button_index == MOUSE_BUTTON_WHEEL_UP):
				dock.scale_drawing_circle_up()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if (event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				dock.scale_drawing_circle_down()
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS
func _enter_tree() -> void:

	# gdlint: disable=max-line-length
	dock = preload("res://addons/SunshineClouds2/Dock/CloudsEditorDock.tscn").instantiate() as CloudsEditorController
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

	scene_changed.connect(dock.scene_changed)
	dock.call_deferred(&"initial_scene_load")
	set_input_event_forwarding_always_enabled()
func _exit_tree() -> void:
	scene_changed.disconnect(dock.scene_changed)

	remove_control_from_docks(dock)
	dock.free()
