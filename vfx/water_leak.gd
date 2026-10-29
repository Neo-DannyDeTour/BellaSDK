@tool
## Pressurized 3D water pipe leak controller managing stream, mist, and ballistic splash emitters.
class_name WaterLeak
extends Node3D

## Shader instance parameter key for per-instance water color tinting.
const PARAM_LEAK_COLOR: StringName = &"leak_color"
## Shader instance parameter key for particle camera billboarding toggle.
const PARAM_IS_BILLBOARD: StringName = &"is_billboard"
## Deferred method name for coalescing ballistic raycast updates.
const METHOD_UPDATE_ARC: StringName = &"_update_arc"
## Number of linear segments used to approximate the parabolic trajectory.
const ARC_STEPS: int = 8
## Maximum lifetime in seconds simulated along the ballistic arc before miss fallback.
const MAX_ARC_TIME: float = 1.5
## Standard downward gravity vector matching [ParticleProcessMaterial] defaults.
const GRAVITY_VEC: Vector3 = Vector3(0.0, -9.8, 0.0)
## Physics collision mask for Layer 1 (Environment).
const ENV_COLLISION_MASK: int = 1
## Physics collision mask for Layer 2 (Player).
const PLAYER_COLLISION_MASK: int = 2

## Water color tint applied across all child particle emitters via instance uniforms.
@export var leak_color: Color = Color(0.4, 0.7, 0.9, 0.6):
	set(value):
		leak_color = value
		if is_inside_tree():
			_apply_color()

## Initial ejection velocity in meters per second governing stream arc distance.
@export_range(0.5, 25.0, 0.1) var leak_speed: float = 6.0:
	set(value):
		var clamped: float = maxf(0.5, value)
		if is_equal_approx(leak_speed, clamped):
			return
		leak_speed = clamped
		if is_inside_tree():
			_apply_speed()
			call_deferred(METHOD_UPDATE_ARC)

## Total particle count distributed proportionally across stream, mist, and splash emitters.
@export_range(12, 2048, 1) var leak_amount: int = 256:
	set(value):
		var clamped: int = maxi(12, value)
		if leak_amount == clamped:
			return
		leak_amount = clamped
		if is_inside_tree():
			_apply_amount()

@export_group("Spurt Dynamics")
## Enables stochastic spurts and irregular dripping instead of a continuous uniform jet.
@export var uneven_spawn: bool = true:
	set(value):
		uneven_spawn = value
		if is_inside_tree():
			if uneven_spawn and _is_on_screen:
				_schedule_spurt()
			else:
				_reset_spurt()

## Controls interval variation between high-pressure bursts and low-pressure drips.
@export_range(0.1, 2.0, 0.05) var spurt_irregularity: float = 0.6

@export_group("Screen VFX")
## Triggers screen water droplets on the player when standing under or inside the leak spray.
@export var trigger_screen_vfx: bool = true

## Target droplet intensity dispatched to [ScreenEffectsManager] upon entering the spray.
@export_range(0.1, 1.5, 0.05) var screen_vfx_intensity: float = 0.85

var _has_impact_hit: bool = false
var _is_on_screen: bool = true
var _arc_update_queued: bool = false
var _is_player_in_zone: bool = false
var _is_spurt_scheduled: bool = false

@onready var _jet_stream: GPUParticles3D = $JetStream
@onready var _mist_spray: GPUParticles3D = $MistSpray
@onready var _impact_splash: GPUParticles3D = $ImpactSplash
@onready var _leak_audio: AudioStreamPlayer3D = $LeakAudio
@onready var _screen_notifier: VisibleOnScreenNotifier3D = $ScreenNotifier
@onready var _splash_zone: Area3D = $SplashZone
@onready var _splash_shape: CollisionShape3D = $SplashZone/CollisionShape3D


## Validates child nodes, binds culling signals, and initializes particle parameters.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(is_instance_valid(_jet_stream), "WaterLeak: Missing JetStream GPUParticles3D.")
	assert(is_instance_valid(_mist_spray), "WaterLeak: Missing MistSpray GPUParticles3D.")
	assert(is_instance_valid(_impact_splash), "WaterLeak: Missing ImpactSplash GPUParticles3D.")
	assert(is_instance_valid(_leak_audio), "WaterLeak: Missing LeakAudio AudioStreamPlayer3D.")
	assert(is_instance_valid(_screen_notifier), "WaterLeak: Missing ScreenNotifier node.")
	assert(is_instance_valid(_splash_zone), "WaterLeak: Missing SplashZone Area3D node.")
	assert(is_instance_valid(_splash_shape), "WaterLeak: Missing CollisionShape3D on SplashZone.")

	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)

	_splash_zone.collision_layer = 0
	_splash_zone.collision_mask = PLAYER_COLLISION_MASK
	_splash_zone.body_entered.connect(_on_player_entered_zone)
	_splash_zone.body_exited.connect(_on_player_exited_zone)

	_mist_spray.set_instance_shader_parameter(PARAM_IS_BILLBOARD, true)
	_jet_stream.set_instance_shader_parameter(PARAM_IS_BILLBOARD, false)
	_impact_splash.set_instance_shader_parameter(PARAM_IS_BILLBOARD, false)

	_apply_color()
	_apply_amount()
	_apply_speed()
	_queue_arc_update()

	if uneven_spawn:
		_schedule_spurt()


## Clears screen droplets if destroyed while the player is standing inside the spray zone.
func _exit_tree() -> void:
	if _is_player_in_zone and trigger_screen_vfx:
		Events.rain_vfx_toggled.emit(0.0)


## Re-evaluates ballistic impact position if the leak node transform changes in the tree.
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		_queue_arc_update()


## Applies per-instance shader color to all three particle emitters without duplicating materials.
func _apply_color() -> void:
	_jet_stream.set_instance_shader_parameter(PARAM_LEAK_COLOR, leak_color)
	_mist_spray.set_instance_shader_parameter(PARAM_LEAK_COLOR, leak_color)
	_impact_splash.set_instance_shader_parameter(PARAM_LEAK_COLOR, leak_color)


## Splits total particle budget across stream (50%), mist (25%), and splash (25%).
func _apply_amount() -> void:
	var jet_count: int = maxi(4, leak_amount >> 1)
	var sub_count: int = maxi(4, leak_amount >> 2)
	if _jet_stream.amount != jet_count:
		_jet_stream.amount = jet_count
	if _mist_spray.amount != sub_count:
		_mist_spray.amount = sub_count
	if _impact_splash.amount != sub_count:
		_impact_splash.amount = sub_count
	print("WaterLeak [%s]: particle budget set to %d" % [name, leak_amount])


## Updates initial velocity ranges on scene-local process materials for stream and mist.
func _apply_speed() -> void:
	var jet_mat: ParticleProcessMaterial = _jet_stream.process_material as ParticleProcessMaterial
	if is_instance_valid(jet_mat):
		jet_mat.initial_velocity_min = leak_speed * 0.92
		jet_mat.initial_velocity_max = leak_speed * 1.08

	var mist_mat: ParticleProcessMaterial = _mist_spray.process_material as ParticleProcessMaterial
	if is_instance_valid(mist_mat):
		mist_mat.initial_velocity_min = leak_speed * 0.55
		mist_mat.initial_velocity_max = leak_speed * 0.85


## Schedules next irregular spurt modulation step using non-allocating scene tree timer.
func _schedule_spurt() -> void:
	if _is_spurt_scheduled or not is_inside_tree() or not _is_on_screen or not uneven_spawn:
		return
	_is_spurt_scheduled = true
	var delay: float = randf_range(0.2, 0.75) * spurt_irregularity
	get_tree().create_timer(delay, false).timeout.connect(_on_spurt_cycle)


## Randomly modulates particle emission ratios to simulate realistic dripping and pressure surges.
func _on_spurt_cycle() -> void:
	_is_spurt_scheduled = false
	if not is_inside_tree() or not _is_on_screen or not uneven_spawn:
		_reset_spurt()
		return

	var is_surge: bool = randf() > 0.35
	var ratio: float = randf_range(0.7, 1.0) if is_surge else randf_range(0.15, 0.45)
	_jet_stream.amount_ratio = ratio
	_mist_spray.amount_ratio = ratio * 0.9
	_impact_splash.amount_ratio = ratio if _has_impact_hit else 0.0

	_schedule_spurt()


## Resets particle emission ratios back to full continuous flow.
func _reset_spurt() -> void:
	_is_spurt_scheduled = false
	_jet_stream.amount_ratio = 1.0
	_mist_spray.amount_ratio = 1.0
	_impact_splash.amount_ratio = 1.0


## Queues a single deferred parabolic raycast update per frame.
func _queue_arc_update() -> void:
	if _arc_update_queued:
		return
	_arc_update_queued = true
	call_deferred(METHOD_UPDATE_ARC)


## Solves the 8-step ballistic parabola against Layer 1 Environment and positions [ImpactSplash].
func _update_arc() -> void:
	_arc_update_queued = false
	if not is_inside_tree():
		return

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position
	var v0: Vector3 = -global_basis.z * leak_speed
	var dt: float = MAX_ARC_TIME / float(ARC_STEPS)
	var prev_pt: Vector3 = origin
	var hit_found: bool = false
	var hit_pos: Vector3 = origin
	var hit_normal: Vector3 = Vector3.UP
	var hit_time: float = MAX_ARC_TIME

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.collision_mask = ENV_COLLISION_MASK
	query.hit_from_inside = false

	var local_bounds: AABB = AABB(Vector3.ZERO, Vector3.ZERO)

	for i: int in range(1, ARC_STEPS + 1):
		var t: float = float(i) * dt
		var next_pt: Vector3 = origin + (v0 * t) + (0.5 * GRAVITY_VEC * t * t)
		query.from = prev_pt
		query.to = next_pt
		var result: Dictionary = space_state.intersect_ray(query)

		if not result.is_empty():
			hit_found = true
			var raw_pos: Variant = result.get(&"position")
			if raw_pos is Vector3:
				hit_pos = raw_pos
			var raw_normal: Variant = result.get(&"normal")
			if raw_normal is Vector3:
				hit_normal = raw_normal

			var seg_len: float = prev_pt.distance_to(next_pt)
			var frac: float = prev_pt.distance_to(hit_pos) / seg_len if seg_len > 0.0001 else 1.0
			hit_time = maxf(0.08, (float(i - 1) + frac) * dt)
			local_bounds = local_bounds.expand(to_local(hit_pos))
			break

		local_bounds = local_bounds.expand(to_local(next_pt))
		prev_pt = next_pt

	_has_impact_hit = hit_found
	_jet_stream.lifetime = hit_time

	if hit_found:
		_impact_splash.global_position = hit_pos
		_impact_splash.global_basis = _basis_from_normal(hit_normal)

	_screen_notifier.aabb = local_bounds.grow(0.75)

	if is_instance_valid(_splash_shape) and _splash_shape.shape is BoxShape3D:
		var padded: AABB = local_bounds.grow(1.2)
		(_splash_shape.shape as BoxShape3D).size = padded.size.max(Vector3(1.5, 1.5, 1.5))
		_splash_shape.position = padded.get_center()

	_sync_emission_state()


## Constructs an orthonormal [Basis] with its Y axis aligned to the provided surface normal.
func _basis_from_normal(normal: Vector3) -> Basis:
	var n: Vector3 = normal.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(n.y) > 0.99 else Vector3.UP
	var x_axis: Vector3 = ref.cross(n).normalized()
	var z_axis: Vector3 = n.cross(x_axis).normalized()
	return Basis(x_axis, n, z_axis)


## Synchronizes emitter and audio activity with screen visibility and surface contact state.
func _sync_emission_state() -> void:
	_jet_stream.emitting = _is_on_screen
	_mist_spray.emitting = _is_on_screen
	_impact_splash.emitting = _is_on_screen and _has_impact_hit
	_leak_audio.stream_paused = not _is_on_screen


## Dispatches screen rain droplet VFX when the player body enters the water spray zone.
func _on_player_entered_zone(body: Node3D) -> void:
	if not trigger_screen_vfx:
		return
	if body.is_in_group(&"player") or body.is_class("Player") or body.name == "Player":
		_is_player_in_zone = true
		Events.rain_vfx_toggled.emit(screen_vfx_intensity)
		print("WaterLeak [%s]: Player entered water zone -> rain screen VFX active" % name)


## Stops screen water droplets when the player leaves the water spray zone.
func _on_player_exited_zone(body: Node3D) -> void:
	if not trigger_screen_vfx:
		return
	if body.is_in_group(&"player") or body.is_class("Player") or body.name == "Player":
		_is_player_in_zone = false
		Events.rain_vfx_toggled.emit(0.0)
		print("WaterLeak [%s]: Player exited water zone -> rain screen VFX fading" % name)


## Enables particle simulation and resumes audio when entering the camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_sync_emission_state()
	if uneven_spawn:
		_schedule_spurt()
	print("WaterLeak [%s]: active (screen entered)" % name)


## Halts particle simulation and pauses audio when leaving the camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_sync_emission_state()
	print("WaterLeak [%s]: culled (screen exited)" % name)
