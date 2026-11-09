## Physical wooden shipping crate supporting pickup, throwing, impact damage, and breaking.
##
## Inherits from [PickableObject] on physics layer 3 (Interactive). Upon health depletion,
## spawns physical debris chunks on physics layer 4 (Debris) with per-instance fade out.
class_name BreakableCrate
extends PickableObject

## Emitted once when the crate health depletes and chunks spawn.
@warning_ignore("unused_signal")
signal broken(world_position: Vector3)

## Shader uniform name driving per-instance debris alpha fade.
const PARAM_FADE: StringName = &"fade"

## Mass in kilograms assigned to each individual debris chunk.
const DEBRIS_MASS: float = 1.8

## Base impulse magnitude dispersing debris outward from crate center.
const RADIAL_BLAST_STRENGTH: float = 3.5

## Multiplier transferring incoming hit impulse to fractured debris chunks.
const HIT_IMPULSE_TRANSFER: float = 0.35

## Total duration in seconds debris chunks remain in the world before fading.
const DEBRIS_LIFETIME: float = 6.0

## Duration in seconds of the debris transparency fade out tween.
const DEBRIS_FADE_DURATION: float = 1.0

## Multiplier scaling angular velocity applied to spawned debris chunks.
const DEBRIS_TORQUE_STRENGTH: float = 1.5

## Multiplier converting impact speed into self damage when hitting obstacles.
const SELF_DAMAGE_SPEED_RATIO: float = 1.5

## Downward velocity threshold in meters per second triggering player stomp fracture.
const PLAYER_STOMP_SPEED_THRESHOLD: float = -7.0

## Vertical fall velocity threshold in meters per second inflicting impact damage.
const CRATE_FALL_SPEED_THRESHOLD: float = -6.0

## Multiplier converting vertical fall velocity into self impact damage.
const FALL_DAMAGE_RATIO: float = 4.0

@export_category("Breakable Settings")
## Total hit points required to shatter the crate into debris.
@export var max_health: float = 25.0

## The primary intact mesh hidden when the crate fractures.
@export var intact_mesh: MeshInstance3D

## The primary collision shape disabled when the crate fractures.
@export var intact_collision: CollisionShape3D

## Parent container holding static debris chunk meshes.
@export var debris_root: Node3D

## Specialized spatial shader driving per-instance alpha fade without pipeline stalls.
@export var fade_shader: Shader

## Remaining hit points before crate destruction.
var _current_health: float = 25.0

## Flag preventing repeated fracture triggers.
var _is_broken: bool = false

## Pre-impact linear velocity tracked inside [_integrate_forces] for fall damage.
var _pre_impact_velocity: Vector3 = Vector3.ZERO

## Cached list of dynamically created debris rigid bodies.
var _debris_bodies: Array[RigidBody3D] = []

## Cached list of debris mesh instances receiving instance shader uniforms.
var _debris_meshes: Array[MeshInstance3D] = []

## Active tween handling debris lifetime and fade out interpolation.
var _fade_tween: Tween


## Validates required node references, sets mass, and prepares debris chunks.
func _ready() -> void:
	super._ready()
	assert(intact_mesh != null, "BreakableCrate: intact_mesh is required.")
	assert(intact_collision != null, "BreakableCrate: intact_collision is required.")
	assert(debris_root != null, "BreakableCrate: debris_root is required.")

	_current_health = max_health
	mass = 25.0
	collision_layer = CollisionLayers.MASK_INTERACTIVE
	collision_mask = (
		CollisionLayers.MASK_ENVIRONMENT
		| CollisionLayers.MASK_PLAYER
		| CollisionLayers.MASK_INTERACTIVE
		| CollisionLayers.MASK_DEBRIS
		| CollisionLayers.MASK_ENEMIES
	)

	debris_root.visible = false
	_prepare_debris_chunks()


## Cleans up active tween when exiting the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_fade_tween)


## Tracks pre-impact velocity before solver contact resolution.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not _is_broken and not is_held:
		_pre_impact_velocity = state.linear_velocity


## Applies hit damage and physics impulse; triggers fracture at or below 0 HP.
func apply_hit(damage: float, hit_position: Vector3, impulse: Vector3) -> void:
	if _is_broken:
		return

	_current_health -= damage
	if _current_health > 0.0:
		apply_impulse(impulse, hit_position - global_position)
		print("BreakableCrate: Hit received. HP remaining: ", _current_health)
		return

	_is_broken = true
	print("BreakableCrate: Broken at ", global_position)
	if is_held:
		drop()
	broken.emit(global_position)
	_trigger_break.call_deferred(hit_position, impulse)


## Processes incoming combat damage and forwards values to [method apply_hit].
func take_damage(
	amount: int, hit_position: Vector3 = Vector3.ZERO, hit_direction: Vector3 = Vector3.ZERO
) -> void:
	var damage_val: float = float(amount)
	var pos: Vector3 = hit_position if hit_position != Vector3.ZERO else global_position
	var impulse: Vector3 = hit_direction * (damage_val * 0.2)
	apply_hit(damage_val, pos, impulse)


## Handles high-velocity collision impacts, player stomps, and free fall damage.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)
	if _is_broken or is_held:
		return

	if body == holder or body.is_in_group(&"player") or body is CharacterBody3D:
		var char_body: CharacterBody3D = body as CharacterBody3D
		if is_instance_valid(char_body):
			var player_fall_speed: float = char_body.velocity.y
			if player_fall_speed <= PLAYER_STOMP_SPEED_THRESHOLD:
				var stomp_pos: Vector3 = global_position + Vector3(0.0, 1.05, 0.0)
				var stomp_impulse: Vector3 = Vector3.DOWN * 8.0
				print("BreakableCrate: Player stomp detected! Speed: ", player_fall_speed)
				apply_hit(max_health, stomp_pos, stomp_impulse)
		return

	var fall_speed: float = _pre_impact_velocity.y
	if fall_speed <= CRATE_FALL_SPEED_THRESHOLD:
		var fall_damage: float = absf(fall_speed) * FALL_DAMAGE_RATIO
		var fall_pos: Vector3 = global_position
		print("BreakableCrate: Free fall impact! Fall speed: ", fall_speed, " Dmg: ", fall_damage)
		apply_hit(fall_damage, fall_pos, Vector3.UP * 5.0)
		return

	var throw_speed: float = _last_velocity.length()
	if throw_speed >= damage_velocity_threshold:
		var self_damage: float = throw_speed * SELF_DAMAGE_SPEED_RATIO
		var impact_pos: Vector3 = global_position
		var impact_dir: Vector3 = -_last_velocity.normalized()
		apply_hit(self_damage, impact_pos, impact_dir * throw_speed)


## Converts static debris child meshes into sleeping debris rigid bodies.
func _prepare_debris_chunks() -> void:
	var raw_children: Array[Node] = debris_root.get_children()
	for child: Node in raw_children:
		var mesh_inst: MeshInstance3D = child as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue

		if fade_shader != null:
			_apply_fade_shader(mesh_inst)

		var body: RigidBody3D = RigidBody3D.new()
		body.name = mesh_inst.name + "_Body"
		body.mass = DEBRIS_MASS
		body.collision_layer = CollisionLayers.MASK_NONE
		body.collision_mask = CollisionLayers.MASK_NONE
		body.freeze = true
		body.transform = mesh_inst.transform

		var col: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		var aabb: AABB = mesh_inst.mesh.get_aabb()
		box.size = aabb.size.max(Vector3(0.03, 0.03, 0.03))
		col.shape = box
		col.position = aabb.get_center()

		debris_root.remove_child(mesh_inst)
		mesh_inst.transform = Transform3D.IDENTITY
		mesh_inst.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
		mesh_inst.set_instance_shader_parameter(PARAM_FADE, 1.0)

		body.add_child(mesh_inst)
		body.add_child(col)
		debris_root.add_child(body)

		_debris_bodies.append(body)
		_debris_meshes.append(mesh_inst)


## Replaces mesh material with fade shader while preserving source albedo texture.
func _apply_fade_shader(mesh_inst: MeshInstance3D) -> void:
	var active_mat: Material = mesh_inst.get_active_material(0)
	if active_mat == null and mesh_inst.mesh != null:
		active_mat = mesh_inst.mesh.surface_get_material(0)

	var shader_mat: ShaderMaterial = ShaderMaterial.new()
	shader_mat.shader = fade_shader
	if active_mat is BaseMaterial3D:
		var base_mat: BaseMaterial3D = active_mat as BaseMaterial3D
		if base_mat != null and base_mat.albedo_texture != null:
			shader_mat.set_shader_parameter(&"albedo_texture", base_mat.albedo_texture)
	mesh_inst.material_override = shader_mat


## Disables intact collider, reparents debris root, activates physics, and starts fade.
func _trigger_break(hit_position: Vector3, impulse: Vector3) -> void:
	if is_instance_valid(intact_mesh):
		intact_mesh.visible = false
	if is_instance_valid(intact_collision):
		intact_collision.disabled = true

	freeze = true
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_NONE

	if is_instance_valid(label):
		label.hide()
	if is_instance_valid(prompt_icon):
		prompt_icon.hide()
	if is_instance_valid(highlight_comp):
		highlight_comp.suppress(true)

	var parent_node: Node = get_parent()
	if is_instance_valid(parent_node) and is_instance_valid(debris_root):
		Utilities.reparent_keep_transform(debris_root, parent_node, true)

	debris_root.visible = true
	var crate_center: Vector3 = global_position + Vector3(0.0, 0.525, 0.0)

	for body: RigidBody3D in _debris_bodies:
		if not is_instance_valid(body):
			continue
		body.collision_layer = CollisionLayers.MASK_DEBRIS
		body.collision_mask = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS
		body.freeze = false

		var radial_dir: Vector3 = (body.global_position - crate_center).normalized()
		var blast_impulse: Vector3 = (
			radial_dir * RADIAL_BLAST_STRENGTH + impulse * HIT_IMPULSE_TRANSFER
		)
		body.apply_impulse(blast_impulse, hit_position - body.global_position)
		body.apply_torque_impulse(radial_dir.cross(Vector3.UP) * DEBRIS_TORQUE_STRENGTH)

	Utilities.safe_kill_tween(_fade_tween)
	_fade_tween = create_tween()
	_fade_tween.tween_interval(DEBRIS_LIFETIME)
	_fade_tween.tween_method(_set_debris_fade, 1.0, 0.0, DEBRIS_FADE_DURATION)
	_fade_tween.tween_callback(_on_fade_finished)


## Frees debris container and crate root upon fade completion.
func _on_fade_finished() -> void:
	if is_instance_valid(debris_root):
		debris_root.queue_free()
	queue_free()


## Updates per-instance fade alpha parameter on all active debris meshes.
func _set_debris_fade(value: float) -> void:
	for mesh_inst: MeshInstance3D in _debris_meshes:
		if is_instance_valid(mesh_inst):
			mesh_inst.set_instance_shader_parameter(PARAM_FADE, value)
