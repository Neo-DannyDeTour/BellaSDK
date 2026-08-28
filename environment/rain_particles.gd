@tool
## Particle manager driving spatial rain simulation,
## unshaded billboarding, and player volume detection.
class_name RainParticles
extends GPUParticles3D

## Shader code for rendering unshaded faux-refractive rain droplets.
const RAIN_SHADER_CODE: String = """
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D albedo_tex : hint_default_black, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;

uniform vec4 tint_color : source_color = vec4(0.9, 0.95, 1.0, 0.5);
uniform float shine_strength = 0.6;

void vertex() {
	mat4 modified_model_view = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]
	);
	modified_model_view = modified_model_view * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
	MODELVIEW_MATRIX = modified_model_view;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec4 base = texture(albedo_tex, UV);
	vec3 n_tex = texture(normal_tex, UV).rgb * 2.0 - 1.0;

	vec4 pColor = COLOR;
	float final_mask = base.r * tint_color.a * pColor.a;

	if (final_mask < 0.05) {
		discard;
	}

	vec3 base_color = tint_color.rgb * (1.0 - abs(n_tex.z) * 0.3);
	vec3 light_dir = normalize(vec3(0.1, 0.8, 0.4));
	float spec = max(dot(n_tex, light_dir), 0.0);
	vec3 shine = pow(spec, 12.0) * shine_strength * vec3(1.0);

	ALBEDO = base_color + shine;
	ALPHA = final_mask;
}
"""

## Collision mask layer integer assigned to the player character detection volume.
static var player_collision_mask: int = 2

@export_group("Rain Textures")
## Texture providing the alpha droplet silhouette mask.
@export var droplet_shape_tex: Texture2D:
	set(value):
		droplet_shape_tex = value
		_apply_textures()

## Texture providing surface normal data for specular lighting sheen.
@export var droplet_normal_tex: Texture2D:
	set(value):
		droplet_normal_tex = value
		_apply_textures()

@export_group("Rain Material")
## Base albedo color applied to the falling rain droplets.
@export_color_no_alpha var rain_tint: Color = Color(0.9, 0.95, 1.0):
	set(value):
		rain_tint = value
		_update_shader_params()

## Base opacity scalar for the particle material.
@export_range(0.0, 1.0, 0.01) var base_alpha: float = 0.5:
	set(value):
		base_alpha = value
		_update_shader_params()

## Intensity scalar of the pseudo-refraction color shift.
@export_range(-2.0, 2.0, 0.01) var refraction_strength: float = 0.35:
	set(value):
		refraction_strength = value
		_update_shader_params()

## Multiplier for specular highlight reflection sheen.
@export_range(0.0, 1.0, 0.01) var surface_shine: float = 0.6:
	set(value):
		surface_shine = value
		_update_shader_params()

## Background blur factor uniform passed into the droplet shader.
@export_range(0.0, 5.0, 0.1) var background_blur: float = 1.5:
	set(value):
		background_blur = value
		_update_shader_params()

## Dimensions of the individual QuadMesh particle draw instance.
@export var droplet_size: Vector2 = Vector2(0.5, 0.5):
	set(value):
		droplet_size = value
		_update_draw_mesh()

## Cached internal process material driving particle physics.
var _proc_mat: ParticleProcessMaterial

## Cached QuadMesh instance used for particle rasterization.
var _draw_mesh: QuadMesh

## Material instance executing the unshaded rain shader.
var _shader_mat: ShaderMaterial


## Lifecycle method configuring mesh references, materials, and auto volume detectors.
func _ready() -> void:
	print("RainParticles: Initializing rain emitter system.")
	_init_system()
	_apply_settings()

	if not Engine.is_editor_hint():
		call_deferred("_setup_auto_volume")


## Constructs QuadMesh and initializes fallback particle materials.
func _init_system() -> void:
	if draw_pass_1 == null or not (draw_pass_1 is QuadMesh):
		_draw_mesh = QuadMesh.new()
		draw_pass_1 = _draw_mesh
	else:
		_draw_mesh = draw_pass_1 as QuadMesh

	if _shader_mat == null:
		_shader_mat = ShaderMaterial.new()
		var shader: Shader = Shader.new()
		shader.code = RAIN_SHADER_CODE
		_shader_mat.shader = shader
		_draw_mesh.material = _shader_mat

	if process_material == null or not (process_material is ParticleProcessMaterial):
		_proc_mat = ParticleProcessMaterial.new()
		process_material = _proc_mat

		_proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		_proc_mat.emission_box_extents = Vector3(10.0, 5.0, 10.0)
		_proc_mat.direction = Vector3.DOWN
		_proc_mat.spread = 2.0
		_proc_mat.gravity = Vector3(0.0, -9.8, 0.0)
		_proc_mat.initial_velocity_min = 35.0
		_proc_mat.initial_velocity_max = 45.0
		_proc_mat.particle_flag_align_y = false
	else:
		_proc_mat = process_material as ParticleProcessMaterial


## Configures default particle flags, preprocess states, and updates uniforms.
func _apply_settings() -> void:
	explosiveness = 0.0
	interpolate = true
	draw_passes = 1
	collision_base_size = 0.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	preprocess = lifetime

	_update_draw_mesh()
	_apply_textures()
	_update_shader_params()


## Sets size dimensions on the quad mesh draw pass.
func _update_draw_mesh() -> void:
	if _draw_mesh:
		_draw_mesh.size = droplet_size


## Assigns active droplet textures or builds procedural fallbacks.
func _apply_textures() -> void:
	if _shader_mat == null:
		return

	if droplet_shape_tex:
		_shader_mat.set_shader_parameter(&"albedo_tex", droplet_shape_tex)
	else:
		_shader_mat.set_shader_parameter(&"albedo_tex", _generate_fallback_albedo())

	if droplet_normal_tex:
		_shader_mat.set_shader_parameter(&"normal_tex", droplet_normal_tex)
	else:
		_shader_mat.set_shader_parameter(&"normal_tex", _generate_fallback_normal())


## Propagates material export values to shader parameters.
func _update_shader_params() -> void:
	if _shader_mat == null:
		return

	var final_tint: Color = rain_tint
	final_tint.a = base_alpha
	_shader_mat.set_shader_parameter(&"tint_color", final_tint)
	_shader_mat.set_shader_parameter(&"refraction_strength", refraction_strength)
	_shader_mat.set_shader_parameter(&"shine_strength", surface_shine)
	_shader_mat.set_shader_parameter(&"blur_amount", background_blur)


## Creates a fallback placeholder monochrome droplet shape.
## [return] The generated placeholder [Texture2D].
func _generate_fallback_albedo() -> Texture2D:
	var image: Image = Image.create(32, 128, false, Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var u: float = (float(x) / float(image.get_width() - 1)) * 2.0 - 1.0
			var y_stretch: float = (float(y) / float(image.get_height() - 1)) * 2.0 - 1.0
			var dist: float = sqrt(u * u + (y_stretch * y_stretch) * 0.01)
			var val: float = 1.0 - smoothstep(0.7, 0.9, dist)
			image.set_pixel(x, y, Color(val, val, val, val))
	return ImageTexture.create_from_image(image)


## Creates a fallback placeholder normal map with rounded curvature.
## [return] The generated normal map [Texture2D].
func _generate_fallback_normal() -> Texture2D:
	var image: Image = Image.create(32, 128, false, Image.FORMAT_RGBA8)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			var u: float = float(x) / float(image.get_width() - 1)
			var y_pct: float = float(y) / float(image.get_height() - 1)
			var nx: float = (u * 2.0 - 1.0) * 0.8
			var ny: float = (y_pct * 2.0 - 1.0) * 0.1
			var nz: float = sqrt(1.0 - nx * nx - ny * ny)
			image.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5, 1.0))
	return ImageTexture.create_from_image(image)


## Builds an Area3D trigger matching emission bounds to detect player entrance.
func _setup_auto_volume() -> void:
	print("RainParticles: Generating automatic trigger volume.")
	var rain_area: Area3D = Area3D.new()
	rain_area.collision_layer = 0
	rain_area.collision_mask = player_collision_mask
	add_child(rain_area)

	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()

	var width: float = 20.0
	var depth: float = 20.0
	var height: float = 30.0

	if process_material is ParticleProcessMaterial:
		var pm: ParticleProcessMaterial = process_material as ParticleProcessMaterial
		if pm.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			width = pm.emission_box_extents.x * 2.0
			depth = pm.emission_box_extents.z * 2.0

		var fall_speed: float = (pm.initial_velocity_min + pm.initial_velocity_max) / 2.0
		height = fall_speed * lifetime

	box_shape.size = Vector3(width, height, depth)
	shape_node.shape = box_shape
	shape_node.position.y = -(height / 2.0)

	rain_area.add_child(shape_node)
	rain_area.body_entered.connect(_on_body_entered)
	rain_area.body_exited.connect(_on_body_exited)


## Notifies the player controller and triggers screen rain droplets on enter.
## [param body] The [Node3D] entering the rain trigger.
func _on_body_entered(body: Node3D) -> void:
	print("RainParticles: Body entered rain zone -> ", body.name)
	if body is Player or body.is_in_group(&"player"):
		Events.rain_vfx_toggled.emit(0.75)
		if body.has_method("enter_rain_volume"):
			body.enter_rain_volume()


## Notifies the player controller and clears screen rain droplets on exit.
## [param body] The [Node3D] leaving the rain trigger.
func _on_body_exited(body: Node3D) -> void:
	print("RainParticles: Body exited rain zone -> ", body.name)
	if body is Player or body.is_in_group(&"player"):
		Events.rain_vfx_toggled.emit(0.0)
		if body.has_method("exit_rain_volume"):
			body.exit_rain_volume()
