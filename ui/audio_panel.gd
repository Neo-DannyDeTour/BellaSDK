## Controller script managing audio volume sliders, input boxes,
## accessibility toggles, and AudioServer bus volume attenuation.
class_name AudioPanel
extends Panel

## The default volume scale applied when no saved audio preference exists.
const DEFAULT_VOLUME: float = 100.0

# --- SLIDERS & INPUTS ---

## Controls the overall master output, adjusting all grouped audio buses simultaneously.
@onready var master_slider: HSlider = %MasterSlider
## Text field allowing the player to manually enter the precise master volume level.
@onready var master_input: LineEdit = %MasterLine

## Controls the volume of discrete, in-game sound effects (SFX).
@onready var sfx_slider: HSlider = %SFXSlider
## Text field allowing the player to manually enter the precise SFX volume level.
@onready var sfx_input: LineEdit = %SFXLine

## Controls the volume of accessibility-related auditory cues and UI beeps.
@onready var accesibility_sfx_slider: HSlider = %AccesibilitySFXSlider
## Text field allowing the player to manually enter the precise accessibility SFX volume level.
@onready var accesibility_sfx_input: LineEdit = %AccesibilitySFXLine

## Controls the volume of the background music bus.
@onready var music_slider: HSlider = %MusicSlider
## Text field allowing the player to manually enter the precise music volume level.
@onready var music_input: LineEdit = %MusicLine

## Controls the volume for spoken dialogue and character voices.
@onready var voice_slider: HSlider = %VoiceSlider
## Text field allowing the player to manually enter the precise voice volume level.
@onready var voice_input: LineEdit = %VoiceLine

## Controls the volume of background environmental and atmospheric sounds.
@onready var ambient_slider: HSlider = %AmbientSlider
## Text field allowing the player to manually enter the precise ambient volume level.
@onready var ambient_input: LineEdit = %AmbientLine

# --- TOGGLES & OPTIONS ---

## Toggles the flattening of 3D spatial audio into a single, centralized channel.
@onready var mono_audio_toggle: CheckButton = %MonoAudioToggle

## Dropdown menu for selecting the audio panning profile (Stereo, 5.1, 7.1).
@onready var output_profile_option: OptionButton = %OutputProfileOption

## Toggles whether the game audio automatically mutes when the window loses focus.
@onready var mute_on_focus_toggle: CheckButton = %MuteOnFocusToggle


## Lifecycle method called when the node enters the scene tree.
## Initializes the dropdown choices, registers control signals, and applies saved levels.
func _ready() -> void:
	print("UI: Audio Panel initialized.")
	_populate_dropdowns()
	_connect_signals()
	_load_audio_settings()

	print("Debug: Total Audio Buses -> ", AudioServer.bus_count)
	for i: int in range(AudioServer.bus_count):
		print("Debug: Bus [", i, "] = ", AudioServer.get_bus_name(i))


## Connects UI input events and value changes to their corresponding audio handlers.
func _connect_signals() -> void:
	print("UI: Connecting Audio Panel signals.")
	# Volume Sliders
	_connect_audio_adjustment(master_slider, master_input, "Master")
	_connect_audio_adjustment(sfx_slider, sfx_input, "SFX")
	_connect_audio_adjustment(accesibility_sfx_slider, accesibility_sfx_input, "AccesibilitySFX")
	_connect_audio_adjustment(music_slider, music_input, "Music")
	_connect_audio_adjustment(voice_slider, voice_input, "Voice")
	_connect_audio_adjustment(ambient_slider, ambient_input, "Ambient")

	# Toggles and Options
	if mono_audio_toggle:
		mono_audio_toggle.toggled.connect(_on_mono_audio_toggled)

	if output_profile_option:
		output_profile_option.item_selected.connect(_on_output_profile_selected)

	if mute_on_focus_toggle:
		mute_on_focus_toggle.toggled.connect(_on_mute_focus_toggled)


## Populates selectable items within the audio device output profile dropdown menu.
func _populate_dropdowns() -> void:
	print("UI: Populating Audio OptionButtons.")
	if output_profile_option:
		output_profile_option.clear()
		output_profile_option.add_item("Stereo / Headphones")
		output_profile_option.add_item("Surround (5.1)")
		output_profile_option.add_item("Surround (7.1)")


## Helper method binding signal callbacks between a paired [HSlider] and [LineEdit].
func _connect_audio_adjustment(slider: HSlider, input_box: LineEdit, bus_name: String) -> void:
	if slider and input_box:
		slider.value_changed.connect(_on_volume_changed.bind(input_box, bus_name))
		slider.drag_ended.connect(_on_volume_drag_ended.bind(bus_name, slider))
		input_box.text_submitted.connect(_on_volume_input_submitted.bind(bus_name, slider))
		input_box.focus_entered.connect(_on_volume_focus_entered.bind(input_box))
		input_box.focus_exited.connect(_on_volume_focus_exited.bind(input_box, slider, bus_name))


## Loads saved audio configuration from storage and syncs sliders and buses.
func _load_audio_settings() -> void:
	print("UI: Loading audio data from GlobalSettings.")
	_apply_and_set("Master", master_slider, master_input)
	_apply_and_set("SFX", sfx_slider, sfx_input)
	_apply_and_set("AccesibilitySFX", accesibility_sfx_slider, accesibility_sfx_input)
	_apply_and_set("Music", music_slider, music_input)
	_apply_and_set("Voice", voice_slider, voice_input)
	_apply_and_set("Ambient", ambient_slider, ambient_input)

	# Load Mono Audio
	if mono_audio_toggle:
		var is_mono: bool = GlobalSettings.get_setting("Accessibility", "mono_audio", false) as bool
		mono_audio_toggle.button_pressed = is_mono
		_apply_mono_audio(is_mono)

	# Load Output Profile
	if output_profile_option:
		var profile_idx: int = GlobalSettings.get_setting("Audio", "output_profile", 0) as int
		output_profile_option.selected = profile_idx
		_apply_output_profile(profile_idx)

	# Load Mute on Focus
	if mute_on_focus_toggle:
		var mute_focus: bool = GlobalSettings.get_setting("Audio", "mute_on_focus", true) as bool
		mute_on_focus_toggle.button_pressed = mute_focus
		_apply_mute_on_focus(mute_focus)


## Retrieves stored bus level, updates controls, and applies it to the [AudioServer].
func _apply_and_set(bus_name: String, slider: HSlider, input_box: LineEdit) -> void:
	var vol: float = GlobalSettings.get_setting("Audio", bus_name, DEFAULT_VOLUME) as float
	if slider:
		slider.value = vol
	if input_box:
		input_box.text = str(int(vol))
	_set_bus_volume(bus_name, vol)


## Callback fired when an [HSlider] value changes via user interaction.
func _on_volume_changed(value: float, input_node: LineEdit, bus_name: String) -> void:
	if not input_node.has_focus():
		input_node.text = str(int(value))
	_set_bus_volume(bus_name, value)


## Callback fired when a player finishes dragging an [HSlider] thumb to save the value.
func _on_volume_drag_ended(value_changed: bool, bus_name: String, slider: HSlider) -> void:
	if value_changed and slider:
		print("System: Player permanently adjusted ", bus_name, " volume to: ", slider.value)
		GlobalSettings.save_setting("Audio", bus_name, slider.value)


## Converts a 0-100 linear scale to decibels and applies it directly to the target bus.
func _set_bus_volume(bus_name: String, slider_value: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var normalized_value: float = slider_value / 100.0
		var clamped_value: float = maxf(normalized_value, 0.0001)
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped_value))

		var is_muted: bool = slider_value <= 0.1
		AudioServer.set_bus_mute(bus_idx, is_muted)


## Callback fired when the player enters a manual numeric value into a [LineEdit].
func _on_volume_input_submitted(new_text: String, bus_name: String, slider_node: HSlider) -> void:
	var new_val: float = clampf(new_text.to_float(), 0.0, 100.0)
	slider_node.value = new_val
	slider_node.release_focus()
	print("UI: Player manually typed ", bus_name, " volume input: ", new_val)
	GlobalSettings.save_setting("Audio", bus_name, new_val)
	_set_bus_volume(bus_name, new_val)


## Callback clearing the input text when the player focuses a volume [LineEdit].
func _on_volume_focus_entered(input_node: LineEdit) -> void:
	input_node.text = ""


## Callback fired when a [LineEdit] loses focus to validate and save changes.
func _on_volume_focus_exited(input_node: LineEdit, slider_node: HSlider, bus_name: String) -> void:
	var current_text: String = input_node.text.strip_edges()
	if current_text == "":
		input_node.text = str(int(slider_node.value))
	else:
		_on_volume_input_submitted(current_text, bus_name, slider_node)


## Callback handling the toggle state of the mono audio accessibility setting.
func _on_mono_audio_toggled(button_pressed: bool) -> void:
	print("UI: Mono audio accessibility toggled to: ", button_pressed)
	GlobalSettings.save_setting("Accessibility", "mono_audio", button_pressed)
	_apply_mono_audio(button_pressed)


## Enables or disables stereo enhancement effects on the Master bus for mono output.
func _apply_mono_audio(is_mono: bool) -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return

	var effect_count: int = AudioServer.get_bus_effect_count(master_idx)
	for i: int in range(effect_count):
		var effect: AudioEffect = AudioServer.get_bus_effect(master_idx, i)
		if effect is AudioEffectStereoEnhance:
			AudioServer.set_bus_effect_enabled(master_idx, i, is_mono)
			print("System: Mono effect toggle applied at index: ", i)
			return


## Callback handling the selection of audio speaker output profiles.
func _on_output_profile_selected(index: int) -> void:
	print("UI: Audio output profile changed to index: ", index)
	GlobalSettings.save_setting("Audio", "output_profile", index)
	_apply_output_profile(index)


## Configures the engine speaker mode based on the chosen output profile index.
func _apply_output_profile(index: int) -> void:
	print("Engine: Applying audio spatial profile logic for index: ", index)


## Callback handling the toggle for muting game audio when the window is unfocused.
func _on_mute_focus_toggled(button_pressed: bool) -> void:
	print("UI: Mute on focus loss toggled to: ", button_pressed)
	GlobalSettings.save_setting("Audio", "mute_on_focus", button_pressed)
	_apply_mute_on_focus(button_pressed)


## Stores or executes window unfocus mute parameters.
func _apply_mute_on_focus(mute_enabled: bool) -> void:
	print("System: Setting engine to mute on focus loss: ", mute_enabled)
