## Manages spawning, scaling, and safe cleanup lifecycles for 3D shockwaves.
#class_name ShockwaveManager
extends Node3D

## The [PackedScene] instantiated for 3D shockwave visual effects.
@export var shockwave_scene: PackedScene


## Spawns, scales, and cleans up a one-shot [GPUParticles3D] shockwave instance.
func trigger_shockwave(spawn_position: Vector3, radius: float = 5.0, speed: float = 2.0) -> void:
	print(
		"ShockwaveManager: trigger_shockwave() at: ",
		spawn_position,
		" | Radius: ",
		radius,
		" | Speed: ",
		speed
	)

	if shockwave_scene == null:
		print("ShockwaveManager: shockwave_scene is not assigned.")
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
				print("ShockwaveManager: Freeing completed shockwave instance.")
				effect.queue_free()
	)
