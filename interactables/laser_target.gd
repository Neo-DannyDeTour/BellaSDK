@tool
## A static 3D target that detects continuous laser beams and relays power signals.
##
## Acts as a sensor node in puzzle and interaction mechanics. When hit by a laser,
## it triggers its own signals and delegates state changes to a bound [OutputTransmitter3D].
class_name LaserTarget
extends StaticBody3D

## Emitted when the target is struck by an active laser.
signal activated
## Emitted when the laser stops hitting the target.
signal deactivated

## Array of nodes that this target will pass to its associated transmitter.
@export var targets: Array[Node3D]:
	set(value):
		targets = value
		_update_transmitter_targets()

## The transmitter node responsible for forwarding the power signal.
@export var transmitter: OutputTransmitter3D:
	set(value):
		transmitter = value
		_update_transmitter_targets()


## Initializes the transmitter target list on node entry.
func _ready() -> void:
	_update_transmitter_targets()


## Receives the laser hit and forwards the activation state to the transmitter.
func power_on() -> void:
	print("LaserTarget: Hit by laser! Forwarding power_on to transmitter.")
	activated.emit()
	if is_instance_valid(transmitter):
		transmitter.power_on()


## Handles the laser removal and forwards the deactivation state to the transmitter.
func power_off() -> void:
	print("LaserTarget: Laser removed! Forwarding power_off to transmitter.")
	deactivated.emit()
	if is_instance_valid(transmitter):
		transmitter.power_off()


## Synchronizes the assigned targets array with the linked transmitter instance.
func _update_transmitter_targets() -> void:
	if is_instance_valid(transmitter):
		transmitter.targets = targets
