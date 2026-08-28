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


func test_modifier_applies_damage() -> void:
	print("TestHealthModifier: test_modifier_applies_damage() called.")

	# Create a true collision scenario or use a custom extended script
	var mocked_modifier: Variant = ModifierScript.new()
	add_child_autofree(mocked_modifier)
	# Inject dummy_body by exploiting duck typing or by overriding the script temporarily
	mocked_modifier.set_script(preload("res://test/mocks/mock_health_modifier.gd"))
	mocked_modifier._dummy_bodies = [dummy_body]


	mocked_modifier.modify_amount = -20

	# Trigger timeout manually
	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should decrease by 20 from modifier.")


func test_modifier_applies_healing() -> void:
	print("TestHealthModifier: test_modifier_applies_healing() called.")
	health_comp.take_damage(50)  # Set health to 50

	# Create a true collision scenario or use a custom extended script
	var mocked_modifier: Variant = ModifierScript.new()
	add_child_autofree(mocked_modifier)
	# Inject dummy_body by exploiting duck typing or by overriding the script temporarily
	mocked_modifier.set_script(preload("res://test/mocks/mock_health_modifier.gd"))
	mocked_modifier._dummy_bodies = [dummy_body]


	mocked_modifier.modify_amount = 30

	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should increase by 30 from modifier.")
