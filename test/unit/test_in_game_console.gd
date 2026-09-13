## Unit tests for [InGameConsole] functionality and UI suggestion updates.
class_name TestInGameConsole
extends GutTest

var _console: InGameConsole


## Set up test instance before each test method.
func before_each() -> void:
	print("TestInGameConsole: Instantiating InGameConsole for test.")
	_console = InGameConsole.new()
	_console._ready()


## Clean up test instance after each test method.
func after_each() -> void:
	print("TestInGameConsole: Cleaning up InGameConsole instance.")
	if is_instance_valid(_console):
		_console.free()


## Tests that _update_suggestion_ui produces correct BBCode output when match_index is active.
func test_update_suggestion_ui_formatting() -> void:
	print("TestInGameConsole: Running test_update_suggestion_ui_formatting().")
	_console.current_matches = ["help", "clear", "quit"]
	_console.match_index = 1

	_console._update_suggestion_ui()

	var expected: String = (
		"[color=gray]  help[/color]\n"
		+ "[color=yellow]> clear[/color]\n"
		+ "[color=gray]  quit[/color]"
	)
	assert_eq(_console.suggestion_label.text, expected)


## Tests that _update_suggestion_ui handles empty current_matches cleanly.
func test_update_suggestion_ui_empty() -> void:
	print("TestInGameConsole: Running test_update_suggestion_ui_empty().")
	_console.current_matches = []
	_console.match_index = -1

	_console._update_suggestion_ui()

	assert_eq(_console.suggestion_label.text, "")
