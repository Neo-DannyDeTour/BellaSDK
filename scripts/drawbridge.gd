@tool
extends Node3D

@export_category("Bridge Setup")
@export var bridge_size: Vector3 = Vector3(2.0, 0.2, 5.0):
	set(value):
		bridge_size = value
		_update_bridge_shape()

@export_range(-1.0, 1.0) var hinge_offset: float = -1.0:
	set(value):
		hinge_offset = value
		_update_bridge_shape()

@export_category("Debug Visuals")
@export var show_debug_pin: bool = true:
	set(value):
		show_debug_pin = value
		_update_bridge_shape()

@export var pin_extension: float = 0.5:
	set(value):
		pin_extension = value
		_update_bridge_shape()

@export_category("Puzzle Logic")
@export var ropes: Array[NodePath]

var intact_ropes: int = 0
var bridge_fallen: bool = false

@onready var bridge: RigidBody3D = $TheBridge


func _ready() -> void:
	_update_bridge_shape()

	if has_node("HingeAnchor"):
		var anchor := get_node("HingeAnchor")
		if anchor is CollisionObject3D:
			anchor.collision_layer = 0
			anchor.collision_mask = 0

	if not Engine.is_editor_hint() and has_node("DebugPin"):
		get_node("DebugPin").hide()

	if Engine.is_editor_hint():
		return

	for rope_path in ropes:
		var rope_root := get_node_or_null(rope_path)
		if rope_root:
			# Tell the script to hunt for the signal inside the rope!
			var signal_node := _find_signal_source(rope_root, "rope_broken")
			if signal_node:
				intact_ropes += 1
				signal_node.rope_broken.connect(_on_rope_broken)

	print("Bridge initialized. Holding on by ", intact_ropes, " ropes.")


func _find_signal_source(parent: Node, sig_name: String) -> Node:
	if parent.has_signal(sig_name):
		return parent

	for child in parent.get_children():
		var found := _find_signal_source(child, sig_name)
		if found:
			return found

	return null


func _update_bridge_shape() -> void:
	if not is_node_ready():
		return

	if bridge:
		bridge.position = Vector3.ZERO
		bridge.rotation_degrees = Vector3.ZERO

	var z_shift := (bridge_size.z / 2.0) * -hinge_offset
	var visual_offset := Vector3(0, 0, z_shift)

	var mesh_instance := $TheBridge/MeshInstance3D
	if mesh_instance:
		if not mesh_instance.mesh is BoxMesh:
			mesh_instance.mesh = BoxMesh.new()
		mesh_instance.mesh = mesh_instance.mesh.duplicate()
		mesh_instance.mesh.size = bridge_size
		mesh_instance.position = visual_offset

	var collision := $TheBridge/CollisionShape3D
	if collision:
		if not collision.shape is BoxShape3D:
			collision.shape = BoxShape3D.new()
		collision.shape = collision.shape.duplicate()
		collision.shape.size = bridge_size
		collision.position = visual_offset

	# NOTE: Joint code is gone! It relies purely on the saved .tscn file now.

	_draw_debug_pin()


func _draw_debug_pin() -> void:
	if not is_node_ready():
		return
	if not show_debug_pin:
		if has_node("DebugPin"):
			get_node("DebugPin").queue_free()
		return

	var debug_pin: MeshInstance3D
	if not has_node("DebugPin"):
		debug_pin = MeshInstance3D.new()
		debug_pin.name = "DebugPin"
		add_child(debug_pin)
	else:
		debug_pin = get_node("DebugPin")

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = bridge_size.x + pin_extension

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cyl.material = mat

	debug_pin.mesh = cyl
	debug_pin.position = Vector3.ZERO
	debug_pin.rotation_degrees = Vector3(0, 0, 90)


func _on_rope_broken() -> void:
	if Engine.is_editor_hint():
		return

	intact_ropes -= 1
	if intact_ropes <= 0 and not bridge_fallen:
		drop_bridge()


func drop_bridge() -> void:
	if Engine.is_editor_hint():
		return

	bridge_fallen = true
	bridge.set_deferred("freeze", false)
	bridge.set_deferred("sleeping", false)
	bridge.apply_central_impulse(Vector3.DOWN * 0.1)


func _on_ground_lock_trigger_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body == bridge and bridge_fallen:
		bridge.set_deferred("freeze", true)
		print("Bridge Locked!")
