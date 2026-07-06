class_name TinnitusEffect
extends AudioStreamPlayer

var playback: AudioStreamGeneratorPlayback
var phase: float = 0.0
var frequency: float = 6500.0
var sample_rate: float = 44100.0
var duration: float = 4.0


func _ready() -> void:
	print(
		"TinnitusEffect: _ready() called. Generating procedural ear ring for ",
		duration,
		" seconds."
	)

	var generator := AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	stream = generator

	bus = "Master"

	play()
	playback = get_stream_playback()
	_fill_buffer()

	var tween: Tween = create_tween()
	tween.tween_property(self, "volume_db", -60.0, duration).set_ease(Tween.EASE_IN_OUT).set_trans(
		Tween.TRANS_SINE
	)
	tween.tween_callback(queue_free)


func _process(_delta: float) -> void:
	_fill_buffer()


func _fill_buffer() -> void:
	if not is_instance_valid(playback):
		return

	var frames_available: int = playback.get_frames_available()
	var increment: float = (frequency * TAU) / sample_rate

	for i: int in range(frames_available):
		var sample: float = sin(phase) * 0.05
		playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + increment, TAU)
