## Central repository managing registration, validation, and routing of console commands.
class_name ConsoleCommandRegistry
extends RefCounted

## Dictionary storing registered [ConsoleCommand] references keyed by name.
var _commands: Dictionary = {}
## Caches debug authorization state based on build flags.
var _is_debug_allowed: bool = OS.has_feature("debug")


## Adds a command to the catalog if build permissions allow it.
func register_command(cmd: ConsoleCommand) -> void:
	if cmd.is_debug and not _is_debug_allowed:
		return
	print("ConsoleCommandRegistry: Adding command '", cmd.name, "'")
	_commands[cmd.name.to_lower()] = cmd


## Removes a previously registered command by its identifier.
func unregister_command(command_name: String) -> void:
	var clean_name: String = command_name.to_lower()
	if _commands.has(clean_name):
		print("ConsoleCommandRegistry: Unregistering command '", clean_name, "'")
		_commands.erase(clean_name)


## Fetches a registered [ConsoleCommand] by its identifier.
func get_command(command_name: String) -> ConsoleCommand:
	var clean_name: String = command_name.to_lower()
	return _commands.get(clean_name, null)


## Checks if a command identifier is registered and accessible.
func has_command(command_name: String) -> bool:
	return _commands.has(command_name.to_lower())


## Returns a sorted list of all active command identifiers.
func get_valid_commands() -> Array[String]:
	var list: Array[String] = []
	for key: String in _commands.keys():
		list.append(key)
	list.sort()
	return list


## Evaluates partial command and argument strings to return autocomplete candidates.
func get_autocomplete_matches(current_text: String) -> Array[String]:
	print("ConsoleCommandRegistry: Calculating matches for: '", current_text, "'")
	var clean_text: String = current_text.strip_edges(true, false)
	while clean_text.contains("  "):
		clean_text = clean_text.replace("  ", " ")

	var parts: PackedStringArray = clean_text.split(" ")
	var matches: Array[String] = []

	if parts.size() == 1:
		var search: String = parts[0].to_lower()
		var starts: Array[String] = []
		var partials: Array[String] = []
		for cmd_name: String in _commands.keys():
			if cmd_name.begins_with(search):
				starts.append(cmd_name)
			elif cmd_name.contains(search):
				partials.append(cmd_name)
		matches.append_array(starts)
		matches.append_array(partials)
	elif parts.size() >= 2:
		var root_cmd: String = parts[0].to_lower()
		var sub_term: String = parts[1].to_lower()
		var cmd: ConsoleCommand = get_command(root_cmd)
		if cmd and cmd.arg_provider.is_valid():
			var raw_args: Variant = cmd.arg_provider.call()
			if raw_args is Array:
				var starts: Array[String] = []
				var partials: Array[String] = []
				for arg: Variant in raw_args:
					var str_arg: String = str(arg).to_lower()
					var full_match: String = root_cmd + " " + str_arg
					if str_arg.begins_with(sub_term):
						starts.append(full_match)
					elif str_arg.contains(sub_term):
						partials.append(full_match)
				matches.append_array(starts)
				matches.append_array(partials)

	return matches
