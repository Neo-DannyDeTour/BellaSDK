## Controls a 3D spotlight powered by a [PowerComponent].
##
## Acts as a logic bridge, taking an exported power requirement
## and passing it to the internal component to manage light visibility.
class_name LightLogic
extends Node3D

## The number of distinct power sources needed to turn this light on.
@export var required_power: int = 1

## Reference to the internal component that calculates power inputs.
@onready var power_component: PowerComponent = $PowerComponent
## Reference to the visual spotlight node.
@onready var light: SpotLight3D = $SpotLight3D


## Initializes the power requirement and sets up signal connections.
## Lifecycle trigger: _ready.
## Returns void.
func _ready() -> void:
	# 1. Pass the designer's chosen number down to the calculator
	power_component.required_power = self.required_power

	# 2. Start the light completely off
	light.visible = false

	# 3. Listen for the component's signals
	power_component.powered_on.connect(_turn_on_light)
	power_component.powered_off.connect(_turn_off_light)


## Handles the signal when sufficient power is received.
## Returns void.
func _turn_on_light() -> void:
	light.visible = true


## Handles the signal when power drops below the required threshold.
## Returns void.
func _turn_off_light() -> void:
	light.visible = false
