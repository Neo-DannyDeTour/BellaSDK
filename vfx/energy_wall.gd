## Controls a 4-slot hit-reactive world-space shader ripple buffer on an energy
## barrier [MeshInstance3D]. Driven by external collision callers via [method trigger_hit]
## or [method take_damage] with zero per-frame loop cost.
# class_name EnergyWall
extends MeshInstance3D

## Instance uniform key for impact slot 0 (xyz = world_pos, w = ripple_progress).
const PARAM_HIT_SLOT_0: StringName = &"hit_slot_0"

## Instance uniform key for impact slot 1 (xyz = world_pos, w = ripple_progress).
const PARAM_HIT_SLOT_1: StringName = &"hit_slot_1"

## Instance uniform key for impact slot 2 (xyz = world_pos, w = ripple_progress).
const PARAM_HIT_SLOT_2: StringName = &"hit_slot_2"

## Instance uniform key for impact slot 3 (xyz = world_pos, w = ripple_progress).
const PARAM_HIT_SLOT_3: StringName = &"hit_slot_3"

## Total concurrent impact slots packed into the shader's mat4 hit_buffer.
const SLOT_COUNT: int = 4

## Inactive slot vector with progress (.w) set to 1.0.
const INACTIVE_SLOT: Vector4 = Vector4(0.0, 0.0, 0.0, 1.0)

## Duration in seconds for a single concentric ripple to expand and fade out.
@export_range(0.1, 5.0, 0.05) var ripple_duration: float = 0.85

## Fires periodic overlapping test ripples and enables mouse-click raycast hits.
@export var demo_auto_fire: bool = false

## Pre-allocated [StringName] uniform lookup table for the 4 mat4 columns.
var _slot_params: Array[StringName] = [
	PARAM_HIT_SLOT_0, PARAM_HIT_SLOT_1, PARAM_HIT_SLOT_2, PARAM_HIT_SLOT_3
]

## Packed 4x4 matrix where each column stores (world_pos.x, world_pos.y, world_pos.z, progress).
var _hit_buffer: Projection = Projection(INACTIVE_SLOT, INACTIVE_SLOT, INACTIVE_SLOT, INACTIVE_SLOT)

## Active per-slot [Tween] references for the 4 ring-buffer slots.
var _slot_tweens: Array[Tween] = [null, null, null, null]

## Next ring-buffer column index (0 to 3) to overwrite on impact.
var _next_slot: int = 0

## Repeating [Tween] driving automated overlapping showcase hits when [member demo_auto_fire] is on.
var _demo_tween: Tween = null

## Optional child [StaticBody3D] configured to Physics Layer 1 (Environment).
@onready var _static_body: StaticBody3D = get_node_or_null("StaticBody3D") as StaticBody3D

## Optional child [VisibleOnScreenNotifier3D] gating rendering when off-screen.
@onready var _screen_notifier: VisibleOnScreenNotifier3D = (
	get_node_or_null("ScreenNotifier") as VisibleOnScreenNotifier3D
)


## Validates [member mesh] invariant, assigns environment layers, and idles all 4 buffer slots.
func _ready() -> void:
	assert(mesh != null, "EnergyWall requires an assigned Mesh resource.")
	assert(ripple_duration > 0.0, "EnergyWall ripple_duration must exceed 0.0.")
	set_process(false)
	set_physics_process(false)
	set_process_unhandled_input(demo_auto_fire)

	layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	if is_instance_valid(_static_body):
		_static_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
		_static_body.collision_mask = CollisionLayers.MASK_NONE

	if is_instance_valid(_screen_notifier):
		Utilities.safe_connect(_screen_notifier.screen_entered, _on_screen_entered)
		Utilities.safe_connect(_screen_notifier.screen_exited, _on_screen_exited)

	_hit_buffer = Projection(INACTIVE_SLOT, INACTIVE_SLOT, INACTIVE_SLOT, INACTIVE_SLOT)
	for i: int in range(SLOT_COUNT):
		set_instance_shader_parameter(_slot_params[i], INACTIVE_SLOT)

	if demo_auto_fire:
		_start_demo_loop()


## Kills all active slot and demo [Tween] instances when leaving the [SceneTree].
func _exit_tree() -> void:
	for i: int in range(SLOT_COUNT):
		Utilities.safe_kill_tween(_slot_tweens[i])
		_slot_tweens[i] = null
	Utilities.safe_kill_tween(_demo_tween)
	_demo_tween = null


## Handles mouse-click raycast impacts and Spacebar 4-hit rapid burst in demo mode.
func _unhandled_input(event: InputEvent) -> void:
	if not demo_auto_fire or not is_inside_tree():
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var cam: Camera3D = get_viewport().get_camera_3d()
			if is_instance_valid(cam):
				var origin: Vector3 = cam.project_ray_origin(mouse_event.position)
				var target: Vector3 = origin + cam.project_ray_normal(mouse_event.position) * 50.0
				var hit: Dictionary = Utilities.raycast_3d(
					get_world_3d().direct_space_state,
					origin,
					target,
					CollisionLayers.MASK_ENVIRONMENT
				)
				if not hit.is_empty() and hit.has("position"):
					var hit_pos_variant: Variant = hit.get("position")
					if hit_pos_variant is Vector3:
						var hit_pos: Vector3 = hit_pos_variant
						trigger_hit(hit_pos)
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			trigger_rapid_burst()


## Allocates the next slot in the 4-slot ring buffer and tweens its progress from 0.0 to 1.0.
func trigger_hit(world_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	var slot_idx: int = _next_slot
	_next_slot = (_next_slot + 1) % SLOT_COUNT
	print("EnergyWall: impact at ", world_pos, " [slot ", slot_idx, "]")

	_set_slot_progress(0.0, slot_idx, world_pos)

	var slot_tween: Tween = Utilities.reset_tween_ext(
		self, _slot_tweens[slot_idx], Tween.TRANS_QUAD, Tween.EASE_OUT
	)
	_slot_tweens[slot_idx] = slot_tween
	if is_instance_valid(slot_tween):
		slot_tween.tween_method(
			_set_slot_progress.bind(slot_idx, world_pos), 0.0, 1.0, ripple_duration
		)


## Compatibility entry point for BellaSDK hitscan and melee damage callers.
func take_damage(_amount: int, hit_pos: Vector3, _shot_dir: Vector3 = Vector3.ZERO) -> void:
	trigger_hit(hit_pos)


## Fires 4 staggered hits across the barrier surface to demonstrate overlapping mat4 slots.
func trigger_rapid_burst() -> void:
	if not is_inside_tree():
		return
	print("EnergyWall: triggering 4-slot rapid-fire burst")
	var offsets: Array[Vector3] = [
		Vector3(-0.75, 0.35, 0.0),
		Vector3(0.65, 0.4, 0.0),
		Vector3(-0.45, -0.35, 0.0),
		Vector3(0.55, -0.3, 0.0)
	]
	for i: int in range(SLOT_COUNT):
		var world_target: Vector3 = to_global(offsets[i])
		if i == 0:
			trigger_hit(world_target)
		else:
			Utilities.delay_call(self, float(i) * 0.12, trigger_hit.bind(world_target))


## Updates column [param slot_idx] (0..3) in [_hit_buffer] and pushes its instance uniform.
func _set_slot_progress(progress: float, slot_idx: int, world_pos: Vector3) -> void:
	var packed: Vector4 = Vector4(world_pos.x, world_pos.y, world_pos.z, progress)
	match slot_idx:
		0:
			_hit_buffer.x = packed
		1:
			_hit_buffer.y = packed
		2:
			_hit_buffer.z = packed
		3:
			_hit_buffer.w = packed
	set_instance_shader_parameter(_slot_params[slot_idx], packed)


## Starts an event-driven repeating [Tween] that fires overlapping demo ripples.
func _start_demo_loop() -> void:
	trigger_rapid_burst()
	_demo_tween = Utilities.reset_tween(self, _demo_tween)
	if is_instance_valid(_demo_tween):
		_demo_tween.set_loops()
		_demo_tween.tween_interval(0.22)
		_demo_tween.tween_callback(_fire_random_demo_hit)


## Picks a pseudo-random point on the local quad and triggers a world-space hit.
func _fire_random_demo_hit() -> void:
	var local_hit: Vector3 = Vector3(randf_range(-1.1, 1.1), randf_range(-0.65, 0.65), 0.0)
	trigger_hit(to_global(local_hit))


## Restores mesh visibility when entering the camera frustum.
func _on_screen_entered() -> void:
	visible = true


## Hides mesh when exiting the camera frustum.
func _on_screen_exited() -> void:
	visible = false
