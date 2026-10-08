## GUT test validating the audio pool manager class.
extends GutTest

## Local type definition for the unexported audio pool script.
const AudioPool = preload("res://core/audio_pool.gd")

## The name identifying this GUT test suite.
var test_name: String = "Test AudioPool"

## The instance of the audio pool being tested.
var _audio_pool: AudioPool = null


## Prepares a new audio pool instance before running each test case.
func before_each() -> void:
	print("Setting up AudioPool for tests...")
	_audio_pool = AudioPool.new()
	add_child_autoqfree(_audio_pool)


## Creates a synthetic [AudioStreamWAV] for non-disk audio testing.
func _create_dummy_stream() -> AudioStreamWAV:
	print("Test: Generating dummy AudioStreamWAV...")
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	stream.data = PackedByteArray([0, 0, 0, 0])
	return stream


## Verifies pre-allocation and default bus setups for 2D and 3D pools.
func test_ready_allocates_pools() -> void:
	print("Testing AudioPool pools allocation...")
	var players_2d: Array[Node] = _audio_pool.find_children("*", "AudioStreamPlayer", false, false)
	var players_3d: Array[Node] = _audio_pool.find_children(
		"*", "AudioStreamPlayer3D", false, false
	)

	assert_eq(players_2d.size(), AudioPool.POOL_SIZE_2D, "2D pool size check")
	assert_eq(players_3d.size(), AudioPool.POOL_SIZE_3D, "3D pool size check")

	if not players_2d.is_empty():
		var p2d: AudioStreamPlayer = players_2d[0]
		assert_not_null(p2d, "Pool 2D elements should not be null")
		assert_eq(p2d.bus, &"SFX", "Bus should be set to SFX")

	if not players_3d.is_empty():
		var p3d: AudioStreamPlayer3D = players_3d[0]
		assert_not_null(p3d, "Pool 3D elements should not be null")
		assert_eq(p3d.bus, &"SFX", "Bus should be set to SFX")


## Tests retrieving 2D audio stream players from the pool.
func test_get_pooled_player_2d() -> void:
	print("Testing AudioPool.get_pooled_player_2d()...")
	var player1: AudioStreamPlayer = _audio_pool.get_pooled_player_2d()
	var player2: AudioStreamPlayer = _audio_pool.get_pooled_player_2d()
	assert_not_null(player1, "Should return an AudioStreamPlayer")
	assert_ne(player1, player2, "Consecutive calls should return different")


## Tests retrieving 3D audio stream players from the pool.
func test_get_pooled_player_3d() -> void:
	print("Testing AudioPool.get_pooled_player_3d()...")
	var player1: AudioStreamPlayer3D = _audio_pool.get_pooled_player_3d()
	var player2: AudioStreamPlayer3D = _audio_pool.get_pooled_player_3d()
	assert_not_null(player1, "Should return an AudioStreamPlayer3D")
	assert_ne(player1, player2, "Consecutive calls should return different")


## Tests playing 2D audio streams with circular allocation.
func test_play_sfx_2d() -> void:
	print("Testing AudioPool.play_sfx_2d()...")
	var dummy_stream: AudioStreamWAV = _create_dummy_stream()
	var player: AudioStreamPlayer = _audio_pool.play_sfx_2d(dummy_stream, &"SFX")
	assert_not_null(player, "Player should not be null when stream is valid")
	assert_eq(player.stream, dummy_stream, "Player stream should match input")
	assert_eq(player.bus, &"SFX", "Player bus should match requested bus")

	var null_player: AudioStreamPlayer = _audio_pool.play_sfx_2d(null, &"SFX")
	assert_null(null_player, "Null stream should return null player")


## Tests playing 3D audio streams with spatial placement.
func test_play_sfx_3d() -> void:
	print("Testing AudioPool.play_sfx_3d()...")
	var dummy_stream: AudioStreamWAV = _create_dummy_stream()
	var target_pos: Vector3 = Vector3(5.0, 1.0, -3.0)
	var player: AudioStreamPlayer3D = _audio_pool.play_sfx_3d(dummy_stream, target_pos, &"SFX")
	assert_not_null(player, "3D player should not be null when stream valid")
	assert_eq(player.stream, dummy_stream, "3D player stream should match")
	assert_eq(player.global_position, target_pos, "3D player position match")

	var null_player: AudioStreamPlayer3D = _audio_pool.play_sfx_3d(null, target_pos, &"SFX")
	assert_null(null_player, "Null stream should return null player")
