## Unit test suite validating SmokeGrenadeWeapon pickup event emissions and HUD tag registration.
class_name TestSmokeGrenadePickup
extends GutTest

## The smoke grenade weapon instance under test.
var grenade: SmokeGrenadeWeapon = null

## The tag notification UI overlay under test.
var tag_hud: TagNotification = null

## Mock player instance.
var mock_player: CharacterBody3D = null

## Weapon inventory component.
var inventory: WeaponInventoryComponent = null


## Prepares isolated SmokeGrenadeWeapon, mock player, and TagNotification before each test.
func before_each() -> void:
	print("TestSmokeGrenadePickup: Setting up test environment.")
	grenade = SmokeGrenadeWeapon.new()
	add_child_autofree(grenade)

	mock_player = CharacterBody3D.new()
	add_child_autofree(mock_player)

	inventory = WeaponInventoryComponent.new()
	inventory.name = "WeaponInventoryComponent"
	mock_player.add_child(inventory)

	tag_hud = TagNotification.new()
	add_child_autofree(tag_hud)


## Teardown hook sweeping root-level projectile spawns and resetting SmokeManager.
func after_each() -> void:
	var root: Window = get_tree().root
	for child: Node in root.find_children("*", "SmokeGrenadeProjectile", true, false):
		child.queue_free()
	for child: Node in root.find_children("*", "FogVolume", true, false):
		child.queue_free()

	var smoke_manager: Node = root.get_node_or_null("SmokeManager")
	if is_instance_valid(smoke_manager) and smoke_manager.has_method(&"clear_all"):
		smoke_manager.call(&"clear_all")

	grenade = null
	tag_hud = null
	mock_player = null
	inventory = null


## Verifies that equipping SmokeGrenadeWeapon emits weapon_tag_displayed with 'smoke_grenade'.
func test_pickup_emits_weapon_tag_displayed() -> void:
	print("TestSmokeGrenadePickup: test_pickup_emits_weapon_tag_displayed() executing.")
	watch_signals(Events)

	grenade.equip_to_player(mock_player)

	assert_signal_emitted_with_parameters(Events, "weapon_tag_displayed", ["smoke_grenade"])
	assert_true(
		grenade.is_equipped, "Grenade should be marked as equipped after equip_to_player()."
	)


## Verifies that TagNotification registers and spawns the smoke grenade dogtag texture.
func test_tag_notification_registers_smoke_grenade() -> void:
	print("TestSmokeGrenadePickup: test_tag_notification_registers_smoke_grenade() executing.")
	assert_true(
		TagNotification.TAG_TEXTURES.has("smoke_grenade"),
		"TagNotification must have smoke_grenade registered in TAG_TEXTURES."
	)

	Events.weapon_tag_displayed.emit("smoke_grenade")

	assert_has(
		tag_hud._collected_order,
		"smoke_grenade",
		"smoke_grenade must be present in _collected_order."
	)
	assert_eq(
		tag_hud._active_weapon,
		"smoke_grenade",
		"smoke_grenade must be marked as active weapon in TagNotification."
	)
	assert_true(
		tag_hud._spawned_tags.has("smoke_grenade"),
		"TextureRect node must be created and tracked in _spawned_tags."
	)
