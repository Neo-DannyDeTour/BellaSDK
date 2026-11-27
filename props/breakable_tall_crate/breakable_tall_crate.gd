## Breakable 8-piece tall wooden shipping crate.
##
## Operates as a single [RigidBody3D] on the Interactive physics layer until broken
## by [method take_damage] or high-velocity impact, then wakes 8 pre-allocated
## child [RigidBody3D] plank gibs on the Debris layer and fades them out.
# class_name BreakableTallCrate
extends RigidBody3D

## Emitted when the crate breaks into wood gibs. [param origin] is the world position.
signal broken(origin: Vector3)

## Per-instance shader uniform driving wood gib fade-out.
const SHADER_ALPHA_PARAM: StringName = &"albedo_alpha"
## Collision layer used by debris planks.
const LAYER_DEBRIS: int = CollisionLayers.MASK_DEBRIS
## Mask for debris planks: environment and other debris.
const MASK_DEBRIS: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS
## Seconds debris stays opaque before fading.
const FADE_DELAY_SEC: float = 5.0
## Seconds the debris fade-out lasts.
const FADE_DURATION_SEC: float = 1.2
## Expected number of pre-allocated plank gibs.
const EXPECTED_GIB_COUNT: int = 8

## Damage the intact crate absorbs before breaking.
@export var max_health: float = 35.0
## Squared linear speed (m/s) on contact that triggers impact fracture.
@export var impact_velocity_sq_threshold: float = 20.0
## Outward impulse strength applied to planks on break.
@export var burst_impulse: float = 2.6
## Optional fade-capable [ShaderMaterial] applied to plank gibs for smooth debris fade-out.
@export var gib_fade_material: ShaderMaterial = null

## Remaining health of the intact crate.
var _health: float = 35.0
## True once the crate has begun breaking.
var _is_broken: bool = false
## Active fade tween for debris planks.
var _fade_tween: Tween = null
## Cached debris plank bodies.
var _gib_bodies: Array[RigidBody3D] = []
## Cached debris plank meshes.
var _gib_meshes: Array[MeshInstance3D] = []
## Cached debris plank collision shapes.
var _gib_shapes: Array[CollisionShape3D] = []

## Container for the intact crate mesh.
@onready var _intact_visuals: Node3D = $IntactVisuals
## Container for the pre-allocated debris planks.
@onready var _gibs_root: Node3D = $Gibs


## Validates node structure, caches gib references, and configures physics state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(_intact_visuals != null, "BreakableTallCrate: Missing IntactVisuals node.")
	assert(_gibs_root != null, "BreakableTallCrate: Missing Gibs root node.")
	_health = max_health
	for child: Node in _gibs_root.get_children():
		var gib: RigidBody3D = child as RigidBody3D
		if gib != null:
			_gib_bodies.append(gib)
			var mesh: MeshInstance3D = _find_first_mesh(gib)
			var shape: CollisionShape3D = gib.get_node_or_null("Shape") as CollisionShape3D
			assert(mesh != null and shape != null, "BreakableTallCrate: Malformed gib child.")
			_gib_meshes.append(mesh)
			_gib_shapes.append(shape)
			if gib_fade_material != null:
				mesh.material_override = gib_fade_material
	assert(
		_gib_bodies.size() == EXPECTED_GIB_COUNT,
		"BreakableTallCrate: Expected 8 plank gibs.",
	)
	body_entered.connect(_on_body_entered)


## Cleans up active tweens on tree exit.
func _exit_tree() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()


## Applies damage and breaks the crate when health reaches zero.
func take_damage(amount: float, hit_pos: Vector3, impulse: Vector3 = Vector3.ZERO) -> void:
	if _is_broken or amount <= 0.0:
		return
	_health -= amount
	print("BreakableTallCrate: damaged, remaining=", _health)
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
	print("BreakableTallCrate: broken at ", global_position)
	call_deferred(&"_execute_break_deferred", hit_pos, impulse)


## Swaps intact collision/visuals for independent debris planks and starts fade timer.
func _execute_break_deferred(hit_pos: Vector3, impulse: Vector3) -> void:
	if not is_inside_tree():
		return
	broken.emit(global_position)
	freeze = true
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_NONE
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
		var world_xform: Transform3D = gib.global_transform
		if parent_node != null:
			_gibs_root.remove_child(gib)
			parent_node.add_child(gib)
			gib.global_transform = world_xform
		gib.collision_layer = LAYER_DEBRIS
		gib.collision_mask = MASK_DEBRIS
		shape.disabled = false
		gib.freeze = false
		var offset: Vector3 = gib.global_position - hit_pos
		var dir: Vector3 = offset.normalized() if offset.length_squared() > 0.0001 else Vector3.UP
		gib.apply_central_impulse(dir * burst_impulse + impulse * 0.45)
		gib.apply_torque_impulse(
			Vector3(randf_range(-1.8, 1.8), randf_range(-1.8, 1.8), randf_range(-1.8, 1.8))
		)
	_start_fade_out()


## Starts delayed fade-out tween across all debris planks then frees them and self.
func _start_fade_out() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_interval(FADE_DELAY_SEC)
	_fade_tween.tween_method(_set_gibs_alpha, 1.0, 0.0, FADE_DURATION_SEC)
	_fade_tween.tween_callback(_cleanup_all)


## Updates per-instance shader alpha on all still-valid debris meshes.
func _set_gibs_alpha(alpha: float) -> void:
	for mesh: MeshInstance3D in _gib_meshes:
		if is_instance_valid(mesh):
			mesh.set_instance_shader_parameter(SHADER_ALPHA_PARAM, alpha)


## Frees all reparented debris planks and the parent crate node.
func _cleanup_all() -> void:
	for gib: RigidBody3D in _gib_bodies:
		if is_instance_valid(gib):
			gib.queue_free()
	if is_instance_valid(self):
		queue_free()


## Recursively locates the first [MeshInstance3D] under [param root].
func _find_first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child: Node in root.get_children():
		var found: MeshInstance3D = _find_first_mesh(child)
		if found != null:
			return found
	return null
