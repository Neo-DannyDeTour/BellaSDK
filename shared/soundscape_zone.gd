@tool
extends Area3D

@export_category("Zone Dimensions")
## Type your exact box dimensions here!
@export var zone_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		zone_size = value
		_update_bounds()

@export_category("Soundscape Settings")
@export var soundscape: SoundscapeData
@export var base_volume_db: float = 0.0
@export var fade_duration: float = 2.0
## Check this to keep the soundscape playing until another one is entered.
@export var persist_after_exit: bool = false
## Check this to loop the ambient track when it finishes.
@export var loop_ambient: bool = true

# Shared across all instances of this script to track the globally active zone
static var current_active_zone: Area3D = null

var current_tween: Tween

@onready var ambient_player: AudioStreamPlayer = $AmbientPlayer
@onready var one_shot_player: AudioStreamPlayer = $OneShotPlayer
@onready var timer: Timer = $RandomSoundTimer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	print("Readying Soundscape Zone: ", name)
	_update_bounds()

	if Engine.is_editor_hint():
		return

	# Add to a group so zones can communicate with each other dynamically
	add_to_group("soundscape_zones")

	ambient_player.volume_db = -80.0
	one_shot_player.volume_db = -80.0

	timer.timeout.connect(_on_timer_timeout)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	ambient_player.finished.connect(_on_ambient_finished)


# --- Editor Only: Update Shape Size ---
func _update_bounds() -> void:
	if not is_inside_tree():
		return

	var shape_node: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if shape_node:
		if not shape_node.shape is BoxShape3D:
			shape_node.shape = BoxShape3D.new()

		shape_node.shape.resource_local_to_scene = true
		shape_node.shape.size = zone_size


# --- Gameplay Logic ---
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.is_in_group("player") and soundscape:
		# Ignore if we are already the active soundscape zone
		if current_active_zone == self:
			print("Ignoring re-entry: ", name, " is already the active zone.")
			return
			
		print("Player entered NEW soundscape: ", name)
		current_active_zone = self
		_start_soundscape()


func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.is_in_group("player") and soundscape:
		print("Player exited soundscape: ", name)
		if not persist_after_exit:
			_stop_soundscape()
		else:
			print("Persist is TRUE: ", name, " will continue playing.")


func _start_soundscape() -> void:
	print("Starting soundscape: ", name)
	
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
		_schedule_next_random_sound()


func _stop_soundscape() -> void:
	print("Stopping soundscape: ", name)
	timer.stop()
	_fade_volume(ambient_player, -80.0, true)


func _remote_stop(new_zone: Area3D) -> void:
	# Called by a newly entered zone. If we are currently playing, we should stop.
	if new_zone != self and ambient_player.playing:
		print("Remote stop triggered on ", name, " by new zone: ", new_zone.name)
		_stop_soundscape()


func _fade_volume(
	player: AudioStreamPlayer, 
	target_vol: float, 
	pause_on_finish: bool = false
) -> void:
	print("Fading volume for ", player.name, " to ", target_vol, " dB.")
	
	if current_tween and current_tween.is_running():
		current_tween.kill()

	current_tween = create_tween()
	current_tween.tween_property(
		player, 
		"volume_db", 
		target_vol, 
		fade_duration
	).set_trans(Tween.TRANS_SINE)

	if pause_on_finish:
		current_tween.tween_callback(_pause_player.bind(player))


func _pause_player(player: AudioStreamPlayer) -> void:
	print("Pausing player: ", player.name)
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
	if loop_ambient:
		print("Ambient track finished. Looping enabled, restarting: ", name)
		ambient_player.play()
	else:
		print("Ambient track finished. Looping disabled: ", name)
