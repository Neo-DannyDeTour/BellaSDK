## Unit tests for KeycardData custom resource verifying clearance identifiers and visuals.
class_name TestKeycardData
extends GutTest

## Primary KeycardData resource instance under test.
var _keycard_data: KeycardData = null


## Sets up a fresh KeycardData instance before each test.
func before_each() -> void:
	print("TestKeycardData: before_each() setup started.")
	_keycard_data = KeycardData.new()


## Cleans up KeycardData reference after each test.
func after_each() -> void:
	print("TestKeycardData: after_each() cleanup completed.")
	_keycard_data = null


## Verifies default property values on freshly created KeycardData resources.
func test_default_values() -> void:
	print("TestKeycardData: test_default_values() executing.")
	assert_eq(_keycard_data.card_id, &"", "Default card_id should be empty StringName.")
	assert_eq(_keycard_data.display_letter, "", "Default display_letter should be empty string.")
	assert_eq(_keycard_data.display_number, "", "Default display_number should be empty string.")
	assert_eq(_keycard_data.card_color, Color.WHITE, "Default card_color should be Color.WHITE.")
	assert_null(_keycard_data.card_texture, "Default card_texture should be null.")


## Verifies setting custom card identification credentials and visual properties.
func test_custom_properties() -> void:
	print("TestKeycardData: test_custom_properties() executing.")
	_keycard_data.card_id = &"RED_LEVEL_3"
	_keycard_data.display_letter = "A"
	_keycard_data.display_number = "101"
	_keycard_data.card_color = Color.RED

	assert_eq(_keycard_data.card_id, &"RED_LEVEL_3", "card_id should match assigned StringName.")
	assert_eq(_keycard_data.display_letter, "A", "display_letter should match assigned text.")
	assert_eq(_keycard_data.display_number, "101", "display_number should match assigned text.")
	assert_eq(_keycard_data.card_color, Color.RED, "card_color should match assigned Color.")
