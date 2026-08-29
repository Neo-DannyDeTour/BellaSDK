## Unit tests for the KeycardSystem autoload script.
##
## This suite verifies the behavior of the [KeycardSystem] singleton to ensure
## keycards can be added, tracked, and consumed correctly, alongside signal emissions.
class_name TestKeycardSystem
extends GutTest

## The loaded script reference for [KeycardSystem].
const KEYCARD_SYSTEM_SCRIPT: GDScript = preload("res://core/KeycardSystem.gd")

## The instance of the [KeycardSystem] being tested.
var system: Node = null


## Instantiates [KeycardSystem] and registers autofree cleanup.
func before_each() -> void:
	print("TestKeycardSystem: before_each() called. Setting up test environment.")
	system = autofree(KeycardSystem.new()) as Node
	if system is Node:
		add_child_autoqfree(system)


## Verifies picking up a card tracks correctly and emits [signal KeycardSystem.card_picked_up].
func test_add_card() -> void:
	print("TestKeycardSystem: test_add_card() called. Testing adding a card.")
	watch_signals(system)

	system.call("add_card", &"red_card")

	assert_true(bool(system.call("has_card", &"red_card")), "System should have red_card.")
	assert_signal_emitted_with_parameters(system, "card_picked_up", [&"red_card"])


## Verifies picking up duplicate cards is rejected without emitting signals.
func test_add_duplicate_card() -> void:
	print("TestKeycardSystem: test_add_duplicate_card() called. Testing adding duplicate.")
	system.call("add_card", &"blue_card")
	watch_signals(system)

	system.call("add_card", &"blue_card")

	assert_signal_not_emitted(system, "card_picked_up", "Should not emit on duplicate.")


## Verifies consuming a valid card removes it and emits [signal KeycardSystem.card_used].
func test_consume_card() -> void:
	print("TestKeycardSystem: test_consume_card() called. Testing consuming a card.")
	system.call("add_card", &"green_card")
	watch_signals(system)

	system.call("consume_card", &"green_card")

	assert_false(bool(system.call("has_card", &"green_card")), "System should not have green_card.")
	assert_signal_emitted_with_parameters(system, "card_used", [&"green_card"])


## Verifies consuming a missing card fails gracefully without emitting signals.
func test_consume_nonexistent_card() -> void:
	print("TestKeycardSystem: test_consume_nonexistent_card() called. Testing invalid card.")
	watch_signals(system)

	system.call("consume_card", &"yellow_card")

	assert_signal_not_emitted(system, "card_used", "Should not emit if card missing.")
