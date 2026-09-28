## Unit tests verifying PuzzleSocket plug-in, unplug, and power source logic.
class_name TestPuzzleSocket
extends GutTest

## The [PuzzleSocket] instance under test.
var socket: PuzzleSocket = null

## Mock plug node to test insertion logic.
var mock_plug: RigidBody3D = null


## Prepares mock dependencies and socket instance before each test.
func before_each() -> void:
	print("TestPuzzleSocket: before_each() setup started.")

	socket = load("res://shared/puzzle_socket.gd").new()

	var mock_snap: Marker3D = Marker3D.new()
	mock_snap.name = "Marker3D"
	socket.add_child(mock_snap)
	socket.snap_position = mock_snap

	var mock_trigger: Area3D = Area3D.new()
	mock_trigger.name = "PlugTriggerArea"
	socket.add_child(mock_trigger)
	socket.plug_trigger_area = mock_trigger

	add_child_autofree(socket)

	mock_plug = RigidBody3D.new()
	mock_plug.add_to_group("plug")
	add_child_autofree(mock_plug)
	await get_tree().process_frame


## Validates socket powering on when plug is inserted.
func test_plug_in() -> void:
	print("TestPuzzleSocket: test_plug_in() called.")
	watch_signals(socket)

	socket.can_be_unplugged = true
	socket.is_power_source = false
	socket.requires_power_link = false

	socket.plug_in(mock_plug)

	assert_true(socket.is_powered, "Socket should be powered after plug inserted.")
	assert_eq(socket.current_plug, mock_plug, "Current plug should match mock.")
	assert_signal_emitted(socket, "socket_powered_on", "Should emit socket_powered_on signal.")


## Validates socket unpowering and clearing plug reference.
func test_unplug() -> void:
	print("TestPuzzleSocket: test_unplug() called.")
	socket.can_be_unplugged = true
	socket.plug_in(mock_plug)

	watch_signals(socket)

	socket.unplug()

	assert_false(socket.is_powered, "Socket should not be powered after unplug.")
	assert_null(socket.current_plug, "Socket should clear plug reference.")
	assert_signal_emitted(socket, "socket_powered_off", "Should emit socket_powered_off signal.")


## Validates socket power source behavior.
func test_power_source_logic() -> void:
	print("TestPuzzleSocket: test_power_source_logic() called.")
	socket.is_power_source = true

	socket.plug_in(mock_plug)
	assert_true(socket.is_powered, "Power source socket should become powered.")
