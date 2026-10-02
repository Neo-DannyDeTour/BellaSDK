@tool
## Procedural falling particle that melts upon hitting floor geometry.
class_name Particle
extends Node3D

## Spawn grace period duration in seconds preventing instant self-collision.
const GRACE_PERIOD: float = 0.05

@export_group("Editor Preview")
## Preview floor elevation coordinate for editor simulation.
@export var editor_floor_y: float = 0.0

## Vertical fall speed in meters per second.
var fall_speed: float = 5.0

## Shrink rate in units per second when melting on floor.
var melt_speed: float = 0.5

## Initial spherical radius of particle on spawn.
var initial_radius: float = 0.2

## Current dynamic radius of particle while active.
var current_radius: float = 0.2

## Flag indicating whether particle is currently melting.
var is_melting: bool = false

## Flag indicating whether particle is active in scene.
var is_active: bool = false

## Accumulated alive time in seconds since activation.
var alive_time: float = 0.0

## Cached shader material reference assigned to mesh instance.
var _shader_material: ShaderMaterial

## Direct reference to attached [MeshInstance3D] node.
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D as MeshInstance3D

## Direct reference to attached floor detection [Area3D].
@onready var area_3d: Area3D = $Area3D as Area3D


## Initializes collision masks and sets top level coordinates.
func _ready() -> void:
	print("Particle: Initializing particle instance.")
	current_radius = initial_radius
	set_as_top_level(true)

	if area_3d != null:
		area_3d.collision_layer = CollisionLayers.MASK_NONE
		area_3d.collision_mask = CollisionLayers.MASK_ENVIRONMENT

	if not Engine.is_editor_hint():
		if area_3d != null:
			area_3d.body_entered.connect(_on_area_body_entered)


## Processes falling translation and floor melting.
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
		global_position.y -= shrink_amount

		if current_radius <= 0.0:
			deactivate()
	else:
		global_position += Vector3.DOWN * fall_speed * delta


## Restores initial state and makes particle visible.
func reset_particle() -> void:
	#print("Particle: Resetting particle for spawn.")
	is_active = true
	is_melting = false
	current_radius = initial_radius
	alive_time = 0.0
	visible = true
	force_update_transform()


## Deactivates particle and teleports out of view.
func deactivate() -> void:
	if not Engine.is_editor_hint():
		print("Particle: Deactivating particle.")
	is_active = false
	is_melting = false
	visible = false
	global_position = Vector3(0.0, -1000.0, 0.0)


## Resolves and caches active [ShaderMaterial] instance.
func _get_shader_material() -> ShaderMaterial:
	if _shader_material != null:
		return _shader_material

	if mesh_instance_3d == null:
		mesh_instance_3d = (
			NodeQuery.find_first_child_of_type(self, MeshInstance3D) as MeshInstance3D
		)

	if mesh_instance_3d != null:
		_shader_material = mesh_instance_3d.get_active_material(0) as ShaderMaterial

	return _shader_material


## Assigns particle noise texture to shader uniform.
func set_particle_image(image: ImageTexture) -> void:
	#print("Particle: Assigning particle image texture.")
	var mat: ShaderMaterial = _get_shader_material()
	if mat != null:
		mat.set_shader_parameter(&"particles", image)


## Updates particle count uniform in shader.
func update_n_particles(n: int) -> void:
	#print("Particle: Updating particle count uniform to: ", n)
	var mat: ShaderMaterial = _get_shader_material()
	if mat != null:
		mat.set_shader_parameter(&"n_particles", n)


## Updates color, opacity, and roughness parameters in shader.
func update_shader_params(
	p_color: Color, p_opacity: float, p_roughness: float, p_metallic: float, p_k_blend: float
) -> void:
	print("Particle: Updating shader visual parameters.")
	var mat: ShaderMaterial = _get_shader_material()
	if mat != null:
		mat.set_shader_parameter(&"color", p_color)
		mat.set_shader_parameter(&"opacity", p_opacity)
		mat.set_shader_parameter(&"roughness", p_roughness)
		mat.set_shader_parameter(&"metallic", p_metallic)
		mat.set_shader_parameter(&"k", p_k_blend)


## Detects floor contact and triggers melting phase.
func _on_area_body_entered(_body: Node3D) -> void:
	if not is_active or is_melting or alive_time < GRACE_PERIOD:
		return

	print("Particle: Floor collision confirmed. Starting melt.")
	is_melting = true
