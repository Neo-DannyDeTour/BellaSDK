## Tracks and navigates submitted console input strings across a session.
class_name ConsoleHistory
extends RefCounted

## Stores the history of typed command strings.
var _history: Array[String] = []
## Tracks the current browsing index inside the history stack.
var _history_index: int = 0
## Maximum allowed entries stored before purging oldest commands.
var _max_capacity: int = 100


## Constructs a new [ConsoleHistory] instance with a fixed ring capacity.
func _init(capacity: int = 100) -> void:
	print("ConsoleHistory: Initialized with capacity: ", capacity)
	_max_capacity = capacity


## Appends a new unique command entry to the back of the history array.
func add(command_text: String) -> void:
	var clean_text: String = command_text.strip_edges()
	if clean_text.is_empty():
		return

	if _history.is_empty() or _history.back() != clean_text:
		print("ConsoleHistory: Appending entry: ", clean_text)
		_history.append(clean_text)

	if _history.size() > _max_capacity:
		_history.pop_front()

	reset_index()


## Resets the browsing pointer to the end of the history stack.
func reset_index() -> void:
	_history_index = _history.size()


## Moves the pointer and returns the corresponding historical command string.
func navigate(direction: int) -> String:
	if _history.is_empty():
		return ""

	print("ConsoleHistory: Navigating pointer. Offset: ", direction)
	_history_index += direction
	_history_index = clampi(_history_index, 0, _history.size())

	if _history_index == _history.size():
		return ""
	return _history[_history_index]


## Checks if the history stack currently holds any recorded entries.
func is_empty() -> bool:
	return _history.is_empty()
