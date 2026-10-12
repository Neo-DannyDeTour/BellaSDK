## Directional blood spray particles emitting textured droplets away from hit.
class_name BloodSplatterVFX
extends CPUParticles3D


## Configures droplet billboard material, velocity curves, and one-shot burst.
func _ready() -> void:
	print("BloodSplatterVFX: Emitting blood spray burst.")
	emitting = false
	one_shot = true
	explosiveness = 0.95
	amount = 16
	lifetime = 0.4

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	mesh = quad

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.65, 0.02, 0.02, 1.0)
	material_override = mat

	var timer: SceneTreeTimer = get_tree().create_timer(lifetime + 0.1)
	timer.timeout.connect(queue_free)


## Sets spray direction away from shooter and applies optional blood texture.
func setup(shot_dir: Vector3, blood_tex: Texture2D = null) -> void:
	print("BloodSplatterVFX: Setting up trajectory away from shooter.")
	direction = shot_dir.normalized() + (Vector3.UP * 0.4)
	spread = 35.0
	initial_velocity_min = 2.5
	initial_velocity_max = 5.0
	gravity = Vector3(0.0, -12.0, 0.0)

	if is_instance_valid(blood_tex) and material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = material_override as StandardMaterial3D
		mat.albedo_texture = blood_tex

	emitting = true
