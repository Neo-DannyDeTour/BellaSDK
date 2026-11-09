## Unit test suite validating [BreakableCrate] instantiation, fall damage, and player stomp.
class_name TestBreakableCrate
extends GutTest

## Preloaded breakable crate packed scene.
const CRATE_SCENE: PackedScene = preload("res://interactables/breakable_crate.tscn")

## Instance of the breakable crate under test.
var crate: BreakableCrate = null


## Prepares isolated BreakableCrate instance before each test.
func before_each() -> void:
	print("TestBreakableCrate: Setting up test environment.")
	crate = CRATE_SCENE.instantiate() as BreakableCrate
	add_child_autofree(crate)


## Cleans up crate instance after each test.
func after_each() -> void:
	print("TestBreakableCrate: Tearing down test environment.")
	crate = null


## Validates instantiation and node hierarchy requirements.
func test_crate_instantiation_and_properties() -> void:
	assert_not_null(crate, "Crate instance should instantiate successfully.")
	assert_true(crate is BreakableCrate, "Crate node must be a BreakableCrate.")
	assert_true(crate is PickableObject, "Crate node must inherit PickableObject.")
	assert_eq(crate.mass, 25.0, "Crate mass must equal 25.0 kg.")
	assert_eq(crate.max_health, 25.0, "Crate max health must equal 25.0.")
	assert_eq(
		crate.collision_layer,
		CollisionLayers.MASK_INTERACTIVE,
		"Crate collision layer must match MASK_INTERACTIVE."
	)
	assert_not_null(crate.intact_mesh, "Intact mesh reference must be assigned.")
	assert_not_null(crate.intact_collision, "Intact collision reference must be assigned.")
	assert_not_null(crate.debris_root, "Debris root reference must be assigned.")
	assert_true(crate.intact_collision.shape is BoxShape3D, "Collision shape must be a BoxShape3D.")
	var box: BoxShape3D = crate.intact_collision.shape as BoxShape3D
	assert_eq(box.size, Vector3(1.0, 1.05, 1.0), "Box shape size must match crate bounds.")


## Validates gun shot hit damage application and break triggering.
func test_crate_gunshot_break() -> void:
	watch_signals(crate)
	# Single revolver shot dealing 25 damage
	crate.take_damage(25, crate.global_position, Vector3.FORWARD)
	assert_signal_emitted(crate, "broken", "Crate should break on 25 damage shot.")


## Validates player falling from height onto the crate.
func test_player_stomp_break() -> void:
	watch_signals(crate)
	var mock_player: CharacterBody3D = CharacterBody3D.new()
	mock_player.add_to_group(&"player")
	mock_player.velocity = Vector3(0.0, -9.5, 0.0)
	add_child_autofree(mock_player)

	crate._on_body_entered(mock_player)
	assert_signal_emitted(crate, "broken", "Player falling at -9.5 m/s should break crate.")
