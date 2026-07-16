extends Panel
class_name AudioAccessibilityPanel

## The default volume scale applied when no saved audio preference exists.
const DEFAULT_VOLUME: float = 1.0

# --- SLIDERS & INPUTS ---

## Controls the overall master output, adjusting all grouped audio buses simultaneously.
@onready var master_slider: HSlider = %MasterSlider
## Text field allowing the player to manually enter the precise master volume level.
@onready var master_input: LineEdit = %MasterLine

## Controls the volume of discrete, in-game sound effects (SFX).
@onready var sfx_slider: HSlider = %SFXSlider
## Text field allowing the player to manually enter the precise SFX volume level.
@onready var sfx_input: LineEdit = %SFXLine

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

# --- TOGGLES ---

## Toggles the flattening of 3D spatial audio into a single, centralized channel.
@onready var mono_audio_toggle: CheckButton = %MonoAudioToggle

## Toggles the rendering of visual UI indicators for critical directional sounds.
@onready var visual_cues_toggle: CheckButton = %VisualCuesToggle

## Toggles the display of in-game waypoints or breadcrumb trails to guide the player.
@onready var nav_assist_toggle: CheckButton = %NavAssistToggle


func _ready() -> void:
	print("UI: Audio Accessibility Panel initialized.")
	
	# Connect Sliders and LineEdits
	_connect_audio_adjustment(master_slider, master_input, "Master")
	_connect_audio_adjustment(sfx_slider, sfx_input, "SFX")
	_connect_audio_adjustment(music_slider, music_input, "Music")
	_connect_audio_adjustment(voice_slider, voice_input, "Voice")
	_connect_audio_adjustment(ambient_slider, ambient_input, "Ambient")
	
	# Connect Toggles
	if mono_audio_toggle:
		mono_audio_toggle.toggled.connect(_on_mono_audio_toggled)
	if visual_cues_toggle:
		visual_cues_toggle.toggled.connect(_on_visual_cues_toggled)
	if nav_assist_toggle:
		nav_assist_toggle.toggled.connect(_on_nav_assist_toggled)
		
	_load_audio_settings()


func _connect_audio_adjustment(
	slider: HSlider, input_box: LineEdit, bus_name: String
) -> void:
	if slider and input_box:
		print("UI: Connecting slider and input for audio bus: ", bus_name)
		slider.value_changed.connect(_on_volume_changed.bind(input_box, bus_name))
		slider.drag_ended.connect(_on_volume_drag_ended.bind(bus_name, slider))
		input_box.text_submitted.connect(
			_on_volume_input_submitted.bind(bus_name, slider)
		)
		input_box.focus_entered.connect(_on_volume_focus_entered.bind(input_box))
		input_box.focus_exited.connect(
			_on_volume_focus_exited.bind(input_box, slider, bus_name)
		)


func _connect_slider(slider: HSlider, bus_name: String) -> void:
	if slider:
		print("UI: Connecting slider for audio bus: ", bus_name)
		slider.value_changed.connect(_on_volume_changed.bind(bus_name))
		slider.drag_ended.connect(_on_volume_drag_ended.bind(bus_name, slider))


func _load_audio_settings() -> void:
	print("UI: Loading audio and accessibility data from GlobalSettings.")
	
	# Load Volume Sliders and Inputs
	_apply_and_set("Master", master_slider, master_input)
	_apply_and_set("SFX", sfx_slider, sfx_input)
	_apply_and_set("Music", music_slider, music_input)
	_apply_and_set("Voice", voice_slider, voice_input)
	_apply_and_set("Ambient", ambient_slider, ambient_input)

	# Load Accessibility Toggles
	var is_mono: bool = GlobalSettings.get_setting("Accessibility", "mono_audio", false) as bool
	if mono_audio_toggle:
		mono_audio_toggle.button_pressed = is_mono
		_apply_mono_audio(is_mono)

	if visual_cues_toggle:
		var visual_cues: bool = GlobalSettings.get_setting("Accessibility", "visual_audio_cues", false) as bool
		visual_cues_toggle.button_pressed = visual_cues

	if nav_assist_toggle:
		var nav_assist: bool = GlobalSettings.get_setting("Accessibility", "navigation_assist", false) as bool
		nav_assist_toggle.button_pressed = nav_assist


func _apply_and_set(bus_name: String, slider: HSlider, input_box: LineEdit) -> void:
	var vol: float = GlobalSettings.get_setting(
		"Audio", bus_name, DEFAULT_VOLUME
	) as float
	
	if slider:
		slider.value = vol
	if input_box:
		input_box.text = str(int(vol))
		
	_set_bus_volume(bus_name, vol)


func _on_volume_changed(
	value: float, input_node: LineEdit, bus_name: String
) -> void:
	# Does not write to disk, only adjusts volume in real-time while dragging
	if not input_node.has_focus():
		input_node.text = str(int(value))
	_set_bus_volume(bus_name, value)


func _on_volume_drag_ended(value_changed: bool, bus_name: String, slider: HSlider) -> void:
	if value_changed and slider:
		print("System: Player permanently adjusted ", bus_name, " volume to: ", slider.value)
		GlobalSettings.save_setting("Audio", bus_name, slider.value)


func _set_bus_volume(bus_name: String, slider_value: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		# 1. Normalize the 0-100 slider value to a 0.0-1.0 scale
		var normalized_value: float = slider_value / 100.0
		
		# 2. Clamp to avoid log(0) errors when the slider is at 0
		var clamped_value: float = maxf(normalized_value, 0.0001)
		
		# 3. Apply to the audio server safely
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(clamped_value))
		
		# 4. Mute if the slider is at the absolute bottom
		var is_muted: bool = slider_value <= 0.1
		AudioServer.set_bus_mute(bus_idx, is_muted)
		
		print("Audio: Volume for '", bus_name, "' set to ", slider_value, " (Muted: ", is_muted, ")")


func _on_mono_audio_toggled(button_pressed: bool) -> void:
	print("UI: Mono audio accessibility toggled to: ", button_pressed)
	GlobalSettings.save_setting("Accessibility", "mono_audio", button_pressed)
	_apply_mono_audio(button_pressed)


func _apply_mono_audio(is_mono: bool) -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
		
	print("System: Applying Mono Audio routing on Master bus. State: ", is_mono)
	
	# Iterate through the effects on the Master bus to find the StereoEnhance effect
	var effect_count: int = AudioServer.get_bus_effect_count(master_idx)
	for i: int in range(effect_count):
		var effect: AudioEffect = AudioServer.get_bus_effect(master_idx, i)
		if effect is AudioEffectStereoEnhance:
			# If mono is true, bypass the stereo enhancement (or vice versa depending on your effect setup)
			# Alternatively, if you are using an effect specifically to crush to mono, toggle its bypass here.
			AudioServer.set_bus_effect_enabled(master_idx, i, is_mono)
			print("System: Mono effect toggle applied at index: ", i)
			return
			
	print("Warning: Mono audio effect not found on Master bus.")


func _on_visual_cues_toggled(button_pressed: bool) -> void:
	print("UI: Visual audio cues accessibility toggled to: ", button_pressed)
	GlobalSettings.save_setting("Accessibility", "visual_audio_cues", button_pressed)


func _on_nav_assist_toggled(button_pressed: bool) -> void:
	print("UI: Navigation assist toggled to: ", button_pressed)
	GlobalSettings.save_setting("Accessibility", "navigation_assist", button_pressed)


func _on_volume_input_submitted(
	new_text: String, bus_name: String, slider_node: HSlider
) -> void:
	# Clamping between 0 and 100 based on the normalization in _set_bus_volume
	var new_val: float = clampf(new_text.to_float(), 0.0, 100.0)
	slider_node.value = new_val
	slider_node.release_focus()
	
	print("UI: Player manually typed ", bus_name, " volume input: ", new_val)
	GlobalSettings.save_setting("Audio", bus_name, new_val)
	_set_bus_volume(bus_name, new_val)


func _on_volume_focus_entered(input_node: LineEdit) -> void:
	print("UI: Player focused volume input box.")
	input_node.text = ""


func _on_volume_focus_exited(
	input_node: LineEdit, slider_node: HSlider, bus_name: String
) -> void:
	print("UI: Player unfocused volume input box for: ", bus_name)
	var current_text: String = input_node.text.strip_edges()
	
	if current_text == "":
		input_node.text = str(int(slider_node.value))
	else:
		_on_volume_input_submitted(current_text, bus_name, slider_node)
