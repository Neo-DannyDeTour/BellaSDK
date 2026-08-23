## Editor plugin registering the volumetric clouds viewport inspector and dock.
@tool
extends EditorPlugin

## Reference to the instantiated editor dock controller.
var dock: CloudsEditorController


## Determines if this plugin handles the inspected [param object].
func _handles(object: Object) -> bool:
	return object is SunshineCloudsDriverGD


## Forwards 3D viewport input events to the clouds brush controller.
func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(dock):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if dock.current_draw_mode == CloudsEditorController.DrawingMode.NONE:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if Input.is_key_pressed(KEY_ESCAPE):
		dock.draw_mode_cancel()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if Input.is_key_pressed(KEY_CTRL):
		dock.set_draw_invert(true)
	else:
		dock.set_draw_invert(false)

	if event is InputEventMouse:
		dock.iterate_cursor_location(viewport_camera, event)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.is_pressed():
				dock.begin_cursor_draw()
				Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if dock.drawing_currently:
				dock.end_cursor_draw()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				dock.scale_drawing_circle_up()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				dock.scale_drawing_circle_down()
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Instantiates the dock and connects scene lifecycle signals.
func _enter_tree() -> void:
	dock = preload(
		"res://addons/SunshineClouds2/Dock/CloudsEditorDock.tscn"
	).instantiate() as CloudsEditorController
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)

	scene_changed.connect(dock.scene_changed)
	dock.call_deferred(&"initial_scene_load")
	set_input_event_forwarding_always_enabled()


## Cleans up dock references when the plugin is disabled.
func _exit_tree() -> void:
	if is_instance_valid(dock):
		if scene_changed.is_connected(dock.scene_changed):
			scene_changed.disconnect(dock.scene_changed)
		remove_control_from_docks(dock)
		dock.free()
		dock = null
