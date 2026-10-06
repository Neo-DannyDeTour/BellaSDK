## Floor hazard dealing periodic damage to overlapping entities with a [HealthComponent].
@tool
class_name ElectrifiedFloor
extends StaticBody3D

## Dimensions for the floor area. Resizes child meshes and shapes when modified.
@export var floor_size: float = 2.0:
	set(value):
		floor_size = maxf(0.1, value)
		if is_instance_valid(self) and is_inside_tree() and is_node_ready():
			_update_sizes()

## Damage applied per tick to overlapping entities with a [HealthComponent].
@export var damage_per_tick: int = 10

## Cooldown in seconds between damage application intervals.
@export var tick_rate: float = 0.5

## Detection zone identifying entities entering the electrified boundary.
@export var damage_area: Area3D

var _time_since_last_tick: float = 0.0
var _overlapping_bodies: Array[Node3D] = []


## Initializes bounds and connects detection signals when running in-game.
func _ready() -> void:
	print("ElectrifiedFloor: _ready() - Initializing electrified floor.")
	_update_sizes()

	if Engine.is_editor_hint():
		return

	if is_instance_valid(damage_area):
		damage_area.body_entered.connect(_on_body_entered)
		damage_area.body_exited.connect(_on_body_exited)
	else:
		printerr("ElectrifiedFloor: _ready() - damage_area is not assigned!")


## Accumulates delta time and triggers ticks against registered bodies.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _overlapping_bodies.is_empty():
		return

	_time_since_last_tick += delta
	if _time_since_last_tick >= tick_rate:
		_apply_damage_to_bodies()
		_time_since_last_tick = 0.0


## Resizes collision shapes and mesh instances to match [member floor_size].
func _update_sizes() -> void:
	print("ElectrifiedFloor: _update_sizes() - Resizing meshes and colliders to ", floor_size)

	var floor_col: CollisionShape3D = get_node_or_null("FloorCollision") as CollisionShape3D
	var floor_mesh: MeshInstance3D = get_node_or_null("FloorMesh") as MeshInstance3D
	var lightning_plane: MeshInstance3D = get_node_or_null("LightningPlane") as MeshInstance3D
	var damage_col: CollisionShape3D = (
		get_node_or_null("DamageArea/DamageCollision") as CollisionShape3D
	)

	if is_instance_valid(floor_col) and floor_col.shape is BoxShape3D:
		var box_shape: BoxShape3D = floor_col.shape as BoxShape3D
		box_shape.size = Vector3(floor_size, 0.5, floor_size)

	if is_instance_valid(floor_mesh) and floor_mesh.mesh is PlaneMesh:
		var plane: PlaneMesh = floor_mesh.mesh as PlaneMesh
		plane.size = Vector2(floor_size, floor_size)

	if is_instance_valid(lightning_plane) and lightning_plane.mesh is PlaneMesh:
		var lightning: PlaneMesh = lightning_plane.mesh as PlaneMesh
		lightning.size = Vector2(floor_size, floor_size)

	if is_instance_valid(damage_col) and damage_col.shape is BoxShape3D:
		var damage_box: BoxShape3D = damage_col.shape as BoxShape3D
		damage_box.size = Vector3(floor_size, 1.0, floor_size)
		damage_col.position.y = 0.25


## Handles entry detection and appends new target bodies to tracking array.
func _on_body_entered(body: Node3D) -> void:
	if body == self:
		return

	print("ElectrifiedFloor: _on_body_entered() - Body entered: ", body.name)
	if not _overlapping_bodies.has(body):
		_overlapping_bodies.append(body)


## Handles exit detection and removes departing bodies from tracking array.
func _on_body_exited(body: Node3D) -> void:
	print("ElectrifiedFloor: _on_body_exited() - Body exited: ", body.name)
	_overlapping_bodies.erase(body)


## Iterates through cached bodies and dispatches damage to valid targets.
func _apply_damage_to_bodies() -> void:
	print("ElectrifiedFloor: _apply_damage_to_bodies() - Shocking bodies.")
	for body: Node3D in _overlapping_bodies:
		if is_instance_valid(body):
			_try_damage_body(body)


## Queries a body for [HealthComponent] and emits electrocuted events.
func _try_damage_body(body: Node3D) -> void:
	var health_comp: HealthComponent = _find_health_component(body)

	if health_comp != null:
		print("ElectrifiedFloor: _try_damage_body() - Damaging ", body.name)
		health_comp.take_damage(damage_per_tick)

		if body.is_in_group("player") or "player" in body.name.to_lower():
			print("ElectrifiedFloor: Emitting player_electrocuted signal!")
			Events.player_electrocuted.emit()
	else:
		print("ElectrifiedFloor: _try_damage_body() - No HealthComponent on ", body.name)


## Recursively searches child tree of target [Node] for a [HealthComponent].
func _find_health_component(target_node: Node) -> HealthComponent:
	for child: Node in target_node.get_children():
		if child is HealthComponent:
			return child as HealthComponent

		var found: HealthComponent = _find_health_component(child)
		if found != null:
			return found

	return null
