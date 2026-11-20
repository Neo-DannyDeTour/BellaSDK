## Event-driven industrial bulkhead cage light controller.
## Manages Render Layer 1, per-instance glass shader uniforms, and [OmniLight3D] state.
# class_name CageLight
extends Node3D

## Render Layer 1 (Environment).
const LAYER_ENVIRONMENT: int = 1
## Instance shader uniform for glass emission energy.
const PARAM_EMISSION_ENERGY: StringName = &"emission_energy"
## Instance shader uniform for glass emission color.
const PARAM_EMISSION_COLOR: StringName = &"emission_color"

## Target bulkhead mesh with glass dome on surface 1.
@export var mesh_instance: MeshInstance3D
## Optional [OmniLight3D] paired with the glass dome.
@export var omni_light: OmniLight3D
## Initial enabled state applied in [method _ready].
@export var default_enabled: bool = true
## Shader emission energy when enabled.
@export var active_shader_energy: float = 2.5
## Light energy when enabled.
@export var active_light_energy: float = 1.2
## Shared light and glass emission tint.
@export var light_color: Color = Color(1.0, 0.68, 0.22, 1.0)

var _is_enabled: bool = true


## Validates nodes, sets Render Layer 1, disables process loops, and applies initial state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(mesh_instance != null, "CageLight: mesh_instance must be assigned.")

	mesh_instance.layers = LAYER_ENVIRONMENT
	if is_instance_valid(omni_light):
		omni_light.layers = LAYER_ENVIRONMENT
		omni_light.light_color = light_color

	mesh_instance.set_instance_shader_parameter(PARAM_EMISSION_COLOR, light_color)
	set_light_state(default_enabled, active_shader_energy, active_light_energy)


## Sets the discrete on/off state and energy of the bulkhead light without duplicating materials.
func set_light_state(enabled: bool, shader_energy: float = 2.5, omni_energy: float = 1.2) -> void:
	_is_enabled = enabled
	var target_shader_energy: float = shader_energy if enabled else 0.0
	var target_omni_energy: float = omni_energy if enabled else 0.0

	if is_instance_valid(mesh_instance):
		mesh_instance.set_instance_shader_parameter(PARAM_EMISSION_ENERGY, target_shader_energy)

	if is_instance_valid(omni_light):
		omni_light.visible = enabled and target_omni_energy > 0.0
		omni_light.light_energy = target_omni_energy

	print(
		"CageLight [%s] state -> enabled: %s, energy: %.2f" % [name, enabled, target_shader_energy]
	)
