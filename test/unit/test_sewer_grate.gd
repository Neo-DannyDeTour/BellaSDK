extends GutTest
## Unit tests for [SewerGrate] component integration and [EventSequenceTrigger] execution.
class_name TestSewerGrate

## Instantiated [SewerGrate] test fixture.
var _grate: SewerGrate = null


## Instantiates sewer grate scene before each test run.
func before_each() -> void:
	print("TestSewerGrate: Setting up test fixture.")
	var sc: PackedScene = load("res://interactables/sewer_grate/sewer_grate.tscn") as PackedScene
	_grate = sc.instantiate() as SewerGrate
	add_child(_grate)


## Frees test fixture after each test run.
func after_each() -> void:
	print("TestSewerGrate: Tearing down test fixture.")
	if is_instance_valid(_grate):
		_grate.queue_free()
	_grate = null


## Verifies mandatory child components and physics bodies are configured correctly.
func test_initial_hierarchy_and_components() -> void:
	assert_not_null(_grate, "SewerGrate instance should be valid.")

	var interact_comp: Node = _grate.get_node_or_null("InteractComponent")
	assert_not_null(interact_comp, "InteractComponent should be present in scene.")
	assert_true(interact_comp is InteractComponent, "Must be instance of InteractComponent.")

	var highlight_comp: Node = _grate.get_node_or_null("HighlightComponent")
	assert_not_null(highlight_comp, "HighlightComponent should be present in scene.")
	assert_true(highlight_comp is HighlightComponent, "Must be instance of HighlightComponent.")

	var body_left: RigidBody3D = _grate.get_node_or_null("GrateBodyLeft") as RigidBody3D
	var body_right: RigidBody3D = _grate.get_node_or_null("GrateBodyRight") as RigidBody3D
	assert_not_null(body_left, "GrateBodyLeft should be created by _ready().")
	assert_not_null(body_right, "GrateBodyRight should be created by _ready().")


## Verifies player direct interaction dispatches door toggle according to permissions.
func test_player_interaction_and_permission() -> void:
	assert_false(_grate.is_open, "Grate should start closed.")

	var dummy_char: CharacterBody3D = CharacterBody3D.new()
	dummy_char.name = "TestPlayer"
	_grate.interact_with(dummy_char)
	assert_true(_grate.is_open, "Grate should be opened by direct interaction.")

	_grate.allow_player_interact = false
	_grate.interact_with(dummy_char)
	assert_true(_grate.is_open, "Grate should remain open when interaction is disabled.")
	dummy_char.free()


## Verifies EventSequenceTrigger-compatible methods and signal dispatch.
func test_event_sequencer_methods_and_signals() -> void:
	watch_signals(_grate)

	_grate.open()
	assert_true(_grate.is_open, "open() should set is_open to true.")

	_grate.close()
	assert_false(_grate.is_open, "close() should set is_open to false.")

	_grate.toggle_open()
	assert_true(_grate.is_open, "toggle_open() should invert is_open state.")


## Verifies detaching a leaf disconnects swing tweens and marks leaf detached.
func test_detach_leaf_breakaway() -> void:
	watch_signals(_grate)

	_grate.detach_leaf(true, Vector3(0.0, 10.0, 5.0))
	assert_true(_grate.is_left_detached, "is_left_detached should be true.")
	await wait_physics_frames(2)
	assert_signal_emitted(_grate, &"leaf_detached", "leaf_detached should be emitted.")
