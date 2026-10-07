## Zero-allocation audio stream player pool manager for 60 FPS runtime stability.
# class_name AudioPool
extends Node

## Default pool capacity for pre-allocated 2D audio stream players.
const POOL_SIZE_2D: int = 16
## Default pool capacity for pre-allocated 3D audio stream players.
const POOL_SIZE_3D: int = 32

## Pool containing pre-allocated [AudioStreamPlayer] nodes for 2D SFX.
var _pool_2d: Array[AudioStreamPlayer] = []
## Pool containing pre-allocated [AudioStreamPlayer3D] nodes for 3D spatial SFX.
var _pool_3d: Array[AudioStreamPlayer3D] = []

## Index pointer tracking the next circular slot in the 2D pool.
var _index_2d: int = 0
## Index pointer tracking the next circular slot in the 3D pool.
var _index_3d: int = 0


## Pre-allocates audio player instances and adds them to the scene tree.
func _ready() -> void:
	_ensure_pools_allocated()


## Allocates and instantiates audio nodes if not yet populated.
func _ensure_pools_allocated() -> void:
	if _pool_2d.is_empty():
		for i: int in range(POOL_SIZE_2D):
			var player_2d: AudioStreamPlayer = AudioStreamPlayer.new()
			player_2d.name = "AudioPool2D_%d" % i
			player_2d.bus = &"SFX"
			add_child(player_2d)
			_pool_2d.append(player_2d)

	if _pool_3d.is_empty():
		for j: int in range(POOL_SIZE_3D):
			var player_3d: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
			player_3d.name = "AudioPool3D_%d" % j
			player_3d.bus = &"SFX"
			add_child(player_3d)
			_pool_3d.append(player_3d)


## Plays a 2D sound effect using a recycled pooled player.
func play_sfx_2d(stream: AudioStream, bus: StringName = &"SFX") -> AudioStreamPlayer:
	_ensure_pools_allocated()
	if stream == null or _pool_2d.is_empty():
		return null
	var player: AudioStreamPlayer = _pool_2d[_index_2d]
	_index_2d = (_index_2d + 1) % POOL_SIZE_2D
	player.stream = stream
	player.bus = bus
	print("[AudioPool] Playing 2D SFX: %s on bus %s" % [stream.resource_path, bus])
	player.play()
	return player


## Plays a 3D sound effect at [param global_pos] using a recycled pooled player.
func play_sfx_3d(
	stream: AudioStream, global_pos: Vector3, bus: StringName = &"SFX"
) -> AudioStreamPlayer3D:
	_ensure_pools_allocated()
	if stream == null or _pool_3d.is_empty():
		return null
	var player: AudioStreamPlayer3D = _pool_3d[_index_3d]
	_index_3d = (_index_3d + 1) % POOL_SIZE_3D
	player.global_position = global_pos
	player.stream = stream
	player.bus = bus
	print("[AudioPool] Playing 3D SFX: %s at %s" % [stream.resource_path, str(global_pos)])
	player.play()
	return player


## Obtains an idle 2D audio stream player from the pool.
func get_pooled_player_2d() -> AudioStreamPlayer:
	_ensure_pools_allocated()
	if _pool_2d.is_empty():
		return null
	var player: AudioStreamPlayer = _pool_2d[_index_2d]
	_index_2d = (_index_2d + 1) % POOL_SIZE_2D
	print("[AudioPool] Retrieved idle 2D pooled player: %s" % player.name)
	return player


## Obtains an idle 3D audio stream player from the pool.
func get_pooled_player_3d() -> AudioStreamPlayer3D:
	_ensure_pools_allocated()
	if _pool_3d.is_empty():
		return null
	var player: AudioStreamPlayer3D = _pool_3d[_index_3d]
	_index_3d = (_index_3d + 1) % POOL_SIZE_3D
	print("[AudioPool] Retrieved idle 3D pooled player: %s" % player.name)
	return player
