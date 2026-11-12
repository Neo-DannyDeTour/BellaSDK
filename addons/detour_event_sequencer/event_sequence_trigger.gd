## Area3D trigger evaluating gate conditions and executing sequential or parallel [EventStep]s.
@tool
class_name EventSequenceTrigger
extends BaseTriggerArea3D

## Emitted when all non-parallel steps in the sequence complete execution.
signal sequence_completed

## Default physics collision mask bit for Player (Layer 2 = bit value 2).
const DEFAULT_ACTIVATOR_MASK: int = 2
## Attack duration of [RoarScreenEffect] in seconds.
const ROAR_ATTACK_TIME: float = 0.1
## Decay duration of [RoarScreenEffect] in seconds.
const ROAR_DECAY_TIME: float = 0.3

@export_group("Trigger Filter")
## Physics layers permitted to activate this trigger (L2=2, L3=4, L4=8, L5=16).
@export_flags_3d_physics var activator_mask: int = DEFAULT_ACTIVATOR_MASK:
	set(value):
		activator_mask = value
		collision_mask = value

@export_group("Sequence Data")
## Gate conditions that must all evaluate to true on entry before steps run.
@export var conditions: Array[EventCondition] = []

## Ordered list of [EventStep] actions executed when conditions pass.
@export var steps: Array[EventStep] = []

## Flag preventing overlapping sequential executions while running.
var _is_running: bool = false

## Current activator node driving sequence execution.
var _active_activator: Node3D = null

## Tracks whether active activator is currently inside trigger bounds.
var _activator_inside: bool = false

## Captured world position of the activator when entering the trigger.
var _activator_entry_pos: Vector3 = Vector3.ZERO


## Configures collision layers, default visualizer text, and runtime listeners.
func _ready() -> void:
	auto_consume_on_entry = false
	if trigger_text == "TRIGGER":
		trigger_text = "EVENT SEQUENCE"
	super._ready()
	set_process(false)
	set_physics_process(false)
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = activator_mask
	if Engine.is_editor_hint():
		return
	print("EventSequenceTrigger: Ready -> ", name)


## Evaluates all configured [member conditions] against [param activator].
func are_conditions_met(activator: Node3D) -> bool:
	for cond: EventCondition in conditions:
		if cond == null:
			continue
		if not cond.evaluate(self, activator):
			return false
	return true


## Runs all [member steps] using their configured delay and concurrency modes.
func trigger_sequence(activator: Node3D = null) -> void:
	print("EventSequenceTrigger: Starting sequence on ", name)
	_is_running = true
	if is_instance_valid(activator):
		_active_activator = activator
		_activator_inside = true
		_activator_entry_pos = activator.global_position

	for i: int in range(steps.size()):
		var step: EventStep = steps[i]
		if step == null:
			continue
		if step.fire_once and step.has_fired:
			continue

		match step.exec_mode:
			EventStep.ExecMode.PARALLEL:
				_run_parallel_step(step, activator)
			EventStep.ExecMode.SEQUENTIAL:
				await _run_step_action(step, activator, true)
			EventStep.ExecMode.WAIT_SIGNAL:
				await _run_step_action(step, activator, false)
				await _await_step_signal(step, activator)
			EventStep.ExecMode.WAIT_LOOK:
				await _run_step_action(step, activator, false)
				await _await_step_look(step, activator)

	_is_running = false
	sequence_completed.emit()
	print("EventSequenceTrigger: Sequence completed on ", name)


## Entry callback verifying activator eligibility and gate conditions.
func _on_body_entered(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if _has_triggered and trigger_once:
		return
	if _is_running:
		return
	if not are_conditions_met(body):
		print("EventSequenceTrigger: Conditions not met for ", body.name)
		return

	print("EventSequenceTrigger: Activated by ", body.name)
	_has_triggered = true
	_active_activator = body
	_activator_inside = true
	_activator_entry_pos = body.global_position
	player_entered.emit(body)
	trigger_sequence(body)


## Exit callback tracking when activator leaves volume bounds.
func _on_body_exited(body: Node3D) -> void:
	if Engine.is_editor_hint():
		return
	if body == _active_activator:
		print("EventSequenceTrigger: Activator exited volume -> ", body.name)
		_activator_inside = false
		player_exited.emit(body)


## Waits for step delay and executes step action or cinematic coroutine.
func _run_step_action(
	step: EventStep, activator: Node3D, await_completion: bool = true
) -> void:
	if step.delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(step.delay).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return

	step.has_fired = true
	match step.step_type:
		EventStep.StepType.CALL_METHOD, EventStep.StepType.SET_PROPERTY:
			step.execute(self, activator)
		EventStep.StepType.PLAYER_LOCK:
			_exec_player_lock(step, activator)
		EventStep.StepType.LOOK_AT:
			await _exec_look_at(step, activator, await_completion)
		EventStep.StepType.MOVE_TOWARDS:
			await _exec_move_towards(step, activator, await_completion)
		EventStep.StepType.MOVE_OFFSET:
			await _exec_move_offset(step, activator, await_completion)
		EventStep.StepType.CAMERA_TILT:
			await _exec_camera_tilt(step, activator, await_completion)
		EventStep.StepType.CAMERA_FOV:
			await _exec_camera_fov(step, activator, await_completion)
		EventStep.StepType.SCREEN_DRUNK:
			await _exec_screen_drunk(step, activator, await_completion)
		EventStep.StepType.SCREEN_ROAR:
			await _exec_screen_roar(step, await_completion)
		EventStep.StepType.SCREEN_FADE:
			await _exec_screen_fade(step, await_completion)
		EventStep.StepType.PLAY_AUDIO:
			await _exec_play_audio(step, activator, await_completion)
		EventStep.StepType.TELEPORT_PLAYER:
			_exec_teleport_player(step, activator)


## Spawns detached coroutine for parallel step execution without blocking sequence.
func _run_parallel_step(step: EventStep, activator: Node3D) -> void:
	await _run_step_action(step, activator, false)


## Toggles cinematic movement and camera look lock on the player.
func _exec_player_lock(step: EventStep, activator: Node3D) -> void:
	var is_locked: bool = step.parameter.strip_edges().to_lower() != "false"
	print("EventSequenceTrigger: PLAYER_LOCK -> ", is_locked)
	if is_instance_valid(Events) and Events.has_signal(&"player_cinematic_lock_requested"):
		Events.player_cinematic_lock_requested.emit(is_locked)
	var player_node: Node3D = _resolve_player_node(activator)
	if is_instance_valid(player_node) and &"is_cinematic_locked" in player_node:
		player_node.set(&"is_cinematic_locked", is_locked)


## Rotates player body yaw and head pitch to look at the resolved target node.
func _exec_look_at(step: EventStep, activator: Node3D, await_completion: bool) -> void:
	var target: Node = step.resolve_target(self, activator)
	if not (target is Node3D):
		print("EventSequenceTrigger: LOOK_AT target is not Node3D.")
		return
	var target_3d: Node3D = target as Node3D
	var player_node: Node3D = _resolve_player_node(activator)
	var cam: Camera3D = _resolve_camera(player_node)
	var head: Node3D = (
		player_node.get_node_or_null("Head") as Node3D if is_instance_valid(player_node) else null
	)

	var eye_pos: Vector3 = (
		cam.global_position
		if is_instance_valid(cam)
		else (
			player_node.global_position + Vector3(0.0, 1.52, 0.0)
			if is_instance_valid(player_node)
			else global_position
		)
	)
	var diff: Vector3 = target_3d.global_position - eye_pos
	if diff.length_squared() < 0.0001:
		return

	var target_yaw: float = atan2(-diff.x, -diff.z)
	var horiz_dist: float = Vector2(diff.x, diff.z).length()
	var target_pitch: float = clampf(atan2(diff.y, horiz_dist), deg_to_rad(-89.0), deg_to_rad(89.0))
	print("EventSequenceTrigger: LOOK_AT -> ", target_3d.name, " over ", step.duration, "s")

	if is_instance_valid(player_node) and is_instance_valid(head):
		var start_yaw: float = player_node.global_rotation.y
		var end_yaw: float = start_yaw + angle_difference(start_yaw, target_yaw)
		if step.duration <= 0.0:
			player_node.global_rotation.y = end_yaw
			head.rotation.x = target_pitch
			return
		var tw: Tween = create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(player_node, "global_rotation:y", end_yaw, step.duration)
		tw.tween_property(head, "rotation:x", target_pitch, step.duration)
		if await_completion:
			await tw.finished
	elif is_instance_valid(cam):
		cam.look_at(target_3d.global_position, Vector3.UP)


## Moves player horizontally toward the resolved target node by [member EventStep.distance].
func _exec_move_towards(step: EventStep, activator: Node3D, await_completion: bool) -> void:
	var target: Node = step.resolve_target(self, activator)
	if not (target is Node3D):
		print("EventSequenceTrigger: MOVE_TOWARDS target is not Node3D.")
		return
	var target_3d: Node3D = target as Node3D
	var actor: Node3D = _resolve_player_node(activator)
	if not is_instance_valid(actor):
		return

	var to_target: Vector3 = target_3d.global_position - actor.global_position
	var planar_dir: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	if planar_dir.length_squared() < 0.0001:
		planar_dir = -actor.global_transform.basis.z
		planar_dir.y = 0.0
	planar_dir = planar_dir.normalized()

	var end_pos: Vector3 = actor.global_position + (planar_dir * step.distance)
	print(
		"EventSequenceTrigger: MOVE_TOWARDS -> ",
		target_3d.name,
		" dist=",
		step.distance,
		"m over ",
		step.duration,
		"s"
	)
	if step.duration <= 0.0:
		actor.global_position = end_pos
		return
	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(actor, "global_position", end_pos, step.duration)
	if await_completion:
		await tw.finished


## Translates the resolved target node by [member EventStep.offset_vector] over duration.
func _exec_move_offset(step: EventStep, activator: Node3D, await_completion: bool) -> void:
	var target: Node = step.resolve_target(self, activator)
	if not (target is Node3D):
		print("EventSequenceTrigger: MOVE_OFFSET target is not Node3D.")
		return
	var target_3d: Node3D = target as Node3D
	var end_pos: Vector3 = target_3d.global_position + step.offset_vector
	print(
		"EventSequenceTrigger: MOVE_OFFSET on ",
		target_3d.name,
		" offset=",
		step.offset_vector,
		" over ",
		step.duration,
		"s"
	)
	if step.duration <= 0.0:
		target_3d.global_position = end_pos
		return
	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(target_3d, "global_position", end_pos, step.duration)
	if await_completion:
		await tw.finished


## Tilts the active player camera roll (Dutch angle) to [member EventStep.angle_deg].
func _exec_camera_tilt(step: EventStep, activator: Node3D, await_completion: bool) -> void:
	var player_node: Node3D = _resolve_player_node(activator)
	var cam: Camera3D = _resolve_camera(player_node)
	if not is_instance_valid(cam):
		return
	_halt_drunk_camera_override(player_node)
	var target_rad: float = deg_to_rad(step.angle_deg)
	print("EventSequenceTrigger: CAMERA_TILT -> ", step.angle_deg, " deg over ", step.duration, "s")
	if step.duration <= 0.0:
		cam.rotation.z = target_rad
		return
	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam, "rotation:z", target_rad, step.duration)
	if await_completion:
		await tw.finished


## Transitions active camera field of view to [member EventStep.angle_deg] for Jaws dolly zoom.
func _exec_camera_fov(step: EventStep, activator: Node3D, await_completion: bool) -> void:
	var player_node: Node3D = _resolve_player_node(activator)
	var cam: Camera3D = _resolve_camera(player_node)
	if not is_instance_valid(cam):
		return
	_halt_drunk_camera_override(player_node)
	var target_fov: float = clampf(step.angle_deg, 10.0, 160.0)
	print("EventSequenceTrigger: CAMERA_FOV -> ", target_fov, " deg over ", step.duration, "s")
	if step.duration <= 0.0:
		cam.fov = target_fov
		return
	var tw: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cam, "fov", target_fov, step.duration)
	if await_completion:
		await tw.finished


## Transitions screen drunk distortion and sway intensity via [Events] or player controller.
func _exec_screen_drunk(step: EventStep, activator: Node3D, await_completion: bool) -> void:
	var player_node: Node3D = _resolve_player_node(activator)
	print(
		"EventSequenceTrigger: SCREEN_DRUNK -> intensity=",
		step.effect_intensity,
		" duration=",
		step.duration
	)
	if is_instance_valid(player_node) and player_node.has_method(&"set_drunk_intensity"):
		player_node.call(&"set_drunk_intensity", step.effect_intensity, step.duration)
	elif is_instance_valid(Events) and Events.has_signal(&"drunk_intensity_changed"):
		Events.drunk_intensity_changed.emit(step.effect_intensity, step.duration)
	if await_completion and step.duration > 0.0 and is_inside_tree():
		await get_tree().create_timer(step.duration).timeout


## Emits [signal Events.monster_roared] to trigger radial shockwave blur.
func _exec_screen_roar(step: EventStep, await_completion: bool) -> void:
	print("EventSequenceTrigger: SCREEN_ROAR -> sustain=", step.duration, "s")
	if is_instance_valid(Events) and Events.has_signal(&"monster_roared"):
		Events.monster_roared.emit(step.duration)
	var total_roar_time: float = ROAR_ATTACK_TIME + maxf(0.0, step.duration) + ROAR_DECAY_TIME
	if await_completion and total_roar_time > 0.0 and is_inside_tree():
		await get_tree().create_timer(total_roar_time).timeout


## Dispatches fullscreen fade transition to [ScreenEffectsCore] and [ScreenEffectsManager].
func _exec_screen_fade(step: EventStep, await_completion: bool) -> void:
	print(
		"EventSequenceTrigger: SCREEN_FADE -> in=",
		step.duration,
		" hold=",
		step.fade_hold_duration,
		" out=",
		step.fade_out_duration
	)
	if is_instance_valid(Events) and Events.has_signal(&"screen_fade_requested"):
		Events.screen_fade_requested.emit(
			step.fade_color,
			step.duration,
			step.fade_hold_duration,
			step.fade_out_duration,
			false,
			0.0,
			false,
			0
		)
	if await_completion and step.duration > 0.0 and is_inside_tree():
		await get_tree().create_timer(step.duration).timeout


## Plays configured [member EventStep.audio_stream] via [AudioPool] (2D or 3D at target).
func _exec_play_audio(step: EventStep, activator: Node3D, await_completion: bool) -> void:
	if step.audio_stream == null:
		print("EventSequenceTrigger: PLAY_AUDIO has no audio_stream assigned.")
		return
	var target: Node = step.resolve_target(self, activator)
	var start_sec: float = maxf(0.0, step.audio_start_offset)
	if target is Node3D and not step.target_path.is_empty():
		var target_3d: Node3D = target as Node3D
		print(
			"EventSequenceTrigger: PLAY_AUDIO 3D at ",
			target_3d.name,
			" offset=",
			start_sec,
			"s"
		)
		var player_3d: AudioStreamPlayer3D = AudioPool.play_sfx_3d(
			step.audio_stream, target_3d.global_position
		)
		if is_instance_valid(player_3d) and start_sec > 0.0:
			player_3d.seek(start_sec)
	else:
		print("EventSequenceTrigger: PLAY_AUDIO 2D offset=", start_sec, "s")
		var player_2d: AudioStreamPlayer = AudioPool.play_sfx_2d(step.audio_stream)
		if is_instance_valid(player_2d) and start_sec > 0.0:
			player_2d.seek(start_sec)

	if await_completion and is_inside_tree():
		var wait_len: float = step.duration
		if wait_len <= 0.0:
			wait_len = maxf(0.0, step.audio_stream.get_length() - start_sec)
		if wait_len > 0.0:
			await get_tree().create_timer(wait_len).timeout


## Teleports player to target node position or back to trigger entry position.
func _exec_teleport_player(step: EventStep, activator: Node3D) -> void:
	var player_node: Node3D = _resolve_player_node(activator)
	if not is_instance_valid(player_node):
		return

	var dest_pos: Vector3 = _activator_entry_pos
	if not step.target_is_activator and not step.target_path.is_empty():
		var target: Node = step.resolve_target(self, activator)
		if target is Node3D:
			var target_3d: Node3D = target as Node3D
			dest_pos = target_3d.global_position
	elif dest_pos == Vector3.ZERO:
		dest_pos = global_position

	print("EventSequenceTrigger: TELEPORT_PLAYER -> ", dest_pos)
	if player_node.has_method(&"teleport_to"):
		player_node.call(&"teleport_to", dest_pos, 0.0)
	else:
		player_node.global_position = dest_pos


## Resolves the active player [Node3D] from [param activator] or scene group.
func _resolve_player_node(activator: Node3D) -> Node3D:
	if is_instance_valid(activator):
		return activator
	if is_instance_valid(_active_activator):
		return _active_activator
	if is_inside_tree():
		var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
		for node: Node in players:
			if node is CharacterBody3D:
				return node as Node3D
	return null


## Resolves the active [Camera3D] from [param player_node] or current viewport.
func _resolve_camera(player_node: Node3D) -> Camera3D:
	if is_instance_valid(player_node):
		var cam_child: Node = player_node.find_child("Camera3D", true, false)
		if cam_child is Camera3D:
			return cam_child as Camera3D
	if is_inside_tree():
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			return vp.get_camera_3d()
	return null


## Halts [DrunkEffect] per-frame camera roll/FOV overrides before explicit camera tweens.
func _halt_drunk_camera_override(player_node: Node3D) -> void:
	if not is_instance_valid(player_node):
		return
	var drunk_layer: Node = player_node.get_node_or_null("DrunkEffect")
	if is_instance_valid(drunk_layer):
		drunk_layer.set_process(false)


## Awaits configured completion signal on the step target node.
func _await_step_signal(step: EventStep, activator: Node3D) -> void:
	var target: Node = step.resolve_target(self, activator)
	if not is_instance_valid(target):
		return
	if step.signal_name.is_empty() or not target.has_signal(step.signal_name):
		print("EventSequenceTrigger: Missing signal ", step.signal_name, " on ", target.name)
		return
	print("EventSequenceTrigger: Awaiting signal ", step.signal_name, " on ", target.name)
	await Signal(target, step.signal_name)


## Awaits continuous player camera gaze alignment toward step target node.
func _await_step_look(step: EventStep, activator: Node3D) -> void:
	var target: Node = step.resolve_target(self, activator)
	if not (target is Node3D):
		print("EventSequenceTrigger: Target not Node3D for WAIT_LOOK on ", name)
		return

	var target_3d: Node3D = target as Node3D
	var accumulated_time: float = 0.0
	print("EventSequenceTrigger: Awaiting gaze on ", target_3d.name)

	while is_inside_tree() and is_instance_valid(self):
		await get_tree().process_frame
		if not is_instance_valid(self) or not is_inside_tree() or not is_instance_valid(target_3d):
			return

		if is_instance_valid(_active_activator) and not _activator_inside:
			accumulated_time = 0.0
			continue

		var vp: Viewport = get_viewport()
		if not is_instance_valid(vp):
			continue
		var cam: Camera3D = vp.get_camera_3d()
		if not is_instance_valid(cam):
			continue

		var dir_to_target: Vector3 = cam.global_position.direction_to(target_3d.global_position)
		var camera_forward: Vector3 = -cam.global_transform.basis.z.normalized()
		var dot_product: float = camera_forward.dot(dir_to_target)

		var delta: float = get_process_delta_time()
		if delta <= 0.0:
			delta = 1.0 / 60.0

		if dot_product >= step.look_tolerance:
			accumulated_time += delta
			if accumulated_time >= step.look_time:
				print("EventSequenceTrigger: Gaze threshold met for ", target_3d.name)
				return
		else:
			accumulated_time = 0.0
