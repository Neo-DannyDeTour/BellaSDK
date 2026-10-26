## Unit test suite validating ThrowableWeapon mechanics, stacking, and quick throw.
class_name TestThrowableWeapon
extends GutTest

## The grenade weapon instance under test.
var weapon: ThrowableWeapon = null

## The camera instance passed into shoot routines.
var camera: Camera3D = null

## The inventory component simulating player weapon slots.
var inventory: WeaponInventoryComponent = null

## Weapon holder socket node.
var weapon_holder: Node3D = null


## Prepares isolated SmokeGrenadeWeapon, Camera3D, and WeaponInventoryComponent before each test.
func before_each() -> void:
	print("TestThrowableWeapon: before_each() setup started.")
	weapon = SmokeGrenadeWeapon.new()
	add_child_autofree(weapon)

	camera = Camera3D.new()
	add_child_autofree(camera)

	weapon_holder = Node3D.new()
	add_child_autofree(weapon_holder)

	inventory = WeaponInventoryComponent.new()
	inventory.weapon_holder = weapon_holder
	inventory.camera = camera
	add_child_autofree(inventory)


## Verifies default tuning parameters and grenade stack limits.
func test_default_properties() -> void:
	print("TestThrowableWeapon: test_default_properties() called.")
	assert_eq(weapon.weapon_tag, "smoke_grenade", "Weapon tag should be smoke_grenade.")
	assert_eq(weapon.default_slot, 4, "Default slot should be 4.")
	assert_eq(weapon.current_ammo, 1, "Initial count should be 1 grenade.")
	assert_eq(weapon.max_ammo, 3, "Maximum stack capacity should be 3.")
	assert_eq(weapon.ammo_type, &"smoke_grenade", "Ammo type should be smoke_grenade.")


## Verifies that unequipped throwable refuses to shoot.
func test_shoot_fails_when_not_equipped() -> void:
	print("TestThrowableWeapon: test_shoot_fails_when_not_equipped() called.")
	weapon.is_equipped = false
	var thrown: bool = weapon.shoot(camera)

	assert_false(thrown, "Unequipped throwable must reject throwing calls.")
	assert_eq(weapon.current_ammo, 1, "Ammo must not decrement when unequipped.")


## Verifies that firing an equipped throwable consumes exactly one grenade.
func test_shoot_consumes_grenade_when_equipped() -> void:
	print("TestThrowableWeapon: test_shoot_consumes_grenade_when_equipped() called.")
	weapon.is_equipped = true
	weapon.current_ammo = 2
	var thrown: bool = weapon.shoot(camera)

	assert_true(thrown, "Equipped throwable should throw successfully.")
	assert_eq(weapon.current_ammo, 1, "Throwing must consume exactly 1 grenade.")


## Verifies that firing with zero ammunition is rejected.
func test_shoot_fails_when_empty() -> void:
	print("TestThrowableWeapon: test_shoot_fails_when_empty() called.")
	weapon.is_equipped = true
	weapon.current_ammo = 0
	var thrown: bool = weapon.shoot(camera)

	assert_false(thrown, "Throwing with empty stack must fail.")
	assert_eq(weapon.current_ammo, 0, "Chamber count remains zero.")


## Verifies that add_grenade increments up to maximum capacity of 3 and rejects overflow.
func test_add_grenade_stacks_to_max() -> void:
	print("TestThrowableWeapon: test_add_grenade_stacks_to_max() called.")
	weapon.current_ammo = 1

	var add_first: bool = weapon.add_grenade(1)
	assert_true(add_first, "Adding grenade to partial stack should succeed.")
	assert_eq(weapon.current_ammo, 2, "Ammo should increase to 2.")

	var add_second: bool = weapon.add_grenade(1)
	assert_true(add_second, "Adding second grenade should reach max capacity 3.")
	assert_eq(weapon.current_ammo, 3, "Ammo should reach max 3.")

	var add_overflow: bool = weapon.add_grenade(1)
	assert_false(add_overflow, "Adding beyond max_ammo must return false.")
	assert_eq(weapon.current_ammo, 3, "Ammo must remain capped at 3.")


## Verifies that quick_throw_grenade on WeaponInventoryComponent throws the grenade.
func test_inventory_quick_throw_grenade() -> void:
	print("TestThrowableWeapon: test_inventory_quick_throw_grenade() called.")
	inventory.register_weapon(weapon)
	weapon.is_equipped = true
	weapon.current_ammo = 2

	var quick_thrown: bool = inventory.quick_throw_grenade()
	assert_true(quick_thrown, "Quick throw should succeed via inventory.")
	assert_eq(weapon.current_ammo, 1, "Quick throw should decrement ammo.")
