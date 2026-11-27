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
	assert_eq(_get_manager_idx(), 1, "Ring index should advance to 1.")


## Verifies a [RigidBody3D] on layer 1 is rejected.
func test_rigid_body_rejected() -> void:
	var body: RigidBody3D = RigidBody3D.new()
	body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	add_child_autofree(body)
	manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	assert_eq(_get_manager_idx(), 0, "Moving bodies must not consume pool slots.")


## Verifies a [StaticBody3D] outside the environment layer is rejected.
func test_non_environment_layer_rejected() -> void:
	var body: StaticBody3D = _make_static_body(CollisionLayers.MASK_INTERACTIVE)
	manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	assert_eq(_get_manager_idx(), 0, "Interactive layer must not receive holes.")


## Verifies the ring index wraps after exceeding the pool size.
func test_ring_index_wraps() -> void:
	var body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	var pool_map: Dictionary = IMPACT_MANAGER_SCRIPT.get_script_constant_map()
	var raw_size: Variant = pool_map.get("POOL_SIZE", 64)
	var pool_size: int = raw_size if raw_size is int else 64
	for i: int in range(pool_size + 1):
		manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	assert_eq(_get_manager_idx(), 1, "Index should wrap to 1 after pool_size + 1 hits.")


## Verifies scene change hides every pooled decal and resets VFX bursts and indices.
func test_scene_changed_hides_all() -> void:
	var body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	for i: int in range(3):
		manager.call(&"_on_bullet_impact_requested", Vector3.ZERO, Vector3.UP, body)

	manager.call(&"_on_scene_changed")

	for child: Node in manager.get_children():
		if child is Decal:
			var decal: Decal = child as Decal
			assert_false(decal.visible, "All decals should be hidden after scene change.")
	assert_eq(_get_manager_idx(), 0, "Ring index should reset after scene change.")
	assert_eq(_get_vfx_idx(), 0, "VFX ring index should reset after scene change.")

	var vfx_container: Node = manager.get_node_or_null("ImpactVfxContainer")
	assert_not_null(vfx_container, "ImpactVfxContainer child should exist.")
	if is_instance_valid(vfx_container):
		assert_eq(vfx_container.get_child_count(), 16, "VFX pool should contain 16 bursts.")
		for burst_node: Node in vfx_container.get_children():
			for emitter_node: Node in burst_node.get_children():
				if emitter_node is GPUParticles3D:
					var emitter: GPUParticles3D = emitter_node as GPUParticles3D
					assert_false(emitter.emitting, "VFX emitter should stop on scene change.")
					assert_false(emitter.visible, "VFX emitter should hide on scene change.")


## Verifies concrete, wood, and metal static hits pick surface-matched decal textures.
func test_surface_decal_selection() -> void:
	var concrete_body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	concrete_body.add_to_group(&"concrete")
	var wood_body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	wood_body.add_to_group(&"wood")
	var metal_body: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	metal_body.add_to_group(&"metal")

	manager.call(&"_on_bullet_impact_requested", Vector3(1.0, 0.0, 0.0), Vector3.UP, concrete_body)
	manager.call(&"_on_bullet_impact_requested", Vector3(2.0, 0.0, 0.0), Vector3.UP, wood_body)
	manager.call(&"_on_bullet_impact_requested", Vector3(3.0, 0.0, 0.0), Vector3.UP, metal_body)

	var concrete_decal: Decal = manager.get_child(0) as Decal
	var wood_decal: Decal = manager.get_child(1) as Decal
	var metal_decal: Decal = manager.get_child(2) as Decal

	var concrete_albedos: Array = _get_texture_array(&"_albedos")
	var wood_albedos: Array = _get_texture_array(&"_wood_albedos")
	var metal_albedos: Array = _get_texture_array(&"_metal_albedos")
	var metal_orms: Array = _get_texture_array(&"_metal_orms")

	assert_true(concrete_albedos.has(concrete_decal.texture_albedo), "Should use concrete albedo.")
	assert_true(wood_albedos.has(wood_decal.texture_albedo), "Should use wood albedo.")
	assert_true(metal_albedos.has(metal_decal.texture_albedo), "Should use metal albedo.")
	assert_true(metal_orms.has(metal_decal.texture_orm), "Metal should use specular ORM rim.")
	assert_ne(wood_decal.texture_albedo, concrete_decal.texture_albedo, "Wood != concrete texture.")


## Verifies interactive RigidBody3D props spawn a VFX burst without consuming decal slots.
func test_interactive_prop_triggers_vfx_without_decal() -> void:
	var crate: RigidBody3D = RigidBody3D.new()
	crate.collision_layer = CollisionLayers.MASK_INTERACTIVE
	crate.add_to_group(&"wood")
	add_child_autofree(crate)

	manager.call(&"_on_bullet_impact_requested", Vector3(0.0, 1.5, 0.0), Vector3.FORWARD, crate)

	assert_eq(_get_manager_idx(), 0, "Interactive RigidBody3D must not consume decal slots.")
	assert_eq(_get_vfx_idx(), 1, "Interactive RigidBody3D should trigger an ImpactVfxBurst.")

	var vfx_container: Node = manager.get_node_or_null("ImpactVfxContainer")
	assert_not_null(vfx_container, "ImpactVfxContainer should exist.")
	if is_instance_valid(vfx_container):
		var burst: Node = vfx_container.get_child(0)
		var smoke_puff: GPUParticles3D = burst.get_node("SmokePuff") as GPUParticles3D
		var debris_chips: GPUParticles3D = burst.get_node("DebrisChips") as GPUParticles3D
		var metal_sparks: GPUParticles3D = burst.get_node("MetalSparks") as GPUParticles3D
		assert_true(smoke_puff.visible, "Wood burst should activate SmokePuff.")
		assert_true(debris_chips.visible, "Wood burst should activate DebrisChips.")
		assert_false(metal_sparks.visible, "Wood burst should skip MetalSparks.")


## Verifies an 8-pellet shotgun impact in one frame caps VFX bursts at 3 while placing 8 decals.
func test_shotgun_frame_vfx_burst_cap() -> void:
	var wall: StaticBody3D = _make_static_body(CollisionLayers.MASK_ENVIRONMENT)
	for i: int in range(8):
		var offset: Vector3 = Vector3(float(i) * 0.05, 0.0, 0.0)
		manager.call(&"_on_bullet_impact_requested", offset, Vector3.BACK, wall)

	assert_eq(_get_manager_idx(), 8, "All 8 shotgun pellets should place bullet hole decals.")
	assert_eq(_get_vfx_idx(), 3, "Same-frame shotgun bursts must cap at 3 ImpactVfxBurst slots.")
	assert_eq(_get_frame_burst_count(), 3, "Per-frame burst counter must cap at 3.")


## Creates an auto-freed [StaticBody3D] on [param layer_mask].
func _make_static_body(layer_mask: int) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = layer_mask
	add_child_autofree(body)
	return body


## Helper retrieving private ring buffer index safely.
func _get_manager_idx() -> int:
	var raw: Variant = manager.get(&"_idx")
	return raw if raw is int else -1


## Helper retrieving private VFX burst ring buffer index safely.
func _get_vfx_idx() -> int:
	var raw: Variant = manager.get(&"_vfx_idx")
	return raw if raw is int else -1


## Helper retrieving per-frame VFX burst count safely.
func _get_frame_burst_count() -> int:
	var raw: Variant = manager.get(&"_frame_burst_count")
	return raw if raw is int else -1


## Helper retrieving a private texture array safely for surface decal verification.
func _get_texture_array(prop_name: StringName) -> Array:
	var raw: Variant = manager.get(prop_name)
	return raw if raw is Array else []
