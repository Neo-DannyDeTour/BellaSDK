## Unit tests verifying the [PlayerInteractionScanner] terminal mode state transitions.
##
## This suite tests entering and exiting terminal mode, verifying state flags,
## references, and [signal PlayerInteractionScanner.terminal_mode_toggled] emissions.
class_name TestInteractionScanner
extends GutTest

## The InteractionScanner instance under test.
var scanner: InteractionScanner = null


## Instantiates InteractionScanner and registers autofree cleanup before each test.
func before_each() -> void:
	print("TestInteractionScanner: Executing before_each() setup.")
	scanner = InteractionScanner.new()
	add_child_autofree(scanner)


## Verifies that entering terminal mode sets flags and references correctly.
func test_enter_terminal_mode() -> void:
	print("TestInteractionScanner: Executing test_enter_terminal_mode().")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	watch_signals(scanner)
	scanner.enter_terminal_mode(terminal)

	assert_true(scanner.is_in_terminal_mode, "Scanner should be in terminal mode.")
	assert_eq(scanner.active_terminal, terminal, "Active terminal reference should be stored.")
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [true])


## Verifies that exiting terminal mode clears flags and references correctly.
func test_exit_terminal_mode() -> void:
	print("TestInteractionScanner: Executing test_exit_terminal_mode().")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	scanner.enter_terminal_mode(terminal)
	watch_signals(scanner)
	scanner.exit_terminal_mode()

	assert_false(scanner.is_in_terminal_mode, "Scanner should have exited terminal mode.")
	assert_null(scanner.active_terminal, "Terminal reference should be cleared.")
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [false])


## Verifies that setting up the master link injects the dependency correctly.
func test_setup_master_link() -> void:
	print("TestInteractionScanner: Executing test_setup_master_link().")
	var master: Node = Node.new()
	add_child_autofree(master)

	scanner.setup_master_link(master)
	assert_eq(
		scanner.master_component, master, "Scanner should properly link its Master reference."
	)
