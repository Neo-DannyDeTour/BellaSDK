extends GutTest

## The instance of the KeycardSystem being tested.
## We use Variant since the script is not globally registered.
var system: Variant = null


func before_each() -> void:
	print("TestKeycardSystem: before_each() called. Setting up test environment.")
	system = load("res://core/KeycardSystem.gd").new()
	add_child_autofree(system)


func test_add_card() -> void:
	print("TestKeycardSystem: test_add_card() called. Testing adding a card.")
	watch_signals(system)

	system.add_card(&"red_card")

	assert_true(system.has_card(&"red_card"), "System should have red_card.")
	assert_signal_emitted_with_parameters(system, "card_picked_up", [&"red_card"])


func test_add_duplicate_card() -> void:
	print("TestKeycardSystem: test_add_duplicate_card() called. Testing adding duplicate.")
	system.add_card(&"blue_card")
	watch_signals(system)

	system.add_card(&"blue_card")

	assert_signal_not_emitted(system, "card_picked_up", "Should not emit on duplicate.")


func test_consume_card() -> void:
	print("TestKeycardSystem: test_consume_card() called. Testing consuming a card.")
	system.add_card(&"green_card")
	watch_signals(system)

	system.consume_card(&"green_card")

	assert_false(system.has_card(&"green_card"), "System should not have green_card.")
	assert_signal_emitted_with_parameters(system, "card_used", [&"green_card"])


func test_consume_nonexistent_card() -> void:
	print("TestKeycardSystem: test_consume_nonexistent_card() called. Testing invalid card.")
	watch_signals(system)

	system.consume_card(&"yellow_card")

	assert_signal_not_emitted(system, "card_used", "Should not emit if card missing.")
