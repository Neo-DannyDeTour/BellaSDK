@tool
extends Area3D

@export_category("Zone Dimensions")
## Type your exact box dimensions here!
@export var zone_size: Vector3 = Vector3(1, 1, 1):
	set(value):
		zone_size = value
		_update_bounds()

@export_category("Soundscape Settings")
@export var soundscape: SoundscapeData 
@export var base_volume_db: float = 0.0
@export var fade_duration: float = 2.0

@onready var ambient_player: AudioStreamPlayer = $AmbientPlayer
@onready var one_shot_player: AudioStreamPlayer = $OneShotPlayer
@onready var timer: Timer = $RandomSoundTimer
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var current_tween: Tween

func _ready() -> void:
	# ADD THIS LINE: Force the shape to match our numbers when the game starts!
	_update_bounds() 
	
	# STOP HERE IF IN THE EDITOR: We don't want sounds playing while mapping!
	if Engine.is_editor_hint():
		return
		
	# Ensure the players start silent in the actual game
	ambient_player.volume_db = -80.0
	one_shot_player.volume_db = -80.0
	
	timer.timeout.connect(_on_timer_timeout)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

# --- Editor Only: Update Shape Size ---
func _update_bounds() -> void:
	if not is_inside_tree():
		return
		
	var shape_node := get_node_or_null("CollisionShape3D")
	if shape_node:
		if not shape_node.shape is BoxShape3D:
			shape_node.shape = BoxShape3D.new()
			
		# ADD THIS LINE: Tells Godot not to share this box size with other zones!
		shape_node.shape.resource_local_to_scene = true 
			
		shape_node.shape.size = zone_size

# --- Gameplay Logic ---
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint(): return
	
	if body.is_in_group("player") and soundscape:
		_start_soundscape()

func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint(): return
	
	if body.is_in_group("player") and soundscape:
		_stop_soundscape()

func _start_soundscape() -> void:
	if soundscape.ambient_track:
		ambient_player.stream = soundscape.ambient_track
		ambient_player.play()
		_fade_volume(ambient_player, base_volume_db)
	
	if soundscape.random_sounds.size() > 0:
		one_shot_player.volume_db = soundscape.random_volume_db 
		_schedule_next_random_sound()

func _stop_soundscape() -> void:
	timer.stop()
	_fade_volume(ambient_player, -80.0, true)

func _fade_volume(player: AudioStreamPlayer, target_vol: float, stop_on_finish: bool = false) -> void:
	if current_tween and current_tween.is_running():
		current_tween.kill()
		
	current_tween = create_tween()
	current_tween.tween_property(player, "volume_db", target_vol, fade_duration).set_trans(Tween.TRANS_SINE)
	
	if stop_on_finish:
		current_tween.tween_callback(player.stop)

func _schedule_next_random_sound() -> void:
	var next_time := randf_range(soundscape.min_interval, soundscape.max_interval)
	timer.start(next_time)

func _on_timer_timeout() -> void:
	if soundscape.random_sounds.is_empty():
		return
		
	var random_sound: AudioStream = soundscape.random_sounds.pick_random()
	one_shot_player.stream = random_sound
	one_shot_player.play()
	
	_schedule_next_random_sound()
