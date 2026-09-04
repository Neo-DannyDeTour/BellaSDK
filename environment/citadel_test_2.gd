## Controls the emission energy and overload state of the Citadel Core mesh.
##
## [CitadelCoreController] interacts directly with a [ShaderMaterial] on the mesh
## to visually represent the core's energy levels increasing or decreasing based
## on puzzle states or triggers in the environment.
class_name CitadelCoreController
extends MeshInstance3D

## The factor by which the base emission energy is multiplied when overloaded.
@export var overload_multiplier: float = 3.0

## The default emission energy level of the core when stable.
var _base_energy: float = 2.0

## Tracks whether the core is currently in an overloaded state.
var _is_overloaded: bool = false

## Cached reference to the active [ShaderMaterial] on the mesh.
var _material: ShaderMaterial


## Called when the node enters the scene tree for the first time.
## Locates the [ShaderMaterial] and sets the initial base energy.
func _ready() -> void:
	print("CitadelCoreController: Initializing Citadel Core...")

	# Grab the active material to manipulate shader parameters via code
	var mat: Material = get_active_material(0)
	if mat is ShaderMaterial:
		_material = mat as ShaderMaterial
		print("CitadelCoreController: Shader material successfully loaded.")
		_material.set_shader_parameter("emission_energy", _base_energy)
	else:
		print("CitadelCoreController: Error - Shader material not found on surface 0.")


## Increases the core's emission energy to simulate an overloaded state.
func trigger_overload() -> void:
	print("CitadelCoreController: Triggering core overload sequence!")
	if _is_overloaded:
		print("CitadelCoreController: Core is already overloaded. Ignoring call.")
		return

	_is_overloaded = true
	if _material:
		var target_energy: float = _base_energy * overload_multiplier
		_material.set_shader_parameter("emission_energy", target_energy)
		print("CitadelCoreController: Emission energy increased to: ", target_energy)


## Restores the core's emission energy back to its stable baseline.
func stabilize_core() -> void:
	print("CitadelCoreController: Stabilizing core...")
	if not _is_overloaded:
		print("CitadelCoreController: Core is already stable. Ignoring call.")
		return

	_is_overloaded = false
	if _material:
		_material.set_shader_parameter("emission_energy", _base_energy)
		print("CitadelCoreController: Core stabilized. Emission energy reset to base level.")
