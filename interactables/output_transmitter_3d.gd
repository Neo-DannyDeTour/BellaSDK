@tool
## Generic signal router bridging interactable mechanisms with target nodes.
class_name OutputTransmitter3D
extends Node3D

## Emitted when transmitter sends power to targets.
signal activated

## Emitted when transmitter stops sending power.
signal deactivated

## Targets receiving power signals from transmitter.
@export var targets: Array[Node3D] = []:
	set(value):
		targets = value
		if Engine.is_editor_hint():
			_draw_connection_line()

## Active state flag for outputting power.
var is_active: bool = false

## Debug mesh displaying line links in editor.
var debug_line: MeshInstance3D


## Enables editor frame processing for debug visuals.
func _ready() -> void:
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint():
		_draw_connection_line()


## Cleans up editor debug nodes when detached.
func _exit_tree() -> void:
	if is_instance_valid(debug_line):
		debug_line.queue_free()
		debug_line = null


## Updates target connection lines within editor.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_draw_connection_line()


## Activates transmitter and energizes all targets.
func power_on() -> void:
	if not is_active:
		print("OutputTransmitter3D: Power ON -> Energizing targets.")
		is_active = true
		activated.emit()
		_energize_targets()


## Deactivates transmitter and cuts power to targets.
func power_off() -> void:
	if is_active:
		print("OutputTransmitter3D: Power OFF -> De-energizing targets.")
		is_active = false
		deactivated.emit()
		_deenergize_targets()


## Invokes power activation hooks on valid targets.
func _energize_targets() -> void:
	for target: Node3D in targets:
		if not is_instance_valid(target):
			continue
		var comp: Node = target.get_node_or_null("PowerComponent")
		if is_instance_valid(comp) and comp.has_method("add_power"):
			comp.call("add_power")
		elif target.has_method("power_on"):
			target.call("power_on")


## Invokes power deactivation hooks on valid targets.
func _deenergize_targets() -> void:
	for target: Node3D in targets:
		if not is_instance_valid(target):
			continue
		var comp: Node = target.get_node_or_null("PowerComponent")
		if is_instance_valid(comp) and comp.has_method("remove_power"):
			comp.call("remove_power")
		elif target.has_method("power_off"):
			target.call("power_off")


## Draws debug line connections to all targets.
func _draw_connection_line() -> void:
	if targets.is_empty():
		if is_instance_valid(debug_line):
			debug_line.queue_free()
			debug_line = null
		return

	if not is_instance_valid(debug_line):
		debug_line = MeshInstance3D.new()
		debug_line.name = "DebugLinkLine"
		debug_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(debug_line)

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 100
		mat.albedo_color = Color.RED
		debug_line.material_override = mat

		var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
		debug_line.mesh = immediate_mesh

	var mesh: ImmediateMesh = debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for target: Node3D in targets:
		if is_instance_valid(target) and target.is_inside_tree():
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(to_local(target.global_position))

	mesh.surface_end()


## Routes normalized progress weight to targets.
func transmit_progress(value: float) -> void:
	for target: Node3D in targets:
		if is_instance_valid(target) and target.has_method("set_progress"):
			target.call("set_progress", value)
