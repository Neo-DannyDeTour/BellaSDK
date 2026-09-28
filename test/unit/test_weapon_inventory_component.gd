## Tests weapon inventory registration, slot selection, and ammo management.
class_name TestWeaponInventoryComponent
extends GutTest

## The [WeaponInventoryComponent] instance under test.
var inventory: WeaponInventoryComponent = null

## First mock weapon instance.
var mock_weapon_1: Node3D = null

## Second mock weapon instance.
var mock_weapon_2: Node3D = null

## The parent weapon holder node.
var mock_weapon_holder: Node3D = null


## Mock weapon class simulating shoot, reload, and ammo UI routines.
class MockWeapon:
	extends Node3D

	## Weapon identifier tag for inventory classification.
	var weapon_tag: String = "weapon"

	## Default inventory slot assigned to this weapon.
	var default_slot: int = 1

	## Caliber or ammunition category consumed by this weapon.
	var ammo_type: String = "bullets"

	## Available reserve ammunition pool.
	var reserve_ammo: int = 10

	## Logs simulated ammo UI synchronization.
	func sync_ammo_ui() -> void:
		print("MockWeapon: sync_ammo_ui() called.")

	## Mock shooting routine accepting a camera reference.
	func shoot(_cam: Camera3D) -> void:
		print("MockWeapon: shoot() called.")

	## Mock reload routine.
	func reload() -> void:
		print("MockWeapon: reload() called.")


## Prepares weapon holder, weapons, and inventory before each test.
func before_each() -> void:
	print("TestWeaponInventoryComponent: before_each() setup started.")
	inventory = WeaponInventoryComponent.new()
	mock_weapon_holder = Node3D.new()
	inventory.weapon_holder = mock_weapon_holder

	mock_weapon_1 = MockWeapon.new()
	mock_weapon_1.name = "MockWeapon1"
	mock_weapon_1.set("weapon_tag", "weapon_1")
	mock_weapon_1.set("default_slot", 1)
	mock_weapon_1.set("ammo_type", "bullets")
	mock_weapon_1.set("reserve_ammo", 10)

	mock_weapon_2 = MockWeapon.new()
	mock_weapon_2.name = "MockWeapon2"
	mock_weapon_2.set("weapon_tag", "weapon_2")
	mock_weapon_2.set("default_slot", 2)
	mock_weapon_2.set("ammo_type", "shells")
	mock_weapon_2.set("reserve_ammo", 5)

	autofree(mock_weapon_1)
	autofree(mock_weapon_2)
	add_child_autofree(mock_weapon_holder)
	add_child_autofree(inventory)
	print("TestWeaponInventoryComponent: before_each() setup completed.")


## Verifies [method WeaponInventoryComponent.register_weapon] assigns slot 0.
func test_register_weapon() -> void:
	print("TestWeaponInventoryComponent: test_register_weapon() running.")
	inventory.register_weapon(mock_weapon_1)

	var slot_0: Node3D = inventory.slots[0]
	assert_eq(slot_0, mock_weapon_1, "Weapon 1 should be registered in slot 0.")
	assert_eq(
		inventory.current_slot_index,
		0,
		"Current slot should switch to the newly registered weapon."
	)


## Verifies [method WeaponInventoryComponent.select_slot] toggles visibility.
func test_select_slot() -> void:
	print("TestWeaponInventoryComponent: test_select_slot() running.")
	inventory.register_weapon(mock_weapon_1)
	inventory.register_weapon(mock_weapon_2)

	# Registering weapon 2 already selected slot 1; switch to slot 0 first:
	inventory.select_slot(0)
	assert_eq(inventory.current_slot_index, 0, "Slot 0 should be active.")
	assert_true(mock_weapon_1.visible, "Active weapon should be visible.")
	assert_false(mock_weapon_2.visible, "Inactive weapon should be hidden.")

	# Now switch to slot 1:
	inventory.select_slot(1)
	assert_eq(inventory.current_slot_index, 1, "Slot 1 should be active.")
	assert_true(mock_weapon_2.visible, "Active weapon should be visible.")
	assert_false(mock_weapon_1.visible, "Inactive weapon should be hidden.")
	assert_eq(inventory.previous_slot_index, 0, "Previous slot index should be 0.")


## Verifies [method WeaponInventoryComponent.add_ammo] increases reserve pool.
func test_add_ammo() -> void:
	print("TestWeaponInventoryComponent: test_add_ammo() running.")
	inventory.register_weapon(mock_weapon_1)

	var result: bool = inventory.add_ammo(StringName("bullets"), 20)
	assert_true(result, "Adding ammo should return true for matching ammo type.")

	var res_ammo_1: Variant = mock_weapon_1.get("reserve_ammo")
	assert_eq(int(res_ammo_1), 30, "Reserve ammo should be increased by 20.")

	var false_result: bool = inventory.add_ammo(StringName("rockets"), 5)
	assert_false(false_result, "Adding ammo should return false for unmatched ammo type.")
