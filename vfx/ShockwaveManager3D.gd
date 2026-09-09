## Manages spawning, scaling, and safe cleanup lifecycles for 3D shockwaves.
class_name ShockwaveManager
extends Node3D

## [PackedScene] instantiated for 3D shockwave visual effects.
@export var shockwave_scene: PackedScene


## Spawns, configures, and cleans up a [GPUParticles3D] shockwave instance.
func trigger_shockwave(spawn_position: Vector3, radius: float = 5.0) -> void:
	print("ShockwaveManager: Spawning shockwave at: ", spawn_position, " | Radius: ", radius)

	if shockwave_scene == null:
		return

	var raw_instance: Node = shockwave_scene.instantiate()
	if not (raw_instance is GPUParticles3D):
		print("ShockwaveManager: Scene is not GPUParticles3D. Freeing instance.")
		raw_instance.queue_free()
		return

	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		print("ShockwaveManager: current_scene is null. Aborting spawn.")
		raw_instance.queue_free()
		return

	var effect_instance: GPUParticles3D = raw_instance as GPUParticles3D
	current_scene.add_child(effect_instance)

	effect_instance.global_position = spawn_position
	effect_instance.scale = Vector3(radius, radius, radius)
	effect_instance.one_shot = true
	effect_instance.explosiveness = 1.0
	effect_instance.restart()

	var speed_factor: float = maxf(0.01, effect_instance.speed_scale)
	var actual_lifetime: float = (effect_instance.lifetime / speed_factor) + 0.1

	var timer: SceneTreeTimer = get_tree().create_timer(actual_lifetime)
	timer.timeout.connect(
		func() -> void:
			if is_instance_valid(effect_instance):
				effect_instance.queue_free(),
		CONNECT_ONE_SHOT
	)
