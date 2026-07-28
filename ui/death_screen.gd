extends CanvasLayer
class_name DeathScreen

## Array of randomized phrases displayed upon player death.
const DEATH_MESSAGES: Array[String] = [
	"You died", 
	"You're dead", 
	"Busted", 
	"Fell from grace", 
    "Bella is no more"
]

## The standard waveform points for a healthy heartbeat.
const HEALTHY_POINTS: Array[Vector2] = [
	Vector2(-0.8, 0.0), Vector2(-0.6, 0.0), Vector2(-0.4, 0.0),
	Vector2(-0.2, 0.0), Vector2(-0.1, 0.1), Vector2(-0.05, -0.2),
	Vector2(0.0, 0.5), Vector2(0.05, -0.4), Vector2(0.1, 0.1),
	Vector2(0.2, 0.0), Vector2(0.4, 0.0), Vector2(0.6, 0.0),
	Vector2(0.8, 0.0)
]

## The flattened waveform points representing a stopped heart.
const FLATLINE_POINTS: Array[Vector2] = [
	Vector2(-0.8, 0.0), Vector2(-0.6, 0.0), Vector2(-0.4, 0.0),
	Vector2(-0.2, 0.0), Vector2(-0.1, 0.0), Vector2(-0.05, 0.0),
	Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.1, 0.0),
	Vector2(0.2, 0.0), Vector2(0.4, 0.0), Vector2(0.6, 0.0),
	Vector2(0.8, 0.0)
]

@onready var background: ColorRect = $Background
@onready var ecg_monitor: ColorRect = $ECGMonitor
@onready var death_label: Label = $DeathLabel
@onready var pain_overlay: ColorRect = $PainOverlay

var _beep_stream: AudioStreamWAV
var _flatline_stream: AudioStreamWAV
var heart_audio: AudioStreamPlayer

var _skip_allowed: bool = false
var _is_dead: bool = false

# Variables to perfectly sync the shader and audio manually via _process
var _shader_time: float = 0.0
var _aspect: float = 1.0
var _target_speed: float = 2.0
var _cycle_count: int = 0
var _flatline_started: bool = false


func _ready() -> void:
	print("DeathScreen: _ready() - Initializing UI and generating audio streams.")
	hide()
	death_label.modulate.a = 0.0
	background.modulate.a = 0.0
	
	if pain_overlay:
		pain_overlay.hide()
		pain_overlay.color = Color(1.0, 0.0, 0.0, 0.0)
	
	heart_audio = AudioStreamPlayer.new()
	add_child(heart_audio)
	
	_beep_stream = _generate_tone(800.0, 0.15, false, 0.3)
	_flatline_stream = _generate_tone(350.0, 0.5, true, 0.1)
	
	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("points", HEALTHY_POINTS)
		
	if Events.has_signal("player_died"):
		Events.player_died.connect(play_death_sequence)


func _input(event: InputEvent) -> void:
	if _skip_allowed and event is InputEventMouseButton and event.pressed:
		print("DeathScreen: _input() - Mouse clicked, skipping death screen early.")
		_return_to_main_menu()


func play_death_sequence(ran_in_last_10_secs: bool = false) -> void:
	print("DeathScreen: play_death_sequence() - Triggering sequence.")
	
	# FREE THE MOUSE so the player can actually click
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	show()
	_skip_allowed = false
	death_label.text = DEATH_MESSAGES.pick_random()
	
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_aspect = viewport_size.x / viewport_size.y
	_target_speed = 4.0 if ran_in_last_10_secs else 2.0
	
	# Start the visual pulse slightly off-screen to the left
	_shader_time = -(_aspect * 0.5)
	_cycle_count = 0
	_flatline_started = false
	_is_dead = true 
	
	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("points", HEALTHY_POINTS)
		
	var ui_tween: Tween = create_tween().set_parallel(true)
	ui_tween.tween_property(background, "modulate:a", 1.0, 3.0)
	
	if pain_overlay:
		pain_overlay.show()
		ui_tween.tween_property(pain_overlay, "color:a", 0.4, 3.0)
	
	ecg_monitor.modulate.a = 0.0
	ui_tween.tween_property(ecg_monitor, "modulate:a", 1.0, 3.0)
	
	get_tree().create_timer(3.0).timeout.connect(_allow_skipping)
	get_tree().create_timer(10.0).timeout.connect(_return_to_main_menu)


## Drives the shader time manually to guarantee audio fires exactly on the visual spike.
func _process(delta: float) -> void:
	if not _is_dead:
		return
		
	var prev_time: float = _shader_time
	_shader_time += delta * _target_speed
	
	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("u_time", _shader_time)
		
	# The visual spike crosses the exact center at 0.0, then every (aspect * 2.0)
	var next_spike_time: float = float(_cycle_count) * (_aspect * 2.0)
	
	if prev_time < next_spike_time and _shader_time >= next_spike_time:
		if _cycle_count < 2:
			_play_beep()
		elif _cycle_count == 2 and not _flatline_started:
			_flatline_started = true
			_play_flatline()
			
			var flatline_tween: Tween = create_tween()
			var cycle_duration: float = (_aspect * 2.0) / _target_speed
			flatline_tween.tween_method(_lerp_heartbeat_to_flatline, 0.0, 1.0, cycle_duration * 0.8)
			
			var text_tween: Tween = create_tween()
			text_tween.tween_property(death_label, "modulate:a", 1.0, 3.0)
			
		_cycle_count += 1


func _generate_tone(freq: float, duration: float, loop: bool, volume: float = 1.0) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	
	var frames: int = int(stream.mix_rate * duration)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	
	for i in range(frames):
		var time: float = float(i) / float(stream.mix_rate)
		var sample: float = sin(time * freq * TAU)
		
		var envelope: float = 1.0
		if not loop:
			if time < 0.01: 
				envelope = time / 0.01
			elif time > duration - 0.05: 
				envelope = (duration - time) / 0.05
				
		var val: int = int(sample * envelope * 32767.0 * volume) 
		var byte_idx: int = i * 2
		data[byte_idx] = val & 0xFF
		data[byte_idx + 1] = (val >> 8) & 0xFF
		
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames
		
	return stream


func _lerp_heartbeat_to_flatline(weight: float) -> void:
	var current_points: Array[Vector2] = []
	for i in range(HEALTHY_POINTS.size()):
		var lerped_point: Vector2 = HEALTHY_POINTS[i].lerp(FLATLINE_POINTS[i], weight)
		current_points.append(lerped_point)
		
	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("points", current_points)


func _play_beep() -> void:
	print("DeathScreen: _play_beep() - Beep.")
	heart_audio.stream = _beep_stream
	heart_audio.play()


func _play_flatline() -> void:
	print("DeathScreen: _play_flatline() - Flatline.")
	heart_audio.stream = _flatline_stream
	heart_audio.play()


func _allow_skipping() -> void:
	print("DeathScreen: _allow_skipping() - Skipping unlocked.")
	_skip_allowed = true


func _return_to_main_menu() -> void:
	# PREVENTS CRASH: Timer fires but scene is already gone / node is queued for deletion
	if not is_inside_tree():
		return
		
	print("DeathScreen: _return_to_main_menu() - Changing scene.")
	_is_dead = false 
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
