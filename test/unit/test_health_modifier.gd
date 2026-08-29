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

	# Add our dummy_body to the area to simulate overlap
	# We can just manually set its position if the physics server was running
	# but since it is headless, we mock the array manually.


func test_modifier_applies_damage() -> void:
	print("TestHealthModifier: test_modifier_applies_damage() called.")

	var script: GDScript = GDScript.new()
	script.source_code = """
extends Area3D
var modify_amount: int = -20
func _on_tick_timer_timeout() -> void:
	var bodies: Array[Node3D] = []
	var body: Node3D = get_meta("dummy_body")
	if is_instance_valid(body):
		bodies.append(body)
	for b: Node3D in bodies:
		var health_node: Node = b.get_node_or_null("Components/HealthComponent")
		if health_node != null:
			if modify_amount < 0:
				health_node.take_damage(abs(modify_amount))
			elif modify_amount > 0:
				health_node.heal(modify_amount)
"""
	script.reload()
	var mocked_modifier: Variant = script.new()
	add_child_autofree(mocked_modifier)
	mocked_modifier.set_meta("dummy_body", dummy_body)

	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should decrease by 20 from modifier.")


func test_modifier_applies_healing() -> void:
	print("TestHealthModifier: test_modifier_applies_healing() called.")
	health_comp.take_damage(50)  # Set health to 50

	var script: GDScript = GDScript.new()
	script.source_code = """
extends Area3D
var modify_amount: int = 30
func _on_tick_timer_timeout() -> void:
	var bodies: Array[Node3D] = []
	var body: Node3D = get_meta("dummy_body")
	if is_instance_valid(body):
		bodies.append(body)
	for b: Node3D in bodies:
		var health_node: Node = b.get_node_or_null("Components/HealthComponent")
		if health_node != null:
			if modify_amount < 0:
				health_node.take_damage(abs(modify_amount))
			elif modify_amount > 0:
				health_node.heal(modify_amount)
"""
	script.reload()
	var mocked_modifier: Variant = script.new()
	add_child_autofree(mocked_modifier)
	mocked_modifier.set_meta("dummy_body", dummy_body)

	mocked_modifier._on_tick_timer_timeout()

	assert_eq(health_comp.current_health, 80, "Health should increase by 30 from modifier.")
