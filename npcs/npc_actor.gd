## Reusable Half-Life-style animated NPC with [AnimationTree], [LookAtModifier3D], and event hooks.
class_name NpcActor
extends CharacterBody3D

## Emitted when [NpcActor] starts transitioning to [param clip_name].
signal animation_started(clip_name: StringName)

## Emitted when a one-shot animation completes or [method stop_animation] returns to default.
signal animation_completed(clip_name: StringName)

## Default AnimationTree state machine playback property key.
const PARAM_PLAYBACK: StringName = &"parameters/playback"
## Minimum angular alignment (radians) to finish a body yaw turn.
const BODY_TURN_STOP_RAD: float = 0.14
## Minimum squared planar distance to evaluate horizontal yaw direction.
const MIN_PLANAR_DIST_SQ: float = 0.0004
## Neutral eye height offset in meters for 1.64m humanoid characters.
const DEFAULT_EYE_HEIGHT_M: float = 1.48
## Forward neutral gaze distance in meters when look-at relaxes.
const NEUTRAL_LOOK_DIST_M: float = 3.0

@export_group("Scene References")
## Child [Node3D] holding the rigged GLB model ([Skeleton3D] and [AnimationPlayer]).
@export var model_root: Node3D
## Optional [VisibleOnScreenNotifier3D] gating per-frame look-at and [AnimationTree] updates.
@export var visibility_notifier: VisibleOnScreenNotifier3D

@export_group("Animation")
## Default looping clip played on [method _ready] and after one-shot clips finish.
@export var default_animation: StringName = &"idle"
## Stepping turn-left animation clip played automatically when turning counter-clockwise.
@export var turn_left_animation: StringName = &"turn_left"
## Stepping turn-right animation clip played automatically when turning clockwise.
@export var turn_right_animation: StringName = &"turn_right"
## Animation clip names forced to [constant Animation.LOOP_LINEAR] on startup.
@export var looping_clips: Array[StringName] = [
	&"idle", &"a_pose", &"t_pose", &"turn_left", &"turn_right", &"air_hump", &"booty_slap"
]
## Crossfade blend time in seconds between [AnimationNodeStateMachine] states.
@export_range(0.0, 1.0, 0.01) var crossfade_duration: float = 0.15
## Maps [signal Events.level_event_triggered] names to animation clip names.
@export var event_animation_map: Dictionary[String, String] = {}

@export_group("Real-Time Look-At")
## Enables continuous real-time gaze tracking toward player camera or custom target.
@export var look_at_enabled: bool = true:
	set(value):
		look_at_enabled = value
		if is_inside_tree():
			_refresh_process_state()
## Maximum tracking range in meters; beyond this distance look-at smoothly relaxes.
@export_range(1.0, 60.0, 0.5) var max_look_distance: float = 18.0:
	set(value):
		max_look_distance = maxf(1.0, value)
		_max_look_distance_sq = max_look_distance * max_look_distance
## Exponential smoothing speed for gaze target interpolation.
@export_range(1.0, 25.0, 0.5) var look_smooth_speed: float = 9.0
## Upper torso bone name receiving subtle secondary gaze rotation.
@export var chest_bone_name: String = "UpperChest"
## Head bone name receiving primary gaze rotation.
@export var head_bone_name: String = "Head"
## Influence weight for [member chest_bone_name] [LookAtModifier3D].
@export_range(0.0, 1.0, 0.02) var chest_look_influence: float = 0.30
## Influence weight for [member head_bone_name] [LookAtModifier3D].
@export_range(0.0, 1.0, 0.02) var head_look_influence: float = 0.92
## Rotates NPC root yaw smoothly when target orbits past [member body_turn_threshold_deg].
@export var turn_body_when_behind: bool = true
## Horizontal angle (degrees) from NPC forward before body starts rotating toward target.
@export_range(20.0, 140.0, 1.0) var body_turn_threshold_deg: float = 65.0
## Body yaw turn speed in radians per second when stepping toward behind-angle targets.
@export_range(0.5, 12.0, 0.25) var body_turn_speed: float = 3.2

## Cached rigged [Skeleton3D] discovered inside [member model_root].
var _skeleton: Skeleton3D = null
## Cached [AnimationPlayer] discovered inside [member model_root].
var _anim_player: AnimationPlayer = null
## Runtime [AnimationTree] driving crossfaded state machine playback.
var _anim_tree: AnimationTree = null
## Cached [AnimationNodeStateMachinePlayback] controller for [member _anim_tree].
var _playback: AnimationNodeStateMachinePlayback = null
## Child [Marker3D] smoothly positioned at the active world gaze point.
var _look_target: Marker3D = null
## Native C++ [LookAtModifier3D] for upper torso follow-through.
var _chest_modifier: LookAtModifier3D = null
## Native C++ [LookAtModifier3D] for primary head gaze tracking.
var _head_modifier: LookAtModifier3D = null
## Optional explicit override look target set by [EventSequenceTrigger].
var _override_target: Node3D = null
## Cached active player [Camera3D] resolved via [Events] or viewport fallback.
var _player_camera: Camera3D = null
## Active animation clip name.
var _current_clip: StringName = &""
## True while current clip is running as a non-looping one-shot.
var _is_playing_oneshot: bool = false
## True while an explicit non-default scripted clip (e.g. air_hump, t_pose) overrides idle turns.
var _is_scripted_clip_active: bool = false
## Cached squared distance limit for zero-sqrt proximity gating.
var _max_look_distance_sq: float = 324.0
## Tracks visibility state from [member visibility_notifier].
var _is_on_screen: bool = true
## Current smoothed look-at blend factor in [0.0, 1.0].
var _look_blend: float = 0.0
## True while body root is actively turning toward a behind-angle target.
var _is_turning_body: bool = false
## Cached list of clip names registered in [member _anim_tree].
var _registered_clips: Array[StringName] = []


## Initializes collision layers, [AnimationTree], [LookAtModifier3D] stack, and event listeners.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_max_look_distance_sq = max_look_distance * max_look_distance

	if not is_instance_valid(model_root):
		model_root = get_node_or_null(^"Model") as Node3D
	assert(is_instance_valid(model_root), "NpcActor requires model_root assigned.")

	collision_layer = CollisionLayers.MASK_INTERACTIVE
	collision_mask = CollisionLayers.MASK_SOLID_WORLD | CollisionLayers.MASK_PLAYER
	_apply_render_layers_recursive(model_root)

	_skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	_anim_player = model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(is_instance_valid(_skeleton), "NpcActor requires Skeleton3D inside model_root.")
	assert(is_instance_valid(_anim_player), "NpcActor requires AnimationPlayer inside model_root.")

	_setup_animation_tree()
	_setup_look_at_modifiers()
	_setup_visibility_gating()
	_connect_global_events()

	if _registered_clips.has(default_animation):
		play_animation(String(default_animation))
		if is_instance_valid(_anim_tree):
			_anim_tree.advance(0.0)

	_refresh_process_state()
	print("NpcActor: Ready -> ", name, " clips=", _registered_clips)


## Disconnects persistent [Events] listeners when leaving the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(Events):
		if Events.level_event_triggered.is_connected(_on_level_event_triggered):
			Events.level_event_triggered.disconnect(_on_level_event_triggered)
		if Events.player_camera_registered.is_connected(_on_player_camera_registered):
			Events.player_camera_registered.disconnect(_on_player_camera_registered)


## Updates smoothed gaze target and optional behind-angle body yaw while visible on screen.
func _process(delta: float) -> void:
	if not is_instance_valid(_look_target):
		return

	var target_pos: Vector3 = _resolve_gaze_world_position()
	var has_active_target: bool = false
	if look_at_enabled and target_pos != Vector3.INF:
		var dist_sq: float = global_position.distance_squared_to(target_pos)
		has_active_target = dist_sq <= _max_look_distance_sq

	var blend_target: float = 1.0 if has_active_target else 0.0
	var damp_alpha: float = 1.0 - exp(-look_smooth_speed * delta)
	_look_blend = lerpf(_look_blend, blend_target, damp_alpha)

	var desired_world_pos: Vector3 = target_pos if has_active_target else _get_neutral_look_pos()
	_look_target.global_position = _look_target.global_position.lerp(desired_world_pos, damp_alpha)

	if is_instance_valid(_chest_modifier):
		_chest_modifier.influence = chest_look_influence * _look_blend
	if is_instance_valid(_head_modifier):
		_head_modifier.influence = head_look_influence * _look_blend

	if has_active_target and turn_body_when_behind:
		_update_body_yaw_tracking(target_pos, delta)
	else:
		_finish_body_turn()

	if not look_at_enabled and _look_blend < 0.005:
		_look_blend = 0.0
		if is_instance_valid(_chest_modifier):
			_chest_modifier.influence = 0.0
		if is_instance_valid(_head_modifier):
			_head_modifier.influence = 0.0
		set_process(false)


## Plays [param clip_name] smoothly via [AnimationTree]; callable from [EventSequenceTrigger].
func play_animation(clip_name: String) -> void:
	var clip_sn: StringName = StringName(clip_name.strip_edges())
	if clip_sn.is_empty() or not _registered_clips.has(clip_sn):
		print("NpcActor: Unknown clip '", clip_name, "' on ", name)
		return

	_is_playing_oneshot = false
	_is_scripted_clip_active = clip_sn != default_animation
	_apply_clip_loop_mode(clip_sn, looping_clips.has(clip_sn))
	_travel_to_clip(clip_sn)
	print("NpcActor: ", name, " -> play_animation('", clip_sn, "')")


## Plays [param clip_name] once, emits [signal animation_completed], and returns to default clip.
func play_animation_once(clip_name: String) -> void:
	var clip_sn: StringName = StringName(clip_name.strip_edges())
	if clip_sn.is_empty() or not _registered_clips.has(clip_sn):
		print("NpcActor: Unknown one-shot clip '", clip_name, "' on ", name)
		return

	_is_playing_oneshot = true
	_is_scripted_clip_active = true
	_apply_clip_loop_mode(clip_sn, false)
	_travel_to_clip(clip_sn)
	print("NpcActor: ", name, " -> play_animation_once('", clip_sn, "')")


## Stops active scripted clip and crossfades back to [member default_animation].
func stop_animation() -> void:
	var finished_clip: StringName = _current_clip
	_is_playing_oneshot = false
	_is_scripted_clip_active = false
	if _registered_clips.has(default_animation) and _current_clip != default_animation:
		_apply_clip_loop_mode(default_animation, looping_clips.has(default_animation))
		_travel_to_clip(default_animation)
	animation_completed.emit(finished_clip)
	print("NpcActor: ", name, " -> stop_animation (returned to '", default_animation, "')")


## Toggles real-time gaze tracking; callable from [EventSequenceTrigger].
func set_look_at_enabled(enabled: bool) -> void:
	look_at_enabled = enabled
	print("NpcActor: ", name, " -> look_at_enabled=", enabled)


## Assigns a custom [Node3D] look target, or passes [code]null[/code] to resume player tracking.
func set_look_target(target: Node3D) -> void:
	_override_target = target
	_refresh_process_state()
	var target_name: String = String(target.name) if is_instance_valid(target) else "PlayerCamera"
	print("NpcActor: ", name, " -> look_target=", target_name)


## Toggles behind-angle body yaw rotation toward gaze target.
func set_body_turn_enabled(enabled: bool) -> void:
	turn_body_when_behind = enabled
	print("NpcActor: ", name, " -> turn_body_when_behind=", enabled)


## Returns the currently active animation clip name.
func get_current_animation() -> StringName:
	return _current_clip


## Returns the rigged [Skeleton3D] managed by this actor.
func get_skeleton() -> Skeleton3D:
	return _skeleton


## Returns the active [AnimationTree] driving state machine transitions.
func get_animation_tree() -> AnimationTree:
	return _anim_tree


## Returns the chest and head [LookAtModifier3D] nodes for inspection or tests.
func get_look_modifiers() -> Array[LookAtModifier3D]:
	var mods: Array[LookAtModifier3D] = []
	if is_instance_valid(_chest_modifier):
		mods.append(_chest_modifier)
	if is_instance_valid(_head_modifier):
		mods.append(_head_modifier)
	return mods


## Builds an [AnimationTree] with [AnimationNodeStateMachine] transitions for all model clips.
func _setup_animation_tree() -> void:
	_anim_tree = get_node_or_null(^"AnimationTree") as AnimationTree
	if not is_instance_valid(_anim_tree):
		_anim_tree = AnimationTree.new()
		_anim_tree.name = "AnimationTree"
		add_child(_anim_tree)

	var state_machine: AnimationNodeStateMachine = AnimationNodeStateMachine.new()
	_registered_clips.clear()

	var clip_list: PackedStringArray = _anim_player.get_animation_list()
	for raw_name: String in clip_list:
		if raw_name == "RESET":
			continue
		var clip_sn: StringName = StringName(raw_name)
		var anim_node: AnimationNodeAnimation = AnimationNodeAnimation.new()
		anim_node.animation = clip_sn
		state_machine.add_node(clip_sn, anim_node)
		_registered_clips.append(clip_sn)
		_apply_clip_loop_mode(clip_sn, looping_clips.has(clip_sn))

	if _registered_clips.has(default_animation):
		var start_trans: AnimationNodeStateMachineTransition = (
			AnimationNodeStateMachineTransition.new()
		)
		start_trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		state_machine.add_transition(&"Start", default_animation, start_trans)

	for from_clip: StringName in _registered_clips:
		for to_clip: StringName in _registered_clips:
			if from_clip == to_clip:
				continue
			var trans: AnimationNodeStateMachineTransition = (
				AnimationNodeStateMachineTransition.new()
			)
			trans.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			trans.xfade_time = crossfade_duration
			state_machine.add_transition(from_clip, to_clip, trans)

	_anim_tree.tree_root = state_machine
	# Resolve GLB track paths relative to model_root (matching AnimationPlayer.root_node).
	_anim_tree.root_node = _anim_tree.get_path_to(model_root)
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.active = true

	var raw_pb: Variant = _anim_tree.get(PARAM_PLAYBACK)
	if raw_pb is AnimationNodeStateMachinePlayback:
		_playback = raw_pb as AnimationNodeStateMachinePlayback

	if not _anim_tree.animation_finished.is_connected(_on_tree_animation_finished):
		_anim_tree.animation_finished.connect(_on_tree_animation_finished)


## Attaches native C++ [LookAtModifier3D] nodes for chest and head directly under [Skeleton3D].
func _setup_look_at_modifiers() -> void:
	_look_target = get_node_or_null(^"LookTarget") as Marker3D
	if not is_instance_valid(_look_target):
		_look_target = Marker3D.new()
		_look_target.name = "LookTarget"
		add_child(_look_target)
	_look_target.position = Vector3(0.0, DEFAULT_EYE_HEIGHT_M, -NEUTRAL_LOOK_DIST_M)

	if _skeleton.find_bone(chest_bone_name) >= 0:
		_chest_modifier = _create_look_modifier(
			"ChestLookAt", chest_bone_name, chest_look_influence, 70.0, 30.0, 0.70
		)
	if _skeleton.find_bone(head_bone_name) >= 0:
		_head_modifier = _create_look_modifier(
			"HeadLookAt", head_bone_name, head_look_influence, 140.0, 70.0, 0.75
		)


## Creates or updates a single [LookAtModifier3D] under [member _skeleton] targeting LookTarget.
func _create_look_modifier(
	mod_name: String,
	bone: String,
	initial_influence: float,
	yaw_total_deg: float,
	pitch_total_deg: float,
	damp_threshold: float,
) -> LookAtModifier3D:
	var mod: LookAtModifier3D = _skeleton.get_node_or_null(NodePath(mod_name)) as LookAtModifier3D
	if not is_instance_valid(mod):
		mod = LookAtModifier3D.new()
		mod.name = mod_name
		_skeleton.add_child(mod)

	mod.bone_name = bone
	mod.target_node = mod.get_path_to(_look_target)
	mod.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	mod.primary_rotation_axis = Vector3.AXIS_Y
	mod.use_secondary_rotation = true
	mod.use_angle_limitation = true
	mod.symmetry_limitation = true
	mod.primary_limit_angle = deg_to_rad(yaw_total_deg)
	mod.secondary_limit_angle = deg_to_rad(pitch_total_deg)
	mod.primary_damp_threshold = damp_threshold
	mod.secondary_damp_threshold = damp_threshold
	mod.influence = initial_influence if look_at_enabled else 0.0
	mod.active = true
	return mod


## Hooks [member visibility_notifier] callbacks to sleep updates while off-screen.
func _setup_visibility_gating() -> void:
	if not is_instance_valid(visibility_notifier):
		visibility_notifier = (
			get_node_or_null(^"VisibleOnScreenNotifier3D") as VisibleOnScreenNotifier3D
		)
	# Default on-screen in _ready() because is_on_screen() is false before first render cull pass.
	_is_on_screen = true
	if not is_instance_valid(visibility_notifier):
		return

	if not visibility_notifier.screen_entered.is_connected(_on_screen_entered):
		visibility_notifier.screen_entered.connect(_on_screen_entered)
	if not visibility_notifier.screen_exited.is_connected(_on_screen_exited):
		visibility_notifier.screen_exited.connect(_on_screen_exited)


## Connects [Events] signals for level events and active player camera registration.
func _connect_global_events() -> void:
	if not is_instance_valid(Events):
		return
	if not Events.level_event_triggered.is_connected(_on_level_event_triggered):
		Events.level_event_triggered.connect(_on_level_event_triggered)
	if not Events.player_camera_registered.is_connected(_on_player_camera_registered):
		Events.player_camera_registered.connect(_on_player_camera_registered)


## Transitions [member _playback] to [param clip_sn] and updates state tracking.
func _travel_to_clip(clip_sn: StringName) -> void:
	_current_clip = clip_sn
	if is_instance_valid(_playback):
		var cur_node: StringName = _playback.get_current_node()
		if cur_node.is_empty() or cur_node == &"Start" or cur_node == clip_sn:
			_playback.start(clip_sn, true)
		else:
			_playback.travel(clip_sn)
	elif is_instance_valid(_anim_player):
		_anim_player.play(clip_sn, crossfade_duration)
	animation_started.emit(clip_sn)


## Applies [constant Animation.LOOP_LINEAR] or [constant Animation.LOOP_NONE] on a clip resource.
func _apply_clip_loop_mode(clip_sn: StringName, should_loop: bool) -> void:
	if not is_instance_valid(_anim_player) or not _anim_player.has_animation(clip_sn):
		return
	var anim: Animation = _anim_player.get_animation(clip_sn)
	if is_instance_valid(anim):
		anim.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE


## Resolves the active world-space target point (override node, player camera, or player group).
func _resolve_gaze_world_position() -> Vector3:
	if is_instance_valid(_override_target):
		return _override_target.global_position

	if not is_instance_valid(_player_camera):
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_player_camera = vp.get_camera_3d()

	if is_instance_valid(_player_camera):
		return _player_camera.global_position

	if is_inside_tree():
		var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
		for node: Node in players:
			if node is CharacterBody3D:
				var body: Node3D = node as Node3D
				return body.global_position + Vector3(0.0, DEFAULT_EYE_HEIGHT_M, 0.0)

	return Vector3.INF


## Computes world-space neutral forward eye point for gaze relaxation.
func _get_neutral_look_pos() -> Vector3:
	var forward_dir: Vector3 = -global_transform.basis.z.normalized()
	return (
		global_position
		+ Vector3(0.0, DEFAULT_EYE_HEIGHT_M, 0.0)
		+ forward_dir * NEUTRAL_LOOK_DIST_M
	)


## Smoothly rotates NPC root Y-yaw with stepping turn animation when target orbits behind.
func _update_body_yaw_tracking(target_pos: Vector3, delta: float) -> void:
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	if to_target.length_squared() < MIN_PLANAR_DIST_SQ:
		_finish_body_turn()
		return

	var target_yaw: float = atan2(-to_target.x, -to_target.z)
	var yaw_diff: float = angle_difference(global_rotation.y, target_yaw)
	var threshold_rad: float = deg_to_rad(body_turn_threshold_deg)

	if not _is_turning_body and absf(yaw_diff) > threshold_rad:
		_is_turning_body = true

	if _is_turning_body:
		var step: float = 1.0 - exp(-body_turn_speed * delta)
		global_rotation.y = global_rotation.y + yaw_diff * step
		if not _is_scripted_clip_active:
			var turn_clip: StringName = (
				turn_left_animation if yaw_diff > 0.0 else turn_right_animation
			)
			if _registered_clips.has(turn_clip) and _current_clip != turn_clip:
				_apply_clip_loop_mode(turn_clip, true)
				_travel_to_clip(turn_clip)
		if absf(yaw_diff) <= BODY_TURN_STOP_RAD:
			_finish_body_turn()


## Ends body yaw rotation and crossfades back to [member default_animation] if not scripted.
func _finish_body_turn() -> void:
	if not _is_turning_body:
		return
	_is_turning_body = false
	if not _is_scripted_clip_active and _registered_clips.has(default_animation):
		if _current_clip != default_animation:
			_apply_clip_loop_mode(default_animation, looping_clips.has(default_animation))
			_travel_to_clip(default_animation)


## Enables or disables [method _process] and [member _anim_tree] based on visibility and look state.
func _refresh_process_state() -> void:
	var should_tick: bool = _is_on_screen and (look_at_enabled or _look_blend > 0.005)
	set_process(should_tick)
	if is_instance_valid(_anim_tree):
		_anim_tree.active = _is_on_screen


## Recursively assigns [constant CollisionLayers.RENDER_MASK_INTERACTIVE] to all child meshes.
func _apply_render_layers_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		mesh_inst.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	for child: Node in node.get_children():
		_apply_render_layers_recursive(child)


## Callback triggered when [member visibility_notifier] enters active camera frustum.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_refresh_process_state()


## Callback triggered when [member visibility_notifier] exits active camera frustum.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_refresh_process_state()


## Callback triggered when a non-looping [AnimationTree] state finishes playback.
func _on_tree_animation_finished(anim_name: StringName) -> void:
	if not _is_playing_oneshot or anim_name != _current_clip:
		return
	_is_playing_oneshot = false
	_is_scripted_clip_active = false
	animation_completed.emit(anim_name)
	if _registered_clips.has(default_animation) and default_animation != anim_name:
		_apply_clip_loop_mode(default_animation, looping_clips.has(default_animation))
		_travel_to_clip(default_animation)


## Callback reacting to [signal Events.level_event_triggered] using [member event_animation_map].
func _on_level_event_triggered(event_name: String, is_active: bool) -> void:
	if not event_animation_map.has(event_name):
		return
	var mapped_clip: String = event_animation_map[event_name]
	if is_active:
		play_animation(mapped_clip)
	else:
		stop_animation()


## Callback caching active player [Camera3D] registered on [Events].
func _on_player_camera_registered(camera: Camera3D) -> void:
	_player_camera = camera
