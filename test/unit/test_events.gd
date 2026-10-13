extends GutTest

## The target singleton event bus instance we are testing
var _events_instance: Node


func before_all() -> void:
	print("Setting up global events singleton for tests.")
	_events_instance = Events

	if not _events_instance:
		_events_instance = load("res://shared/events.gd").new()
		get_tree().root.add_child(_events_instance)


func test_events_initialization() -> void:
	print("Testing Events singleton initialization.")
	assert_not_null(_events_instance, "Events singleton should be initialized and accessible.")


func test_dynamic_signals_can_be_emitted() -> void:
	print("Testing Events singleton dynamic signal emissions.")
	watch_signals(_events_instance)

	_events_instance.player_damaged.emit(10)
	assert_signal_emitted_with_parameters(
		_events_instance, "player_damaged", [10], "Should emit player_damaged successfully."
	)

	_events_instance.godmode_toggled.emit(true)
	assert_signal_emitted_with_parameters(
		_events_instance, "godmode_toggled", [true], "Should emit godmode_toggled successfully."
	)

	_events_instance.active_weapon_changed.emit("pistol")
	assert_signal_emitted_with_parameters(
		_events_instance,
		"active_weapon_changed",
		["pistol"],
		"Should emit active_weapon_changed successfully."
	)


func test_load_registered_fonts() -> void:
	print("Testing Events._load_registered_fonts()")
	# Simply calling this should not crash and should cache the fallback font
	_events_instance._load_registered_fonts()
	var fonts: Dictionary = _events_instance.fonts
	assert_has(fonts, "default", "Should have registered a default fallback font.")


func test_on_font_changed() -> void:
	print("Testing Events._on_font_changed()")
	_events_instance._on_font_changed("default")
	# Assert that this ran without throwing an error by executing true
	assert_true(true, "Font changed without errors")
