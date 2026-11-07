## Registers and executes core application, scene navigation, and save system commands.
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
		ConsoleCommand.new("restart", "Reloads the active scene.", _cmd_restart, Callable(), true)
	)
	registry.register_command(
		ConsoleCommand.new(
			"gamespeed", "Sets engine time scale factor.", _cmd_gamespeed, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"timescale", "Sets engine time scale factor (alias).", _cmd_gamespeed, Callable(), true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"pause", "Toggles game engine pause state.", _cmd_pause, Callable(), false
		)
	)
	registry.register_command(
		ConsoleCommand.new("uiscale", "Scales the user interface.", _cmd_uiscale)
	)
	registry.register_command(
		ConsoleCommand.new(
			"map", "Loads a level scene from res://levels/.", _cmd_map, _get_level_options, true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"checkpoint",
			"Teleports player to the last activated checkpoint.",
			_cmd_checkpoint,
			Callable(),
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new("save", "Creates a new game save file.", _cmd_save, Callable(), false)
	)
	registry.register_command(
		ConsoleCommand.new(
			"quicksave",
			"Saves state directly to quicksave slot.",
			_cmd_quicksave,
			Callable(),
			false
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"load",
			"Loads an existing save file or lists available saves.",
			_cmd_load,
			_get_load_options,
			false
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"quickload",
			"Loads state directly from quicksave slot.",
			_cmd_quickload,
			Callable(),
			false
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"chapter",
			"Broadcasts narrative chapter title card.",
			_cmd_chapter,
			func() -> Array[String]: return ["1", "2", "3", "4", "5"],
			true
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"bind", "Binds a key to a console command string.", _cmd_bind, Callable(), false
		)
	)
	registry.register_command(
		ConsoleCommand.new("unbind", "Removes a custom keybinding.", _cmd_unbind, Callable(), false)
	)
	registry.register_command(
		ConsoleCommand.new(
			"unbindall", "Removes all custom keybindings.", _cmd_unbindall, Callable(), false
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"bindlist", "Lists all custom keybindings.", _cmd_bindlist, Callable(), false
		)
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


## Loads a level scene by shorthand name or explicit resource path.
func _cmd_map(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_map called with args: ", args)
	if args.is_empty():
		context.write("Usage: map <level_name>", "yellow")
		return

	var input_name: String = args[0].strip_edges()
	var target_path: String = ""

	if input_name.begins_with("res://"):
		target_path = input_name
	else:
		var scn_path: String = "res://levels/" + input_name + ".scn"
		var tscn_path: String = "res://levels/" + input_name + ".tscn"
		var raw_path: String = "res://levels/" + input_name
		if ResourceLoader.exists(scn_path):
			target_path = scn_path
		elif ResourceLoader.exists(tscn_path):
			target_path = tscn_path
		elif ResourceLoader.exists(raw_path):
			target_path = raw_path

	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		context.write("Error: Map '" + input_name + "' not found.", "red")
		return

	context.write("Loading map: " + target_path + "...", "green")
	var tree: SceneTree = context.get_tree()
	if is_instance_valid(tree):
		tree.paused = false

	if is_instance_valid(context.host) and context.host.has_method(&"_on_console_toggle_requested"):
		context.host.call(&"_on_console_toggle_requested")

	var transition_node: Node = (
		tree.root.get_node_or_null("SceneTransition")
		if is_instance_valid(tree) and is_instance_valid(tree.root)
		else null
	)
	if is_instance_valid(transition_node) and transition_node.has_method(&"change_scene_to_file"):
		transition_node.call(&"change_scene_to_file", target_path)
	elif is_instance_valid(tree):
		tree.change_scene_to_file(target_path)


## Teleports the active player to the most recent checkpoint.
func _cmd_checkpoint(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_checkpoint called.")
	if SaveManager.last_checkpoint_pos == Vector3.ZERO:
		context.write("No active checkpoint set.", "yellow")
		return

	var player: Node3D = context.get_player()
	if not is_instance_valid(player):
		context.write("Player node not found in scene tree.", "red")
		return

	var target_pos: Vector3 = SaveManager.last_checkpoint_pos + Vector3(0.0, 0.5, 0.0)
	if Events.has_signal(&"teleport_requested"):
		Events.teleport_requested.emit(target_pos)
	else:
		player.global_position = target_pos
	context.write("Teleported to checkpoint at " + str(target_pos), "green")


## Captures current gameplay state and creates a persistent save file.
func _cmd_save(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_save called with args: ", args)
	var custom_name: String = ""
	if not args.is_empty():
		custom_name = " ".join(args).strip_edges()

	SaveManager.create_save(custom_name)
	var label: String = custom_name if not custom_name.is_empty() else "Auto-timestamp"
	context.write("Game saved successfully (" + label + ").", "green")


## Loads a saved game state or lists available save files.
func _cmd_load(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_load called with args: ", args)
	var saves: Array[Dictionary] = SaveManager.get_all_saves()

	if args.is_empty():
		if saves.is_empty():
			context.write("No saved games found.", "yellow")
			return
		context.write("Available saves (" + str(saves.size()) + "):", "cyan")
		for save_entry: Dictionary in saves:
			var sid: String = str(save_entry.get("id", ""))
			var sname: String = str(save_entry.get("name", ""))
			var stime: String = str(save_entry.get("timestamp", ""))
			context.write("  - [" + sid + "] " + sname + " (" + stime + ")", "white")
		return

	var query: String = args[0].strip_edges()
	var target_base: String = ""

	for save_entry: Dictionary in saves:
		var sid: String = str(save_entry.get("id", ""))
		var sname: String = str(save_entry.get("name", ""))
		var base: String = str(save_entry.get("base_path", ""))
		if query == sid or query == sname or query == base or ("save_" + query) == sid:
			target_base = base
			break

	if target_base.is_empty():
		if FileAccess.file_exists(query + ".dat"):
			target_base = query
		elif FileAccess.file_exists(SaveManager.SAVES_DIR + query + ".dat"):
			target_base = SaveManager.SAVES_DIR + query
		elif FileAccess.file_exists(SaveManager.SAVES_DIR + "save_" + query + ".dat"):
			target_base = SaveManager.SAVES_DIR + "save_" + query

	if target_base.is_empty():
		context.write("Save '" + query + "' not found.", "red")
		return

	context.write("Loading save: " + target_base + "...", "green")
	if is_instance_valid(context.host) and context.host.has_method(&"_on_console_toggle_requested"):
		context.host.call(&"_on_console_toggle_requested")

	SaveManager.load_save_game(target_base)


## Returns autocomplete candidates for available level scene files.
func _get_level_options() -> Array[String]:
	var options: Array[String] = []
	var dir: DirAccess = DirAccess.open("res://levels")
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".tscn") or file_name.ends_with(".scn"):
					options.append(file_name.get_basename())
			file_name = dir.get_next()
	options.sort()
	return options


## Returns autocomplete candidates for available save file IDs.
func _get_load_options() -> Array[String]:
	var options: Array[String] = []
	var saves: Array[Dictionary] = SaveManager.get_all_saves()
	for save_entry: Dictionary in saves:
		var sid: String = str(save_entry.get("id", ""))
		if not sid.is_empty():
			options.append(sid)
	return options


## Broadcasts narrative chapter title card event.
func _cmd_chapter(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_chapter called with args: ", args)
	var ch_num: String = args[0].strip_edges() if not args.is_empty() else "1"
	var ch_name: String = "Chapter " + ch_num
	Events.chapter_triggered.emit(ch_name, Events.ChapterAnimStyle.SIMPLE, 4.0, Color.WHITE)
	context.write("Chapter sequence triggered: " + ch_name, "green")


## Toggles the engine scene tree pause state.
func _cmd_pause(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_pause called.")
	var tree: SceneTree = context.get_tree()
	if not is_instance_valid(tree):
		return
	tree.paused = not tree.paused
	var state_msg: String = "PAUSED" if tree.paused else "UNPAUSED"
	context.write("Engine execution state: " + state_msg, "yellow" if tree.paused else "green")


## Saves gameplay state directly to quicksave slot.
func _cmd_quicksave(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: Executing quicksave.")
	_cmd_save(PackedStringArray(["quicksave"]))


## Loads gameplay state directly from quicksave slot.
func _cmd_quickload(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: Executing quickload.")
	_cmd_load(PackedStringArray(["quicksave"]))


## Binds a physical key name to a console command or prints current binding.
func _cmd_bind(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_bind called with args: ", args)
	if args.is_empty():
		context.write("Usage: bind <key> [command...]", "yellow")
		return

	var key_name: String = args[0].to_lower().strip_edges()
	if args.size() == 1:
		if is_instance_valid(context.host) and context.host.has_method(&"get_keybinds"):
			var raw_binds: Variant = context.host.call(&"get_keybinds")
			if raw_binds is Dictionary:
				var binds_dict: Dictionary = Dictionary(raw_binds)
				if binds_dict.has(key_name):
					context.write(
						'"%s" is bound to: %s' % [key_name, str(binds_dict[key_name])], "cyan"
					)
					return
		context.write('"' + key_name + '" is not bound.', "yellow")
		return

	var cmd_slice: PackedStringArray = args.slice(1)
	var cmd_str: String = " ".join(cmd_slice).strip_edges()
	if cmd_str.begins_with('"') and cmd_str.ends_with('"') and cmd_str.length() >= 2:
		cmd_str = cmd_str.substr(1, cmd_str.length() - 2).strip_edges()

	if is_instance_valid(context.host) and context.host.has_method(&"bind_key"):
		context.host.call(&"bind_key", key_name, cmd_str)
		context.write('Bound "%s" -> "%s"' % [key_name, cmd_str], "green")


## Unbinds a custom command keybinding.
func _cmd_unbind(args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: _cmd_unbind called with args: ", args)
	if args.is_empty():
		context.write("Usage: unbind <key>", "yellow")
		return

	var key_name: String = args[0].to_lower().strip_edges()
	if is_instance_valid(context.host) and context.host.has_method(&"unbind_key"):
		context.host.call(&"unbind_key", key_name)
		context.write('Unbound key "' + key_name + '"', "green")


## Removes all custom keybindings.
func _cmd_unbindall(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: Executing unbindall.")
	if is_instance_valid(context.host) and context.host.has_method(&"unbind_all_keys"):
		context.host.call(&"unbind_all_keys")
		context.write("All custom keybindings cleared.", "yellow")


## Prints all active custom keybindings to terminal log.
func _cmd_bindlist(_args: PackedStringArray) -> void:
	print("ConsoleSystemCommands: Executing bindlist.")
	if not is_instance_valid(context.host) or not context.host.has_method(&"get_keybinds"):
		context.write("No custom keybindings active.", "yellow")
		return

	var raw_binds: Variant = context.host.call(&"get_keybinds")
	if not (raw_binds is Dictionary):
		context.write("No custom keybindings active.", "yellow")
		return

	var binds_dict: Dictionary = Dictionary(raw_binds)
	if binds_dict.is_empty():
		context.write("No custom keybindings currently active.", "yellow")
		return

	context.write("Active keybindings (%d):" % binds_dict.size(), "cyan")
	for k: Variant in binds_dict.keys():
		var key_str: String = str(k)
		context.write("  " + key_str + " : " + str(binds_dict[k]), "white")
