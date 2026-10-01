## Area3D trigger holding a sequence of Source-like [EventStep] actions.
class_name EventSequenceTrigger
extends Area3D

## Emitted when all event steps in the sequence complete execution.
signal sequence_completed

## Ordered array of [EventStep] resources executed on activation.
@export var steps: Array[EventStep] = []

## If true, trigger fires only once and deactivates.
@export var trigger_once: bool = true

## Tracks whether this trigger has already executed.
var _has_triggered: bool = false

## [method _ready] sets collision mask and connects body signal.
func _ready() -> void:
	print("EventSequenceTrigger initialized: ", name)
	collision_mask = 2 # Physics Layer 2: Player
	body_entered.connect(_on_body_entered)

## Trigger callback executed when a body enters [Area3D].
func _on_body_entered(body: Node3D) -> void:
	print("Trigger entered by body: ", body.name)
	if _has_triggered and trigger_once:
		print("Trigger already fired once. Ignoring.")
		return
	_has_triggered = true
	trigger_sequence()

## Executes all [EventStep] items sequentially with their delays.
func trigger_sequence() -> void:
	print("Starting sequence execution with ", steps.size(), " steps.")
	for step: EventStep in steps:
		if step == null:
			continue
		if step.delay > 0.0:
			await get_tree().create_timer(step.delay).timeout
		step.execute(self)
	sequence_completed.emit()
	print("Sequence execution finished.")
