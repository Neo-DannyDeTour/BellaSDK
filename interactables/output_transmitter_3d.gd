@tool
class_name OutputTransmitter3D
extends Node3D

signal activated
signal deactivated

## The list of nodes that this transmitter sends its signals or progress updates to.
@export var targets: Array[Node3D]

## A state flag marking whether the transmitter is actively outputting power/signal.
var is_active: bool = false
## The immediate mesh instance used to draw editor debug lines to all target nodes.
var debug_line: MeshInstance3D


func _ready() -> void:
	set_process(Engine.is_editor_hint())


func _process(_delta: float) -> void:
	_draw_connection_line()


func power_on() -> void:
	if not is_active:
		print("OutputTransmitter3D: State changed to ON. Energizing targets.")
		is_active = true
		activated.emit()
		_energize_targets()


func power_off() -> void:
	if is_active:
		print("OutputTransmitter3D: State changed to OFF. De-energizing targets.")
		is_active = false
		deactivated.emit()
		_deenergize_targets()


func _energize_targets() -> void:
	for target: Node3D in targets:
		if is_instance_valid(target):
			var comp: Node = target.get_node_or_null("PowerComponent")
			if is_instance_valid(comp) and comp.has_method("add_power"):
				comp.add_power()
			elif target.has_method("power_on"):
				target.power_on()


func _deenergize_targets() -> void:
	for target: Node3D in targets:
		if is_instance_valid(target):
			var comp: Node = target.get_node_or_null("PowerComponent")
			if is_instance_valid(comp) and comp.has_method("remove_power"):
				comp.remove_power()
			elif target.has_method("power_off"):
				target.power_off()


func _draw_connection_line() -> void:
	if not targets or targets.is_empty():
		if is_instance_valid(debug_line):
			debug_line.queue_free()
			debug_line = null
		return

	if not is_instance_valid(debug_line):
		debug_line = MeshInstance3D.new()
		add_child(debug_line)

		var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
		debug_line.mesh = immediate_mesh

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color.RED
		debug_line.material_override = mat

	var mesh: ImmediateMesh = debug_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	for target: Node3D in targets:
		if is_instance_valid(target):
			mesh.surface_add_vertex(Vector3.ZERO)
			mesh.surface_add_vertex(to_local(target.global_position))

	mesh.surface_end()


func transmit_progress(value: float) -> void:
	for target: Node3D in targets:
		if is_instance_valid(target) and target.has_method("set_progress"):
			target.set_progress(value)
