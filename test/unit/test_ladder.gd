## Unit test suite validating Ladder sizing, runtime mesh visibility, and body interactions.
class_name TestLadder
extends GutTest

## The ladder instance under test.
var ladder: Ladder = null


## Mock physics body implementing ladder interaction receiver methods.
class MockClimber:
	extends CharacterBody3D

	## Last ladder instance passed to enter_ladder.
	var last_entered_ladder: Node3D = null

	## Last ladder instance passed to exit_ladder.
	var last_exited_ladder: Node3D = null

	## Records entered ladder instance.
	func enter_ladder(ladder_node: Node3D) -> void:
		print("MockClimber: enter_ladder() called.")
		last_entered_ladder = ladder_node

	## Records exited ladder instance.
	func exit_ladder(ladder_node: Node3D) -> void:
		print("MockClimber: exit_ladder() called.")
		last_exited_ladder = ladder_node


## Creates a clean ladder instance before each test.
func before_each() -> void:
	print("TestLadder: before_each() setup.")
	ladder = Ladder.new()
	add_child_autofree(ladder)


## Verifies that mutating ladder_size updates child collision shape dimensions.
func test_ladder_size_updates_collision_shape() -> void:
	print("TestLadder: test_ladder_size_updates_collision_shape() called.")
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(1.0, 1.0, 1.0)
	col_shape.shape = box_shape
	col_shape.name = "CollisionShape3D"
	ladder.add_child(col_shape)

	var new_size: Vector3 = Vector3(3.0, 8.0, 0.8)
	ladder.ladder_size = new_size

	var updated_box: BoxShape3D = col_shape.shape as BoxShape3D
	assert_not_null(updated_box, "CollisionShape3D should hold a valid BoxShape3D.")
	assert_eq(updated_box.size, new_size, "Collision shape size should match ladder_size.")


## Verifies that _ready hides helper mesh visuals outside the editor.
func test_ready_hides_visuals_at_runtime() -> void:
	print("TestLadder: test_ready_hides_visuals_at_runtime() called.")
	var arrow_mesh: MeshInstance3D = MeshInstance3D.new()
	arrow_mesh.name = "Arrow"
	arrow_mesh.visible = true
	ladder.add_child(arrow_mesh)

	var main_mesh: MeshInstance3D = MeshInstance3D.new()
	main_mesh.name = "MeshInstance3D"
	main_mesh.visible = true
	ladder.add_child(main_mesh)

	ladder.arrow = arrow_mesh
	ladder._ready()

	assert_false(arrow_mesh.visible, "Editor arrow mesh should be hidden at runtime.")
	assert_false(main_mesh.visible, "Main helper mesh should be hidden at runtime.")


## Verifies that body entry dispatches enter_ladder to capable bodies.
func test_body_entered_calls_climber() -> void:
	print("TestLadder: test_body_entered_calls_climber() called.")
	var climber: MockClimber = MockClimber.new()
	add_child_autofree(climber)

	ladder._on_body_entered(climber)
	assert_eq(climber.last_entered_ladder, ladder, "Climber should record ladder on enter.")


## Verifies that body exit dispatches exit_ladder to capable bodies.
func test_body_exited_calls_climber() -> void:
	print("TestLadder: test_body_exited_calls_climber() called.")
	var climber: MockClimber = MockClimber.new()
	add_child_autofree(climber)

	ladder._on_body_exited(climber)
	assert_eq(climber.last_exited_ladder, ladder, "Climber should record ladder on exit.")


## Verifies that non-climber physics bodies trigger no errors on entry or exit.
func test_non_climber_body_ignored() -> void:
	print("TestLadder: test_non_climber_body_ignored() called.")
	var inert_body: StaticBody3D = StaticBody3D.new()
	add_child_autofree(inert_body)

	ladder._on_body_entered(inert_body)
	ladder._on_body_exited(inert_body)
	pass_test("Non-climber body was safely ignored without exceptions.")
