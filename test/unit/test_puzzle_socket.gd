extends GutTest

## The PuzzleSocket instance under test.
var socket: PuzzleSocket = null
## Mock plug node to test insertion logic.
var mock_plug: RigidBody3D = null


func before_each() -> void:
	print("TestPuzzleSocket: before_each() setup.")

	socket = load("res://shared/puzzle_socket.gd").new()
	add_child_autofree(socket)

	var mock_snap: Marker3D = Marker3D.new()
	socket.add_child(mock_snap)
	socket.snap_position = mock_snap

	mock_plug = RigidBody3D.new()
	add_child_autofree(mock_plug)

	socket._ready()


func test_plug_in() -> void:
	print("TestPuzzleSocket: test_plug_in() called.")
	watch_signals(socket)

	socket.can_be_unplugged = true
	socket.is_power_source = false
	socket.requires_power_link = false

	socket.plug_in(mock_plug)

	assert_true(socket.is_powered, "Socket should be powered after plugging in.")
	assert_eq(socket.current_plug, mock_plug, "Socket current plug should be the mock plug.")
	assert_signal_emitted(
		socket, "socket_powered_on", "Should emit powered_on signal when simple plug inserted."
	)


func test_unplug() -> void:
	print("TestPuzzleSocket: test_unplug() called.")
	socket.can_be_unplugged = true
	socket.plug_in(mock_plug)

	watch_signals(socket)

	socket.unplug()

	assert_false(socket.is_powered, "Socket should not be powered after unplugging.")
	assert_null(socket.current_plug, "Socket should clear current plug reference.")
	assert_signal_emitted(
		socket, "socket_powered_off", "Should emit powered_off signal when unplugged."
	)


func test_power_source_logic() -> void:
	print("TestPuzzleSocket: test_power_source_logic() called.")
	socket.is_power_source = true

	# RigidBody lacks this natively, but we test the socket logic
	# so we can just verify the socket internal state.
	socket.plug_in(mock_plug)
	assert_true(socket.is_powered, "Socket as power source should become powered when plugged.")
