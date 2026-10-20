## Unit test suite validating Shotgun archetype properties and spread configuration.
class_name TestShotgun
extends GutTest

## The shotgun instance under test.
var shotgun: Shotgun = null

## The camera reference for firing routines.
var camera: Camera3D = null


## Prepares an isolated Shotgun and Camera3D before each test.
func before_each() -> void:
	print("TestShotgun: before_each() setup started.")
	shotgun = Shotgun.new()
	add_child_autofree(shotgun)

	camera = Camera3D.new()
	add_child_autofree(camera)


## Verifies that Shotgun inherits from HitscanWeapon base class.
func test_inherits_hitscan_weapon() -> void:
	print("TestShotgun: test_inherits_hitscan_weapon() called.")
	assert_true(shotgun is HitscanWeapon, "Shotgun must inherit from HitscanWeapon.")


## Verifies overridden multi-pellet spread, slot, and damage properties.
func test_shotgun_archetype_configuration() -> void:
	print("TestShotgun: test_shotgun_archetype_configuration() called.")
	assert_eq(shotgun.weapon_tag, "shotgun", "Tag must be shotgun.")
	assert_eq(shotgun.ammo_type, &"shotgun", "Ammo type must be shotgun.")
	assert_eq(shotgun.default_slot, 3, "Shotgun default slot must be 3.")
	assert_eq(shotgun.projectile_count, 8, "Shotgun must fire 8 pellets per shot.")
	assert_eq(shotgun.spread_angle, 4.0, "Spread cone angle must be 4.0 degrees.")
	assert_eq(shotgun.damage_per_shot, 10, "Per-pellet damage must be 10.")
	assert_eq(shotgun.fire_rate, 1.0, "Fire rate cooldown must be 1.0s.")


## Verifies that shooting and reloading operate cleanly on shotgun instances.
func test_shotgun_fire_and_reload() -> void:
	print("TestShotgun: test_shotgun_fire_and_reload() called.")
	shotgun.is_equipped = true
	var fired: bool = shotgun.shoot(camera)

	assert_true(fired, "Shotgun should fire when equipped.")
	assert_eq(shotgun.current_ammo, 5, "Firing must consume 1 shell from current magazine.")

	shotgun.reload()
	assert_eq(shotgun.current_ammo, 6, "Reloading must restore shotgun magazine to capacity.")
