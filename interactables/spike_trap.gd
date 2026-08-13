@tool
extends Node3D
class_name SpikeTrap

@export_group("Trigger Settings")
## Use proximity trigger.
@export var use_proximity_trigger: bool = true
## Stay active while inside.
@export var stay_active_while_inside: bool = true
## Proximity area.
@export var proximity_area: Area3D
## Proximity shape node.
@export var proximity_shape_node: CollisionShape3D

@export_group("Trigger Dimensions")
## Trigger size.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_node_ready():
			_update_trigger_shape()

## Trigger offset.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_node_ready():
			_update_trigger_shape()

@export_group("Movement Settings")
## Move distance.
@export var move_distance: float = 2.0
## Move duration.
@export var move_duration: float = 0.15
## Return delay.
@export var return_delay: float = 1.5
## Spike body.
@export var spike_body: AnimatableBody3D

## Is triggered.
var _is_triggered: bool = false
## Is retracting.
var _is_retracting: bool = false
## Players in zone.
var _players_in_zone: int = 0
## Original position.
var _original_position: Vector3


func _ready() -> void:
	# Force the shape to update now that the node tree is built
	_update_trigger_shape()

	if Engine.is_editor_hint():
		return

	if not spike_body:
		push_error("SpikeTrap: Spike body is not assigned.")
		return

	_original_position = spike_body.position

	if use_proximity_trigger and proximity_area:
		proximity_area.body_entered.connect(_on_body_entered)
		proximity_area.body_exited.connect(_on_body_exited)


func trigger_spikes() -> void:
	if _is_triggered:
		return

	print("SpikeTrap: Spikes activated and extending.")
	_is_triggered = true
	_is_retracting = false

	var tween: Tween = create_tween()
	var target: Vector3 = _original_position + Vector3(0.0, move_distance, 0.0)

	tween.tween_property(spike_body, "position", target, move_duration)
	tween.tween_callback(_on_spikes_fully_extended)


func _on_spikes_fully_extended() -> void:
	await get_tree().create_timer(return_delay).timeout
	_try_retract()


func _try_retract() -> void:
	if not _is_triggered or _is_retracting:
		return

	if stay_active_while_inside and _players_in_zone > 0:
		print("SpikeTrap: Delaying retraction. Player is still in zone.")
		return

	print("SpikeTrap: Spikes retracting.")
	_is_retracting = true

	var tween: Tween = create_tween()
	tween.tween_property(spike_body, "position", _original_position, move_duration * 2.0)
	tween.tween_callback(_reset_trigger)


func _on_body_entered(body: Node3D) -> void:
	if not use_proximity_trigger:
		return

	if body.is_in_group("player"):
		_players_in_zone += 1
		trigger_spikes()


func _on_body_exited(body: Node3D) -> void:
	if not use_proximity_trigger:
		return

	if body.is_in_group("player"):
		_players_in_zone = maxi(0, _players_in_zone - 1)

		if _players_in_zone == 0 and _is_triggered and not _is_retracting:
			print("SpikeTrap: Player left zone. Preparing to retract.")
			await get_tree().create_timer(0.2).timeout
			_try_retract()


func _reset_trigger() -> void:
	print("SpikeTrap: Trap reset.")
	_is_triggered = false
	_is_retracting = false

	if _players_in_zone > 0 and use_proximity_trigger:
		trigger_spikes()


func _update_trigger_shape() -> void:
	if not is_instance_valid(proximity_shape_node):
		if Engine.is_editor_hint():
			print("SpikeTrap: Proximity Shape Node is missing in the Inspector.")
		return

	proximity_shape_node.position = trigger_offset

	var shape: Shape3D = proximity_shape_node.shape
	if shape is BoxShape3D:
		shape.size = trigger_size
	elif not shape:
		var new_shape: BoxShape3D = BoxShape3D.new()
		new_shape.size = trigger_size
		proximity_shape_node.shape = new_shape
