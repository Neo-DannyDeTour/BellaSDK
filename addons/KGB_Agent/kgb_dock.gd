@tool
extends Control

# --- UI Elements ---
var atom_spinbox: SpinBox
var merge_spinbox: SpinBox
var generate_btn: Button
var sequence_display: RichTextLabel
var context_input: TextEdit
var ask_ai_btn: Button
var ai_output: RichTextLabel
var http_request: HTTPRequest

var api_key: String = ""

# --- The 55 Gameplay Atoms ---
var gameplay_atoms: Dictionary = {
	1: "Tutorial",
	2: "Story beat",
	3: "'Friction'/one more thing/BUT/second try/break the pattern/the hitch",
	4: "Cutscene/non-interactive moment/comic",
	5: "Going forward/ following/ chasing / running away",
	6: "Battle",
	7: "Loop/Spiral/Hub/weenie/Dynamic/Dark Souls Door",
	8: "Puzzle/battle puzzle/complicate",
	9: "New mechanic/ability/upgrade",
	10: "Old mechanics - new context/alternative usage/creative execution/setup",
	11: "Take something away from the player/bad visibility",
	12: "'Guitar Solo'/unique scene/unique script/cool vista/non-interactive dynamism",
	13: "Defense/territory defense/arena/target defense/waves of enemies",
	14: "Section with turret/sniper/howitzer/cannon/artillery/Storming the room",
	15: "New Enemy/New Cannon/Item/Character/Soundscapes",
	16: "New combination of enemies/equipment/AI/transformation",
	17: "Changing the atmosphere/tempo/Assets/Soundscapes",
	18: "Genre change/working with the camera/Changing perspective",
	19: "From hiding to hiding/Running at speed from one point to another",
	20: "Big battle",
	21: "Boss battle",
	22: "Find the key/button/valve/switch/card/generator/move the box/insert [ITEM]",
	23: "The platforming/floor is lava/Step on the right tiles",
	24: "Mood creation",
	25: "Sudden change of route",
	26: "SUDDENLY!",
	27: "Room or tunnel trap",
	28: "Increasing the difficulty level/particularly difficult area/difficulty modifier",
	29: "Optional content/chance encounter/challenge",
	30: "Free movement/atmosphere creation",
	31: "Backtracking",
	32: "The first mention of future events/locations/characters/enemies",
	33: "Reminder",
	34: "Movement mechanics",
	35: "Filler/repetitions/'Just take a look around.'",
	36: "Mini-games and QTE/environmental takedowns",
	37: "Collectibles/Dopamine/Vendors/optional junk",
	38: "Timer",
	39: "Help traps/using the same asset in multiple places and in different contexts",
	40: "Locked in a room with a boss",
	41: "NPC are fighting",
	42: "Change of a hero",
	43: "Strategizing/Memorizing",
	44: "Easter Eggs/Trophy hunt",
	45: "Forks/Elections/replayability/optional order of passage/King of The Hill",
	46: "Friendly NPC/Escort",
	47: "Task/quest",
	48: "Test of your skills",
	49: "Background activity",
	50: "Optional activity",
	51: "Vandalism/resource room/get big gun early",
	52: "Gimmick/Optional mechanics/The reference",
	53: "Sandbox/System",
	54: "Opportunities",
	55: "Change of framework"
}

# --- Backtracking Modifiers ---
var backtracking_options: Array = [
	"Add new enemies.",
	"Add new obstacles and puzzles.",
	"Change of route: Route changes slightly (HL2:EP1 railway) or map gradually opens (RE2 Remake).",
	"New bosses/mini-bosses: e.g., Mr. X from RE2 Remake adding randomness and paranoia.",
	"New items, weapons, collectibles, and achievements that change typical gameplay.",
	"New visual and audio context (weather, lighting, music changes).",
	"New plot details and cutscenes.",
	"Optional content reveals.",
	"Change of context: E.g., RE2 Remake corridor shifts from pure horror/gathering into an active combat zone.",
	"Random encounters, skits, and dynamic puzzles.",
	"Pumping/Power Fantasy: Return to old locations with new weapons to easily throw enemies away.",
	"Traversal mastery: With new features and skills, complete old platforming levels in a second.",
	"Teleports: Free movement between opened locations (Hollow Knight, Metroid Dread).",
	"Competitive component: Neon White style speed-running of familiar areas."
]

var current_sequence: Array = []
var sequence_has_backtracking: bool = false


func _ready() -> void:
	# 1. SETUP HTTP NODE
	if has_node("HTTPRequest"):
		http_request = $HTTPRequest
	else:
		http_request = HTTPRequest.new()
		add_child(http_request)

	if not http_request.request_completed.is_connected(_on_http_request_completed):
		http_request.request_completed.connect(_on_http_request_completed)

	_load_api_key()
	_build_ui()


func _load_api_key() -> void:
	var path = "res://addons/gemini_copilot/gemini_key.cfg"
	print_rich("[color=yellow]KGB Agent: Attempting to load key from [/color]", path)

	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var content = file.get_as_text()

		# SMART LOADER: Finds the key whether it's raw text or key="value"
		if '="' in content:
			api_key = content.split('="')[1].replace('"', "").strip_edges()
		elif ":" in content:
			api_key = content.split(":")[1].strip_edges()
		else:
			api_key = content.strip_edges()

		if api_key.length() > 5:
			print_rich(
				"[color=green]KGB Agent: Key Loaded Successfully! (Starts with: [/color]",
				api_key.left(5),
				")"
			)
		else:
			print_rich("[color=red]KGB Agent: Key found but seems too short![/color]")
	else:
		print_rich("[color=red]KGB Agent: CANNOT FIND CFG FILE![/color]")


func _on_generate_pressed() -> void:
	current_sequence.clear()
	sequence_has_backtracking = false
	sequence_display.text = "Generated Sequence:\n"

	for i in range(int(atom_spinbox.value)):
		var id = randi_range(1, 55)
		var beat = gameplay_atoms.get(id, "Unknown")
		if id == 31:
			sequence_has_backtracking = true

		if randf() * 100.0 <= merge_spinbox.value:
			var id2 = randi_range(1, 55)
			beat += " + " + gameplay_atoms.get(id2, "Unknown")
			if id2 == 31:
				sequence_has_backtracking = true

		current_sequence.append(beat)
		sequence_display.text += str(i + 1) + ". " + beat + "\n"

	if sequence_has_backtracking:
		sequence_display.text += (
			"\n--- BACKTRACKING MODIFIERS ---\n" + "\n".join(backtracking_options)
		)


func _on_ask_ai_pressed() -> void:
	if api_key.is_empty():
		ai_output.text = "Error: Key empty. Check Output console."
		return

	ai_output.text = "Thinking with Gemini 3.1 Pro..."

	# --- 1. THE 2026 MODEL ID FIX ---
	# As of March 2026, preview models REQUIRE the '-preview' suffix.
	# Since you have a Pro key, use 3.1-pro for the best results!
	var model_name = "gemini-3.1-pro-preview"

	# --- 2. ENDPOINT CHECK ---
	# Preview models are most stable on the v1beta endpoint.
	var url = (
		"https://generativelanguage.googleapis.com/v1beta/models/"
		+ model_name
		+ ":generateContent?key="
		+ api_key.strip_edges()
	)

	var prompt = "Context: " + context_input.text + "\nSequence: " + ", ".join(current_sequence)
	if sequence_has_backtracking:
		prompt += "\nBacktracking Rules: " + ", ".join(backtracking_options)

	var body = JSON.stringify({"contents": [{"parts": [{"text": prompt}]}]})

	var body_bytes = body.to_utf8_buffer()
	var headers = PackedStringArray(
		["Content-Type: application/json", "Content-Length: " + str(body_bytes.size())]
	)

	print_rich("[color=cyan]KGB Agent: Requesting [/color]", model_name)

	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		ai_output.text = "HTTP Error: " + str(error)


func _on_http_request_completed(result, response_code, headers, body) -> void:
	var response = body.get_string_from_utf8()
	print_rich("[color=white]KGB Agent: Received Response Code [/color]", response_code)

	if response_code == 200:
		var json = JSON.parse_string(response)
		ai_output.text = json["candidates"][0]["content"]["parts"][0]["text"]
	else:
		ai_output.text = "API Error: " + str(response_code) + "\n" + response


# --- UI BUILDER (Separated for clarity) ---
func _build_ui():
	# (Clean old UI first)
	for child in get_children():
		if child != http_request:
			child.queue_free()

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	add_child(vbox)

	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)

	atom_spinbox = SpinBox.new()
	atom_spinbox.value = 5
	hbox.add_child(Label.new())
	hbox.get_child(-1).text = "Atoms:"
	hbox.add_child(atom_spinbox)

	merge_spinbox = SpinBox.new()
	merge_spinbox.value = 15
	hbox.add_child(Label.new())
	hbox.get_child(-1).text = " Merge%:"
	hbox.add_child(merge_spinbox)

	generate_btn = Button.new()
	generate_btn.text = "Generate Sequence"
	generate_btn.pressed.connect(_on_generate_pressed)
	vbox.add_child(generate_btn)

	sequence_display = RichTextLabel.new()
	sequence_display.custom_minimum_size.y = 150
	vbox.add_child(sequence_display)

	context_input = TextEdit.new()
	context_input.placeholder_text = "Level Context (Genre, Setting, etc)..."
	context_input.custom_minimum_size.y = 100
	# This forces the text to drop to the next line instead of scrolling forever
	context_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(context_input)

	ask_ai_btn = Button.new()
	ask_ai_btn.text = "Ask Gemini"
	ask_ai_btn.pressed.connect(_on_ask_ai_pressed)
	vbox.add_child(ask_ai_btn)

	ai_output = RichTextLabel.new()
	ai_output.size_flags_vertical = SIZE_EXPAND_FILL

	# These two lines allow you to click-drag to select and right-click to copy!
	ai_output.selection_enabled = true
	ai_output.context_menu_enabled = true

	# Optional: Keep the text readable
	ai_output.bbcode_enabled = true

	vbox.add_child(ai_output)
