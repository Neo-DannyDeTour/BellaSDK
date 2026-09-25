## Provides an in-game developer terminal with autocomplete and execution.
#class_name InGameConsole
extends CanvasLayer

## Maps enemy identifier strings to their scene resource file paths.
const ENEMY_SCENE_PATHS: Dictionary[String, String] = {
	"bear_trap": "res://enemies/bear_trap.tscn",
	"beartrap": "res://enemies/bear_trap.tscn",
	"flying_tile": "res://enemies/flying_tile.tscn",
	"flyingtile": "res://enemies/flying_tile.tscn",
	"guardian_pillar": "res://enemies/guardian_pillar.tscn",
	"pillar": "res://enemies/guardian_pillar.tscn",
	"rook_trap": "res://enemies/rook_trap.tscn",
	"rook": "res://enemies/rook_trap.tscn",
	"tentacle": "res://enemies/tentacle_enemy.tscn",
	"tentacle_enemy": "res://enemies/tentacle_enemy.tscn",
	"turret": "res://enemies/turret.tscn"
}

## Reference to [RichTextLabel] output log display.
@onready var output_log: RichTextLabel = $BackgroundPanel/LayoutContainer/OutputLog
## Reference to [RichTextLabel] suggestion display.
@onready var suggestion_label: RichTextLabel = $BackgroundPanel/LayoutContainer/SuggestionLog
## Reference to [LineEdit] text input bar.
@onready var command_input: LineEdit = $BackgroundPanel/LayoutContainer/CommandInput

## Central registry storing and routing [ConsoleCommand] instances.
var registry: ConsoleCommandRegistry = ConsoleCommandRegistry.new()
## Manages [ConsoleHistory] command submission and navigation.
var history: ConsoleHistory = ConsoleHistory.new(100)

## Holds the list of autocomplete string matches for the current input.
var current_matches: Array[String] = []
## Tracks the currently selected index within autocomplete matches.
var match_index: int = -1
## Prevents text change events from triggering during match navigation.
var is_navigating_matches: bool = false
## Indicates whether the console UI nodes have been fully initialized.
var is_ui_ready: bool = false
## Stores queued messages to display when the UI initializes.
var message_history: Array[Dictionary] = []

## Tracks active state of boolean commands to allow single-word toggling.
var toggle_states: Dictionary = {
	"aimassist": false,
	"audio_spatial": true,
	"collision": false,
	"fly": false,
	"fullbright": false,
	"god": false,
	"hidehud": false,
	"highcontrast": false,
	"mono_audio": false,
	"noclip": false,
	"noshake": false,
	"photosensitivity": false,
	"shadows": true,
	"showcolliders": false,
	"showfps": false,
	"subtitles": false,
	"togglecrouch": false,
	"togglesprint": false,
	"visionassist": false,
	"wireframe": false,
	"wireframeoverlay": false,
	"wolfvision": false
}


## Lifecycle constructor initializing and registering base console commands.
func _init() -> void:
	print("InGameConsole: _init() called. Registering default commands.")
	_register_default_commands()


## Lifecycle initialization method binding UI events and signal handlers.
func _ready() -> void:
	print("InGameConsole: _ready() called. Binding UI signals.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	visible = false
	get_tree().paused = false

	command_input.placeholder_text = "Type a command..."
	command_input.gui_input.connect(_on_line_edit_gui_input)
	command_input.text_changed.connect(_on_text_changed)

	output_log.scroll_following = true
	output_log.selection_enabled = true
	output_log.bbcode_enabled = true

	suggestion_label.bbcode_enabled = true
	suggestion_label.fit_content = true
	suggestion_label.visible = false

	is_ui_ready = true

	for msg: Dictionary in message_history:
		output_log.push_color(Color(msg["color"]))
		output_log.add_text(msg["text"])
		output_log.pop()
		output_log.newline()

	_connect_event_bus()


## Connects the console to relevant global event bus signals.
func _connect_event_bus() -> void:
	print("InGameConsole: Connecting event bus signals.")
	if not has_node("/root/Events"):
		return

	var events: Node = get_node("/root/Events")
	if events.has_signal("console_toggle_requested"):
		events.console_toggle_requested.connect(_on_console_toggle_requested)
	if events.has_signal("noclip_toggled"):
		events.noclip_toggled.connect(_on_external_noclip_toggled)


## Keeps internal noclip toggle state synchronized with external events.
func _on_external_noclip_toggled(is_active: bool) -> void:
	print("InGameConsole: External noclip state updated -> ", is_active)
	toggle_states["noclip"] = is_active


## Intercepts Escape and UI cancellation inputs to dismiss the terminal.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and visible:
		print("InGameConsole: ui_cancel pressed. Closing console.")
		_on_console_toggle_requested()
		get_viewport().set_input_as_handled()


## Handles keyboard navigation for command history and autocomplete lists.
func _on_line_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			print("InGameConsole: Key UP pressed.")
			command_input.accept_event()
			if current_matches.is_empty():
				_navigate_history(-1)
			else:
				_navigate_suggestions(-1)

		elif event.keycode == KEY_DOWN:
			print("InGameConsole: Key DOWN pressed.")
			command_input.accept_event()
			if current_matches.is_empty():
				_navigate_history(1)
			else:
				_navigate_suggestions(1)

		elif event.keycode == KEY_TAB:
			print("InGameConsole: Key TAB pressed.")
			command_input.accept_event()
			if not current_matches.is_empty():
				print("InGameConsole: Autocomplete selected match via Tab.")
				var match_text: String = current_matches[maxi(0, match_index)]
				command_input.text = match_text + " "
				command_input.caret_column = command_input.text.length()
				_on_text_changed(command_input.text)

		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			print("InGameConsole: Key ENTER pressed.")
			command_input.accept_event()
			_on_command_submitted(command_input.text)


## Normalizes spaces and refreshes autocomplete suggestions.
func _on_text_changed(new_text: String) -> void:
	if is_navigating_matches:
		return

	if new_text.contains("  "):
		var caret: int = command_input.caret_column
		var collapsed: String = new_text
		while collapsed.contains("  "):
			collapsed = collapsed.replace("  ", " ")
		is_navigating_matches = true
		command_input.text = collapsed
		command_input.caret_column = mini(caret, collapsed.length())
		is_navigating_matches = false
		new_text = collapsed

	var search_text: String = new_text.strip_edges(true, false)
	if search_text.is_empty():
		_reset_suggestions()
		return

	current_matches = registry.get_autocomplete_matches(search_text)
	match_index = -1

	if current_matches.is_empty():
		suggestion_label.visible = false
	else:
		suggestion_label.visible = true
		_update_suggestion_ui()
		print("InGameConsole: Matches found: ", current_matches.size())


## Cycles through autocomplete suggestion candidates.
func _navigate_suggestions(direction: int) -> void:
	print("InGameConsole: Navigating suggestions. Direction: ", direction)
	match_index += direction
	if match_index < 0:
		match_index = current_matches.size() - 1
	elif match_index >= current_matches.size():
		match_index = 0

	is_navigating_matches = true
	command_input.text = current_matches[match_index] + " "
	command_input.caret_column = command_input.text.length()
	is_navigating_matches = false

	_update_suggestion_ui()


## Updates the BBCode formatting of the autocomplete suggestions panel.
func _update_suggestion_ui() -> void:
	print("InGameConsole: Updating suggestion UI elements.")
	var lines: PackedStringArray = []
	lines.resize(current_matches.size())
	for i: int in range(current_matches.size()):
		if i == match_index:
			lines[i] = "[color=yellow]> " + current_matches[i] + "[/color]"
		else:
			lines[i] = "[color=gray]  " + current_matches[i] + "[/color]"

	suggestion_label.text = "\n".join(lines).strip_edges()


## Resets and clears autocomplete match arrays and labels.
func _reset_suggestions() -> void:
	print("InGameConsole: Resetting suggestion state.")
	current_matches.clear()
	match_index = -1
	suggestion_label.visible = false
	suggestion_label.text = ""


## Moves backward or forward through past submitted command history.
func _navigate_history(direction: int) -> void:
	if history.is_empty():
		return
	print("InGameConsole: Navigating history offset: ", direction)
	command_input.text = history.navigate(direction)
	command_input.caret_column = command_input.text.length()


## Appends a formatted message to the console output log.
func write(message: String, color: String = "white") -> void:
	print("Console Output: ", message)
	if not is_ui_ready:
		message_history.append({"text": message, "color": color})
		return

	output_log.push_color(Color(color))
	output_log.add_text(message)
	output_log.pop()
	output_log.newline()


## Appends an informational log message to the terminal.
func log_info(msg: String) -> void:
	print("InGameConsole logging info: ", msg)
	write(msg, "lightgray")


## Appends a warning message to the terminal.
func log_warn(msg: String) -> void:
	print("InGameConsole logging warning: ", msg)
	write("[WARNING] " + msg, "yellow")


## Appends an error message to the terminal.
func log_error(msg: String) -> void:
	print("InGameConsole logging error: ", msg)
	write("[ERROR] " + msg, "red")


## Parses and dispatches user text input upon submission.
func _on_command_submitted(text: String) -> void:
	print("InGameConsole: _on_command_submitted called.")
	command_input.clear()
	_reset_suggestions()

	var clean_text: String = text.strip_edges()
	while clean_text.contains("  "):
		clean_text = clean_text.replace("  ", " ")

	if clean_text.is_empty():
		return

	history.add(clean_text)
	write("> " + clean_text, "darkgray")

	var parts: PackedStringArray = clean_text.split(" ", false)
	if parts.is_empty():
		return

	var command_name: String = parts[0].to_lower()
	var args: PackedStringArray = parts.slice(1)

	var cmd: ConsoleCommand = registry.get_command(command_name)
	if cmd:
		print("InGameConsole: Executing command '", command_name, "'")
		cmd.handler.call(args)
	else:
		var err_msg: String = "Unknown command: '" + command_name + "'. Type 'help' for a list."
		write(err_msg, "red")

	if visible:
		command_input.grab_focus()


## Toggles console visibility, manages pause state, and handles mouse mode.
func _on_console_toggle_requested() -> void:
	print("InGameConsole: _on_console_toggle_requested() received.")
	visible = not visible

	if visible:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		command_input.clear()
		_reset_suggestions()
		history.reset_index()
		command_input.call_deferred("grab_focus")
		print("InGameConsole: Console UI toggled -> OPENED.")
	else:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("InGameConsole: Console UI toggled -> CLOSED.")

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("console_toggled"):
			events.console_toggled.emit(visible)


## Returns autocomplete candidates for colorblind shader modes.
func _get_colorblind_options() -> Array[String]:
	return ["normal", "protanopia", "deuteranopia", "tritanopia", "mono", "achromatopsia", "split"]


## Returns available font identifiers from [GlobalSettings].
func _get_font_options() -> Array[String]:
	if is_instance_valid(GlobalSettings):
		return GlobalSettings.get_font_ids()
	return []


## Returns available screen filter identifiers from [GlobalSettings].
func _get_screen_filter_options() -> Array[String]:
	if is_instance_valid(GlobalSettings):
		return GlobalSettings.get_screen_filter_ids()
	return []


## Returns enemy identifier keys for spawnenemy autocomplete.
func _get_enemy_options() -> Array[String]:
	var keys: Array[String] = []
	for k: String in ENEMY_SCENE_PATHS.keys():
		keys.append(k)
	return keys


## Displays all valid registered console commands.
func _cmd_help(_args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_help called.")
	var valid: String = ", ".join(registry.get_valid_commands())
	write("Available commands: " + valid, "green")


## Clears terminal output log and message history buffer.
func _cmd_clear(_args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_clear called.")
	output_log.clear()
	message_history.clear()
	write("Console cleared.", "cyan")


## Terminates the game application immediately.
func _cmd_quit(_args: PackedStringArray) -> void:
	print("InGameConsole: Action Quitting Game")
	write("Exiting game...", "red")
	get_tree().quit()


## Reloads the active scene tree.
func _cmd_restart(_args: PackedStringArray) -> void:
	print("InGameConsole: Action Reloading Current Scene")
	write("Restarting scene...", "yellow")
	get_tree().paused = false
	_on_console_toggle_requested()
	get_tree().reload_current_scene()


## Registers core terminal commands and sets up autocompletion providers.
func _register_default_commands() -> void:
	print("InGameConsole: Registering default commands.")
	registry.register_command(
		ConsoleCommand.new("help", "Lists all available commands.", _cmd_help)
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
			"colorblind",
			"Applies accessibility colorblind shader.",
			_cmd_colorblind,
			_get_colorblind_options
		)
	)

	registry.register_command(
		ConsoleCommand.new("highcontrast", "Toggles high contrast overlay mode.", _cmd_highcontrast)
	)

	registry.register_command(
		ConsoleCommand.new("screenshake", "Triggers a screenshake event.", _cmd_screenshake)
	)

	registry.register_command(
		ConsoleCommand.new("subtitles", "Toggles dialogue subtitles.", _cmd_subtitles)
	)

	registry.register_command(
		ConsoleCommand.new("mono_audio", "Toggles mono audio downmixing.", _cmd_mono_audio)
	)

	registry.register_command(
		ConsoleCommand.new(
			"photosensitivity", "Toggles photosensitive safety filter.", _cmd_photosensitivity
		)
	)

	registry.register_command(
		ConsoleCommand.new("setfont", "Changes global font style.", _cmd_setfont, _get_font_options)
	)

	registry.register_command(
		ConsoleCommand.new(
			"screenfilter",
			"Applies fullscreen post-processing filter.",
			_cmd_screenfilter,
			_get_screen_filter_options
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"visionassist",
			"Configures vision assist highlights.",
			_cmd_visionassist,
			func() -> Array[String]: return ["mode", "color"]
		)
	)

	registry.register_command(
		ConsoleCommand.new("wolfvision", "Toggles wolf vision mode.", _cmd_wolfvision)
	)

	registry.register_command(
		ConsoleCommand.new("uiscale", "Scales the user interface.", _cmd_uiscale)
	)

	registry.register_command(
		ConsoleCommand.new("fov", "Overrides camera field of view.", _cmd_fov)
	)

	registry.register_command(
		ConsoleCommand.new(
			"shadows",
			"Toggles global shadow casting.",
			_cmd_shadows,
			func() -> Array[String]: return ["on", "off"]
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"vsync",
			"Toggles vertical synchronization mode.",
			_cmd_vsync,
			func() -> Array[String]: return ["on", "off"]
		)
	)

	registry.register_command(
		ConsoleCommand.new("hidehud", "Toggles HUD visibility.", _cmd_hidehud)
	)

	registry.register_command(
		ConsoleCommand.new("gamma", "Adjusts environment tonemap exposure.", _cmd_gamma)
	)

	registry.register_command(
		ConsoleCommand.new("noshake", "Disables camera screenshake triggers.", _cmd_noshake)
	)

	registry.register_command(
		ConsoleCommand.new(
			"togglecrouch", "Switches crouch input between hold and toggle.", _cmd_togglecrouch
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"togglesprint", "Switches sprint input between hold and toggle.", _cmd_togglesprint
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"aimassist",
			"Toggles controller aim friction and magnetism.",
			_cmd_aimassist,
			func() -> Array[String]: return ["on", "off"]
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"textspeed", "Sets dialogue text reveal speed multiplier.", _cmd_textspeed
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"audio_spatial",
			"Toggles positional 3D audio downmixing.",
			_cmd_audio_spatial,
			func() -> Array[String]: return ["on", "off"]
		)
	)

	_register_debug_commands()
	_register_easter_egg_commands()


## Sets the engine time scale factor.
func _cmd_gamespeed(args: PackedStringArray) -> void:
	print("InGameConsole: Action Set Gamespeed")
	if args.size() > 0:
		var new_speed: float = args[0].to_float()
		Engine.time_scale = clampf(new_speed, 0.1, 10.0)
		write("Time scale set to: " + str(Engine.time_scale), "green")
	else:
		write("Usage: gamespeed <value>", "yellow")


## Sets the UI display scale factor.
func _cmd_uiscale(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_uiscale called with args: ", args)
	if args.size() > 0:
		var sc: float = args[0].to_float()
		write("UI Scale set to: " + str(sc), "green")
	else:
		write("Usage: uiscale <float> (Default: 1.0)", "yellow")


## Registers debug-only commands restricted to development builds.
func _register_debug_commands() -> void:
	print("InGameConsole: Registering debug commands.")
	registry.register_command(
		ConsoleCommand.new("die", "Drains player health to zero.", _cmd_die, Callable(), true)
	)

	registry.register_command(
		ConsoleCommand.new(
			"deathscreen",
			"Previews a specific death screen effect.",
			_cmd_deathscreen,
			func() -> Array[String]:
				return ["ecg", "cave", "lava", "static", "glass", "jitter", "burn"],
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"noclip", "Toggles noclip collision mode.", _cmd_noclip, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"fullbright",
			"Toggles fullbright unshaded render mode.",
			_cmd_fullbright,
			Callable(),
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"wireframe", "Toggles wireframe rendering mode.", _cmd_wireframe, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"wireframeoverlay",
			"Toggles green wireframe overlay.",
			_cmd_wireframe_overlay,
			Callable(),
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"collision",
			"Toggles debug collision shape visibility.",
			_cmd_collision,
			Callable(),
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"gamespeed", "Sets the engine time scale factor.", _cmd_gamespeed, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"normals", "Toggles normal buffer debug visualization.", _cmd_normals, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"sethealth", "Sets player health value directly.", _cmd_sethealth, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"showfps",
			"Toggles on-screen performance diagnostic HUD.",
			_cmd_showfps,
			Callable(),
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new("stat_fps", "Alias for showfps command.", _cmd_showfps, Callable(), true)
	)

	registry.register_command(
		ConsoleCommand.new(
			"teleport", "Teleports player to XYZ coordinates.", _cmd_teleport, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"printpos", "Prints current player global coordinates.", _cmd_printpos, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"reloadmap",
			"Reloads current scene tree state immediately.",
			_cmd_reloadmap,
			Callable(),
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"showcolliders",
			"Toggles collision shape debug visualization.",
			_cmd_showcolliders,
			Callable(),
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new("fly", "Toggles flight navigation mode.", _cmd_fly, Callable(), true)
	)

	registry.register_command(
		ConsoleCommand.new("god", "Toggles godmode invulnerability.", _cmd_god, Callable(), true)
	)

	registry.register_command(
		ConsoleCommand.new(
			"give", "Adds an item into player inventory.", _cmd_give, Callable(), true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"give_ammo",
			"Adds specified ammo type into inventory.",
			_cmd_give_ammo,
			func() -> Array[String]: return ["bullet", "energy", "shell", "rocket"],
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"spawnenemy", "Instantiates an enemy entity.", _cmd_spawnenemy, _get_enemy_options, true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"killall",
			"Destroys all active entities in enemies group.",
			_cmd_killall,
			Callable(),
			true
		)
	)

	registry.register_command(
		ConsoleCommand.new(
			"sv_gravity",
			"Overrides global physics gravity vector magnitude.",
			_cmd_sv_gravity,
			Callable(),
			true
		)
	)


## Easter egg handler for sv_cheats command.
func _cmd_sv_cheats(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_sv_cheats called with args: ", args)
	if args.size() > 0 and args[0] == "1":
		var msg: String = "You don't need it. God gave us enough impulse."
		write(msg, "white")
	else:
		write("Usage: sv_cheats 1", "red")


## Easter egg handler for impulse command.
func _cmd_impulse(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_impulse called with args: ", args)
	if args.size() > 0 and args[0] == "101":
		var msg: String = "Bella is a trained professional."
		write(msg, "white")
	else:
		write("Usage: impulse 101", "red")


## Registers easter egg and cheat console commands.
func _register_easter_egg_commands() -> void:
	print("InGameConsole: Registering easter egg commands.")
	registry.register_command(
		ConsoleCommand.new(
			"iddqd", "", func(_a: PackedStringArray) -> void: write("good memory!", "gold")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"idkfa", "", func(_a: PackedStringArray) -> void: write("another classic", "gold")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"kirov", "", func(_a: PackedStringArray) -> void: write("Kirov reporting!", "red")
		)
	)
	registry.register_command(
		ConsoleCommand.new("soyuz", "", func(_a: PackedStringArray) -> void: write("Nerushimuy!"))
	)
	var on_motherlode: Callable = func(_a: PackedStringArray) -> void:
		write("This is a classic get-rich-quick scheme! Arrested!")

	registry.register_command(ConsoleCommand.new("motherlode", "", on_motherlode))
	registry.register_command(
		ConsoleCommand.new(
			"konami",
			"",
			func(_a: PackedStringArray) -> void: write("Fuck Konami and thank god for Jimbo")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"upupdowndownleftrightleftrightbastart",
			"",
			func(_a: PackedStringArray) -> void: write("30 lives to this miss!")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"showmethemoney",
			"",
			func(_a: PackedStringArray) -> void: write("All I have is 10 bucks")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"thereisnocowlevel",
			"",
			func(_a: PackedStringArray) -> void: write("There is none! I swear!")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"whosyourdaddy", "", func(_a: PackedStringArray) -> void: write("DannyDeTour, bitch")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"dnkroz",
			"",
			func(_a: PackedStringArray) -> void: write("You're an inspiration for birth control.")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"hesoyam", "", func(_a: PackedStringArray) -> void: write("What's up, homie?")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"leavemealone",
			"",
			func(_a: PackedStringArray) -> void: write("Tommy! Remember the good old times?!")
		)
	)
	registry.register_command(
		ConsoleCommand.new(
			"thegodfather", "", func(_a: PackedStringArray) -> void: write("do not care")
		)
	)
	registry.register_command(ConsoleCommand.new("sv_cheats", "", _cmd_sv_cheats))
	registry.register_command(ConsoleCommand.new("impulse", "", _cmd_impulse))


## Handles colorblind command execution and dispatches event signals.
func _cmd_colorblind(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_colorblind called with args: ", args)
	if args.is_empty():
		var hint: String = (
			"Usage: colorblind <normal|protanopia|deuteranopia|" + "tritanopia|mono|split>"
		)
		write(hint, "yellow")
		return

	var mode_arg: String = args[0].to_lower()
	var mode_int: int = -1
	match mode_arg:
		"off", "normal":
			mode_int = 0
		"protanopia":
			mode_int = 1
		"deuteranopia":
			mode_int = 2
		"tritanopia":
			mode_int = 3
		"achromatopsia", "mono":
			mode_int = 4
		"split", "all", "debug":
			mode_int = 5
		_:
			var err: String = (
				"Unknown type. Try: normal, protanopia, deuteranopia, " + "tritanopia, mono, split"
			)
			write(err, "red")
			return

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("colorblind_mode_changed"):
			events.colorblind_mode_changed.emit(mode_int)
	write("Colorblind mode set to: " + mode_arg, "green")


## Handles high contrast command toggling.
func _cmd_highcontrast(_args: PackedStringArray) -> void:
	toggle_states["highcontrast"] = not toggle_states["highcontrast"]
	var active: bool = toggle_states["highcontrast"]
	print("InGameConsole: Toggled highcontrast to: ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("high_contrast_toggled"):
			events.high_contrast_toggled.emit(active)
	write("High contrast " + ("activated." if active else "deactivated."), "green")


## Handles screenshake command requests.
func _cmd_screenshake(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_screenshake called with args: ", args)
	if toggle_states.get("noshake", false):
		write("Screenshake suppressed via noshake.", "yellow")
		return

	if args.is_empty():
		var hint: String = "Usage: screenshake <intensity 0.0-16.0> [duration_in_seconds]"
		write(hint, "yellow")
		return

	var amount: float = args[0].to_float()
	var duration: float = 1.0
	if args.size() > 1:
		duration = args[1].to_float()

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("screenshake_requested"):
			events.screenshake_requested.emit(amount, duration)

	var msg: String = (
		"Screenshake: Intensity "
		+ str(clampf(amount, 0.0, 16.0))
		+ ", Duration "
		+ str(duration)
		+ "s"
	)
	write(msg, "green")


## Handles subtitle toggling.
func _cmd_subtitles(_args: PackedStringArray) -> void:
	toggle_states["subtitles"] = not toggle_states["subtitles"]
	var active: bool = toggle_states["subtitles"]
	print("InGameConsole: Toggled subtitles to: ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("subtitles_toggled"):
			events.subtitles_toggled.emit(active)
	write("Subtitles " + ("activated." if active else "deactivated."), "green")


## Handles mono audio downmixing toggling.
func _cmd_mono_audio(_args: PackedStringArray) -> void:
	toggle_states["mono_audio"] = not toggle_states["mono_audio"]
	var active: bool = toggle_states["mono_audio"]
	print("InGameConsole: Toggled mono_audio to: ", active)
	write("Mono audio " + ("activated." if active else "deactivated."), "green")


## Handles photosensitivity mode toggling.
func _cmd_photosensitivity(_args: PackedStringArray) -> void:
	toggle_states["photosensitivity"] = not toggle_states["photosensitivity"]
	var active: bool = toggle_states["photosensitivity"]
	print("InGameConsole: Toggled photosensitivity to: ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("photosensitivity_mode_toggled"):
			events.photosensitivity_mode_toggled.emit(active)
	var status_str: String = "activated." if active else "deactivated."
	write("Photosensitivity mode " + status_str, "green")


## Handles setfont command requests.
func _cmd_setfont(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_setfont called with args: ", args)
	var valid_fonts: Array[String] = []
	if is_instance_valid(GlobalSettings):
		valid_fonts = GlobalSettings.get_font_ids()

	if args.is_empty():
		var hint: String = "Usage: setfont <font_name>\nAvailable: " + ", ".join(valid_fonts)
		write(hint, "yellow")
		return

	var font_choice: String = args[0].to_lower()
	if font_choice in valid_fonts:
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("font_changed"):
				events.font_changed.emit(font_choice)
		write("Global font set to: " + font_choice, "green")
	else:
		write("Unknown font. Available: " + ", ".join(valid_fonts), "red")


## Handles screenfilter command requests.
func _cmd_screenfilter(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_screenfilter called with args: ", args)
	var valid_filters: Array[String] = []
	if is_instance_valid(GlobalSettings):
		valid_filters = GlobalSettings.get_screen_filter_ids()

	if args.is_empty():
		var hint: String = "Usage: screenfilter <type>\nAvailable: " + ", ".join(valid_filters)
		write(hint, "yellow")
		return

	var filter_type: String = args[0].to_lower()
	if filter_type == "off" or filter_type in valid_filters:
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("screen_filter_changed"):
				events.screen_filter_changed.emit(filter_type)
		write("Screen filter: " + filter_type, "green")
	else:
		write("Unknown filter. Available: " + ", ".join(valid_filters), "red")


## Handles visionassist command configurations and toggles.
func _cmd_visionassist(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_visionassist called with args: ", args)
	if args.is_empty():
		toggle_states["visionassist"] = not toggle_states["visionassist"]
		var active: bool = toggle_states["visionassist"]
		print("InGameConsole: Vision assist toggled to: ", active)
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("vision_assist_toggled"):
				events.vision_assist_toggled.emit(active)
		var stat: String = "activated." if active else "deactivated."
		write("Vision assist " + stat, "green")
		return

	var arg1: String = args[0].to_lower()
	if arg1 == "mode" and args.size() == 2:
		var mode_name: String = args[1].to_lower()
		if mode_name in ["black_and_white", "aaa_blue", "pure_black"]:
			if has_node("/root/Events"):
				var events: Node = get_node("/root/Events")
				if events.has_signal("vision_assist_mode_changed"):
					events.vision_assist_mode_changed.emit(mode_name)
			write("Vision Assist mode set to: " + mode_name, "green")
		else:
			var err: String = "Invalid mode. Use 'black_and_white', 'aaa_blue', or 'pure_black'."
			write(err, "yellow")
	elif arg1 == "color" and args.size() == 3:
		var target_group: String = args[1].to_lower()
		var color_name: String = args[2].to_lower()
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("vision_assist_color_changed"):
				events.vision_assist_color_changed.emit(target_group, color_name)
		var msg: String = "Vision Assist: Changed " + target_group + " to " + color_name
		write(msg, "green")
	else:
		var hint: String = (
			"Usage: visionassist OR visionassist mode <mode> OR "
			+ "visionassist color <group> <color>"
		)
		write(hint, "yellow")


## Handles wolfvision toggling.
func _cmd_wolfvision(_args: PackedStringArray) -> void:
	toggle_states["wolfvision"] = not toggle_states["wolfvision"]
	var active: bool = toggle_states["wolfvision"]
	print("InGameConsole: Wolf vision toggled to: ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("wolf_vision_toggled"):
			events.wolf_vision_toggled.emit(active)
	write("Wolf vision " + ("activated." if active else "deactivated."), "green")


## Handles noclip command toggling.
func _cmd_noclip(_args: PackedStringArray) -> void:
	print("InGameConsole: Action toggling noclip.")
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("noclip_ui_button_pressed"):
			events.noclip_ui_button_pressed.emit()
	var active: bool = not toggle_states.get("noclip", false)
	write("Noclip " + ("activated." if active else "deactivated."), "green")


## Handles fullbright render mode toggling.
func _cmd_fullbright(_args: PackedStringArray) -> void:
	toggle_states["fullbright"] = not toggle_states["fullbright"]
	var active: bool = toggle_states["fullbright"]
	print("InGameConsole: Toggled fullbright to: ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("fullbright_toggled"):
			events.fullbright_toggled.emit(active)
	write("Fullbright " + ("activated." if active else "deactivated."), "green")


## Handles wireframe render mode toggling.
func _cmd_wireframe(_args: PackedStringArray) -> void:
	toggle_states["wireframe"] = not toggle_states["wireframe"]
	var active: bool = toggle_states["wireframe"]
	print("InGameConsole: Toggled wireframe to: ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("wireframe_toggled"):
			events.wireframe_toggled.emit(active)
	write("Wireframe " + ("activated." if active else "deactivated."), "green")


## Handles wireframe overlay material toggling.
func _cmd_wireframe_overlay(_args: PackedStringArray) -> void:
	toggle_states["wireframeoverlay"] = not toggle_states["wireframeoverlay"]
	var active: bool = toggle_states["wireframeoverlay"]
	print("InGameConsole: Toggled wireframe overlay to: ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("wireframe_overlay_toggled"):
			events.wireframe_overlay_toggled.emit(active)
	var status_str: String = "activated." if active else "deactivated."
	write("Wireframe overlay " + status_str, "green")


## Handles debug collision shape visibility toggling.
func _cmd_collision(_args: PackedStringArray) -> void:
	toggle_states["collision"] = not toggle_states["collision"]
	var active: bool = toggle_states["collision"]
	print("InGameConsole: Toggled collisions to: ", active)
	get_tree().debug_collisions_hint = active
	var root_node: Node = get_tree().current_scene
	if root_node:
		_refresh_collision_nodes(root_node, active)
	var stat: String = "activated." if active else "deactivated."
	write("Collision shapes " + stat, "green")


## Recursively updates visibility of collision visualizers.
func _refresh_collision_nodes(node: Node, show_collisions: bool) -> void:
	if node is CollisionShape3D or node is RayCast3D or node is ShapeCast3D:
		node.visible = show_collisions
	for child: Node in node.get_children():
		_refresh_collision_nodes(child, show_collisions)


## Handles normal buffer visualization debug mode toggling.
func _cmd_normals(_args: PackedStringArray) -> void:
	print("InGameConsole: Action Toggled Normal View")
	var vp: Viewport = get_viewport()
	if vp.debug_draw == Viewport.DEBUG_DRAW_NORMAL_BUFFER:
		vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		write("Normal view deactivated.", "yellow")
	else:
		vp.debug_draw = Viewport.DEBUG_DRAW_NORMAL_BUFFER
		write("Normal view activated.", "green")


## Resolves the player [HealthComponent] without recursive tree traversal.
func _get_player_health_component(player: Node) -> HealthComponent:
	if not is_instance_valid(player):
		return null

	var comp: Variant = player.get("health_component")
	if is_instance_valid(comp) and comp is HealthComponent:
		return comp as HealthComponent

	var direct_path: Node = player.get_node_or_null("Components/HealthComponent")
	if is_instance_valid(direct_path) and direct_path is HealthComponent:
		return direct_path as HealthComponent

	var shallow_path: Node = player.get_node_or_null("HealthComponent")
	if is_instance_valid(shallow_path) and shallow_path is HealthComponent:
		return shallow_path as HealthComponent

	return null


## Handles die debug command using direct component resolution.
func _cmd_die(_args: PackedStringArray) -> void:
	print("InGameConsole: Action Executing 'die' command.")
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		write("Player node not found in the 'player' group.", "yellow")
		return

	var health_comp: HealthComponent = _get_player_health_component(player)

	if is_instance_valid(health_comp):
		health_comp.current_health = 0
		health_comp.health_changed.emit(0)
		if health_comp.is_player_health and has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("player_health_changed"):
				events.player_health_changed.emit(0)
		health_comp.die()
		write("Player health drained to 0. You died.", "red")
	else:
		write("HealthComponent not found in player's components.", "yellow")


## Handles deathscreen preview command via group and scene lookups.
func _cmd_deathscreen(args: PackedStringArray) -> void:
	print("InGameConsole: Action Executing 'deathscreen' preview.")
	if args.is_empty():
		write("Usage: deathscreen <ecg|cave|lava|static|glass|jitter>", "yellow")
		return

	var screen_name: String = args[0].to_lower()
	var ds: DeathScreen = null
	var ds_node: Node = get_tree().get_first_node_in_group("death_screen")

	if is_instance_valid(ds_node) and ds_node is DeathScreen:
		ds = ds_node as DeathScreen
	else:
		var curr_scene: Node = get_tree().current_scene
		if is_instance_valid(curr_scene):
			var direct_ui: Node = curr_scene.get_node_or_null("UI/DeathScreen")
			if direct_ui is DeathScreen:
				ds = direct_ui as DeathScreen

	if not is_instance_valid(ds):
		write("DeathScreen node not found in scene tree.", "red")
		return

	var chosen_effect: DeathScreen.EffectType = DeathScreen.EffectType.ECG
	match screen_name:
		"ecg":
			chosen_effect = DeathScreen.EffectType.ECG
		"lava":
			chosen_effect = DeathScreen.EffectType.LAVA
		"cave":
			chosen_effect = DeathScreen.EffectType.CAVE_TUNNEL
		"static":
			chosen_effect = DeathScreen.EffectType.TV_STATIC
		"glass":
			chosen_effect = DeathScreen.EffectType.GLASS
		"jitter":
			chosen_effect = DeathScreen.EffectType.JITTER
		"burn":
			chosen_effect = DeathScreen.EffectType.BURN
		_:
			var err: String = "Unknown screen. Available: ecg, cave, lava, static, glass, jitter, burn"
			write(err, "red")
			return

	_on_console_toggle_requested()
	ds.play_death_preview(chosen_effect)
	write("Previewing death screen: " + screen_name.to_upper(), "green")


## Handles sethealth debug command with input validation.
func _cmd_sethealth(args: PackedStringArray) -> void:
	print("InGameConsole: Action Executing 'sethealth' command.")
	if args.is_empty() or not args[0].is_valid_int():
		write("Usage: sethealth <value 0-300>", "yellow")
		return

	var health_val: int = clampi(args[0].to_int(), 0, 300)
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		write("Player node not found in the 'player' group.", "yellow")
		return

	var health_comp: HealthComponent = _get_player_health_component(player)

	if is_instance_valid(health_comp):
		health_comp.current_health = health_val
		health_comp.health_changed.emit(health_comp.current_health)

		if health_comp.is_player_health and has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("player_health_changed"):
				events.player_health_changed.emit(health_comp.current_health)

		if health_comp.current_health == 0:
			health_comp.die()

		write("Player health forcefully set to: " + str(health_val), "green")
	else:
		write("HealthComponent not found on the player entity.", "yellow")


## Toggles the on-screen FPS and performance diagnostic HUD.
func _cmd_showfps(_args: PackedStringArray) -> void:
	toggle_states["showfps"] = not toggle_states["showfps"]
	var active: bool = toggle_states["showfps"]
	print("InGameConsole: Toggled showfps -> ", active)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("metrics_panel_toggle_requested"):
			events.metrics_panel_toggle_requested.emit()
	write("FPS monitor " + ("enabled." if active else "disabled."), "green")


## Teleports the player entity to target coordinates.
func _cmd_teleport(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_teleport called with args: ", args)
	if args.size() < 3:
		write("Usage: teleport <x> <y> <z>", "yellow")
		return

	var target_pos: Vector3 = Vector3(args[0].to_float(), args[1].to_float(), args[2].to_float())
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		write("Player entity not found in 'player' group.", "red")
		return

	if player.has_method("teleport_to"):
		player.call("teleport_to", target_pos, 0.0)
	elif player is Node3D:
		(player as Node3D).global_position = target_pos

	write("Teleported player to: " + str(target_pos), "green")


## Outputs the player's current global position coordinates.
func _cmd_printpos(_args: PackedStringArray) -> void:
	print("InGameConsole: Executing printpos.")
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not is_instance_valid(player):
		write("Player entity not found.", "red")
		return

	var pos: Vector3 = player.global_position
	var formatted_pos: String = "%.2f, %.2f, %.2f" % [pos.x, pos.y, pos.z]
	print("Player Global Position: ", formatted_pos)
	write("Position: " + formatted_pos, "cyan")


## Resets the current scene state without restarting the engine.
func _cmd_reloadmap(_args: PackedStringArray) -> void:
	print("InGameConsole: Executing reloadmap.")
	write("Reloading map...", "yellow")
	get_tree().paused = false
	_on_console_toggle_requested()
	get_tree().reload_current_scene()


## Toggles debug collision shape rendering in the tree.
func _cmd_showcolliders(args: PackedStringArray) -> void:
	print("InGameConsole: Action toggling showcolliders.")
	_cmd_collision(args)


## Toggles gravity-free flight navigation mode.
func _cmd_fly(_args: PackedStringArray) -> void:
	toggle_states["fly"] = not toggle_states["fly"]
	var active: bool = toggle_states["fly"]
	print("InGameConsole: Toggled fly mode -> ", active)

	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		var loco: Node = player.get("locomotion_component")
		if is_instance_valid(loco):
			var def_grav: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
			loco.set("gravity", 0.0 if active else def_grav)
			print("InGameConsole: PlayerLocomotionComponent gravity -> ", loco.get("gravity"))

	write("Fly mode " + ("activated." if active else "deactivated."), "green")


## Toggles godmode invulnerability on the active player.
func _cmd_god(_args: PackedStringArray) -> void:
	toggle_states["god"] = not toggle_states["god"]
	var active: bool = toggle_states["god"]
	print("InGameConsole: Toggled godmode -> ", active)

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		events.set("is_godmode", active)
		if events.has_signal("godmode_toggled"):
			events.godmode_toggled.emit(active)

	write("Godmode " + ("activated." if active else "deactivated."), "green")


## Grants an item directly to the player inventory.
func _cmd_give(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_give called with args: ", args)
	if args.is_empty():
		write("Usage: give <item_name> [amount]", "yellow")
		return

	var item_name: String = args[0].to_lower()
	var amount: int = args[1].to_int() if args.size() > 1 else 1
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("inventory_item_given"):
			events.inventory_item_given.emit(item_name, amount)

	write("Given %d x '%s' to player." % [amount, item_name], "green")


## Grants ammunition directly to player reserves.
func _cmd_give_ammo(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_give_ammo called with args: ", args)
	if args.is_empty():
		write("Usage: give_ammo <ammo_type> [amount]", "yellow")
		return

	var ammo_type: String = args[0].to_lower()
	var amount: int = args[1].to_int() if args.size() > 1 else 30
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("ammo_collected"):
			events.ammo_collected.emit(StringName(ammo_type), amount)

	write("Given %d x '%s' ammo." % [amount, ammo_type], "green")


## Spawns an enemy instance in front of player orientation.
func _cmd_spawnenemy(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_spawnenemy called with args: ", args)
	if args.is_empty():
		var valid_list: PackedStringArray = PackedStringArray(ENEMY_SCENE_PATHS.keys())
		var msg: String = "Usage: spawnenemy <name>\nValid: " + ", ".join(valid_list)
		write(msg, "yellow")
		return

	var enemy_key: String = args[0].to_lower()
	if not ENEMY_SCENE_PATHS.has(enemy_key):
		write("Unknown enemy: '" + enemy_key + "'.", "red")
		return

	var scene_path: String = ENEMY_SCENE_PATHS[enemy_key]
	if not ResourceLoader.exists(scene_path):
		write("Scene file not found: " + scene_path, "red")
		return

	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if not packed_scene:
		write("Failed to load scene: " + scene_path, "red")
		return

	var enemy_node: Node = packed_scene.instantiate()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if is_instance_valid(player) and enemy_node is Node3D:
		var spawn_offset: Vector3 = player.global_transform.basis.z * 3.0
		var spawn_pos: Vector3 = player.global_position - spawn_offset
		(enemy_node as Node3D).global_position = spawn_pos

	get_tree().current_scene.add_child(enemy_node)
	write("Spawned enemy '" + enemy_key + "' successfully.", "green")


## Destroys active enemy entities without deep recursion.
func _cmd_killall(_args: PackedStringArray) -> void:
	print("InGameConsole: Executing killall.")
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	var count: int = 0

	for enemy: Node in enemies:
		if not is_instance_valid(enemy) or enemy.is_in_group("player"):
			continue

		var hc: Variant = enemy.get("health_component")
		if not is_instance_valid(hc):
			hc = enemy.get_node_or_null("HealthComponent")
		if not is_instance_valid(hc):
			hc = enemy.get_node_or_null("Components/HealthComponent")

		if is_instance_valid(hc) and hc.has_method("take_damage"):
			hc.call("take_damage", 99999)
			count += 1
		elif enemy.has_method("die"):
			enemy.call("die")
			count += 1
		elif enemy is Node3D:
			enemy.queue_free()
			count += 1

	write("Destroyed %d active entities." % count, "green")


## Recursively locates and eliminates hostile entities with health components.
func _kill_enemies_recursive(node: Node) -> int:
	var destroyed: int = 0
	if node.is_in_group("player"):
		return 0

	if node is HealthComponent and not (node as HealthComponent).is_player_health:
		(node as HealthComponent).take_damage(99999)
		destroyed += 1

	for child: Node in node.get_children():
		destroyed += _kill_enemies_recursive(child)
	return destroyed


## Overrides the global physics gravity magnitude.
func _cmd_sv_gravity(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_sv_gravity called with args: ", args)
	if args.is_empty():
		var cur_g: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
		var msg: String = "Current gravity: " + str(cur_g) + ". Usage: sv_gravity <val>"
		write(msg, "yellow")
		return

	var grav: float = args[0].to_float()
	PhysicsServer3D.area_set_param(
		get_viewport().find_world_3d().space, PhysicsServer3D.AREA_PARAM_GRAVITY, grav
	)
	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		var loco: Node = player.get("locomotion_component")
		if is_instance_valid(loco):
			loco.set("gravity", grav)

	write("Global physics gravity updated to: " + str(grav), "green")


## Updates the camera field of view setting.
func _cmd_fov(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_fov called with args: ", args)
	if args.is_empty():
		write("Usage: fov <degrees 30-130>", "yellow")
		return

	var fov_val: float = clampf(args[0].to_float(), 30.0, 130.0)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Settings", "base_fov", fov_val)

	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "camera_controller" in player:
		var cam_ctrl: Node = player.get("camera_controller")
		if is_instance_valid(cam_ctrl):
			cam_ctrl.set("base_fov", fov_val)
			cam_ctrl.set("target_fov", fov_val)
			var cam: Camera3D = cam_ctrl.get("camera") as Camera3D
			if is_instance_valid(cam):
				cam.fov = fov_val

	write("Field of view set to: " + str(fov_val), "green")


## Configures runtime shadow rendering across 3D lights.
func _cmd_shadows(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_shadows called with args: ", args)
	var active: bool = not toggle_states["shadows"]
	if not args.is_empty():
		active = args[0].to_lower() == "on" or args[0] == "1"

	toggle_states["shadows"] = active
	var root_scene: Node = get_tree().current_scene
	if is_instance_valid(root_scene):
		_toggle_light_shadows_recursive(root_scene, active)

	write("Dynamic shadows " + ("enabled." if active else "disabled."), "green")


## Recursively updates shadow casting on all active Light3D instances.
func _toggle_light_shadows_recursive(node: Node, active: bool) -> void:
	if node is Light3D:
		(node as Light3D).shadow_enabled = active
	for child: Node in node.get_children():
		_toggle_light_shadows_recursive(child, active)


## Configures runtime V-Sync display mode.
func _cmd_vsync(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_vsync called with args: ", args)
	var is_disabled: bool = DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED
	var enable: bool = is_disabled
	if not args.is_empty():
		enable = args[0].to_lower() == "on" or args[0] == "1"

	var mode: DisplayServer.VSyncMode = (
		DisplayServer.VSYNC_ENABLED if enable else DisplayServer.VSYNC_DISABLED
	)
	DisplayServer.window_set_vsync_mode(mode)
	write("V-Sync " + ("enabled." if enable else "disabled."), "green")


## Toggles player HUD layer node visibility.
func _cmd_hidehud(_args: PackedStringArray) -> void:
	toggle_states["hidehud"] = not toggle_states["hidehud"]
	var is_hidden: bool = toggle_states["hidehud"]
	print("InGameConsole: Toggled hidehud -> ", is_hidden)

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("ui_visibility_toggle_requested"):
			events.ui_visibility_toggle_requested.emit()

	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "ui_controller" in player:
		var ui: CanvasLayer = player.get("ui_controller") as CanvasLayer
		if is_instance_valid(ui):
			ui.visible = not is_hidden

	write("HUD " + ("hidden." if is_hidden else "revealed."), "green")


## Sets global environment tonemap exposure value without root recursion.
func _cmd_gamma(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_gamma called with args: ", args)
	if args.is_empty():
		write("Usage: gamma <value 0.1-3.0>", "yellow")
		return

	var gamma_val: float = clampf(args[0].to_float(), 0.1, 3.0)
	var env: Environment = null

	var env_node: Node = get_tree().get_first_node_in_group("world_environment")
	if is_instance_valid(env_node) and env_node is WorldEnvironment:
		env = (env_node as WorldEnvironment).environment
	else:
		var curr_scene: Node = get_tree().current_scene
		if is_instance_valid(curr_scene):
			var direct_env: Node = curr_scene.get_node_or_null("WorldEnvironment")
			if direct_env is WorldEnvironment:
				env = (direct_env as WorldEnvironment).environment

	if env == null:
		var world_3d: World3D = get_viewport().find_world_3d()
		if is_instance_valid(world_3d):
			env = world_3d.environment

	if is_instance_valid(env):
		env.tonemap_exposure = gamma_val
		write("Tonemap exposure set to: " + str(gamma_val), "green")
	else:
		write("Active Environment resource not found.", "yellow")


## Prevents screenshake events from firing on the event bus.
func _cmd_noshake(_args: PackedStringArray) -> void:
	toggle_states["noshake"] = not toggle_states["noshake"]
	var active: bool = toggle_states["noshake"]
	print("InGameConsole: Toggled noshake -> ", active)
	write("Screenshake suppression " + ("enabled." if active else "disabled."), "green")


## Toggles crouch input behavior between hold and toggle.
func _cmd_togglecrouch(_args: PackedStringArray) -> void:
	toggle_states["togglecrouch"] = not toggle_states["togglecrouch"]
	var active: bool = toggle_states["togglecrouch"]
	print("InGameConsole: Toggled togglecrouch -> ", active)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Controls", "toggle_crouch", active)
	var stat: String = "enabled." if active else "disabled (hold)."
	write("Toggle crouch " + stat, "green")


## Toggles sprint input behavior between hold and toggle.
func _cmd_togglesprint(_args: PackedStringArray) -> void:
	toggle_states["togglesprint"] = not toggle_states["togglesprint"]
	var active: bool = toggle_states["togglesprint"]
	print("InGameConsole: Toggled togglesprint -> ", active)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Controls", "toggle_sprint", active)
	var stat: String = "enabled." if active else "disabled (hold)."
	write("Toggle sprint " + stat, "green")


## Toggles controller aim friction and magnetism assists.
func _cmd_aimassist(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_aimassist called with args: ", args)
	var active: bool = not toggle_states["aimassist"]
	if not args.is_empty():
		active = args[0].to_lower() == "on" or args[0] == "1"

	toggle_states["aimassist"] = active
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Accessibility", "aim_assist", active)
	write("Aim assist " + ("enabled." if active else "disabled."), "green")


## Sets subtitle text reveal speed rate.
func _cmd_textspeed(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_textspeed called with args: ", args)
	if args.is_empty():
		write("Usage: textspeed <multiplier 0.5-3.0>", "yellow")
		return

	var speed_val: float = clampf(args[0].to_float(), 0.5, 3.0)
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Accessibility", "text_speed", speed_val)
	write("Text speed multiplier set to: " + str(speed_val), "green")


## Configures 3D spatial audio downmixing to stereo 2D.
func _cmd_audio_spatial(args: PackedStringArray) -> void:
	print("InGameConsole: _cmd_audio_spatial called with args: ", args)
	var active: bool = not toggle_states["audio_spatial"]
	if not args.is_empty():
		active = args[0].to_lower() == "on" or args[0] == "1"

	toggle_states["audio_spatial"] = active
	if is_instance_valid(GlobalSettings):
		GlobalSettings.save_setting("Audio", "spatial_audio", active)
	var stat: String = "enabled." if active else "disabled (2D stereo)."
	write("Spatial 3D audio " + stat, "green")
