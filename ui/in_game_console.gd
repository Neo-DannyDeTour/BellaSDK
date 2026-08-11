extends CanvasLayer

## The rich text label used to display the console's output log.
var output_log: RichTextLabel
## The main container panel for the console UI.
var panel: PanelContainer
## The vertical box container organizing the console UI elements.
var vbox: VBoxContainer
## The line edit field where the user types console commands.
var command_input: LineEdit

## The full-screen color rectangle used to apply the colorblind shader.
var colorblind_rect: ColorRect
## The full-screen color rectangle used to apply the high contrast shader.
var high_contrast_rect: ColorRect

## Stores the history of output messages to populate the log when the UI initializes.
var message_history: Array[Dictionary] = []
## Indicates whether the console UI nodes have been fully initialized.
var is_ui_ready: bool = false

## Stores the history of typed commands to allow the user to navigate previous inputs.
var typed_history: Array[String] = []
## Tracks the current position in the typed command history during navigation.
var history_index: int = 0

## The rich text label used to display autocomplete suggestions above the input field.
var suggestion_label: RichTextLabel
## Holds the list of autocomplete string matches for the current input.
var current_matches: Array[String] = []
## Tracks the currently selected index within the autocomplete matches list.
var match_index: int = -1
## Prevents text change events from triggering while navigating autocomplete matches.
var is_navigating_matches: bool = false

## Security variable: Indicates if debug commands (noclip, gamespeed, sethealth) are allowed.
var is_debug_allowed: bool = OS.has_feature("debug")

## Tracks the active state of toggleable boolean commands to allow single-word toggling.
var toggle_states: Dictionary = {
	"highcontrast": false,
	"subtitles": false,
	"mono_audio": false,
	"photosensitivity": false,
	"visionassist": false
}

## A list of all base commands available in the console. 
var valid_commands: Array[String] = [
	"help",
	"clear",
	"quit",
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
	"highcontrast",
	"screenshake",
	"subtitles",
	"mono_audio",
	"uiscale",
	"photosensitivity",
	"setfont",
	"screenfilter",
    "visionassist"
]

## A list of valid arguments specifically for the colorblind command.
var valid_colorblind_args: Array[String] = [
	"normal", "protanopia", "deuteranopia", "tritanopia", "mono", "achromatopsia"
]
## A list of valid font choices for the setfont command.
var valid_font_args: Array[String] = ["default", "dyslexic", "papyrus", "comic"]
## A list of valid screen filter shaders for the screenfilter command.
var valid_screenfilter_args: Array[String] = [
	"off", "crt", "vhs", "pixelate", "toon", "gameboy", "glitch", "grain", "halftone",
	"nightvision", "kuwahara", "ascii", "90anime", "manga", "handdrawn", "moebius",
	"obra", "psychedelic", "botw", "ghibli", "reaction", "software", "swirl", "mandelbrot"
]

## The full-screen color rectangle used to apply generalized screen filter shaders.
var screen_filter_rect: ColorRect
## A dictionary mapping shader names to their loaded Resource objects for optimization.
var cached_shaders: Dictionary = {}


func _init() -> void:
	print("InGameConsole: _init() called. Initializing command list.")
	if is_debug_allowed:
		valid_commands.append("noclip")
		valid_commands.append("gamespeed")
		valid_commands.append("die")
		valid_commands.append("normals")
		valid_commands.append("sethealth")


func _ready() -> void:
	print("InGameConsole: _ready() called. Building UI elements.")
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
		output_log.push_color(Color(msg["color"]))
		output_log.add_text(msg["text"])
		output_log.pop()
		output_log.newline()

	var filter_layer: CanvasLayer = CanvasLayer.new()
	filter_layer.layer = 127
	add_child(filter_layer)

	colorblind_rect = ColorRect.new()
	colorblind_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	colorblind_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = preload("res://vfx/colorblind.gdshader")
	colorblind_rect.material = mat
	filter_layer.add_child(colorblind_rect)

	high_contrast_rect = ColorRect.new()
	high_contrast_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	high_contrast_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	high_contrast_rect.visible = false

	var hc_mat: ShaderMaterial = ShaderMaterial.new()
	hc_mat.shader = preload("res://vfx/high_contrast.gdshader")
	high_contrast_rect.material = hc_mat
	filter_layer.add_child(high_contrast_rect)

	screen_filter_rect = ColorRect.new()
	screen_filter_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_filter_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_filter_rect.visible = false
	filter_layer.add_child(screen_filter_rect)

	write("Developer console initialized. Press ~ to toggle.", "cyan")

	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("colorblind_mode_changed"):
			events.colorblind_mode_changed.connect(_on_ui_colorblind_changed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("console") or (event.is_action_pressed("ui_cancel") and visible):
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

		get_viewport().set_input_as_handled()


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
			if current_matches.size() > 0:
				print("Tab Autocomplete triggered.")
				var match_text: String = current_matches[max(0, match_index)]
				command_input.text = match_text + " "
				command_input.caret_column = command_input.text.length()
				_on_text_changed(command_input.text)

		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			print("InGameConsole: Key ENTER pressed.")
			command_input.accept_event()
			_on_command_submitted(command_input.text)


func _on_text_changed(new_text: String) -> void:
	if is_navigating_matches:
		return

	var search_text: String = new_text.lstrip(" ").replace("  ", " ")

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
		print(
			"Console fetching suggestions for input: '",
			search_text,
			"' -> Found: ",
			current_matches.size()
		)


func _get_autocomplete_matches(current_text: String) -> Array[String]:
	print("Console calculating autocomplete matches for: '", current_text, "'")
	var parts: PackedStringArray = current_text.split(" ")
	var matches: Array[String] = []

	if parts.size() == 1:
		var search_term: String = parts[0].to_lower()
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
		var main_cmd: String = parts[0].to_lower()
		var sub_term: String = parts[1].to_lower()
		var arg_matches: Array[String] = []

		if main_cmd == "colorblind":
			arg_matches = valid_colorblind_args
		elif main_cmd == "setfont":
			arg_matches = valid_font_args
		elif main_cmd == "screenfilter":
			arg_matches = valid_screenfilter_args
		elif main_cmd == "visionassist":
			arg_matches = ["mode", "color"]

		var exact_starts: Array[String] = []
		var partials: Array[String] = []

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

	is_navigating_matches = true
	command_input.text = current_matches[match_index] + " "
	command_input.caret_column = command_input.text.length()
	is_navigating_matches = false

	_update_suggestion_ui()


func _update_suggestion_ui() -> void:
	print("InGameConsole: Updating suggestion UI graphics.")
	var bbcode: String = ""
	for i: int in range(current_matches.size()):
		if i == match_index:
			bbcode += "[color=yellow]> " + current_matches[i] + "[/color]\n"
		else:
			bbcode += "[color=gray]  " + current_matches[i] + "[/color]\n"

	suggestion_label.text = bbcode.strip_edges()


func _reset_suggestions() -> void:
	print("InGameConsole: _reset_suggestions() called. Clearing match data.")
	current_matches.clear()
	match_index = -1
	suggestion_label.visible = false
	suggestion_label.text = ""


func _navigate_history(direction: int) -> void:
	if typed_history.is_empty():
		return

	print("Navigating console history. Direction: ", direction)
	history_index += direction
	history_index = clampi(history_index, 0, typed_history.size())

	if history_index == typed_history.size():
		command_input.text = ""
	else:
		command_input.text = typed_history[history_index]
		command_input.caret_column = command_input.text.length()


func write(message: String, color: String = "white") -> void:
	print("Console Output: ", message)

	if not is_ui_ready:
		message_history.append({"text": message, "color": color})
		return

	output_log.push_color(Color(color))
	output_log.add_text(message)
	output_log.pop()
	output_log.newline()


func log_info(msg: String) -> void:
	print("InGameConsole logging info: ", msg)
	write(msg, "lightgray")


func log_warn(msg: String) -> void:
	print("InGameConsole logging warning: ", msg)
	write("[WARNING] " + msg, "yellow")


func log_error(msg: String) -> void:
	print("InGameConsole logging error: ", msg)
	write("[ERROR] " + msg, "red")


func _on_command_submitted(text: String) -> void:
	print("InGameConsole: _on_command_submitted() processing command.")
	command_input.clear()
	_reset_suggestions()

	var clean_text: String = text.strip_edges()

	if clean_text != "":
		if typed_history.is_empty() or typed_history.back() != clean_text:
			typed_history.append(clean_text)
		history_index = typed_history.size()

		write("> " + clean_text, "darkgray")

		var parts: PackedStringArray = clean_text.split(" ")
		var command: String = parts[0].to_lower()
		var args: PackedStringArray = parts.slice(1)

		print("Executing Console Command: ", command, " | Args: ", args)
		_process_command(command, args)

	if visible:
		command_input.grab_focus()


func _process_command(cmd: String, args: PackedStringArray) -> void:
	print("InGameConsole: Processing core command switch: ", cmd)
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
			if is_debug_allowed:
				print("InGameConsole: Action toggled Noclip")
				if has_node("/root/Events"):
					var events: Node = get_node("/root/Events")
					if events.has_signal("noclip_ui_button_pressed"):
						events.emit_signal("noclip_ui_button_pressed")
				write("Toggled Noclip.", "yellow")
			else:
				write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")
		"iddqd":
			write("good memory!", "gold")
		"idkfa":
			write("another classic", "gold")
		"kirov":
			write("Kirov reporting!", "red")
		"sv_cheats":
			if args.size() > 0 and args[0] == "1":
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
			if args.size() > 0 and args[0] == "101":
				write(
					"Bella doesn't need to hear about safety preconscious. She's a trained pro",
                    "white"
				)
			else:
				write("Usage: sv_cheats 1", "red")
		"thegodfather":
			write("do not care")
		"colorblind":
			if args.size() > 0:
				var mode: String = args[0].to_lower()
				var material: ShaderMaterial = colorblind_rect.material as ShaderMaterial
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
							"Unknown type. Try: normal, protanopia, deuteranopia, tritanopia",
                            "red"
						)
			else:
				write(
					"Usage: colorblind <type>\nTypes: normal, protanopia, deuteranopia...",
                    "yellow"
				)
		"gamespeed":
			if is_debug_allowed:
				print("InGameConsole: Action Set Gamespeed")
				if args.size() > 0:
					var new_speed: float = args[0].to_float()
					Engine.time_scale = clampf(new_speed, 0.1, 10.0)
					write("Time scale set to: " + str(Engine.time_scale), "green")
				else:
					write("Usage: gamespeed <value> (e.g., 0.7 for 70% speed)", "yellow")
			else:
				write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")
		"highcontrast":
			toggle_states["highcontrast"] = !toggle_states["highcontrast"]
			var active: bool = toggle_states["highcontrast"]
			print("InGameConsole: Toggled highcontrast to ", active)
			if has_node("/root/Events"):
				var events: Node = get_node("/root/Events")
				if events.has_signal("high_contrast_toggled"):
					events.emit_signal("high_contrast_toggled", active)
			write("High contrast mode: " + ("Enabled" if active else "Disabled"), "green")
		"screenshake":
			if args.size() > 0:
				var amount: float = args[0].to_float()
				var duration: float = 1.0

				if args.size() > 1:
					duration = args[1].to_float()

				if has_node("/root/Events"):
					var events: Node = get_node("/root/Events")
					if events.has_signal("screenshake_requested"):
						events.emit_signal("screenshake_requested", amount, duration)

				var msg: String = (
                    "Screenshake: Intensity "
					+ str(clampf(amount, 0.0, 16.0))
					+ ", Duration "
					+ str(duration)
					+ "s"
				)
				write(msg, "green")
			else:
				write("Usage: screenshake <intensity 0.0-16.0> [duration_in_seconds]", "yellow")
		"subtitles":
			toggle_states["subtitles"] = !toggle_states["subtitles"]
			var active: bool = toggle_states["subtitles"]
			print("InGameConsole: Toggled subtitles to ", active)
			if has_node("/root/Events"):
				var events: Node = get_node("/root/Events")
				if events.has_signal("subtitles_toggled"):
					events.emit_signal("subtitles_toggled", active)
			write("Subtitles: " + ("ON" if active else "OFF"), "green")
		"mono_audio":
			toggle_states["mono_audio"] = !toggle_states["mono_audio"]
			var active: bool = toggle_states["mono_audio"]
			print("InGameConsole: Toggled mono_audio to ", active)
			write("Mono Audio: " + ("ON" if active else "OFF"), "green")
		"uiscale":
			if args.size() > 0:
				var scale_val: float = args[0].to_float()
				write("UI Scale set to: " + str(scale_val), "green")
			else:
				write("Usage: uiscale <float> (Default is usually 1.0)", "yellow")
		"photosensitivity":
			toggle_states["photosensitivity"] = !toggle_states["photosensitivity"]
			var active: bool = toggle_states["photosensitivity"]
			print("InGameConsole: Toggled photosensitivity to ", active)
			if has_node("/root/Events"):
				var events: Node = get_node("/root/Events")
				if events.has_signal("photosensitivity_mode_toggled"):
					events.emit_signal("photosensitivity_mode_toggled", active)
			write("Photosensitivity safe mode: " + ("ON" if active else "OFF"), "green")
		"setfont":
			if args.size() > 0:
				var font_choice: String = args[0].to_lower()
				if font_choice in valid_font_args:
					if has_node("/root/Events"):
						var events: Node = get_node("/root/Events")
						if events.has_signal("font_changed"):
							events.emit_signal("font_changed", font_choice)
					write("Global font set to: " + font_choice, "green")
				else:
					write("Unknown font. Available: default, dyslexic, papyrus, comic", "red")
			else:
				write(
					"Usage: setfont <font_name>\nAvailable: default, dyslexic, papyrus, comic",
                    "yellow"
				)
		"screenfilter":
			if args.size() > 0:
				var filter_type: String = args[0].to_lower()
				if filter_type == "off":
					screen_filter_rect.material = null
					screen_filter_rect.visible = false
					write("Screen filter disabled.", "green")
				elif filter_type in valid_screenfilter_args:
					var shader_path: String = ""

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

					var mat: ShaderMaterial = ShaderMaterial.new()
					mat.shader = cached_shaders[filter_type] as Shader
					screen_filter_rect.material = mat
					screen_filter_rect.visible = true
					write(filter_type.to_upper() + " filter enabled.", "green")
				else:
					write(
						"Unknown filter. Available: off, crt, vhs, pixelate, toon...",
                        "red"
					)
			else:
				write(
					"Usage: screenfilter <type>\nAvailable: off, crt, vhs, pixelate...",
                    "yellow"
				)
		"visionassist":
			if args.size() == 0:
				toggle_states["visionassist"] = !toggle_states["visionassist"]
				var active: bool = toggle_states["visionassist"]
				print("InGameConsole: Vision assist toggled to ", active)
				if has_node("/root/Events"):
					var events: Node = get_node("/root/Events")
					if events.has_signal("vision_assist_toggled"):
						events.emit_signal("vision_assist_toggled", active)
				write("Vision Assist: " + ("ON" if active else "OFF"), "green")

			elif args.size() > 0:
				var arg1: String = args[0].to_lower()
				
				if arg1 == "mode" and args.size() == 2:
					var mode_name: String = args[1].to_lower()
					if mode_name in ["black_and_white", "aaa_blue", "pure_black"]:
						if has_node("/root/Events"):
							var events: Node = get_node("/root/Events")
							if events.has_signal("vision_assist_mode_changed"):
								events.emit_signal("vision_assist_mode_changed", mode_name)
						write("Vision Assist mode set to: " + mode_name, "green")
						print("Console: Vision assist mode changed to ", mode_name)
					else:
						write(
							"Invalid mode. Use 'black_and_white', 'aaa_blue', or 'pure_black'.",
                            "yellow"
						)
				elif arg1 == "color" and args.size() == 3:
					var target_group: String = args[1].to_lower()
					var color_name: String = args[2].to_lower()

					if has_node("/root/Events"):
						var events: Node = get_node("/root/Events")
						if events.has_signal("vision_assist_color_changed"):
							events.emit_signal(
								"vision_assist_color_changed", target_group, color_name
							)
					write("Vision Assist: Changed " + target_group + " to " + color_name, "green")
					print("Console: Vision assist color changed for ", target_group)
				else:
					write(
						"Usage: visionassist OR visionassist mode <mode> OR color <group> <color>",
                        "yellow"
					)
		"die":
			if is_debug_allowed:
				print("InGameConsole: Action Executing 'die' command.")

				var players: Array[Node] = get_tree().get_nodes_in_group("player")
				if players.size() > 0:
					var player: Node = players[0]

					var health_comp: Node = player.get_node_or_null("Components/HealthComponent")

					if not health_comp:
						health_comp = player.find_child("HealthComponent", true, false)

					if health_comp and health_comp is HealthComponent:
						health_comp.take_damage(health_comp.current_health)
						write("You dropped dead.", "red")
					else:
						write(
							"HealthComponent not found in the player's 'Components' node.", "yellow"
						)
				else:
					write("Player node not found in the 'player' group.", "yellow")
			else:
				write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")
		"normals":
			if is_debug_allowed:
				print("InGameConsole: Action Toggled Normal View")
				var vp: Viewport = get_viewport()
				if vp.debug_draw == Viewport.DEBUG_DRAW_NORMAL_BUFFER:
					vp.debug_draw = Viewport.DEBUG_DRAW_DISABLED
					write("Normal view OFF.", "yellow")
				else:
					vp.debug_draw = Viewport.DEBUG_DRAW_NORMAL_BUFFER
					write("Normal view ON.", "green")
			else:
				write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")
		"sethealth":
			if is_debug_allowed:
				print("InGameConsole: Action Executing 'sethealth' command.")
				if args.size() > 0:
					var health_val: int = args[0].to_int()
					health_val = clampi(health_val, 0, 300)
					
					var players: Array[Node] = get_tree().get_nodes_in_group("player")
					if players.size() > 0:
						var player: Node = players[0]
						var health_comp: Node = player.get_node_or_null(
                            "Components/HealthComponent"
						)
						
						if not health_comp:
							health_comp = player.find_child("HealthComponent", true, false)
							
						if health_comp and health_comp is HealthComponent:
							print("InGameConsole: Found HealthComponent, updating values.")
							health_comp.current_health = health_val
							
							# Force the component to broadcast the new health so the UI updates
							health_comp.health_changed.emit(health_comp.current_health)
							
							if health_comp.is_player_health and has_node("/root/Events"):
								var events: Node = get_node("/root/Events")
								if events.has_signal("player_health_changed"):
									events.emit_signal("player_health_changed", health_comp.current_health)
									print("InGameConsole: Relayed health to global Events bus.")
							
							# Handle instant death if set to 0
							if health_comp.current_health == 0:
								print("InGameConsole: Health set to 0, triggering die().")
								health_comp.die()

							write("Player health forcefully set to: " + str(health_val), "green")
						else:
							write("HealthComponent not found on the player entity.", "yellow")
					else:
						write("Player node not found in the 'player' group.", "yellow")
				else:
					write("Usage: sethealth <value 0-300>", "yellow")
			else:
				write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")

		_:
			write("Unknown command: '" + cmd + "'. Type 'help' for a list.", "red")


func _on_ui_colorblind_changed(mode: int) -> void:
	print("InGameConsole: Intercepted colorblind UI change to mode index: ", mode)
	if colorblind_rect and colorblind_rect.material:
		var material: ShaderMaterial = colorblind_rect.material as ShaderMaterial
		material.set_shader_parameter("mode", mode)
