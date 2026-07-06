extends Panel

const DEFAULT_VOLUME: float = 1.0

@onready var master_slider: HSlider = %MasterSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var music_slider: HSlider = %MusicSlider

func _ready() -> void:
	print("UI: Audio Panel initialized.")
	_connect_slider(master_slider, "Master")
	_connect_slider(sfx_slider, "SFX")
	_connect_slider(music_slider, "Music")
	_load_audio_settings()

func _connect_slider(slider: HSlider, bus_name: String) -> void:
	slider.value_changed.connect(_on_volume_changed.bind(bus_name))
	slider.drag_ended.connect(_on_volume_drag_ended.bind(bus_name, slider))

func _load_audio_settings() -> void:
	print("UI: Loading audio data from GlobalSettings.")
	_apply_and_set("Master", master_slider)
	_apply_and_set("SFX", sfx_slider)
	_apply_and_set("Music", music_slider)

func _apply_and_set(bus_name: String, slider: HSlider) -> void:
	var vol: float = GlobalSettings.get_setting("Audio", bus_name, DEFAULT_VOLUME)
	slider.value = vol
	_set_bus_volume(bus_name, vol)

func _on_volume_changed(value: float, bus_name: String) -> void:
	_set_bus_volume(bus_name, value)

func _on_volume_drag_ended(value_changed: bool, bus_name: String, slider: HSlider) -> void:
	if value_changed:
		print("Player adjusted ", bus_name, " volume to: ", slider.value)
		GlobalSettings.save_setting("Audio", bus_name, slider.value)

func _set_bus_volume(bus_name: String, linear_value: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var clamped_value: float = maxf(linear_value, 0.0001)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped_value))
		AudioServer.set_bus_mute(bus_idx, linear_value <= 0.001)
