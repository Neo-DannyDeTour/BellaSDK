class_name TestWeaponInventoryComponent
extends GutTest

## The component under test.
var inventory: WeaponInventoryComponent

## A mock weapon node 1.
var mock_weapon_1: Node3D

## A mock weapon node 2.
var mock_weapon_2: Node3D

## The weapon holder node.
var mock_weapon_holder: Node3D


class MockWeapon:
	extends Node3D
	var weapon_tag: String = "weapon"
	var default_slot: int = 1
	var ammo_type: String = "bullets"
	var reserve_ammo: int = 10

	func sync_ammo_ui() -> void:
		print("MockWeapon: sync_ammo_ui() called.")

	func shoot(_cam: Camera3D) -> void:
		pass

	func reload() -> void:
		pass


func before_each() -> void:
	print("TestWeaponInventoryComponent: before_each() setup starting.")
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

	add_child_autofree(mock_weapon_holder)
	add_child_autofree(inventory)
	print("TestWeaponInventoryComponent: before_each() setup completed.")


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


func test_select_slot() -> void:
	print("TestWeaponInventoryComponent: test_select_slot() running.")
	inventory.register_weapon(mock_weapon_1)
	inventory.register_weapon(mock_weapon_2)

	inventory.select_slot(1)
	assert_eq(inventory.current_slot_index, 1, "Slot 1 should be active.")
	assert_true(mock_weapon_2.visible, "Active weapon should be visible.")
	assert_false(mock_weapon_1.visible, "Inactive weapon should be hidden.")

	inventory.select_slot(0)
	assert_eq(inventory.current_slot_index, 0, "Slot 0 should be active.")
	assert_true(mock_weapon_1.visible, "Active weapon should be visible.")
	assert_false(mock_weapon_2.visible, "Inactive weapon should be hidden.")
	assert_eq(inventory.previous_slot_index, 1, "Previous slot index should be 1.")


func test_add_ammo() -> void:
	print("TestWeaponInventoryComponent: test_add_ammo() running.")
	inventory.register_weapon(mock_weapon_1)

	var result: bool = inventory.add_ammo(StringName("bullets"), 20)
	assert_true(result, "Adding ammo should return true for matching ammo type.")

	var res_ammo_1: Variant = mock_weapon_1.get("reserve_ammo")
	assert_eq(int(res_ammo_1), 30, "Reserve ammo should be increased by 20.")

	var false_result: bool = inventory.add_ammo(StringName("rockets"), 5)
	assert_false(false_result, "Adding ammo should return false for unmatched ammo type.")
