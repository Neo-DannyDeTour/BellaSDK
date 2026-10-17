## Unit test suite validating AudioManager sfx throttling and playback limits.
extends GutTest

const AUDIO_MANAGER_SCRIPT: GDScript = preload("res://core/audio_manager.gd")

## AudioManager node instance under test.
var _audio_manager: Node


## Initializes a clean AudioManager instance before each test.
func before_each() -> void:
	print("Setting up AudioManager instance for testing.")
	_audio_manager = AUDIO_MANAGER_SCRIPT.new() as Node
	add_child_autofree(_audio_manager)


## Cleans up AudioManager instance after each test.
func after_each() -> void:
	print("Tearing down AudioManager test instance.")
	_audio_manager = null


## Verifies that AudioManager sets process mode to ALWAYS on ready.
func test_ready_process_mode() -> void:
	print("Testing AudioManager process_mode on initialization.")
	assert_eq(
		_audio_manager.process_mode,
		Node.PROCESS_MODE_ALWAYS,
		"AudioManager process mode should be PROCESS_MODE_ALWAYS."
	)


## Verifies null stream handling in 2D playback.
func test_play_sfx_2d_throttled_null_stream() -> void:
	print("Testing play_sfx_2d_throttled with null stream.")
	var result: AudioStreamPlayer = (
		_audio_manager.call("play_sfx_2d_throttled", null, &"SFX", Vector2(0.95, 1.05), 4)
		as AudioStreamPlayer
	)
	assert_null(result, "2D playback with null stream should return null.")


## Verifies null stream handling in 3D playback.
func test_play_sfx_3d_throttled_null_stream() -> void:
	print("Testing play_sfx_3d_throttled with null stream.")
	var result: AudioStreamPlayer3D = (
		_audio_manager.call(
			"play_sfx_3d_throttled", null, Vector3.ZERO, &"SFX", Vector2(0.95, 1.05), 4
		)
		as AudioStreamPlayer3D
	)
	assert_null(result, "3D playback with null stream should return null.")


## Verifies finished callback decrements active 2D playback counts correctly.
func test_on_player_2d_finished_decrements_count() -> void:
	print("Testing 2D finished callback count decrement.")
	var counts: Dictionary = _audio_manager.get("_active_sfx_counts")
	var key: StringName = &"res://test_stream.wav"
	counts[key] = 3
	_audio_manager.call("_on_player_2d_finished", null, key)

	var updated_counts: Dictionary = _audio_manager.get("_active_sfx_counts")
	assert_eq(
		updated_counts.get(key, 0),
		2,
		"Active SFX count should decrement from 3 to 2 after finishing."
	)


## Verifies finished callback decrements active 3D playback counts correctly.
func test_on_player_3d_finished_decrements_count() -> void:
	print("Testing 3D finished callback count decrement.")
	var counts: Dictionary = _audio_manager.get("_active_sfx_counts")
	var key: StringName = &"res://test_stream_3d.wav"
	counts[key] = 1
	_audio_manager.call("_on_player_3d_finished", null, key)

	var updated_counts: Dictionary = _audio_manager.get("_active_sfx_counts")
	assert_eq(
		updated_counts.get(key, 0),
		0,
		"Active SFX count should decrement from 1 to 0 after finishing."
	)
