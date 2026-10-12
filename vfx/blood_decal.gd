## Fading blood stain decal projecting splatter textures onto the environment.
class_name BloodDecal
extends Decal

## Emitted when the decal finishes its lifespan and begins freeing.
signal decal_expired


## Initializes decal projection box, cull mask, and schedules fade tween.
func _ready() -> void:
	print("BloodDecal: Initializing decal instance on environment.")
	cull_mask = 1 << 0
	size = Vector3(1.2, 0.8, 1.2)


## Configures transform orientation to surface normal and applies texture.
func setup(pos: Vector3, normal: Vector3, tex: Texture2D, life: float) -> void:
	print("BloodDecal: Positioning decal on surface normal: ", normal)
	global_position = pos

	if not normal.is_equal_approx(Vector3.UP):
		var up_vector: Vector3 = Vector3.UP
		if abs(normal.dot(up_vector)) > 0.99:
			up_vector = Vector3.RIGHT
		var x_axis: Vector3 = up_vector.cross(normal).normalized()
		var z_axis: Vector3 = normal.cross(x_axis).normalized()
		global_transform.basis = Basis(x_axis, normal, z_axis)

	rotate_object_local(Vector3.UP, randf_range(0.0, TAU))

	if is_instance_valid(tex):
		texture_albedo = tex

	var tween: Tween = create_tween()
	tween.tween_interval(life)
	tween.tween_property(self, "modulate:a", 0.0, 1.2)
	tween.tween_callback(queue_free)
