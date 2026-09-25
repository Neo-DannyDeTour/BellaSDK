## Complete GUT test suite validating [Utilities] static helper methods and edge cases.
class_name TestUtilities
extends GutTest


## Dummy ancestor class for hierarchy search tests.
class DummyAncestorNode:
	extends Node


## Dummy intermediate child class for hierarchy search tests.
class DummyChildNode:
	extends Node


## Test signal emitted without payload to verify [method Utilities.safe_connect].
signal test_ping

## Tracks execution flag for testing callback dispatching in [Callable] tests.
var _callback_executed: bool = false


## Target callback invoked by signal emission to toggle [member _callback_executed].
func _on_test_ping_received() -> void:
	print("[TestUtilities] Received test signal ping.")
	_callback_executed = true


## Resets test state and internal flags before each test scenario runs.
func before_each() -> void:
	print("[TestUtilities] Running before_each setup.")
	_callback_executed = false


## Cleans up transient test artifacts and state after each test scenario completes.
func after_each() -> void:
	print("[TestUtilities] Running after_each teardown.")
	_callback_executed = false


## Verifies [method Utilities.center_control] calculates pivot from non-zero size.
func test_center_control_with_size() -> void:
	print("[TestUtilities] Testing center_control with explicit size.")
	var control: Control = Control.new()
	autofree(control)
	control.size = Vector2(200.0, 100.0)
	Utilities.center_control(control)
	assert_eq(control.pivot_offset, Vector2(100.0, 50.0), "Pivot offset should match half size.")


## Verifies [method Utilities.center_control] falls back to custom minimum size.
func test_center_control_with_custom_minimum_size() -> void:
	print("[TestUtilities] Testing center_control with custom_minimum_size.")
	var control: Control = Control.new()
	autofree(control)
	control.size = Vector2.ZERO
	control.custom_minimum_size = Vector2(120.0, 60.0)
	Utilities.center_control(control)
	assert_eq(
		control.pivot_offset,
		Vector2(60.0, 30.0),
		"Pivot offset should match half custom_minimum_size."
	)


## Verifies [method Utilities.center_control] handles null inputs without throwing errors.
func test_center_control_null_guard() -> void:
	print("[TestUtilities] Testing center_control null guard.")
	Utilities.center_control(null)
	pass_test("Null control handled gracefully.")


## Verifies [method Utilities.clear_children] calls [method Node.queue_free] on all children.
func test_clear_children_valid_parent() -> void:
	print("[TestUtilities] Testing clear_children on valid parent.")
	var parent: Node = Node.new()
	add_child_autofree(parent)
	var child_a: Node = Node.new()
	var child_b: Node = Node.new()
	parent.add_child(child_a)
	parent.add_child(child_b)
	assert_eq(parent.get_child_count(), 2, "Parent should have two children initially.")
	Utilities.clear_children(parent)
	assert_true(child_a.is_queued_for_deletion(), "Child A must be queued for deletion.")
	assert_true(child_b.is_queued_for_deletion(), "Child B must be queued for deletion.")


## Verifies [method Utilities.clear_children] handles null input safely.
func test_clear_children_null_guard() -> void:
	print("[TestUtilities] Testing clear_children null guard.")
	Utilities.clear_children(null)
	pass_test("Null parent handled gracefully.")


## Verifies [method Utilities.reset_tween] creates a valid [Tween] when existing is null.
func test_reset_tween_null_existing() -> void:
	print("[TestUtilities] Testing reset_tween with null initial tween.")
	var node: Node = Node.new()
	add_child_autofree(node)
	var tw: Tween = Utilities.reset_tween(node, null)
	assert_not_null(tw, "Created tween should not be null.")
	assert_true(tw.is_valid(), "Created tween should be valid.")


## Verifies [method Utilities.reset_tween] kills existing [Tween] before returning a new one.
func test_reset_tween_replaces_active_tween() -> void:
	print("[TestUtilities] Testing reset_tween kills existing active tween.")
	var node: Node = Node.new()
	add_child_autofree(node)
	var first_tw: Tween = node.create_tween()
	assert_true(first_tw.is_valid(), "Initial tween must be valid.")
	var second_tw: Tween = Utilities.reset_tween(node, first_tw)
	assert_false(first_tw.is_valid(), "Original tween should be killed.")
	assert_not_null(second_tw, "New tween should not be null.")
	assert_true(second_tw.is_valid(), "New tween must be valid.")


## Verifies [method Utilities.reset_tween] returns null for nodes not inside the tree.
func test_reset_tween_orphan_node_guard() -> void:
	print("[TestUtilities] Testing reset_tween orphan node guard.")
	var orphan_node: Node = Node.new()
	autofree(orphan_node)
	var tw: Tween = Utilities.reset_tween(orphan_node, null)
	assert_null(tw, "Tween creation on orphan node should return null.")


## Verifies [method Utilities.safe_connect] binds signal to [Callable] and returns true.
func test_safe_connect_success() -> void:
	print("[TestUtilities] Testing safe_connect initial binding.")
	var target_callable: Callable = Callable(self, "_on_test_ping_received")
	var connected: bool = Utilities.safe_connect(test_ping, target_callable)
	assert_true(connected, "Initial safe_connect call should return true.")
	assert_true(test_ping.is_connected(target_callable), "Signal should be connected.")
	test_ping.emit()
	assert_true(_callback_executed, "Emitted signal should trigger callable.")
	test_ping.disconnect(target_callable)


## Verifies [method Utilities.safe_connect] prevents redundant connection and returns false.
func test_safe_connect_prevents_duplicate() -> void:
	print("[TestUtilities] Testing safe_connect duplicate connection guard.")
	var target_callable: Callable = Callable(self, "_on_test_ping_received")
	test_ping.connect(target_callable)
	var connected_again: bool = Utilities.safe_connect(test_ping, target_callable)
	assert_false(connected_again, "Subsequent safe_connect call should return false.")
	test_ping.disconnect(target_callable)


## Verifies [method Utilities.reparent_keep_transform] shifts hierarchy while preserving pose.
func test_reparent_keep_transform() -> void:
	print("[TestUtilities] Testing reparent_keep_transform with Node3D.")
	var parent_a: Node3D = Node3D.new()
	var parent_b: Node3D = Node3D.new()
	var child: Node3D = Node3D.new()
	add_child_autofree(parent_a)
	add_child_autofree(parent_b)
	parent_a.position = Vector3(10.0, 0.0, 0.0)
	parent_b.position = Vector3(0.0, 20.0, 0.0)
	parent_a.add_child(child)
	child.position = Vector3(5.0, 5.0, 5.0)
	var expected_global_pos: Vector3 = child.global_position
	Utilities.reparent_keep_transform(child, parent_b, true)
	assert_eq(child.get_parent(), parent_b, "Child parent should be updated.")
	assert_almost_eq(
		child.global_position.x,
		expected_global_pos.x,
		0.001,
		"Global X position must be preserved."
	)
	assert_almost_eq(
		child.global_position.y,
		expected_global_pos.y,
		0.001,
		"Global Y position must be preserved."
	)
	assert_almost_eq(
		child.global_position.z,
		expected_global_pos.z,
		0.001,
		"Global Z position must be preserved."
	)


## Verifies [method Utilities.reparent_keep_transform] handles null or orphan nodes safely.
func test_reparent_null_and_orphan_guards() -> void:
	print("[TestUtilities] Testing reparent_keep_transform safety guards.")
	var valid_parent: Node = Node.new()
	add_child_autofree(valid_parent)
	var orphan_child: Node = Node.new()
	autofree(orphan_child)
	Utilities.reparent_keep_transform(null, valid_parent)
	Utilities.reparent_keep_transform(orphan_child, null)
	Utilities.reparent_keep_transform(orphan_child, valid_parent)
	assert_null(
		orphan_child.get_parent(), "Orphan child without tree presence should not be reparented."
	)


## Verifies [method Utilities.raycast_3d] returns empty dictionary if space state is null.
func test_raycast_3d_null_space_state() -> void:
	print("[TestUtilities] Testing raycast_3d null space state handling.")
	var res: Dictionary = Utilities.raycast_3d(null, Vector3.ZERO, Vector3.FORWARD)
	assert_eq(res, {}, "Null space state must return empty dictionary.")


## Verifies [method Utilities.raycast_3d] correctly updates cached query parameters.
func test_raycast_3d_query_cache_mutation() -> void:
	print("[TestUtilities] Testing raycast_3d query parameter mutation.")
	var node_3d: Node3D = Node3D.new()
	add_child_autofree(node_3d)
	var world_3d: World3D = node_3d.get_world_3d()
	if not world_3d:
		pass_test("World3D unavailable in headless run; skipped query call.")
		return
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var origin: Vector3 = Vector3(1.0, 2.0, 3.0)
	var target: Vector3 = Vector3(4.0, 5.0, 6.0)
	var mask: int = 7
	var dummy_rid: RID = RID()
	var exclude: Array[RID] = [dummy_rid]
	Utilities.raycast_3d(space, origin, target, mask, exclude)
	var query: PhysicsRayQueryParameters3D = Utilities._cached_ray_query
	assert_eq(query.from, origin, "Cached query 'from' should be updated.")
	assert_eq(query.to, target, "Cached query 'to' should be updated.")
	assert_eq(query.collision_mask, mask, "Cached query mask should be updated.")
	assert_eq(query.exclude, exclude, "Cached query exclude array must be updated.")


## Verifies [method Utilities.delay_call] triggers [Callable] after specified timeout.
func test_delay_call_execution() -> void:
	print("[TestUtilities] Testing delay_call async callback execution.")
	var node: Node = Node.new()
	add_child_autofree(node)
	var target_callable: Callable = Callable(self, "_on_test_ping_received")
	var timer: SceneTreeTimer = Utilities.delay_call(node, 0.05, target_callable)
	assert_not_null(timer, "Timer instance should not be null.")
	assert_false(_callback_executed, "Callback should not fire immediately.")
	await wait_seconds(0.1)
	assert_true(_callback_executed, "Callback should be triggered after delay timeout.")


## Verifies [method Utilities.delay_call] returns null when node is not in scene tree.
func test_delay_call_orphan_node_guard() -> void:
	print("[TestUtilities] Testing delay_call orphan node guard.")
	var orphan_node: Node = Node.new()
	autofree(orphan_node)
	var target_callable: Callable = Callable(self, "_on_test_ping_received")
	var timer: SceneTreeTimer = Utilities.delay_call(orphan_node, 0.1, target_callable)
	assert_null(timer, "Orphan node should return null timer.")
	assert_false(_callback_executed, "Callback should not be triggered on orphan.")


## Verifies [method Utilities.find_ancestor_of_type] traverses upwards to find matching script.
func test_find_ancestor_of_type_success() -> void:
	print("[TestUtilities] Testing find_ancestor_of_type hierarchy ascent.")
	var grand_parent: DummyAncestorNode = DummyAncestorNode.new()
	var parent: DummyChildNode = DummyChildNode.new()
	var child: Node = Node.new()
	add_child_autofree(grand_parent)
	grand_parent.add_child(parent)
	parent.add_child(child)
	var found: Node = Utilities.find_ancestor_of_type(child, DummyAncestorNode)
	assert_eq(found, grand_parent, "Should locate DummyAncestorNode two levels up.")


## Verifies [method Utilities.find_ancestor_of_type] returns null if script is not in ancestry.
func test_find_ancestor_of_type_missing() -> void:
	print("[TestUtilities] Testing find_ancestor_of_type missing target.")
	var parent: Node = Node.new()
	var child: Node = Node.new()
	add_child_autofree(parent)
	parent.add_child(child)
	var found: Node = Utilities.find_ancestor_of_type(child, DummyAncestorNode)
	assert_null(found, "Should return null if target script is not in hierarchy.")


## Verifies [method Utilities.find_ancestor_of_type] handles null node or script gracefully.
func test_find_ancestor_of_type_null_guards() -> void:
	print("[TestUtilities] Testing find_ancestor_of_type null guards.")
	var node: Node = Node.new()
	autofree(node)
	assert_null(
		Utilities.find_ancestor_of_type(null, DummyAncestorNode), "Null node should return null."
	)
	assert_null(Utilities.find_ancestor_of_type(node, null), "Null script type should return null.")
