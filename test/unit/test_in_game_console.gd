## Unit tests for [InGameConsole] functionality and UI suggestion updates.
class_name TestInGameConsole
extends GutTest

## Preloaded scene reference for the in-game console under test.
const CONSOLE_SCENE: PackedScene = preload("res://ui/in_game_console.tscn")

## Instance of the console UI under test.
var _console: CanvasLayer = null


## Set up test instance before each test method.
func before_each() -> void:
	print("TestInGameConsole: Instantiating InGameConsole for test.")
	var raw_node: Node = CONSOLE_SCENE.instantiate()
	_console = raw_node as CanvasLayer
	if not is_instance_valid(_console):
		if is_instance_valid(raw_node):
			raw_node.queue_free()
		return
	add_child_autofree(_console)


## Clean up test instance after each test method.
func after_each() -> void:
	print("TestInGameConsole: Cleaning up InGameConsole instance.")


## Tests that _update_suggestion_ui produces correct BBCode output when match_index is active.
func test_update_suggestion_ui_formatting() -> void:
	print("TestInGameConsole: Running test_update_suggestion_ui_formatting().")
	var matches: Array[String] = ["help", "clear", "quit"]
	_console.set("current_matches", matches)
	_console.set("match_index", 1)

	_console.call("_update_suggestion_ui")

	var expected: String = (
		"[color=gray]  help[/color]\n"
		+ "[color=yellow]> clear[/color]\n"
		+ "[color=gray]  quit[/color]"
	)

	var label_node: Node = _console.get_node_or_null(
		"BackgroundPanel/LayoutContainer/SuggestionLog"
	)
	assert_not_null(label_node, "SuggestionLog node should be present.")
	if label_node is RichTextLabel:
		var label: RichTextLabel = label_node
		assert_eq(label.text, expected)


## Tests that _update_suggestion_ui handles empty current_matches cleanly.
func test_update_suggestion_ui_empty() -> void:
	print("TestInGameConsole: Running test_update_suggestion_ui_empty().")
	var empty_matches: Array[String] = []
	_console.set("current_matches", empty_matches)
	_console.set("match_index", -1)

	_console.call("_update_suggestion_ui")

	var label_node: Node = _console.get_node_or_null(
		"BackgroundPanel/LayoutContainer/SuggestionLog"
	)
	assert_not_null(label_node, "SuggestionLog node should be present.")
	if label_node is RichTextLabel:
		var label: RichTextLabel = label_node
		assert_eq(label.text, "")


## Tests that infinite_ammo console command correctly updates settings and state.
func test_infinite_ammo_console_command() -> void:
	print("TestInGameConsole: Running test_infinite_ammo_console_command().")
	_console.call("_cmd_infinite_ammo", PackedStringArray(["on"]))
	assert_true(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_ammo", false),
		"Infinite ammo should be enabled after running command with 'on'."
	)

	_console.call("_cmd_infinite_ammo", PackedStringArray(["off"]))
	assert_false(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_ammo", false),
		"Infinite ammo should be disabled after running command with 'off'."
	)

	_console.call("_cmd_infinite_ammo", PackedStringArray())
	assert_true(
		GlobalSettings.get_setting_bool("Accessibility", "infinite_ammo", false),
		"Infinite ammo should be toggled to true when invoked without arguments."
	)
	_console.call("_cmd_infinite_ammo", PackedStringArray(["off"]))


## Tests that toggle commands invert state on subsequent invocations.
func test_toggle_command_double_invocation() -> void:
	print("TestInGameConsole: Running test_toggle_command_double_invocation().")
	var states: Dictionary = _console.get("toggle_states") as Dictionary
	states["wolfvision"] = false

	_console.call("_cmd_wolfvision", PackedStringArray())
	assert_true(states["wolfvision"], "First invocation without args should activate wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray())
	assert_false(
		states["wolfvision"], "Second invocation without args should deactivate wolfvision."
	)


## Tests that toggle commands accept 1/0 and on/off arguments.
func test_toggle_command_boolean_tokens() -> void:
	print("TestInGameConsole: Running test_toggle_command_boolean_tokens().")
	var states: Dictionary = _console.get("toggle_states") as Dictionary

	_console.call("_cmd_wolfvision", PackedStringArray(["1"]))
	assert_true(states["wolfvision"], "Argument '1' should turn on wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray(["0"]))
	assert_false(states["wolfvision"], "Argument '0' should turn off wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray(["on"]))
	assert_true(states["wolfvision"], "Argument 'on' should turn on wolfvision.")

	_console.call("_cmd_wolfvision", PackedStringArray(["off"]))
	assert_false(states["wolfvision"], "Argument 'off' should turn off wolfvision.")


## Tests that invalid toggle arguments do not mutate state.
func test_toggle_command_invalid_argument() -> void:
	print("TestInGameConsole: Running test_toggle_command_invalid_argument().")
	var states: Dictionary = _console.get("toggle_states") as Dictionary
	states["wolfvision"] = false

	_console.call("_cmd_wolfvision", PackedStringArray(["gibberish"]))
	assert_false(states["wolfvision"], "Invalid argument should not mutate toggle state.")


## Tests that autocomplete matches include boolean toggle options.
func test_toggle_command_autocomplete_suggestions() -> void:
	print("TestInGameConsole: Running test_toggle_command_autocomplete_suggestions().")
	var reg: ConsoleCommandRegistry = _console.get("registry") as ConsoleCommandRegistry
	assert_not_null(reg, "Command registry should exist.")

	var matches: Array[String] = reg.get_autocomplete_matches("wolfvision ")
	assert_true(matches.has("wolfvision on"), "Suggestions should contain 'wolfvision on'.")
	assert_true(matches.has("wolfvision off"), "Suggestions should contain 'wolfvision off'.")
	assert_true(matches.has("wolfvision 1"), "Suggestions should contain 'wolfvision 1'.")
	assert_true(matches.has("wolfvision 0"), "Suggestions should contain 'wolfvision 0'.")
