## Controls the player's flashlight, managing dynamic shadows, flickering,
## and volumetric fog rendering logic.
##
## Tracks wall proximity to adjust position, adds procedural jitter, and
## synchronizes sway with mouse motion.
class_name FlashlightController
extends Node3D

@export_category("Node References")
## Reference to the main player view camera for calculating raycasts.
@export var camera: Camera3D
## Reference to the main forward-facing spotlight.
@export var flashlight: SpotLight3D
## Optional ambient light to illuminate the area immediately surrounding the player.
@export var omni_light: OmniLight3D

@export_category("Flashlight Settings")
## The distance in meters the raycast checks to detect walls and retract the flashlight.
@export var flashlight_maintain_distance: float = 1.5
## The default target light energy during stable operation.
@export var base_energy: float = 10.0
## Intensity scalar specifically for rendering the beam inside volumetric fog.
@export var volumetric_energy: float = 8.0
## The maximum magnitude of procedural sway offset based on mouse movement.
@export var sway_amount: float = 5.0
## The interpolation speed for returning the sway offset to center.
@export var smooth_speed: float = 10.0
## The interpolation speed for the flashlight retracting backwards.
@export var flashlight_pos_smoothness: float = 10.0
## The interpolation speed for the flashlight sway rotation.
@export var flashlight_rot_smoothness: float = 10.0

## Cached local resting position of the flashlight setup.
var default_pos: Vector3 = Vector3.ZERO
## Calculated 2D coordinate for procedural sway offset targeting.
var sway_target: Vector2 = Vector2.ZERO
## Remaining duration in seconds for an active flicker event.
var flicker_timer: float = 0.0
## Tracks if the flashlight is currently executing a flicker event.
var is_flickering: bool = false
## Accumulated time index used for the procedural noise generator.
var noise_time: float = 0.0
## Dedicated noise instance used to create subtle positional jitter.
var jitter_noise: FastNoiseLite = FastNoiseLite.new()


## Caches initial positions and injects self into the parent player node.
func _ready() -> void:
	print("FlashlightController executing: Initializing setup.")
	default_pos = position
	flashlight.visible = false

	# Enforce the volumetric beam energy required for the custom fog shader
	flashlight.light_volumetric_fog_energy = volumetric_energy

	if omni_light != null:
		omni_light.visible = false

	jitter_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	jitter_noise.frequency = 0.8

	var player_node: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player_node) and "flashlight_controller" in player_node:
		player_node.set("flashlight_controller", self)


## Catches unhandled input for the flashlight toggle action.
## [param event] The incoming input event.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flashlight"):
		var new_state: bool = not flashlight.visible
		flashlight.visible = new_state

		if omni_light != null:
			omni_light.visible = new_state

		print("Player executing: Toggled flashlight visibility to ", new_state)


## Executes per-frame logic when the flashlight is powered on.
## [param delta] Frame time delta in seconds.
func _process(delta: float) -> void:
	if not flashlight.visible:
		return

	_apply_sway(delta)
	_apply_pushback(delta)
	_apply_instability(delta)


## Smoothly rotates the flashlight rig in response to accumulated sway targeting.
## [param delta] Frame time delta in seconds.
func _apply_sway(delta: float) -> void:
	var max_sway: float = 150.0
	sway_target.x = clampf(sway_target.x, -max_sway, max_sway)
	sway_target.y = clampf(sway_target.y, -max_sway, max_sway)

	var target_rot: Vector3 = Vector3(
		sway_target.y * (sway_amount * 0.0015), sway_target.x * (sway_amount * 0.0015), 0.0
	)

	rotation = rotation.lerp(target_rot, delta * flashlight_rot_smoothness)
	sway_target = sway_target.lerp(Vector2.ZERO, delta * (smooth_speed * 0.5))


## Raycasts forward and smoothly pulls the flashlight body backward
## to prevent clipping through walls.
## [param delta] Frame time delta in seconds.
func _apply_pushback(delta: float) -> void:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var forward_dir: Vector3 = -camera.global_transform.basis.z
	var ray_start: Vector3 = camera.global_position
	var ray_end: Vector3 = ray_start + (forward_dir * flashlight_maintain_distance)

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.hit_from_inside = false
	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		var dist: float = ray_start.distance_to(result.position)
		var base_push: float = flashlight_maintain_distance - dist
		var prox: float = clampf(1.0 - (dist / flashlight_maintain_distance), 0.0, 1.0)
		var extra_push: float = (flashlight_maintain_distance * 0.25) * prox
		var target_z: float = base_push + extra_push

		flashlight.position.z = lerpf(flashlight.position.z, target_z, delta * 15.0)
	else:
		flashlight.position.z = lerpf(flashlight.position.z, 0.0, delta * 15.0)


## Introduces random energy flickering and subtle rotational noise to mimic aging hardware.
## [param delta] Frame time delta in seconds.
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
		flashlight.light_energy = lerpf(
			flashlight.light_energy, base_energy + micro_fluct, delta * 20.0
		)

	noise_time += delta * 4.0
	rotation.x += jitter_noise.get_noise_2d(noise_time, 0.0) * 0.003
	rotation.y += jitter_noise.get_noise_2d(0.0, noise_time) * 0.003
