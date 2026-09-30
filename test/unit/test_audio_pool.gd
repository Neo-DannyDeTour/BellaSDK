extends GutTest

## A GUT test script for the [AudioPool] class validating the pre-allocated audio stream manager.
var test_name: String = "Test AudioPool"

## The instance of the AudioPool being tested.
var _audio_pool: Node = null


func before_each() -> void:
	print("Setting up AudioPool for tests...")
	_audio_pool = load("res://core/audio_pool.gd").new()
	add_child_autoqfree(_audio_pool)


func test_ready_allocates_pools() -> void:
	print("Testing AudioPool pools allocation...")
	var pool_2d: Array = _audio_pool.get("_pool_2d")
	var pool_3d: Array = _audio_pool.get("_pool_3d")

	assert_eq(pool_2d.size(), _audio_pool.get("POOL_SIZE_2D"), "2D pool should be fully allocated")
	assert_eq(pool_3d.size(), _audio_pool.get("POOL_SIZE_3D"), "3D pool should be fully allocated")

	if pool_2d.size() > 0:
		var p2d: AudioStreamPlayer = pool_2d[0]
		assert_not_null(p2d, "Pool 2D elements should not be null")
		assert_eq(p2d.bus, &"SFX", "Bus should be set to SFX")

	if pool_3d.size() > 0:
		var p3d: AudioStreamPlayer3D = pool_3d[0]
		assert_not_null(p3d, "Pool 3D elements should not be null")
		assert_eq(p3d.bus, &"SFX", "Bus should be set to SFX")


func test_get_pooled_player_2d() -> void:
	print("Testing AudioPool.get_pooled_player_2d()...")
	var player1: AudioStreamPlayer = _audio_pool.get_pooled_player_2d()
	var player2: AudioStreamPlayer = _audio_pool.get_pooled_player_2d()
	assert_not_null(player1, "Should return an AudioStreamPlayer")
	assert_ne(player1, player2, "Consecutive calls should return different players")

	var current_index: int = _audio_pool.get("_index_2d")
	assert_eq(current_index, 2, "Index should advance circularly")


func test_get_pooled_player_3d() -> void:
	print("Testing AudioPool.get_pooled_player_3d()...")
	var player1: AudioStreamPlayer3D = _audio_pool.get_pooled_player_3d()
	var player2: AudioStreamPlayer3D = _audio_pool.get_pooled_player_3d()
	assert_not_null(player1, "Should return an AudioStreamPlayer3D")
	assert_ne(player1, player2, "Consecutive calls should return different players")

	var current_index: int = _audio_pool.get("_index_3d")
	assert_eq(current_index, 2, "Index should advance circularly")
