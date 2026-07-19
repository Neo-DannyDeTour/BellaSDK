class_name DecalPool
extends Node3D

@export var decal_texture: Texture2D
@export var max_decals: int = 50
@export var decal_size: Vector3 = Vector3(0.5, 0.5, 0.5)

var _decals: Array[Decal] = []
var _current_index: int = 0


func _ready() -> void:
	# Pre-allocate decals to prevent runtime stuttering
	for i in range(max_decals):
		var decal: Decal = Decal.new()
		decal.texture_albedo = decal_texture
		decal.size = decal_size

		# Performance optimization: stop rendering decals far from the camera
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 15.0
		decal.distance_fade_length = 5.0

		# Hide the decal initially by placing it far out of bounds
		decal.global_position = Vector3(0.0, -1000.0, 0.0)

		add_child(decal)
		_decals.append(decal)


func spawn_decal(hit_position: Vector3, surface_normal: Vector3) -> void:
	print("Spawning decal at position: ", hit_position, ", normal: ", surface_normal)

	# Grab the oldest decal from the pool
	var decal: Decal = _decals[_current_index]
	decal.global_position = hit_position

	# Decals project from +Y to -Y. We need to align the +Y axis to the surface normal.
	if surface_normal.is_equal_approx(Vector3.UP):
		decal.global_basis = Basis.IDENTITY
	elif surface_normal.is_equal_approx(Vector3.DOWN):
		# Prevent quaternion singularity when vectors are perfectly opposite
		decal.global_basis = Basis(Vector3.RIGHT, PI)
	else:
		# Fast and safe rotation from UP to the target normal
		var rotation_quat: Quaternion = Quaternion(Vector3.UP, surface_normal)
		decal.global_basis = Basis(rotation_quat)

	# Add a random twist so repeating decals don't look perfectly identical
	decal.rotate_object_local(Vector3.UP, randf_range(0.0, TAU))

	# Advance the index, wrapping back to 0 when max_decals is reached
	_current_index = (_current_index + 1) % max_decals
