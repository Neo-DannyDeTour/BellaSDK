## Unit test suite for ConsoleHistory tracking input navigation and ring buffer limits.
class_name TestConsoleHistory
extends GutTest

## Internal reference to the console history stack under test.
var _history: ConsoleHistory = null


## Initializes a fresh ConsoleHistory instance with a small capacity for testing.
func before_each() -> void:
	print("TestConsoleHistory: Initializing new ConsoleHistory instance with capacity 3.")
	_history = ConsoleHistory.new(3)


## Cleans up the ConsoleHistory instance after each test method.
func after_each() -> void:
	print("TestConsoleHistory: Cleaning up ConsoleHistory instance.")
	_history = null


## Tests initial state of ConsoleHistory.
func test_initial_state() -> void:
	print("TestConsoleHistory: Testing initial state.")
	assert_true(_history.is_empty(), "New history instance should be empty.")
	assert_eq(_history.navigate(-1), "", "Navigating empty history should return empty string.")


## Tests adding valid command strings and trimming whitespace.
func test_add_command_and_whitespace_trimming() -> void:
	print("TestConsoleHistory: Testing adding command strings and whitespace trimming.")
	_history.add("   help   ")
	assert_false(_history.is_empty(), "History should not be empty after adding entry.")

	_history.add("")
	_history.add("   ")

	assert_eq(_history.navigate(-1), "help", "Trailing/leading whitespace should be trimmed.")


## Tests ignoring duplicate consecutive commands.
func test_ignore_consecutive_duplicates() -> void:
	print("TestConsoleHistory: Testing duplicate command handling.")
	_history.add("clear")
	_history.add("clear")

	assert_eq(_history.navigate(-1), "clear", "First step back should yield 'clear'.")
	assert_eq(_history.navigate(-1), "clear", "Second step back should clamp to start at 'clear'.")


## Tests ring buffer purging when capacity limit is exceeded.
func test_capacity_overflow_purges_oldest() -> void:
	print("TestConsoleHistory: Testing capacity limit and oldest entry purging.")
	_history.add("cmd1")
	_history.add("cmd2")
	_history.add("cmd3")
	_history.add("cmd4")

	assert_eq(_history.navigate(-1), "cmd4", "Latest entry should be 'cmd4'.")
	assert_eq(_history.navigate(-1), "cmd3", "Previous entry should be 'cmd3'.")
	assert_eq(_history.navigate(-1), "cmd2", "Oldest entry remaining should be 'cmd2'.")
	assert_eq(
		_history.navigate(-1), "cmd2", "cmd1 should have been purged due to capacity 3 limit."
	)


## Tests navigating history stack forward and backward.
func test_navigation_boundaries() -> void:
	print("TestConsoleHistory: Testing navigation pointer clamping.")
	_history.add("first")
	_history.add("second")

	assert_eq(_history.navigate(-1), "second", "Up arrow should navigate to 'second'.")
	assert_eq(_history.navigate(-1), "first", "Up arrow again should navigate to 'first'.")
	assert_eq(_history.navigate(-1), "first", "Up arrow at start should clamp and remain 'first'.")

	assert_eq(_history.navigate(1), "second", "Down arrow should navigate to 'second'.")
	assert_eq(
		_history.navigate(1), "", "Down arrow past latest command should return empty string."
	)
