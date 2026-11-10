## Breakable 5-plank wooden shelf prop.
##
## Operates as a single [RigidBody3D] on the Interactive physics layer until broken
## by [method take_damage] or high-velocity impact, then wakes 5 pre-allocated
## child [RigidBody3D] planks on the Debris layer and fades them out.
# class_name BreakableShelf
extends RigidBody3D

## Emitted when the shelf breaks into debris planks. [param origin] is the world position.
@warning_ignore("unused_signal")
signal broken(origin: Vector3)

## Per-instance shader uniform driving plank fade-out.
const SHADER_ALPHA_PARAM: StringName = &"albedo_alpha"
## Collision layer used by debris planks.
const LAYER_DEBRIS: int = CollisionLayers.MASK_DEBRIS
## Mask for debris planks: environment and other debris.
const MASK_DEBRIS: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS
## Seconds debris stays opaque before fading.
const FADE_DELAY_SEC: float = 4.0
## Seconds the debris fade-out lasts.
const FADE_DURATION_SEC: float = 1.0

## Damage the intact shelf absorbs before breaking.
@export var max_health: float = 20.0
## Squared linear speed (m/s) on contact that triggers impact fracture.
@export var impact_velocity_sq_threshold: float = 16.0
## Outward impulse strength applied to planks on break.
@export var burst_impulse: float = 2.2

## Remaining health of the intact shelf.
var _health: float = 20.0
## True once the shelf has begun breaking.
var _is_broken: bool = false
## Active fade tween for debris planks.
var _fade_tween: Tween = null
## Cached debris plank bodies.
var _gib_bodies: Array[RigidBody3D] = []
## Cached debris plank meshes.
var _gib_meshes: Array[MeshInstance3D] = []
## Cached debris plank collision shapes.
var _gib_shapes: Array[CollisionShape3D] = []

## Container for the intact plank meshes.
@onready var _intact_visuals: Node3D = $IntactVisuals
## Container for the pre-allocated debris planks.
@onready var _gibs_root: Node3D = $Gibs


## Validates node structure, caches plank references, and configures physics state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(_intact_visuals != null, "BreakableShelf: Missing IntactVisuals node.")
	assert(_gibs_root != null, "BreakableShelf: Missing Gibs root node.")
	_health = max_health
	for child: Node in _gibs_root.get_children():
		var gib: RigidBody3D = child as RigidBody3D
		if gib != null:
			_gib_bodies.append(gib)
			var mesh: MeshInstance3D = gib.get_node_or_null("Mesh") as MeshInstance3D
			var shape: CollisionShape3D = gib.get_node_or_null("Shape") as CollisionShape3D
			assert(mesh != null and shape != null, "BreakableShelf: Malformed gib child.")
			_gib_meshes.append(mesh)
			_gib_shapes.append(shape)
	assert(_gib_bodies.size() == 5, "BreakableShelf: Expected 5 plank gibs.")
	body_entered.connect(_on_body_entered)


## Cleans up active tweens on tree exit.
func _exit_tree() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()


## Applies damage and breaks the shelf when health reaches zero.
func take_damage(amount: float, hit_pos: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
	if _is_broken or amount <= 0.0:
		return
	_health -= amount
	print("BreakableShelf: damaged, remaining=", _health)
	if _health <= 0.0:
		_trigger_break(hit_pos, impulse)
	elif impulse != Vector3.ZERO:
		apply_impulse(impulse, hit_pos - global_position)


## Evaluates physics collision velocity to trigger impact fracture.
func _on_body_entered(_body: Node) -> void:
	if _is_broken:
		return
	if linear_velocity.length_squared() >= impact_velocity_sq_threshold:
		_trigger_break(global_position, linear_velocity * 0.35)


## Schedules deferred transition from intact body to debris planks.
func _trigger_break(hit_pos: Vector3, impulse: Vector3) -> void:
	if _is_broken:
		return
	_is_broken = true
	print("BreakableShelf: broken at ", global_position)
	call_deferred(&"_execute_break_deferred", hit_pos, impulse)


## Swaps intact collision/visuals for independent debris planks and starts fade timer.
func _execute_break_deferred(hit_pos: Vector3, impulse: Vector3) -> void:
	if not is_inside_tree():
		return
	broken.emit(global_position)
	freeze = true
	collision_layer = 0
	collision_mask = 0
	_intact_visuals.visible = false
	for child: Node in get_children():
		var col: CollisionShape3D = child as CollisionShape3D
		if col != null:
			col.disabled = true
	_gibs_root.visible = true
	var parent_node: Node = get_parent()
	for i: int in range(_gib_bodies.size()):
		var gib: RigidBody3D = _gib_bodies[i]
		var shape: CollisionShape3D = _gib_shapes[i]
		var g_xform: Transform3D = gib.global_transform
		if parent_node != null:
			gib.reparent(parent_node, true)
		gib.global_transform = g_xform
		shape.disabled = false
		gib.collision_layer = LAYER_DEBRIS
		gib.collision_mask = MASK_DEBRIS
		gib.freeze = false
		gib.linear_velocity = linear_velocity
		gib.angular_velocity = angular_velocity
		var offset: Vector3 = gib.global_position - hit_pos
		var dist_sq: float = maxf(offset.length_squared(), 0.04)
		var dir: Vector3 = offset.normalized() if dist_sq > 0.0001 else Vector3.UP
		gib.apply_central_impulse(dir * (burst_impulse / dist_sq) + impulse * 0.25)
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_interval(FADE_DELAY_SEC)
	_fade_tween.tween_method(_set_gibs_alpha, 1.0, 0.0, FADE_DURATION_SEC)
	_fade_tween.tween_callback(_cleanup_gibs)


## Updates per-instance alpha uniform on all valid plank meshes.
func _set_gibs_alpha(alpha: float) -> void:
	for mesh: MeshInstance3D in _gib_meshes:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter(SHADER_ALPHA_PARAM, alpha)


## Frees spawned debris planks and the root shelf node.
func _cleanup_gibs() -> void:
	for gib: RigidBody3D in _gib_bodies:
		if is_instance_valid(gib):
			gib.queue_free()
	queue_free()
