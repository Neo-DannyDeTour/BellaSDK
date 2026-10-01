## Controls player flashlight with zero-allocation pushback, sway, and flicker.
class_name FlashlightController
extends Node3D

## Maximum angular sway boundary in pixels.
const MAX_SWAY_BOUND: float = 150.0

## Reference to main player [Camera3D] for calculating forward raycasts.
@export var camera: Camera3D

## Reference to primary [SpotLight3D] spotlight beam.
@export var flashlight: SpotLight3D

## Optional ambient [OmniLight3D] illuminating surrounding geometry.
@export var omni_light: OmniLight3D

## Distance in meters checked to retract flashlight near obstacles.
@export var flashlight_maintain_distance: float = 1.5

## Target base light energy during stable operation.
@export var base_energy: float = 10.0

## Beam intensity scalar inside volumetric fog passes.
@export var volumetric_energy: float = 8.0

## Maximum magnitude of procedural sway offset from mouse movement.
@export var sway_amount: float = 5.0

## Interpolation return speed for centering sway offset.
@export var smooth_speed: float = 10.0

## Interpolation speed for flashlight retracting backwards.
@export var flashlight_pos_smoothness: float = 10.0

## Interpolation speed for flashlight rotation smoothing.
@export var flashlight_rot_smoothness: float = 10.0

## Cached local resting position of flashlight setup.
var default_pos: Vector3 = Vector3.ZERO

## Calculated 2D coordinate for procedural sway offset targeting.
var sway_target: Vector2 = Vector2.ZERO

## Remaining duration in seconds for an active flicker event.
var flicker_timer: float = 0.0

## Tracks if flashlight is currently executing a flicker event.
var is_flickering: bool = false

## Accumulated time index used for procedural noise sampling.
var noise_time: float = 0.0

## Dedicated [FastNoiseLite] instance generating positional jitter.
var jitter_noise: FastNoiseLite = FastNoiseLite.new()

## Cached [RID] exclusion array to eliminate runtime allocations during raycasts.
var _exclude_rids: Array[RID] = []

## Cached ray start vector to eliminate per-frame vector allocations.
var _ray_start: Vector3 = Vector3.ZERO

## Cached ray end vector to eliminate per-frame vector allocations.
var _ray_end: Vector3 = Vector3.ZERO


## Initializes noise, registers controller, and caches exclusion RIDs.
func _ready() -> void:
	print("FlashlightController: Initializing flashlight controller.")
	default_pos = position
	flashlight.visible = false
	flashlight.light_volumetric_fog_energy = volumetric_energy

	if omni_light != null:
		omni_light.visible = false

	jitter_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	jitter_noise.frequency = 0.8

	var player_node: Node = NodeQuery.get_single_node_in_group(get_tree(), &"player")
	if is_instance_valid(player_node):
		if &"flashlight_controller" in player_node:
			player_node.set(&"flashlight_controller", self)
		if player_node is CollisionObject3D:
			_exclude_rids.append((player_node as CollisionObject3D).get_rid())


## Catches unhandled input for flashlight toggle actions.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"flashlight"):
		var new_state: bool = not flashlight.visible
		flashlight.visible = new_state
		if omni_light != null:
			omni_light.visible = new_state
		print("FlashlightController: Toggled flashlight visibility -> ", new_state)


## Executes per-frame sway, pushback raycasts, and energy flicker updates.
func _process(delta: float) -> void:
	if not flashlight.visible:
		return

	_apply_sway(delta)
	_apply_pushback(delta)
	_apply_instability(delta)


## Smoothly rotates flashlight rig via [MathUtils.damp] in response to sway.
func _apply_sway(delta: float) -> void:
	sway_target.x = clampf(sway_target.x, -MAX_SWAY_BOUND, MAX_SWAY_BOUND)
	sway_target.y = clampf(sway_target.y, -MAX_SWAY_BOUND, MAX_SWAY_BOUND)

	var target_rot: Vector3 = Vector3(
		sway_target.y * (sway_amount * 0.0015), sway_target.x * (sway_amount * 0.0015), 0.0
	)

	rotation = MathUtils.damp(rotation, target_rot, flashlight_rot_smoothness, delta)
	sway_target = MathUtils.damp(sway_target, Vector2.ZERO, smooth_speed * 0.5, delta)


## Performs zero-allocation raycasts to retract flashlight from obstacles.
func _apply_pushback(delta: float) -> void:
	if not is_instance_valid(camera):
		return

	var world_3d: World3D = get_world_3d()
	if world_3d == null:
		return
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space_state == null:
		return

	var cam_transform: Transform3D = camera.global_transform
	_ray_start = cam_transform.origin
	_ray_end = _ray_start - cam_transform.basis.z * flashlight_maintain_distance

	var mask: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_INTERACTIVE
	var hit: Dictionary = NodeQuery.cast_ray(space_state, _ray_start, _ray_end, mask, _exclude_rids)

	if not hit.is_empty():
		var hit_pos: Vector3 = hit.get(&"position", _ray_end)
		var dist: float = _ray_start.distance_to(hit_pos)
		var base_push: float = flashlight_maintain_distance - dist
		var prox: float = clampf(1.0 - (dist / flashlight_maintain_distance), 0.0, 1.0)
		var extra_push: float = (flashlight_maintain_distance * 0.25) * prox
		var target_z: float = base_push + extra_push
		flashlight.position.z = MathUtils.damp(flashlight.position.z, target_z, 15.0, delta)
	else:
		flashlight.position.z = MathUtils.damp(flashlight.position.z, 0.0, 15.0, delta)


## Introduces procedural energy flickering and subtle rotational noise.
func _apply_instability(delta: float) -> void:
	if not is_flickering and randf() < 0.003:
		is_flickering = true
		flicker_timer = randf_range(0.1, 0.6)

	if is_flickering:
		flicker_timer -= delta
		flashlight.light_energy = randf_range(2.0, base_energy * 1.1)
		if flicker_timer <= 0.0:
			is_flickering = false
			flashlight.light_energy = base_energy
	else:
		var micro_fluct: float = randf_range(-0.4, 0.4)
		flashlight.light_energy = MathUtils.damp(
			flashlight.light_energy, base_energy + micro_fluct, 20.0, delta
		)

	noise_time += delta * 4.0
	rotation.x += jitter_noise.get_noise_2d(noise_time, 0.0) * 0.003
	rotation.y += jitter_noise.get_noise_2d(0.0, noise_time) * 0.003
