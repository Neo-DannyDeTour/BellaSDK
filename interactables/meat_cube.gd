## Drives spring-based jiggle deformation and bouncy player impacts on a rigid meat cube.
class_name MeatCubeInteractor
extends RigidBody3D

const PARAM_IMPACT_POS: StringName = &"impact_local_pos"
const PARAM_SQUISH_VEC: StringName = &"squish_vector"
const SLEEP_THRESHOLD: float = 0.0005

## Visual [MeshInstance3D] receiving [member PARAM_SQUISH_VEC] shader parameters.
@export var meat_visual: MeshInstance3D
## Upward launch speed applied to a [CharacterBody3D] landing on the cube.
@export var player_bounce_speed: float = 11.5
## Horizontal knockback multiplier when bouncing a [CharacterBody3D] off the sides.
@export var side_bounce_speed: float = 7.0
## Harmonic spring stiffness controlling snap-back speed.
@export var spring_stiffness: float = 180.0
## Harmonic spring damping controlling jiggle decay.
@export var spring_damping: float = 8.5
## Maximum local vertex displacement magnitude.
@export var max_squish: float = 0.45

@onready var _bounce_detector: Area3D = $BounceDetector

var _squish_pos: Vector3 = Vector3.ZERO
var _squish_vel: Vector3 = Vector3.ZERO
var _last_bounce_msec: int = 0


func _ready() -> void:
	assert(is_instance_valid(meat_visual), "MeatCubeInteractor requires meat_visual.")
	assert(is_instance_valid(_bounce_detector), "MeatCubeInteractor requires BounceDetector.")
	set_process(false)
	body_entered.connect(_on_rigid_body_entered)
	_bounce_detector.body_entered.connect(_on_player_detector_entered)
	_apply_shader_params(Vector3.UP, Vector3.ZERO)


func _process(delta: float) -> void:
	var step: float = minf(delta, 0.033)
	var accel: Vector3 = (-spring_stiffness * _squish_pos) - (spring_damping * _squish_vel)
	_squish_vel += accel * step
	_squish_pos += _squish_vel * step
	_squish_pos = _squish_pos.limit_length(max_squish)

	if is_instance_valid(meat_visual):
		meat_visual.set_instance_shader_parameter(PARAM_SQUISH_VEC, _squish_pos)

	if (
		_squish_pos.length_squared() < SLEEP_THRESHOLD
		and _squish_vel.length_squared() < SLEEP_THRESHOLD
	):
		_squish_pos = Vector3.ZERO
		_squish_vel = Vector3.ZERO
		if is_instance_valid(meat_visual):
			meat_visual.set_instance_shader_parameter(PARAM_SQUISH_VEC, Vector3.ZERO)
		set_process(false)


## Applies an external squish impulse at [param world_point] along [param world_impulse].
func apply_jiggle_impulse(world_point: Vector3, world_impulse: Vector3) -> void:
	var local_point: Vector3 = to_local(world_point)
	var local_dir: Vector3 = global_transform.basis.inverse() * world_impulse
	_squish_vel += local_dir
	_apply_shader_params(local_point, _squish_pos)
	set_process(true)


func _apply_shader_params(local_pos: Vector3, squish: Vector3) -> void:
	if is_instance_valid(meat_visual):
		meat_visual.set_instance_shader_parameter(PARAM_IMPACT_POS, local_pos)
		meat_visual.set_instance_shader_parameter(PARAM_SQUISH_VEC, squish)


func _on_rigid_body_entered(body: Node) -> void:
	if body == self:
		return
	var impact_vel: Vector3 = linear_velocity
	if body is RigidBody3D:
		var other_rb: RigidBody3D = body as RigidBody3D
		impact_vel = other_rb.linear_velocity - linear_velocity
	var speed: float = impact_vel.length()
	if speed > 1.0:
		var hit_point: Vector3 = global_position + Vector3.DOWN
		apply_jiggle_impulse(hit_point, impact_vel.normalized() * minf(speed * 0.6, 8.0))


func _on_player_detector_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_bounce_msec < 120:
		return
	_last_bounce_msec = now_msec

	var player: CharacterBody3D = body as CharacterBody3D
	var to_player: Vector3 = player.global_position - global_position
	var local_offset: Vector3 = global_transform.basis.inverse() * to_player

	# Top landing vs side impact
	if local_offset.y > 0.55 and absf(local_offset.x) < 1.15 and absf(local_offset.z) < 1.15:
		var incoming_down: float = maxf(-player.velocity.y, 4.0)
		player.velocity.y = maxf(player_bounce_speed, incoming_down * 0.9)
		apply_jiggle_impulse(player.global_position, Vector3.DOWN * minf(incoming_down * 0.85, 9.0))
		apply_central_impulse(Vector3.DOWN * minf(incoming_down * 3.0, 35.0))
	else:
		var push_dir: Vector3 = Vector3(to_player.x, 0.35, to_player.z).normalized()
		player.velocity = push_dir * side_bounce_speed
		apply_jiggle_impulse(player.global_position, -push_dir * 6.5)
		apply_central_impulse(-push_dir * 20.0)
