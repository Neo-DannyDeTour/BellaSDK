## Visual test cell verifying [ThrowableWeapon] fires a projectile via [method shoot].
class_name CellWeaponDrop
extends MechanicTestCell

## Preloaded throwable weapon scene.
const WEAPON_SCENE: PackedScene = preload("res://weapons/throwable_weapon.tscn")

## Spawned throwable weapon instance under test.
var _weapon: Node3D = null


## Spawns throwable weapon on the test pad.
func _setup_cell() -> void:
	cell_title = "Weapon: Throwable Shoot"
	_weapon = WEAPON_SCENE.instantiate() as Node3D
	_weapon.position = Vector3(0.0, 1.5, 0.0)
	add_child(_weapon)
	await wait_frames(2)


## Calls shoot() with the cell camera and verifies projectile firing succeeds.
func _run_test() -> void:
	if not assert_true(is_instance_valid(_weapon), "Weapon scene must instantiate."):
		return

	_weapon.set("is_equipped", true)
	_weapon.call("add_grenade", 1)
	var before_ammo: Variant = _weapon.get("current_ammo")
	var fired: Variant = _weapon.call("shoot", get_cell_camera())
	assert_eq(fired, true, "ThrowableWeapon.shoot() must return true when equipped.")
	var after_ammo: Variant = _weapon.get("current_ammo")
	assert_true(
		int(after_ammo) == int(before_ammo) - 1,
		"ThrowableWeapon ammo must decrement after shoot()."
	)
	await wait_frames(3)


## Cleans up spawned weapon instance.
func _teardown_cell() -> void:
	if is_instance_valid(_weapon):
		_weapon.queue_free()
	await wait_frames(1)
