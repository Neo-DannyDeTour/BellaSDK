@tool
extends Area3D

@export_category("Level Design")

## Defines the physical dimensions of the trigger area and its visual representation.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_visuals()

## Sets the visual color of the trigger box in the editor to help differentiate trigger types.
@export var trigger_color: Color = Color(1.0, 0.5, 0.0, 0.8):
	set(value):
		trigger_color = value
		_update_visuals()

## Determines the text displayed above the trigger in the editor for quick identification.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		_update_visuals()

@export_category("Screenshake Settings")

## Controls whether the screen shake can only occur once or multiple times.
@export var trigger_once: bool = true

## Dictates the strength of the screen shake effect when a player enters the area.
@export_range(0.0, 16.0) var shake_intensity: float = 4.0

## Specifies how long the screen shake effect lasts in seconds.
@export var shake_duration: float = 2.5

## Tracks if the trigger has already been activated to handle 'trigger_once' logic.
var _triggered: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		_update_visuals()
		return

	var editor_mesh: EditorTriggerVisualizer = _get_visualizer()
	if editor_mesh:
		editor_mesh.queue_free()

	body_entered.connect(_on_body_entered)


func _update_visuals() -> void:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		if not col.shape:
			col.shape = BoxShape3D.new()

		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true

		if col.shape is BoxShape3D:
			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = trigger_size

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if visual:
		visual.trigger_size = trigger_size
		visual.trigger_color = trigger_color
		visual.trigger_text = trigger_text


func _get_visualizer() -> EditorTriggerVisualizer:
	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			return child as EditorTriggerVisualizer
	return null


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	if trigger_once and _triggered:
		return

	_triggered = true
	print("ScreenshakeTrigger activated by: ", body.name, ". Emitting event.")
	Events.screenshake_requested.emit(shake_intensity, shake_duration)
