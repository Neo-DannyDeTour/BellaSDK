@tool
extends Area3D

## Type your exact box dimensions here!
@export_category("Zone Dimensions")
@export var zone_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		zone_size = value
		_update_bounds()

## The resource containing the ambient track and random sounds.
@export_category("Soundscape Settings")
@export var soundscape: SoundscapeData
## The target volume for the ambient track when fully faded in.
@export var base_volume_db: float = 0.0
## Duration in seconds for fading volume in and out.
@export var fade_duration: float = 0.5
## Check this to keep the soundscape playing until another one is entered.
@export var persist_after_exit: bool = false
## Check this to loop the ambient track when it finishes.
@export var loop_ambient: bool = true
## Check this to make this the fallback soundscape when no others are active.
@export var is_default_soundscape: bool = false
## Check this to ensure the soundscape only activates the very first time the player enters.
@export var activate_once: bool = false

# Shared across all instances to track global state
## Property: Current Active Zone.
static var current_active_zone: Area3D = null
## Property: Default Zone.
static var default_zone: Area3D = null

## Property: Current Tween.
var current_tween: Tween

## Property: Ambient Player.
@onready var ambient_player: AudioStreamPlayer = $AmbientPlayer
## Property: One Shot Player.
@onready var one_shot_player: AudioStreamPlayer = $OneShotPlayer
## Property: Timer.
@onready var timer: Timer = $RandomSoundTimer
## Property: Collision Shape.
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

## Property: Last Exit Time.
var _last_exit_time: int = 0
## Property: Has Been Activated.
var _has_been_activated: bool = false
const DEBOUNCE_MSEC: int = 100


func _ready() -> void:
	print("Readying Soundscape Zone: ", name)
	_update_bounds()

	if Engine.is_editor_hint():
		return

	# --- ROUTE TO AMBIENT BUS ---
	print("Audio: Routing ", name, " players to Ambient bus.")
	ambient_player.bus = &"Ambient"
	one_shot_player.bus = &"Ambient"

	# Register default soundscape on initialization
	if is_default_soundscape:
		default_zone = self

	# Add to a group so zones can communicate dynamically
	add_to_group("soundscape_zones")

	ambient_player.volume_db = -80.0
	one_shot_player.volume_db = -80.0

	timer.timeout.connect(_on_timer_timeout)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	ambient_player.finished.connect(_on_ambient_finished)

	# Initialize the default soundscape if we are the default
	if is_default_soundscape:
		call_deferred("_deferred_check_fallback")


# --- Editor Only: Update Shape Size ---
func _update_bounds() -> void:
	print("Updating bounds for: ", name)
	if not is_inside_tree():
		return

	var shape_node: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node:
		if not shape_node.shape is BoxShape3D:
			shape_node.shape = BoxShape3D.new()

		shape_node.shape.resource_local_to_scene = true
		shape_node.shape.size = zone_size


# --- Gameplay Logic ---
func _on_body_entered(body: Node3D) -> void:
	print("Body entered zone: ", name)
	if Engine.is_editor_hint():
		return

	if body.is_in_group("player") and soundscape:
		if activate_once and _has_been_activated:
			print("Ignoring re-entry: ", name, " is set to activate_once and has already fired.")
			return

		if current_active_zone == self:
			if Time.get_ticks_msec() - _last_exit_time > DEBOUNCE_MSEC:
				print("Ignoring re-entry: ", name, " is already the active zone.")
			return

		print("Player entered NEW soundscape: ", name)
		current_active_zone = self
		_has_been_activated = true
		_start_soundscape()


func _on_body_exited(body: Node3D) -> void:
	print("Body exited zone: ", name)
	if Engine.is_editor_hint():
		return

	if body.is_in_group("player") and soundscape:
		_last_exit_time = Time.get_ticks_msec()
		print("Player exited soundscape: ", name)

		if current_active_zone == self:
			current_active_zone = null

		if not persist_after_exit:
			_stop_soundscape()
			call_deferred("_deferred_check_fallback")
		else:
			print("Persist is TRUE: ", name, " will continue playing.")


func _deferred_check_fallback() -> void:
	print("Checking fallback soundscape state.")
	# If no new zone claimed the active spot this frame, trigger the default
	if current_active_zone == null and default_zone != null:
		if not default_zone.ambient_player.playing or default_zone.ambient_player.stream_paused:
			print("No active zones. Resuming default soundscape: ", default_zone.name)
			default_zone._start_soundscape()


func _start_soundscape() -> void:
	print("Starting/Resuming soundscape: ", name)

	# Tell all other zones in the group to stop playing
	get_tree().call_group("soundscape_zones", "_remote_stop", self)

	if soundscape.ambient_track:
		ambient_player.stream = soundscape.ambient_track

		# Resume if paused, otherwise start from the beginning
		if ambient_player.stream_paused:
			print("Unpausing ambient track in: ", name)
			ambient_player.stream_paused = false
		elif not ambient_player.playing:
			print("Playing ambient track from start in: ", name)
			ambient_player.play()

		_fade_volume(ambient_player, base_volume_db)

	if soundscape.random_sounds.size() > 0:
		one_shot_player.volume_db = soundscape.random_volume_db
		# Only schedule if it isn't already running from a persist state
		if timer.is_stopped():
			_schedule_next_random_sound()


func _stop_soundscape() -> void:
	print("Stopping soundscape (pausing via fade): ", name)
	timer.stop()
	# Passing true ensures _pause_player is called after the fadeout
	_fade_volume(ambient_player, -80.0, true)


func _remote_stop(new_zone: Area3D) -> void:
	print("Remote stop evaluated on: ", name)
	# Stop if another zone overrides us while we are actively playing
	var is_playing: bool = ambient_player.playing and not ambient_player.stream_paused
	if new_zone != self and is_playing:
		print("Remote stop triggered on ", name, " by new zone: ", new_zone.name)
		_stop_soundscape()


func _fade_volume(
	player: AudioStreamPlayer, target_vol: float, pause_on_finish: bool = false
) -> void:
	print("Fading volume for ", player.name, " to ", target_vol, " dB over ", fade_duration, "s.")

	if current_tween and current_tween.is_running() -> void:
		current_tween.kill()

	current_tween = create_tween()
	current_tween.tween_property(player, "volume_db", target_vol, fade_duration).set_trans(
		Tween.TRANS_SINE
	)

	if pause_on_finish:
		current_tween.tween_callback(_pause_player.bind(player))


func _pause_player(player: AudioStreamPlayer) -> void:
	print("Pausing player to preserve stream progress: ", player.name)
	player.stream_paused = true


func _schedule_next_random_sound() -> void:
	var next_time: float = randf_range(soundscape.min_interval, soundscape.max_interval)
	print("Scheduling next random sound in ", next_time, " seconds for ", name)
	timer.start(next_time)


func _on_timer_timeout() -> void:
	print("Random sound timer timeout in: ", name)

	if soundscape.random_sounds.is_empty():
		return

	var random_sound: AudioStream = soundscape.random_sounds.pick_random()
	one_shot_player.stream = random_sound
	one_shot_player.play()

	_schedule_next_random_sound()


func _on_ambient_finished() -> void:
	print("Ambient track finished in: ", name)
	if loop_ambient:
		print("Looping enabled, restarting: ", name)
		ambient_player.play()
	else:
		print("Looping disabled: ", name)
