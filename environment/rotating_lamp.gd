## Rotating hazard lamp that spins its rotor and projects spot lighting.
@tool
class_name RotatingLamp
extends Node3D

# --------------------------------------
# EXPORTS
# --------------------------------------
## Defines how fast the rotor spins in radians per second.
@export var rotation_speed: float = 3.14

## Determines spotlight and glowing mesh emission color.
@export var lamp_color: Color = Color(1.0, 0.0, 0.0):
	set(value):
		lamp_color = value
		_update_lamp_visuals()

## Controls brightness intensity of spotlight and glowing mesh.
@export var lamp_energy: float = 5.0:
	set(value):
		lamp_energy = value
		_update_lamp_visuals()

## Toggles whether lamp is actively spinning and emitting light.
@export var is_active: bool = true

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Rotor node rotating the attached spotlight and visual mesh.
@onready var rotor: Node3D = $Rotor

## Spotlight component projecting directional cone light.
@onready var spot_light: SpotLight3D = $Rotor/SpotLight3D

## Visual mesh instance representing glowing lamp bulb.
@onready var light_mesh: MeshInstance3D = $Rotor/LightMesh

# --------------------------------------
# RUNTIME STATE
# --------------------------------------
## Runtime standard material driving bulb color and emission.
var _lamp_material: StandardMaterial3D


## Initializes runtime bulb material and applies visual settings.
func _ready() -> void:
	print("RotatingLamp: Initializing lamp on: ", name)
	_lamp_material = StandardMaterial3D.new()
	if is_instance_valid(light_mesh):
		light_mesh.set_surface_override_material(0, _lamp_material)
	_update_lamp_visuals()


## Rotates lamp rotor node around Y-axis during gameplay.
func _process(delta: float) -> void:
	if is_active and not Engine.is_editor_hint():
		if is_instance_valid(rotor):
			rotor.rotate_y(rotation_speed * delta)


## Toggles the lamp's active state on or off when called by player.
func toggle_lamp() -> void:
	is_active = not is_active
	if is_instance_valid(spot_light):
		spot_light.visible = is_active

	if is_active:
		print("RotatingLamp: Lamp activated by player.")
	else:
		print("RotatingLamp: Lamp deactivated by player.")


## Updates spotlight energy and material emission values.
func _update_lamp_visuals() -> void:
	if is_instance_valid(spot_light):
		spot_light.light_color = lamp_color
		spot_light.light_energy = lamp_energy
		spot_light.shadow_enabled = false

	if is_instance_valid(_lamp_material):
		_lamp_material.albedo_color = lamp_color
		_lamp_material.emission_enabled = true
		_lamp_material.emission = lamp_color
		_lamp_material.emission_energy_multiplier = lamp_energy
