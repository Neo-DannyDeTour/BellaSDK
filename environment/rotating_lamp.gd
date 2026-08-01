@tool
extends Node3D
class_name RotatingLamp

## Defines how fast the rotor part of the lamp spins (in radians per second).
@export var rotation_speed: float = 3.14

## Determines the color of both the spotlight and the glowing mesh emission.
@export var lamp_color: Color = Color(1.0, 0.0, 0.0):
	set(value):
		lamp_color = value
		_update_lamp_visuals()

## Controls the brightness intensity of the spotlight and the glowing mesh.
@export var lamp_energy: float = 5.0:
	set(value):
		lamp_energy = value
		_update_lamp_visuals()

## Toggles whether the lamp is actively spinning and emitting light.
@export var is_active: bool = true

@onready var rotor: Node3D = $Rotor
@onready var spot_light: SpotLight3D = $Rotor/SpotLight3D
@onready var light_mesh: MeshInstance3D = $Rotor/LightMesh

var _lamp_material: StandardMaterial3D


func _ready() -> void:
	_lamp_material = StandardMaterial3D.new()
	if light_mesh:
		light_mesh.set_surface_override_material(0, _lamp_material)
	_update_lamp_visuals()


func _process(delta: float) -> void:
	# Engine.is_editor_hint() prevents the lamp from spinning in the editor viewport.
	if is_active and not Engine.is_editor_hint():
		if rotor:
			rotor.rotate_y(rotation_speed * delta)


## Toggles the lamp's active state on or off when called by a player or event.
func toggle_lamp() -> void:
	is_active = not is_active
	if spot_light:
		spot_light.visible = is_active

	if is_active:
		print("Rotating lamp activated by player.")
	else:
		print("Rotating lamp deactivated by player.")


func _update_lamp_visuals() -> void:
	if spot_light:
		spot_light.light_color = lamp_color
		spot_light.light_energy = lamp_energy
		# Shadow kept false to maintain strict 60 FPS performance.
		spot_light.shadow_enabled = false

	if _lamp_material:
		_lamp_material.albedo_color = lamp_color
		_lamp_material.emission_enabled = true
		_lamp_material.emission = lamp_color
		_lamp_material.emission_energy_multiplier = lamp_energy
