@tool
## Event-driven controller for the Combine Citadel Core reactor assembly.
## Synchronizes shader instance uniforms, light intensity, and plasma arcs via [Tween].
class_name ArgonCitadelCore
extends Node3D

## Per-instance shader uniform controlling the normalized 4-second reactor cycle.
const PARAM_PULSE_PHASE: StringName = &"pulse_phase"
## Per-instance shader uniform seeding plasma arc vertex displacement.
const PARAM_ARC_SEED: StringName = &"arc_seed"
## Full duration of one expansion-collapse pulse cycle in seconds.
const CYCLE_DURATION: float = 4.0
## Duration of each quarter-phase stage (shrink, small-hold, expand, huge-hold) in seconds.
const QUARTER_DURATION: float = 1.0
## Duration of an individual plasma lightning discharge in seconds.
const ARC_DURATION: float = 0.38
## Maximum squared camera distance (45m) before skipping high-frequency arc sub-tweens.
const MAX_ARC_DIST_SQ: float = 2025.0
## Local center of the suspended ferrofluid core sphere.
const CORE_ORIGIN: Vector3 = Vector3(0.0, 4.0, 0.0)
## Orange expansion light color.
const COLOR_ORANGE: Color = Color(1.0, 0.48, 0.12, 1.0)
## Cyan surge light color.
const COLOR_CYAN: Color = Color(0.2, 0.88, 1.0, 1.0)
## Dark reset light color.
const COLOR_DARK: Color = Color(0.08, 0.22, 0.35, 1.0)
## Pre-calculated emitter and claw endpoints at ~4.2m radius from [member CORE_ORIGIN].
const ARC_TARGETS: Array[Vector3] = [
	Vector3(0.0, 6.2, -3.58),
	Vector3(0.0, 6.2, 3.58),
	Vector3(3.58, 6.2, 0.0),
	Vector3(-3.58, 6.2, 0.0),
	Vector3(-3.8, 2.2, 0.0),
	Vector3(3.8, 2.2, 0.0),
]

var _pulse_tween: Tween = null
var _arc_tween_a: Tween = null
var _arc_tween_b: Tween = null
var _burst_counter: int = 0

@onready var _inner_core: MeshInstance3D = $InnerCore as MeshInstance3D
@onready var _outer_shell: MeshInstance3D = $OuterShell as MeshInstance3D
@onready var _corona_halo: MeshInstance3D = $CoronaHalo as MeshInstance3D
@onready var _corona_waves: MeshInstance3D = $CoronaWaves as MeshInstance3D
@onready var _axial_beam: MeshInstance3D = $AxialBeam as MeshInstance3D
@onready var _arc_ribbon_a: MeshInstance3D = $ArcRibbonA as MeshInstance3D
@onready var _arc_ribbon_b: MeshInstance3D = $ArcRibbonB as MeshInstance3D
@onready var _core_light: OmniLight3D = $CoreLight as OmniLight3D
@onready var _visibility_notifier: VisibleOnScreenNotifier3D = (
	$VisibilityNotifier as VisibleOnScreenNotifier3D
)


## Validates child nodes, disables per-frame polling, and starts the reactor cycle.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(is_instance_valid(_inner_core), "ArgonCitadelCore: InnerCore missing.")
	assert(is_instance_valid(_outer_shell), "ArgonCitadelCore: OuterShell missing.")
	assert(is_instance_valid(_corona_halo), "ArgonCitadelCore: CoronaHalo missing.")
	assert(is_instance_valid(_corona_waves), "ArgonCitadelCore: CoronaWaves missing.")
	assert(is_instance_valid(_axial_beam), "ArgonCitadelCore: AxialBeam missing.")
	assert(is_instance_valid(_arc_ribbon_a), "ArgonCitadelCore: ArcRibbonA missing.")
	assert(is_instance_valid(_arc_ribbon_b), "ArgonCitadelCore: ArcRibbonB missing.")
	assert(is_instance_valid(_core_light), "ArgonCitadelCore: CoreLight missing.")
	assert(is_instance_valid(_visibility_notifier), "ArgonCitadelCore: VisibilityNotifier missing.")

	_arc_ribbon_a.set_instance_shader_parameter(PARAM_PULSE_PHASE, 0.0)
	_arc_ribbon_b.set_instance_shader_parameter(PARAM_PULSE_PHASE, 0.0)

	if not _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
		_visibility_notifier.screen_entered.connect(_on_screen_entered)
	if not _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
		_visibility_notifier.screen_exited.connect(_on_screen_exited)

	_start_core_cycle()


## Disconnects notifier signals and kills active [Tween] instances on tree exit.
func _exit_tree() -> void:
	if is_instance_valid(_visibility_notifier):
		if _visibility_notifier.screen_entered.is_connected(_on_screen_entered):
			_visibility_notifier.screen_entered.disconnect(_on_screen_entered)
		if _visibility_notifier.screen_exited.is_connected(_on_screen_exited):
			_visibility_notifier.screen_exited.disconnect(_on_screen_exited)
	_stop_core_cycle()


## Starts or restarts the looping 4-second reactor [Tween] sequence with 1.0s quarters.
func _start_core_cycle() -> void:
	if not is_inside_tree():
		return
	_stop_core_cycle()
	print("ArgonCitadelCore: Pulse loop active.")

	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_callback(_on_phase_orange)
	_pulse_tween.tween_method(_apply_pulse_phase, 0.0, 0.25, QUARTER_DURATION)
	_pulse_tween.tween_callback(_trigger_arc_burst)
	_pulse_tween.tween_method(_apply_pulse_phase, 0.25, 0.50, QUARTER_DURATION)
	_pulse_tween.tween_callback(_on_phase_cyan)
	_pulse_tween.tween_method(_apply_pulse_phase, 0.50, 0.75, QUARTER_DURATION)
	_pulse_tween.tween_callback(_trigger_arc_burst)
	_pulse_tween.tween_method(_apply_pulse_phase, 0.75, 1.0, QUARTER_DURATION)


## Kills all active pulse and lightning arc [Tween] instances.
func _stop_core_cycle() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null

	if _arc_tween_a and _arc_tween_a.is_valid():
		_arc_tween_a.kill()
	_arc_tween_a = null

	if _arc_tween_b and _arc_tween_b.is_valid():
		_arc_tween_b.kill()
	_arc_tween_b = null


## Updates per-instance shader phase and interpolates [member _core_light] energy.
func _apply_pulse_phase(phase: float) -> void:
	if not is_inside_tree() or not is_instance_valid(_inner_core):
		return

	_inner_core.set_instance_shader_parameter(PARAM_PULSE_PHASE, phase)
	_outer_shell.set_instance_shader_parameter(PARAM_PULSE_PHASE, phase)
	_corona_halo.set_instance_shader_parameter(PARAM_PULSE_PHASE, phase)
	_corona_waves.set_instance_shader_parameter(PARAM_PULSE_PHASE, phase)
	_axial_beam.set_instance_shader_parameter(PARAM_PULSE_PHASE, phase)

	if phase < 0.25:
		var weight_ramp: float = phase * 4.0
		_core_light.light_color = COLOR_DARK.lerp(COLOR_ORANGE, weight_ramp)
		_core_light.light_energy = lerpf(2.0, 8.2, weight_ramp)
	elif phase < 0.50:
		_core_light.light_color = COLOR_ORANGE
		_core_light.light_energy = 8.2
	elif phase < 0.75:
		var weight_cool: float = (phase - 0.50) * 4.0
		_core_light.light_color = COLOR_ORANGE.lerp(COLOR_CYAN, weight_cool)
		_core_light.light_energy = lerpf(8.2, 4.8, weight_cool)
	else:
		var weight_quench: float = (phase - 0.75) * 4.0
		_core_light.light_color = COLOR_CYAN.lerp(COLOR_DARK, weight_quench)
		_core_light.light_energy = lerpf(4.8, 2.0, weight_quench)


## Logs discrete transition into the orange outward-wave eruption stage.
func _on_phase_orange() -> void:
	print("ArgonCitadelCore: Phase -> RING_SHRINK_ORANGE_ERUPTION")


## Logs discrete transition into the blue inward-wave quench stage.
func _on_phase_cyan() -> void:
	print("ArgonCitadelCore: Phase -> RING_EXPAND_BLUE_QUENCH")


## Fires both pooled plasma ribbons toward opposite chamber anchors if within camera range.
func _trigger_arc_burst() -> void:
	if not is_inside_tree() or not is_instance_valid(_arc_ribbon_a):
		return

	var viewport: Viewport = get_viewport()
	if is_instance_valid(viewport):
		var cam: Camera3D = viewport.get_camera_3d()
		if is_instance_valid(cam):
			var dist_sq: float = global_position.distance_squared_to(cam.global_position)
			if dist_sq > MAX_ARC_DIST_SQ:
				return

	var count: int = ARC_TARGETS.size()
	var idx_a: int = _burst_counter % count
	var idx_b: int = (_burst_counter + 3) % count
	_burst_counter += 1

	print("ArgonCitadelCore: Plasma arc discharge [", idx_a, ", ", idx_b, "]")
	_fire_arc_ribbon(_arc_ribbon_a, ARC_TARGETS[idx_a], true)
	_fire_arc_ribbon(_arc_ribbon_b, ARC_TARGETS[idx_b], false)


## Positions a ribbon midpoint between [member CORE_ORIGIN] and target, then tweens fade.
func _fire_arc_ribbon(ribbon: MeshInstance3D, target: Vector3, is_primary: bool) -> void:
	if not is_inside_tree() or not is_instance_valid(ribbon):
		return

	var mid_local: Vector3 = (CORE_ORIGIN + target) * 0.5
	var world_mid: Vector3 = to_global(mid_local)
	var world_target: Vector3 = to_global(target)
	ribbon.look_at_from_position(world_mid, world_target, Vector3.UP)
	ribbon.set_instance_shader_parameter(PARAM_ARC_SEED, float(_burst_counter) * 1.73)

	if is_primary:
		if _arc_tween_a and _arc_tween_a.is_valid():
			_arc_tween_a.kill()
		_arc_tween_a = create_tween()
		_arc_tween_a.tween_method(_set_arc_a_fade, 1.0, 0.0, ARC_DURATION)
	else:
		if _arc_tween_b and _arc_tween_b.is_valid():
			_arc_tween_b.kill()
		_arc_tween_b = create_tween()
		_arc_tween_b.tween_method(_set_arc_b_fade, 1.0, 0.0, ARC_DURATION)


## Sets per-instance fade uniform on [member _arc_ribbon_a].
func _set_arc_a_fade(val: float) -> void:
	if is_inside_tree() and is_instance_valid(_arc_ribbon_a):
		_arc_ribbon_a.set_instance_shader_parameter(PARAM_PULSE_PHASE, val)


## Sets per-instance fade uniform on [member _arc_ribbon_b].
func _set_arc_b_fade(val: float) -> void:
	if is_inside_tree() and is_instance_valid(_arc_ribbon_b):
		_arc_ribbon_b.set_instance_shader_parameter(PARAM_PULSE_PHASE, val)


## Resumes reactor cycle when entering camera frustum.
func _on_screen_entered() -> void:
	print("ArgonCitadelCore: Entered screen -> resuming reactor.")
	_start_core_cycle()


## Suspends reactor cycle when exiting camera frustum.
func _on_screen_exited() -> void:
	print("ArgonCitadelCore: Exited screen -> pausing reactor.")
	_stop_core_cycle()
