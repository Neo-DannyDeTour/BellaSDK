@tool
extends Control

# --- UI Elements ---

## The SpinBox controlling how many atomic gameplay beats are generated per sequence.
var atom_spinbox: SpinBox

## The SpinBox controlling the percentage chance of merging two atoms together.
var merge_spinbox: SpinBox

## The button that triggers the random sequence generation logic.
var generate_btn: Button

## The text area displaying the locally generated sequence outline.
var sequence_display: RichTextLabel

## The text input field where the user provides level context for the AI.
var context_input: TextEdit

## The button that sends the generated sequence and context to the Gemini API.
var ask_ai_btn: Button

## The text area displaying the final response from the AI.
var ai_output: RichTextLabel

## The node responsible for handling the asynchronous HTTP POST requests to the API.
var http_request: HTTPRequest

## The cached API key loaded from the local configuration file.
var api_key: String = ""

# --- The 55 Gameplay Atoms ---

## The core dictionary defining the 55 fundamental gameplay atoms for generation.
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

## A list of design modifiers appended if the sequence rolls a backtracking atom.
var backtracking_options: Array[String] = [
	"Add new enemies.",
	"Add new obstacles and puzzles.",
	"Change of route: Route changes slightly (HL2:EP1 railway) or map gradually opens (RE2 Remake).",
	"New bosses/mini-bosses: e.g., Mr. X from RE2 Remake adding randomness and paranoia.",
	"New items, weapons, collectibles, and achievements that change typical gameplay.",
	"New visual and audio context (weather, lighting, music changes).",
	"New plot details and cutscenes.",
	"Optional content reveals.",
	(
		"Change of context: E.g., RE2 Remake corridor shifts from pure "
		+ "horror/gathering into an active combat zone."
	),
	"Random encounters, skits, and dynamic puzzles.",
	"Pumping/Power Fantasy: Return to old locations with new weapons to easily throw enemies away.",
	"Traversal mastery: With new features and skills, complete old platforming levels in a second.",
	"Teleports: Free movement between opened locations (Hollow Knight, Metroid Dread).",
	"Competitive component: Neon White style speed-running of familiar areas."
]

## The locally cached array holding the text for the current generated sequence.
var current_sequence: Array[String] = []

## A flag identifying whether the current sequence requires backtracking logic.
var sequence_has_backtracking: bool = false


func _ready() -> void:
	# 1. SETUP HTTP NODE
	if has_node("HTTPRequest"):
		http_request = $HTTPRequest as HTTPRequest
	else:
		http_request = HTTPRequest.new()
		add_child(http_request)

	if not http_request.request_completed.is_connected(_on_http_request_completed):
		http_request.request_completed.connect(_on_http_request_completed)

	_load_api_key()
	_build_ui()


func _load_api_key() -> void:
	var path: String = "res://addons/gemini_copilot/gemini_key.cfg"
	print_rich("[color=yellow]KGB Agent: Attempting to load key from [/color]", path)

	if FileAccess.file_exists(path):
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		var content: String = file.get_as_text()

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

	var atom_count: int = int(atom_spinbox.value)
	var merge_chance: float = merge_spinbox.value

	for i: int in range(atom_count):
		var id: int = randi_range(1, 55)
		var beat: String = gameplay_atoms.get(id, "Unknown") as String
		if id == 31:
			sequence_has_backtracking = true

		if randf() * 100.0 <= merge_chance:
			var id2: int = randi_range(1, 55)
			beat += " + " + (gameplay_atoms.get(id2, "Unknown") as String)
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
	var model_name: String = "gemini-3.1-pro-preview"

	# --- 2. ENDPOINT CHECK ---
	# Preview models are most stable on the v1beta endpoint.
	var url: String = (
		"https://generativelanguage.googleapis.com/v1beta/models/"
		+ model_name
		+ ":generateContent?key="
		+ api_key.strip_edges()
	)

	var prompt: String = (
		"Context: " + context_input.text + "\nSequence: " + ", ".join(current_sequence)
	)
	if sequence_has_backtracking:
		prompt += "\nBacktracking Rules: " + ", ".join(backtracking_options)

	var body: String = JSON.stringify({"contents": [{"parts": [{"text": prompt}]}]})

	var body_bytes: PackedByteArray = body.to_utf8_buffer()
	var headers: PackedStringArray = PackedStringArray(
		["Content-Type: application/json", "Content-Length: " + str(body_bytes.size())]
	)

	print_rich("[color=cyan]KGB Agent: Requesting [/color]", model_name)

	var error: Error = http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		ai_output.text = "HTTP Error: " + str(error)


func _on_http_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		ai_output.text = "HTTP Request Failed. Result code: " + str(result)
		return

	var response: String = body.get_string_from_utf8()
	print_rich("[color=white]KGB Agent: Received Response Code [/color]", response_code)

	if response_code == 200:
		var json: Variant = JSON.parse_string(response)
		if typeof(json) != TYPE_DICTIONARY:
			ai_output.text = "Error: Invalid JSON response."
			return

		var json_dict: Dictionary = json as Dictionary
		if (
			not json_dict.has("candidates")
			or typeof(json_dict["candidates"]) != TYPE_ARRAY
			or (json_dict["candidates"] as Array).is_empty()
		):
			ai_output.text = "Error: JSON response missing 'candidates'."
			return

		var candidate: Dictionary = json["candidates"][0]
		if typeof(candidate) != TYPE_DICTIONARY or not candidate.has("content"):
			ai_output.text = "Error: JSON response missing 'content'."
			return

		var content: Dictionary = candidate["content"]
		if (
			typeof(content) != TYPE_DICTIONARY
			or not (content as Dictionary).has("parts")
			or typeof((content as Dictionary)["parts"]) != TYPE_ARRAY
			or ((content as Dictionary)["parts"] as Array).is_empty()
		):
			ai_output.text = "Error: JSON response missing 'parts'."
			return

		var part: Dictionary = content["parts"][0]
		if (
			typeof(part) != TYPE_DICTIONARY
			or not (part as Dictionary).has("text")
			or typeof((part as Dictionary)["text"]) != TYPE_STRING
		):
			ai_output.text = "Error: JSON response missing 'text'."
			return

		ai_output.text = (part as Dictionary)["text"] as String
	else:
		ai_output.text = "API Error: " + str(response_code) + "\n" + response


# --- UI BUILDER (Separated for clarity) ---
func _build_ui() -> void:
	# (Clean old UI first)
	for child: Node in get_children():
		if child != http_request:
			child.queue_free()

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var hbox: HBoxContainer = HBoxContainer.new()
	vbox.add_child(hbox)

	atom_spinbox = SpinBox.new()
	atom_spinbox.value = 5.0

	var label_atoms: Label = Label.new()
	label_atoms.text = "Atoms:"
	hbox.add_child(label_atoms)
	hbox.add_child(atom_spinbox)

	merge_spinbox = SpinBox.new()
	merge_spinbox.value = 15.0

	var label_merge: Label = Label.new()
	label_merge.text = " Merge%:"
	hbox.add_child(label_merge)
	hbox.add_child(merge_spinbox)

	generate_btn = Button.new()
	generate_btn.text = "Generate Sequence"
	generate_btn.pressed.connect(_on_generate_pressed)
	vbox.add_child(generate_btn)

	sequence_display = RichTextLabel.new()
	sequence_display.custom_minimum_size.y = 150.0
	vbox.add_child(sequence_display)

	context_input = TextEdit.new()
	context_input.placeholder_text = "Level Context (Genre, Setting, etc)..."
	context_input.custom_minimum_size.y = 100.0
	context_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vbox.add_child(context_input)

	ask_ai_btn = Button.new()
	ask_ai_btn.text = "Ask Gemini"
	ask_ai_btn.pressed.connect(_on_ask_ai_pressed)
	vbox.add_child(ask_ai_btn)

	ai_output = RichTextLabel.new()
	ai_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ai_output.selection_enabled = true
	ai_output.context_menu_enabled = true
	ai_output.bbcode_enabled = true

	vbox.add_child(ai_output)
