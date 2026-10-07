@tool
## Controls proximity detection, extending spikes, and automated retraction.
class_name SpikeTrap
extends Node3D

@export_group("Trigger Settings")
## Enables automatic detection when a player enters the trigger volume.
@export var use_proximity_trigger: bool = true
## Prevents the trap from resetting while any player remains inside.
@export var stay_active_while_inside: bool = true
## Proximity [Area3D] handling collision signals.
@export var proximity_area: Area3D
## Child [CollisionShape3D] representing the trigger boundary.
@export var proximity_shape_node: CollisionShape3D

@export_group("Trigger Dimensions")
## Extents size applied to the trigger box volume.
@export var trigger_size: Vector3 = Vector3(2.0, 2.0, 2.0):
	set(value):
		trigger_size = value
		if is_inside_tree() and is_node_ready():
			_update_trigger_shape()

## Positional offset applied to the trigger shape node.
@export var trigger_offset: Vector3 = Vector3.ZERO:
	set(value):
		trigger_offset = value
		if is_inside_tree() and is_node_ready():
			_update_trigger_shape()

@export_group("Movement Settings")
## Vertical distance in meters the spikes extend when triggered.
@export var move_distance: float = 2.0
## Duration in seconds of the spike thrust animation.
@export var move_duration: float = 0.15
## Delay in seconds before spikes attempt to retract.
@export var return_delay: float = 1.5
## Animated physics body holding spike meshes and hazard colliders.
@export var spike_body: AnimatableBody3D

## Indicates whether the trap is currently activated or extending.
var _is_triggered: bool = false
## Indicates whether the trap is currently playing its retraction tween.
var _is_retracting: bool = false
## Number of player bodies currently located within the proximity trigger.
var _players_in_zone: int = 0
## Initial resting position of the spike physics body.
var _original_position: Vector3


## Initializes spike positions, configures colliders, and binds events.
func _ready() -> void:
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


## Extends spikes upward using a tween animation.
func trigger_spikes() -> void:
	if _is_triggered:
		return

	print("SpikeTrap: Spikes activated and extending.")
	_is_triggered = true
	_is_retracting = false

	var tween: Tween = create_tween()
	var target: Vector3 = _original_position + Vector3(0.0, move_distance, 0.0)

	tween.tween_property(spike_body, ^"position", target, move_duration)
	tween.tween_callback(_on_spikes_fully_extended)


## Waits for delay timer after extension before starting retraction.
func _on_spikes_fully_extended() -> void:
	await get_tree().create_timer(return_delay).timeout
	_try_retract()


## Verifies safety conditions and retracts spikes to resting position.
func _try_retract() -> void:
	if not _is_triggered or _is_retracting:
		return

	if stay_active_while_inside and _players_in_zone > 0:
		print("SpikeTrap: Delaying retraction. Player is still in zone.")
		return

	print("SpikeTrap: Spikes retracting.")
	_is_retracting = true

	var tween: Tween = create_tween()
	tween.tween_property(spike_body, ^"position", _original_position, move_duration * 2.0)
	tween.tween_callback(_reset_trigger)


## Tracks entering player bodies and triggers extension.
func _on_body_entered(body: Node3D) -> void:
	if not use_proximity_trigger:
		return

	if body.is_in_group(&"player"):
		_players_in_zone += 1
		trigger_spikes()


## Tracks exiting bodies and initiates retraction if zone is clear.
func _on_body_exited(body: Node3D) -> void:
	if not use_proximity_trigger:
		return

	if body.is_in_group(&"player"):
		_players_in_zone = maxi(0, _players_in_zone - 1)

		if _players_in_zone == 0 and _is_triggered and not _is_retracting:
			print("SpikeTrap: Player left zone. Preparing to retract.")
			await get_tree().create_timer(0.2).timeout
			_try_retract()


## Resets trap state flags and triggers immediately if players remain.
func _reset_trigger() -> void:
	print("SpikeTrap: Trap reset.")
	_is_triggered = false
	_is_retracting = false

	if _players_in_zone > 0 and use_proximity_trigger:
		trigger_spikes()


## Updates collision shape dimensions and offset safely in editor and runtime.
func _update_trigger_shape() -> void:
	if not is_instance_valid(proximity_shape_node):
		if Engine.is_editor_hint():
			print("SpikeTrap: Proximity Shape Node is missing in the Inspector.")
		return

	proximity_shape_node.position = trigger_offset

	var box_shape: BoxShape3D = (
		proximity_shape_node.shape if proximity_shape_node.shape is BoxShape3D else null
	)
	if box_shape:
		box_shape.size = trigger_size
	elif not proximity_shape_node.shape:
		var new_shape: BoxShape3D = BoxShape3D.new()
		new_shape.size = trigger_size
		proximity_shape_node.shape = new_shape
