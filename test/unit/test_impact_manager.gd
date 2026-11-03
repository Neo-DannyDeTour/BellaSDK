## Unit test suite validating ImpactManager collider filtering, ring buffer, and scene clearing.
class_name TestImpactManager
extends GutTest

## Script under test; no class_name because it would shadow the ImpactManager autoload.
const IMPACT_MANAGER_SCRIPT: GDScript = preload("res://vfx/impact_manager.gd")

## The isolated manager instance under test.
var manager: Node3D = null


## Instantiates an isolated ImpactManager before each test.
func before_each() -> void:
	print("TestImpactManager: before_each() setup started.")
	manager = IMPACT_MANAGER_SCRIPT.new() as Node3D
	add_child_autofree(manager)


## Verifies a layer 1 [StaticBody3D] hit shows a decal and advances the ring index.
func test_static_environment_places_decal() -> void:
	var body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	manager.call(&"_on_bullet_impact_requested", Vector3(1.0, 2.0, 3.0), Vector3.UP, body)

	var first: Decal = manager.get_child(0) as Decal
	assert_true(first.visible, "First pooled decal should be visible after valid hit.")
	assert_almost_eq(first.global_position, Vector3(1.0, 2.0, 3.0), Vector3.ONE * 0.001)
	assert_eq(int(manager.get(&"_idx")), 1, "Ring index should advance to 1.")


## Verifies a [RigidBody3D] on layer 1 is rejected.
func test_rigid_body_rejected() -> void:
	var body: RigidBody3D = RigidBody3D.new()
	body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	add_child_autofree(body)
	manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	assert_eq(int(manager.get(&"_idx")), 0, "Moving bodies must not consume pool slots.")


## Verifies a [StaticBody3D] outside the environment layer is rejected.
func test_non_environment_layer_rejected() -> void:
	var body: StaticBody3D = _make_static_body(CollisionLayers.MASK_INTERACTIVE)
	manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	assert_eq(int(manager.get(&"_idx")), 0, "Interactive layer must not receive holes.")


## Verifies the ring index wraps after exceeding the pool size.
func test_ring_index_wraps() -> void:
	var body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	var pool_size: int = int(IMPACT_MANAGER_SCRIPT.get_script_constant_map()["POOL_SIZE"])
	for i: int in range(pool_size + 1):
		manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	assert_eq(int(manager.get(&"_idx")), 1, "Index should wrap to 1 after pool_size + 1 hits.")


## Verifies scene change hides every pooled decal and resets the index.
func test_scene_changed_hides_all() -> void:
	var body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	for i: int in range(3):
		manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	manager.call(&"_on_scene_changed")

	for child: Node in manager.get_children():
		var decal: Decal = child as Decal
		assert_false(decal.visible, "All decals should be hidden after scene change.")
	assert_eq(int(manager.get(&"_idx")), 0, "Ring index should reset after scene change.")


## Creates an auto-freed [StaticBody3D] on [param layer_mask].
func _make_static_body(layer_mask: int) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = layer_mask
	add_child_autofree(body)
	return body
