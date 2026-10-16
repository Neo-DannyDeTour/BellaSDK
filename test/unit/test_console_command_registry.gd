## Unit test suite for ConsoleCommandRegistry managing command registration and autocomplete.
class_name TestConsoleCommandRegistry
extends GutTest

## Internal reference to the command registry instance being tested.
var _registry: ConsoleCommandRegistry = null


## Initializes a fresh ConsoleCommandRegistry instance before each test.
func before_each() -> void:
	print("TestConsoleCommandRegistry: Initializing new ConsoleCommandRegistry.")
	_registry = ConsoleCommandRegistry.new()


## Cleans up the ConsoleCommandRegistry instance after each test.
func after_each() -> void:
	print("TestConsoleCommandRegistry: Cleaning up ConsoleCommandRegistry instance.")
	_registry = null


## Dummy handler function used for populating test command instances.
func _dummy_handler(_args: PackedStringArray) -> void:
	print("TestConsoleCommandRegistry: Executing dummy command handler.")


## Dummy argument provider function returning test arguments for autocomplete.
func _dummy_arg_provider() -> Array[String]:
	print("TestConsoleCommandRegistry: Providing test argument suggestions.")
	var suggestions: Array[String] = ["god", "noclip", "fly"]
	return suggestions


## Tests registration and retrieval of non-debug commands.
func test_register_and_get_command() -> void:
	print("TestConsoleCommandRegistry: Testing command registration and retrieval.")
	var cmd: ConsoleCommand = ConsoleCommand.new(
		"help", "Shows help message.", Callable(self, "_dummy_handler")
	)
	_registry.register_command(cmd)

	assert_true(_registry.has_command("help"), "Registry should contain 'help' command.")
	assert_true(_registry.has_command("HELP"), "Registry lookup should be case insensitive.")

	var retrieved: ConsoleCommand = _registry.get_command("help")
	assert_not_null(retrieved, "Retrieved command should not be null.")
	if retrieved != null:
		assert_eq(retrieved.name, "help", "Retrieved command name should match.")


## Tests unregistering commands from the registry.
func test_unregister_command() -> void:
	print("TestConsoleCommandRegistry: Testing command unregistration.")
	var cmd: ConsoleCommand = ConsoleCommand.new(
		"clear", "Clears terminal log.", Callable(self, "_dummy_handler")
	)
	_registry.register_command(cmd)
	assert_true(_registry.has_command("clear"), "Command 'clear' should be registered.")

	_registry.unregister_command("CLEAR")
	assert_false(_registry.has_command("clear"), "Command 'clear' should be unregistered.")
	assert_null(_registry.get_command("clear"), "Getting unregistered command should return null.")


## Tests getting valid sorted command list.
func test_get_valid_commands() -> void:
	print("TestConsoleCommandRegistry: Testing get_valid_commands sorting.")
	var cmd1: ConsoleCommand = ConsoleCommand.new(
		"quit", "Exits game.", Callable(self, "_dummy_handler")
	)
	var cmd2: ConsoleCommand = ConsoleCommand.new(
		"alpha", "First command.", Callable(self, "_dummy_handler")
	)
	_registry.register_command(cmd1)
	_registry.register_command(cmd2)

	var valid: Array[String] = _registry.get_valid_commands()
	assert_eq(valid.size(), 2, "Should have 2 registered commands.")
	if valid.size() == 2:
		assert_eq(valid[0], "alpha", "Commands list should be sorted alphabetically.")
		assert_eq(valid[1], "quit", "Commands list should be sorted alphabetically.")


## Tests autocomplete matching for command names.
func test_autocomplete_matches_command_names() -> void:
	print("TestConsoleCommandRegistry: Testing autocomplete matching for command names.")
	var cmd1: ConsoleCommand = ConsoleCommand.new(
		"cheats_god", "Toggle godmode.", Callable(self, "_dummy_handler")
	)
	var cmd2: ConsoleCommand = ConsoleCommand.new(
		"cheats_noclip", "Toggle noclip.", Callable(self, "_dummy_handler")
	)
	var cmd3: ConsoleCommand = ConsoleCommand.new(
		"spawn_item", "Spawn item.", Callable(self, "_dummy_handler")
	)
	_registry.register_command(cmd1)
	_registry.register_command(cmd2)
	_registry.register_command(cmd3)

	var matches: Array[String] = _registry.get_autocomplete_matches("cheat")
	assert_eq(matches.size(), 2, "Should return 2 matching cheat commands.")
	assert_true(matches.has("cheats_god"), "Matches should include 'cheats_god'.")
	assert_true(matches.has("cheats_noclip"), "Matches should include 'cheats_noclip'.")


## Tests autocomplete matching with argument provider.
func test_autocomplete_matches_argument_provider() -> void:
	print("TestConsoleCommandRegistry: Testing autocomplete matching for command arguments.")
	var cmd: ConsoleCommand = ConsoleCommand.new(
		"toggle",
		"Toggle setting.",
		Callable(self, "_dummy_handler"),
		Callable(self, "_dummy_arg_provider")
	)
	_registry.register_command(cmd)

	var matches: Array[String] = _registry.get_autocomplete_matches("toggle go")
	assert_eq(matches.size(), 1, "Should match single argument suggestion 'god'.")
	if matches.size() > 0:
		assert_eq(matches[0], "toggle god", "Autocomplete match should combine command and arg.")
