@tool
## 3D music volume triggering section switches and editor audio.
class_name MusicTrigger3D
extends Area3D

## Timing rule defining when an incoming musical switch takes place.
enum SwitchMode {
	IMMEDIATE,
	END_OF_SECTION,
}

## Emitted when playback transitions to [param section_number].
signal section_changed(section_number: int)

## Scene tree group identifying active music triggers.
const TRIGGER_GROUP: String = "music_triggers"

## Time tolerance in seconds for loop boundaries.
const BOUNDARY_TOLERANCE_SEC: float = 0.05

@export_group("Visualizer Connection")

## Linked [EditorTriggerVisualizer] node rendering 3D bounds.
@export var visualizer: EditorTriggerVisualizer:
	set(value):
		visualizer = value
		_sync_from_visualizer()

@export_group("Music Master Settings")

## Audio stream containing the full song track. Master trigger holds this.
@export var audio_stream: AudioStream:
	set(value):
		audio_stream = value
		_sync_label()

## Toggle to preview audio playback directly in the editor.
@export var preview_in_editor: bool = false:
	set(value):
		if preview_in_editor == value:
			return
		preview_in_editor = value
		_toggle_editor_preview(value)

## Automatically begins playback of this section on game start.
@export var auto_play_on_start: bool = false

@export_group("Trigger Switching")

## Explicit master [MusicTrigger3D] hosting the audio stream.
## Leave empty on the master node itself.
@export var connected_music_trigger: MusicTrigger3D:
	set(value):
		if value == self:
			connected_music_trigger = null
		else:
			connected_music_trigger = value
		_sync_label()

## Timing rule dictating when the section switch takes place.
@export var switch_mode: SwitchMode = SwitchMode.IMMEDIATE

## Crossfade duration in seconds between audio transitions.
@export var crossfade_duration: float = 0.3

## When true, fires only once during gameplay.
@export var trigger_once: bool = false

@export_group("Section Configuration")

## Musical section index (1, 2, 3...) of this trigger.
@export var section_index: int = 1:
	set(value):
		section_index = maxi(value, 1)
		_sync_label()

## Enables manual start and end timestamp overrides.
@export var manual_override_time: bool = true:
	set(value):
		manual_override_time = value
		_sync_label()

## Custom manual start timestamp in seconds.
@export var custom_start_time: float = 0.0:
	set(value):
		custom_start_time = maxf(value, 0.0)
		_sync_label()

## Custom manual end timestamp in seconds.
@export var custom_end_time: float = 16.0:
	set(value):
		custom_end_time = maxf(value, 0.0)
		_sync_label()

## Whether this section loops until another section triggers.
@export var is_looping: bool = true

## Flag indicating whether this trigger has already fired.
var _has_triggered: bool = false

## Primary audio player handling current playback.
var _player_a: AudioStreamPlayer

## Secondary audio player handling crossfades.
var _player_b: AudioStreamPlayer

## Standalone audio player dedicated to in-editor previews.
var _preview_player: AudioStreamPlayer

## Active audio player currently emitting sound.
var _active_player: AudioStreamPlayer

## Inactive player standing by to receive next transition.
var _standby_player: AudioStreamPlayer

## Tween controlling crossfade transitions between players.
var _crossfade_tween: Tween

## Child collision shape node providing physics bounds.
var _collision_shape: CollisionShape3D

## Currently playing section index on master trigger.
var _current_section: int = -1

## Section index queued for transition.
var _queued_section: int = -1

## Start time in seconds for the queued section.
var _queued_start_time: float = 0.0

## End time in seconds for the queued section.
var _queued_end_time: float = 0.0

## Whether the queued section loops after playing.
var _queued_looping: bool = true

## Active start timestamp in seconds for playback.
var _active_start_time: float = 0.0

## Active end timestamp in seconds for playback.
var _active_end_time: float = 0.0

## Whether the currently playing section loops.
var _active_looping: bool = true

## Queued switch mode awaiting section completion.
var _queued_switch_mode: SwitchMode = SwitchMode.IMMEDIATE

## Queued crossfade duration for next transition.
var _queued_crossfade: float = 0.3


func _ready() -> void:
	add_to_group(TRIGGER_GROUP)
	_setup_collision()
	_locate_visualizer()
	_sync_from_visualizer()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	var master: MusicTrigger3D = _resolve_master_trigger()
	if master == self and audio_stream != null:
		_ensure_players_initialized()
		if auto_play_on_start:
			play_section(section_index, get_start_timestamp(), get_end_timestamp(), is_looping)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_process_editor_preview()
		_sync_from_visualizer()
		return
	if _active_player == null or not _active_player.playing:
		return
	var pos: float = _active_player.get_playback_position()
	_handle_loop_and_queue(pos)


func _setup_collision() -> void:
	collision_layer = 0
	collision_mask = 2
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		add_child(_collision_shape)


func _locate_visualizer() -> void:
	if visualizer != null:
		return
	visualizer = get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	if visualizer == null:
		visualizer = find_child("*Visualizer*", false, false) as EditorTriggerVisualizer


func _sync_from_visualizer() -> void:
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if visualizer == null:
		_locate_visualizer()
	_sync_label()
	if visualizer == null or not is_instance_valid(_collision_shape):
		return
	if visualizer.shape_type == EditorTriggerVisualizer.ShapeType.BOX:
		var box: BoxShape3D = (
			_collision_shape.shape if _collision_shape.shape is BoxShape3D else null
		)
		if box == null:
			box = BoxShape3D.new()
			_collision_shape.shape = box
		box.size = visualizer.trigger_size
	elif visualizer.shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
		var sphere: SphereShape3D = (
			_collision_shape.shape if _collision_shape.shape is SphereShape3D else null
		)
		if sphere == null:
			sphere = SphereShape3D.new()
			_collision_shape.shape = sphere
		sphere.radius = visualizer.trigger_size.x / 2.0


func _sync_label() -> void:
	if not is_inside_tree() or visualizer == null or not is_instance_valid(visualizer):
		return
	var start_t: float = get_start_timestamp()
	var end_t: float = get_end_timestamp()
	var label: String = "Part %d (%.1fs - %.1fs)" % [section_index, start_t, end_t]
	visualizer.trigger_text = label


func get_start_timestamp() -> float:
	if manual_override_time:
		return custom_start_time
	return 0.0


func get_end_timestamp() -> float:
	if manual_override_time:
		return custom_end_time
	var master: MusicTrigger3D = _resolve_master_trigger()
	var stream: AudioStream = audio_stream
	if master != null and master.audio_stream != null:
		stream = master.audio_stream
	if stream != null:
		return stream.get_length()
	return custom_end_time


func _handle_loop_and_queue(pos: float) -> void:
	if pos >= _active_end_time - BOUNDARY_TOLERANCE_SEC:
		if _queued_section != -1:
			_execute_transition()
		elif _active_looping:
			_active_player.seek(_active_start_time)
		else:
			_active_player.stop()


func _on_body_entered(_body: Node3D) -> void:
	if trigger_once and _has_triggered:
		return
	var master: MusicTrigger3D = _resolve_master_trigger()
	if master == null:
		push_warning("MusicTrigger3D: No master music trigger located for: " + name)
		return
	_has_triggered = true
	var start_t: float = get_start_timestamp()
	var end_t: float = get_end_timestamp()
	master.request_switch(
		section_index, start_t, end_t, is_looping, switch_mode, crossfade_duration
	)


## Locates the proper master trigger:
## 1. If self has an audio_stream, self is master.
## 2. If connected_music_trigger is explicitly set, use it.
## 3. Otherwise find another MusicTrigger3D that owns an audio_stream.
func _resolve_master_trigger() -> MusicTrigger3D:
	if audio_stream != null:
		return self
	if connected_music_trigger != null and connected_music_trigger != self:
		return connected_music_trigger
	if not is_inside_tree():
		return null
	var triggers: Array[Node] = get_tree().get_nodes_in_group(TRIGGER_GROUP)
	for node: Node in triggers:
		var trigger: MusicTrigger3D = node if node is MusicTrigger3D else null
		if trigger != null and trigger != self and trigger.audio_stream != null:
			return trigger
	return null


func _ensure_players_initialized() -> void:
	if _player_a == null:
		_player_a = _create_audio_player("PlayerA")
	if _player_b == null:
		_player_b = _create_audio_player("PlayerB")
	if _active_player == null:
		_active_player = _player_a
	if _standby_player == null:
		_standby_player = _player_b


func request_switch(
	sec_idx: int, start_t: float, end_t: float, looping: bool, mode: SwitchMode, fade_time: float
) -> void:
	_ensure_players_initialized()
	if not _active_player.playing:
		play_section(sec_idx, start_t, end_t, looping)
		return
	if sec_idx == _current_section and _queued_section == -1:
		return
	_queued_section = sec_idx
	_queued_start_time = start_t
	_queued_end_time = end_t
	_queued_looping = looping
	_queued_switch_mode = mode
	_queued_crossfade = fade_time
	if mode == SwitchMode.IMMEDIATE:
		_execute_transition()


func play_section(
	sec_idx: int, start_t: float = -1.0, end_t: float = -1.0, looping: bool = true
) -> void:
	_ensure_players_initialized()
	_current_section = sec_idx
	_queued_section = -1
	_active_start_time = start_t if start_t >= 0.0 else get_start_timestamp()
	_active_end_time = end_t if end_t >= 0.0 else get_end_timestamp()
	_active_looping = looping
	_active_player.stream = audio_stream
	_active_player.volume_db = 0.0
	_active_player.play(_active_start_time)
	section_changed.emit(_current_section)


func _execute_transition() -> void:
	_ensure_players_initialized()
	_current_section = _queued_section
	_active_start_time = _queued_start_time
	_active_end_time = _queued_end_time
	_active_looping = _queued_looping
	_queued_section = -1
	_standby_player.stream = audio_stream
	_standby_player.volume_db = -80.0
	_standby_player.play(_active_start_time)
	if is_instance_valid(_crossfade_tween) and _crossfade_tween.is_running():
		_crossfade_tween.kill()
	if _queued_crossfade > 0.0:
		_crossfade_tween = create_tween().set_parallel(true)
		_crossfade_tween.tween_property(_standby_player, "volume_db", 0.0, _queued_crossfade)
		_crossfade_tween.tween_property(_active_player, "volume_db", -80.0, _queued_crossfade)
		var old_active: AudioStreamPlayer = _active_player
		_active_player = _standby_player
		_standby_player = old_active
		_crossfade_tween.chain().tween_callback(old_active.stop)
	else:
		_standby_player.volume_db = 0.0
		_active_player.stop()
		var old_active: AudioStreamPlayer = _active_player
		_active_player = _standby_player
		_standby_player = old_active
	section_changed.emit(_current_section)


func _toggle_editor_preview(enable: bool) -> void:
	if not Engine.is_editor_hint():
		return
	var master: MusicTrigger3D = _resolve_master_trigger()
	var stream: AudioStream = master.audio_stream if master != null else null
	if master == null or stream == null:
		push_warning("MusicTrigger3D: Cannot preview. No audio stream found on master.")
		_preview_player_stop()
		return
	if _preview_player == null:
		_preview_player = _create_audio_player("EditorPreviewPlayer")
	if enable:
		_preview_player.stream = stream
		_preview_player.volume_db = 0.0
		_preview_player.play(get_start_timestamp())
	else:
		_preview_player_stop()


func _process_editor_preview() -> void:
	if not preview_in_editor or _preview_player == null:
		return
	if not _preview_player.playing:
		return
	var pos: float = _preview_player.get_playback_position()
	var end_t: float = get_end_timestamp()
	if pos >= end_t - BOUNDARY_TOLERANCE_SEC:
		if is_looping:
			_preview_player.seek(get_start_timestamp())
		else:
			_preview_player_stop()


func _preview_player_stop() -> void:
	if _preview_player != null:
		_preview_player.stop()
	# Set internal backing variable directly to prevent setter recursion loop
	preview_in_editor = false


func _create_audio_player(player_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	add_child(player)
	return player
