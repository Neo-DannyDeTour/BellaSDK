extends Node

var is_fuzzing: bool = true
var fuzz_timer: float = 0.0
const FUZZ_INTERVAL: float = 0.1  # Slightly slower to let complex tweens (like vaulting) start

var input_history: Array[String] = []
const MAX_HISTORY: int = 50

# Mapped directly to the inputs required by your Player script
const ACTIONS: Array[String] = [
	"forward",
	"backward",
	"left",
	"right",
	"jump",
	"crouch",
	"sprint",
	"interact",
	"zoom",
	"flashlight",
	"shoot"
]


func _ready() -> void:
	randomize()


func _process(delta: float) -> void:
	if not is_fuzzing:
		return

	fuzz_timer += delta
	if fuzz_timer >= FUZZ_INTERVAL:
		fuzz_timer = 0.0
		_generate_random_action()
		_generate_random_mouse_motion()


func _generate_random_action() -> void:
	var random_action: String = ACTIONS.pick_random()
	var is_pressed: bool = randi() % 2 == 0

	_log_action(random_action, is_pressed)

	var event: InputEventAction = InputEventAction.new()
	event.action = random_action
	event.pressed = is_pressed
	Input.parse_input_event(event)


func _generate_random_mouse_motion() -> void:
	# Crucial for your script: Without this, the player will never look up at monkey bars
	# or look down to trigger the is_sliding rope logic.
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = Vector2(randf_range(-150.0, 150.0), randf_range(-150.0, 150.0))
	Input.parse_input_event(event)


func _log_action(action: String, pressed: bool) -> void:
	var state: String = "PRESSED" if pressed else "RELEASED"
	var log_entry: String = "[%s] %s: %s" % [Time.get_ticks_msec(), action, state]
	input_history.push_back(log_entry)
	if input_history.size() > MAX_HISTORY:
		input_history.pop_front()


func print_crash_report() -> void:
	print("--- FUZZER CRASH REPORT ---")
	for entry: String in input_history:
		print(entry)
	print("---------------------------")
