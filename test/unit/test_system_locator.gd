## Unit tests verifying [SystemLocator] static singleton resolution and caching behavior.
class_name TestSystemLocator
extends GutTest

## The [SystemLocator] under test.
var locator: SystemLocator = null


## Mock window providing isolated node retrieval.
class MockWindow:
	extends Window

	## Lifecycle initialization for mock window.
	func _ready() -> void:
		pass


## Sets up environment before each test.
func before_each() -> void:
	print("TestSystemLocator: Setup test environment.")
	SystemLocator.clear_cache()
	locator = SystemLocator.new()
	add_child_autofree(locator)


## Cleans up environment after each test.
func after_each() -> void:
	print("TestSystemLocator: Teardown test environment.")
	SystemLocator.clear_cache()


## Verifies _ready calls resolve_all_systems which safely handles missing root nodes.
func test_ready_resolves_all_systems_safely() -> void:
	print("TestSystemLocator: Testing _ready safety without target nodes.")
	var mock_window: MockWindow = MockWindow.new()
	add_child_autofree(mock_window)
	SystemLocator.clear_cache()
	SystemLocator.root_override = mock_window

	locator._ready()
	assert_null(SystemLocator._tts_manager, "TTSManager should be null if not in tree.")
	assert_null(SystemLocator._keycard_system, "KeycardSystem should be null if not in tree.")
	assert_null(SystemLocator._graphics_manager, "GraphicsManager should be null if not in tree.")


## Verifies custom service registration and retrieval logic.
func test_register_and_get_service() -> void:
	print("TestSystemLocator: Testing custom service registration.")
	var custom_service: Node = Node.new()
	var service_name: StringName = "CustomService"

	SystemLocator.register_service(service_name, custom_service)
	var retrieved: Node = SystemLocator.get_service(service_name)

	assert_eq(retrieved, custom_service, "Should retrieve the exact registered service node.")
	custom_service.free()


## Verifies dynamic fallback logic for un-cached requested services.
func test_get_service_dynamic_fallback() -> void:
	print("TestSystemLocator: Testing dynamic service fallback from root.")
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not is_instance_valid(tree):
		pass_test("No SceneTree available for dynamic root fallback test. Skipping.")
		return

	var root: Window = tree.root
	var mock_service: Node = Node.new()
	mock_service.name = "DynamicFallbackService"
	root.add_child(mock_service)

	var retrieved: Node = SystemLocator.get_service("DynamicFallbackService")
	assert_eq(retrieved, mock_service, "Should locate mock service dynamically from root.")

	mock_service.queue_free()


## Verifies clear_cache completely resets static state.
func test_clear_cache() -> void:
	print("TestSystemLocator: Testing static cache clearing.")
	var dummy_node: Node = Node.new()
	SystemLocator._tts_manager = dummy_node
	SystemLocator._keycard_system = dummy_node
	SystemLocator._graphics_manager = dummy_node
	SystemLocator.register_service("Test", dummy_node)

	SystemLocator.clear_cache()

	assert_null(SystemLocator._tts_manager, "TTS cache should be null.")
	assert_null(SystemLocator._keycard_system, "Keycard cache should be null.")
	assert_null(SystemLocator._graphics_manager, "Graphics cache should be null.")
	var retrieved: Node = SystemLocator.get_service("Test")
	assert_null(retrieved, "Service registry should be empty.")

	dummy_node.free()
