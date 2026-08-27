extends GutTest

## Variant instance for the health modifier under test.
var modifier: Variant = null
## Dummy physics body to represent a character.
var dummy_body: Node3D = null
## Child health component attached to the dummy body.
var health_comp: Variant = null


func before_each() -> void:
	print("TestHealthModifier: before_each() setup.")

	modifier = load("res://shared/health_modifier.gd").new()
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


func test_modifier_applies_damage() -> void:
	print("TestHealthModifier: test_modifier_applies_damage() called.")
	modifier.modify_amount = -10
	modifier._ready()

	# Manually push the dummy body into the modifier's overlapping array
	# since we are bypassing physics engine overlap detection.
	# Wait, Area3D.get_overlapping_bodies() relies on the physics server.
	# We can instead test the internal tick function by replacing the array if possible,
	# or manually calling the internal logic if it's coupled.

	# Let's mock get_overlapping_bodies on the modifier.
	var modifier_double: Variant = double("res://shared/health_modifier.gd")
	var mocked_modifier: Variant = modifier_double.new()
	add_child_autofree(mocked_modifier)
	stub(mocked_modifier, "get_overlapping_bodies").to_return([dummy_body])

	mocked_modifier.modify_amount = -20
	mocked_modifier._ready()

	# Trigger timeout manually
	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should decrease by 20 from modifier.")


func test_modifier_applies_healing() -> void:
	print("TestHealthModifier: test_modifier_applies_healing() called.")
	health_comp.take_damage(50)  # Set health to 50

	var modifier_double: Variant = double("res://shared/health_modifier.gd")
	var mocked_modifier: Variant = modifier_double.new()
	add_child_autofree(mocked_modifier)
	stub(mocked_modifier, "get_overlapping_bodies").to_return([dummy_body])

	mocked_modifier.modify_amount = 30
	mocked_modifier._ready()

	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should increase by 30 from modifier.")
