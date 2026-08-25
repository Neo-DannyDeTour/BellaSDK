## Displays a post-death sequence with visual effects and audio feedback.
##
## Listens for the `player_died` global event and takes over the screen to play
## an animated sequence (e.g., ECG flatline, lava burn, cave tunnel, or TV static).
class_name DeathScreen
extends CanvasLayer

## Defines the player's movement state at the exact moment of death.
enum DeathState { CROUCHING, WALKING, SPRINTING }

## Available visual effect types for the death screen sequence.
enum EffectType { ECG, LAVA, CAVE_TUNNEL, TV_STATIC }

## Array of randomized phrases displayed upon player death.
const DEATH_MESSAGES: Array[String] = [
	"You died", "You're dead", "Busted", "Fell from grace", "Bella is no more"
]

## The standard waveform points for a healthy heartbeat.
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

## The flattened waveform points representing a stopped heart.
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

## Persisted effect pool shuffled to prevent duplicate screens across runs.
static var _effect_pool: Array[EffectType] = []

## The background color rectangle node.
@onready var background: ColorRect = $Background

## The ECG monitor node displaying the heartbeat line.
@onready var ecg_monitor: ColorRect = $ECGMonitor

## The lava shader overlay displaying dynamic lava fill.
@onready var lava_overlay: ColorRect = $LavaOverlay

## The cave tunnel shader overlay displaying the 3D raymarched abyss.
@onready var cave_tunnel_overlay: ColorRect = $CaveTunnelOverlay

## The TV static overlay node displaying CRT noise and picture reveal.
@onready var tv_static_overlay: ColorRect = $TVStaticOverlay

## The label node for displaying death messages.
@onready var death_label: Label = $DeathLabel

## The pain overlay node for red vignette flash effects.
@onready var pain_overlay: ColorRect = $PainOverlay

## The audio stream generated for the healthy heartbeat beep.
var _beep_stream: AudioStreamWAV

## The audio stream generated for the continuous flatline tone.
var _flatline_stream: AudioStreamWAV

## The audio stream generated for the continuous TV static noise.
var _static_stream: AudioStreamWAV

## The audio player node responsible for playing sequence sounds.
var _heart_audio: AudioStreamPlayer

## Tracks whether the player is currently allowed to skip the death screen.
var _skip_allowed: bool = false

## Indicates whether the death sequence is currently active.
var _is_dead: bool = false

## The current time passed into the shader to animate the ECG line.
var _shader_time: float = 0.0

## The aspect ratio of the screen to ensure the shader renders perfectly.
var _aspect: float = 1.0

## The playback speed of the ECG animation and audio sequence.
var _target_speed: float = 2.0

## The number of times the heartbeat visual has spiked across the screen.
var _cycle_count: int = 0

## Tracks whether the flatline sequence has already been initiated.
var _flatline_started: bool = false

## The active visual effect selected for the current death sequence.
var _active_effect: EffectType = EffectType.ECG


## Configures UI visibility, synthesizes audio tones, and connects the death signal.
func _ready() -> void:
	print("DeathScreen: _ready() - Initializing UI and shader overlays.")
	randomize()
	hide()
	death_label.modulate.a = 0.0
	background.modulate.a = 0.0

	if ecg_monitor:
		ecg_monitor.hide()

	if lava_overlay:
		lava_overlay.hide()

	if cave_tunnel_overlay:
		cave_tunnel_overlay.hide()
		cave_tunnel_overlay.color = Color.WHITE

	if tv_static_overlay:
		tv_static_overlay.hide()

	if pain_overlay:
		pain_overlay.hide()
		pain_overlay.color = Color(1.0, 0.0, 0.0, 0.0)

	_heart_audio = AudioStreamPlayer.new()
	add_child(_heart_audio)

	_beep_stream = _generate_tone(800.0, 0.15, false, 0.25)
	_flatline_stream = _generate_tone(350.0, 0.5, true, 0.08)
	_static_stream = _generate_white_noise(0.5, true, 0.015)

	var ecg_mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if ecg_mat:
		ecg_mat.set_shader_parameter("points", HEALTHY_POINTS)

	if Events.has_signal("player_died"):
		Events.player_died.connect(play_death_sequence)


## Evaluates input for skipping the death sequence if the timer has passed.
## [param event] The system input event.
func _input(event: InputEvent) -> void:
	if _skip_allowed and event is InputEventMouseButton and event.pressed:
		print("DeathScreen: _input() - Mouse clicked, skipping death screen.")
		_return_to_main_menu()


## Advances the active shader time and triggers auditory effects based on time intervals.
## [param delta] Engine frame delta.
func _process(delta: float) -> void:
	if not _is_dead or _active_effect != EffectType.ECG:
		return

	var prev_time: float = _shader_time
	_shader_time += delta * _target_speed

	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("u_time", _shader_time)

	var next_spike_time: float = float(_cycle_count) * (_aspect * 2.0)

	if prev_time < next_spike_time and _shader_time >= next_spike_time:
		if _cycle_count < 2:
			_play_beep()
		elif _cycle_count == 2 and not _flatline_started:
			_trigger_flatline()

		_cycle_count += 1


## Retrieves the next random effect from the pool, refilling when depleted.
## [return] The next [enum EffectType] to play.
func _get_next_effect() -> EffectType:
	print("DeathScreen: _get_next_effect() - Fetching random non-repeating screen.")
	if _effect_pool.is_empty():
		print("DeathScreen: _get_next_effect() - Pool empty. Reshuffling all effects.")
		var all_effects: Array = EffectType.values()
		for e: int in all_effects:
			_effect_pool.append(e as EffectType)
		_effect_pool.shuffle()

	var selected: EffectType = _effect_pool.pop_back()
	print("DeathScreen: _get_next_effect() - Remaining in pool: ", _effect_pool.size())
	return selected


## Initiates the entire death screen takeover flow.
## [param death_state] Player state index configuring sequence pacing.
func play_death_sequence(death_state: int = DeathState.WALKING) -> void:
	print("DeathScreen: play_death_sequence() - Triggering sequence. State: ", death_state)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()

	_stop_all_audio()
	_skip_allowed = false
	_is_dead = true
	death_label.text = DEATH_MESSAGES.pick_random()

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_aspect = viewport_size.x / viewport_size.y

	_active_effect = _get_next_effect()
	print("DeathScreen: play_death_sequence() - Selected effect: ", _active_effect)

	background.modulate.a = 0.0

	if pain_overlay:
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

	match _active_effect:
		EffectType.ECG:
			_start_ecg_effect(death_state)
		EffectType.LAVA:
			_start_lava_effect()
		EffectType.CAVE_TUNNEL:
			_start_cave_tunnel_effect()
		EffectType.TV_STATIC:
			_start_tv_static_effect()

	get_tree().create_timer(3.0).timeout.connect(_allow_skipping)
	get_tree().create_timer(10.0).timeout.connect(_return_to_main_menu)


## Plays a specific death effect preview and restores gameplay when finished.
## [param effect] The specific [enum EffectType] to preview.
## [param death_state] Pacing state modifier.
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

	if pain_overlay:
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

	match _active_effect:
		EffectType.ECG:
			_start_ecg_effect(death_state)
		EffectType.LAVA:
			_start_lava_effect()
		EffectType.CAVE_TUNNEL:
			_start_cave_tunnel_effect()
		EffectType.TV_STATIC:
			_start_tv_static_effect()

	var close_preview: Callable = func() -> void:
		print("DeathScreen: Preview complete, restoring game.")
		_is_dead = false
		_stop_all_audio()
		hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	get_tree().create_timer(4.5).timeout.connect(close_preview)


## Prepares and begins the hospital ECG monitor shader visual effect.
## [param death_state] Impacts pacing modifiers.
func _start_ecg_effect(death_state: int) -> void:
	print("DeathScreen: _start_ecg_effect() - Starting ECG monitor effect.")
	if not is_instance_valid(ecg_monitor):
		push_error("DeathScreen: ecg_monitor node is missing.")
		return

	ecg_monitor.show()
	ecg_monitor.modulate.a = 0.0

	_shader_time = -(_aspect * 0.5)
	_cycle_count = 0
	_flatline_started = false

	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if mat:
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


## Prepares and begins the rising lava shader visual effect.
func _start_lava_effect() -> void:
	print("DeathScreen: _start_lava_effect() - Dynamically filling lava.")
	lava_overlay.show()
	lava_overlay.modulate.a = 0.0

	var lava_mat: ShaderMaterial = lava_overlay.material as ShaderMaterial
	if lava_mat:
		lava_mat.set_shader_parameter("emission", 0.0)
		lava_mat.set_shader_parameter("resolution", get_viewport().get_visible_rect().size)

	var lava_tween: Tween = create_tween().set_parallel(true)
	lava_tween.tween_property(lava_overlay, "modulate:a", 1.0, 2.5)
	lava_tween.tween_property(death_label, "modulate:a", 1.0, 3.0)

	if lava_mat:
		lava_tween.tween_property(lava_mat, "shader_parameter/emission", 1.8, 3.0)


## Prepares and begins the cave tunnel raymarching shader visual effect.
func _start_cave_tunnel_effect() -> void:
	print("DeathScreen: _start_cave_tunnel_effect() - Descending into cave tunnel.")
	cave_tunnel_overlay.show()
	cave_tunnel_overlay.modulate.a = 0.0

	var cave_mat: ShaderMaterial = cave_tunnel_overlay.material as ShaderMaterial
	if cave_mat:
		cave_mat.set_shader_parameter("resolution", get_viewport().get_visible_rect().size)

	var tunnel_tween: Tween = create_tween().set_parallel(true)
	tunnel_tween.tween_property(cave_tunnel_overlay, "modulate:a", 1.0, 2.5)
	tunnel_tween.tween_property(death_label, "modulate:a", 1.0, 3.0)


## Prepares and begins the flickering TV static shader visual effect.
func _start_tv_static_effect() -> void:
	print("DeathScreen: _start_tv_static_effect() - Starting TV static effect.")
	if not is_instance_valid(tv_static_overlay):
		push_error("DeathScreen: tv_static_overlay node is missing.")
		return

	tv_static_overlay.show()
	tv_static_overlay.modulate.a = 1.0

	var mat: ShaderMaterial = tv_static_overlay.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("static_intensity", 1.0)

	_play_static_audio()

	var static_tween: Tween = create_tween()

	# Phase 1: Heavy static
	static_tween.tween_interval(0.8)

	# Phase 2: Rapid flickering transition revealing the underlying image
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.4, 0.06)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.8, 0.05)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.2, 0.08)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.5, 0.06)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.05, 0.12)

	# Phase 3: Hold clear picture visibility and fade in text
	if is_instance_valid(death_label):
		var text_tween: Tween = create_tween()
		text_tween.tween_interval(1.2)
		text_tween.tween_property(death_label, "modulate:a", 1.0, 1.0)

	static_tween.tween_interval(2.2)

	# Phase 4: Flicker back into 100% heavy static
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.45, 0.07)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.15, 0.05)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.75, 0.08)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 0.35, 0.06)
	static_tween.tween_property(mat, "shader_parameter/static_intensity", 1.0, 0.1)


## Initiates the transition from beating heart waveform to flatline waveform.
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


## Procedurally synthesizes basic audio waves to avoid relying on external files.
## [param freq] Desired wave frequency.
## [param duration] Desired length in seconds.
## [param loop] Should the tone loop continuously.
## [param volume] Playback scaling multiplier.
## [return] A generated [AudioStreamWAV] buffer.
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


## Procedurally synthesizes white noise audio for the TV static effect.
## [param duration] Length in seconds for looping buffer.
## [param loop] Whether the stream should loop seamlessly.
## [param volume] Overall volume scale.
## [return] A generated white noise [AudioStreamWAV] buffer.
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


## Tween callback interpolating the raw points fed to the ECG shader.
## [param weight] Normal interpolation value from 0.0 to 1.0.
func _lerp_heartbeat_to_flatline(weight: float) -> void:
	var current_points: Array[Vector2] = []
	for i: int in range(HEALTHY_POINTS.size()):
		var lerped_point: Vector2 = HEALTHY_POINTS[i].lerp(FLATLINE_POINTS[i], weight)
		current_points.append(lerped_point)

	var mat: ShaderMaterial = ecg_monitor.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("points", current_points)


## Triggers a single playback instance of the short pulse beep audio.
func _play_beep() -> void:
	if not _is_dead:
		return
	print("DeathScreen: _play_beep() - Playing heartbeat beep.")
	_heart_audio.stream = _beep_stream
	_heart_audio.play()


## Triggers the looping playback instance of the flatline audio.
func _play_flatline() -> void:
	if not _is_dead:
		return
	print("DeathScreen: _play_flatline() - Playing flatline audio.")
	_heart_audio.stream = _flatline_stream
	_heart_audio.play()


## Triggers the looping playback instance of the TV static noise.
func _play_static_audio() -> void:
	if not _is_dead:
		return
	print("DeathScreen: _play_static_audio() - Playing TV static noise.")
	_heart_audio.stream = _static_stream
	_heart_audio.play()


## Immediately halts any active procedural sound stream.
func _stop_all_audio() -> void:
	print("DeathScreen: _stop_all_audio() - Halting audio streams.")
	if is_instance_valid(_heart_audio):
		_heart_audio.stop()
		_heart_audio.stream = null


## Unlocks the ability for the player to input a skip command after a timer duration.
func _allow_skipping() -> void:
	print("DeathScreen: _allow_skipping() - Input skip unlocked.")
	_skip_allowed = true


## Clears out sequence state and triggers an engine scene change back to the main menu.
func _return_to_main_menu() -> void:
	if not is_inside_tree():
		return

	print("DeathScreen: _return_to_main_menu() - Changing scene to main menu.")
	_is_dead = false
	_stop_all_audio()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
