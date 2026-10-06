@tool
## Area3D volume managing ambient loops and pooled one-shot environmental SFX.
## Integrates [EditorTriggerVisualizer] for in-editor wireframe and bounds display.
class_name SoundscapeZone
extends Area3D

@export_group("Trigger Volume")
## Geometric shape type used for collision and visual debug bounds.
@export var shape_type: EditorTriggerVisualizer.ShapeType = EditorTriggerVisualizer.ShapeType.BOX:
	set(value):
		shape_type = value
		if is_inside_tree():
			_update_bounds()

## Dimensions of soundscape area volume in meters.
@export var zone_size: Vector3 = Vector3(1.0, 1.0, 1.0):
	set(value):
		zone_size = value
		if is_inside_tree():
			_update_bounds()

## Local offset applied to both the collision shape and the visualizer node.
@export var zone_offset: Vector3 = Vector3.ZERO:
	set(value):
		zone_offset = value
		if is_inside_tree():
			_update_bounds()

@export_group("Trigger Debug Visualizer")
## Determines if the trigger visualizer mesh should be visible in-game.
@export var show_in_game: bool = false:
	set(value):
		show_in_game = value
		if is_inside_tree():
			_update_bounds()

## Base tint and opacity applied to the volumetric inner fill.
@export var zone_color: Color = Color(0.2, 0.8, 0.6, 0.25):
	set(value):
		zone_color = value
		if is_inside_tree():
			_update_bounds()

## Edge color for the outline wireframe cage and orientation arrow.
@export var outline_color: Color = Color(0.4, 1.0, 0.8, 0.9):
	set(value):
		outline_color = value
		if is_inside_tree():
			_update_bounds()

## Allows the visualizer to remain visible through walls and level geometry.
@export var x_ray_mode: bool = false:
	set(value):
		x_ray_mode = value
		if is_inside_tree():
			_update_bounds()

## Displays an arrow pointing along -Z indicating player entry heading.
@export var show_orientation: bool = true:
	set(value):
		show_orientation = value
		if is_inside_tree():
			_update_bounds()

## Appends metric dimensions to the 3D billboard text label.
@export var show_metric_dimensions: bool = true:
	set(value):
		show_metric_dimensions = value
		if is_inside_tree():
			_update_bounds()

## Text displayed above volume wireframe in editor for identification.
@export var zone_text: String = "SOUNDSCAPE":
	set(value):
		zone_text = value
		if is_inside_tree():
			_update_bounds()

@export_group("Soundscape Settings")
## The resource containing ambient track and random sounds.
@export var soundscape: SoundscapeData

## Target volume for ambient track when fully faded in.
@export var base_volume_db: float = 0.0

## Duration in seconds for fading volume in and out.
@export var fade_duration: float = 0.5

## Keeps soundscape playing until another one is entered.
@export var persist_after_exit: bool = false

## Loops ambient track when it finishes.
@export var loop_ambient: bool = true

## Makes this the fallback soundscape when no others are active.
@export var is_default_soundscape: bool = false

## Ensures soundscape only activates very first time player enters.
@export var activate_once: bool = false

## Shared pointer tracking the currently active soundscape zone.
static var current_active_zone: SoundscapeZone = null

## Shared pointer tracking default fallback soundscape zone.
static var default_zone: SoundscapeZone = null

## Active tween handling volume fades.
var current_tween: Tween

## Primary audio stream player for background ambient music.
@onready
var ambient_player: AudioStreamPlayer = get_node_or_null("AmbientPlayer") as AudioStreamPlayer

## Internal timer used for scheduling random environmental one-shot sounds.
@onready var timer: Timer = get_node_or_null("RandomSoundTimer") as Timer

## Attached collision shape node defining trigger boundaries.
@onready
var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D

## System timestamp in milliseconds tracking last exit time.
var _last_exit_time: int = 0

## Guard tracking whether activate_once has been triggered.
var _has_been_activated: bool = false

## Debounce threshold in milliseconds preventing immediate re-triggering.
const DEBOUNCE_MSEC: int = 100


## Initializes bounds, audio buses, and connections on ready.
func _ready() -> void:
	print("SoundscapeZone: Initializing: ", name)
	_update_bounds()

	if Engine.is_editor_hint():
		return

	if is_instance_valid(ambient_player):
		ambient_player.bus = &"Ambient"
		ambient_player.volume_db = -80.0
		if not ambient_player.finished.is_connected(_on_ambient_finished):
			ambient_player.finished.connect(_on_ambient_finished)

	if is_default_soundscape:
		default_zone = self

	add_to_group(&"soundscape_zones")

	if is_instance_valid(timer):
		if not timer.timeout.is_connected(_on_timer_timeout):
			timer.timeout.connect(_on_timer_timeout)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)

	if is_default_soundscape:
		call_deferred(&"_deferred_check_fallback")


## Rebuilds collision shapes and synchronizes debug visualizer properties.
func _update_bounds() -> void:
	if not is_inside_tree():
		return

	var shape_node: CollisionShape3D = _get_collision_shape()
	if is_instance_valid(shape_node):
		if shape_type == EditorTriggerVisualizer.ShapeType.BOX:
			if not shape_node.shape is BoxShape3D:
				shape_node.shape = BoxShape3D.new()
			else:
				shape_node.shape = shape_node.shape.duplicate()
			shape_node.shape.resource_local_to_scene = true
			var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
			box_shape.size = zone_size
		elif shape_type == EditorTriggerVisualizer.ShapeType.SPHERE:
			if not shape_node.shape is SphereShape3D:
				shape_node.shape = SphereShape3D.new()
			else:
				shape_node.shape = shape_node.shape.duplicate()
			shape_node.shape.resource_local_to_scene = true
			var sphere_shape: SphereShape3D = shape_node.shape as SphereShape3D
			sphere_shape.radius = zone_size.x * 0.5

		shape_node.position = zone_offset

	var visual: EditorTriggerVisualizer = _get_visualizer()
	if is_instance_valid(visual):
		visual.shape_type = shape_type
		visual.trigger_size = zone_size
		visual.trigger_color = zone_color
		visual.outline_color = outline_color
		visual.x_ray_mode = x_ray_mode
		visual.show_orientation = show_orientation
		visual.show_metric_dimensions = show_metric_dimensions
		visual.trigger_text = zone_text
		visual.show_in_game = show_in_game
		visual.position = zone_offset


## Safely retrieves the child [CollisionShape3D] instance.
func _get_collision_shape() -> CollisionShape3D:
	if is_instance_valid(collision_shape):
		return collision_shape
	var col: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not is_instance_valid(col):
		for child: Node in get_children():
			if child is CollisionShape3D:
				col = child
				break
	return col


## Safely retrieves the child [EditorTriggerVisualizer] instance.
func _get_visualizer() -> EditorTriggerVisualizer:
	var visual: EditorTriggerVisualizer = (
		get_node_or_null("EditorTriggerVisualizer") as EditorTriggerVisualizer
	)
	if not is_instance_valid(visual):
		for child: Node in get_children():
			if child is EditorTriggerVisualizer:
				return child as EditorTriggerVisualizer
	return visual


## Activates soundscape zone when player enters volume.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.is_in_group(&"player") and soundscape != null:
		if activate_once and _has_been_activated:
			return

		if current_active_zone == self:
			if Time.get_ticks_msec() - _last_exit_time > DEBOUNCE_MSEC:
				print("SoundscapeZone: Player re-entered active zone: ", name)
			return

		print("SoundscapeZone: Player entered new soundscape: ", name)
		current_active_zone = self
		_has_been_activated = true
		_start_soundscape()


## Deactivates soundscape zone when player leaves volume.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return

	if body.is_in_group(&"player") and soundscape != null:
		_last_exit_time = Time.get_ticks_msec()
		print("SoundscapeZone: Player exited soundscape: ", name)

		if current_active_zone == self:
			current_active_zone = null

		if not persist_after_exit:
			_stop_soundscape()
			call_deferred(&"_deferred_check_fallback")


## Checks and restores default fallback soundscape when idle.
func _deferred_check_fallback() -> void:
	print("SoundscapeZone: Evaluating fallback soundscape state.")
	if current_active_zone == null and default_zone != null:
		var def_ambient: AudioStreamPlayer = default_zone.ambient_player
		if is_instance_valid(def_ambient):
			if not def_ambient.playing or def_ambient.stream_paused:
				print("SoundscapeZone: Resuming default soundscape: ", default_zone.name)
				default_zone._start_soundscape()


## Begins ambient playback and schedules pooled one-shot timer.
func _start_soundscape() -> void:
	print("SoundscapeZone: Starting soundscape: ", name)
	get_tree().call_group(&"soundscape_zones", &"_remote_stop", self)

	if soundscape.ambient_track:
		ambient_player.stream = soundscape.ambient_track

		if ambient_player.stream_paused:
			ambient_player.stream_paused = false
		elif not ambient_player.playing:
			ambient_player.play()

		_fade_volume(ambient_player, base_volume_db)

	if soundscape.random_sounds.size() > 0 and timer.is_stopped():
		_schedule_next_random_sound()


## Pauses ambient track and halts random sound timer.
func _stop_soundscape() -> void:
	print("SoundscapeZone: Stopping soundscape: ", name)
	timer.stop()
	_fade_volume(ambient_player, -80.0, true)


## Halts playback if another active zone claims priority.
func _remote_stop(new_zone: SoundscapeZone) -> void:
	var is_playing: bool = ambient_player.playing and not ambient_player.stream_paused
	if new_zone != self and is_playing:
		print("SoundscapeZone: Remote stop triggered on: ", name)
		_stop_soundscape()


## Smoothly tweens player volume towards [param target_vol].
func _fade_volume(
	player_node: AudioStreamPlayer, target_vol: float, pause_on_finish: bool = false
) -> void:
	print("SoundscapeZone: Fading volume on ", player_node.name, " to ", target_vol)
	if current_tween and current_tween.is_running():
		current_tween.kill()

	current_tween = create_tween()
	current_tween.tween_property(player_node, "volume_db", target_vol, fade_duration).set_trans(
		Tween.TRANS_SINE
	)

	if pause_on_finish:
		current_tween.tween_callback(func() -> void: player_node.stream_paused = true)


## Calculates randomized interval and starts one-shot timer.
func _schedule_next_random_sound() -> void:
	var next_time: float = randf_range(soundscape.min_interval, soundscape.max_interval)
	print("SoundscapeZone: Scheduling next random sound in ", next_time, " seconds.")
	timer.start(next_time)


## Dispatches pooled one-shot environmental SFX via [AudioPool].
func _on_timer_timeout() -> void:
	print("SoundscapeZone: Playing random one-shot sound via AudioPool.")
	if soundscape.random_sounds.is_empty():
		return

	var random_sound: AudioStream = soundscape.random_sounds.pick_random()
	var pooled_player: AudioStreamPlayer = AudioPool.play_sfx_2d(random_sound, &"Ambient")
	if is_instance_valid(pooled_player):
		pooled_player.volume_db = soundscape.random_volume_db

	_schedule_next_random_sound()


## Loops ambient track when reaching completion.
func _on_ambient_finished() -> void:
	print("SoundscapeZone: Ambient track finished on: ", name)
	if loop_ambient:
		ambient_player.play()
