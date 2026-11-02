@tool
## Pickable Alyx-style liquid bottle integrating [PickableObject] physics and buoyancy
## with Verlet spring-damper sloshing and [VisibleOnScreenNotifier3D] sleep gating.
class_name PickableLiquidBottle
extends PickableObject

## Pre-allocated shader instance parameter name for surface tilt coefficients.
const PARAM_COEFF: StringName = &"coeff"
## Pre-allocated shader instance parameter name for agitation/carbonation velocity.
const PARAM_VEL: StringName = &"vel"
## Pre-allocated shader instance parameter name for normalized liquid fill height.
const PARAM_FILL: StringName = &"fill_amount"
## Pre-allocated shader instance parameter name for half-extents of the container mesh.
const PARAM_SIZE: StringName = &"size"
## Pre-allocated shader instance parameter name for inner wall offset.
const PARAM_THICKNESS: StringName = &"glass_thickness"
## Pre-allocated shader instance parameter name for UV noise scaling.
const PARAM_SCALE: StringName = &"scale"
## Pre-allocated shader instance parameter name for RGBA liquid albedo and opacity.
const PARAM_COLOR: StringName = &"liquid_color"
## Pre-allocated shader instance parameter name for held transparency fade.
const PARAM_HELD_FADE: StringName = &"held_fade"

## Spring restoring stiffness for the 2D liquid surface plane.
const SPRING_CONSTANT: float = 180.0
## Coupling factor converting world acceleration into surface tilt.
const REACTION_STRENGTH: float = 3.5
## Velocity damping factor for the Verlet wave integrator.
const DAMPENING: float = 4.2
## Squared motion threshold below which the slosh simulation enters sleep mode.
const SLEEP_THRESHOLD_SQ: float = 0.000004
## Squared displacement threshold for triggering carbonation agitation.
const MOTION_THRESHOLD_SQ: float = 0.000025

@export_category("Liquid Simulation")
## Multiplier scaling the visual slosh tilt amplitude [0.0..1.0].
@export_range(0.0, 1.0, 0.0001) var liquid_mobility: float = 1.0
## Normalized liquid fill level inside the bottle [0.0..1.0].
@export_range(0.0, 1.0, 0.0001) var fill: float = 0.55:
	set = set_fill
## Simulated inner glass wall thickness relative to bottle width [0.0..1.0].
@export_range(0.0, 1.0, 0.0001) var glass_thickness: float = 0.015:
	set = set_glass_thickness
## Enables rising carbonation bubbles and surface foam when shaken.
@export var gas: bool = true:
	set = set_gas
## RGBA liquid color where alpha < 1.0 enables screen-space refraction and Beer-Lambert absorption.
@export var liquid_color: Color = Color(0.05, 0.82, 0.96, 0.45):
	set = set_liquid_color

var _coeff: Vector2 = Vector2.ZERO
var _coeff_old: Vector2 = Vector2.ZERO
var _coeff_old_old: Vector2 = Vector2.ZERO
var _pos1: Vector3 = Vector3.ZERO
var _pos2: Vector3 = Vector3.ZERO
var _pos3: Vector3 = Vector3.ZERO
var _vel: float = 0.0
## Cached dimensions of the bottle mesh bounding box scaled to local space.
var _mesh_size: Vector3 = Vector3(0.1572, 0.5232, 0.1572)
var _is_on_screen: bool = true
var _is_sloshing: bool = false

@onready var _bottle_mesh: MeshInstance3D = $BottleMesh
@onready var _cap_mesh: MeshInstance3D = $BottleMesh/CapMesh
@onready var _liquid_notifier: VisibleOnScreenNotifier3D = $LiquidVisibilityNotifier


## Initializes liquid bottle parameters, visibility signals, and base [PickableObject] state.
func _ready() -> void:
	set_process(false)
	assert(_bottle_mesh != null, "PickableLiquidBottle requires a BottleMesh child node.")
	assert(
		_liquid_notifier != null,
		"PickableLiquidBottle requires a LiquidVisibilityNotifier child node."
	)

	if not _liquid_notifier.screen_entered.is_connected(_on_liquid_screen_entered):
		_liquid_notifier.screen_entered.connect(_on_liquid_screen_entered)
	if not _liquid_notifier.screen_exited.is_connected(_on_liquid_screen_exited):
		_liquid_notifier.screen_exited.connect(_on_liquid_screen_exited)

	_is_on_screen = _liquid_notifier.is_on_screen()
	_sync_mesh_metrics()
	_apply_all_parameters()

	_pos1 = _get_effective_point()
	_pos2 = _pos1
	_pos3 = _pos1

	if Engine.is_editor_hint():
		set_physics_process(false)
		return

	super._ready()


## Disconnects visibility gating signals when exiting the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(_liquid_notifier) and _liquid_notifier.is_inside_tree():
		if _liquid_notifier.screen_entered.is_connected(_on_liquid_screen_entered):
			_liquid_notifier.screen_entered.disconnect(_on_liquid_screen_entered)
		if _liquid_notifier.screen_exited.is_connected(_on_liquid_screen_exited):
			_liquid_notifier.screen_exited.disconnect(_on_liquid_screen_exited)


## Evaluates whether physics processing should remain active for hold, rigidbody, or sloshing.
func _update_process_state() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	var base_active: bool = is_held or is_in_water or not sleeping or _standing_lock_ticks > 0
	var slosh_active: bool = _is_sloshing and _is_on_screen
	set_physics_process(base_active or slosh_active)


## Steps base [PickableObject] physics and updates the Verlet liquid slosh simulation.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	super._physics_process(delta)
	if _is_on_screen:
		_step_liquid_slosh(delta)


## Attaches bottle to player hold target and injects a grab slosh impulse.
func pick_up(target: Marker3D, player_node: Node3D) -> void:
	super.pick_up(target, player_node)
	if is_held:
		apply_slosh_impulse(Vector2(0.35, -0.25), 0.45)


## Releases bottle from player grasp and injects a release slosh impulse.
func drop() -> void:
	var was_held: bool = is_held
	super.drop()
	if was_held:
		apply_slosh_impulse(Vector2(-0.4, 0.35), 0.5)


## Throws bottle with [param impulse_vector] and agitates the internal liquid.
func throw(impulse_vector: Vector3) -> void:
	super.throw(impulse_vector)
	var horiz_impulse: Vector2 = Vector2(impulse_vector.x, impulse_vector.z) * 0.12
	apply_slosh_impulse(horiz_impulse.limit_length(1.4), 1.0)


## Routes hold transparency to [code]held_fade[/code] on [BottleMesh] to preserve next_pass.
func set_model_transparency(parent_node: Node, alpha: float) -> void:
	if not is_instance_valid(parent_node):
		return

	if parent_node == _bottle_mesh:
		_bottle_mesh.set_instance_shader_parameter(PARAM_HELD_FADE, alpha)
	elif parent_node is GeometryInstance3D:
		var geom: GeometryInstance3D = parent_node as GeometryInstance3D
		geom.transparency = alpha

	for child: Node in parent_node.get_children():
		set_model_transparency(child, alpha)


## Updates the normalized liquid fill level [0.0..1.0] and pushes to the instance uniform.
func set_fill(value: float) -> void:
	fill = clampf(value, 0.0, 1.0)
	if is_inside_tree() and is_instance_valid(_bottle_mesh):
		_bottle_mesh.set_instance_shader_parameter(PARAM_FILL, fill)


## Updates the liquid color and alpha transparency and pushes to the instance uniform.
func set_liquid_color(value: Color) -> void:
	liquid_color = value
	if is_inside_tree() and is_instance_valid(_bottle_mesh):
		_bottle_mesh.set_instance_shader_parameter(PARAM_COLOR, liquid_color)


## Updates the simulated glass wall thickness and pushes to the instance uniform.
func set_glass_thickness(value: float) -> void:
	glass_thickness = clampf(value, 0.0, 1.0)
	if is_inside_tree() and is_instance_valid(_bottle_mesh):
		_bottle_mesh.set_instance_shader_parameter(PARAM_THICKNESS, glass_thickness * _mesh_size.x)


## Enables or disables rising carbonation bubbles and surface foam when shaken.
func set_gas(value: bool) -> void:
	gas = value
	if not gas:
		_vel = 0.0
		if is_inside_tree() and is_instance_valid(_bottle_mesh):
			_bottle_mesh.set_instance_shader_parameter(PARAM_VEL, 0.0)


## Injects an instantaneous slosh impulse into the liquid surface and wakes slosh physics.
func apply_slosh_impulse(impulse: Vector2, agitation: float = 1.0) -> void:
	_coeff = (_coeff + impulse).limit_length(1.5)
	if gas:
		_vel = clampf(_vel + agitation, 0.0, 1.0)
	_wake_slosh()
	print("PickableLiquidBottle [%s]: slosh impulse applied (%s)" % [name, str(impulse)])


## Handles physical collisions by dealing projectile damage and agitating the liquid.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)
	var impact_speed: float = _last_velocity.length()
	if impact_speed > 0.4:
		var strength: float = clampf(impact_speed * 0.2, 0.15, 1.4)
		apply_slosh_impulse(
			Vector2(_last_velocity.x, _last_velocity.z).normalized() * strength,
			clampf(impact_speed * 0.25, 0.2, 1.0)
		)


## Steps the 2D Verlet spring-damper slosh equation and puts slosh state to sleep when settled.
func _step_liquid_slosh(delta: float) -> void:
	if not is_instance_valid(_bottle_mesh) or not is_inside_tree():
		return

	var safe_delta: float = maxf(delta, 0.001)
	var inv_dt_sq: float = 1.0 / (safe_delta * safe_delta)
	var current_pt: Vector3 = _get_effective_point()

	var accel_3d: Vector3 = (current_pt - 2.0 * _pos3 + _pos2) * inv_dt_sq
	_pos1 = _pos2
	_pos2 = _pos3
	_pos3 = current_pt

	var accel: Vector2 = (
		Vector2(accel_3d.x + accel_3d.y * 0.35, accel_3d.z + accel_3d.y * 0.35).limit_length(80.0)
	)

	_coeff_old_old = _coeff_old
	_coeff_old = _coeff

	var spring_term: Vector2 = (
		safe_delta * safe_delta * (-SPRING_CONSTANT * _coeff_old - REACTION_STRENGTH * accel)
	)
	var damping_term: Vector2 = safe_delta * DAMPENING * (_coeff_old - _coeff_old_old)
	_coeff = (spring_term + 2.0 * _coeff_old - _coeff_old_old - damping_term).limit_length(1.6)

	var moved_dist_sq: float = _pos1.distance_squared_to(_pos3)
	if not gas:
		_vel = 0.0
	elif moved_dist_sq < MOTION_THRESHOLD_SQ and _coeff.length_squared() < 0.01:
		_vel = clampf(_vel - safe_delta * 0.85, 0.0, 1.0)
	else:
		_vel = clampf(_vel + safe_delta * 3.5, 0.0, 1.0)

	var scaled_coeff: Vector2 = _coeff * liquid_mobility
	_bottle_mesh.set_instance_shader_parameter(PARAM_COEFF, scaled_coeff)
	_bottle_mesh.set_instance_shader_parameter(PARAM_VEL, _vel)

	var delta_coeff_sq: float = (_coeff - _coeff_old).length_squared()
	if (
		_coeff.length_squared() < SLEEP_THRESHOLD_SQ
		and delta_coeff_sq < SLEEP_THRESHOLD_SQ
		and moved_dist_sq < SLEEP_THRESHOLD_SQ
		and _vel <= 0.001
	):
		_coeff = Vector2.ZERO
		_coeff_old = Vector2.ZERO
		_coeff_old_old = Vector2.ZERO
		_vel = 0.0
		_is_sloshing = false
		_bottle_mesh.set_instance_shader_parameter(PARAM_COEFF, Vector2.ZERO)
		_bottle_mesh.set_instance_shader_parameter(PARAM_VEL, 0.0)
		_update_process_state()
	else:
		_is_sloshing = true


## Returns the world-space position of the bottle top to capture linear and angular motion.
func _get_effective_point() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	return global_position + global_transform.basis.y * _mesh_size.y


## Caches the bottle mesh AABB dimensions and uploads scale/size instance parameters.
func _sync_mesh_metrics() -> void:
	if not is_instance_valid(_bottle_mesh) or _bottle_mesh.mesh == null:
		return
	_mesh_size = _bottle_mesh.get_aabb().size * _bottle_mesh.scale.abs()
	var half_size: Vector2 = Vector2(_mesh_size.x * 0.5, _mesh_size.y * 0.5)
	var safe_scale_y: float = maxf(scale.y * absf(_bottle_mesh.scale.y), 0.001)
	var uv_scale: float = _mesh_size.y * 4.0 / safe_scale_y
	_bottle_mesh.set_instance_shader_parameter(PARAM_SIZE, half_size)
	_bottle_mesh.set_instance_shader_parameter(PARAM_SCALE, uv_scale)


## Uploads all static and dynamic instance shader parameters to the bottle mesh.
func _apply_all_parameters() -> void:
	if not is_inside_tree() or not is_instance_valid(_bottle_mesh):
		return
	_bottle_mesh.set_instance_shader_parameter(PARAM_FILL, fill)
	_bottle_mesh.set_instance_shader_parameter(PARAM_COLOR, liquid_color)
	_bottle_mesh.set_instance_shader_parameter(PARAM_THICKNESS, glass_thickness * _mesh_size.x)
	_bottle_mesh.set_instance_shader_parameter(PARAM_COEFF, _coeff * liquid_mobility)
	_bottle_mesh.set_instance_shader_parameter(PARAM_VEL, _vel)
	_bottle_mesh.set_instance_shader_parameter(PARAM_HELD_FADE, 0.0)


## Wakes up the slosh simulation and refreshes the physics process state.
func _wake_slosh() -> void:
	if not is_inside_tree():
		return
	if not _is_sloshing:
		_pos1 = _get_effective_point()
		_pos2 = _pos1
		_pos3 = _pos1
	_is_sloshing = true
	_update_process_state()


## Handles [signal VisibleOnScreenNotifier3D.screen_entered] to resume active sloshing.
func _on_liquid_screen_entered() -> void:
	_is_on_screen = true
	if not sleeping or _coeff.length_squared() >= SLEEP_THRESHOLD_SQ or _vel > 0.001:
		_wake_slosh()


## Handles [signal VisibleOnScreenNotifier3D.screen_exited] to suspend off-screen slosh updates.
func _on_liquid_screen_exited() -> void:
	_is_on_screen = false
	_update_process_state()
