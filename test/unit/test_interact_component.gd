class_name TestInteractComponent
extends GutTest

## The interact component under test.
var component: InteractComponent

## A mock parent node.
var mock_parent: Node

## A mock character body.
var mock_character: CharacterBody3D


class MockParent:
	extends Node
	var interacted_with: bool = false
	var interact_held_called: bool = false

	func interact_with(_character: CharacterBody3D) -> void:
		interacted_with = true

	func interact_held(_character: CharacterBody3D) -> void:
		interact_held_called = true


func before_each() -> void:
	print("TestInteractComponent: before_each() setup starting.")
	component = InteractComponent.new()
	mock_parent = MockParent.new()
	mock_character = CharacterBody3D.new()

	mock_parent.add_child(component)
	add_child_autofree(mock_parent)
	add_child_autofree(mock_character)
	print("TestInteractComponent: before_each() setup completed.")


func test_hover_cursor() -> void:
	print("TestInteractComponent: test_hover_cursor() running.")
	var hit_position: Vector3 = Vector3(1, 2, 3)

	assert_false(component.is_currently_focused, "Should not be focused initially.")
	assert_false(component.is_processing(), "Process should be disabled initially.")

	component.hover_cursor(mock_character, hit_position)

	assert_true(component.is_currently_focused, "Should be focused after hover.")
	assert_true(component.is_processing(), "Process should be enabled after hover.")
	assert_eq(component.last_hit_position, hit_position, "Hit position should be recorded.")
	assert_true(
		component.characters_hovering.has(mock_character),
		"Character should be in hovering dictionary."
	)


func test_interact_with() -> void:
	print("TestInteractComponent: test_interact_with() running.")
	component.interact_with(mock_character)
	assert_true(
		mock_parent.get("interacted_with"), "Parent's interact_with should have been called."
	)


func test_interact_held() -> void:
	print("TestInteractComponent: test_interact_held() running.")
	component.interact_held(mock_character)
	assert_true(
		mock_parent.get("interact_held_called"), "Parent's interact_held should have been called."
	)
