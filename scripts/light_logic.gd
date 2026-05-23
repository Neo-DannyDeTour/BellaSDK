extends Node3D

# --- THE FIX: Expose the setting on the Root Node ---
@export var required_power: int = 1

@onready var power_component: PowerComponent = $PowerComponent
@onready var light: SpotLight3D = $SpotLight3D


func _ready() -> void:
	# 1. Pass the designer's chosen number down to the calculator
	power_component.required_power = self.required_power

	# 2. Start the light completely off
	light.visible = false

	# 3. Listen for the component's signals
	power_component.powered_on.connect(_turn_on_light)
	power_component.powered_off.connect(_turn_off_light)


func _turn_on_light() -> void:
	light.visible = true


func _turn_off_light() -> void:
	light.visible = false
