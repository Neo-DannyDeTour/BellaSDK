class_name TestBellaArchitecture
extends GutTest
## Comprehensive GUT test suite validating all 7 BellaSDK core architecture layers.

## Tracking counters capturing signal emissions during test execution.
var _signal_counts: Dictionary[StringName, int] = {}


## Test lifecycle setup clearing tracking counters before each test run.
func before_each() -> void:
	_signal_counts.clear()


## Test Layer 1: Utilities static math, grid snapping, and distance tests.
func test_layer1_utilities_math_and_grid() -> void:
	print("TestBellaArchitecture: Testing Layer 1 - Utilities.")
	var origin: Vector3 = Vector3(1.23, 4.56, 7.89)
	var snapped_pos: Vector3 = Utilities.snap_to_grid_3d(origin, 0.5)
	assert_eq(snapped_pos, Vector3(1.0, 4.5, 8.0), "Grid snap should align to 0.5 units.")

	var raw_angle: float = 4.0 * PI
	var norm_angle: float = Utilities.normalize_angle(raw_angle)
	assert_almost_eq(norm_angle, 0.0, 0.001, "Angle normalization must wrap to [-PI, PI].")

	var pos_a: Vector3 = Vector3(0.0, 0.0, 0.0)
	var pos_b: Vector3 = Vector3(3.0, 0.0, 4.0)
	assert_true(
		Utilities.is_within_distance_3d(pos_a, pos_b, 5.0),
		"3-4-5 triangle hypotenuse should evaluate <= 5.0."
	)
	assert_false(
		Utilities.is_within_distance_3d(pos_a, pos_b, 4.9),
		"Distance 5.0 should exceed 4.9 max check."
	)


## Test Layer 2: Deterministic RNG seeding and global runtime cache.
func test_layer2_global_rng_determinism() -> void:
	print("TestBellaArchitecture: Testing Layer 2 - Global State & RNG.")
	var global_node: Node = get_node_or_null("/root/Global")
	if not is_instance_valid(global_node):
		var global_script: GDScript = load("res://core/global.gd")
		if is_instance_valid(global_script):
			global_node = global_script.new()
			global_node.name = "Global"
			add_child_autofree(global_node)

	assert_not_null(global_node, "Global autoload must be registered in /root/Global.")

	if not is_instance_valid(global_node):
		return

	global_node.call("set_game_seed", 1337)
	var rng: RandomNumberGenerator = global_node.get("rng") as RandomNumberGenerator
	var val_a: float = rng.randf()

	global_node.call("set_game_seed", 1337)
	var val_b: float = rng.randf()
	assert_eq(val_a, val_b, "Identical seeds must produce deterministic random numbers.")

	global_node.call("cache_value", &"difficulty_level", 3)
	var cached: Variant = global_node.call("get_cached_value", &"difficulty_level", 1)
	assert_eq(int(cached), 3, "Transient cache must return stored runtime values.")

	global_node.call("clear_cache")
	var fallback: Variant = global_node.call("get_cached_value", &"difficulty_level", 99)
	assert_eq(int(fallback), 99, "Cleared cache must return fallback value.")


## Test Layer 3: Decoupled Events signal routing and signature arity.
func test_layer3_events_bus_lifecycle() -> void:
	print("TestBellaArchitecture: Testing Layer 3 - Events Signal Bus.")
	assert_not_null(Events, "Events autoload must exist in scene tree.")

	var on_wave_started: Callable = func(wave_num: int) -> void:
		_signal_counts[&"wave_started"] = _signal_counts.get(&"wave_started", 0) + 1
		assert_eq(wave_num, 42, "Wave number parameter should match emitted value.")

	var on_player_died: Callable = func(death_state: int) -> void:
		_signal_counts[&"player_died"] = _signal_counts.get(&"player_died", 0) + 1
		assert_eq(death_state, 1, "Death state parameter should match emitted value.")

	Events.wave_started.connect(on_wave_started, CONNECT_ONE_SHOT)
	Events.player_died.connect(on_player_died, CONNECT_ONE_SHOT)

	Events.wave_started.emit(42)
	Events.player_died.emit(1)

	assert_eq(_signal_counts.get(&"wave_started", 0), 1, "wave_started signal must emit once.")
	assert_eq(_signal_counts.get(&"player_died", 0), 1, "player_died signal must emit once.")


## Test Layer 4: Static Types enums, string lookups, and layer bitmasks.
func test_layer4_types_and_collision_masks() -> void:
	print("TestBellaArchitecture: Testing Layer 4 - Types & Enums.")
	assert_eq(Types.item_category_to_string(Types.ItemCategory.WEAPON), "Weapon")
	assert_eq(Types.item_category_to_string(Types.ItemCategory.KEYCARD), "Keycard")
	assert_eq(Types.faction_to_string(Types.Faction.ENEMY), "Hostile")
	assert_eq(Types.damage_type_to_string(Types.DamageType.FIRE), "Thermal")

	assert_eq(Types.MASK_ENVIRONMENT, 1 << 0, "Environment must be bit 0.")
	assert_eq(Types.MASK_PLAYER, 1 << 1, "Player must be bit 1.")
	assert_eq(Types.MASK_INTERACTIVE, 1 << 2, "Interactive must be bit 2.")
	assert_eq(Types.MASK_ENEMIES, 1 << 4, "Enemies must be bit 4.")

	var solid_mask: int = Types.MASK_SOLID_WORLD
	assert_true(bool(solid_mask & Types.MASK_ENVIRONMENT), "Solid world must include environment.")
	assert_true(bool(solid_mask & Types.MASK_INTERACTIVE), "Solid world must include interactive.")
	assert_false(bool(solid_mask & Types.MASK_ENEMIES), "Solid world must not include enemies.")


## Test Layer 5: ReferenceData palette defaults and category icon fallbacks.
func test_layer5_reference_data_resolution() -> void:
	print("TestBellaArchitecture: Testing Layer 5 - ReferenceData.")
	var ref_data: ReferenceData = ReferenceData.new()
	assert_not_null(ref_data, "ReferenceData must instantiate successfully.")

	assert_almost_eq(ref_data.primary_color.r, 0.12, 0.01, "Primary color red should be 0.12.")
	assert_almost_eq(ref_data.success_color.g, 0.85, 0.01, "Success color green should be 0.85.")

	var resolved_icon: Texture2D = ref_data.get_category_icon(Types.ItemCategory.KEYCARD)
	assert_null(resolved_icon, "Unconfigured icon must return null without crashing.")


## Test Layer 6: AudioManager concurrency throttling and instance capping.
func test_layer6_audio_manager_concurrency_limits() -> void:
	print("TestBellaArchitecture: Testing Layer 6 - AudioManager Throttling.")
	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	if not is_instance_valid(audio_mgr):
		var audio_script: GDScript = load("res://core/audio_manager.gd")
		if is_instance_valid(audio_script):
			audio_mgr = audio_script.new()
			audio_mgr.name = "AudioManager"
			add_child_autofree(audio_mgr)

	assert_not_null(audio_mgr, "AudioManager autoload must be registered in /root/AudioManager.")

	if not is_instance_valid(audio_mgr):
		return

	var mock_stream: AudioStreamGenerator = AudioStreamGenerator.new()
	mock_stream.resource_path = "res://tests/mock_hit.wav"

	var active_players: Array[AudioStreamPlayer] = []
	for i: int in range(6):
		var p: AudioStreamPlayer = (
			audio_mgr.call("play_sfx_2d_throttled", mock_stream, &"SFX", Vector2.ONE, 4)
			as AudioStreamPlayer
		)
		if is_instance_valid(p):
			active_players.append(p)

	assert_eq(active_players.size(), 4, "AudioManager must throttle sound playback at limit 4.")


## Test Integration: WaveSpawner emitting wave_started, enemy_spawned, and wave_completed.
func test_wave_spawner_lifecycle_integration() -> void:
	print("TestBellaArchitecture: Testing WaveSpawner lifecycle integration.")
	var spawner: WaveSpawner = WaveSpawner.new()
	spawner.name = "TestWaveSpawner"
	spawner.total_waves = 1
	spawner.base_enemy_count = 2
	spawner.min_spawn_interval = 0.01
	spawner.max_spawn_interval = 0.02

	var dummy_enemy_script: GDScript = GDScript.new()
	dummy_enemy_script.source_code = "extends Node3D\nfunc _ready() -> void:\n\tpass\n"
	dummy_enemy_script.reload()

	var dummy_scene: PackedScene = PackedScene.new()
	var root_dummy: Node3D = Node3D.new()
	root_dummy.set_script(dummy_enemy_script)
	dummy_scene.pack(root_dummy)
	root_dummy.free()
	spawner.enemy_scene = dummy_scene

	add_child_autofree(spawner)

	var spawned_enemies: Array[Node3D] = []
	var on_enemy_spawned: Callable = func(enemy: Node3D) -> void: spawned_enemies.append(enemy)

	Events.enemy_spawned.connect(on_enemy_spawned)

	spawner.start_spawner()
	await wait_seconds(0.2)

	assert_eq(spawned_enemies.size(), 2, "Spawner must spawn all 2 enemies for wave 1.")

	var wave_completed_emitted: bool = false
	var on_wave_completed: Callable = func(_wave: int) -> void: wave_completed_emitted = true

	Events.wave_completed.connect(on_wave_completed, CONNECT_ONE_SHOT)

	for enemy: Node3D in spawned_enemies:
		Events.enemy_killed.emit(enemy, null)
		enemy.queue_free()

	await wait_seconds(0.2)
	assert_true(wave_completed_emitted, "wave_completed must emit when all enemies are slain.")

	if Events.enemy_spawned.is_connected(on_enemy_spawned):
		Events.enemy_spawned.disconnect(on_enemy_spawned)
