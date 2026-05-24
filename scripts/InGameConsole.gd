extends CanvasLayer

# Save this as InGameConsole.gd
# IMPORTANT: Go to Project -> Project Settings -> Autoload, and add this script with the Node Name "Console".

var output_log: RichTextLabel
var panel: PanelContainer
var vbox: VBoxContainer
var command_input: LineEdit

# ACCESSIBILITY
var colorblind_rect: ColorRect
var high_contrast_rect: ColorRect

# --- Message Cache & UI State ---
var message_history: Array[Dictionary] = []
var is_ui_ready: bool = false

# --- Command History & Autocomplete ---
var typed_history: Array[String] = []
var history_index: int = 0

# A list of all available root commands for Tab Autocomplete
var valid_commands: Array[String] = [
	"help",
	"clear",
	"quit",
	"noclip",
	"iddqd",
	"idkfa",
	"kirov",
	"sv_cheats",
	"soyuz",
	"motherlode",
	"konami",
	"upupdowndownleftrightleftrightbastart",
	"showmethemoney",
	"thereisnocowlevel",
	"whosyourdaddy",
	"dnkroz",
	"hesoyam",
	"leavemealone",
	"impulse",
	"thegodfather",
	"colorblind",
	"gamespeed",
	"highcontrast",
	"screenshake",
	"subtitles",
	"mono_audio",
	"uiscale",
	"photosensitivity",
	"setfont"
]

# Sub-arguments for autocomplete
var valid_colorblind_args: Array[String] = [
	"normal", "protanopia", "deuteranopia", "tritanopia", "mono", "achromatopsia"
]
var valid_font_args: Array[String] = ["default", "dyslexic", "papyrus", "comic"]
var valid_on_off_args: Array[String] = ["on", "off"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	visible = false

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -450
	add_child(panel)

	vbox = VBoxContainer.new()
	panel.add_child(vbox)

	output_log = RichTextLabel.new()
	output_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output_log.scroll_following = true
	output_log.selection_enabled = true
	output_log.bbcode_enabled = true
	output_log.add_theme_constant_override("margin_left", 10)
	output_log.add_theme_constant_override("margin_top", 10)
	vbox.add_child(output_log)

	command_input = LineEdit.new()
	command_input.placeholder_text = "Type a command..."
	command_input.text_submitted.connect(_on_command_submitted)

	# Catch Tab and Arrow keys
	command_input.gui_input.connect(_on_line_edit_gui_input)
	vbox.add_child(command_input)

	is_ui_ready = true

	# Dump any messages that were sent during game startup
	for msg: Dictionary in message_history:
		output_log.append_text("[color=" + msg["color"] + "]" + msg["text"] + "[/color]\n")

	# --- Colorblind Filter Setup ---
	var filter_layer := CanvasLayer.new()
	filter_layer.layer = 127
	add_child(filter_layer)

	colorblind_rect = ColorRect.new()
	colorblind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	colorblind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/colorblind.gdshader")
	colorblind_rect.material = mat
	filter_layer.add_child(colorblind_rect)

	# --- High Contrast Setup ---
	high_contrast_rect = ColorRect.new()
	high_contrast_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	high_contrast_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	high_contrast_rect.visible = false

	var hc_mat := ShaderMaterial.new()
	hc_mat.shader = load("res://assets/shaders/high_contrast.gdshader")
	high_contrast_rect.material = hc_mat
	filter_layer.add_child(high_contrast_rect)

	write("Developer console initialized. Press ~ to toggle.", "cyan")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("console"):
		visible = !visible

		if visible:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			command_input.grab_focus()
			command_input.clear()
			history_index = typed_history.size()
		else:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

		get_viewport().set_input_as_handled()


# --- Catch Tab and Arrows safely inside the LineEdit ---
func _on_line_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_UP, KEY_PAGEUP]:
			command_input.accept_event()
			_navigate_history(-1)
		elif event.keycode in [KEY_DOWN, KEY_PAGEDOWN]:
			command_input.accept_event()
			_navigate_history(1)
		elif event.keycode == KEY_TAB:
			command_input.accept_event()
			_attempt_autocomplete()


# --- History Navigation Logic ---
func _navigate_history(direction: int) -> void:
	if typed_history.is_empty():
		return

	history_index += direction
	history_index = clamp(history_index, 0, typed_history.size())

	if history_index == typed_history.size():
		command_input.text = ""
	else:
		command_input.text = typed_history[history_index]
		command_input.caret_column = command_input.text.length()


# --- Autocomplete Logic ---
func _attempt_autocomplete() -> void:
	# Use lstrip instead of strip_edges so trailing spaces trigger argument autocompletion
	var current_text := command_input.text.lstrip(" ")
	if current_text == "":
		return

	# In Godot 4, split retains empty strings by default.
	# E.g., "colorblind " becomes ["colorblind", ""] allowing empty arg matching.
	var parts := current_text.split(" ")

	# Autocomplete Main Command
	if parts.size() == 1:
		var search_term := parts[0].to_lower()
		var matches := []

		for cmd: String in valid_commands:
			if cmd.begins_with(search_term):
				matches.append(cmd)

		if matches.size() == 1:
			command_input.text = matches[0] + " "
			command_input.caret_column = command_input.text.length()
		elif matches.size() > 1:
			write("Matches: " + ", ".join(matches), "yellow")

	# Autocomplete Sub-commands
	elif parts.size() == 2:
		var main_cmd := parts[0].to_lower()
		var sub_term := parts[1].to_lower()
		var arg_matches := []

		if main_cmd == "colorblind":
			for arg: String in valid_colorblind_args:
				if arg.begins_with(sub_term):
					arg_matches.append(arg)

		elif main_cmd == "setfont":
			for arg: String in valid_font_args:
				if arg.begins_with(sub_term):
					arg_matches.append(arg)

		elif main_cmd in ["subtitles", "mono_audio", "photosensitivity", "highcontrast"]:
			for arg: String in valid_on_off_args:
				if arg.begins_with(sub_term):
					arg_matches.append(arg)

		if arg_matches.size() == 1:
			command_input.text = main_cmd + " " + arg_matches[0] + " "
			command_input.caret_column = command_input.text.length()
		elif arg_matches.size() > 1:
			write("Matches: " + ", ".join(arg_matches), "yellow")


# --- LOGGING ---
func write(message: String, color: String = "white") -> void:
	print(message)

	message_history.append({"text": message, "color": color})

	if is_ui_ready and output_log:
		output_log.append_text("[color=" + color + "]" + message + "[/color]\n")


func log_info(msg: String) -> void:
	write(msg, "lightgray")


func log_warn(msg: String) -> void:
	write("[WARNING] " + msg, "yellow")


func log_error(msg: String) -> void:
	write("[ERROR] " + msg, "red")


# --- COMMAND PARSING ---


func _on_command_submitted(text: String) -> void:
	command_input.clear()

	var clean_text := text.strip_edges()

	if clean_text != "":
		if typed_history.is_empty() or typed_history.back() != clean_text:
			typed_history.append(clean_text)
		history_index = typed_history.size()

		write("> " + clean_text, "darkgray")

		var parts := clean_text.split(" ")
		var command := parts[0].to_lower()
		var args := parts.slice(1)

		_process_command(command, args)

	await get_tree().process_frame

	if visible:
		command_input.grab_focus()


func _process_command(cmd: String, _args: PackedStringArray) -> void:
	match cmd:
		"help":
			# Dynamically joins the valid_commands array so you never have to manually update this list
			write("Available commands: " + ", ".join(valid_commands), "green")
		"clear":
			output_log.clear()
			message_history.clear()
			write("Console cleared.", "cyan")
		"quit":
			write("Exiting game...", "red")
			get_tree().quit()
		"noclip":
			Events.noclip_ui_button_pressed.emit()
			write("Toggled Noclip.", "yellow")
		"iddqd":
			write("good memory!", "gold")
		"idkfa":
			write("another classic", "gold")
		"kirov":
			write("Kirov reporting!", "red")
		"sv_cheats":
			if _args.size() > 0 and _args[0] == "1":
				write("You don't need it. God has given us enough impulse this time", "white")
			else:
				write("Usage: sv_cheats 1", "red")
		"soyuz":
			write("Nerushimuy!")
		"motherlode":
			write("This is a classic get-rich-quick scheme! You're being arrested!")
		"konami":
			write("Fuck Konami and thank god for Jimbo")
		"upupdowndownleftrightleftrightbastart":
			write("30 lives to this miss!")
		"showmethemoney":
			write("All I have is 10 bucks")
		"thereisnocowlevel":
			write("There is none! I swear!")
		"whosyourdaddy":
			write("DannyDeTour, bitch")
		"dnkroz":
			write("You're an inspiration for birth control.")
		"hesoyam":
			write("What's up, homie?")
		"leavemealone":
			write("Tommy! Remember the good old times?!")
		"impulse":
			if _args.size() > 0 and _args[0] == "101":
				write(
					"Bella doesn't need to hear about safety preconscious. She's a highly trained professional",
					"white"
				)
			else:
				write("Usage: sv_cheats 1", "red")
		"thegodfather":
			write("do not care")
		"colorblind":
			if _args.size() > 0:
				var mode := _args[0].to_lower()
				var material := colorblind_rect.material as ShaderMaterial
				match mode:
					"off", "normal":
						material.set_shader_parameter("mode", 0)
						write("Colorblind filter disabled.", "green")
					"protanopia":
						material.set_shader_parameter("mode", 1)
						write("Protanopia (Red-Blind) filter enabled.", "green")
					"deuteranopia":
						material.set_shader_parameter("mode", 2)
						write("Deuteranopia (Green-Blind) filter enabled.", "green")
					"tritanopia":
						material.set_shader_parameter("mode", 3)
						write("Tritanopia (Blue-Blind) filter enabled.", "green")
					"achromatopsia", "mono":
						material.set_shader_parameter("mode", 4)
						write("Achromatopsia (Monochrome) filter enabled.", "green")
					_:
						write(
							"Unknown type. Available: normal, protanopia, deuteranopia, tritanopia, mono, achromatopsia",
							"red"
						)
			else:
				write("Usage: colorblind <type>", "red")
				write(
					"Types: normal, protanopia, deuteranopia, tritanopia, mono, achromatopsia",
					"yellow"
				)
		"gamespeed":
			if _args.size() > 0:
				var new_speed := _args[0].to_float()
				Engine.time_scale = clamp(new_speed, 0.1, 10.0)
				write("Time scale set to: " + str(Engine.time_scale), "green")
			else:
				write("Usage: gamespeed <value> (e.g., 0.7 for 70% speed)", "yellow")
		"highcontrast":
			if _args.size() > 0:
				var active := _args[0].to_lower() == "on"
				Events.high_contrast_toggled.emit(active)
				write("High contrast mode: " + ("Enabled" if active else "Disabled"), "green")
			else:
				write("Usage: highcontrast <on/off>", "yellow")
		"screenshake":
			if _args.size() > 0:
				var amount := _args[0].to_float()
				# Example: GlobalSettings.shake_multiplier = clamp(amount, 0.0, 1.0)
				write("Screenshake multiplier set to: " + str(clamp(amount, 0.0, 1.0)), "green")
			else:
				write("Usage: screenshake <0.0 to 1.0>", "yellow")
		"subtitles":
			if _args.size() > 0:
				var active := _args[0].to_lower() == "on"
				Events.subtitles_toggled.emit(active)
				write("Subtitles: " + ("ON" if active else "OFF"), "green")
			else:
				write("Usage: subtitles <on/off>", "yellow")
		"mono_audio":
			if _args.size() > 0:
				var active := _args[0].to_lower() == "on"
				write("Mono Audio: " + ("ON" if active else "OFF"), "green")
			else:
				write("Usage: mono_audio <on/off>", "yellow")
		"uiscale":
			if _args.size() > 0:
				var scale_val := _args[0].to_float()
				write("UI Scale set to: " + str(scale_val), "green")
			else:
				write("Usage: uiscale <float> (Default is usually 1.0)", "yellow")
		"photosensitivity":
			if _args.size() > 0:
				var active := _args[0].to_lower() == "on"
				Events.photosensitivity_mode_toggled.emit(active)
				write("Photosensitivity safe mode: " + ("ON" if active else "OFF"), "green")
			else:
				write("Usage: photosensitivity <on/off>", "yellow")
		"setfont":
			if _args.size() > 0:
				var font_choice := _args[0].to_lower()

				if font_choice in valid_font_args:
					Events.font_changed.emit(font_choice)
					write("Global font set to: " + font_choice, "green")
				else:
					write("Unknown font. Available: default, dyslexic, papyrus, comic", "red")
			else:
				write("Usage: setfont <font_name>", "yellow")
				write("Available: default, dyslexic, papyrus, comic", "darkgray")
		_:
			write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")
