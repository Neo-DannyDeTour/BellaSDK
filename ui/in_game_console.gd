## Provides an in-game developer terminal with autocomplete and execution.
#class_name InGameConsole
extends CanvasLayer

## Central registry storing and routing [ConsoleCommand] instances.
var registry: ConsoleCommandRegistry = ConsoleCommandRegistry.new()

## Manages [ConsoleHistory] command submission and navigation.
var history: ConsoleHistory = ConsoleHistory.new(100)

## Holds the list of autocomplete string matches for current input.
var current_matches: Array[String] = []

## Tracks currently selected index within autocomplete matches.
var match_index: int = -1

## Prevents text change events from triggering during match navigation.
var is_navigating_matches: bool = false

## Indicates whether console UI nodes have been fully initialized.
var is_ui_ready: bool = false

## Stores queued messages to display when UI initializes.
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
	"infinite_ammo": false,
	"mono_audio": false,
	"noclip": false,
	"noshake": false,
	"photosensitivity": false,
	"shadows": true,
	"showcolliders": false,
	"showfps": false,
	"showtrigger": false,
	"subtitles": false,
	"togglecrouch": false,
	"togglesprint": false,
	"visionassist": false,
	"wireframe": false,
	"wireframeoverlay": false,
	"wolfvision": false,
	"wolfmode": false,
}

## Bridge context providing output and state access to command modules.
var context: ConsoleContext = null

## Core application and terminal lifecycle command registrar.
var system_commands: ConsoleSystemCommands = null

## Gameplay cheats and entity spawning command registrar.
var cheat_commands: ConsoleCheatCommands = null

## Accessibility, audio, video, and render debug command registrar.
var settings_commands: ConsoleSettingsCommands = null

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Reference to [RichTextLabel] output log display.
@onready var output_log: RichTextLabel = $BackgroundPanel/LayoutContainer/OutputLog

## Reference to [RichTextLabel] suggestion display.
@onready var suggestion_label: RichTextLabel = $BackgroundPanel/LayoutContainer/SuggestionLog

## Reference to [LineEdit] text input bar.
@onready var command_input: LineEdit = $BackgroundPanel/LayoutContainer/CommandInput


# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------
## Lifecycle constructor initializing context and registering command modules.
func _init() -> void:
	print("InGameConsole: _init() registering default commands.")
	context = ConsoleContext.new(self, toggle_states)
	system_commands = ConsoleSystemCommands.new(context)
	cheat_commands = ConsoleCheatCommands.new(context)
	settings_commands = ConsoleSettingsCommands.new(context)
	_register_all_commands()


## Lifecycle initialization binding UI events and signal handlers.
func _ready() -> void:
	print("InGameConsole: _ready() binding UI signals.")
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
		var raw_color: Variant = msg.get("color", Color.WHITE)
		var text_color: Color = Color.WHITE
		if raw_color is Color:
			text_color = raw_color
		elif raw_color is String:
			var color_str: String = raw_color
			text_color = Color(color_str)
		elif raw_color is int:
			var color_int: int = raw_color
			text_color = Color(color_int)

		var raw_text: Variant = msg.get("text", "")
		var text_content: String = str(raw_text)

		output_log.push_color(text_color)
		output_log.add_text(text_content)
		output_log.pop()
		output_log.newline()

	_connect_event_bus()


## Cleanly disconnects global event bus subscriptions when exiting scene tree.
func _exit_tree() -> void:
	if (
		Events.has_signal(&"console_toggle_requested")
		and Events.console_toggle_requested.is_connected(_on_console_toggle_requested)
	):
		Events.console_toggle_requested.disconnect(_on_console_toggle_requested)
	if (
		Events.has_signal(&"noclip_toggled")
		and Events.noclip_toggled.is_connected(_on_external_noclip_toggled)
	):
		Events.noclip_toggled.disconnect(_on_external_noclip_toggled)
	if (
		Events.has_signal(&"infinite_ammo_toggled")
		and Events.infinite_ammo_toggled.is_connected(_on_external_infinite_ammo_toggled)
	):
		Events.infinite_ammo_toggled.disconnect(_on_external_infinite_ammo_toggled)


## Intercepts Escape and UI cancellation inputs to dismiss terminal.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and visible:
		print("InGameConsole: ui_cancel pressed. Closing console.")
		_on_console_toggle_requested()
		get_viewport().set_input_as_handled()


# --------------------------------------
# PUBLIC METHODS & LOGGING
# --------------------------------------
## Appends a formatted message to console output log.
func write(message: String, color: String = "white") -> void:
	print("Console Output: ", message)
	if not is_ui_ready:
		message_history.append({"text": message, "color": color})
		return

	output_log.push_color(Color(color))
	output_log.add_text(message)
	output_log.pop()
	output_log.newline()


## Appends an informational log message to terminal.
func log_info(msg: String) -> void:
	print("InGameConsole logging info: ", msg)
	write(msg, "lightgray")


## Appends a warning message to terminal.
func log_warn(msg: String) -> void:
	print("InGameConsole logging warning: ", msg)
	write("[WARNING] " + msg, "yellow")


## Appends an error message to terminal.
func log_error(msg: String) -> void:
	print("InGameConsole logging error: ", msg)
	write("[ERROR] " + msg, "red")


# --------------------------------------
# BACKWARD COMPATIBILITY FORWARDERS
# --------------------------------------
## Backward compatibility forwarder for infinite ammo toggle command.
func _cmd_infinite_ammo(args: PackedStringArray) -> void:
	if is_instance_valid(cheat_commands):
		cheat_commands._cmd_infinite_ammo(args)


## Backward compatibility forwarder for wolf vision toggle command.
func _cmd_wolfvision(args: PackedStringArray) -> void:
	if is_instance_valid(settings_commands):
		settings_commands._cmd_wolfvision(args)


## Backward compatibility forwarder for boolean toggle parsing.
func _parse_toggle_arg(args: PackedStringArray, current_state: bool, cmd_name: String) -> Variant:
	return context.parse_toggle_arg(args, current_state, cmd_name)


## Backward compatibility forwarder for boolean toggle autocomplete options.
func _get_toggle_options() -> Array[String]:
	return context.get_toggle_options()


# --------------------------------------
# PRIVATE METHODS
# --------------------------------------
## Registers command modules into the central registry.
func _register_all_commands() -> void:
	print("InGameConsole: Registering default commands.")
	system_commands.register_commands(registry)
	settings_commands.register_commands(registry)
	cheat_commands.register_commands(registry)


## Connects console to relevant global event bus signals.
func _connect_event_bus() -> void:
	print("InGameConsole: Connecting event bus signals.")
	if Events.has_signal(&"console_toggle_requested"):
		Events.console_toggle_requested.connect(_on_console_toggle_requested)
	if Events.has_signal(&"noclip_toggled"):
		Events.noclip_toggled.connect(_on_external_noclip_toggled)
	if Events.has_signal(&"infinite_ammo_toggled"):
		Events.infinite_ammo_toggled.connect(_on_external_infinite_ammo_toggled)


## Keeps internal noclip toggle state synchronized with external events.
func _on_external_noclip_toggled(is_active: bool) -> void:
	print("InGameConsole: External noclip state updated -> ", is_active)
	toggle_states["noclip"] = is_active


## Keeps internal infinite ammo toggle state synchronized with external events.
func _on_external_infinite_ammo_toggled(is_active: bool) -> void:
	print("InGameConsole: External infinite ammo state updated -> ", is_active)
	toggle_states["infinite_ammo"] = is_active


## Handles keyboard navigation for command history and autocomplete lists.
func _on_line_edit_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.is_pressed()):
		return

	var key_ev: InputEventKey = event as InputEventKey
	if not key_ev:
		return

	if key_ev.keycode == KEY_UP:
		print("InGameConsole: Key UP pressed.")
		command_input.accept_event()
		if current_matches.is_empty():
			_navigate_history(-1)
		else:
			_navigate_suggestions(-1)

	elif key_ev.keycode == KEY_DOWN:
		print("InGameConsole: Key DOWN pressed.")
		command_input.accept_event()
		if current_matches.is_empty():
			_navigate_history(1)
		else:
			_navigate_suggestions(1)

	elif key_ev.keycode == KEY_TAB:
		print("InGameConsole: Key TAB pressed.")
		command_input.accept_event()
		if not current_matches.is_empty():
			print("InGameConsole: Autocomplete selected match via Tab.")
			var match_text: String = current_matches[maxi(0, match_index)]
			command_input.text = match_text + " "
			command_input.caret_column = command_input.text.length()
			_on_text_changed(command_input.text)

	elif key_ev.keycode in [KEY_ENTER, KEY_KP_ENTER]:
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


## Updates BBCode formatting of autocomplete suggestions panel.
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
	if cmd != null:
		print("InGameConsole: Executing command '", command_name, "'")
		cmd.handler.call(args)
	else:
		var err_msg: String = "Unknown command: '" + command_name + "'. Type 'help' for a list."
		write(err_msg, "red")

	if visible:
		command_input.grab_focus()


## Toggles console visibility, pause state, and mouse mode.
func _on_console_toggle_requested() -> void:
	print("InGameConsole: _on_console_toggle_requested() received.")
	visible = not visible

	if visible:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		command_input.clear()
		_reset_suggestions()
		history.reset_index()
		command_input.call_deferred(&"grab_focus")
		print("InGameConsole: Console UI toggled -> OPENED.")
	else:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("InGameConsole: Console UI toggled -> CLOSED.")

	Events.console_toggled.emit(visible)
