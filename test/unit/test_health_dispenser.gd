## Unit tests for HealthDispenser verifying health reservoir, healing logic, and screen updates.
class_name TestHealthDispenser
extends GutTest

const HEALTH_DISPENSER_SCRIPT: GDScript = preload("res://interactables/health_dispenser.gd")
const HEALTH_COMPONENT_SCRIPT: GDScript = preload("res://core/components/health_component.gd")

## Primary HealthDispenser node instance under test.
var _dispenser: HealthDispenser = null


## Prepares a clean HealthDispenser instance before each test execution.
func before_each() -> void:
	print("TestHealthDispenser: before_each() setup started.")
	_dispenser = HEALTH_DISPENSER_SCRIPT.new()
	add_child_autofree(_dispenser)


## Cleans up HealthDispenser reference after each test execution.
func after_each() -> void:
	print("TestHealthDispenser: after_each() cleanup completed.")
	_dispenser = null


## Verifies default dispenser health initialization and reservoir configuration.
func test_initialization() -> void:
	print("TestHealthDispenser: test_initialization() executing.")
	assert_eq(_dispenser.max_dispenser_health, 200, "Default max_dispenser_health should be 200.")
	var current_hp: int = _dispenser.get("_current_dispenser_health")
	assert_eq(current_hp, 200, "Initial reservoir health should match max_dispenser_health.")


## Verifies that interact_held dispenses health to injured player character.
func test_interact_held_healing() -> void:
	print("TestHealthDispenser: test_interact_held_healing() executing.")
	var player: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(player)

	var comps: Node = Node.new()
	comps.name = "Components"
	player.add_child(comps)

	var health_comp: Node = HEALTH_COMPONENT_SCRIPT.new()
	health_comp.name = "HealthComponent"
	comps.add_child(health_comp)
	health_comp.set("max_health", 100)
	health_comp.set("current_health", 50)

	_dispenser.set("_player_health_component", health_comp)
	_dispenser.set("_last_heal_time", 0)

	_dispenser.interact_held(player)

	var new_hp: int = health_comp.get("current_health")
	assert_eq(new_hp, 75, "Player health should increase by heal_amount (25 HP).")

	var remaining_dispenser_hp: int = _dispenser.get("_current_dispenser_health")
	assert_eq(remaining_dispenser_hp, 175, "Dispenser reservoir should decrease by 25 HP.")


## Verifies screen texture update logic across player health threshold brackets.
func test_update_screen() -> void:
	print("TestHealthDispenser: test_update_screen() executing.")
	var sprite: Sprite3D = Sprite3D.new()
	add_child_autofree(sprite)
	_dispenser.screen_sprite = sprite

	var health_comp: Node = HEALTH_COMPONENT_SCRIPT.new()
	add_child_autofree(health_comp)
	health_comp.set("max_health", 100)
	health_comp.set("current_health", 20)

	var tex_low: Texture2D = Texture2D.new()
	var tex_high: Texture2D = Texture2D.new()
	_dispenser.tex_low_health = tex_low
	_dispenser.tex_ready_health = tex_high

	_dispenser.set("_player_health_component", health_comp)

	@warning_ignore("unsafe_method_access")
	_dispenser.call("_update_screen")
	assert_eq(
		_dispenser.screen_sprite.texture, tex_low, "Low health ratio should set tex_low_health."
	)

	health_comp.set("current_health", 100)
	@warning_ignore("unsafe_method_access")
	_dispenser.call("_update_screen")
	assert_eq(
		_dispenser.screen_sprite.texture, tex_high, "Full health ratio should set tex_ready_health."
	)
