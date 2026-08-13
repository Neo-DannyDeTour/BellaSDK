extends GutTest

## Variant instance for the InteractionScanner under test
var scanner: Variant = null


func before_each() -> void:
	print("TestInteractionScanner: before_each() setup.")
	scanner = load("res://player/player_interaction_scanner.gd").new()
	add_child_autofree(scanner)


func test_enter_terminal_mode() -> void:
	print("TestInteractionScanner: test_enter_terminal_mode() called.")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	watch_signals(scanner)
	scanner.enter_terminal_mode(terminal)

	assert_true(scanner.is_in_terminal_mode, "Scanner should be in terminal mode.")
	assert_eq(scanner.active_terminal, terminal, "Active terminal reference should be stored.")
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [true])


func test_exit_terminal_mode() -> void:
	print("TestInteractionScanner: test_exit_terminal_mode() called.")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	scanner.enter_terminal_mode(terminal)
	watch_signals(scanner)
	scanner.exit_terminal_mode()

	assert_false(scanner.is_in_terminal_mode, "Scanner should have exited terminal mode.")
	assert_null(scanner.active_terminal, "Terminal reference should be cleared.")
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [false])


func test_setup_master_link() -> void:
	print("TestInteractionScanner: test_setup_master_link() called.")
	var master: Node = Node.new()
	add_child_autofree(master)

	scanner.setup_master_link(master)
	assert_eq(
		scanner.master_component, master, "Scanner should properly link its Master reference."
	)
