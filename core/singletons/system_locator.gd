## Central service locator caching global autoload references for zero-allocation access.
class_name SystemLocator
extends Node

## Cached reference to global Text-To-Speech manager node.
static var _tts_manager: Node = null

## Cached reference to global keycard inventory manager node.
static var _keycard_system: Node = null

## Cached reference to global graphics settings and benchmark manager node.
static var _graphics_manager: Node = null

## Generic registry storing dynamic service references by [StringName].
static var _services: Dictionary = {}

## Optional root window override used to isolate tests from engine autoloads.
static var root_override: Window = null


## Initializes the service locator and pre-caches available root singletons.
func _ready() -> void:
	print("SystemLocator: Initializing service locator singleton.")
	resolve_all_systems()


## Pre-caches known engine singletons from scene tree root.
static func resolve_all_systems() -> void:
	print("SystemLocator: Pre-caching core root singletons.")
	get_tts_manager()
	get_keycard_system()
	get_graphics_manager()


## Registers a custom service [param service_instance] under [param service_name].
static func register_service(service_name: StringName, service_instance: Node) -> void:
	print("SystemLocator: Registering service -> ", service_name)
	_services[service_name] = service_instance


## Returns the registered service [Node] mapped to [param service_name].
static func get_service(service_name: StringName) -> Node:
	print("SystemLocator: Resolving service -> ", service_name)
	var service: Node = (
		_services.get(service_name, null) if _services.get(service_name, null) is Node else null
	)
	if not is_instance_valid(service):
		var root: Window = _get_root_window()
		if is_instance_valid(root) and root.has_node(NodePath(service_name)):
			service = root.get_node(NodePath(service_name))
			_services[service_name] = service
	return service


## Returns the cached [TTSManager] node or null if unavailable.
static func get_tts_manager() -> Node:
	if is_instance_valid(_tts_manager):
		return _tts_manager
	print("SystemLocator: Resolving TTSManager instance.")
	var root: Window = _get_root_window()
	if is_instance_valid(root) and root.has_node("TTSManager"):
		_tts_manager = root.get_node("TTSManager")
	return _tts_manager


## Returns the cached [KeycardSystem] node or null if unavailable.
static func get_keycard_system() -> Node:
	if is_instance_valid(_keycard_system):
		return _keycard_system
	print("SystemLocator: Resolving KeycardSystem instance.")
	var root: Window = _get_root_window()
	if is_instance_valid(root) and root.has_node("KeycardSystem"):
		_keycard_system = root.get_node("KeycardSystem")
	return _keycard_system


## Returns the cached [GraphicsManager] node or null if unavailable.
static func get_graphics_manager() -> Node:
	if is_instance_valid(_graphics_manager):
		return _graphics_manager
	print("SystemLocator: Resolving GraphicsManager instance.")
	var root: Window = _get_root_window()
	if is_instance_valid(root) and root.has_node("GraphicsManager"):
		_graphics_manager = root.get_node("GraphicsManager")
	return _graphics_manager


## Clears all cached singleton and dynamic service references.
static func clear_cache() -> void:
	print("SystemLocator: Clearing all cached system references.")
	_tts_manager = null
	_keycard_system = null
	_graphics_manager = null
	_services.clear()
	root_override = null


## Helper resolving root [Window] safely across static scopes.
static func _get_root_window() -> Window:
	if is_instance_valid(root_override):
		return root_override
	var tree: SceneTree = Engine.get_main_loop() if Engine.get_main_loop() is SceneTree else null
	if is_instance_valid(tree):
		return tree.root
	return null
