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


## Registers group, establishes physics, locates visualizers, and starts auto playback.
func _ready() -> void:
	print("MusicTrigger3D: Initializing music trigger node: ", name)
	add_to_group(TRIGGER_GROUP)
	_setup_collision()
	_locate_visualizer()
	_sync_from_visualizer()
	if Engine.is_editor_hint():
		return
	Utilities.safe_connect(body_entered, _on_body_entered)
	var master: MusicTrigger3D = _resolve_master_trigger()
	if master == self and audio_stream != null:
		_ensure_players_initialized()
		if auto_play_on_start:
			play_section(section_index, get_start_timestamp(), get_end_timestamp(), is_looping)


## Updates editor visualizer syncing and manages active playback loop timers.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_process_editor_preview()
		_sync_from_visualizer()
		return
	if _active_player == null or not _active_player.playing:
		return
	var pos: float = _active_player.get_playback_position()
	_handle_loop_and_queue(pos)


## Assigns physics collision layers and creates collision shape if needed.
func _setup_collision() -> void:
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_PLAYER
	_collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision_shape == null:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "CollisionShape3D"
		add_child(_collision_shape)


## Resolves visualizer child reference using [NodeQuery].
func _locate_visualizer() -> void:
	if visualizer != null:
		return
	visualizer = get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	if visualizer == null:
		visualizer = (
			NodeQuery.find_first_child_of_type(self, EditorTriggerVisualizer)
			as EditorTriggerVisualizer
		)


## Syncs collision shape bounds with visualizer parameters.
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


## Updates display label text on visualizer mesh.
func _sync_label() -> void:
	if not is_inside_tree() or visualizer == null or not is_instance_valid(visualizer):
		return
	var start_t: float = get_start_timestamp()
	var end_t: float = get_end_timestamp()
	var label: String = "Part %d (%.1fs - %.1fs)" % [section_index, start_t, end_t]
	visualizer.trigger_text = label


## Returns the effective section start timestamp in seconds.
func get_start_timestamp() -> float:
	if manual_override_time:
		return custom_start_time
	return 0.0


## Returns the effective section end timestamp in seconds.
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


## Monitors playback position to execute loops or queued transitions.
func _handle_loop_and_queue(pos: float) -> void:
	if pos >= _active_end_time - BOUNDARY_TOLERANCE_SEC:
		if _queued_section != -1:
			_execute_transition()
		elif _active_looping:
			_active_player.seek(_active_start_time)
		else:
			_active_player.stop()


## Handles player physics body entry and requests section switch on master.
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
	print("MusicTrigger3D: Body entered volume. Switching to section: ", section_index)
	master.request_switch(
		section_index, start_t, end_t, is_looping, switch_mode, crossfade_duration
	)


## Locates master music trigger hosting primary audio stream.
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


## Instantiates primary and secondary audio players if uninitialized.
func _ensure_players_initialized() -> void:
	if _player_a == null:
		_player_a = _create_audio_player("PlayerA")
	if _player_b == null:
		_player_b = _create_audio_player("PlayerB")
	if _active_player == null:
		_active_player = _player_a
	if _standby_player == null:
		_standby_player = _player_b


## Schedules or immediately executes musical section switch.
func request_switch(
	sec_idx: int, start_t: float, end_t: float, looping: bool, mode: SwitchMode, fade_time: float
) -> void:
	print("MusicTrigger3D: Switch requested for section: ", sec_idx)
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


## Commences playback of designated section on active audio player.
func play_section(
	sec_idx: int, start_t: float = -1.0, end_t: float = -1.0, looping: bool = true
) -> void:
	print("MusicTrigger3D: Playing section ", sec_idx, " from ", start_t, " to ", end_t)
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


## Performs smooth audio crossfade transition between active and standby players.
func _execute_transition() -> void:
	print("MusicTrigger3D: Executing audio transition to section: ", _queued_section)
	_ensure_players_initialized()
	_current_section = _queued_section
	_active_start_time = _queued_start_time
	_active_end_time = _queued_end_time
	_active_looping = _queued_looping
	_queued_section = -1
	_standby_player.stream = audio_stream
	_standby_player.volume_db = -80.0
	_standby_player.play(_active_start_time)
	_crossfade_tween = Utilities.reset_tween(self, _crossfade_tween)
	if _queued_crossfade > 0.0:
		_crossfade_tween.set_parallel(true)
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


## Toggles editor preview audio playback.
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


## Checks editor preview playback bounds and handles looping.
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


## Halts editor preview playback safely.
func _preview_player_stop() -> void:
	if _preview_player != null:
		_preview_player.stop()
	preview_in_editor = false


## Obtains a pooled 2D audio stream player from [AudioPool].
func _create_audio_player(player_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioPool.get_pooled_player_2d()
	if not is_instance_valid(player):
		player = AudioStreamPlayer.new()
		player.name = player_name
		add_child(player)
	print("MusicTrigger3D: Obtained pooled audio player for: ", player_name)
	return player
