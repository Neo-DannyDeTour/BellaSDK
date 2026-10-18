## Physical drawbridge unlocking physics constraints to swing downward when ropes break.
@tool
class_name Drawbridge
extends Node3D

@export_category("Bridge Setup")

## Dimensions of the bridge platform in meters.
@export var bridge_size: Vector3 = Vector3(2.0, 0.2, 5.0):
	set(value):
		bridge_size = value
		if is_instance_valid(self) and is_inside_tree() and is_node_ready():
			_update_bridge_shape()

## Offset ratio of rotational hinge relative to length.
@export_range(-1.0, 1.0) var hinge_offset: float = -1.0:
	set(value):
		hinge_offset = value
		if is_instance_valid(self) and is_inside_tree() and is_node_ready():
			_update_bridge_shape()

## Array of marker nodes that should stick to and swing with the bridge deck.
@export var bridge_markers: Array[Node3D] = []

@export_category("Debug Visuals")

## Shows red cylinder indicating bridge hinge axis in editor.
@export var show_debug_pin: bool = true:
	set(value):
		show_debug_pin = value
		if is_instance_valid(self) and is_inside_tree() and is_node_ready():
			_update_bridge_shape()

## Distance debug pin extends past bridge sides.
@export var pin_extension: float = 0.5:
	set(value):
		pin_extension = value
		if is_instance_valid(self) and is_inside_tree() and is_node_ready():
			_update_bridge_shape()

@export_category("Puzzle Logic")

## Array of paths pointing to rope nodes suspending bridge.
@export var ropes: Array[NodePath] = []

var intact_ropes: int = 0
var bridge_fallen: bool = false

@onready var bridge: RigidBody3D = $TheBridge if $TheBridge is RigidBody3D else null


## Re-parents bridge markers so they inherit physics motion without editable children.
func _setup_bridge_markers() -> void:
	print("Drawbridge: _setup_bridge_markers() - Attaching markers to bridge body.")
	if not is_instance_valid(bridge):
		return

	for marker: Node3D in bridge_markers:
		if is_instance_valid(marker):
			var global_trans: Transform3D = marker.global_transform
			marker.reparent(bridge, true)
			marker.global_transform = global_trans


## Connects rope signals and initializes physical state.
func _ready() -> void:
	print("Drawbridge: _ready() - Initializing bridge instance.")
	_update_bridge_shape()

	if not Engine.is_editor_hint():
		_setup_bridge_markers()

	var anchor: CollisionObject3D = (
		get_node_or_null("HingeAnchor")
		if get_node_or_null("HingeAnchor") is CollisionObject3D
		else null
	)
	if is_instance_valid(anchor):
		anchor.collision_layer = 0
		anchor.collision_mask = 0

	var debug_pin: Node3D = (
		get_node_or_null("DebugPin") if get_node_or_null("DebugPin") is Node3D else null
	)
	if is_instance_valid(debug_pin) and not Engine.is_editor_hint():
		debug_pin.hide()

	if Engine.is_editor_hint():
		return

	for rope_path: NodePath in ropes:
		var rope_root: Node = get_node_or_null(rope_path)
		if is_instance_valid(rope_root):
			var signal_node: Node = _find_signal_source(rope_root, &"rope_broken")
			if is_instance_valid(signal_node):
				intact_ropes += 1
				if not signal_node.is_connected(&"rope_broken", _on_rope_broken):
					signal_node.connect(&"rope_broken", _on_rope_broken)

	print("Drawbridge: Initialized. Holding on by ", intact_ropes, " ropes.")


## Recursively locates child node declaring target signal.
func _find_signal_source(parent: Node, sig_name: StringName) -> Node:
	if not is_instance_valid(parent):
		return null

	if parent.has_signal(sig_name):
		return parent

	for child: Node in parent.get_children():
		var found: Node = _find_signal_source(child, sig_name)
		if is_instance_valid(found):
			return found

	return null


## Dynamically adjusts mesh and collision bounds in editor.
func _update_bridge_shape() -> void:
	print("Drawbridge: _update_bridge_shape() - Updating dimensions.")
	if not is_node_ready():
		return

	if is_instance_valid(bridge):
		bridge.position = Vector3.ZERO
		bridge.rotation_degrees = Vector3.ZERO

	var z_shift: float = (bridge_size.z * 0.5) * -hinge_offset
	var visual_offset: Vector3 = Vector3(0.0, 0.0, z_shift)

	var mesh_instance: MeshInstance3D = (
		get_node_or_null("TheBridge/MeshInstance3D") as MeshInstance3D
	)
	if is_instance_valid(mesh_instance):
		if not mesh_instance.mesh is BoxMesh:
			mesh_instance.mesh = BoxMesh.new()
		else:
			mesh_instance.mesh = mesh_instance.mesh.duplicate() as BoxMesh

		var box_mesh: BoxMesh = mesh_instance.mesh if mesh_instance.mesh is BoxMesh else null
		box_mesh.size = bridge_size
		mesh_instance.position = visual_offset

	var collision: CollisionShape3D = (
		get_node_or_null("TheBridge/CollisionShape3D") as CollisionShape3D
	)
	if is_instance_valid(collision):
		if not collision.shape is BoxShape3D:
			collision.shape = BoxShape3D.new()
		else:
			collision.shape = collision.shape.duplicate() as BoxShape3D

		var box_shape: BoxShape3D = collision.shape if collision.shape is BoxShape3D else null
		box_shape.size = bridge_size
		collision.position = visual_offset

	_draw_debug_pin()


## Generates or updates red hinge indicator in editor viewport.
func _draw_debug_pin() -> void:
	if not is_node_ready():
		return

	var existing_pin: Node3D = (
		get_node_or_null("DebugPin") if get_node_or_null("DebugPin") is Node3D else null
	)

	if not show_debug_pin:
		if is_instance_valid(existing_pin):
			existing_pin.queue_free()
		return

	var debug_pin: MeshInstance3D
	if not is_instance_valid(existing_pin):
		debug_pin = MeshInstance3D.new()
		debug_pin.name = "DebugPin"
		add_child(debug_pin)
	else:
		debug_pin = existing_pin as MeshInstance3D

	if is_instance_valid(debug_pin):
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.04
		cyl.bottom_radius = 0.04
		cyl.height = bridge_size.x + pin_extension

		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color.RED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		cyl.material = mat

		debug_pin.mesh = cyl
		debug_pin.position = Vector3.ZERO
		debug_pin.rotation_degrees = Vector3(0.0, 0.0, 90.0)


## Tracks severed ropes and triggers drop when all ropes break.
func _on_rope_broken() -> void:
	print("Drawbridge: _on_rope_broken() - Rope severed.")
	if Engine.is_editor_hint():
		return

	intact_ropes -= 1
	if intact_ropes <= 0 and not bridge_fallen:
		drop_bridge()


## Unfreezes bridge physics body and initiates downward swing.
func drop_bridge() -> void:
	print("Drawbridge: drop_bridge() - Dropping bridge physics body.")
	if Engine.is_editor_hint():
		return

	bridge_fallen = true
	if is_instance_valid(bridge):
		bridge.set_deferred("freeze", false)
		bridge.set_deferred("sleeping", false)
		bridge.apply_central_impulse(Vector3.DOWN * 0.1)


## Locks bridge in place once trigger zone confirms ground impact.
func _on_ground_lock_trigger_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body == bridge and bridge_fallen:
		print("Drawbridge: Ground impact detected. Freezing bridge.")
		if is_instance_valid(bridge):
			bridge.set_deferred("freeze", true)
