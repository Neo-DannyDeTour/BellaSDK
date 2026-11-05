@tool
class_name EventSequenceTrigger
extends BaseTriggerArea3D

## Area3D trigger evaluating gate conditions and executing sequential or parallel [EventStep]s.

## Emitted when all non-parallel steps in the sequence complete execution.
signal sequence_completed

## Default physics collision mask bit for Player (Layer 2 = bit value 2).
const DEFAULT_ACTIVATOR_MASK: int = 2

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
				await _run_step_action(step, activator)
			EventStep.ExecMode.WAIT_SIGNAL:
				await _run_step_action(step, activator)
				await _await_step_signal(step, activator)
			EventStep.ExecMode.WAIT_LOOK:
				await _run_step_action(step, activator)
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


## Waits for step delay and executes step action.
func _run_step_action(step: EventStep, activator: Node3D) -> void:
	if step.delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(step.delay).timeout
	if is_instance_valid(self) and is_inside_tree():
		step.execute(self, activator)


## Spawns detached coroutine for parallel step execution without blocking sequence.
func _run_parallel_step(step: EventStep, activator: Node3D) -> void:
	await _run_step_action(step, activator)


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
