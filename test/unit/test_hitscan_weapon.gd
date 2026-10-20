## Unit test suite validating HitscanWeapon shooting logic, fire rate, and reloading.
class_name TestHitscanWeapon
extends GutTest

## The weapon instance under test.
var weapon: HitscanWeapon = null

## The camera instance passed into shoot routines.
var camera: Camera3D = null


## Prepares an isolated HitscanWeapon and Camera3D before each test.
func before_each() -> void:
	print("TestHitscanWeapon: before_each() setup started.")
	weapon = HitscanWeapon.new()
	add_child_autofree(weapon)

	camera = Camera3D.new()
	add_child_autofree(camera)


## Verifies default weapon tuning parameters and ammo metrics.
func test_default_properties() -> void:
	print("TestHitscanWeapon: test_default_properties() called.")
	assert_eq(weapon.damage_per_shot, 25, "Default damage should be 25.")
	assert_eq(weapon.max_range, 50.0, "Default range should be 50m.")
	assert_eq(weapon.fire_rate, 0.5, "Default fire rate should be 0.5s.")
	assert_eq(weapon.ammo_capacity, 6, "Default ammo capacity should be 6.")
	assert_eq(weapon.current_ammo, 6, "Default current ammo should be 6.")
	assert_eq(weapon.reserve_ammo, 6, "Default reserve ammo should be 6.")
	assert_eq(weapon.ammo_type, &"revolver", "Default ammo type should be revolver.")


## Verifies that firing an equipped weapon decrements magazine ammo count.
func test_shoot_decrements_ammo_when_equipped() -> void:
	print("TestHitscanWeapon: test_shoot_decrements_ammo_when_equipped() called.")
	weapon.is_equipped = true
	var fired: bool = weapon.shoot(camera)

	assert_true(fired, "Equipped weapon should fire successfully.")
	assert_eq(weapon.current_ammo, 5, "Firing must consume exactly one round from magazine.")


## Verifies that unequipped weapons refuse to fire.
func test_shoot_fails_when_not_equipped() -> void:
	print("TestHitscanWeapon: test_shoot_fails_when_not_equipped() called.")
	weapon.is_equipped = false
	var fired: bool = weapon.shoot(camera)

	assert_false(fired, "Unequipped weapon must reject firing calls.")
	assert_eq(weapon.current_ammo, 6, "Unequipped dry fire should not decrement ammo.")


## Verifies dry fire rejection when chamber is completely empty.
func test_shoot_dry_fire_when_empty() -> void:
	print("TestHitscanWeapon: test_shoot_dry_fire_when_empty() called.")
	weapon.is_equipped = true
	weapon.current_ammo = 0
	var fired: bool = weapon.shoot(camera)

	assert_false(fired, "Weapon with empty chamber should dry fire.")
	assert_eq(weapon.current_ammo, 0, "Chamber count should remain zero on dry fire.")


## Verifies that shots within the fire rate cooldown interval are rejected.
func test_shoot_respects_fire_rate() -> void:
	print("TestHitscanWeapon: test_shoot_respects_fire_rate() called.")
	weapon.is_equipped = true
	weapon.fire_rate = 1.0

	var first_shot: bool = weapon.shoot(camera)
	var immediate_shot: bool = weapon.shoot(camera)

	assert_true(first_shot, "First shot should succeed.")
	assert_false(immediate_shot, "Second shot inside cooldown window must be rejected.")


## Verifies that reloading transfers rounds from reserves up to maximum capacity.
func test_reload_transfers_ammo_from_reserves() -> void:
	print("TestHitscanWeapon: test_reload_transfers_ammo_from_reserves() called.")
	weapon.current_ammo = 2
	weapon.reserve_ammo = 10
	weapon.ammo_capacity = 6

	weapon.reload()

	assert_eq(weapon.current_ammo, 6, "Reload should top off chamber to capacity.")
	assert_eq(weapon.reserve_ammo, 6, "Reserve rounds should decrease by loaded amount.")


## Verifies that reloading when already full or without reserves is a no-op.
func test_reload_when_full_or_empty_reserves_noops() -> void:
	print("TestHitscanWeapon: test_reload_when_full_or_empty_reserves_noops() called.")
	weapon.current_ammo = 6
	weapon.reserve_ammo = 10
	weapon.ammo_capacity = 6
	weapon.reload()
	assert_eq(weapon.current_ammo, 6, "Reload on full chamber should not change ammo.")

	weapon.current_ammo = 1
	weapon.reserve_ammo = 0
	weapon.reload()
	assert_eq(weapon.current_ammo, 1, "Reload without reserve ammo should not change chamber.")


## Verifies that sync_ammo_ui dispatches the weapon_ammo_changed event signal.
func test_sync_ammo_ui_emits_event() -> void:
	print("TestHitscanWeapon: test_sync_ammo_ui_emits_event() called.")
	watch_signals(Events)
	weapon.current_ammo = 4
	weapon.reserve_ammo = 8
	weapon.ammo_capacity = 6

	weapon.sync_ammo_ui()

	assert_signal_emitted_with_parameters(Events, &"weapon_ammo_changed", [4, 8, 6])
