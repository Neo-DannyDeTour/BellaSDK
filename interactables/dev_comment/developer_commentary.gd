extends StaticBody3D
class_name DeveloperCommentary

@export_group("Commentary Settings")
@export var interact_sound: AudioStream = null
@export var commentary_title: String = "Developer Note"
@export_multiline var commentary_content: String = ""
@export var use_rich_text: bool = true
@export var spin_speed: float = 3.0

@onready var interact_comp: Interact_Component = $Interact_Component
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var commentary_ui: CanvasLayer = $CommentaryUI
@onready var label_title: Label = $CommentaryUI/Panel/VBoxContainer/TitleLabel
@onready var label_content: RichTextLabel = $CommentaryUI/Panel/VBoxContainer/AutoScrollContainer/MarginContainer/ContentLabel
@onready var sprite: Sprite3D = $Sprite3D
@onready var equalizer_mesh: MeshInstance3D = $EqualizerMesh

var is_open: bool = false
var active_player: CharacterBody3D = null
var _initial_billboard_mode: BaseMaterial3D.BillboardMode = BaseMaterial3D.BILLBOARD_DISABLED

var _spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var _bus_idx: int = -1
var _audio_data: Array[float] = []
const VU_COUNT: int = 32


func _ready() -> void:
	commentary_ui.hide()
	equalizer_mesh.hide()
	label_title.text = commentary_title
	_initial_billboard_mode = sprite.billboard as BaseMaterial3D.BillboardMode
	
	if use_rich_text:
		label_content.bbcode_enabled = true
	else: 
		label_content.bbcode_enabled = false
		
	label_content.text = commentary_content
	
	if interact_comp:
		interact_comp.interacted.connect(_on_interacted)
		
	_initialize_audio_spectrum()


func _process(delta: float) -> void:
	if is_open:
		sprite.rotate_x(spin_speed * delta)
	
	_update_equalizer()


func _initialize_audio_spectrum() -> void:
	print("DeveloperCommentary: Initializing audio spectrum analyzer for bus 'Commentary'.")
	_audio_data.resize(VU_COUNT)
	_audio_data.fill(0.0)
	
	_bus_idx = AudioServer.get_bus_index("Commentary")
	if _bus_idx >= 0:
		_spectrum_analyzer = AudioServer.get_bus_effect_instance(_bus_idx, 0) as AudioEffectSpectrumAnalyzerInstance


func _update_equalizer() -> void:
	var mat: ShaderMaterial = equalizer_mesh.material_override as ShaderMaterial
	if not mat:
		return
		
	if _spectrum_analyzer and audio_player.playing:
		var prev_hz: float = 20.0
		for i: int in range(VU_COUNT):
			var hz: float = prev_hz * 1.3 
			var magnitude: Vector2 = _spectrum_analyzer.get_magnitude_for_frequency_range(prev_hz, hz)
			var energy: float = clampf((linear_to_db(magnitude.length()) + 80.0) / 80.0, 0.0, 1.0)
			_audio_data[i] = energy
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
	commentary_ui.show()
	equalizer_mesh.show()
	
	if active_player:
		var target_pos: Vector3 = active_player.global_position
		target_pos.y = sprite.global_position.y
		if sprite.global_position.distance_to(target_pos) > 0.01:
			sprite.look_at(target_pos, Vector3.UP)
			
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED as BaseMaterial3D.BillboardMode
	
	if interact_sound and audio_player:
		audio_player.stream = interact_sound
		audio_player.play()
		
	if active_player and active_player.has_user_signal("toggled_interface"):
		active_player.emit_signal("toggled_interface", true)


func close_commentary() -> void:
	print("DeveloperCommentary: Closing UI, hiding equalizer, stopping audio, and resetting sprite.")
	is_open = false
	commentary_ui.hide()
	equalizer_mesh.hide()
	
	sprite.rotation = Vector3.ZERO 
	sprite.billboard = _initial_billboard_mode
	
	if audio_player and audio_player.playing:
		audio_player.stop()

	if active_player and active_player.has_user_signal("toggled_interface"):
		active_player.emit_signal("toggled_interface", false)
		
	active_player = null


func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		print("DeveloperCommentary: Player pressed cancel/menu. Closing.")
		close_commentary()
		get_viewport().set_input_as_handled()
