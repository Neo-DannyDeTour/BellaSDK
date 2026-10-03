## Manages spawning, scaling, and zero-allocation pooled 3D shockwaves.
#class_name ShockwaveManager
extends Node3D

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Number of pre-instantiated shockwave particle systems in pool.
const POOL_SIZE: int = 6

# --------------------------------------
# EXPORTS
# --------------------------------------
## The [PackedScene] instantiated for 3D shockwave visual effects.
@export var shockwave_scene: PackedScene

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Pre-warmed pool of [GPUParticles3D] shockwave instances.
var _particles_pool: Array[GPUParticles3D] = []

## Index pointing to next particle instance in cyclic pool.
var _pool_index: int = 0


## Initializes the internal particle pool to prevent runtime allocations.
func _ready() -> void:
	print("ShockwaveManager: Initializing pooled particle instances.")
	_init_pool()


## Pre-allocates shockwave particle nodes in the scene tree.
func _init_pool() -> void:
	if not is_instance_valid(shockwave_scene):
		print("ShockwaveManager: shockwave_scene unassigned.")
		return

	_particles_pool.clear()
	for i: int in range(POOL_SIZE):
		var raw_instance: Node = shockwave_scene.instantiate()
		if raw_instance is GPUParticles3D:
			var effect: GPUParticles3D = raw_instance as GPUParticles3D
			effect.one_shot = true
			effect.emitting = false
			effect.explosiveness = 1.0
			add_child(effect)
			_particles_pool.append(effect)
		else:
			raw_instance.queue_free()


## Fires a pooled [GPUParticles3D] shockwave without dynamic heap allocation.
func trigger_shockwave(spawn_position: Vector3, radius: float = 5.0, speed: float = 2.0) -> void:
	print("ShockwaveManager: trigger_shockwave() at: ", spawn_position, " | Radius: ", radius)

	if _particles_pool.is_empty():
		_trigger_fallback_shockwave(spawn_position, radius, speed)
		return

	var effect: GPUParticles3D = _particles_pool[_pool_index]
	_pool_index = (_pool_index + 1) % _particles_pool.size()

	if is_instance_valid(effect):
		effect.global_position = spawn_position
		effect.scale = Vector3(radius, radius, radius)
		effect.speed_scale = maxf(0.01, speed)
		effect.restart()
		effect.emitting = true


## Fallback dynamic spawn when particle pool has not been pre-warmed.
func _trigger_fallback_shockwave(spawn_position: Vector3, radius: float, speed: float) -> void:
	if not is_instance_valid(shockwave_scene):
		return

	var raw_instance: Node = shockwave_scene.instantiate()
	if not (raw_instance is GPUParticles3D):
		raw_instance.queue_free()
		return

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		raw_instance.queue_free()
		return

	var effect: GPUParticles3D = raw_instance as GPUParticles3D
	effect.one_shot = true
	effect.explosiveness = 1.0
	effect.speed_scale = maxf(0.01, speed)
	current_scene.add_child(effect)

	effect.global_position = spawn_position
	effect.scale = Vector3(radius, radius, radius)
	effect.restart()

	var actual_duration: float = (effect.lifetime / effect.speed_scale) + 0.15
	var cleanup_timer: SceneTreeTimer = get_tree().create_timer(actual_duration)
	cleanup_timer.timeout.connect(
		func() -> void:
			if is_instance_valid(effect):
				effect.queue_free()
	)
