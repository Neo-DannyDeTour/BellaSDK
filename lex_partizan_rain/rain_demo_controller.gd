## Event-driven controller for the AAA Rain Shader showcase scene.
## Connects HUD controls to [ShaderMaterial] uniforms, interactive slope tilt,
## roof shelter toggle, and right-mouse orbit camera rotation.
extends Node3D

## Shader uniform parameter name for active rain intensity.
const PARAM_RAIN_AMOUNT: StringName = &"rain_amount"
## Shader uniform parameter name for surface wetness and porosity darkening.
const PARAM_WET_LEVEL: StringName = &"wet_level"
## Shader uniform parameter name for heightmap puddle coverage.
const PARAM_PUDDLE_COVERAGE: StringName = &"puddle_coverage"
## Shader uniform parameter name for snow accumulation.
const PARAM_SNOW_AMOUNT: StringName = &"snow_amount"
## Shader uniform parameter name for roof heightmap occlusion toggle.
const PARAM_USE_ROOF: StringName = &"use_roof_occlusion"
## Shader uniform parameter name for roof heightmap texture binding.
const PARAM_ROOF_TEX: StringName = &"roofing_height"
## Orbit sensitivity in radians per pixel of mouse motion.
const ORBIT_SENSITIVITY: float = 0.006
## Minimum camera pitch angle in radians.
const MIN_PITCH: float = -1.35
## Maximum camera pitch angle in radians.
const MAX_PITCH: float = -0.08

@export var camera_pivot: Node3D
@export var tilt_ramp_mesh: MeshInstance3D
@export var roof_occluder_mesh: MeshInstance3D
@export var roof_subviewport: SubViewport
@export var rain_slider: HSlider
@export var wet_slider: HSlider
@export var puddle_slider: HSlider
@export var snow_slider: HSlider
@export var slope_slider: HSlider
@export var roof_check: CheckButton
@export var status_label: Label
@export var surface_meshes: Array[MeshInstance3D] = []

var _materials: Array[ShaderMaterial] = []
var _orbiting: bool = false
var _yaw: float = -0.28
var _pitch: float = -0.58


## Validates exported nodes, binds [ViewportTexture] to materials, and connects HUD signals.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(camera_pivot != null, "Mandatory camera_pivot missing.")
	assert(tilt_ramp_mesh != null, "Mandatory tilt_ramp_mesh missing.")
	assert(roof_occluder_mesh != null, "Mandatory roof_occluder_mesh missing.")
	assert(roof_subviewport != null, "Mandatory roof_subviewport missing.")
	assert(rain_slider != null, "Mandatory rain_slider missing.")
	assert(wet_slider != null, "Mandatory wet_slider missing.")
	assert(puddle_slider != null, "Mandatory puddle_slider missing.")
	assert(snow_slider != null, "Mandatory snow_slider missing.")
	assert(slope_slider != null, "Mandatory slope_slider missing.")
	assert(roof_check != null, "Mandatory roof_check missing.")
	assert(status_label != null, "Mandatory status_label missing.")

	var roof_tex: ViewportTexture = roof_subviewport.get_texture()
	for mesh_inst: MeshInstance3D in surface_meshes:
		if not is_instance_valid(mesh_inst):
			continue
		var mat: Material = mesh_inst.get_active_material(0)
		if mat is ShaderMaterial:
			var shader_mat: ShaderMaterial = mat as ShaderMaterial
			shader_mat.set_shader_parameter(PARAM_ROOF_TEX, roof_tex)
			_materials.append(shader_mat)

	rain_slider.value_changed.connect(_on_rain_slider_changed)
	wet_slider.value_changed.connect(_on_wet_slider_changed)
	puddle_slider.value_changed.connect(_on_puddle_slider_changed)
	snow_slider.value_changed.connect(_on_snow_slider_changed)
	slope_slider.value_changed.connect(_on_slope_slider_changed)
	roof_check.toggled.connect(_on_roof_check_toggled)

	_apply_orbit_transform()
	_refresh_status_label()
	print("Rain demo initialized with ", _materials.size(), " active AAA rain materials.")


## Handles right-mouse button orbit camera rotation without per-frame polling.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			print("Camera orbit state: ", _orbiting)
	elif event is InputEventMouseMotion and _orbiting:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= mm.relative.x * ORBIT_SENSITIVITY
		_pitch = clampf(_pitch - mm.relative.y * ORBIT_SENSITIVITY, MIN_PITCH, MAX_PITCH)
		_apply_orbit_transform()


## Updates [member PARAM_RAIN_AMOUNT] across all registered materials when slider moves.
func _on_rain_slider_changed(val: float) -> void:
	_set_all_shader_params(PARAM_RAIN_AMOUNT, val)
	_refresh_status_label()
	print("Rain amount updated: ", snappedf(val, 0.01))


## Updates [member PARAM_WET_LEVEL] across all registered materials when slider moves.
func _on_wet_slider_changed(val: float) -> void:
	_set_all_shader_params(PARAM_WET_LEVEL, val)
	_refresh_status_label()
	print("Wetness level updated: ", snappedf(val, 0.01))


## Updates [member PARAM_PUDDLE_COVERAGE] across all registered materials when slider moves.
func _on_puddle_slider_changed(val: float) -> void:
	_set_all_shader_params(PARAM_PUDDLE_COVERAGE, val)
	_refresh_status_label()
	print("Puddle coverage updated: ", snappedf(val, 0.01))


## Updates [member PARAM_SNOW_AMOUNT] across all registered materials when slider moves.
func _on_snow_slider_changed(val: float) -> void:
	_set_all_shader_params(PARAM_SNOW_AMOUNT, val)
	_refresh_status_label()
	print("Snow amount updated: ", snappedf(val, 0.01))


## Tilts [member tilt_ramp_mesh] from flat (0 deg) through vertical (90 deg) to overhang (135 deg).
func _on_slope_slider_changed(deg: float) -> void:
	tilt_ramp_mesh.rotation_degrees.x = deg
	_refresh_status_label()
	print("Interactive surface tilt angle: ", snappedf(deg, 1.0), " deg")


## Toggles overhead shelter mesh visibility and [member PARAM_USE_ROOF] uniform.
func _on_roof_check_toggled(enabled: bool) -> void:
	roof_occluder_mesh.visible = enabled
	_set_all_shader_params(PARAM_USE_ROOF, enabled)
	_refresh_status_label()
	print("Roof occlusion enabled: ", enabled)


## Broadcasts a shader parameter value to every material in [member _materials].
func _set_all_shader_params(param: StringName, val: Variant) -> void:
	for shader_mat: ShaderMaterial in _materials:
		shader_mat.set_shader_parameter(param, val)


## Applies spherical yaw and pitch angles to [member camera_pivot].
func _apply_orbit_transform() -> void:
	camera_pivot.rotation = Vector3(_pitch, _yaw, 0.0)


## Refreshes the HUD telemetry summary text.
func _refresh_status_label() -> void:
	var deg: float = slope_slider.value
	var ny: float = cos(deg_to_rad(deg))
	var zone_name: String = "Flat Puddles + Ripples"
	if ny <= -0.15:
		zone_name = "Overhang (Dry)"
	elif ny < 0.85:
		zone_name = "Sloped / Vertical (Droplets + Gravity Streaks)"
	elif ny < 0.92:
		zone_name = "Shallow Slope (Droplets + Draining Puddles)"
	status_label.text = (
		"Angle: %d deg (N.y = %.2f) -> %s | RMB Drag: Orbit Camera" % [int(deg), ny, zone_name]
	)
