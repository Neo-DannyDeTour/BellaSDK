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

# --- Live Suggestions (HL2 Style) ---
var suggestion_label: RichTextLabel
var current_matches: Array[String] = []
var match_index: int = -1
var is_navigating_matches: bool = false

# A list of all available root commands for Tab Autocomplete
var valid_commands: Array[String] = [
	"help", "clear", "quit", "noclip", "iddqd", "idkfa", "kirov",
	"sv_cheats", "soyuz", "motherlode", "konami",
	"upupdowndownleftrightleftrightbastart", "showmethemoney",
	"thereisnocowlevel", "whosyourdaddy", "dnkroz", "hesoyam",
	"leavemealone", "impulse", "thegodfather", "colorblind",
	"gamespeed", "highcontrast", "screenshake", "subtitles",
	"mono_audio", "uiscale", "photosensitivity", "setfont",
	"screenfilter"
]

# Sub-arguments for autocomplete
var valid_colorblind_args: Array[String] = [
	"normal", "protanopia", "deuteranopia", "tritanopia", "mono", "achromatopsia"
]
var valid_font_args: Array[String] = ["default", "dyslexic", "papyrus", "comic"]
var valid_on_off_args: Array[String] = ["on", "off"]
var valid_screenfilter_args: Array[String] = [
	"off", "crt", "vhs", "pixelate", "toon", 
	"gameboy", "glitch", "grain", "halftone", "nightvision", "kuwahara", "ascii"
]

# --- Screen Filter State ---
var screen_filter_rect: ColorRect
var cached_shaders: Dictionary = {}

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

	# HL2 Style Suggestion Box
	suggestion_label = RichTextLabel.new()
	suggestion_label.bbcode_enabled = true
	suggestion_label.fit_content = true
	suggestion_label.visible = false
	suggestion_label.add_theme_constant_override("margin_left", 10)
	vbox.add_child(suggestion_label)

	command_input = LineEdit.new()
	command_input.placeholder_text = "Type a command..."
	command_input.gui_input.connect(_on_line_edit_gui_input)
	command_input.text_changed.connect(_on_text_changed)
	vbox.add_child(command_input)

	is_ui_ready = true

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
	mat.shader = preload("res://vfx/colorblind.gdshader")
	colorblind_rect.material = mat
	filter_layer.add_child(colorblind_rect)

	# --- High Contrast Setup ---
	high_contrast_rect = ColorRect.new()
	high_contrast_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	high_contrast_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	high_contrast_rect.visible = false

	var hc_mat := ShaderMaterial.new()
	hc_mat.shader = preload("res://vfx/high_contrast.gdshader")
	high_contrast_rect.material = hc_mat
	filter_layer.add_child(high_contrast_rect)

	# --- Screen Filter Setup ---
	screen_filter_rect = ColorRect.new()
	screen_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_filter_rect.visible = false
	filter_layer.add_child(screen_filter_rect)

	write("Developer console initialized. Press ~ to toggle.", "cyan")


func _input(event: InputEvent) -> void:
	var console_pressed: bool = event.is_action_pressed("console")
	var cancel_pressed: bool = event.is_action_pressed("ui_cancel") and visible

	if console_pressed or cancel_pressed:
		visible = !visible

		if visible:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			command_input.clear()
			_reset_suggestions()
			history_index = typed_history.size()
			command_input.call_deferred("grab_focus")
			print("Console UI toggled: OPENED.")
		else:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			print("Console UI toggled: CLOSED.")

		Events.terminal_mode_toggled.emit(visible)
		get_viewport().set_input_as_handled()


# --- Keyboard Input Routing ---
func _on_line_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			command_input.accept_event()
			if current_matches.is_empty():
				_navigate_history(-1)
			else:
				_navigate_suggestions(-1)
		
		elif event.keycode == KEY_DOWN:
			command_input.accept_event()
			if current_matches.is_empty():
				_navigate_history(1)
			else:
				_navigate_suggestions(1)
		
		elif event.keycode == KEY_TAB:
			command_input.accept_event()
			if current_matches.size() > 0:
				print("Tab Autocomplete triggered.")
				# Grab the selected match (or the first one if none selected)
				var match_text: String = current_matches[max(0, match_index)]
				
				# Update the text box and move the caret
				command_input.text = match_text + " "
				command_input.caret_column = command_input.text.length()
				
				# CRITICAL: Changing text via code does NOT trigger 'text_changed'.
				# We must manually force it to update the next layer of suggestions!
				_on_text_changed(command_input.text)
				
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			command_input.accept_event()
			_on_command_submitted(command_input.text)


# --- HL2 Style Real-Time Suggestion Logic ---
func _on_text_changed(new_text: String) -> void:
	# If the user is just using arrow keys to cycle matches, don't re-trigger a search
	if is_navigating_matches:
		return

	# Keep one trailing space if it exists so we can detect typing arguments
	var search_text := new_text.lstrip(" ").replace("  ", " ")
	
	if search_text == "":
		_reset_suggestions()
		return

	current_matches = _get_autocomplete_matches(search_text)
	match_index = -1

	if current_matches.is_empty():
		suggestion_label.visible = false
	else:
		suggestion_label.visible = true
		_update_suggestion_ui()
		print("Console fetching suggestions for input: '", search_text, "' -> Found: ", current_matches.size())


func _get_autocomplete_matches(current_text: String) -> Array[String]:
	print("Console calculating autocomplete matches for: '", current_text, "'")
	var parts := current_text.split(" ")
	var matches: Array[String] = []

	if parts.size() == 1:
		var search_term := parts[0].to_lower()
		var exact_starts: Array[String] = []
		var partials: Array[String] = []

		for cmd: String in valid_commands:
			if cmd.begins_with(search_term):
				exact_starts.append(cmd)
			elif cmd.contains(search_term):
				partials.append(cmd)

		matches.append_array(exact_starts)
		matches.append_array(partials)

	elif parts.size() == 2:
		var main_cmd := parts[0].to_lower()
		var sub_term := parts[1].to_lower()
		var arg_matches: Array[String] = []

		if main_cmd == "colorblind":
			arg_matches = valid_colorblind_args
		elif main_cmd == "setfont":
			arg_matches = valid_font_args
		elif main_cmd in ["subtitles", "mono_audio", "photosensitivity", "highcontrast"]:
			arg_matches = valid_on_off_args
		elif main_cmd == "screenfilter":
			arg_matches = valid_screenfilter_args

		var exact_starts: Array[String] = []
		var partials: Array[String] = []

		# Apply the same smart-sorting to sub-arguments
		for arg: String in arg_matches:
			if arg.begins_with(sub_term):
				exact_starts.append(main_cmd + " " + arg)
			elif arg.contains(sub_term):
				partials.append(main_cmd + " " + arg)

		matches.append_array(exact_starts)
		matches.append_array(partials)

	return matches


func _navigate_suggestions(direction: int) -> void:
	print("Navigating console suggestions. Direction: ", direction)
	
	match_index += direction
	if match_index < 0:
		match_index = current_matches.size() - 1
	elif match_index >= current_matches.size():
		match_index = 0

	# Flag prevents _on_text_changed from wiping our selection out
	is_navigating_matches = true
	command_input.text = current_matches[match_index] + " "
	command_input.caret_column = command_input.text.length()
	is_navigating_matches = false

	_update_suggestion_ui()


func _update_suggestion_ui() -> void:
	var bbcode := ""
	for i in range(current_matches.size()):
		if i == match_index:
			bbcode += "[color=yellow]> " + current_matches[i] + "[/color]\n"
		else:
			bbcode += "[color=gray]  " + current_matches[i] + "[/color]\n"
	
	suggestion_label.text = bbcode.strip_edges()


func _reset_suggestions() -> void:
	current_matches.clear()
	match_index = -1
	suggestion_label.visible = false
	suggestion_label.text = ""


# --- History Navigation Logic ---
func _navigate_history(direction: int) -> void:
	if typed_history.is_empty():
		return

	print("Navigating console history. Direction: ", direction)
	history_index += direction
	history_index = clamp(history_index, 0, typed_history.size())

	if history_index == typed_history.size():
		command_input.text = ""
	else:
		command_input.text = typed_history[history_index]
		command_input.caret_column = command_input.text.length()


# --- LOGGING ---
func write(message: String, color: String = "white") -> void:
	print("Console Output: ", message)
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
	_reset_suggestions()

	var clean_text := text.strip_edges()

	if clean_text != "":
		if typed_history.is_empty() or typed_history.back() != clean_text:
			typed_history.append(clean_text)
		history_index = typed_history.size()

		write("> " + clean_text, "darkgray")

		var parts := clean_text.split(" ")
		var command := parts[0].to_lower()
		var args := parts.slice(1)

		print("Executing Console Command: ", command, " | Args: ", args)
		_process_command(command, args)

	if visible:
		command_input.grab_focus()


func _process_command(cmd: String, _args: PackedStringArray) -> void:
	match cmd:
		"help":
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
				write("Bella doesn't need to hear about safety preconscious. She's a highly trained professional", "white")
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
						write("Unknown type. Available: normal, protanopia, deuteranopia, tritanopia, mono, achromatopsia", "red")
			else:
				write("Usage: colorblind <type>\nTypes: normal, protanopia, deuteranopia, tritanopia, mono, achromatopsia", "yellow")
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
				var duration := 1.0 
				
				if _args.size() > 1:
					duration = _args[1].to_float()
					
				Events.screenshake_requested.emit(amount, duration)
				
				# Updated clamping text output
				var msg := "Screenshake: Intensity " + str(clampf(amount, 0.0, 16.0)) + ", Duration " + str(duration) + "s"
				write(msg, "green")
			else:
				write("Usage: screenshake <intensity 0.0-16.0> [duration_in_seconds]", "yellow")
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
				write("Usage: setfont <font_name>\nAvailable: default, dyslexic, papyrus, comic", "yellow")
		"screenfilter":
			if _args.size() > 0:
				var filter_type: String = _args[0].to_lower()
				if filter_type == "off":
					screen_filter_rect.material = null
					screen_filter_rect.visible = false
					write("Screen filter disabled.", "green")
				elif filter_type in valid_screenfilter_args:
					var shader_path: String = ""
					
					# Route to the correct new folders
					if filter_type == "grain":
						shader_path = "res://environment/grain.gdshader"
					else:
						shader_path = "res://vfx/" + filter_type + ".gdshader"
						
					if not cached_shaders.has(filter_type):
						if ResourceLoader.exists(shader_path):
							cached_shaders[filter_type] = load(shader_path)
							print("Console loading new shader resource: ", shader_path)
						else:
							write("Shader not found at: " + shader_path, "red")
							return

					var mat := ShaderMaterial.new()
					mat.shader = cached_shaders[filter_type] as Shader
					screen_filter_rect.material = mat
					screen_filter_rect.visible = true
					write(filter_type.to_upper() + " filter enabled.", "green")
				else:
					write("Unknown filter. Available: off, crt, vhs, pixelate, toon, gameboy, glitch, grain, halftone, nightvision, kuwahara, ascii", "red")
			else:
				write("Usage: screenfilter <type>\nAvailable: off, crt, vhs, pixelate, toon...", "yellow")
		_:
			write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")
