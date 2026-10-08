## Unit tests verifying [PlayerInteractionScanner] terminal mode state.
class_name TestInteractionScanner
extends GutTest

## Preloaded script reference for the scanner component.
const SCANNER_SCRIPT: GDScript = preload("res://player/player_interaction_scanner.gd")

## The [PlayerInteractionScanner] instance under test.
var scanner: Node = null


## Instantiates [PlayerInteractionScanner] and registers autofree cleanup.
func before_each() -> void:
	print("TestInteractionScanner: Executing before_each() setup.")
	@warning_ignore("unsafe_method_access")
	scanner = SCANNER_SCRIPT.new()
	add_child_autofree(scanner)


## Verifies entering terminal mode sets flags and references correctly.
func test_enter_terminal_mode() -> void:
	print("TestInteractionScanner: Executing test_enter_terminal_mode().")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	watch_signals(scanner)
	scanner.call("enter_terminal_mode", terminal)

	var in_mode_val: Variant = scanner.get("is_in_terminal_mode")
	var is_in_mode: bool = false
	if in_mode_val is bool:
		@warning_ignore("unsafe_cast")
		is_in_mode = in_mode_val as bool
	assert_true(is_in_mode, "Scanner should be in terminal mode.")

	var active_val: Variant = scanner.get("active_terminal")
	var active_node: Node3D = null
	if active_val is Node3D:
		@warning_ignore("unsafe_cast")
		active_node = active_val as Node3D
	assert_eq(active_node, terminal, "Active terminal reference should be stored.")
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [true])


## Verifies exiting terminal mode clears flags and references correctly.
func test_exit_terminal_mode() -> void:
	print("TestInteractionScanner: Executing test_exit_terminal_mode().")
	var terminal: Node3D = Node3D.new()
	add_child_autofree(terminal)

	scanner.call("enter_terminal_mode", terminal)
	watch_signals(scanner)
	scanner.call("exit_terminal_mode")

	var in_mode_val: Variant = scanner.get("is_in_terminal_mode")
	var is_in_mode: bool = true
	if in_mode_val is bool:
		@warning_ignore("unsafe_cast")
		is_in_mode = in_mode_val as bool
	assert_false(is_in_mode, "Scanner should have exited terminal mode.")

	var active_val: Variant = scanner.get("active_terminal")
	var active_node: Node3D = null
	if active_val is Node3D:
		@warning_ignore("unsafe_cast")
		active_node = active_val as Node3D
	assert_null(active_node, "Terminal reference should be cleared.")
	assert_signal_emitted_with_parameters(scanner, "terminal_mode_toggled", [false])


## Verifies setting up the master link injects dependency correctly.
func test_setup_master_link() -> void:
	print("TestInteractionScanner: Executing test_setup_master_link().")
	var master: PlayerInteractionComponent = PlayerInteractionComponent.new()
	add_child_autofree(master)

	scanner.call("setup_master_link", master)

	var master_val: Variant = scanner.get("master_component")
	var master_node: PlayerInteractionComponent = null
	if master_val is PlayerInteractionComponent:
		@warning_ignore("unsafe_cast")
		master_node = master_val as PlayerInteractionComponent
	assert_eq(master_node, master, "Scanner should properly link its Master reference.")
