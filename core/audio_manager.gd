#class_name AudioManager
extends Node
## Polyphony-limited audio manager with pitch variation and concurrency suppression.

## Maximum simultaneous audio streams permitted for a single sound key.
const DEFAULT_CONCURRENCY_LIMIT: int = 4

## Active instance counts indexed by audio resource path.
var _active_sfx_counts: Dictionary[StringName, int] = {}


## Lifecycle initializer configuring process mode for audio persistence.
func _ready() -> void:
	print("[AudioManager] AudioManager Autoload initialized.")
	process_mode = Node.PROCESS_MODE_ALWAYS


## Plays 2D SFX with concurrency limiting and pitch variation.
func play_sfx_2d_throttled(
	stream: AudioStream,
	bus: StringName = &"SFX",
	pitch_range: Vector2 = Vector2(0.95, 1.05),
	concurrency_limit: int = DEFAULT_CONCURRENCY_LIMIT
) -> AudioStreamPlayer:
	if stream == null:
		return null

	var stream_key: StringName = StringName(stream.resource_path)
	var active_count: int = _active_sfx_counts.get(stream_key, 0)
	if active_count >= concurrency_limit:
		print("[AudioManager] Suppressed 2D SFX playback limit: ", stream_key)
		return null

	var pool: Node = get_node_or_null("/root/AudioPool")
	if not is_instance_valid(pool):
		push_error("[AudioManager] AudioPool autoload not present in scene tree.")
		return null

	var player: AudioStreamPlayer = (
		pool.call("get_pooled_player_2d")
		if pool.call("get_pooled_player_2d") is AudioStreamPlayer
		else null
	)
	if not is_instance_valid(player):
		return null

	_active_sfx_counts[stream_key] = active_count + 1
	player.stream = stream
	player.bus = bus
	player.pitch_scale = randf_range(pitch_range.x, pitch_range.y)
	player.play()
	print("[AudioManager] Playing throttled 2D SFX: ", stream_key)

	var callable: Callable = _on_player_2d_finished.bind(player, stream_key)
	player.finished.connect(callable, CONNECT_ONE_SHOT)
	return player


## Plays 3D spatial SFX at [param global_pos] with concurrency limiting.
func play_sfx_3d_throttled(
	stream: AudioStream,
	global_pos: Vector3,
	bus: StringName = &"SFX",
	pitch_range: Vector2 = Vector2(0.95, 1.05),
	concurrency_limit: int = DEFAULT_CONCURRENCY_LIMIT
) -> AudioStreamPlayer3D:
	if stream == null:
		return null

	var stream_key: StringName = StringName(stream.resource_path)
	var active_count: int = _active_sfx_counts.get(stream_key, 0)
	if active_count >= concurrency_limit:
		print("[AudioManager] Suppressed 3D SFX playback limit: ", stream_key)
		return null

	var pool: Node = get_node_or_null("/root/AudioPool")
	if not is_instance_valid(pool):
		push_error("[AudioManager] AudioPool autoload not present in scene tree.")
		return null

	var player: AudioStreamPlayer3D = (
		pool.call("get_pooled_player_3d")
		if pool.call("get_pooled_player_3d") is AudioStreamPlayer3D
		else null
	)
	if not is_instance_valid(player):
		return null

	_active_sfx_counts[stream_key] = active_count + 1
	player.global_position = global_pos
	player.stream = stream
	player.bus = bus
	player.pitch_scale = randf_range(pitch_range.x, pitch_range.y)
	player.play()
	print("[AudioManager] Playing throttled 3D SFX at: ", global_pos)

	var callable: Callable = _on_player_3d_finished.bind(player, stream_key)
	player.finished.connect(callable, CONNECT_ONE_SHOT)
	return player


## Decrements active count for 2D stream key upon playback completion.
func _on_player_2d_finished(_player: AudioStreamPlayer, stream_key: StringName) -> void:
	var current: int = _active_sfx_counts.get(stream_key, 1)
	_active_sfx_counts[stream_key] = maxi(0, current - 1)


## Decrements active count for 3D stream key upon playback completion.
func _on_player_3d_finished(_player: AudioStreamPlayer3D, stream_key: StringName) -> void:
	var current: int = _active_sfx_counts.get(stream_key, 1)
	_active_sfx_counts[stream_key] = maxi(0, current - 1)
