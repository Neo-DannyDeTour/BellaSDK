@tool
extends StaticBody3D
class_name ElectrifiedFloor

## Defines the length and width of the electrified floor area. Adjusting this updates all related
## meshes and collision shapes simultaneously.
@export var floor_size: float = 2.0:
	set(value):
		floor_size = maxf(0.1, value)
		if is_node_ready():
			_update_sizes()

## The amount of damage dealt to entities standing on the floor per tick.
@export var damage_per_tick: int = 10

## The time in seconds between each damage tick.
@export var tick_rate: float = 0.5

## The Area3D node responsible for detecting entities to damage.
@export var damage_area: Area3D

## Tracks the time elapsed since the floor last dealt damage to occupants.
var _time_since_last_tick: float = 0.0

## Maintains an active array of Node3D entities currently within the floor's damage bounds.
var _overlapping_bodies: Array[Node3D] = []


func _ready() -> void:
	print("ElectrifiedFloor: _ready() - Initializing electrified floor.")
	
	_update_sizes()
	
	if Engine.is_editor_hint():
		return
		
	if damage_area != null:
		damage_area.body_entered.connect(_on_body_entered)
		damage_area.body_exited.connect(_on_body_exited)
	else:
		printerr("ElectrifiedFloor: _ready() - damage_area is not assigned!")


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _overlapping_bodies.is_empty():
		return

	_time_since_last_tick += delta
	if _time_since_last_tick >= tick_rate:
		_apply_damage_to_bodies()
		_time_since_last_tick = 0.0


func _update_sizes() -> void:
	print("ElectrifiedFloor: _update_sizes() - Resizing meshes and colliders to ", floor_size)
	
	var floor_col: CollisionShape3D = get_node_or_null("FloorCollision")
	var floor_mesh: MeshInstance3D = get_node_or_null("FloorMesh")
	var lightning_plane: MeshInstance3D = get_node_or_null("LightningPlane")
	var damage_col: CollisionShape3D = get_node_or_null("DamageArea/DamageCollision")
	
	if floor_col != null and floor_col.shape is BoxShape3D:
		floor_col.shape.size = Vector3(floor_size, 0.5, floor_size) 
		
	if floor_mesh != null and floor_mesh.mesh is PlaneMesh:
		floor_mesh.mesh.size = Vector2(floor_size, floor_size)
		
	if lightning_plane != null and lightning_plane.mesh is PlaneMesh:
		lightning_plane.mesh.size = Vector2(floor_size, floor_size)
		
	if damage_col != null and damage_col.shape is BoxShape3D:
		damage_col.shape.size = Vector3(floor_size, 1.0, floor_size)
		damage_col.position.y = 0.25 


func _on_body_entered(body: Node3D) -> void:
	# Prevent the floor's Area3D from detecting its own StaticBody3D
	if body == self:
		return
		
	print("ElectrifiedFloor: _on_body_entered() - Body entered: ", body.name)
	if body not in _overlapping_bodies:
		_overlapping_bodies.append(body)


func _on_body_exited(body: Node3D) -> void:
	print("ElectrifiedFloor: _on_body_exited() - Body exited: ", body.name)
	if body in _overlapping_bodies:
		_overlapping_bodies.erase(body)


func _apply_damage_to_bodies() -> void:
	print("ElectrifiedFloor: _apply_damage_to_bodies() - Shocking overlapping bodies.")
	for body in _overlapping_bodies:
		if is_instance_valid(body):
			_try_damage_body(body)


func _try_damage_body(body: Node3D) -> void:
	var health_comp: HealthComponent = _find_health_component(body)
	
	if health_comp != null:
		print("ElectrifiedFloor: _try_damage_body() - Damaging ", body.name)
		health_comp.take_damage(damage_per_tick)
		
		# Broader check to ensure we catch the player
		if body.is_in_group("player") or "player" in body.name.to_lower():
			print("ElectrifiedFloor: Emitting player_electrocuted signal!")
			Events.player_electrocuted.emit() # Removed silent fail check
	else:
		print("ElectrifiedFloor: _try_damage_body() - No HealthComponent found on ", body.name)


func _find_health_component(node: Node) -> HealthComponent:
	#print("ElectrifiedFloor: _find_health_component() - Searching for component in ", node.name)
	
	for child: Node in node.get_children():
		if child is HealthComponent:
			return child
			
		var found_comp: HealthComponent = _find_health_component(child)
		if found_comp != null:
			return found_comp
			
	return null
