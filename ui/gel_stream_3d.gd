@tool
## Procedural 3D gel particle stream with dynamic teardrop trail geometry.
class_name GelStream3D
extends GPUParticles3D

## Shader resource rendering the gel droplet surface.
const GEL_SHADER: Shader = preload("res://ui/gel.gdshader")

## Shader uniform key for gel surface tint color.
const PARAM_GEL_COLOR: StringName = &"gel_color"

## Base albedo and alpha color of the gel stream.
@export var gel_color: Color = Color(0.0, 0.5, 1.0, 0.8):
	set(value):
		gel_color = value
		_update_visuals()

## Stream cohesion factor blending between dispersed droplets and a unified stream.
@export_range(0.0, 1.0) var stream_unity: float = 0.0:
	set(value):
		stream_unity = value
		_update_visuals()

## Radius scale multiplier for individual gel droplets.
@export var drop_scale: float = 1.0:
	set(value):
		drop_scale = maxf(0.01, value)
		_update_visuals()

## Base vertical trail length for each droplet.
@export var drop_length: float = 0.1:
	set(value):
		drop_length = maxf(0.01, value)
		_update_visuals()

## Cached particle process material controlling velocity and spread.
var _process_mat: ParticleProcessMaterial

## Cached shader material applied to the trail mesh.
var _draw_mat: ShaderMaterial


## Initializes particle materials and applies initial visual parameters.
func _ready() -> void:
	_initialize_materials()
	_update_visuals()


## Ensures process material, trail mesh, and draw shader material are allocated.
func _initialize_materials() -> void:
	if process_material is ParticleProcessMaterial:
		_process_mat = process_material as ParticleProcessMaterial
	else:
		_process_mat = ParticleProcessMaterial.new()
		process_material = _process_mat

	var current_mesh: TubeTrailMesh = draw_pass_1 if draw_pass_1 is TubeTrailMesh else null
	if not current_mesh:
		current_mesh = TubeTrailMesh.new()
		current_mesh.radial_steps = 4
		current_mesh.sections = 5

		# Remove the disjointed flat caps entirely
		current_mesh.cap_top = false
		current_mesh.cap_bottom = false

		# Create a teardrop curve profile (0.0 is top of drop, 1.0 is the tail)
		var shape_curve: Curve = Curve.new()
		shape_curve.add_point(Vector2(0.0, 0.0))
		shape_curve.add_point(Vector2(0.2, 1.0))
		shape_curve.add_point(Vector2(1.0, 0.0))
		current_mesh.curve = shape_curve

		draw_pass_1 = current_mesh

	if current_mesh.material is ShaderMaterial:
		_draw_mat = current_mesh.material as ShaderMaterial
	else:
		_draw_mat = ShaderMaterial.new()
		_draw_mat.shader = GEL_SHADER
		current_mesh.material = _draw_mat

	trail_enabled = true


## Synchronizes shader uniforms, trail dimensions, and emission settings.
func _update_visuals() -> void:
	if (
		not is_inside_tree()
		or not is_instance_valid(_draw_mat)
		or not is_instance_valid(_process_mat)
	):
		return

	_draw_mat.set_shader_parameter(PARAM_GEL_COLOR, gel_color)

	var current_mesh: TubeTrailMesh = draw_pass_1 if draw_pass_1 is TubeTrailMesh else null
	if current_mesh:
		current_mesh.radius = 0.04 * drop_scale

	# Trail lifetime dictates the vertical length of the drop
	var min_trail: float = drop_length * 0.5
	var max_trail: float = drop_length * 2.0
	trail_lifetime = lerpf(min_trail, max_trail, stream_unity)

	var min_amt: int = 15
	var max_amt: int = 60
	amount = int(lerpf(float(min_amt), float(max_amt), stream_unity))

	_process_mat.direction = Vector3.DOWN

	var min_spread: float = 10.0
	var max_spread: float = 1.0
	_process_mat.spread = lerpf(min_spread, max_spread, stream_unity)

	_process_mat.initial_velocity_min = 3.0

	var min_vel: float = 6.0
	var max_vel: float = 3.0
	_process_mat.initial_velocity_max = lerpf(min_vel, max_vel, stream_unity)
