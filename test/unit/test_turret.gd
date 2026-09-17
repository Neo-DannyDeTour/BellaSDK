extends GutTest

## Preloaded script reference for the turret under test.
const TURRET_SCRIPT: GDScript = preload("res://enemies/turret.gd")

## The Turret instance under test.
var turret: Variant = null
## Dummy node for target tracking.
var dummy_target: Node3D = null
## Health component for damage testing.
var health_comp: HealthComponent = null


## Mock turret to override required components that are usually built in the editor scene.
class MockTurret:
	extends "res://enemies/turret.gd"

	func _ready() -> void:
		# Bypass area and shape setup since they rely on child nodes existing in the real scene
		pass


func before_each() -> void:
	print("TestTurret: before_each() setup.")

	turret = MockTurret.new()
	add_child_autofree(turret)

	var head_node: Node3D = Node3D.new()
	turret.add_child(head_node)
	turret.head = head_node

	var particles: GPUParticles3D = GPUParticles3D.new()
	head_node.add_child(particles)
	turret.bullet_particles = particles

	dummy_target = Node3D.new()
	dummy_target.name = "DummyTarget"

	var components_node: Node = Node.new()
	components_node.name = "Components"
	dummy_target.add_child(components_node)

	health_comp = load("res://shared/health_component.gd").new()
	health_comp.name = "HealthComponent"
	health_comp.max_health = 100
	components_node.add_child(health_comp)

	add_child_autofree(dummy_target)
	health_comp._ready()

	turret._ready()


func test_set_target() -> void:
	print("TestTurret: test_set_target() called.")
	turret._set_target(dummy_target)

	assert_eq(turret.target, dummy_target, "Turret should correctly assign the target.")
	assert_eq(
		turret.target_health_comp,
		health_comp,
		"Turret should correctly cache the target's HealthComponent."
	)


func test_change_state() -> void:
	print("TestTurret: test_change_state() called.")
	turret._change_state(1)  # TurretState.ENGAGING

	assert_eq(turret.current_state, 1, "Turret state should update to ENGAGING.")


func test_damage_player() -> void:
	print("TestTurret: test_damage_player() called.")
	turret._set_target(dummy_target)
	turret.damage = 15

	turret._damage_target()

	assert_eq(
		health_comp.current_health,
		85,
		"Turret should deal correct damage to the target's HealthComponent."
	)


func test_is_hostile() -> void:
	print("TestTurret: test_is_hostile() called.")
	var groups: Array[StringName] = [&"player"]
	turret.hostile_groups = groups

	var mock_enemy: Node = Node.new()
	mock_enemy.add_to_group("enemy")
	var mock_player: Node = Node.new()
	mock_player.add_to_group("player")

	assert_false(turret._is_hostile(mock_enemy), "Should not identify non-hostile groups.")
	assert_true(turret._is_hostile(mock_player), "Should identify hostile groups.")

	mock_enemy.free()
	mock_player.free()
