## Defines the metadata, execution callback, and argument rules for a console command.
class_name ConsoleCommand
extends RefCounted

## Command identifier entered by the user in lowercase.
var name: String = ""
## Short explanation displayed when listing commands in the terminal.
var description: String = ""
## Execution callback with signature: func(args: PackedStringArray) -> void.
var handler: Callable
## Optional callback or array returning valid argument suggestions for autocomplete.
var arg_provider: Callable
## Restricts command availability strictly to debug builds.
var is_debug: bool = false


## Constructs and populates a new [ConsoleCommand] instance.
func _init(
	p_name: String,
	p_desc: String,
	p_handler: Callable,
	p_arg_provider: Callable = Callable(),
	p_is_debug: bool = false
) -> void:
	print("ConsoleCommand: Registered command '", p_name, "'")
	name = p_name
	description = p_desc
	handler = p_handler
	arg_provider = p_arg_provider
	is_debug = p_is_debug
