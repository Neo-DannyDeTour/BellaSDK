class_name ShockwaveManager
extends Node3D

@export var shockwave_scene: PackedScene


# Adding a default value of 5.0 to 'radius' ensures older scripts won't break
# if they only send the spawn_position.
func trigger_shockwave(spawn_position: Vector3, radius: float = 5.0) -> void:
	print(
		"ShockwaveManager: Triggering 3D shockwave at position: ",
		spawn_position,
		" | Radius: ",
		radius
	)

	if shockwave_scene == null:
		return

	var effect_instance: GPUParticles3D = shockwave_scene.instantiate() as GPUParticles3D
	if effect_instance == null:
		return

	get_tree().current_scene.add_child(effect_instance)

	effect_instance.global_position = spawn_position
	effect_instance.scale = Vector3(radius, radius, radius)

	# 1. Force the correct single-fire behavior in code, ignoring the Inspector
	effect_instance.one_shot = true
	effect_instance.explosiveness = 1.0

	# 2. Use restart() instead of emitting = true. This forces the
	# particle system to begin its one-shot cycle instantly.
	effect_instance.restart()

	# 3. Calculate exactly how long the visual effect lasts in real time
	var actual_lifetime: float = effect_instance.lifetime / maxf(0.01, effect_instance.speed_scale)

	# 4. Safely delete it right after it finishes using a Timer.
	# This is heavily optimized and avoids Godot 4's sometimes buggy 'finished' signal.
	var timer: SceneTreeTimer = get_tree().create_timer(actual_lifetime + 0.1)
	timer.timeout.connect(effect_instance.queue_free)
