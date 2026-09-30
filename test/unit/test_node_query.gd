extends GutTest

## A GUT test script for the [NodeQuery] class validating hierarchical traversal logic.
var test_name: String = "Test NodeQuery"

## The root Node3D of the test hierarchy.
var _root_node: Node3D = null
## The child Node3D in the test hierarchy.
var _child_node: Node3D = null
## The grandchild RigidBody3D in the test hierarchy.
var _grandchild_node: RigidBody3D = null


func before_each() -> void:
	print("Setting up NodeQuery test hierarchy...")
	_root_node = Node3D.new()
	_root_node.add_to_group(&"root_group")

	_child_node = Node3D.new()
	_child_node.add_to_group(&"child_group")

	_grandchild_node = RigidBody3D.new()

	_root_node.add_child(_child_node)
	_child_node.add_child(_grandchild_node)

	add_child_autoqfree(_root_node)


func test_find_ancestor_of_type() -> void:
	print("Testing NodeQuery.find_ancestor_of_type()...")
	var res: Node = NodeQuery.find_ancestor_of_type(_grandchild_node, Node3D)
	assert_eq(res, _child_node, "Should find the immediate parent which is a Node3D")

	var res_null: Node = NodeQuery.find_ancestor_of_type(_grandchild_node, Camera3D)
	assert_null(res_null, "Should return null for a non-existent ancestor type")


func test_find_ancestor_in_group() -> void:
	print("Testing NodeQuery.find_ancestor_in_group()...")
	var res: Node = NodeQuery.find_ancestor_in_group(_grandchild_node, &"root_group")
	assert_eq(res, _root_node, "Should find the ancestor in the root group")

	var res_null: Node = NodeQuery.find_ancestor_in_group(_grandchild_node, &"missing_group")
	assert_null(res_null, "Should return null for a non-existent group")
