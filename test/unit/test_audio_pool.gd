## Unit tests for [AudioPool] validating player pre-allocation and recycled playback.
class_name TestAudioPool
extends GutTest

const AUDIO_POOL_SCRIPT: GDScript = preload("res://core/audio_pool.gd")

## The [AudioPool] node instance under test.
var _audio_pool: Node = null

## Reusable mock audio stream for playback verification.
var _dummy_stream: AudioStreamWAV = null


## Prepares test audio pool and dummy stream before each test execution.
func before_each() -> void:
	print("TestAudioPool: Setting up test environment.")
	_dummy_stream = AudioStreamWAV.new()

	_audio_pool = AUDIO_POOL_SCRIPT.new() as Node
	add_child_autoqfree(_audio_pool)


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestAudioPool: Tearing down test environment.")
	_audio_pool = null
	_dummy_stream = null


## Verifies default pool capacities and player node naming conventions.
func test_pool_allocation_capacities() -> void:
	print("TestAudioPool: test_pool_allocation_capacities() executing.")
	var pool_2d: Array = _audio_pool.get("_pool_2d") as Array
	var pool_3d: Array = _audio_pool.get("_pool_3d") as Array

	assert_not_null(pool_2d, "2D pool array should be initialized.")
	assert_eq(pool_2d.size(), 16, "2D pool capacity should default to 16 players.")

	assert_not_null(pool_3d, "3D pool array should be initialized.")
	assert_eq(pool_3d.size(), 32, "3D pool capacity should default to 32 players.")

	var first_player: AudioStreamPlayer = pool_2d[0] as AudioStreamPlayer
	assert_eq(first_player.name, "AudioPool2D_0", "First 2D player name format should match.")
	assert_eq(first_player.bus, &"SFX", "Players should default to SFX bus.")


## Verifies circular index slot rotation on repeated 2D play requests.
func test_play_sfx_2d_rotates_slots() -> void:
	print("TestAudioPool: test_play_sfx_2d_rotates_slots() executing.")
	var p1: AudioStreamPlayer = _audio_pool.call("play_sfx_2d", _dummy_stream, &"SFX")
	assert_not_null(p1, "First 2D play request should return active player.")
	assert_eq(p1.stream, _dummy_stream, "Player stream should be assigned.")

	var p2: AudioStreamPlayer = _audio_pool.call("play_sfx_2d", _dummy_stream, &"SFX")
	assert_not_null(p2, "Second 2D play request should return next player.")
	assert_ne(p1, p2, "Sequential play requests must rotate to distinct pooled players.")


## Verifies 3D position and bus assignment on spatial play requests.
func test_play_sfx_3d_spatial_properties() -> void:
	print("TestAudioPool: test_play_sfx_3d_spatial_properties() executing.")
	var target_pos: Vector3 = Vector3(12.0, -4.0, 7.5)
	var player_3d: AudioStreamPlayer3D = _audio_pool.call(
		"play_sfx_3d", _dummy_stream, target_pos, &"SFX"
	)

	assert_not_null(player_3d, "3D play request should return active player.")
	assert_eq(player_3d.global_position, target_pos, "3D player must match target coordinates.")
	assert_eq(player_3d.stream, _dummy_stream, "Stream resource must be assigned.")


## Verifies null audio stream calls return null safely.
func test_null_stream_handling() -> void:
	print("TestAudioPool: test_null_stream_handling() executing.")
	var null_2d: AudioStreamPlayer = _audio_pool.call("play_sfx_2d", null, &"SFX")
	assert_null(null_2d, "play_sfx_2d with null stream must return null.")

	var null_3d: AudioStreamPlayer3D = _audio_pool.call("play_sfx_3d", null, Vector3.ZERO, &"SFX")
	assert_null(null_3d, "play_sfx_3d with null stream must return null.")


## Verifies manual pooled player retrieval advances circular pointers.
func test_get_pooled_player_retrieval() -> void:
	print("TestAudioPool: test_get_pooled_player_retrieval() executing.")
	var p2d_a: AudioStreamPlayer = _audio_pool.call("get_pooled_player_2d")
	var p2d_b: AudioStreamPlayer = _audio_pool.call("get_pooled_player_2d")
	assert_not_null(p2d_a, "Idle 2D player retrieval should succeed.")
	assert_not_null(p2d_b, "Second 2D player retrieval should succeed.")
	assert_ne(p2d_a, p2d_b, "Retrieved players must advance circularly.")

	var p3d_a: AudioStreamPlayer3D = _audio_pool.call("get_pooled_player_3d")
	var p3d_b: AudioStreamPlayer3D = _audio_pool.call("get_pooled_player_3d")
	assert_not_null(p3d_a, "Idle 3D player retrieval should succeed.")
	assert_not_null(p3d_b, "Second 3D player retrieval should succeed.")
	assert_ne(p3d_a, p3d_b, "Retrieved 3D players must advance circularly.")
