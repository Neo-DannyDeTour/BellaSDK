## Registers and executes core application and terminal system commands.
class_name ConsoleSystemCommands
extends RefCounted

## Context reference providing output logging and scene tree access.
var context: ConsoleContext = null


## Constructs a new [ConsoleSystemCommands] module with the given [param p_context].
func _init(p_context: ConsoleContext) -> void:
	context = p_context


## Registers system commands into the provided [param registry].
func register_commands(registry: ConsoleCommandRegistry) -> void:
	print("ConsoleSystemCommands: Registering system commands.")
	registry.register_command(
		ConsoleCommand.new(
			"help",
			"Lists all available commands.",
			func(_args: PackedStringArray) -> void: _cmd_help(registry)
		)
	)
	registry.register_command(ConsoleCommand.new("clear", "Clears the output log.", _cmd_clear))
	registry.register_command(
		ConsoleCommand.new("quit", "Exits the application immediately.", _cmd_quit)
	)
	registry.register_command(
		ConsoleCommand.new("exit", "Exits the application immediately.", _cmd_quit)
	)
	registry.register_command(
		ConsoleCommand.new("restart", "Reloads the active scene.", _cmd_restart)
	)
	registry.register_command(
		ConsoleCommand.new(
			"gamespeed", "Sets engine time scale factor.", _cmd_gamespeed, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new("uiscale", "Scales the user interface.", _cmd_uiscale)
	)


## Displays all valid registered console commands.
func _cmd_help(registry: ConsoleCommandRegistry) -> void:
	print("ConsoleSystemCommands: _cmd_help called.")
	var valid: String = ", ".join(registry.get_valid_commands())
	context.write("Available commands: " + valid, "green")


## Clears terminal output log and message history buffer.
func _cmd_clear(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_clear called.")
	if is_instance_valid(context.host):
		var log_node: Node = context.host.get_node_or_null(
			"BackgroundPanel/LayoutContainer/OutputLog"
		)
		if log_node is RichTextLabel:
			(log_node as RichTextLabel).clear()
		var msg_hist: Variant = context.host.get("message_history")
		if msg_hist is Array:
			var hist_arr: Array = msg_hist
			hist_arr.clear()
	context.write("Console cleared.", "cyan")


## Terminates the game application immediately.
func _cmd_quit(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: Action Quitting Game")
	context.write("Exiting game...", "red")
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		tree.quit()


## Reloads the active scene tree.
func _cmd_restart(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: Action Reloading Current Scene")
	context.write("Restarting scene...", "yellow")
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		tree.paused = false
		if (
			is_instance_valid(context.host)
			and context.host.has_method(&"_on_console_toggle_requested")
		):
			context.host.call(&"_on_console_toggle_requested")
		tree.reload_current_scene()


## Sets the engine time scale factor.
func _cmd_gamespeed(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: Action Set Gamespeed")
	if not args.is_empty():
		var new_speed: float = args[0].to_float()
		Engine.time_scale = clampf(new_speed, 0.1, 10.0)
		context.write("Time scale set to: " + str(Engine.time_scale), "green")
	else:
		context.write("Usage: gamespeed <value>", "yellow")


## Sets the UI display scale factor.
func _cmd_uiscale(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_uiscale called with args: ", args)
	if not args.is_empty():
		var sc: float = args[0].to_float()
		context.write("UI Scale set to: " + str(sc), "green")
	else:
		context.write("Usage: uiscale <float> (Default: 1.0)", "yellow")
