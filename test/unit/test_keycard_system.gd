extends GutTest

## The loaded script reference for KeycardSystem.
const KEYCARD_SYSTEM_SCRIPT: GDScript = preload("res://core/KeycardSystem.gd")

## The instance of the KeycardSystem being tested.
var system: Variant = null


## Instantiates KeycardSystem and registers autofree cleanup.
func before_each() -> void:
	print("TestKeycardSystem: before_each() called. Setting up test environment.")
	system = autofree(KEYCARD_SYSTEM_SCRIPT.new())
	if system is Node:
		add_child_autoqfree(system)


## Verifies picking up a card tracks correctly and emits card_picked_up.
func test_add_card() -> void:
	print("TestKeycardSystem: test_add_card() called. Testing adding a card.")
	watch_signals(system)

	system.add_card(&"red_card")

	assert_true(system.has_card(&"red_card"), "System should have red_card.")
	assert_signal_emitted_with_parameters(system, "card_picked_up", [&"red_card"])


## Verifies picking up duplicate cards is rejected without emitting signals.
func test_add_duplicate_card() -> void:
	print("TestKeycardSystem: test_add_duplicate_card() called. Testing adding duplicate.")
	system.add_card(&"blue_card")
	watch_signals(system)

	system.add_card(&"blue_card")

	assert_signal_not_emitted(system, "card_picked_up", "Should not emit on duplicate.")


## Verifies consuming a valid card removes it and emits card_used.
func test_consume_card() -> void:
	print("TestKeycardSystem: test_consume_card() called. Testing consuming a card.")
	system.add_card(&"green_card")
	watch_signals(system)

	system.consume_card(&"green_card")

	assert_false(system.has_card(&"green_card"), "System should not have green_card.")
	assert_signal_emitted_with_parameters(system, "card_used", [&"green_card"])


## Verifies consuming a missing card fails gracefully without emitting signals.
func test_consume_nonexistent_card() -> void:
	print("TestKeycardSystem: test_consume_nonexistent_card() called. Testing invalid card.")
	watch_signals(system)

	system.consume_card(&"yellow_card")

	assert_signal_not_emitted(system, "card_used", "Should not emit if card missing.")
