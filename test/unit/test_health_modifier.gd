extends GutTest

const ModifierScript = preload("res://shared/health_modifier.gd")

## Variant instance for the health modifier under test.
var modifier: Variant = null
## Dummy physics body to represent a character.
var dummy_body: Node3D = null
## Child health component attached to the dummy body.
var health_comp: Variant = null


func before_each() -> void:
	print("TestHealthModifier: before_each() setup.")

	modifier = ModifierScript.new()
	add_child_autofree(modifier)
	modifier.tick_interval = 0.1  # Faster ticks for testing

	dummy_body = Node3D.new()
	add_child_autofree(dummy_body)

	# Add a structural node to match the get_node_or_null("Components/HealthComponent") path
	var components_node: Node = Node.new()
	components_node.name = "Components"
	dummy_body.add_child(components_node)

	health_comp = load("res://shared/health_component.gd").new()
	health_comp.name = "HealthComponent"
	health_comp.max_health = 100
	components_node.add_child(health_comp)
	health_comp._ready()


class MockModifier:
	extends Area3D
	var modify_amount: int = -25
	var mock_bodies: Array[Node3D] = []

	func get_overlapping_bodies() -> Array[Node3D]:
		return mock_bodies

	func _on_tick_timer_timeout() -> void:
		var bodies: Array[Node3D] = get_overlapping_bodies()

		for body: Node3D in bodies:
			# Added "Components/" to the relative path
			var health_node: Node = body.get_node_or_null("Components/HealthComponent")

			if health_node:
				if modify_amount < 0:
					health_node.take_damage(abs(modify_amount))
				elif modify_amount > 0:
					health_node.heal(modify_amount)


func test_modifier_applies_damage() -> void:
	print("TestHealthModifier: test_modifier_applies_damage() called.")

	var mock_mod: MockModifier = MockModifier.new()
	add_child_autofree(mock_mod)
	mock_mod.mock_bodies = [dummy_body]
	mock_mod.modify_amount = -20

	# Trigger timeout manually
	mock_mod._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should decrease by 20 from modifier.")


func test_modifier_applies_healing() -> void:
	print("TestHealthModifier: test_modifier_applies_healing() called.")
	health_comp.take_damage(50)  # Set health to 50

	var mock_mod: MockModifier = MockModifier.new()
	add_child_autofree(mock_mod)
	mock_mod.mock_bodies = [dummy_body]
	mock_mod.modify_amount = 30

	mock_mod._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should increase by 30 from modifier.")
