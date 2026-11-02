@tool
## Controls a pressurized high-velocity fire jet on Render Layer 10 (Volumetrics).
## Drives per-instance shader uniforms, light intensity, and player hazard damage.
class_name PressurizedFireJet
extends Node3D

## Instance shader uniform key controlling UV axial scroll velocity.
const PARAM_JET_SPEED: StringName = &"jet_speed"

## Instance shader uniform key controlling Mach core heat and blue-shift.
const PARAM_CORE_HEAT: StringName = &"core_heat"

## Instance shader uniform key controlling world-space axial noise tiling.
const PARAM_AXIAL_TILE: StringName = &"axial_tile"

## Unscaled height of the base [CylinderMesh] primitive in meters.
const BASE_MESH_HEIGHT: float = 2.0

## Unscaled outer radius of the base [CylinderMesh] plume in meters.
const BASE_PLUME_RADIUS: float = 0.22

## Minimum UV scroll speed when pressure approaches cutoff.
const MIN_SPEED: float = 2.5

## Maximum UV scroll speed at full blowtorch pressure.
const MAX_SPEED: float = 22.0

## Minimum axial mesh scale factor at low pressure.
const MIN_LENGTH_SCALE: float = 0.15

## Maximum axial mesh scale factor at full pressure.
const MAX_LENGTH_SCALE: float = 1.0

## Peak [member OmniLight3D.light_energy] emitted at full pressure.
const MAX_LIGHT_ENERGY: float = 3.5

## Pressure threshold below which rendering, lighting, and damage are disabled.
const CUTOFF_PRESSURE: float = 0.01

## Margin in meters added to axial reach checks for character capsule radius.
const BODY_RADIUS_MARGIN: float = 0.45

## Mesh instance rendering the pressurized flame jet cylinder.
@export var jet_mesh: MeshInstance3D

## Dynamic light emitting from the jet nozzle orifice.
@export var jet_light: OmniLight3D

## Visibility notifier managing frustum culling and gating shader updates.
@export var screen_notifier: VisibleOnScreenNotifier3D

## Hazard volume detecting player overlap along the flame jet path.
@export var hazard_area: Area3D

## Collision shape defining the cylindrical hazard volume bounds.
@export var hazard_shape: CollisionShape3D

## Distance in meters from nozzle origin to plume tip at full pressure.
@export_range(0.5, 50.0, 0.25) var jet_length: float = 6.0:
	set(value):
		jet_length = maxf(0.5, value)
		if is_inside_tree():
			_sync_bounds()
			_apply_pressure_state(_pressure)

## Radial thickness multiplier applied to plume cross-section on X and Z axes.
@export_range(0.1, 5.0, 0.05) var radius_scale: float = 1.0:
	set(value):
		radius_scale = maxf(0.1, value)
		if is_inside_tree():
			_sync_bounds()
			_apply_pressure_state(_pressure)

## Health points subtracted per damage tick while inside the active flame jet.
@export var damage_amount: int = 200

## Time interval in seconds between consecutive hazard damage ticks.
@export_range(0.05, 5.0, 0.05) var damage_interval: float = 0.2:
	set(value):
		damage_interval = maxf(0.05, value)
		if is_instance_valid(_damage_timer):
			_damage_timer.wait_time = damage_interval

## Enables automated cycling between active firing and inactive cooldown.
@export var cycle_enabled: bool = false

## Duration in seconds the jet sustains active firing per cycle.
@export_range(0.1, 60.0, 0.1) var active_time: float = 3.0

## Duration in seconds the jet stays completely inactive per cycle.
@export_range(0.1, 60.0, 0.1) var inactive_time: float = 2.0

## Duration in seconds to ramp pressure between active and inactive states.
@export_range(0.0, 5.0, 0.05) var ramp_time: float = 0.2

## Target normalized pressure reached during active phase in range [0.0, 1.0].
@export_range(0.0, 1.0, 0.05) var active_pressure: float = 1.0

## Current normalized operating pressure in range [0.0, 1.0].
var _pressure: float = 1.0

## Frustum visibility state updated by [member screen_notifier].
var _is_on_screen: bool = true

## Generation counter invalidating active cycle coroutines on stop or tree exit.
var _cycle_generation: int = 0

## Active tween interpolating pressure transitions.
var _tween: Tween

## Event-driven timer ticking periodic hazard damage on overlapping targets.
var _damage_timer: Timer

## Cached mapping of overlapping physics bodies to their [HealthComponent].
var _overlapping_targets: Dictionary[Node3D, HealthComponent] = {}


## Validates required nodes, assigns layers, configures hazard volume, and starts cycle.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(jet_mesh != null, "PressurizedFireJet: jet_mesh must be assigned.")
	assert(jet_light != null, "PressurizedFireJet: jet_light must be assigned.")
	assert(screen_notifier != null, "PressurizedFireJet: screen_notifier must be assigned.")
	assert(hazard_area != null, "PressurizedFireJet: hazard_area must be assigned.")
	assert(hazard_shape != null, "PressurizedFireJet: hazard_shape must be assigned.")

	jet_mesh.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	Utilities.safe_connect(screen_notifier.screen_entered, _on_screen_entered)
	Utilities.safe_connect(screen_notifier.screen_exited, _on_screen_exited)

	_setup_hazard_volume()
	_sync_bounds()

	_is_on_screen = screen_notifier.is_on_screen()
	if cycle_enabled:
		_pressure = 0.0
		_apply_pressure_state(0.0)
		start_cycle()
	else:
		_apply_pressure_state(_pressure)


## Cancels active cycle loops and stops damage timer when removing from scene tree.
func _exit_tree() -> void:
	_cycle_generation += 1
	if is_instance_valid(_damage_timer):
		_damage_timer.stop()
	_overlapping_targets.clear()


## Transitions fire jet pressure in range [0.0, 1.0] over [param transition_time] seconds.
func set_pressure(target_pressure: float, transition_time: float = 0.2) -> void:
	var clamped_target: float = clampf(target_pressure, 0.0, 1.0)
	print("PressurizedFireJet [%s]: pressure -> %.2f" % [name, clamped_target])

	if transition_time <= 0.0 or not is_inside_tree():
		if is_instance_valid(_tween) and _tween.is_valid():
			_tween.kill()
		_apply_pressure_state(clamped_target)
		return

	_tween = Utilities.reset_tween_ext(self, _tween, Tween.TRANS_QUAD, Tween.EASE_OUT)
	if _tween:
		_tween.tween_method(_apply_pressure_state, _pressure, clamped_target, transition_time)


## Starts automatic active/inactive duty cycle loop.
func start_cycle() -> void:
	cycle_enabled = true
	_cycle_generation += 1
	_run_cycle(_cycle_generation)


## Stops automatic duty cycle loop and ramps pressure down to cutoff.
func stop_cycle() -> void:
	cycle_enabled = false
	_cycle_generation += 1
	set_pressure(0.0, ramp_time)


## Configures [member hazard_area] collision masks, signals, and tick [Timer].
func _setup_hazard_volume() -> void:
	hazard_area.collision_layer = CollisionLayers.MASK_NONE
	hazard_area.collision_mask = CollisionLayers.MASK_PLAYER
	hazard_area.monitorable = false

	Utilities.safe_connect(hazard_area.body_entered, _on_hazard_body_entered)
	Utilities.safe_connect(hazard_area.body_exited, _on_hazard_body_exited)

	_damage_timer = Timer.new()
	_damage_timer.name = "DamageTimer"
	_damage_timer.wait_time = damage_interval
	_damage_timer.one_shot = false
	add_child(_damage_timer)
	Utilities.safe_connect(_damage_timer.timeout, _on_damage_timer_timeout)


## Synchronizes culling AABB and hazard cylinder dimensions to [member jet_length].
func _sync_bounds() -> void:
	var outer_radius: float = BASE_PLUME_RADIUS * radius_scale
	if is_instance_valid(screen_notifier):
		var margin: float = maxf(0.5, outer_radius * 2.0)
		screen_notifier.aabb = AABB(
			Vector3(-margin, -margin, -jet_length - 0.4),
			Vector3(margin * 2.0, margin * 2.0, jet_length + 0.6)
		)

	if is_instance_valid(hazard_shape):
		var cyl_shape: CylinderShape3D = null
		if hazard_shape.shape is CylinderShape3D:
			cyl_shape = hazard_shape.shape as CylinderShape3D
		else:
			cyl_shape = CylinderShape3D.new()
			cyl_shape.resource_local_to_scene = true
			hazard_shape.shape = cyl_shape
		cyl_shape.height = jet_length
		cyl_shape.radius = maxf(0.15, outer_radius)
		hazard_shape.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		hazard_shape.position = Vector3(0.0, 0.0, -jet_length * 0.5)


## Executes asynchronous active/inactive duty cycle loop for [param generation].
func _run_cycle(generation: int) -> void:
	while cycle_enabled and is_inside_tree() and generation == _cycle_generation:
		set_pressure(active_pressure, ramp_time)
		var active_timer: SceneTreeTimer = get_tree().create_timer(active_time + ramp_time)
		await active_timer.timeout
		if not cycle_enabled or not is_inside_tree() or generation != _cycle_generation:
			return

		set_pressure(0.0, ramp_time)
		var inactive_timer: SceneTreeTimer = get_tree().create_timer(inactive_time + ramp_time)
		await inactive_timer.timeout


## Updates instance shader uniforms, mesh transform, light energy, and hazard state.
func _apply_pressure_state(value: float) -> void:
	_pressure = value
	if not is_instance_valid(jet_mesh) or not is_instance_valid(jet_light):
		return

	var speed: float = lerpf(MIN_SPEED, MAX_SPEED, value)
	var pressure_len_factor: float = lerpf(MIN_LENGTH_SCALE, MAX_LENGTH_SCALE, value)
	var target_half_len: float = (jet_length / BASE_MESH_HEIGHT) * pressure_len_factor
	var pressure_rad_factor: float = lerpf(0.6, 1.0, value)
	var effective_radius: float = pressure_rad_factor * radius_scale

	jet_mesh.set_instance_shader_parameter(PARAM_JET_SPEED, speed)
	jet_mesh.set_instance_shader_parameter(PARAM_CORE_HEAT, value)
	jet_mesh.set_instance_shader_parameter(PARAM_AXIAL_TILE, maxf(0.25, target_half_len))
	# shortcut: mesh scale drives length, move to vertex shader if children attach to jet_mesh
	jet_mesh.scale = Vector3(effective_radius, target_half_len, effective_radius)
	jet_mesh.position = Vector3(0.0, -target_half_len, 0.0)
	jet_light.light_energy = value * MAX_LIGHT_ENERGY
	jet_light.omni_range = maxf(4.0, jet_length * 0.85)

	_update_visibility()
	_update_hazard_state()


## Toggles [member Node3D.visible] on mesh and light from screen state and cutoff threshold.
func _update_visibility() -> void:
	var should_render: bool = _is_on_screen and (_pressure > CUTOFF_PRESSURE)
	jet_mesh.visible = should_render
	jet_light.visible = should_render


## Updates [member hazard_area] monitoring and damage timer from pressure state.
func _update_hazard_state() -> void:
	if not is_instance_valid(hazard_area):
		return

	var is_active: bool = _pressure > CUTOFF_PRESSURE
	if hazard_area.monitoring != is_active:
		hazard_area.set_deferred(&"monitoring", is_active)

	if not is_active:
		_overlapping_targets.clear()
		if is_instance_valid(_damage_timer) and not _damage_timer.is_stopped():
			_damage_timer.stop()
	elif not _overlapping_targets.is_empty() and is_instance_valid(_damage_timer):
		if _damage_timer.is_stopped():
			_damage_timer.start()


## Registers overlapping player body, deals initial contact damage, and starts tick timer.
func _on_hazard_body_entered(body: Node3D) -> void:
	if not is_instance_valid(body):
		return

	var comp: HealthComponent = _resolve_health_component(body)
	if not is_instance_valid(comp):
		return

	_overlapping_targets[body] = comp
	if _pressure > CUTOFF_PRESSURE and _is_within_active_reach(body):
		comp.take_damage(damage_amount)

	if _pressure > CUTOFF_PRESSURE and is_instance_valid(_damage_timer):
		if _damage_timer.is_stopped():
			_damage_timer.start()


## Removes body from active damage tracking and stops timer when empty.
func _on_hazard_body_exited(body: Node3D) -> void:
	_overlapping_targets.erase(body)
	if _overlapping_targets.is_empty() and is_instance_valid(_damage_timer):
		_damage_timer.stop()


## Applies periodic [member damage_amount] to all valid targets inside active plume reach.
func _on_damage_timer_timeout() -> void:
	if _pressure <= CUTOFF_PRESSURE or _overlapping_targets.is_empty():
		if is_instance_valid(_damage_timer):
			_damage_timer.stop()
		return

	for body: Node3D in _overlapping_targets.keys():
		if not is_instance_valid(body):
			_overlapping_targets.erase(body)
			continue
		var comp: HealthComponent = _overlapping_targets.get(body)
		if not is_instance_valid(comp):
			_overlapping_targets.erase(body)
			continue
		if _is_within_active_reach(body):
			comp.take_damage(damage_amount)


## Checks whether [param body] lies within the current pressurized axial plume length.
func _is_within_active_reach(body: Node3D) -> bool:
	var current_reach: float = jet_length * lerpf(MIN_LENGTH_SCALE, MAX_LENGTH_SCALE, _pressure)
	var local_pos: Vector3 = to_local(body.global_position)
	var axial_dist: float = -local_pos.z
	return axial_dist >= -BODY_RADIUS_MARGIN and axial_dist <= (current_reach + BODY_RADIUS_MARGIN)


## Resolves [HealthComponent] on [param body] via property lookup or [NodeQuery].
func _resolve_health_component(body: Node3D) -> HealthComponent:
	if &"health_component" in body:
		var prop_val: Variant = body.get(&"health_component")
		if prop_val is HealthComponent:
			var typed_prop: HealthComponent = prop_val
			return typed_prop

	var direct_node: Node = body.get_node_or_null("Components/HealthComponent")
	if direct_node is HealthComponent:
		var typed_direct: HealthComponent = direct_node
		return typed_direct

	var child_comp: Node = NodeQuery.find_first_child_of_type(body, HealthComponent)
	if child_comp is HealthComponent:
		var typed_child: HealthComponent = child_comp
		return typed_child

	var comp_folder: Node = body.get_node_or_null("Components")
	if is_instance_valid(comp_folder):
		var folder_comp: Node = NodeQuery.find_first_child_of_type(comp_folder, HealthComponent)
		if folder_comp is HealthComponent:
			var typed_folder: HealthComponent = folder_comp
			return typed_folder

	return null


## Enables rendering when [member screen_notifier] enters camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_update_visibility()


## Disables rendering when [member screen_notifier] exits camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_update_visibility()
