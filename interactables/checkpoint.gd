@tool
## Controls checkpoint triggers, in-game holograms, and level design editor visualizers.
## Syncs collision boundaries with an integrated [EditorTriggerVisualizer] gizmo.
class_name Checkpoint
extends Area3D

@export_group("Trigger Volume")
## Geometric shape type utilized for collision and visual debug bounds.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_trigger_shape()
			_update_visualizer()

## Extents of the trigger collision volume and debug visualizer mesh.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree():
			_update_trigger_shape()
			_update_visualizer()

## Local offset applied to both the collision shape and the visualizer node.
@export var trigger_offset: Vector3 = Vector3(0.0, 1.0, 0.0):
	set(value):
		trigger_offset = value
		if is_inside_tree():
			_update_trigger_shape()
			_update_visualizer()

@export_group("Trigger Debug Visualizer")
## Toggles runtime visibility of the editor trigger visualizer mesh.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_visualizer()

## Debug tint color applied to the volumetric inner fill.
@export var trigger_color: Color = Color(0.1, 0.5, 0.9, 0.25):
	set(value):
		trigger_color = value
		if is_inside_tree() and not is_activated:
			_update_visualizer()

## Edge color applied to the wireframe bounding cage and orientation arrow.
@export var outline_color: Color = Color(0.3, 0.8, 1.0, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree() and not is_activated:
			_update_visualizer()

## Allows the visualizer to remain visible through level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_visualizer()

## Displays an arrow pointing along -Z indicating player entry heading.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_visualizer()

## Appends metric dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_visualizer()

## Debug text displayed on the 3D billboard visualizer when inactive.
@export var trigger_text: String = "CHECKPOINT":
	set(value):
		trigger_text = value
		if is_inside_tree() and not is_activated:
			_update_visualizer()

## Debug fill color applied to the visualizer when activated.
@export var active_color: Color = Color(0.0, 0.9, 0.4, 0.35):
	set(value):
		active_color = value
		if is_inside_tree() and is_activated:
			_update_visualizer()

## Outline edge color applied to the visualizer when activated.
@export var active_outline_color: Color = Color(0.2, 1.0, 0.5, 0.95):
	set(value):
		active_outline_color = value
		if is_inside_tree() and is_activated:
			_update_visualizer()

## Debug text displayed on the 3D billboard visualizer when activated.
@export var active_text: String = "CHECKPOINT ACTIVATED":
	set(value):
		active_text = value
		if is_inside_tree() and is_activated:
			_update_visualizer()

@export_group("Hologram Settings")
## In-game floating [Label3D] text displayed over the hologram.
@export var label_text: String = "Checkpoint":
	set(value):
		label_text = value
		if is_inside_tree():
			_update_hologram()

## Primary emission color for the scrolling hologram lines.
@export var line_color: Color = Color.GREEN:
	set(value):
		line_color = value
		if is_inside_tree():
			_update_hologram()

## Translucent albedo base color of the in-game hologram cylinder.
@export var base_color: Color = Color(0.0, 0.2, 0.8, 0.1):
	set(value):
		base_color = value
		if is_inside_tree():
			_update_hologram()

## Vertical scrolling velocity of the in-game hologram effect.
@export var speed: float = 1.0:
	set(value):
		speed = value
		if is_inside_tree():
			_update_hologram()

## Total count of horizontal scanlines drawn across the hologram.
@export var line_count: float = 2.0:
	set(value):
		line_count = value
		if is_inside_tree():
			_update_hologram()

## Normalized width and thickness of the scrolling hologram stripes.
@export_range(0.01, 1.0) var line_thickness: float = 0.1:
	set(value):
		line_thickness = value
		if is_inside_tree():
			_update_hologram()

## Glow intensity factor amplifying emission on hologram stripes.
@export var glow_multiplier: float = 2.0:
	set(value):
		glow_multiplier = value
		if is_inside_tree():
			_update_hologram()

@export_group("Audio Settings")
## The [AudioStream] sound played upon first checkpoint activation.
@export var activation_sound: AudioStream

## Child [AudioStreamPlayer3D] used for checkpoint audio cues.
@onready var audio_player: AudioStreamPlayer3D = (
	get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
)

## Tracks whether this checkpoint is currently the active respawn point.
var is_activated: bool = false

## Original hologram label text cached to restore visual state if deactivated.
var original_label_text: String = ""

## Original hologram speed cached to restore visual state if deactivated.
var original_speed: float = 1.0

## Original line thickness cached to restore visual state if deactivated.
var original_line_thickness: float = 0.1

## Original base color cached to restore visual state if deactivated.
var original_base_color: Color = Color(0.0, 0.2, 0.8, 0.1)


## Initializes shape, syncs visualizer and hologram, and connects callbacks.
func _ready() -> void:
	print("Checkpoint: Initializing checkpoint instance at ", name)
	_update_trigger_shape()
	_update_visualizer()
	_update_hologram()

	if not Engine.is_editor_hint():
		add_to_group(&"checkpoints")
		original_label_text = label_text
		original_speed = speed
		original_line_thickness = line_thickness
		original_base_color = base_color

		if not body_entered.is_connected(_on_body_entered):
			body_entered.connect(_on_body_entered)


## Synchronizes dimensions and position of the child [CollisionShape3D].
func _update_trigger_shape() -> void:
	if not is_inside_tree():
		return

	var col: CollisionShape3D = _get_collision_shape()
	if not is_instance_valid(col):
		return

	if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
		if not col.shape is BoxShape3D:
			col.shape = BoxShape3D.new()
		else:
			col.shape = col.shape.duplicate()
		var box: BoxShape3D = col.shape as BoxShape3D
		box.size = trigger_size
	elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
		if not col.shape is SphereShape3D:
			col.shape = SphereShape3D.new()
		else:
			col.shape = col.shape.duplicate()
		var sphere: SphereShape3D = col.shape as SphereShape3D
		sphere.radius = trigger_size.x * 0.5

	col.position = trigger_offset


## Synchronizes shape, wireframes, gizmos, and colors with [EditorTriggerVisualizer].
func _update_visualizer() -> void:
	if not is_inside_tree():
		return

	var vis: EditorTriggerVisualizer = _get_visualizer()
	if not is_instance_valid(vis):
		return

	vis.shape_type = shape_type
	vis.trigger_size = trigger_size
	vis.show_in_game = show_in_game
	vis.x_ray_mode = x_ray_mode
	vis.show_orientation = show_orientation
	vis.show_metric_dimensions = show_metric_dimensions
	vis.position = trigger_offset

	if is_activated:
		vis.trigger_color = active_color
		vis.outline_color = active_outline_color
		vis.trigger_text = active_text
	else:
		vis.trigger_color = trigger_color
		vis.outline_color = outline_color
		vis.trigger_text = trigger_text


## Passes color, scanline, and speed properties to the hologram shader.
func _update_hologram() -> void:
	if not is_inside_tree():
		return

	var mesh: MeshInstance3D = _get_hologram_mesh()
	if is_instance_valid(mesh):
		mesh.set_instance_shader_parameter("line_color", line_color)
		mesh.set_instance_shader_parameter("base_color", base_color)
		mesh.set_instance_shader_parameter("speed", speed)
		mesh.set_instance_shader_parameter("line_count", line_count)
		mesh.set_instance_shader_parameter("line_thickness", line_thickness)
		mesh.set_instance_shader_parameter("glow_multiplier", glow_multiplier)

	var label: Label3D = _get_hologram_label()
	if is_instance_valid(label):
		label.text = label_text


## Safely retrieves the child [CollisionShape3D] instance.
func _get_collision_shape() -> CollisionShape3D:
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		for child: Node in get_children():
			if child is CollisionShape3D:
				col = child
				break
	return col


## Safely retrieves the child [EditorTriggerVisualizer] instance.
func _get_visualizer() -> EditorTriggerVisualizer:
	var vis: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(vis):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				vis = child
				break
	return vis


## Safely retrieves the child hologram [MeshInstance3D] instance.
func _get_hologram_mesh() -> MeshInstance3D:
	return get_node_or_null("HologramMesh") as MeshInstance3D


## Safely retrieves the child floating [Label3D] node.
func _get_hologram_label() -> Label3D:
	return get_node_or_null("Label3D") as Label3D


## Evaluates physics body entry to activate checkpoint for the player.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.name == "Player" or body.is_in_group("Player"):
		if "noclip" in body and body.get("noclip") == true:
			return

		if not is_activated:
			activate_checkpoint()


## Activates checkpoint, updates [SaveManager] position, and updates visuals.
func activate_checkpoint() -> void:
	print("Checkpoint: Activating checkpoint at ", global_position)
	get_tree().call_group(&"checkpoints", "deactivate_checkpoint")

	is_activated = true
	SaveManager.last_checkpoint_pos = global_position
	print("Checkpoint: Saved player position -> ", SaveManager.last_checkpoint_pos)

	label_text = "Checkpoint Activated"
	speed = -1.0
	line_thickness = 0.8
	base_color = Color(0.0, 0.906, 0.471, 0.102)
	_update_hologram()
	_update_visualizer()

	if is_instance_valid(audio_player) and activation_sound:
		print("Checkpoint: Playing activation sound.")
		audio_player.stream = activation_sound
		audio_player.play()
	else:
		print("Checkpoint: Warning - No audio_player or activation_sound assigned.")


## Deactivates checkpoint and restores cached original visual parameters.
func deactivate_checkpoint() -> void:
	if not is_activated:
		return

	print("Checkpoint: Deactivating checkpoint at ", global_position)
	is_activated = false

	label_text = original_label_text
	speed = original_speed
	line_thickness = original_line_thickness
	base_color = original_base_color
	_update_hologram()
	_update_visualizer()
