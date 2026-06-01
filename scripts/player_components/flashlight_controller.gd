class_name FlashlightController
extends Node3D

@export_category("Node References")
@export var camera: Camera3D
@export var flashlight: SpotLight3D

@export_category("Flashlight Settings")
@export var flashlight_maintain_distance: float = 1.5
@export var base_energy: float = 10.0
@export var sway_amount: float = 5.0
@export var smooth_speed: float = 10.0
@export var flashlight_pos_smoothness: float = 10.0
@export var flashlight_rot_smoothness: float = 10.0

var default_pos: Vector3 = Vector3.ZERO
var sway_target: Vector2 = Vector2.ZERO
var flicker_timer: float = 0.0
var is_flickering: bool = false
var noise_time: float = 0.0
var jitter_noise: FastNoiseLite = FastNoiseLite.new()

func _ready() -> void:
	default_pos = position
	flashlight.visible = false
	
	jitter_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	jitter_noise.frequency = 0.8

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
		
	if event is InputEventMouseMotion and flashlight.visible:
		sway_target += event.relative

func _process(delta: float) -> void:
	if not flashlight.visible:
		return
		
	_apply_sway(delta)
	_apply_pushback(delta)
	_apply_instability(delta)

func _apply_sway(delta: float) -> void:
	var max_sway: float = 150.0
	sway_target.x = clampf(sway_target.x, -max_sway, max_sway)
	sway_target.y = clampf(sway_target.y, -max_sway, max_sway)

	var target_rot := Vector3(
		sway_target.y * (sway_amount * 0.0015), 
		sway_target.x * (sway_amount * 0.0015), 
		0.0
	)
	
	rotation = rotation.lerp(target_rot, delta * flashlight_rot_smoothness)
	sway_target = sway_target.lerp(Vector2.ZERO, delta * (smooth_speed * 0.5))

func _apply_pushback(delta: float) -> void:
	var space_state := get_world_3d().direct_space_state
	var forward_dir := -camera.global_transform.basis.z
	var ray_start := camera.global_position
	var ray_end := ray_start + (forward_dir * flashlight_maintain_distance)

	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	# The parent Player node RID should be passed in via an init function in a real scenario
	query.hit_from_inside = false
	var result := space_state.intersect_ray(query)

	if result:
		var dist: float = ray_start.distance_to(result.position)
		var base_push: float = flashlight_maintain_distance - dist
		var proximity: float = clampf(1.0 - (dist / flashlight_maintain_distance), 0.0, 1.0)
		var extra_push: float = (flashlight_maintain_distance * 0.25) * proximity
		
		flashlight.position.z = lerpf(flashlight.position.z, base_push + extra_push, delta * 15.0)
	else:
		flashlight.position.z = lerpf(flashlight.position.z, 0.0, delta * 15.0)

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
		var micro_fluctuation := randf_range(-0.4, 0.4)
		flashlight.light_energy = lerpf(
			flashlight.light_energy, base_energy + micro_fluctuation, delta * 20.0
		)

	noise_time += delta * 4.0
	rotation.x += jitter_noise.get_noise_2d(noise_time, 0.0) * 0.003
	rotation.y += jitter_noise.get_noise_2d(0.0, noise_time) * 0.003
