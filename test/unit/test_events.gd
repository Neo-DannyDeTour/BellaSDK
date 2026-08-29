## Unit tests for the global [Events] singleton.
extends GutTest

## The instance of the Events singleton for testing.
var _events: Node


## Setup logic that runs before each individual test.
func before_each() -> void:
	print("Setting up Events test environment...")
	_events = load("res://shared/events.gd").new()
	add_child_autofree(_events)


## Teardown logic that runs after each individual test.
func after_each() -> void:
	print("Tearing down Events test environment...")


## Tests that the initial state of the events manager is correct.
func test_initial_state() -> void:
	print("Executing test_initial_state...")
	assert_false(_events.is_godmode, "Godmode should be false by default.")
	assert_eq(_events.fonts.size(), 0, "Fonts dictionary should be initially empty.")
	assert_false(_events._is_cached, "Font cache state should be false by default.")
	assert_null(_events.engine_fallback_font, "Fallback font should be initially null.")


## Tests the [is_godmode] property modification.
func test_godmode_toggle() -> void:
	print("Executing test_godmode_toggle...")
	_events.is_godmode = true
	assert_true(_events.is_godmode, "Godmode should be true after assignment.")
	_events.is_godmode = false
	assert_false(_events.is_godmode, "Godmode should be false after assignment.")
