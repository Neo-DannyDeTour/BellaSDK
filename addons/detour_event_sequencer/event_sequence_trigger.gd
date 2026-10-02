## Area3D trigger executing sequential actions, signal waits, and branch logic.
@tool
class_name EventSequenceTrigger
extends Area3D

## Emitted when all event steps in the sequence complete execution.
signal sequence_completed

## Collision layer bit designated for player detection.
const PLAYER_COLLISION_MASK: int = 2

@export_group("Sequence Settings")
## Ordered array of [EventStep] resources executed on activation.
@export var steps: Array[EventStep] = []

## If true, trigger fires only once and deactivates.
@export var trigger_once: bool = true

## Tracks whether this trigger has already executed.
var _has_triggered: bool = false

## Flag indicating sequence is currently executing asynchronously.
var _is_running: bool = false


## Sets player collision mask and connects body entry signal.
func _ready() -> void:
	print("EventSequenceTrigger: Initialized ", name)
	if Engine.is_editor_hint():
		return
	collision_layer = 0
	collision_mask = PLAYER_COLLISION_MASK
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


## Trigger callback executed when a body enters [Area3D].
func _on_body_entered(body: Node3D) -> void:
	print("EventSequenceTrigger: Body entered -> ", body.name)
	if _has_triggered and trigger_once:
		return
	if _is_running:
		return
	_has_triggered = true
	trigger_sequence()


## Executes sequence steps asynchronously, handling delays, signals, and branching.
func trigger_sequence() -> void:
	print("EventSequenceTrigger: Starting sequence with ", steps.size(), " steps.")
	_is_running = true
	var current_idx: int = 0

	while current_idx < steps.size():
		var step: EventStep = steps[current_idx]
		if step == null:
			current_idx += 1
			continue

		if step.fire_once and step._has_fired:
			current_idx += 1
			continue

		if step.delay > 0.0:
			print("EventSequenceTrigger: Delaying step by ", step.delay, " seconds.")
			await get_tree().create_timer(step.delay).timeout

		match step.step_type:
			EventStep.StepType.CALL_METHOD:
				step.execute(self)
				current_idx += 1

			EventStep.StepType.WAIT_SIGNAL:
				var target: Node = get_node_or_null(step.target_path)
				if not is_instance_valid(target):
					print("EventSequenceTrigger: Target not found: ", step.target_path)
					current_idx += 1
					continue

				var sig_name: StringName = step.signal_name
				if sig_name.is_empty():
					sig_name = step.method_name

				if sig_name.is_empty() or not target.has_signal(sig_name):
					print("EventSequenceTrigger: Missing signal '", sig_name, "' on ", target.name)
					current_idx += 1
					continue

				print("EventSequenceTrigger: Awaiting signal '", sig_name, "' on ", target.name)
				await Signal(target, sig_name)
				print("EventSequenceTrigger: Signal '", sig_name, "' fired. Continuing.")
				current_idx += 1

			EventStep.StepType.LOGIC_BRANCH:
				var condition_met: bool = step.evaluate_condition(self)
				print("EventSequenceTrigger: Branch evaluated as ", condition_met)
				if condition_met and step.branch_jump_step >= 0:
					current_idx = step.branch_jump_step
				else:
					current_idx += 1

	_is_running = false
	sequence_completed.emit()
	print("EventSequenceTrigger: Sequence completed cleanly.")
