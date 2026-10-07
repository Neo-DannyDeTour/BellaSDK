## Physics trigger displaying key-binding hints and notifying [TTSManager].
@tool
class_name HintTrigger
extends Area3D

## Predefined action types mapped to dynamic input hints.
enum HintType { CUSTOM, INTERACT, JUMP, CROUCH, SPRINT, FLASHLIGHT, ZOOM }

@export_category("Trigger Volume")

## Selects whether visualizer and collision represent a box or a sphere.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Defines 3D dimensions of trigger volume in the editor.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Local offset applied to collision shape and visualizer node.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

@export_category("Trigger Debug Visualizer")

## Controls if visualizer mesh and label stay visible during gameplay.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Determines base color and opacity of editor visualizer fill.
@export var trigger_color: Color = Color(0.2, 0.6, 1.0, 0.25):
	set(value):
		trigger_color = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Edge color applied to wireframe bounding cage and orientation arrow.
@export var outline_color: Color = Color(0.4, 0.8, 1.0, 0.9):
	set(value):
		outline_color = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Allows visualizer to remain visible through walls and level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Displays an arrow pointing along -Z indicating player entry heading.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Appends metric dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

## Sets 3D text floating above visualizer in the editor.
@export var trigger_text: String = "HINT":
	set(value):
		trigger_text = value
		if is_instance_valid(self) and is_inside_tree():
			_update_visuals()

@export_category("Hint Settings")

## Select predefined message from dropdown or choose CUSTOM.
@export var hint_type: HintType = HintType.INTERACT

## Text displayed when [member hint_type] is CUSTOM. Use [interact].
@export_multiline var custom_message: String = ""

## When true, triggers only once and ignores future overlaps.
@export var trigger_once: bool = true

## Duration in seconds that hint remains visible on screen.
@export var duration: float = 3.0

## Broadcasts formatted hint message to screen UI via Events.
@export var show_on_screen: bool = true

var _triggered: bool = false


## Initializes collision, synchronizes visuals, and connects signals.
func _ready() -> void:
	print("HintTrigger: _ready() - Initializing trigger.")
	_update_visuals()
	if Engine.is_editor_hint():
		return

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Syncs collision shape and visualizer node with inspector values.
func _update_visuals() -> void:
	if not is_inside_tree():
		return

	var col: CollisionShape3D = _get_collision_shape()
	if is_instance_valid(col):
		if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
			if not col.shape is BoxShape3D:
				col.shape = BoxShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			var box: BoxShape3D = col.shape if col.shape is BoxShape3D else null
			box.size = trigger_size
		elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not col.shape is SphereShape3D:
				col.shape = SphereShape3D.new()
			else:
				col.shape = col.shape.duplicate()
			var sphere: SphereShape3D = col.shape if col.shape is SphereShape3D else null
			sphere.radius = trigger_size.x * 0.5

		col.position = trigger_offset

	var visualizer: EditorTriggerVisualizer = _get_visualizer_node()
	if is_instance_valid(visualizer):
		visualizer.shape_type = shape_type
		visualizer.show_in_game = show_in_game
		visualizer.trigger_size = trigger_size
		visualizer.trigger_color = trigger_color
		visualizer.outline_color = outline_color
		visualizer.x_ray_mode = x_ray_mode
		visualizer.show_orientation = show_orientation
		visualizer.show_metric_dimensions = show_metric_dimensions
		visualizer.trigger_text = trigger_text
		visualizer.position = trigger_offset


## Safely retrieves child [CollisionShape3D] instance.
func _get_collision_shape() -> CollisionShape3D:
	var col: CollisionShape3D = (
		get_node_or_null("CollisionShape3D")
		if get_node_or_null("CollisionShape3D") is CollisionShape3D
		else null
	)
	if not is_instance_valid(col):
		for child: Node in get_children():
			if child is CollisionShape3D:
				col = child as CollisionShape3D
				break
	return col


## Safely retrieves child [EditorTriggerVisualizer] node.
func _get_visualizer_node() -> EditorTriggerVisualizer:
	var visualizer: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visualizer):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
	return visualizer


## Evaluates player entry, formats template tokens, and fires hints.
func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return

	if trigger_once and _triggered:
		return

	_triggered = true
	var raw_message: String = _get_raw_message()
	var formatted_message: String = _format_message_with_keys(raw_message)

	print(
		"HintTrigger: Activated by ",
		body.name,
		" | Emitting: '",
		formatted_message,
		"' | Screen: ",
		show_on_screen
	)

	if show_on_screen:
		Events.hint_requested.emit(formatted_message, duration)

	print("HintTrigger: Sending text to custom TTSManager...")
	TTSManager.speak(formatted_message, self)


## Resolves template prompt text matching assigned [member hint_type].
func _get_raw_message() -> String:
	match hint_type:
		HintType.INTERACT:
			return "Press [interact] to interact."
		HintType.JUMP:
			return "Press [jump] to jump."
		HintType.CROUCH:
			return "Press [crouch] to crouch."
		HintType.SPRINT:
			return "Press [sprint] to sprint."
		HintType.FLASHLIGHT:
			return "Press [flashlight] to toggle flashlight."
		HintType.ZOOM:
			return "Press [zoom] to zoom in."
		HintType.CUSTOM:
			return custom_message
		_:
			return ""


## Replaces bracket action tokens with key strings from [InputMap].
func _format_message_with_keys(text: String) -> String:
	print("HintTrigger: _format_message_with_keys() - Parsing keys...")
	var final_text: String = text
	var actions: Array[String] = [
		"forward",
		"backward",
		"left",
		"right",
		"jump",
		"crouch",
		"sprint",
		"interact",
		"flashlight",
		"zoom"
	]

	for action: String in actions:
		var bracket_action: String = "[" + action + "]"
		if final_text.contains(bracket_action):
			var events: Array[InputEvent] = InputMap.action_get_events(action)
			var key_name: String = "Unassigned"

			if not events.is_empty():
				var ev: InputEvent = events[0]

				if ev is InputEventKey:
					var key_ev: InputEventKey = ev if ev is InputEventKey else null
					if key_ev.physical_keycode != KEY_NONE:
						key_name = OS.get_keycode_string(key_ev.physical_keycode)
					else:
						key_name = OS.get_keycode_string(key_ev.keycode)
				elif ev is InputEventMouseButton:
					var mouse_ev: InputEventMouseButton = (
						ev if ev is InputEventMouseButton else null
					)
					match mouse_ev.button_index:
						MOUSE_BUTTON_LEFT:
							key_name = "Left Click"
						MOUSE_BUTTON_RIGHT:
							key_name = "Right Click"
						MOUSE_BUTTON_MIDDLE:
							key_name = "Middle Click"
						_:
							key_name = "Mouse " + str(mouse_ev.button_index)
				else:
					key_name = ev.as_text().get_slice(" (", 0).strip_edges()

			final_text = final_text.replace(bracket_action, key_name)

	return final_text
