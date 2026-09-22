## Manages the post-death screen sequences, shader transitions, and audio.
class_name DeathScreen
extends CanvasLayer

## Player movement state at moment of death influencing pacing.
enum DeathState { CROUCHING, WALKING, SPRINTING }

## Visual effect types available for the death sequence presentation.
enum EffectType { ECG, LAVA, CAVE_TUNNEL, TV_STATIC, GLASS }

## Randomized messages displayed to the player upon dying.
const DEATH_MESSAGES: Array[String] = [
	"You died",
	"You're dead",
	"Busted",
	"Fell from grace",
	"Bella is no more",
	"Go to Hell!",
	"Your soul is mine!",
	"Nevermore..."
]

## Points defining healthy heartbeat ECG waveform trajectory.
const HEALTHY_POINTS: Array[Vector2] = [
	Vector2(-0.8, 0.0),
	Vector2(-0.6, 0.0),
	Vector2(-0.4, 0.0),
	Vector2(-0.2, 0.0),
	Vector2(-0.1, 0.1),
	Vector2(-0.05, -0.2),
	Vector2(0.0, 0.5),
	Vector2(0.05, -0.4),
	Vector2(0.1, 0.1),
	Vector2(0.2, 0.0),
	Vector2(0.4, 0.0),
	Vector2(0.6, 0.0),
	Vector2(0.8, 0.0)
]

## Points defining stopped flatline ECG waveform trajectory.
const FLATLINE_POINTS: Array[Vector2] = [
	Vector2(-0.8, 0.0),
	Vector2(-0.6, 0.0),
	Vector2(-0.4, 0.0),
	Vector2(-0.2, 0.0),
	Vector2(-0.1, 0.0),
	Vector2(-0.05, 0.0),
	Vector2(0.0, 0.0),
	Vector2(0.05, 0.0),
	Vector2(0.1, 0.0),
	Vector2(0.2, 0.0),
	Vector2(0.4, 0.0),
	Vector2(0.6, 0.0),
	Vector2(0.8, 0.0)
]

## Pool of randomized [enum EffectType] values without repeats.
static var _effect_pool: Array[EffectType] = []

## Background color rectangle overlay node.
@onready var background: ColorRect = $Background

## ECG monitor line display node.
@onready var ecg_monitor: ColorRect = $ECGMonitor

## Lava shader overlay node.
@onready var lava_overlay: ColorRect = $LavaOverlay

## Cave tunnel shader overlay node.
@onready var cave_tunnel_overlay: ColorRect = $CaveTunnelOverlay

## TV static noise shader overlay node.
@onready var tv_static_overlay: ColorRect = $TVStaticOverlay

## Full screen square glass distortion overlay node.
@onready var glass_overlay: ColorRect = $GlassOverlay

## Pain vignette flash overlay node.
@onready var pain_overlay: ColorRect = $PainOverlay

## Text label displaying death messages.
@onready var death_label: Label = $DeathLabel

## Procedural audio stream for healthy heart beeps.
var _beep_stream: AudioStreamWAV

## Procedural audio stream for heart flatline tone.
var _flatline_stream: AudioStreamWAV

## Procedural audio stream for TV static noise.
var _static_stream: AudioStreamWAV

## Audio stream player node for sequence sound effects.
var _heart_audio: AudioStreamPlayer

## Whether the player is currently permitted to skip the screen.
var _skip_allowed: bool = false

## Indicates if a death sequence is actively running.
var _is_dead: bool = false

## Elapsed time passed to the ECG shader for horizontal line movement.
var _shader_time: float = 0.0

## Viewport aspect ratio used for shader alignment.
var _aspect: float = 1.0

## Pacing speed multiplier for ECG animation and audio.
var _target_speed: float = 2.0

## Number of heartbeat spikes rendered across the screen.
var _cycle_count: int = 0

## Whether the flatline audio and visual state has started.
var _flatline_started: bool = false

## The currently active [enum EffectType] being played.
var _active_effect: EffectType = EffectType.GLASS


## Initializes node references, audio buffers, and signal listeners.
func _ready() -> void:
	print("DeathScreen: _ready() - Initializing UI, audio, and overlays.")
	randomize()
	hide()
	death_label.modulate.a = 0.0
	background.modulate.a = 0.0

	if is_instance_valid(ecg_monitor):
		ecg_monitor.hide()

	if is_instance_valid(lava_overlay):
		lava_overlay.hide()

	if is_instance_valid(cave_tunnel_overlay):
		cave_tunnel_overlay.hide()
		cave_tunnel_overlay.color = Color.WHITE

	if is_instance_valid(tv_static_overlay):
		tv_static_overlay.hide()

	if is_instance_valid(glass_overlay):
		glass_overlay.hide()

	if is_instance_valid(pain_overlay):
		pain_overlay.hide()
		pain_overlay.color = Color(1.0, 0.0, 0.0, 0.0)

	if has_node("HeartAudio"):
		_heart_audio = $HeartAudio as AudioStreamPlayer
	else:
		_heart_audio = AudioStreamPlayer.new()
		add_child(_heart_audio)

	_beep_stream = _generate_tone(800.0, 0.15, false, 0.25)
	_flatline_stream = _generate_tone(350.0, 0.5, true, 0.08)
	_static_stream = _generate_white_noise(0.5, true, 0.015)

	if is_instance_valid(ecg_monitor):
		var ecg_mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
		if is_instance_valid(ecg_mat):
			ecg_mat.set_shader_parameter("points", HEALTHY_POINTS)

	if Events.has_signal("player_died"):
		Events.player_died.connect(play_death_sequence)


## Handles skip inputs via mouse click when permitted by [member _skip_allowed].
func _input(event: InputEvent) -> void:
	if _skip_allowed and event is InputEventMouseButton and event.pressed:
		print("DeathScreen: _input() - Skipping death screen.")
		_return_to_main_menu()


## Advances ECG shader playback and triggers beep sounds over time.
func _process(delta: float) -> void:
	if not _is_dead or _active_effect != EffectType.ECG:
		return

	var prev_time: float = _shader_time
	_shader_time += delta * _target_speed

	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if is_instance_valid(mat):
		mat.set_shader_parameter("u_time", _shader_time)

	var next_spike_time: float = float(_cycle_count) * (_aspect * 2.0)
	if prev_time < next_spike_time and _shader_time >= next_spike_time:
		if _cycle_count < 2:
			_play_beep()
		elif _cycle_count == 2 and not _flatline_started:
			_trigger_flatline()
		_cycle_count += 1


## Draws the next non-repeating [enum EffectType] from [member _effect_pool].
func _get_next_effect() -> EffectType:
	print("DeathScreen: _get_next_effect() - Fetching effect from pool.")
	if _effect_pool.is_empty():
		var all_effects: Array = EffectType.values()
		for e: int in all_effects:
			_effect_pool.append(e as EffectType)
		_effect_pool.shuffle()

	var selected: EffectType = _effect_pool.pop_back()
	return selected


## Triggers full death takeover and starts the selected effect.
func play_death_sequence(death_state: int = DeathState.WALKING) -> void:
	print("DeathScreen: play_death_sequence() - Death triggered. State: ", death_state)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()

	_stop_all_audio()
	_skip_allowed = false
	_is_dead = true
	death_label.text = DEATH_MESSAGES.pick_random()

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_aspect = viewport_size.x / viewport_size.y

	_active_effect = _get_next_effect()
	print("DeathScreen: play_death_sequence() - Active effect: ", _active_effect)

	background.modulate.a = 0.0

	if is_instance_valid(pain_overlay):
		pain_overlay.show()
		pain_overlay.color.a = 0.6
		var flash_tween: Tween = create_tween()
		flash_tween.tween_interval(0.3)
		flash_tween.tween_property(pain_overlay, "color:a", 0.0, 0.4)
		flash_tween.tween_callback(pain_overlay.hide)

	ecg_monitor.hide()
	lava_overlay.hide()
	cave_tunnel_overlay.hide()
	if is_instance_valid(tv_static_overlay):
		tv_static_overlay.hide()
	if is_instance_valid(glass_overlay):
		glass_overlay.hide()

	match _active_effect:
		EffectType.ECG:
			_start_ecg_effect(death_state)
		EffectType.LAVA:
			_start_lava_effect()
		EffectType.CAVE_TUNNEL:
			_start_cave_tunnel_effect()
		EffectType.TV_STATIC:
			_start_tv_static_effect()
		EffectType.GLASS:
			_start_glass_effect()

	get_tree().create_timer(3.0).timeout.connect(_allow_skipping)
	get_tree().create_timer(10.0).timeout.connect(_return_to_main_menu)


## Runs a preview of the specified [enum EffectType] for testing.
func play_death_preview(effect: EffectType, death_state: int = DeathState.WALKING) -> void:
	print("DeathScreen: play_death_preview() - Previewing effect: ", effect)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()

	_stop_all_audio()
	_skip_allowed = false
	_is_dead = true
	death_label.text = DEATH_MESSAGES.pick_random()

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_aspect = viewport_size.x / viewport_size.y
	_active_effect = effect

	background.modulate.a = 0.0

	if is_instance_valid(pain_overlay):
		pain_overlay.show()
		pain_overlay.color.a = 0.6
		var flash_tween: Tween = create_tween()
		flash_tween.tween_interval(0.3)
		flash_tween.tween_property(pain_overlay, "color:a", 0.0, 0.4)
		flash_tween.tween_callback(pain_overlay.hide)

	ecg_monitor.hide()
	lava_overlay.hide()
	cave_tunnel_overlay.hide()
	if is_instance_valid(tv_static_overlay):
		tv_static_overlay.hide()
	if is_instance_valid(glass_overlay):
		glass_overlay.hide()

	match _active_effect:
		EffectType.ECG:
			_start_ecg_effect(death_state)
		EffectType.LAVA:
			_start_lava_effect()
		EffectType.CAVE_TUNNEL:
			_start_cave_tunnel_effect()
		EffectType.TV_STATIC:
			_start_tv_static_effect()
		EffectType.GLASS:
			_start_glass_effect()

	var close_preview: Callable = func() -> void:
		print("DeathScreen: Preview complete, restoring game.")
		_is_dead = false
		_stop_all_audio()
		hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	get_tree().create_timer(4.5).timeout.connect(close_preview)


## Runs full-screen glass distortion ramping into darkness.
func _start_glass_effect() -> void:
	print("DeathScreen: _start_glass_effect() - Starting glass distortion sequence.")
	if not is_instance_valid(glass_overlay):
		push_error("DeathScreen: glass_overlay node is missing.")
		return

	glass_overlay.show()
	glass_overlay.modulate.a = 1.0

	var mat: ShaderMaterial = glass_overlay.material as ShaderMaterial
	if not is_instance_valid(mat):
		push_error("DeathScreen: glass_overlay material is invalid.")
		return

	mat.set_shader_parameter("distortion_mix", 0.0)
	mat.set_shader_parameter("lens_strength", 1.8)
	mat.set_shader_parameter("lens_curve", 0.15)
	mat.set_shader_parameter("chromatic_spread", 0.0)
	mat.set_shader_parameter("black_fade", 0.0)
	mat.set_shader_parameter("box_size", Vector2(1.05, 1.05))
	mat.set_shader_parameter("box_radius", 0.25)
	mat.set_shader_parameter("border_weight", 0.0)

	var warp_tween: Tween = create_tween().set_parallel(true)
	(
		warp_tween
		. tween_property(mat, "shader_parameter/distortion_mix", 1.0, 1.4)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	(
		warp_tween
		. tween_property(mat, "shader_parameter/lens_strength", 5.0, 2.4)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		warp_tween
		. tween_property(mat, "shader_parameter/lens_curve", 0.65, 2.4)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)
	(
		warp_tween
		. tween_property(mat, "shader_parameter/chromatic_spread", 0.35, 2.0)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN_OUT)
	)

	var black_tween: Tween = create_tween()
	black_tween.tween_interval(1.2)
	(
		black_tween
		. tween_property(mat, "shader_parameter/black_fade", 1.0, 1.6)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)

	if is_instance_valid(death_label):
		var label_tween: Tween = create_tween()
		label_tween.tween_interval(2.0)
		label_tween.tween_property(death_label, "modulate:a", 1.0, 1.2)


## Starts the hospital ECG monitor shader visual sequence.
func _start_ecg_effect(death_state: int) -> void:
	print("DeathScreen: _start_ecg_effect() - Starting ECG monitor.")
	if not is_instance_valid(ecg_monitor):
		push_error("DeathScreen: ecg_monitor node is missing.")
		return

	ecg_monitor.show()
	ecg_monitor.modulate.a = 0.0

	_shader_time = -(_aspect * 0.5)
	_cycle_count = 0
	_flatline_started = false

	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if is_instance_valid(mat):
		mat.set_shader_parameter("points", HEALTHY_POINTS)
		mat.set_shader_parameter("resolution", get_viewport().get_visible_rect().size)

	var ecg_tween: Tween = create_tween().set_parallel(true)
	if is_instance_valid(background):
		ecg_tween.tween_property(background, "modulate:a", 1.0, 3.0)
	ecg_tween.tween_property(ecg_monitor, "modulate:a", 1.0, 3.0)
	if is_instance_valid(death_label):
		ecg_tween.tween_property(death_label, "modulate:a", 1.0, 3.0)

	match death_state:
		DeathState.CROUCHING:
			_target_speed = 2.0
			_cycle_count = 3
			_trigger_flatline()
		DeathState.SPRINTING:
			_target_speed = 4.0
		DeathState.WALKING, _:
			_target_speed = 2.0


## Begins rising lava overlay shader sequence.
func _start_lava_effect() -> void:
	print("DeathScreen: _start_lava_effect() - Dynamically filling lava.")
	lava_overlay.show()
	lava_overlay.modulate.a = 0.0

	var lava_mat: ShaderMaterial = lava_overlay.material as ShaderMaterial
	if is_instance_valid(lava_mat):
		lava_mat.set_shader_parameter("emission", 0.0)
		lava_mat.set_shader_parameter("resolution", get_viewport().get_visible_rect().size)

	var lava_tween: Tween = create_tween().set_parallel(true)
	lava_tween.tween_property(lava_overlay, "modulate:a", 1.0, 2.5)
	lava_tween.tween_property(death_label, "modulate:a", 1.0, 3.0)

	if is_instance_valid(lava_mat):
		lava_tween.tween_property(lava_mat, "shader_parameter/emission", 1.8, 3.0)


## Begins 3D cave tunnel raymarching shader sequence.
func _start_cave_tunnel_effect() -> void:
	print("DeathScreen: _start_cave_tunnel_effect() - Descending into cave tunnel.")
	cave_tunnel_overlay.show()
	cave_tunnel_overlay.modulate.a = 0.0

	var cave_mat: ShaderMaterial = cave_tunnel_overlay.material as ShaderMaterial
	if is_instance_valid(cave_mat):
		cave_mat.set_shader_parameter("resolution", get_viewport().get_visible_rect().size)

	var tunnel_tween: Tween = create_tween().set_parallel(true)
	tunnel_tween.tween_property(cave_tunnel_overlay, "modulate:a", 1.0, 2.5)
	tunnel_tween.tween_property(death_label, "modulate:a", 1.0, 3.0)


## Runs TV CRT static noise and picture reveal sequence.
func _start_tv_static_effect() -> void:
	print("DeathScreen: _start_tv_static_effect() - Starting TV static effect.")
	if not is_instance_valid(tv_static_overlay):
		push_error("DeathScreen: tv_static_overlay node is missing.")
		return

	tv_static_overlay.show()
	tv_static_overlay.modulate.a = 1.0

	var mat: ShaderMaterial = tv_static_overlay.material as ShaderMaterial
	if is_instance_valid(mat):
		mat.set_shader_parameter("static_intensity", 1.0)

	_play_static_audio()

	var static_tween: Tween = create_tween()
	static_tween.tween_interval(0.8)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.4, 0.06)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.8, 0.05)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.2, 0.08)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.5, 0.06)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.05, 0.12)

	if is_instance_valid(death_label):
		var text_tween: Tween = create_tween()
		text_tween.tween_interval(1.2)
		text_tween.tween_property(death_label, "modulate:a", 1.0, 1.0)

	static_tween.tween_interval(2.2)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.45, 0.07)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.15, 0.05)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.75, 0.08)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.35, 0.06)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 1.0, 0.1)


## Transitions healthy ECG heartbeat into a flatline waveform.
func _trigger_flatline() -> void:
	if _flatline_started:
		return

	print("DeathScreen: _trigger_flatline() - Triggering flatline transition.")
	_flatline_started = true
	_play_flatline()

	var flatline_tween: Tween = create_tween()
	var cycle_duration: float = (_aspect * 2.0) / _target_speed
	flatline_tween.tween_method(_lerp_heartbeat_to_flatline, 0.0, 1.0, cycle_duration * 0.8)

	if is_instance_valid(death_label) and death_label.modulate.a < 0.1:
		var text_tween: Tween = create_tween()
		text_tween.tween_property(death_label, "modulate:a", 1.0, 3.0)


## Procedurally synthesizes a sine wave [AudioStreamWAV] buffer.
func _generate_tone(
	freq: float, duration: float, loop: bool, volume: float = 1.0
) -> AudioStreamWAV:
	print("DeathScreen: _generate_tone() - Generating procedural audio tone.")
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100

	var frames: int = int(stream.mix_rate * duration)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)

	for i: int in range(frames):
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


## Procedurally synthesizes a white noise [AudioStreamWAV] buffer.
func _generate_white_noise(duration: float, loop: bool, volume: float = 1.0) -> AudioStreamWAV:
	print("DeathScreen: _generate_white_noise() - Generating procedural white noise.")
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100

	var frames: int = int(stream.mix_rate * duration)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)

	for i: int in range(frames):
		var sample: float = randf_range(-1.0, 1.0)
		var val: int = int(sample * 32767.0 * volume)
		var byte_idx: int = i * 2
		data[byte_idx] = val & 0xFF
		data[byte_idx + 1] = (val >> 8) & 0xFF

	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = frames

	return stream


## Interpolates ECG shader points between healthy and flatline states.
func _lerp_heartbeat_to_flatline(weight: float) -> void:
	var current_points: Array[Vector2] = []
	for i: int in range(HEALTHY_POINTS.size()):
		var lerped_point: Vector2 = HEALTHY_POINTS[i].lerp(FLATLINE_POINTS[i], weight)
		current_points.append(lerped_point)

	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if is_instance_valid(mat):
		mat.set_shader_parameter("points", current_points)


## Plays the short heartbeat beep audio tone.
func _play_beep() -> void:
	if not _is_dead:
		return
	print("DeathScreen: _play_beep() - Playing heartbeat beep.")
	_heart_audio.stream = _beep_stream
	_heart_audio.play()


## Plays continuous flatline tone on [member _heart_audio].
func _play_flatline() -> void:
	if not _is_dead:
		return
	print("DeathScreen: _play_flatline() - Playing flatline audio.")
	_heart_audio.stream = _flatline_stream
	_heart_audio.play()


## Plays looping static noise on [member _heart_audio].
func _play_static_audio() -> void:
	if not _is_dead:
		return
	print("DeathScreen: _play_static_audio() - Playing TV static noise.")
	_heart_audio.stream = _static_stream
	_heart_audio.play()


## Stops all active procedural audio streams.
func _stop_all_audio() -> void:
	print("DeathScreen: _stop_all_audio() - Halting audio streams.")
	if is_instance_valid(_heart_audio):
		_heart_audio.stop()
		_heart_audio.stream = null


## Sets [member _skip_allowed] to true allowing player skip.
func _allow_skipping() -> void:
	print("DeathScreen: _allow_skipping() - Input skip unlocked.")
	_skip_allowed = true


## Cleans up state and transitions the tree to the main menu scene.
func _return_to_main_menu() -> void:
	if not is_inside_tree():
		return

	print("DeathScreen: _return_to_main_menu() - Changing scene to main menu.")
	_is_dead = false
	_stop_all_audio()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
