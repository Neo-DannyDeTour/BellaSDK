@tool
## Area3D volume managing ambient loops and pooled one-shot environmental SFX.
class_name SoundscapeZone
extends Area3D

## Dimensions of soundscape area volume box in meters.
@export var zone_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		zone_size = value
		_update_bounds()

## The resource containing ambient track and random sounds.
@export var soundscape: SoundscapeData

## Target volume for ambient track when fully faded in.
@export var base_volume_db: float = 0.0

## Duration in seconds for fading volume in and out.
@export var fade_duration: float = 0.5

## Keeps soundscape playing until another one is entered.
@export var persist_after_exit: bool = false

## Loops ambient track when it finishes.
@export var loop_ambient: bool = true

## Makes this the fallback soundscape when no others are active.
@export var is_default_soundscape: bool = false

## Ensures soundscape only activates very first time player enters.
@export var activate_once: bool = false

## Shared pointer tracking the currently active soundscape zone.
static var current_active_zone: Area3D = null

## Shared pointer tracking default fallback soundscape zone.
static var default_zone: Area3D = null

## Active tween handling volume fades.
var current_tween: Tween

## Primary audio stream player for background ambient music.
@onready var ambient_player: AudioStreamPlayer = $AmbientPlayer

## Internal timer used for scheduling random environmental one-shot sounds.
@onready var timer: Timer = $RandomSoundTimer

## Attached collision shape node defining trigger boundaries.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

## System timestamp in milliseconds tracking last exit time.
var _last_exit_time: int = 0

## Guard tracking whether activate_once has been triggered.
var _has_been_activated: bool = false

## Debounce threshold in milliseconds preventing immediate re-triggering.
const DEBOUNCE_MSEC: int = 100


## Initializes bounds, audio buses, and connections on ready.
func _ready() -> void:
	print("SoundscapeZone: Initializing: ", name)
	_update_bounds()

	if Engine.is_editor_hint():
		return

	if is_instance_valid(ambient_player):
		ambient_player.bus = &"Ambient"
		ambient_player.volume_db = -80.0
		ambient_player.finished.connect(_on_ambient_finished)

	if is_default_soundscape:
		default_zone = self

	add_to_group(&"soundscape_zones")

	if is_instance_valid(timer):
		timer.timeout.connect(_on_timer_timeout)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	if is_default_soundscape:
		call_deferred("_deferred_check_fallback")


## Updates box collision shape size to match [member zone_size].
func _update_bounds() -> void:
	if not is_inside_tree():
		return

	var shape_node: CollisionShape3D = (
		(
			collision_shape
			if is_instance_valid(collision_shape)
			else get_node_or_null("CollisionShape3D")
		)
		as CollisionShape3D
	)
	if is_instance_valid(shape_node):
		if not shape_node.shape is BoxShape3D:
			shape_node.shape = BoxShape3D.new()
		shape_node.shape.resource_local_to_scene = true
		(shape_node.shape as BoxShape3D).size = zone_size


## Activates soundscape zone when player enters volume.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.is_in_group(&"player") and soundscape != null:
		if activate_once and _has_been_activated:
			return

		if current_active_zone == self:
			if Time.get_ticks_msec() - _last_exit_time > DEBOUNCE_MSEC:
				print("SoundscapeZone: Player re-entered active zone: ", name)
			return

		print("SoundscapeZone: Player entered new soundscape: ", name)
		current_active_zone = self
		_has_been_activated = true
		_start_soundscape()


## Deactivates soundscape zone when player leaves volume.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.is_in_group(&"player") and soundscape != null:
		_last_exit_time = Time.get_ticks_msec()
		print("SoundscapeZone: Player exited soundscape: ", name)

		if current_active_zone == self:
			current_active_zone = null

		if not persist_after_exit:
			_stop_soundscape()
			call_deferred("_deferred_check_fallback")


## Checks and restores default fallback soundscape when idle.
func _deferred_check_fallback() -> void:
	print("SoundscapeZone: Evaluating fallback soundscape state.")
	if current_active_zone == null and default_zone != null:
		if not default_zone.ambient_player.playing or default_zone.ambient_player.stream_paused:
			print("SoundscapeZone: Resuming default soundscape: ", default_zone.name)
			default_zone._start_soundscape()


## Begins ambient playback and schedules pooled one-shot timer.
func _start_soundscape() -> void:
	print("SoundscapeZone: Starting soundscape: ", name)
	get_tree().call_group(&"soundscape_zones", &"_remote_stop", self)

	if soundscape.ambient_track:
		ambient_player.stream = soundscape.ambient_track

		if ambient_player.stream_paused:
			ambient_player.stream_paused = false
		elif not ambient_player.playing:
			ambient_player.play()

		_fade_volume(ambient_player, base_volume_db)

	if soundscape.random_sounds.size() > 0 and timer.is_stopped():
		_schedule_next_random_sound()


## Pauses ambient track and halts random sound timer.
func _stop_soundscape() -> void:
	print("SoundscapeZone: Stopping soundscape: ", name)
	timer.stop()
	_fade_volume(ambient_player, -80.0, true)


## Halts playback if another active zone claims priority.
func _remote_stop(new_zone: Area3D) -> void:
	var is_playing: bool = ambient_player.playing and not ambient_player.stream_paused
	if new_zone != self and is_playing:
		print("SoundscapeZone: Remote stop triggered on: ", name)
		_stop_soundscape()


## Smoothly tweens player volume towards [param target_vol].
func _fade_volume(
	player_node: AudioStreamPlayer, target_vol: float, pause_on_finish: bool = false
) -> void:
	print("SoundscapeZone: Fading volume on ", player_node.name, " to ", target_vol)
	if current_tween and current_tween.is_running():
		current_tween.kill()

	current_tween = create_tween()
	current_tween.tween_property(player_node, "volume_db", target_vol, fade_duration).set_trans(
		Tween.TRANS_SINE
	)

	if pause_on_finish:
		current_tween.tween_callback(func() -> void: player_node.stream_paused = true)


## Calculates randomized interval and starts one-shot timer.
func _schedule_next_random_sound() -> void:
	var next_time: float = randf_range(soundscape.min_interval, soundscape.max_interval)
	print("SoundscapeZone: Scheduling next random sound in ", next_time, " seconds.")
	timer.start(next_time)


## Dispatches pooled one-shot environmental SFX via [AudioPool].
func _on_timer_timeout() -> void:
	print("SoundscapeZone: Playing random one-shot sound via AudioPool.")
	if soundscape.random_sounds.is_empty():
		return

	var random_sound: AudioStream = soundscape.random_sounds.pick_random()
	var pooled_player: AudioStreamPlayer = AudioPool.play_sfx_2d(random_sound, &"Ambient")
	if is_instance_valid(pooled_player):
		pooled_player.volume_db = soundscape.random_volume_db

	_schedule_next_random_sound()


## Loops ambient track when reaching completion.
func _on_ambient_finished() -> void:
	print("SoundscapeZone: Ambient track finished on: ", name)
	if loop_ambient:
		ambient_player.play()
