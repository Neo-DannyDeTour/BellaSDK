class_name PlayerChunkTracker
extends Node3D
## Tracks player grid coordinates via discrete [Timer] intervals and emits
## [signal Events.player_chunk_changed] on boundary crossings.

## World-space width and depth of a single streaming chunk in meters.
const CHUNK_SIZE: float = 250.0

## Interval in seconds between spatial coordinate checks.
const POLL_INTERVAL: float = 0.2

## Sentinel coordinate used to force an initial chunk emission on startup.
const INVALID_COORD: Vector2i = Vector2i(999999, 999999)

## Cached active chunk coordinate previously evaluated.
var _current_chunk: Vector2i = INVALID_COORD

## Timer driving periodic position checks.
@onready var _poll_timer: Timer = $PollTimer as Timer


## Validates dependencies, disables frame loops, and starts the boundary timer.
func _ready() -> void:
	assert(_poll_timer != null, "PlayerChunkTracker requires a PollTimer child node.")
	set_process(false)
	set_physics_process(false)
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.one_shot = false
	Utilities.safe_connect(_poll_timer.timeout, _on_poll_timer_timeout)
	_poll_timer.start()
	_evaluate_chunk()


## Disconnects timer signal when removed from the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(_poll_timer) and _poll_timer.timeout.is_connected(_on_poll_timer_timeout):
		_poll_timer.timeout.disconnect(_on_poll_timer_timeout)


## Evaluates current world position against [constant CHUNK_SIZE] and emits on change.
func _evaluate_chunk() -> void:
	var pos: Vector3 = global_position
	var coord: Vector2i = Vector2i(floori(pos.x / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE))
	if coord != _current_chunk:
		_current_chunk = coord
		print("Player entered chunk: ", coord)
		Events.player_chunk_changed.emit(coord)


## Triggered by [member _poll_timer] every [constant POLL_INTERVAL] seconds.
func _on_poll_timer_timeout() -> void:
	_evaluate_chunk()
