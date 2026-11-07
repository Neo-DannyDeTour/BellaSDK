## Tests signal rocket auto-ignition, launch, weapon-switch drop, and burnout cleanup.
class_name TestSignalRocket
extends GutTest

## Preloaded weapon script avoiding global class resolution warning before project scan.
const ROCKET_SCRIPT: GDScript = preload("res://weapons/signal_rocket/signal_rocket_weapon.gd")

## Preloaded weapon scene validating scene node configuration.
const WEAPON_SCENE: PackedScene = preload("res://weapons/signal_rocket/signal_rocket_weapon.tscn")

## Preloaded projectile scene validating scene node configuration.
const PROJECTILE_SCENE: PackedScene = preload(
	"res://weapons/signal_rocket/signal_rocket_projectile.tscn"
)

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


## Cleans up spawned projectiles and references from root scene tree.
func after_each() -> void:
	var root: Window = get_tree().root
	for child: Node in root.find_children("*", "SignalRocketProjectile", true, false):
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			child.queue_free()


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


## Verifies interact_with called through interact_comp does not cause weapon duplication.
func test_projectile_repick_no_duplication() -> void:
	var slot_index: int = rocket.default_slot - 1
	rocket.equip_to_player(player_body)
	assert_true(rocket.is_equipped)

	var fired: bool = rocket.shoot(camera)
	assert_true(fired)

	var proj: SignalRocketProjectile = null
	for child: Node in get_tree().root.get_children():
		if child is SignalRocketProjectile:
			proj = child as SignalRocketProjectile
			break

	assert_not_null(proj, "SignalRocketProjectile must be spawned.")
	autofree(proj)

	# Simulate what InteractionScanner calls (interact_with on InteractComponent)
	proj.interact_comp.interact_with(player_body)
	await get_tree().process_frame

	assert_false(is_instance_valid(proj), "Projectile must be freed after pickup.")

	var count_projectiles: int = 0
	for child: Node in get_tree().root.get_children():
		if child is SignalRocketProjectile and is_instance_valid(child):
			count_projectiles += 1
	assert_eq(count_projectiles, 0, "No duplicate projectiles should exist on floor.")

	var equipped_rocket: SignalRocketWeapon = inventory.slots[slot_index] as SignalRocketWeapon
	assert_not_null(equipped_rocket, "Exactly one rocket weapon should be equipped in slot 4.")
	assert_true(equipped_rocket.is_equipped)
	assert_eq(equipped_rocket.current_ammo, 1)
	autofree(equipped_rocket)


## Verifies projectile has prompt label, icon, and highlight components suppressed on burnout.
func test_projectile_prompts_and_burnout() -> void:
	var proj_inst: Node = PROJECTILE_SCENE.instantiate()
	var proj: SignalRocketProjectile = proj_inst as SignalRocketProjectile
	get_tree().root.add_child(proj)
	autofree(proj)

	assert_not_null(proj.label, "Projectile should have Label3D.")
	assert_not_null(proj.prompt_icon, "Projectile should have PromptIcon.")
	assert_not_null(proj.highlight_comp, "Projectile should have HighlightComponent.")
	assert_false(proj.label.visible, "Label3D should start hidden.")

	# Simulate hover focus
	proj.interact_comp.focused.emit()
	assert_true(proj.label.visible, "Label3D should be visible on focus.")

	# Fast forward burnout
	proj.arm(0.02)
	await proj._burn_timer.timeout
	await get_tree().process_frame

	assert_false(proj.label.visible, "Label3D should hide on burnout.")
	assert_false(proj.prompt_icon.visible, "PromptIcon should hide on burnout.")
	assert_false(proj.interact_comp.is_enabled, "InteractComponent should be disabled on burnout.")


## Verifies SignalRocketWeapon scene contains HighlightComponent for level pickup.
func test_weapon_scene_has_highlight_component() -> void:
	var wpn_inst: Node = WEAPON_SCENE.instantiate()
	add_child_autofree(wpn_inst)
	var hl: HighlightComponent = (
		wpn_inst.get_node_or_null("HighlightComponent") as HighlightComponent
	)
	assert_not_null(hl, "SignalRocketWeapon scene must contain HighlightComponent.")
	assert_not_null(hl.interact_component, "HighlightComponent must link to InteractComponent.")
