## Unit tests for BreakableTallCrate damage fracture and debris layer assignment.
extends GutTest

## Preloaded tall breakable wooden crate scene.
const CRATE_SCENE: PackedScene = preload(
	"res://props/breakable_tall_crate/breakable_tall_crate.tscn"
)


## Verifies initial intact state, zero per-frame process overhead, and 8 frozen gibs.
func test_initial_state() -> void:
	var crate: RigidBody3D = CRATE_SCENE.instantiate() as RigidBody3D
	add_child_autofree(crate)
	assert_false(crate.is_processing(), "Should disable _process in _ready().")
	assert_false(crate.is_physics_processing(), "Should disable _physics_process in _ready().")
	assert_eq(crate.collision_layer, CollisionLayers.MASK_INTERACTIVE)
	var gibs_root: Node3D = crate.get_node("Gibs") as Node3D
	assert_not_null(gibs_root)
	assert_false(gibs_root.visible)
	assert_eq(gibs_root.get_child_count(), 8)


## Verifies lethal damage emits broken signal and wakes 8 gibs on the Debris layer.
func test_breaks_into_eight_debris_gibs_on_lethal_damage() -> void:
	var container: Node3D = Node3D.new()
	add_child_autofree(container)
	var crate: RigidBody3D = CRATE_SCENE.instantiate() as RigidBody3D
	container.add_child(crate)

	watch_signals(crate)
	crate.call("take_damage", 50.0, Vector3.ZERO, Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_signal_emitted(crate, "broken")
	assert_eq(crate.collision_layer, CollisionLayers.MASK_NONE)

	var debris_count: int = 0
	for child: Node in container.get_children():
		var rb: RigidBody3D = child as RigidBody3D
		if rb != null and rb != crate and rb.collision_layer == CollisionLayers.MASK_DEBRIS:
			debris_count += 1
			assert_false(rb.freeze)
	assert_eq(debris_count, 8, "Expected 8 active debris gibs reparented to container.")
