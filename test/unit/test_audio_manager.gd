## Unit tests for [AudioManager] validating concurrency throttling and active counter tracking.
class_name TestAudioManager
extends GutTest

const AUDIO_MANAGER_SCRIPT: GDScript = preload("res://core/audio_manager.gd")

## The [AudioManager] node instance under test.
var _audio_manager: Node = null

## Reusable mock audio stream for throttling tests.
var _dummy_stream: AudioStreamWAV = null


## Allocates persistent mock audio stream before entire test run.
func before_all() -> void:
	_dummy_stream = AudioStreamWAV.new()
	_dummy_stream.take_over_path("res://SFX/mock_sound.wav")


## Deallocates mock audio stream after entire test run.
func after_all() -> void:
	_dummy_stream = null


## Prepares test audio manager before each test execution.
func before_each() -> void:
	print("TestAudioManager: Setting up test environment.")
	_audio_manager = AUDIO_MANAGER_SCRIPT.new()
	add_child_autoqfree(_audio_manager)


## Clears local instance references after each test execution.
func after_each() -> void:
	print("TestAudioManager: Tearing down test environment.")
	_audio_manager = null


## Verifies null audio streams return null cleanly.
func test_null_stream_returns_null() -> void:
	print("TestAudioManager: test_null_stream_returns_null() executing.")
	var res_2d: AudioStreamPlayer = _audio_manager.call(
		&"play_sfx_2d_throttled", null, &"SFX", Vector2(1.0, 1.0), 4
	)
	assert_null(res_2d, "Null 2D stream must return null.")

	var res_3d: AudioStreamPlayer3D = _audio_manager.call(
		&"play_sfx_3d_throttled", null, Vector3.ZERO, &"SFX", Vector2(1.0, 1.0), 4
	)
	assert_null(res_3d, "Null 3D stream must return null.")


## Verifies 2D playback throttling suppresses sounds exceeding concurrency limit.
func test_concurrency_limit_suppression_2d() -> void:
	print("TestAudioManager: test_concurrency_limit_suppression_2d() executing.")
	var p1: AudioStreamPlayer = _audio_manager.call(
		&"play_sfx_2d_throttled", _dummy_stream, &"SFX", Vector2(1.0, 1.0), 2
	)
	assert_not_null(p1, "First stream request should play.")

	var p2: AudioStreamPlayer = _audio_manager.call(
		&"play_sfx_2d_throttled", _dummy_stream, &"SFX", Vector2(1.0, 1.0), 2
	)
	assert_not_null(p2, "Second stream request within limit should play.")

	var p3: AudioStreamPlayer = _audio_manager.call(
		&"play_sfx_2d_throttled", _dummy_stream, &"SFX", Vector2(1.0, 1.0), 2
	)
	assert_null(p3, "Third stream request exceeding concurrency limit of 2 must be suppressed.")


## Verifies 3D spatial playback throttling suppresses sounds exceeding concurrency limit.
func test_concurrency_limit_suppression_3d() -> void:
	print("TestAudioManager: test_concurrency_limit_suppression_3d() executing.")
	var p1: AudioStreamPlayer3D = _audio_manager.call(
		&"play_sfx_3d_throttled",
		_dummy_stream,
		Vector3(1.0, 0.0, 0.0),
		&"SFX",
		Vector2(1.0, 1.0),
		1
	)
	assert_not_null(p1, "First 3D stream request should play.")

	var p2: AudioStreamPlayer3D = _audio_manager.call(
		&"play_sfx_3d_throttled",
		_dummy_stream,
		Vector3(2.0, 0.0, 0.0),
		&"SFX",
		Vector2(1.0, 1.0),
		1
	)
	assert_null(p2, "Second 3D stream request exceeding limit of 1 must be suppressed.")


## Verifies completion callbacks decrement the active stream count for subsequent playback.
func test_active_count_decrements_on_finish() -> void:
	print("TestAudioManager: test_active_count_decrements_on_finish() executing.")
	var p1: AudioStreamPlayer = _audio_manager.call(
		&"play_sfx_2d_throttled", _dummy_stream, &"SFX", Vector2(1.0, 1.0), 1
	)
	assert_not_null(p1, "Initial stream request should play.")

	var stream_key: StringName = StringName(_dummy_stream.resource_path)
	var counts_dict: Dictionary = _audio_manager.get(&"_active_sfx_counts")
	var count: int = str(counts_dict.get(stream_key, 0)).to_int()
	assert_eq(count, 1, "Active count must equal 1.")

	# Simulate completion callback
	_audio_manager.call(&"_on_player_2d_finished", p1, stream_key)
	counts_dict = _audio_manager.get(&"_active_sfx_counts")
	count = str(counts_dict.get(stream_key, 0)).to_int()
	assert_eq(count, 0, "Active count must decrement to 0 on finish.")

	# Now another request can play
	var p2: AudioStreamPlayer = _audio_manager.call(
		&"play_sfx_2d_throttled", _dummy_stream, &"SFX", Vector2(1.0, 1.0), 1
	)
	assert_not_null(p2, "Subsequent playback should succeed after count was freed.")
