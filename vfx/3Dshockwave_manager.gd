class_name ShockwaveManager
extends Node3D

@export var shockwave_scene: PackedScene


func trigger_shockwave(spawn_position: Vector3) -> void:
	print("Triggering 3D shockwave at position: ", spawn_position)

	if shockwave_scene == null:
		return

	var effect_instance: GPUParticles3D = shockwave_scene.instantiate() as GPUParticles3D
	if effect_instance == null:
		return

	get_tree().current_scene.add_child(effect_instance)
	effect_instance.global_position = spawn_position
	effect_instance.emitting = true

	var timer: SceneTreeTimer = get_tree().create_timer(effect_instance.lifetime)
	timer.timeout.connect(effect_instance.queue_free)
