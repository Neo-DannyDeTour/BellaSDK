## Unit tests verifying the [PlayerInteractionScanner] terminal mode state transitions.
##
## This suite tests entering and exiting terminal mode, verifying state flags,
## references, and [signal PlayerInteractionScanner.terminal_mode_toggled] emissions.
class_name TestInteractionScanner
extends GutTest

## The [PlayerInteractionScanner] instance under test.
var scanner: Node = null


## Instantiates [PlayerInteractionScanner] and registers autofree cleanup before each test.
func before_each() -> void:
	print("TestInteractionScanner: Executing before_each() setup.")
	scanner = load("res://player/player_interaction_scanner.gd").new() as Node
	add_child_autofree(scanner)


## Verifies that entering terminal mode sets flags and references correctly.
func test_enter_terminal_mode() -> void:
	print("TestInteractionScanner: Executing test_enter_terminal_mode().")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	watch_signals(scanner)
	scanner.call("enter_terminal_mode", terminal)

	assert_true(bool(scanner.get("is_in_terminal_mode")), "Scanner should be in terminal mode.")
	assert_eq(
		scanner.get("active_terminal"), terminal, "Active terminal reference should be stored."
	)
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [true])


## Verifies that exiting terminal mode clears flags and references correctly.
func test_exit_terminal_mode() -> void:
	print("TestInteractionScanner: Executing test_exit_terminal_mode().")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	scanner.call("enter_terminal_mode", terminal)
	watch_signals(scanner)
	scanner.call("exit_terminal_mode")

	assert_false(
		bool(scanner.get("is_in_terminal_mode")), "Scanner should have exited terminal mode."
	)
	assert_null(scanner.get("active_terminal"), "Terminal reference should be cleared.")
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [false])


## Verifies that setting up the master link injects the dependency correctly.
func test_setup_master_link() -> void:
	print("TestInteractionScanner: Executing test_setup_master_link().")
	var master: Node = Node.new()
	add_child_autofree(master)

	scanner.call("setup_master_link", master)
	assert_eq(
		scanner.get("master_component"),
		master,
		"Scanner should properly link its Master reference."
	)
