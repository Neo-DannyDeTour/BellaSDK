#class_name Global
extends Node
## Global game state coordinator, deterministic RNG provider, and scene hook registry.

## Emitted when primary scene reference registers or unregisters. Passes [param main_node].
@warning_ignore("unused_signal")
signal main_scene_registered(main_node: Node)

## Emitted when deterministic game seed changes. Passes [param new_seed].
@warning_ignore("unused_signal")
signal game_seed_changed(new_seed: int)

## Global deterministic random number generator.
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Active primary root/main level scene reference.
var main: Node = null:
	set = set_main

## Global seed used for deterministic procedural generation.
var current_seed: int = 0:
	set = set_game_seed

## In-memory runtime data cache for arbitrary cross-scene parameters.
var cached_data: Dictionary[StringName, Variant] = {}

## Total play session active time in seconds.
var session_elapsed_seconds: float = 0.0


## Initializes random number generator and configures persistent processing.
func _ready() -> void:
	print("[Global] Global Autoload initialized.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	seed_rng_from_time()


## Accumulates total game session running time each frame.
func _process(delta: float) -> void:
	session_elapsed_seconds += delta


## Sets active main level scene node reference and notifies listeners.
func set_main(node: Node) -> void:
	main = node
	if is_instance_valid(main):
		print("[Global] Registered main scene reference: ", main.name)
		if not main.tree_exited.is_connected(_on_main_tree_exited):
			main.tree_exited.connect(_on_main_tree_exited)
		main_scene_registered.emit(main)
	else:
		main_scene_registered.emit(null)


## Clears main scene reference when the registered node exits scene tree.
func _on_main_tree_exited() -> void:
	print("[Global] Active main scene exited tree. Clearing reference.")
	main = null
	main_scene_registered.emit(null)


## Updates master seed value and synchronizes internal [RandomNumberGenerator].
func set_game_seed(seed_val: int) -> void:
	current_seed = seed_val
	rng.seed = seed_val
	print("[Global] Deterministic seed set to: ", current_seed)
	game_seed_changed.emit(current_seed)


## Re-seeds the internal [RandomNumberGenerator] using system OS timestamp.
func seed_rng_from_time() -> void:
	var time_seed: int = int(Time.get_unix_time_from_system())
	print("[Global] Seeding RNG from system clock: ", time_seed)
	set_game_seed(time_seed)


## Caches a runtime [param value] identified by [param key].
func cache_value(key: StringName, value: Variant) -> void:
	cached_data[key] = value
	print("[Global] Cached runtime value for key: ", key)


## Retrieves cached value for [param key], or returns [param default_val].
func get_cached_value(key: StringName, default_val: Variant = null) -> Variant:
	return cached_data.get(key, default_val)


## Flushes all entries stored inside transient runtime cache.
func clear_cache() -> void:
	cached_data.clear()
	print("[Global] Cleared global runtime cache.")
