@tool
## Trigger volume requesting camera trauma through [CameraShakeManager].
class_name ScreenshakeEffect
extends Area3D

## Dimensions of the trigger area visualizer and collision hull.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_visuals()

## Wireframe color of the volume visualizer rendered in editor.
@export var trigger_color: Color = Color(1.0, 0.5, 0.0, 0.8):
	set(value):
		trigger_color = value
		_update_visuals()

## Text displayed above the trigger in the editor viewport.
@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		_update_visuals()

## Dictates whether the screen shake triggers once or repetitively.
@export var trigger_once: bool = true

## Peak trauma intensity requested from [CameraShakeManager].
@export_range(0.0, 16.0) var shake_intensity: float = 4.0

## Duration in seconds of sustained screen shake trauma.
@export var shake_duration: float = 2.5

## Tracks if the trigger has already activated to enforce single-fire.
var _triggered: bool = false

## Cached collision shape child defining the trigger bounds.
var _collision_shape: CollisionShape3D = null


## Configures player-only physics mask and connects body entry signal.
func _ready() -> void:
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if Engine.is_editor_hint():
		_update_visuals()
		return

	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER

	var editor_mesh: EditorTriggerVisualizer = _get_visualizer()
	if editor_mesh != null:
		editor_mesh.queue_free()

	body_entered.connect(_on_body_entered)


## Updates editor wireframe visualizer and collision box dimensions.
func _update_visuals() -> void:
	if not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D

	if is_instance_valid(_collision_shape):
		if _collision_shape.shape == null:
			_collision_shape.shape = BoxShape3D.new()
		if Engine.is_editor_hint() and not _collision_shape.shape.resource_local_to_scene:
			_collision_shape.shape = _collision_shape.shape.duplicate()
			_collision_shape.shape.resource_local_to_scene = true
		if _collision_shape.shape is BoxShape3D:
			(_collision_shape.shape as BoxShape3D).size = trigger_size

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(visual):
		visual.trigger_size = trigger_size
		visual.trigger_color = trigger_color
		visual.trigger_text = trigger_text


## Locates [EditorTriggerVisualizer] child node for editor previews.
func _get_visualizer() -> EditorTriggerVisualizer:
	for child: Node in get_children():
		if child is EditorTriggerVisualizer:
			return child as EditorTriggerVisualizer
	return null


## Requests trauma from [CameraShakeManager] when player enters volume.
func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	if trigger_once and _triggered:
		return

	_triggered = true
	print("ScreenshakeEffect: Activated by: ", body.name, ". Adding trauma.")
	var normalized_trauma: float = clampf(shake_intensity / 16.0, 0.0, 1.0)
	CameraShakeManager.add_trauma(normalized_trauma)
	Events.screenshake_requested.emit(shake_intensity, shake_duration)
