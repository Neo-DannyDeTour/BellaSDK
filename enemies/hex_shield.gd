@tool
## Dynamic hexagonal energy shield on Physics Layer 5 with inspector sizing and hex shatter.
class_name HexShield
extends StaticBody3D

## Emitted once health reaches zero and the shatter sequence begins.
signal shield_shattered

## Physics Layer 5 bitmask value corresponding to Enemies.
const LAYER_ENEMIES: int = 1 << 4

## Instance shader parameter storing world-meter shield width and height.
const PARAM_SHIELD_SIZE: StringName = &"shield_size"

## Instance shader parameter storing active QuadMesh canvas dimensions.
const PARAM_CANVAS_SIZE: StringName = &"canvas_size"

## Instance shader parameter storing local-space hit coordinates.
const PARAM_HIT_POS: StringName = &"hit_local_pos"

## Instance shader parameter driving expanding red ring and edge blink (0.0 to 1.0).
const PARAM_HIT_PROGRESS: StringName = &"hit_progress"

## Instance shader parameter driving hexagon scatter and fade out.
const PARAM_SHATTER: StringName = &"shatter_progress"

## Shield width and height in meters, synced live to mesh, collider, and shader.
@export var shield_size: Vector2 = Vector2(3.0, 2.0):
	set(value):
		shield_size = Vector2(maxf(value.x, 0.2), maxf(value.y, 0.2))
		if is_inside_tree():
			_sync_dimensions()

## Thickness of the BoxShape3D collider in meters.
@export_range(0.05, 1.0, 0.05) var collider_thickness: float = 0.15:
	set(value):
		collider_thickness = value
		if is_inside_tree():
			_sync_dimensions()

## Maximum shield hit points before shattering.
@export var max_health: int = 100

## Duration in seconds for the red ring wave and border blink on impact.
@export_range(0.1, 2.0, 0.05) var hit_wave_duration: float = 0.55

## Duration in seconds for flying hexagons to scatter and disappear.
@export_range(0.2, 3.0, 0.05) var shatter_duration: float = 0.9

## Extra meter padding added around the QuadMesh during shatter so flying hexes aren't clipped.
@export_range(0.5, 6.0, 0.25) var shatter_margin: float = 2.5

## Current active health points remaining.
var _current_health: int = 100

## True once health hits zero and shatter animation has triggered.
var _is_shattered: bool = false

## Active tween animating hit shockwave and red border blink.
var _hit_tween: Tween

## Active tween animating shatter progression.
var _shatter_tween: Tween

## Visual shield mesh holding the hex shader material.
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D

## Physics collider receiving raycast hits from [HitscanWeapon].
@onready
var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D


## Configures Physics Layer 5, validates child nodes, and syncs dimensions.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	if not Engine.is_editor_hint():
		assert(is_instance_valid(mesh_instance), "HexShield requires a MeshInstance3D child.")
		assert(is_instance_valid(collision_shape), "HexShield requires a CollisionShape3D child.")

	_current_health = max_health
	collision_layer = LAYER_ENEMIES
	collision_mask = 0

	_sync_dimensions()
	if is_instance_valid(mesh_instance):
		mesh_instance.set_instance_shader_parameter(PARAM_HIT_POS, Vector3.ZERO)
		mesh_instance.set_instance_shader_parameter(PARAM_HIT_PROGRESS, 1.0)
		mesh_instance.set_instance_shader_parameter(PARAM_SHATTER, 0.0)

	if not Engine.is_editor_hint():
		print(name, ": HexShield ready on Layer 5 | Size: ", shield_size, " HP: ", _current_health)


## Receives hitscan damage from [HitscanWeapon], triggers red edge blink and expanding ring.
func take_damage(amount: int, hit_pos: Vector3, _shot_dir: Vector3 = Vector3.ZERO) -> void:
	if _is_shattered or amount <= 0:
		return

	_current_health = maxi(_current_health - amount, 0)
	print(name, ": Shield hit at ", hit_pos, " | Remaining HP: ", _current_health)

	var local_hit: Vector3 = mesh_instance.to_local(hit_pos)
	mesh_instance.set_instance_shader_parameter(PARAM_HIT_POS, local_hit)
	mesh_instance.set_instance_shader_parameter(PARAM_HIT_PROGRESS, 0.0)

	if is_instance_valid(_hit_tween):
		_hit_tween.kill()

	_hit_tween = create_tween()
	(
		_hit_tween
		. tween_method(_set_hit_progress, 0.0, 1.0, hit_wave_duration)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)

	if _current_health == 0:
		_shatter()


## Resizes the QuadMesh, BoxShape3D, and shader uniforms to match [member shield_size].
func _sync_dimensions() -> void:
	if not is_instance_valid(mesh_instance):
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not is_instance_valid(collision_shape):
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D

	if is_instance_valid(mesh_instance):
		var quad: QuadMesh = mesh_instance.mesh as QuadMesh
		if not is_instance_valid(quad):
			quad = QuadMesh.new()
			mesh_instance.mesh = quad
		quad.size = shield_size
		mesh_instance.set_instance_shader_parameter(PARAM_SHIELD_SIZE, shield_size)
		mesh_instance.set_instance_shader_parameter(PARAM_CANVAS_SIZE, shield_size)

	if is_instance_valid(collision_shape):
		var box: BoxShape3D = collision_shape.shape as BoxShape3D
		if not is_instance_valid(box):
			box = BoxShape3D.new()
			collision_shape.shape = box
		box.size = Vector3(shield_size.x, shield_size.y, collider_thickness)


## Expands canvas for flying hexagons, disables collision, and plays shatter tween.
func _shatter() -> void:
	_is_shattered = true
	print(name, ": Shield HP depleted -> scattering hexagons.")

	set_deferred("collision_layer", 0)
	if is_instance_valid(collision_shape):
		collision_shape.set_deferred("disabled", true)

	if is_instance_valid(mesh_instance):
		var expanded: Vector2 = shield_size + Vector2.ONE * (shatter_margin * 2.0)
		var quad: QuadMesh = mesh_instance.mesh as QuadMesh
		if is_instance_valid(quad):
			quad.size = expanded
		mesh_instance.set_instance_shader_parameter(PARAM_CANVAS_SIZE, expanded)

	shield_shattered.emit()

	if is_instance_valid(_shatter_tween):
		_shatter_tween.kill()

	_shatter_tween = create_tween()
	(
		_shatter_tween
		. tween_method(_set_shatter_progress, 0.0, 1.0, shatter_duration)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_shatter_tween.tween_callback(queue_free)


## Updates per-instance hit wave progress uniform on [member mesh_instance].
func _set_hit_progress(val: float) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.set_instance_shader_parameter(PARAM_HIT_PROGRESS, val)


## Updates per-instance shatter progress uniform on [member mesh_instance].
func _set_shatter_progress(val: float) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.set_instance_shader_parameter(PARAM_SHATTER, val)
