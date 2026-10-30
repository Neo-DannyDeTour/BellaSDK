## Unit tests for [SmokeExplosionVfx] controller, verifying @tool state, properties, and looping.
class_name TestSmokeExplosionVfx
extends GutTest

const SMOKE_SCENE_PATH: String = "res://vfx/smoke_explosion.tscn"


## Verifies scene instantiates with valid node invariants and default properties.
func test_scene_instantiation() -> void:
	var packed_scene: PackedScene = load(SMOKE_SCENE_PATH) as PackedScene
	assert_not_null(packed_scene, "Smoke scene must load successfully.")

	var instance: SmokeExplosionVfx = packed_scene.instantiate() as SmokeExplosionVfx
	assert_not_null(instance, "Instance must be SmokeExplosionVfx type.")
	add_child_autofree(instance)

	assert_true(instance.auto_play, "auto_play should default to true.")
	assert_false(instance.loop, "loop should default to false.")
	assert_eq(instance.loop_interval, 1.0, "loop_interval should default to 1.0.")
	assert_false(instance.preview_active, "preview_active should default to false.")
	assert_true(instance.free_on_finish, "free_on_finish should default to true.")


## Verifies preview toggle and looping functionality can be mutated safely.
func test_preview_and_loop_mutations() -> void:
	var packed_scene: PackedScene = load(SMOKE_SCENE_PATH) as PackedScene
	var instance: SmokeExplosionVfx = packed_scene.instantiate() as SmokeExplosionVfx
	instance.auto_play = false
	add_child_autofree(instance)

	instance.loop = true
	assert_true(instance.loop, "Loop property should be true.")

	instance.preview_active = true
	assert_true(instance.preview_active, "preview_active should be set to true.")

	instance.preview_active = false
	assert_false(instance.preview_active, "preview_active should turn off cleanly.")
