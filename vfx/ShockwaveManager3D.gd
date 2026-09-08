## Spawns, scales, and manages cleanup lifecycles for dynamic 3D shockwave particles.
class_name ShockwaveManager
extends Node3D

## Particle scene instantiated for shockwave visual effects.
@export var shockwave_scene: PackedScene


## Instantiates, scales, triggers, and schedules cleanup for a shockwave particle.
func trigger_shockwave(spawn_position: Vector3, radius: float = 5.0) -> void:
	print("ShockwaveManager: Spawning shockwave at: ", spawn_position, " | Radius: ", radius)

	if shockwave_scene == null:
		return

	var raw_instance: Node = shockwave_scene.instantiate()
	if not (raw_instance is GPUParticles3D):
		print("ShockwaveManager: Scene is not GPUParticles3D. Freeing instance.")
		raw_instance.queue_free()
		return

	var effect_instance: GPUParticles3D = raw_instance as GPUParticles3D
	get_tree().current_scene.add_child(effect_instance)

	effect_instance.global_position = spawn_position
	effect_instance.scale = Vector3(radius, radius, radius)
	effect_instance.one_shot = true
	effect_instance.explosiveness = 1.0
	effect_instance.restart()

	var actual_lifetime: float = effect_instance.lifetime / maxf(0.01, effect_instance.speed_scale)

	var timer: SceneTreeTimer = get_tree().create_timer(actual_lifetime + 0.1)
	timer.timeout.connect(effect_instance.queue_free)
