## Tests signal rocket auto-ignition, launch, weapon-switch drop, and burnout cleanup.
class_name TestSignalRocket
extends GutTest

## Preloaded weapon script avoiding global class resolution warning before project scan.
const ROCKET_SCRIPT: GDScript = preload("res://weapons/signal_rocket/signal_rocket_weapon.gd")

## The [WeaponInventoryComponent] instance under test.
var inventory: WeaponInventoryComponent = null

## The parent weapon holder socket node.
var weapon_holder: Node3D = null

## The rocket weapon under test.
var rocket: SignalRocketWeapon = null

## Simulated player camera.
var camera: Camera3D = null

## Simulated player body.
var player_body: CharacterBody3D = null


## Sets up inventory, camera, player body, and attaches rocket before each test.
func before_each() -> void:
	player_body = CharacterBody3D.new()
	player_body.name = "Player"
	inventory = WeaponInventoryComponent.new()
	inventory.name = "WeaponInventoryComponent"
	weapon_holder = Node3D.new()
	weapon_holder.name = "WeaponHolder"
	camera = Camera3D.new()
	camera.name = "Camera3D"

	add_child_autofree(player_body)
	player_body.add_child(inventory)
	player_body.add_child(weapon_holder)
	player_body.add_child(camera)

	inventory.weapon_holder = weapon_holder
	inventory.camera = camera

	var rocket_inst: Node = ROCKET_SCRIPT.new()
	rocket = rocket_inst as SignalRocketWeapon
	weapon_holder.add_child(rocket)
	autofree(rocket)


## Verifies equipping signal rocket auto-ignites the fuse and starts burn timer.
func test_equip_ignites_flare() -> void:
	rocket.equip_to_player(player_body)
	assert_true(rocket.is_equipped)
	assert_true(rocket.visible)
	assert_eq(rocket.current_ammo, 1)
	assert_gt(rocket._ignition_time_msec, 0.0)
	assert_not_null(rocket._burn_timer)
	assert_eq(inventory.slots[rocket.default_slot - 1], rocket)


## Verifies launching projectile empties ammo, clears inventory, and cleans up.
func test_shoot_launches_and_cleans_inventory() -> void:
	var pistol: Node3D = Node3D.new()
	pistol.set("weapon_tag", "pistol")
	pistol.set("default_slot", 1)
	weapon_holder.add_child(pistol)
	autofree(pistol)
	inventory.register_weapon(pistol)

	rocket.equip_to_player(player_body)
	inventory.select_slot(rocket.default_slot - 1)

	var fired: bool = rocket.shoot(camera)
	assert_true(fired)
	assert_true(rocket._is_expended)
	assert_eq(rocket.current_ammo, 0)
	assert_null(inventory.slots[rocket.default_slot - 1])


## Verifies switching away from active lit rocket drops it and clears inventory slot.
func test_switch_drops_lit_rocket() -> void:
	var pistol: Node3D = Node3D.new()
	pistol.set("weapon_tag", "pistol")
	pistol.set("default_slot", 1)
	weapon_holder.add_child(pistol)
	autofree(pistol)
	inventory.register_weapon(pistol)

	rocket.equip_to_player(player_body)
	inventory.select_slot(rocket.default_slot - 1)
	assert_eq(inventory.current_slot_index, rocket.default_slot - 1)

	inventory.select_slot(0)
	assert_true(rocket._is_expended)
	assert_eq(rocket.current_ammo, 0)


## Verifies held rocket burnout automatically depletes and unregisters from inventory.
func test_burnout_in_hand() -> void:
	rocket.burn_duration = 0.05
	rocket.equip_to_player(player_body)
	assert_true(rocket.is_equipped)
	assert_not_null(rocket._burn_timer)

	await rocket._burn_timer.timeout
	await get_tree().process_frame

	assert_false(is_instance_valid(rocket))
	assert_null(inventory.slots[3])


## Verifies thrown burning rocket projectile can be interacted with to re-equip into hands.
func test_repick_thrown_rocket() -> void:
	rocket.equip_to_player(player_body)
	assert_true(rocket.is_equipped)

	var fired: bool = rocket.shoot(camera)
	assert_true(fired)

	var proj: SignalRocketProjectile = null
	for child: Node in get_tree().root.get_children():
		if child is SignalRocketProjectile:
			proj = child as SignalRocketProjectile
			break

	assert_not_null(proj, "SignalRocketProjectile must be spawned in scene tree.")
	autofree(proj)
	assert_true(proj.is_inside_tree())

	proj.interact_with(player_body)
	await get_tree().process_frame

	assert_false(is_instance_valid(proj), "Projectile must be freed after pickup.")
	var re_equipped: SignalRocketWeapon = inventory.slots[3] as SignalRocketWeapon
	assert_not_null(re_equipped, "SignalRocketWeapon should be re-equipped in slot 4.")
	assert_true(re_equipped.is_equipped)
	assert_eq(re_equipped.current_ammo, 1)
	assert_gt(re_equipped.burn_duration, 0.0)
	autofree(re_equipped)
