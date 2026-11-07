@tool
# class_name ProceduralTube
extends Path3D
## Procedural spline tube generator using [Path3D] and [CSGPolygon3D].
## Supports opaque plastic, transparent plastic with UV liquid flow, and metal presets.

## Visual material style presets for the procedural tube.
enum TubeStyle {
	PLASTIC_OPAQUE,
	PLASTIC_TRANSPARENT,
	METAL,
}

## Shared opaque [ShaderMaterial] resource for plastic and metal tube styles.
const MAT_OPAQUE: ShaderMaterial = preload("res://materials/tube_opaque.tres")
## Shared transparent [ShaderMaterial] resource supporting internal UV liquid flow.
const MAT_TRANSPARENT: ShaderMaterial = preload("res://materials/tube_transparent.tres")

## Per-instance shader parameter name for surface albedo color.
const PARAM_ALBEDO: StringName = &"albedo_color"
## Per-instance shader parameter name for metallic factor.
const PARAM_METALLIC: StringName = &"metallic"
## Per-instance shader parameter name for surface roughness.
const PARAM_ROUGHNESS: StringName = &"roughness"
## Per-instance shader parameter name for transparent shell opacity.
const PARAM_ALPHA: StringName = &"alpha"
## Per-instance shader parameter name for rim Fresnel exponent.
const PARAM_FRESNEL: StringName = &"fresnel_power"
## Per-instance shader parameter name for internal fluid color and opacity.
const PARAM_LIQUID_COLOR: StringName = &"liquid_color"
## Per-instance shader parameter name for normalized 0..1 liquid fill ratio.
const PARAM_LIQUID_FILL: StringName = &"liquid_fill"
## Per-instance shader parameter name for axial UV scrolling speed.
const PARAM_FLOW_SPEED: StringName = &"flow_speed"
## Per-instance shader parameter name for outer tube wall thickness rim threshold.
const PARAM_WALL_RIM: StringName = &"wall_rim"
## Per-instance shader parameter name for total baked spline length in meters.
const PARAM_PATH_LENGTH: StringName = &"path_length"

@export_group("Style & Material")
## Active material preset controlling shader selection and default surface parameters.
@export var style: TubeStyle = TubeStyle.PLASTIC_OPAQUE:
	set(value):
		style = value
		_apply_style_defaults()
		if is_inside_tree():
			_update_material()

## Base surface tint color applied via per-instance uniform.
@export var albedo_color: Color = Color(0.85, 0.85, 0.85, 1.0):
	set(value):
		albedo_color = value
		if is_inside_tree():
			_update_material()

## Metallic reflectance ratio from 0.0 (dielectric) to 1.0 (metal).
@export_range(0.0, 1.0, 0.01) var metallic: float = 0.0:
	set(value):
		metallic = value
		if is_inside_tree():
			_update_material()

## Microsurface roughness ratio from 0.0 (mirror smooth) to 1.0 (matte).
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.35:
	set(value):
		roughness = value
		if is_inside_tree():
			_update_material()

## Base shell opacity used when [member style] is [constant TubeStyle.PLASTIC_TRANSPARENT].
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.3:
	set(value):
		alpha = value
		if is_inside_tree():
			_update_material()

## Exponent controlling grazing-angle Fresnel rim falloff.
@export_range(0.5, 8.0, 0.1) var fresnel_power: float = 2.5:
	set(value):
		fresnel_power = value
		if is_inside_tree():
			_update_material()

@export_group("Liquid Flow (Transparent Only)")
## Color and alpha of the internal flowing liquid inside transparent tubes.
@export var liquid_color: Color = Color(0.1, 0.75, 0.4, 0.9):
	set(value):
		liquid_color = value
		if is_inside_tree():
			_update_material()

## Normalized fill level (0.0 empty to 1.0 full) along the spline path length.
@export_range(0.0, 1.0, 0.01) var liquid_fill: float = 0.0:
	set(value):
		liquid_fill = clampf(value, 0.0, 1.0)
		if is_inside_tree() and is_instance_valid(csg_polygon):
			csg_polygon.set_instance_shader_parameter(PARAM_LIQUID_FILL, liquid_fill)

## UV scroll speed and direction of internal fluid animation.
@export_range(-10.0, 10.0, 0.1) var flow_speed: float = 1.5:
	set(value):
		flow_speed = value
		if is_inside_tree() and is_instance_valid(csg_polygon):
			csg_polygon.set_instance_shader_parameter(PARAM_FLOW_SPEED, flow_speed)

## Grazing-angle normal threshold masking fluid from the outer plastic wall rim.
@export_range(0.05, 0.8, 0.01) var wall_rim: float = 0.35:
	set(value):
		wall_rim = clampf(value, 0.05, 0.8)
		if is_inside_tree() and is_instance_valid(csg_polygon):
			csg_polygon.set_instance_shader_parameter(PARAM_WALL_RIM, wall_rim)

@export_group("Dimensions & Fluidity")
## Outer diameter of the circular cross-section in meters.
@export_range(0.02, 5.0, 0.01, "or_greater") var diameter: float = 0.2:
	set(value):
		diameter = maxf(0.01, value)
		if is_inside_tree():
			_update_cross_section()

## Vertical span of the procedural two-point Bezier curve when [member auto_curve] is enabled.
@export_range(0.1, 50.0, 0.05, "or_greater") var height: float = 2.0:
	set(value):
		height = maxf(0.05, value)
		if is_inside_tree() and auto_curve:
			_rebuild_auto_curve()

## When enabled, automatically generates a smooth S-bend [Curve3D] from [member height].
@export var auto_curve: bool = true:
	set(value):
		auto_curve = value
		if is_inside_tree() and auto_curve:
			_rebuild_auto_curve()

## Tangent handle offset controlling curvature when [member auto_curve] is active.
@export var bend_offset: Vector3 = Vector3(0.5, 0.0, 0.0):
	set(value):
		bend_offset = value
		if is_inside_tree() and auto_curve:
			_rebuild_auto_curve()

## Number of vertices around the circular cross-section polygon.
@export_range(6, 64, 1) var radial_segments: int = 16:
	set(value):
		radial_segments = clampi(value, 6, 64)
		if is_inside_tree():
			_update_cross_section()

## Distance interval in meters between extruded slices along the [Curve3D].
@export_range(0.01, 1.0, 0.01) var path_interval: float = 0.05:
	set(value):
		path_interval = clampf(value, 0.01, 1.0)
		if is_inside_tree() and is_instance_valid(csg_polygon):
			csg_polygon.path_interval = path_interval

@export_group("Physics")
## Enables static environment collision generation on the extruded [CSGPolygon3D].
@export var use_collision: bool = true:
	set(value):
		use_collision = value
		if is_inside_tree() and is_instance_valid(csg_polygon):
			csg_polygon.use_collision = use_collision

## Active tween instance animating [member liquid_fill].
var _fill_tween: Tween = null

## Child [CSGPolygon3D] node extruding the circular profile along this [Path3D].
@onready var csg_polygon: CSGPolygon3D = $CSGPolygon3D


## Initializes node state, connects [signal curve_changed], and builds initial geometry.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(csg_polygon), "ProceduralTube requires a CSGPolygon3D child.")

	if curve == null or (Engine.is_editor_hint() and not curve.resource_local_to_scene):
		curve = Curve3D.new() if curve == null else curve.duplicate() as Curve3D
		curve.resource_local_to_scene = true

	Utilities.safe_connect(curve_changed, _on_curve_changed)

	_configure_csg_node()
	if auto_curve or curve.point_count < 2:
		_rebuild_auto_curve()
	_update_cross_section()
	_update_material()


## Smoothly animates [member liquid_fill] to [param target_fill] over [param duration] seconds.
func tween_liquid_fill(target_fill: float, duration: float = 1.0) -> void:
	_fill_tween = Utilities.reset_tween_ext(self, _fill_tween, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	if _fill_tween == null:
		return
	_fill_tween.tween_property(self, "liquid_fill", clampf(target_fill, 0.0, 1.0), duration)
	print("ProceduralTube: tweening liquid_fill -> ", target_fill)


## Configures static [CSGPolygon3D] path parameters, UV distance scaling, and layer masks.
func _configure_csg_node() -> void:
	if not is_instance_valid(csg_polygon):
		return
	csg_polygon.mode = CSGPolygon3D.MODE_PATH
	csg_polygon.path_node = NodePath("..")
	csg_polygon.path_interval_type = CSGPolygon3D.PATH_INTERVAL_DISTANCE
	csg_polygon.path_interval = path_interval
	csg_polygon.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
	csg_polygon.path_local = true
	csg_polygon.path_u_distance = 1.0
	csg_polygon.smooth_faces = true
	csg_polygon.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	csg_polygon.use_collision = use_collision
	csg_polygon.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	csg_polygon.collision_mask = CollisionLayers.MASK_NONE


## Applies preset values to exported material properties when [member style] changes.
func _apply_style_defaults() -> void:
	match style:
		TubeStyle.PLASTIC_OPAQUE:
			metallic = 0.0
			roughness = 0.35
			fresnel_power = 3.0
		TubeStyle.PLASTIC_TRANSPARENT:
			metallic = 0.0
			roughness = 0.12
			alpha = 0.3
			fresnel_power = 2.5
		TubeStyle.METAL:
			metallic = 0.9
			roughness = 0.22
			fresnel_power = 4.0
	print("ProceduralTube: style changed -> ", TubeStyle.keys()[style])


## Rebuilds the 2-point smooth cubic Bezier [Curve3D] from [member height] and [member bend_offset].
func _rebuild_auto_curve() -> void:
	if curve == null:
		curve = Curve3D.new()
		curve.resource_local_to_scene = true

	curve.clear_points()
	var half_h: float = height * 0.5
	var p0: Vector3 = Vector3.ZERO
	var p1: Vector3 = Vector3(0.0, height, 0.0)

	var out_0: Vector3 = Vector3(bend_offset.x, half_h + bend_offset.y, bend_offset.z)
	var in_1: Vector3 = Vector3(-bend_offset.x, -half_h + bend_offset.y, -bend_offset.z)

	curve.add_point(p0, Vector3.ZERO, out_0)
	curve.add_point(p1, in_1, Vector3.ZERO)
	_sync_path_length()


## Generates circular cross-section [PackedVector2Array] based on [member diameter].
func _update_cross_section() -> void:
	if not is_instance_valid(csg_polygon):
		return

	var radius: float = diameter * 0.5
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(radial_segments)

	var step: float = TAU / float(radial_segments)
	for i: int in range(radial_segments):
		var angle: float = float(i) * step
		points[i] = Vector2(cos(angle) * radius, sin(angle) * radius)

	csg_polygon.polygon = points


## Assigns base shared [ShaderMaterial] and updates per-instance shader uniforms.
func _update_material() -> void:
	if not is_instance_valid(csg_polygon):
		return

	var target_mat: ShaderMaterial = (
		MAT_TRANSPARENT if style == TubeStyle.PLASTIC_TRANSPARENT else MAT_OPAQUE
	)
	if csg_polygon.material != target_mat:
		csg_polygon.material = target_mat

	csg_polygon.set_instance_shader_parameter(PARAM_ALBEDO, albedo_color)
	csg_polygon.set_instance_shader_parameter(PARAM_METALLIC, metallic)
	csg_polygon.set_instance_shader_parameter(PARAM_ROUGHNESS, roughness)
	csg_polygon.set_instance_shader_parameter(PARAM_FRESNEL, fresnel_power)

	if style == TubeStyle.PLASTIC_TRANSPARENT:
		csg_polygon.set_instance_shader_parameter(PARAM_ALPHA, alpha)
		csg_polygon.set_instance_shader_parameter(PARAM_LIQUID_COLOR, liquid_color)
		csg_polygon.set_instance_shader_parameter(PARAM_LIQUID_FILL, liquid_fill)
		csg_polygon.set_instance_shader_parameter(PARAM_FLOW_SPEED, flow_speed)
		csg_polygon.set_instance_shader_parameter(PARAM_WALL_RIM, wall_rim)
		_sync_path_length()


## Pushes baked spline length to the shader so [member liquid_fill] maps 0..1 accurately.
func _sync_path_length() -> void:
	if not is_instance_valid(csg_polygon) or curve == null:
		return
	if style == TubeStyle.PLASTIC_TRANSPARENT:
		var baked_len: float = maxf(0.01, curve.get_baked_length())
		csg_polygon.set_instance_shader_parameter(PARAM_PATH_LENGTH, baked_len)


## Updates shader path length when manual [Curve3D] control points are edited.
func _on_curve_changed() -> void:
	_sync_path_length()
