@tool
extends Area3D

@export_category("Level Design")
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_visuals()

@export var trigger_color: Color = Color(1.0, 0.5, 0.0, 0.8):
	set(value):
		trigger_color = value
		_update_visuals()

@export var trigger_text: String = "TRIGGER":
	set(value):
		trigger_text = value
		_update_visuals()


@export_category("Screenshake Settings")
@export var trigger_once: bool = true
@export_range(0.0, 16.0) var shake_intensity: float = 4.0
@export var shake_duration: float = 2.5

var _triggered: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	var editor_mesh: Node3D = get_node_or_null("EditorVisual")
	if editor_mesh:
		editor_mesh.queue_free()
		
	body_entered.connect(_on_body_entered)


func _update_visuals() -> void:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if col:
		if not col.shape:
			col.shape = BoxShape3D.new()
			
		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			
		if col.shape is BoxShape3D:
			var box := col.shape as BoxShape3D
			box.size = trigger_size
			
	var visual: Node3D = get_node_or_null("EditorVisual")
	if visual:
		# Using .set() safely pushes the values down even if the class cache is broken
		visual.set("trigger_size", trigger_size)
		visual.set("trigger_color", trigger_color)
		visual.set("trigger_text", trigger_text)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
		
	if trigger_once and _triggered:
		return

	_triggered = true
	print("ScreenshakeTrigger activated by: ", body.name, ". Emitting event.")
	Events.screenshake_requested.emit(shake_intensity, shake_duration)
