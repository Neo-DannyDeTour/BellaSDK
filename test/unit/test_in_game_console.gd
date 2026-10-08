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
	_console = CONSOLE_SCENE.instantiate() as CanvasLayer
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
