@tool
## Destructible taut rope snapping into dynamic catenary [PhysicsCable3D] strands when shot.
class_name BreakableRope3D
extends StaticBody3D

## Emitted when the rope snaps after sustaining lethal damage.
signal rope_broken

## Bitmask value selecting physics layer 3 (Interactive).
const INTERACTIVE_LAYER_MASK: int = 1 << 2

@export_category("Anchors")
## Starting anchor point [Node3D] where the rope originates.
@export var start_anchor: Node3D:
	set(value):
		start_anchor = value
		if is_instance_valid(self) and is_inside_tree():
			_update_rope_geometry()

## Ending anchor point [Node3D] where the rope terminates.
@export var end_anchor: Node3D:
	set(value):
		end_anchor = value
		if is_instance_valid(self) and is_inside_tree():
			_update_rope_geometry()

## Local coordinate fallback for the start point if [member start_anchor] is unset.
@export var local_start_point: Vector3 = Vector3.ZERO:
	set(value):
		local_start_point = value
		if is_instance_valid(self) and is_inside_tree():
			_update_rope_geometry()

## Local coordinate fallback for the end point if [member end_anchor] is unset.
@export var local_end_point: Vector3 = Vector3(0.0, -3.0, 0.0):
	set(value):
		local_end_point = value
		if is_instance_valid(self) and is_inside_tree():
			_update_rope_geometry()

@export_category("Dimensions & Visuals")
## Radial thickness of the rope cylinder in meters.
@export_range(0.01, 0.5, 0.01) var rope_radius: float = 0.04:
	set(value):
		rope_radius = value
		if is_instance_valid(self) and is_inside_tree():
			_update_rope_geometry()

## Albedo color applied to the rope surface material.
@export var rope_color: Color = Color(0.25, 0.18, 0.12):
	set(value):
		rope_color = value
		if is_instance_valid(_material):
			_material.albedo_color = rope_color

@export_category("Severance Options")
## Toggles spawning dynamic physics strands upon break.
@export var spawn_dynamic_halves: bool = true

## Prevents duplicate destruction passes once severed.
var is_broken: bool = false

## Bound [HealthComponent] managing entity hit points.
var _health_component: HealthComponent

## Child node rendering the visual cylinder mesh.
var _mesh_instance: MeshInstance3D

## Child node managing the physics collision shape.
var _collision_shape: CollisionShape3D

## Instance-unique cylinder mesh resource.
var _cylinder_mesh: CylinderMesh

## Instance-unique cylinder shape resource.
var _cylinder_shape: CylinderShape3D

## Instance-unique standard material resource.
var _material: StandardMaterial3D

## Cached hit position used when [HealthComponent] emits [signal HealthComponent.died].
var _pending_hit_pos: Vector3 = Vector3.ZERO

## Cached hit direction used when [HealthComponent] emits [signal HealthComponent.died].
var _pending_hit_direction: Vector3 = Vector3.DOWN

## Flag indicating whether a hit position was cached during damage processing.
var _has_pending_hit: bool = false


## Configures unique resources, binds health listeners, and aligns geometry.
func _ready() -> void:
	print("BreakableRope3D: _ready() - Initializing rope instance.")
	collision_layer = INTERACTIVE_LAYER_MASK
	collision_mask = 0

	_setup_internal_nodes()
	_bind_health_component()
	_update_rope_geometry()


## Updates orientation in editor and follows moving anchors during gameplay.
func _process(_delta: float) -> void:
	if is_broken:
		return

	if Engine.is_editor_hint():
		if is_instance_valid(start_anchor) or is_instance_valid(end_anchor):
			_update_rope_geometry()
	elif is_instance_valid(start_anchor) or is_instance_valid(end_anchor):
		_update_rope_geometry()


## Instantiates dedicated instance nodes and resources to prevent shared mutations.
func _setup_internal_nodes() -> void:
	print("BreakableRope3D: _setup_internal_nodes() - Creating instance resources.")
	_mesh_instance = get_node_or_null("VisualMesh") as MeshInstance3D
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "VisualMesh"
		add_child(_mesh_instance)

	_collision_shape = get_node_or_null("CollisionShape") as CollisionShape3D
	if not is_instance_valid(_collision_shape):
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape"
		add_child(_collision_shape)

	_material = StandardMaterial3D.new()
	_material.albedo_color = rope_color
	_material.roughness = 0.9

	_cylinder_mesh = CylinderMesh.new()
	_cylinder_mesh.radial_segments = 8
	_cylinder_mesh.rings = 1
	_cylinder_mesh.material = _material
	_mesh_instance.mesh = _cylinder_mesh

	_cylinder_shape = CylinderShape3D.new()
	_collision_shape.shape = _cylinder_shape


## Discovers child [HealthComponent] and connects to [signal HealthComponent.died].
func _bind_health_component() -> void:
	print("BreakableRope3D: _bind_health_component() - Binding health component.")
	_health_component = get_node_or_null("HealthComponent") as HealthComponent
	if not is_instance_valid(_health_component):
		for child: Node in get_children():
			if child is HealthComponent:
				_health_component = child as HealthComponent
				break

	if is_instance_valid(_health_component):
		_health_component.use_pooling = false
		if not _health_component.died.is_connected(_on_health_component_died):
			_health_component.died.connect(_on_health_component_died)


## Recalculates cylinder length, orientation, and positions between anchor points.
func _update_rope_geometry() -> void:
	if not is_inside_tree() or not is_instance_valid(_mesh_instance):
		return

	var p_start_global: Vector3 = get_start_global_position()
	var p_end_global: Vector3 = get_end_global_position()

	var local_start: Vector3 = to_local(p_start_global)
	var local_end: Vector3 = to_local(p_end_global)

	var length: float = local_start.distance_to(local_end)
	if length < 0.05:
		return

	var midpoint: Vector3 = (local_start + local_end) * 0.5
	var direction: Vector3 = (local_end - local_start).normalized()

	_cylinder_mesh.height = length
	_cylinder_mesh.top_radius = rope_radius
	_cylinder_mesh.bottom_radius = rope_radius

	_cylinder_shape.height = length
	_cylinder_shape.radius = rope_radius

	var up_hint: Vector3 = Vector3.UP if absf(direction.y) < 0.99 else Vector3.RIGHT
	var x_axis: Vector3 = up_hint.cross(direction).normalized()
	var z_axis: Vector3 = direction.cross(x_axis).normalized()
	var align_basis: Basis = Basis(x_axis, direction, z_axis)

	_mesh_instance.transform = Transform3D(align_basis, midpoint)
	_collision_shape.transform = Transform3D(align_basis, midpoint)


## Resolves the starting anchor point in global world space.
func get_start_global_position() -> Vector3:
	if is_instance_valid(start_anchor):
		return start_anchor.global_position
	return to_global(local_start_point)


## Resolves the ending anchor point in global world space.
func get_end_global_position() -> Vector3:
	if is_instance_valid(end_anchor):
		return end_anchor.global_position
	return to_global(local_end_point)


## Receives damage from [HitscanWeapon] and forwards it to [HealthComponent].
func take_damage(amount: int, hit_position: Vector3, direction: Vector3) -> void:
	print("BreakableRope3D: take_damage() - Amount: ", amount, " | Pos: ", hit_position)
	if is_broken:
		return

	_pending_hit_pos = hit_position
	_pending_hit_direction = direction
	_has_pending_hit = true

	if is_instance_valid(_health_component):
		_health_component.take_damage(amount)
		if not is_broken and _health_component.current_health <= 0:
			cut_rope_at(hit_position, direction)
	else:
		cut_rope_at(hit_position, direction)

	_has_pending_hit = false


## Handles [signal HealthComponent.died] and severs the rope.
func _on_health_component_died() -> void:
	print("BreakableRope3D: _on_health_component_died() - Health reached zero.")
	if is_broken:
		return

	var cut_pos: Vector3 = (get_start_global_position() + get_end_global_position()) * 0.5
	var cut_dir: Vector3 = Vector3.DOWN

	if _has_pending_hit:
		cut_pos = _pending_hit_pos
		cut_dir = _pending_hit_direction

	cut_rope_at(cut_pos, cut_dir)


## Snaps rope at [param hit_pos], emitting [signal rope_broken] and spawning strands.
func cut_rope_at(hit_pos: Vector3, shot_dir: Vector3) -> void:
	print("BreakableRope3D: cut_rope_at() - Rope severed at ", hit_pos)
	if is_broken:
		return

	is_broken = true
	rope_broken.emit()

	collision_layer = 0
	_collision_shape.set_deferred("disabled", true)
	_mesh_instance.visible = false

	if spawn_dynamic_halves and not Engine.is_editor_hint():
		_spawn_severed_cables(hit_pos, shot_dir)


## Spawns dynamic [PhysicsCable3D] segments for top and bottom severed sections.
func _spawn_severed_cables(hit_pos: Vector3, shot_dir: Vector3) -> void:
	print("BreakableRope3D: _spawn_severed_cables() - Creating dynamic physics strands.")
	var start_pos: Vector3 = get_start_global_position()
	var end_pos: Vector3 = get_end_global_position()

	var top_length: float = start_pos.distance_to(hit_pos)
	var bottom_length: float = end_pos.distance_to(hit_pos)

	if top_length > 0.15:
		_create_severed_strand(start_anchor, start_pos, hit_pos, top_length, shot_dir * 1.5)

	if bottom_length > 0.15:
		_create_severed_strand(end_anchor, end_pos, hit_pos, bottom_length, shot_dir * 0.5)


## Configures and instances a single severed dynamic catenary strand.
func _create_severed_strand(
	anchor_node: Node3D,
	anchor_pos: Vector3,
	sever_pos: Vector3,
	strand_length: float,
	impulse: Vector3
) -> void:
	print("BreakableRope3D: _create_severed_strand() - Length: ", strand_length)
	var tip_body: RigidBody3D = RigidBody3D.new()
	tip_body.collision_layer = 0
	tip_body.collision_mask = 1
	tip_body.mass = 0.5

	var tip_col: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = rope_radius
	tip_col.shape = sphere
	tip_body.add_child(tip_col)

	get_tree().current_scene.add_child(tip_body)
	tip_body.global_position = sever_pos
	tip_body.apply_central_impulse(impulse)

	var origin_anchor: Node3D = anchor_node
	if not is_instance_valid(origin_anchor):
		origin_anchor = Marker3D.new()
		get_tree().current_scene.add_child(origin_anchor)
		origin_anchor.global_position = anchor_pos

	var cable: PhysicsCable3D = PhysicsCable3D.new()
	cable.start_anchor = origin_anchor
	cable.end_plug = tip_body
	cable.cable_length_meters = strand_length
	cable.thickness = rope_radius
	cable.cable_color = rope_color
	cable.tension_force = 10.0

	get_tree().current_scene.add_child(cable)
