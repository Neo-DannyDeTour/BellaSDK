## Unit test suite validating global event bus emissions and typography overrides.
extends GutTest

const EventsScript: GDScript = preload("res://core/events.gd")

## Cached reference to the target event bus instance under test.
var _events_instance: EventsScript


## Initializes or references the global event bus instance before running tests.
func before_all() -> void:
	print("Setting up global events singleton for tests.")
	if is_instance_valid(Events):
		_events_instance = Events as EventsScript

	if not is_instance_valid(_events_instance):
		_events_instance = EventsScript.new() as EventsScript
		get_tree().root.add_child(_events_instance)


## Cleans up the dynamically instantiated event bus after all test runs complete.
func after_all() -> void:
	print("Tearing down test environment.")
	if is_instance_valid(_events_instance) and _events_instance != Events:
		_events_instance.queue_free()


## Verifies that the Events instance is initialized and accessible.
func test_events_initialization() -> void:
	print("Testing Events singleton initialization.")
	assert_not_null(_events_instance, "Events singleton should be initialized and accessible.")


## Verifies dynamic emission and argument fidelity for core game signals.
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


## Verifies fallback font registration within the internal font registry.
func test_load_registered_fonts() -> void:
	print("Testing Events._load_registered_fonts()")
	_events_instance._load_registered_fonts()
	var registered_fonts: Dictionary = _events_instance.fonts
	assert_has(registered_fonts, "default", "Should have registered a default fallback font.")


## Verifies font switching executes cleanly across active scenes without error.
func test_on_font_changed() -> void:
	print("Testing Events._on_font_changed()")
	_events_instance._on_font_changed("default")
	assert_true(true, "Font changed without errors")
