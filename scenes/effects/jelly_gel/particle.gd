@tool
class_name Particle
extends Node3D

const GRACE_PERIOD: float = 0.05

@export_group("Editor Preview")
@export var editor_floor_y: float = 0.0

var fall_speed: float = 5.0
var melt_speed: float = 0.5
var initial_radius: float = 0.2
var current_radius: float = 0.2
var is_melting: bool = false
var is_active: bool = false
# Tracks how long the particle has been alive to prevent instant self-collision
var alive_time: float = 0.0

var _shader_material: ShaderMaterial

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D as MeshInstance3D
@onready var area_3d: Area3D = $Area3D as Area3D


func _ready() -> void:
	current_radius = initial_radius
	set_as_top_level(true)
	
	if area_3d != null:
		# Layer 0: The particle exists on no layer
		area_3d.collision_layer = 0
		
		# Mask 1: The particle ONLY scans the Environment layer
		area_3d.collision_mask = 1
		
	if not Engine.is_editor_hint():
		if area_3d != null:
			area_3d.body_entered.connect(_on_area_body_entered)


func _process(delta: float) -> void:
	if not is_active:
		return
		
	alive_time += delta

	if Engine.is_editor_hint() and not is_melting:
		if global_position.y <= editor_floor_y:
			is_melting = true

	if is_melting:
		var shrink_amount: float = melt_speed * delta
		current_radius -= shrink_amount
		
		# Visually sink the particle to keep its bottom flush with the floor
		global_position.y -= shrink_amount
		
		if current_radius <= 0.0:
			deactivate()
	else:
		# Use global_position to respect top_level independence
		global_position += Vector3.DOWN * fall_speed * delta


func reset_particle() -> void:
	is_active = true
	is_melting = false
	current_radius = initial_radius
	alive_time = 0.0
	visible = true
	
	force_update_transform()


func deactivate() -> void:
	is_active = false
	is_melting = false
	visible = false
	
	# Teleport to the void to save physics calculations
	global_position = Vector3(0.0, -1000.0, 0.0)


func _get_shader_material() -> ShaderMaterial:
	if _shader_material != null:
		return _shader_material
		
	# Fallback if called before _ready() assigns the @onready variable
	if mesh_instance_3d == null:
		mesh_instance_3d = get_node_or_null("MeshInstance3D") as MeshInstance3D
		
	if mesh_instance_3d != null:
		_shader_material = mesh_instance_3d.get_active_material(0) as ShaderMaterial
		
	return _shader_material


func set_particle_image(image: ImageTexture) -> void:
	var mat: ShaderMaterial = _get_shader_material()
	if mat != null:
		mat.set_shader_parameter(&"particles", image)


func update_n_particles(n: int) -> void:
	var mat: ShaderMaterial = _get_shader_material()
	if mat != null:
		mat.set_shader_parameter(&"n_particles", n)


func update_shader_params(
	p_color: Color,
	p_opacity: float,
	p_roughness: float,
	p_metallic: float,
	p_k_blend: float
) -> void:
	var mat: ShaderMaterial = _get_shader_material()
	if mat != null:
		mat.set_shader_parameter(&"color", p_color)
		mat.set_shader_parameter(&"opacity", p_opacity)
		mat.set_shader_parameter(&"roughness", p_roughness)
		mat.set_shader_parameter(&"metallic", p_metallic)
		mat.set_shader_parameter(&"k", p_k_blend)


func _on_area_body_entered(_body: Node3D) -> void:
	# If the particle just spawned, ignore collisions during the grace period
	if not is_active or is_melting or alive_time < GRACE_PERIOD:
		return
		
	# Because we fixed the collision layers, ANY body detected here 
	# is mathematically guaranteed to be the floor. No string checks needed.
	is_melting = true
