extends GutTest
## Unit tests for [CinderBlock] pickable prop setup, layers, mass, and impact signal.
class_name TestCinderBlock

## Instantiated [CinderBlock] test fixture.
var _cinder_block: CinderBlock = null


## Instantiates cinder block scene before each test run.
func before_each() -> void:
	print("TestCinderBlock: Setting up test fixture.")
	var sc: PackedScene = load("res://interactables/cinder_block/cinder_block.tscn") as PackedScene
	_cinder_block = sc.instantiate() as CinderBlock
	add_child(_cinder_block)


## Frees test fixture after each test run.
func after_each() -> void:
	print("TestCinderBlock: Tearing down test fixture.")
	if is_instance_valid(_cinder_block):
		_cinder_block.queue_free()
	_cinder_block = null


## Verifies mandatory child components, mesh, and collision shape.
func test_initial_hierarchy_and_components() -> void:
	assert_not_null(_cinder_block, "CinderBlock instance should be valid.")
	assert_true(_cinder_block is PickableObject, "CinderBlock must inherit PickableObject.")
	assert_not_null(_cinder_block.mesh_instance, "mesh_instance should be assigned.")
	assert_not_null(_cinder_block.collision_shape, "collision_shape should be assigned.")

	var interact_comp: Node = _cinder_block.get_node_or_null("InteractComponent")
	assert_not_null(interact_comp, "InteractComponent should be present.")
	assert_true(interact_comp is InteractComponent, "Must be instance of InteractComponent.")

	var highlight_comp: Node = _cinder_block.get_node_or_null("HighlightComponent")
	assert_not_null(highlight_comp, "HighlightComponent should be present.")
	assert_true(highlight_comp is HighlightComponent, "Must be instance of HighlightComponent.")


## Verifies mass, heavy carry threshold, and layer bitmasks.
func test_physics_and_layers() -> void:
	assert_eq(_cinder_block.mass, 17.0, "CinderBlock mass must be 17.0 kg.")
	assert_eq(
		_cinder_block.collision_layer,
		CollisionLayers.MASK_INTERACTIVE,
		"Must be on Layer 3 Interactive."
	)
	assert_eq(
		_cinder_block.mesh_instance.layers,
		CollisionLayers.RENDER_MASK_INTERACTIVE,
		"Mesh must render on Layer 3 Interactive."
	)


## Verifies picking and throwing interfaces expected by player interaction component.
func test_pickable_interfaces() -> void:
	assert_true(_cinder_block.has_method(&"pick_up"), "Must implement pick_up.")
	assert_true(_cinder_block.has_method(&"throw"), "Must implement throw.")
	assert_true(_cinder_block.has_method(&"drop"), "Must implement drop.")
	assert_true(
		_cinder_block.has_method(&"apply_throw_impulse"), "Must implement apply_throw_impulse."
	)
