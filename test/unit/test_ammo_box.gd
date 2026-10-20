## Unit test suite validating AmmoBox archetype configuration, prompt toggles, and pickups.
class_name TestAmmoBox
extends GutTest

## The ammo pickup instance under test.
var ammo_box: AmmoBox = null

## Floating prompt label node attached to pickup.
var prompt_label: Label3D = null

## Primary character body simulating player pickup receiver.
var mock_player: CharacterBody3D = null

## Inventory component attached to mock player.
var inventory: WeaponInventoryComponent = null

## Mock gun slotted in inventory to receive ammunition.
var mock_gun: MockHeldGun = null


## Mock weapon class satisfying inventory ammo replenishment protocol.
class MockHeldGun:
	extends Node3D

	## Ammo category tag.
	var ammo_type: StringName = &"revolver"

	## Active reserve count.
	var reserve_ammo: int = 10

	## Weapon identification tag.
	var weapon_tag: String = "revolver"

	## Stub syncing ammo to UI.
	func sync_ammo_ui() -> void:
		print("MockHeldGun: sync_ammo_ui() called.")


## Prepares an isolated AmmoBox, prompt label, and mock player before each test.
func before_each() -> void:
	print("TestAmmoBox: before_each() setup started.")
	ammo_box = AmmoBox.new()
	add_child_autofree(ammo_box)

	prompt_label = Label3D.new()
	ammo_box.add_child(prompt_label)
	ammo_box.label = prompt_label

	mock_player = CharacterBody3D.new()
	add_child_autofree(mock_player)

	inventory = WeaponInventoryComponent.new()
	inventory.name = "WeaponInventoryComponent"
	mock_player.add_child(inventory)

	mock_gun = MockHeldGun.new()
	inventory.add_child(mock_gun)
	inventory.slots[0] = mock_gun


## Verifies default ammo archetype and transfer quantity.
func test_default_properties() -> void:
	print("TestAmmoBox: test_default_properties() called.")
	assert_eq(
		ammo_box.ammo_type, AmmoBox.AmmoArchetype.REVOLVER, "Default archetype should be REVOLVER."
	)
	assert_eq(ammo_box.ammo_amount, 6, "Default ammo amount should be 6.")
	var resolved_id: StringName = StringName(ammo_box.get("_resolved_ammo_id"))
	assert_eq(resolved_id, &"revolver", "Resolved ID should be revolver.")


## Verifies that mutating ammo_type updates the resolved ammunition identifier string.
func test_archetype_mutation_updates_resolved_id() -> void:
	print("TestAmmoBox: test_archetype_mutation_updates_resolved_id() called.")
	ammo_box.ammo_type = AmmoBox.AmmoArchetype.SHOTGUN
	var shotgun_id: StringName = StringName(ammo_box.get("_resolved_ammo_id"))
	assert_eq(shotgun_id, &"shotgun", "Should resolve to shotgun ID.")

	ammo_box.ammo_type = AmmoBox.AmmoArchetype.REVOLVER
	var revolver_id: StringName = StringName(ammo_box.get("_resolved_ammo_id"))
	assert_eq(revolver_id, &"revolver", "Should resolve back to revolver ID.")


## Verifies that focus events display the prompt label and unfocus hides it.
func test_focus_unfocus_toggles_label_visibility() -> void:
	print("TestAmmoBox: test_focus_unfocus_toggles_label_visibility() called.")
	ammo_box._on_interact_focused()
	assert_true(prompt_label.visible, "Focus gained must show prompt label.")

	ammo_box._on_interact_unfocused()
	assert_false(prompt_label.visible, "Focus lost must hide prompt label.")


## Verifies that player interaction adds rounds to matching inventory weapon and frees pickup.
func test_interaction_replenishes_ammo_and_frees_box() -> void:
	print("TestAmmoBox: test_interaction_replenishes_ammo_and_frees_box() called.")
	ammo_box.ammo_amount = 8
	ammo_box._on_interact_component_interacted(mock_player)

	var current_res: int = mock_gun.reserve_ammo
	assert_eq(current_res, 18, "Reserve ammo should increase by ammo_amount.")
	assert_true(ammo_box.is_queued_for_deletion(), "Ammo box must queue free after consumption.")
