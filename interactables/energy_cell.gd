## Physical energy cell that powers generators and can be recharged.
class_name EnergyCell
extends PickableObject

## Emitted when the cell charging state changes.
signal charged_state_changed(is_charged: bool)

## Shader resource used for the bottom-to-top gradient fill animation.
@export var fill_shader: Shader = preload("res://interactables/energy_cell_fill.gdshader")

## Color applied to the cell mesh when depleted of energy.
@export var discharged_color: Color = Color(0.9, 0.15, 0.15, 1.0)

## Color applied to the cell mesh and glow when fully charged.
@export var charged_color: Color = Color(0.15, 0.95, 0.25, 1.0)

## Emission brightness multiplier applied when the cell is charged.
@export var glow_energy: float = 2.5

## Indicates whether the cell is currently charged with energy.
@export var is_charged: bool = false:
	set = set_charged

## Runtime material instance supporting gradual filling.
var _cell_shader_mat: ShaderMaterial = null

## Normalized progress of the vertical charging gradient (0.0 to 1.0).
var fill_progress: float = 0.0:
	set = set_fill_progress


## Initializes the custom shader material and default visual state.
func _ready() -> void:
	super._ready()
	print("EnergyCell: Initializing cell instance: ", name)
	_setup_shader_material()
	_update_cell_visuals()


## Instantiates and assigns the ShaderMaterial on the primary mesh.
func _setup_shader_material() -> void:
	if not is_instance_valid(mesh) or not mesh is GeometryInstance3D:
		return

	var geom: GeometryInstance3D = mesh as GeometryInstance3D
	_cell_shader_mat = ShaderMaterial.new()
	_cell_shader_mat.shader = fill_shader
	_cell_shader_mat.set_shader_parameter("discharged_color", discharged_color)
	_cell_shader_mat.set_shader_parameter("charged_color", charged_color)
	_cell_shader_mat.set_shader_parameter("glow_energy", glow_energy)

	geom.set_surface_override_material(0, _cell_shader_mat)


## Sets the normalized vertical fill level from 0.0 (bottom) to 1.0 (top).
func set_fill_progress(value: float) -> void:
	fill_progress = clampf(value, 0.0, 1.0)
	if is_instance_valid(_cell_shader_mat):
		_cell_shader_mat.set_shader_parameter("fill_progress", fill_progress)


## Updates the charging state and aligns progress threshold.
func set_charged(value: bool) -> void:
	is_charged = value
	print("EnergyCell: set_charged() called on ", name, " -> ", is_charged)
	fill_progress = 1.0 if is_charged else 0.0
	_update_cell_visuals()
	charged_state_changed.emit(is_charged)


## Fully charges the cell, turning it green with an emissive glow.
func charge() -> void:
	print("EnergyCell: charge() executed on ", name)
	set_charged(true)


## Discharges the cell, turning it red and removing glow.
func discharge() -> void:
	print("EnergyCell: discharge() executed on ", name)
	set_charged(false)


## Refreshes shader uniform values to match current attributes.
func _update_cell_visuals() -> void:
	if not is_instance_valid(_cell_shader_mat):
		return

	_cell_shader_mat.set_shader_parameter("fill_progress", fill_progress)
