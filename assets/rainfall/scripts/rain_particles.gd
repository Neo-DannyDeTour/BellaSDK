@tool
extends GPUParticles3D

# --- INSTRUCTIONS ---
# 1. Assign this script to a GPUParticles3D node.
# 2. Assign textures for 'droplet_shape_tex' and 'droplet_normal_tex'.
#    (If left empty, procedural approximations will be generated, but are less detailed).
# 3. Adjust particle physics (Amount, Lifetime, Velocity, Emission Shape) natively in the Inspector!

# --- EXPORTS ---
@export_group("Rain Textures")
# The alpha mask of the droplet (capsule or stretched drop shape)
@export var droplet_shape_tex: Texture2D:
	set(value):
		droplet_shape_tex = value
		_apply_textures()

# The normal map of the droplet (curved surface data)
@export var droplet_normal_tex: Texture2D:
	set(value):
		droplet_normal_tex = value
		_apply_textures()

@export_group("Rain Material")
@export_color_no_alpha var rain_tint: Color = Color(0.9, 0.95, 1.0):
	set(value):
		rain_tint = value
		_update_shader_params()

@export_range(0.0, 1.0, 0.01) var base_alpha: float = 0.5:
	set(value):
		base_alpha = value
		_update_shader_params()

# Determines how heavily the background bends. 
# NOTE: Use NEGATIVE values to pull from the "opposite" direction (inverting the image like a real water drop).
@export_range(-2.0, 2.0, 0.01) var refraction_strength: float = 0.35:
	set(value):
		refraction_strength = value
		_update_shader_params()

# Adds simple specular reflections for liquid sheen.
@export_range(0.0, 1.0, 0.01) var surface_shine: float = 0.6:
	set(value):
		surface_shine = value
		_update_shader_params()

# Controls how muddy/distorted the background inside the drop gets.
@export_range(0.0, 5.0, 0.1) var background_blur: float = 1.5:
	set(value):
		background_blur = value
		_update_shader_params()
		
@export var droplet_size: Vector2 = Vector2(0.5, 0.5):
	set(value):
		droplet_size = value
		_update_draw_mesh()

# --- INTERNAL RESOURCES ---
var _proc_mat: ParticleProcessMaterial
var _draw_mesh: QuadMesh
var _shader_mat: ShaderMaterial

const RAIN_SHADER_CODE = """
shader_type spatial;
// Removed depth_draw_never so it sorts properly, changed to unshaded for speed
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D albedo_tex : hint_default_black, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;

uniform vec4 tint_color : source_color = vec4(0.9, 0.95, 1.0, 0.5);
uniform float shine_strength = 0.6;

void vertex() {
    // Keep your billboard logic exactly as it was
    mat4 modified_model_view = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
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

    // --- FAKED REFRACTION (No Screen Reading) ---
    // Instead of reading the screen, we just tint the drop slightly based on the normal
    // This gives the illusion of volume without the massive cost.
    vec3 base_color = tint_color.rgb * (1.0 - abs(n_tex.z) * 0.3);

    // --- ENHANCED SHINE ---
    // We use a fixed light direction (representing moonlight or ambient sky light)
    vec3 light_dir = normalize(vec3(0.1, 0.8, 0.4));
    float spec = max(dot(n_tex, light_dir), 0.0);
    // Tighten the specular highlight
    vec3 shine = pow(spec, 12.0) * shine_strength * vec3(1.0);
    
    ALBEDO = base_color + shine;
    ALPHA = final_mask;
}
"""

func _ready() -> void:
	_init_system()
	_apply_settings()
	
	if not Engine.is_editor_hint():
		call_deferred("_setup_auto_volume")

func _init_system() -> void:
	# 1. Mesh setup
	if draw_pass_1 == null or not (draw_pass_1 is QuadMesh):
		_draw_mesh = QuadMesh.new()
		draw_pass_1 = _draw_mesh
	else:
		_draw_mesh = draw_pass_1
		
	# 2. Material setup
	if _shader_mat == null:
		_shader_mat = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = RAIN_SHADER_CODE
		_shader_mat.shader = shader
		_draw_mesh.material = _shader_mat
	
	# 3. Process setup - Only overwrite if it doesn't exist so we don't ruin user tweaks
	if process_material == null or not (process_material is ParticleProcessMaterial):
		_proc_mat = ParticleProcessMaterial.new()
		process_material = _proc_mat
		
		# Inject sensible default physics so it works out of the box
		_proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		_proc_mat.emission_box_extents = Vector3(10.0, 5.0, 10.0)
		_proc_mat.direction = Vector3.DOWN
		_proc_mat.spread = 2.0
		_proc_mat.gravity = Vector3(0, -9.8, 0)
		_proc_mat.initial_velocity_min = 35.0
		_proc_mat.initial_velocity_max = 45.0
		_proc_mat.particle_flag_align_y = false
	else:
		_proc_mat = process_material

func _apply_settings() -> void:
	# Basic GPU particle flags that optimize rendering
	explosiveness = 0.0
	interpolate = true
	draw_passes = 1
	collision_base_size = 0.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail_enabled = false
	
	# Pre-simulate the rain based on user's native lifetime setting
	preprocess = lifetime
	
	_update_draw_mesh()
	_apply_textures()
	_update_shader_params()

func _update_draw_mesh() -> void:
	if _draw_mesh:
		_draw_mesh.size = droplet_size

func _apply_textures() -> void:
	if _shader_mat == null: return
	
	if droplet_shape_tex:
		_shader_mat.set_shader_parameter("albedo_tex", droplet_shape_tex)
	else:
		# Fallback placeholder shape
		_shader_mat.set_shader_parameter("albedo_tex", _generate_fallback_albedo())

	if droplet_normal_tex:
		_shader_mat.set_shader_parameter("normal_tex", droplet_normal_tex)
	else:
		# Fallback placeholder normal
		_shader_mat.set_shader_parameter("normal_tex", _generate_fallback_normal())

func _update_shader_params() -> void:
	if _shader_mat == null: return
	
	var final_tint := rain_tint
	final_tint.a = base_alpha
	_shader_mat.set_shader_parameter("tint_color", final_tint)
	_shader_mat.set_shader_parameter("refraction_strength", refraction_strength)
	_shader_mat.set_shader_parameter("shine_strength", surface_shine)
	_shader_mat.set_shader_parameter("blur_amount", background_blur)

# --- Fallback Texture Generation (for testing without external assets) ---

func _generate_fallback_albedo() -> Texture2D:
	var image := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var u := (float(x) / float(image.get_width() - 1)) * 2.0 - 1.0
			var y_stretch := (float(y) / float(image.get_height() - 1)) * 2.0 - 1.0
			var dist := sqrt(u*u + (y_stretch*y_stretch)*0.01)
			var val := 1.0 - smoothstep(0.7, 0.9, dist)
			image.set_pixel(x, y, Color(val, val, val, val))
	return ImageTexture.create_from_image(image)

func _generate_fallback_normal() -> Texture2D:
	var image := Image.create(32, 128, false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var u := float(x) / float(image.get_width() - 1)
			var y_pct := float(y) / float(image.get_height() - 1)
			var nx := (u * 2.0 - 1.0) * 0.8
			var ny := (y_pct * 2.0 - 1.0) * 0.1 
			var nz := sqrt(1.0 - nx*nx - ny*ny)
			image.set_pixel(x, y, Color(nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5, 1.0))
	return ImageTexture.create_from_image(image)

# --- AUTOMATIC PLAYER DETECTION ---

func _setup_auto_volume() -> void:
	var rain_area := Area3D.new()
	# Collision Layer 0 (detects nothing by default), Mask 1 (detects Player)
	rain_area.collision_layer = 0 
	rain_area.collision_mask = 1
	add_child(rain_area)
	
	var shape_node := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	
	var width: float = 20.0
	var depth: float = 20.0
	var height: float = 30.0
	
	# Calculate the size of the rainstorm based on your Particle Physics settings!
	if process_material is ParticleProcessMaterial:
		if process_material.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_BOX:
			width = process_material.emission_box_extents.x * 2.0
			depth = process_material.emission_box_extents.z * 2.0
			
		# Estimate how far the particles fall: (Velocity * Lifetime)
		var fall_speed: float = (process_material.initial_velocity_min + process_material.initial_velocity_max) / 2.0
		height = fall_speed * lifetime

	box_shape.size = Vector3(width, height, depth)
	shape_node.shape = box_shape
	
	# Shift the box down so it covers the space *beneath* the emitter
	shape_node.position.y = - (height / 2.0)
	
	rain_area.add_child(shape_node)
	
	# Wire up the detection internally
	rain_area.body_entered.connect(_on_body_entered)
	rain_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("enter_rain_volume"):
		body.enter_rain_volume()

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("exit_rain_volume"):
		body.exit_rain_volume()
