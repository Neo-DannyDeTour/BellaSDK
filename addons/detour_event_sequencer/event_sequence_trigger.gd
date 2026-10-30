## Area3D trigger evaluating gate conditions and executing sequential or parallel [EventStep]s.
@tool
class_name EventSequenceTrigger
extends Area3D

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

## If true, trigger fires only once and ignores subsequent entries.
@export var trigger_once: bool = true

@export_group("Sequence Data")
## Gate conditions that must all evaluate to true on entry before steps run.
@export var conditions: Array[EventCondition] = []

## Ordered list of [EventStep] actions executed when conditions pass.
@export var steps: Array[EventStep] = []

## Tracks whether this trigger has completed a valid activation.
var _has_triggered: bool = false

## Flag preventing overlapping sequential executions while running.
var _is_running: bool = false


## Configures collision layers and connects body entry listener at runtime.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = activator_mask
	if Engine.is_editor_hint():
		return
	print("EventSequenceTrigger: Ready -> ", name)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


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

	_is_running = false
	sequence_completed.emit()
	print("EventSequenceTrigger: Sequence completed on ", name)


## Entry callback verifying activator eligibility and gate conditions.
func _on_body_entered(body: Node3D) -> void:
	if _has_triggered and trigger_once:
		return
	if _is_running:
		return
	if not are_conditions_met(body):
		print("EventSequenceTrigger: Conditions not met for ", body.name)
		return

	print("EventSequenceTrigger: Activated by ", body.name)
	_has_triggered = true
	trigger_sequence(body)


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
