extends StaticBody3D
class_name DeveloperCommentary

@export_group("Commentary Settings")
## Interact sound.
@export var interact_sound: AudioStream = null
## Commentary title.
@export var commentary_title: String = "Developer Note"
## Commentary content.
@export_multiline var commentary_content: String = ""
## Use rich text.
@export var use_rich_text: bool = true
## Spin speed.
@export var spin_speed: float = 3.0

## Interact comp.
@onready var interact_comp: InteractComponent = $InteractComponent
## Audio player.
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
## Commentary ui.
@onready var commentary_ui: CanvasLayer = $CommentaryUI
## Label title.
@onready var label_title: Label = $CommentaryUI/Panel/VBoxContainer/TitleLabel
## Label content.
@onready var label_content: RichTextLabel = get_node(
    "CommentaryUI/Panel/VBoxContainer/AutoScrollContainer/MarginContainer/ContentLabel"
)
## Sprite.
@onready var sprite: Sprite3D = $Sprite3D
## Equalizer mesh.
@onready var equalizer_mesh: MeshInstance3D = $EqualizerMesh
## Label3D used to display the visual interaction prompt to the player in world space.
@onready var interact_prompt_label: Label3D = $InteractPromptLabel

## Is open.
var is_open: bool = false
## Active player.
var active_player: CharacterBody3D = null
## Initial billboard mode.
var _initial_billboard_mode: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_DISABLED

## Spectrum analyzer.
var _spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
## Bus idx.
var _bus_idx: int = -1
# Use PackedFloat32Array for Godot 4 shader uniform compatibility and performance
## Audio data.
var _audio_data: PackedFloat32Array = PackedFloat32Array()
const VU_COUNT: int = 32

## Tween used to animate the sprite jump and color inversion.
var _focus_tween: Tween
## Original global Y coordinate.
var _original_sprite_y: float
## Track if the player is currently focusing on this node.
var _is_focused: bool = false


func _ready() -> void:
	commentary_ui.hide()
	equalizer_mesh.hide()
	label_title.text = commentary_title
	_initial_billboard_mode = sprite.billboard as BaseMaterial3D.BillboardMode
	
	# Lock in the global world height
	_original_sprite_y = sprite.global_position.y

	if use_rich_text:
		label_content.bbcode_enabled = true
	else:
		label_content.bbcode_enabled = false

	label_content.text = commentary_content

	if interact_comp:
		interact_comp.interacted.connect(_on_interacted)
		if interact_comp.has_signal("focused"):
			interact_comp.focused.connect(_on_focused)
		if interact_comp.has_signal("unfocused"):
			interact_comp.unfocused.connect(_on_unfocused)

	if audio_player:
		audio_player.finished.connect(_on_audio_finished)

	_initialize_audio_spectrum()


func _process(delta: float) -> void:
	if is_open:
		# Rotate Y so it spins horizontally instead of tumbling vertically
		sprite.rotate_x(spin_speed * delta)

	_update_equalizer(delta)


func _initialize_audio_spectrum() -> void:
	print("DeveloperCommentary: Initializing audio spectrum analyzer for bus 'Commentary'.")
	_audio_data.resize(VU_COUNT)
	_audio_data.fill(0.0)

	_bus_idx = AudioServer.get_bus_index("Commentary")
	if _bus_idx >= 0:
		_spectrum_analyzer = (
			AudioServer.get_bus_effect_instance(_bus_idx, 0) as AudioEffectSpectrumAnalyzerInstance
		)


func _update_equalizer(delta: float) -> void:
	var mat: ShaderMaterial = equalizer_mesh.material_override as ShaderMaterial
	if not mat:
		return

	if _spectrum_analyzer and audio_player.playing:
		var prev_hz: float = 100.0
		var max_hz: float = 8000.0
		var hz_multi: float = pow(max_hz / prev_hz, 1.0 / float(VU_COUNT))

		for i: int in range(VU_COUNT):
			var hz: float = prev_hz * hz_multi

			# Use MAGNITUDE_MAX to grab the sharpest spike, avoiding a muddy average
			var mag: Vector2 = _spectrum_analyzer.get_magnitude_for_frequency_range(
				prev_hz, hz, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX
			)

			var raw_energy: float = clampf((linear_to_db(mag.length()) + 60.0) / 50.0, 0.0, 1.0)

			# Exaggerate the peaks and crush the noise by squaring the value
			raw_energy = pow(raw_energy, 2.0)

			_audio_data[i] = lerpf(_audio_data[i], raw_energy, 15.0 * delta)
			prev_hz = hz

		mat.set_shader_parameter("audio_data", _audio_data)

	mat.set_shader_parameter("is_playing", audio_player.playing)


func _on_interacted(player: CharacterBody3D) -> void:
	print("DeveloperCommentary: Player interacted with node: ", name)
	if is_open:
		close_commentary()
	else:
		active_player = player
		open_commentary()


func open_commentary() -> void:
	print("DeveloperCommentary: Opening UI, showing equalizer, playing audio, and spinning sprite.")
	is_open = true
	
	# Stop jumping and reset to baseline instantly when activated
	_stop_and_reset_jump()
	
	commentary_ui.show()
	equalizer_mesh.show()

	if active_player:
		var target_pos: Vector3 = active_player.global_position
		target_pos.y = sprite.global_position.y
		if sprite.global_position.distance_to(target_pos) > 0.01:
			sprite.look_at(target_pos, Vector3.UP, true)

	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED as BaseMaterial3D.BillboardMode

	if interact_sound and audio_player:
		audio_player.stream = interact_sound
		audio_player.play()
		
		var audio_duration: float = interact_sound.get_length()
		print("DeveloperCommentary: Emitting subtitle for length: ", audio_duration)
		Events.subtitle_requested.emit(commentary_title, commentary_content, audio_duration)

	if active_player and active_player.has_user_signal("toggled_interface"):
		active_player.emit_signal("toggled_interface", true)


func close_commentary() -> void:
	print(
        "DeveloperCommentary: Closing UI, hiding equalizer, stopping audio, and resetting sprite."
	)
	is_open = false
	commentary_ui.hide()
	equalizer_mesh.hide()

	sprite.rotation = Vector3.ZERO
	sprite.billboard = _initial_billboard_mode

	if audio_player and audio_player.playing:
		audio_player.stop()
		
	print("DeveloperCommentary: Emitting subtitle_canceled signal.")
	Events.subtitle_canceled.emit()

	if active_player and active_player.has_user_signal("toggled_interface"):
		active_player.emit_signal("toggled_interface", false)

	active_player = null
	
	# If the player is still staring at the object when it finishes, resume the jump loop
	if _is_focused:
		_start_jump_loop()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		print("DeveloperCommentary: Player pressed cancel/menu. Closing.")
		close_commentary()
		get_viewport().set_input_as_handled()


func _on_audio_finished() -> void:
	print("DeveloperCommentary: Audio track finished. Returning to idle state.")

	# Check if it's currently open just to be safe, then close everything
	if is_open:
		close_commentary()

	# Optional: Zero out the audio data so there are no visual spikes
	# if the player interacts with it again immediately.
	_audio_data.fill(0.0)


func _on_focused() -> void:
	print("DeveloperCommentary: Sprite focused.")
	_is_focused = true
	
	# Only start jumping if the commentary isn't currently playing
	if not is_open:
		_start_jump_loop()


func _on_unfocused() -> void:
	print("DeveloperCommentary: Sprite unfocused.")
	_is_focused = false
	_stop_and_reset_jump()


func _start_jump_loop() -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

	_focus_tween = create_tween()
	# Tell the tween to loop infinitely
	_focus_tween.set_loops()
	
	# Jump up and turn gray smoothly
	_focus_tween.tween_property(
		sprite, "global_position:y", _original_sprite_y + 0.15, 0.4
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_focus_tween.parallel().tween_property(sprite, "modulate", Color.GRAY, 0.4)
	
	# Fall down and turn white smoothly
	_focus_tween.chain().tween_property(
		sprite, "global_position:y", _original_sprite_y, 0.4
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_focus_tween.parallel().tween_property(sprite, "modulate", Color.WHITE, 0.4)


func _stop_and_reset_jump() -> void:
	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

	# Create a fresh tween just to smooth out the return to default
	_focus_tween = create_tween()
	_focus_tween.set_parallel(true)
	
	_focus_tween.tween_property(
		sprite, "global_position:y", _original_sprite_y, 0.2
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	_focus_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
