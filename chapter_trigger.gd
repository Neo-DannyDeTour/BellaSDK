@tool
extends Area3D

@export_category("Level Design")
## Changes the size of the trigger box directly from the inspector.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		_update_bounds()

## Sets the color of the visual box in the editor to make it highly visible.
@export var editor_color: Color = Color(1.0, 0.0, 0.0, 0.4):
	set(value):
		editor_color = value
		_update_bounds()

@export_category("Chapter Settings")
@export var chapter_name: String = "Chapter 1"
@export var text_color: Color = Color.WHITE
@export var animation_style: Events.ChapterAnimStyle = Events.ChapterAnimStyle.SIMPLE
@export var display_duration: float = 3.0

var _has_triggered: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	print("ChapterTrigger ready: ", chapter_name)
	
	# Optimization: Delete the visual mesh so it costs zero performance in the compiled game
	var editor_mesh: MeshInstance3D = get_node_or_null("EditorVisual")
	if editor_mesh:
		editor_mesh.queue_free()
		
	body_entered.connect(_on_body_entered)


func _update_bounds() -> void:
	# 1. Update the invisible physics collision shape
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if col:
		if not col.shape:
			col.shape = BoxShape3D.new()
			
		# Duplicate the shape so resizing one trigger doesn't resize all of them
		if not col.shape.resource_local_to_scene:
			col.shape = col.shape.duplicate()
			col.shape.resource_local_to_scene = true
			
		if col.shape is BoxShape3D:
			var box: BoxShape3D = col.shape as BoxShape3D
			box.size = trigger_size
			
	# 2. Update the visible editor mesh and force the color
	var mesh: MeshInstance3D = get_node_or_null("EditorVisual")
	if mesh and mesh.mesh is BoxMesh:
		var box_mesh: BoxMesh = mesh.mesh as BoxMesh
		box_mesh.size = trigger_size
		
		# Apply an unshaded, transparent material so it ignores lighting and stays bright
		var mat: StandardMaterial3D = mesh.material_override as StandardMaterial3D
		if not mat:
			mat = StandardMaterial3D.new()
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh.material_override = mat
			
		mat.albedo_color = editor_color


func _on_body_entered(body: Node3D) -> void:
	# Prevent the editor from executing gameplay code
	if Engine.is_editor_hint():
		return
		
	if not body.is_in_group("player"):
		return
		
	if _has_triggered:
		return

	_has_triggered = true
	print("Player entered chapter volume. Emitting signal for: ", chapter_name)
	Events.chapter_triggered.emit(chapter_name, animation_style as int, display_duration, text_color)
