@tool
class_name LaserTarget
extends StaticBody3D

signal activated
signal deactivated

@export var targets: Array[Node3D]:
	set(value):
		targets = value
		_update_transmitter_targets()

@export var transmitter: OutputTransmitter3D:
	set(value):
		transmitter = value
		_update_transmitter_targets()


func _ready() -> void:
	_update_transmitter_targets()


func power_on() -> void:
	print("LaserTarget: Hit by laser! Forwarding power_on to transmitter.")
	activated.emit()
	if is_instance_valid(transmitter):
		transmitter.power_on()


func power_off() -> void:
	print("LaserTarget: Laser removed! Forwarding power_off to transmitter.")
	deactivated.emit()
	if is_instance_valid(transmitter):
		transmitter.power_off()


func _update_transmitter_targets() -> void:
	if is_instance_valid(transmitter):
		transmitter.targets = targets
