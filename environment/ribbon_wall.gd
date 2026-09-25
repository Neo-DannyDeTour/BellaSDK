@tool
## 3D emissive wall projecting an animated liquid ribbon shader.
class_name RibbonWall
extends Node3D

## Emitted when ribbon gradient colors are updated.
signal colors_changed(color_a: Color, color_b: Color)

@export_group("Wall Dimensions")

## Dimensions of the wall mesh and collision box in meters.
@export var wall_size: Vector2 = Vector2(6.0, 3.0):
	set(value):
		wall_size = value
		_update_mesh_and_collision()

## Thickness depth of the wall collision box in meters.
@export var wall_depth: float = 0.2:
	set(value):
		wall_depth = value
		_update_mesh_and_collision()

@export_group("Lighting & Emission")

## Emissive energy multiplier for world lighting bounce.
@export_range(0.0, 16.0, 0.1) var emission_energy: float = 3.0:
	set(value):
		emission_energy = value
		_update_surface_material()

@export_group("Ribbon Palette")

## Background tone underlying the liquid ribbon effect.
@export var base_color: Color = Color(0.05, 0.05, 0.05, 1.0):
	set(value):
		base_color = value
		_set_shader_param(&"base_color", value)

## First gradient stop color for the flowing ribbon.
@export var ribbon_color_a: Color = Color(0.2, 0.6, 1.0, 1.0):
	set(value):
		ribbon_color_a = value
		_set_shader_param(&"ribbon_color_a", value)
		colors_changed.emit(ribbon_color_a, ribbon_color_b)

## Second gradient stop color for the flowing ribbon.
@export var ribbon_color_b: Color = Color(1.0, 0.3, 0.6, 1.0):
	set(value):
		ribbon_color_b = value
		_set_shader_param(&"ribbon_color_b", value)
		colors_changed.emit(ribbon_color_a, ribbon_color_b)

@export_group("Shader Dynamics")

## Density factor of internal ribbon stripes.
@export_range(1.0, 200.0, 0.1) var zoom: float = 20.0:
	set(value):
		zoom = value
		_set_shader_param(&"zoom", value)

## Vertical cropping limit defining ribbon band thickness.
@export_range(0.1, 1.0, 0.01) var wave_crop: float = 0.8:
	set(value):
		wave_crop = maxf(value, 0.1)
		_set_shader_param(&"wave_crop", wave_crop)

## Global brightness applied to ribbon soft limits.
@export_range(0.1, 3.0, 0.01) var brightness: float = 1.0:
	set(value):
		brightness = value
		_set_shader_param(&"brightness", value)

## Flow rate multiplier of the ribbon distortion over time.
@export_range(0.0, 10.0, 0.01) var speed: float = 1.0:
	set(value):
		speed = value
		_set_shader_param(&"speed", value)

## Iteration depth for domain-warping waves.
@export_range(1, 30) var iterations: int = 5:
	set(value):
		iterations = value
		_set_shader_param(&"iterations", value)

## Base frequency start value for wave iterations.
@export_range(0.1, 50.0, 0.01) var frq_start: float = 20.0:
	set(value):
		frq_start = value
		_set_shader_param(&"frq_start", value)

## Multiplier applied to frequency with every iteration step.
@export_range(0.1, 2.0, 0.01) var frq_coef: float = 1.0:
	set(value):
		frq_coef = value
		_set_shader_param(&"frq_coef", value)

## Alpha cutoff threshold for dark areas to produce transparency.
@export_range(0.0, 1.0, 0.01) var alpha_threshold: float = 0.0:
	set(value):
		alpha_threshold = value
		_set_shader_param(&"alpha_threshold", value)

## Visual mesh instance used for the wall surface.
@onready var _wall_mesh: MeshInstance3D = $WallMesh

## Collision shape attached to the wall static body.
@onready var _collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D

## Viewport generating the dynamic ribbon render target.
@onready var _viewport: SubViewport = $ScreenViewport

## ColorRect rendering the ribbon shader inside the SubViewport.
@onready var _screen_rect: ColorRect = $ScreenViewport/RibbonScreen

## Cached material applied to the wall mesh.
var _surface_mat: StandardMaterial3D

## Cached shader material applied to the 2D ribbon.
var _shader_mat: ShaderMaterial

## Elapsed time accumulator driving editor animation updates.
var _editor_time: float = 0.0


## Initializes node links, sizes, and flushes shader values.
func _ready() -> void:
	_ensure_nodes()
	_setup_viewport_texture()
	_update_viewport_resolution()
	_update_mesh_and_collision()
	_update_surface_material()
	_sync_all_shader_params()
	if not Engine.is_editor_hint():
		_set_shader_param(&"custom_time", -1.0)


## Advances shader time continuously while working inside the editor.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_time += delta * speed
		_set_shader_param(&"custom_time", _editor_time)


## Finds child references safely without deserialization errors.
func _ensure_nodes() -> void:
	if not is_inside_tree():
		return

	if not is_instance_valid(_wall_mesh):
		_wall_mesh = get_node_or_null("WallMesh") as MeshInstance3D

	if not is_instance_valid(_collision_shape):
		_collision_shape = get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D

	if not is_instance_valid(_viewport):
		_viewport = get_node_or_null("ScreenViewport") as SubViewport

	if not is_instance_valid(_screen_rect):
		_screen_rect = get_node_or_null("ScreenViewport/RibbonScreen") as ColorRect

	if is_instance_valid(_wall_mesh):
		var active_mat: Material = _wall_mesh.get_active_material(0)
		if active_mat is StandardMaterial3D:
			_surface_mat = active_mat as StandardMaterial3D

	if is_instance_valid(_screen_rect):
		if _screen_rect.material is ShaderMaterial:
			_shader_mat = _screen_rect.material as ShaderMaterial


## Binds the SubViewport target texture to the 3D surface material.
func _setup_viewport_texture() -> void:
	if not is_instance_valid(_viewport) or not is_instance_valid(_surface_mat):
		return

	_viewport.render_target_update_mode = (SubViewport.UPDATE_ALWAYS)

	var vp_tex: ViewportTexture = _viewport.get_texture()
	_surface_mat.albedo_texture = vp_tex
	_surface_mat.emission_enabled = true
	_surface_mat.emission_texture = vp_tex


## Resizes the SubViewport and ColorRect to prevent stretching.
func _update_viewport_resolution() -> void:
	_ensure_nodes()
	if not is_instance_valid(_viewport) or not is_instance_valid(_screen_rect):
		return

	var base_width: int = 1024
	var aspect: float = maxf(wall_size.y / maxf(wall_size.x, 0.01), 0.1)
	var target_size: Vector2i = Vector2i(base_width, int(base_width * aspect))

	_viewport.size = target_size
	_screen_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_rect.offset_left = 0.0
	_screen_rect.offset_top = 0.0
	_screen_rect.offset_right = 0.0
	_screen_rect.offset_bottom = 0.0


## Syncs the QuadMesh or BoxMesh and BoxShape3D to current dimensions.
func _update_mesh_and_collision() -> void:
	_ensure_nodes()
	if not is_instance_valid(_wall_mesh):
		return

	if is_instance_valid(_wall_mesh.mesh):
		if _wall_mesh.mesh is QuadMesh:
			(_wall_mesh.mesh as QuadMesh).size = wall_size
		elif _wall_mesh.mesh is BoxMesh:
			(_wall_mesh.mesh as BoxMesh).size = Vector3(wall_size.x, wall_size.y, wall_depth)

	if is_instance_valid(_collision_shape):
		if _collision_shape.shape is BoxShape3D:
			var box: BoxShape3D = _collision_shape.shape as BoxShape3D
			box.size = Vector3(wall_size.x, wall_size.y, wall_depth)

	_update_viewport_resolution()


## Applies updated emission parameters to the 3D surface material.
func _update_surface_material() -> void:
	_ensure_nodes()
	if not is_instance_valid(_surface_mat):
		return
	_surface_mat.emission_energy_multiplier = emission_energy


## Updates a specific uniform parameter on the 2D ribbon shader.
func _set_shader_param(param_name: StringName, param_val: Variant) -> void:
	_ensure_nodes()
	if not is_instance_valid(_shader_mat):
		return
	_shader_mat.set_shader_parameter(param_name, param_val)


## Flushes all exported shader properties to the ShaderMaterial.
func _sync_all_shader_params() -> void:
	_set_shader_param(&"base_color", base_color)
	_set_shader_param(&"ribbon_color_a", ribbon_color_a)
	_set_shader_param(&"ribbon_color_b", ribbon_color_b)
	_set_shader_param(&"zoom", zoom)
	_set_shader_param(&"wave_crop", maxf(wave_crop, 0.1))
	_set_shader_param(&"brightness", brightness)
	_set_shader_param(&"speed", speed)
	_set_shader_param(&"iterations", iterations)
	_set_shader_param(&"frq_start", frq_start)
	_set_shader_param(&"frq_coef", frq_coef)
	_set_shader_param(&"alpha_threshold", alpha_threshold)


## Dynamically sets both ribbon colors and emits [signal colors_changed].
func set_ribbon_colors(color_a: Color, color_b: Color) -> void:
	print("RibbonWall: Updating colors to ", color_a, " and ", color_b)
	ribbon_color_a = color_a
	ribbon_color_b = color_b
