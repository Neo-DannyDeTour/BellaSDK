extends MeshInstance3D
class_name CitadelCoreController

@export var overload_multiplier: float = 3.0

var _base_energy: float = 2.0
var _is_overloaded: bool = false
var _material: ShaderMaterial


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


func stabilize_core() -> void:
	print("CitadelCoreController: Stabilizing core...")
	if not _is_overloaded:
		print("CitadelCoreController: Core is already stable. Ignoring call.")
		return

	_is_overloaded = false
	if _material:
		_material.set_shader_parameter("emission_energy", _base_energy)
		print("CitadelCoreController: Core stabilized. Emission energy reset to base level.")
