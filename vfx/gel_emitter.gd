@tool
extends Node3D

const MAX_PARTICLES: int = 50

@export_group("Shader & Particle Parameters")
@export var p_color: Color = Color(0.0, 0.5, 1.0, 1.0):
	set(value):
		p_color = value
		if is_inside_tree():
			_update_all_particles()

@export_range(0.0, 1.0) var p_opacity: float = 1.0:
	set(value):
		p_opacity = value
		if is_inside_tree():
			_update_all_particles()

@export var p_size: float = 0.2:
	set(value):
		p_size = value
		if is_inside_tree():
			_update_all_particles()

@export var p_fall_speed: float = 5.0:
	set(value):
		p_fall_speed = value
		if is_inside_tree():
			_update_all_particles()

@export_range(0.0, 1.0) var p_roughness: float = 0.1:
	set(value):
		p_roughness = value
		if is_inside_tree():
			_update_all_particles()

@export_range(0.0, 1.0) var p_metallic: float = 0.6:
	set(value):
		p_metallic = value
		if is_inside_tree():
			_update_all_particles()

@export var p_blend_k: float = 0.3:
	set(value):
		p_blend_k = value
		if is_inside_tree():
			_update_all_particles()

var subscene_instance: PackedScene = preload("res://vfx/particle.tscn")
var particle_pool: Array[Particle] = []
var first_decal: Node3D = null

var data_texture: Image = Image.create(1024, 1, false, Image.FORMAT_RGBAF)
var tc: ImageTexture 
var particle_data: PackedFloat32Array = PackedFloat32Array()

var splat_pos: Image = Image.create(1024, 1, false, Image.FORMAT_RGBAF)
var splat_tex: ImageTexture 
var splat_count: int = 0

var time: float = 0.0
var spawn_accumulator: float = 0.0
var current_spawn_wait: float = 0.0
var emitter: GPUParticles3D


func _ready() -> void:
	if Engine.is_editor_hint():
		for child: Node in get_children():
			if child is Particle:
				child.queue_free()

	tc = ImageTexture.create_from_image(data_texture)
	splat_tex = ImageTexture.create_from_image(splat_pos)
	
	particle_data.resize(1024 * 4) 

	var emitter_node: Node = get_node_or_null("%splat_emitter")
	if emitter_node is GPUParticles3D:
		emitter = emitter_node as GPUParticles3D

	# Defer initialization to ensure the Inspector and Scene Tree 
	# are completely synced before injecting 50 child nodes.
	call_deferred("_initialize_pool")
	current_spawn_wait = randf_range(0.0, 0.1)


func _initialize_pool() -> void:
	particle_pool.clear() 
	for i: int in range(MAX_PARTICLES):
		var p := subscene_instance.instantiate() as Particle
		if p != null:
			p.visible = false
			p.is_active = false
			add_child(p)
			particle_pool.append(p)
			_apply_params_to_particle(p)


func _update_all_particles() -> void:
	for p: Particle in particle_pool:
		if p != null:
			_apply_params_to_particle(p)


func _apply_params_to_particle(particle: Particle) -> void:
	particle.initial_radius = p_size
	particle.fall_speed = p_fall_speed
	
	if not particle.is_melting:
		particle.current_radius = p_size
		
	particle.update_shader_params(
		p_color, p_opacity, p_roughness, p_metallic, p_blend_k
	)


func _process(delta: float) -> void:
	# 60 FPS Safety Net: Instantly recovers the pool array if the Editor hot-reloads the script
	if Engine.is_editor_hint() and particle_pool.is_empty():
		_recover_pool_state()
		
	time += delta
	
	spawn_accumulator += delta
	if spawn_accumulator >= current_spawn_wait:
		spawn_accumulator = 0.0
		current_spawn_wait = randf_range(0.0, 0.05)
		_spawn_particle_from_pool()
		
	update_data_texture()


func _recover_pool_state() -> void:
	for child: Node in get_children():
		if child is Particle:
			particle_pool.append(child as Particle)


func _spawn_particle_from_pool() -> void:
	for p: Particle in particle_pool:
		if not p.is_active:
			p.global_position = global_position + Vector3(
				randf_range(-0.2, 0.2), 
				0.0, 
				randf_range(-0.2, 0.2)
			)
			p.reset_particle()
			break 


func spawn_splat(pos: Vector3) -> void:
	if first_decal != null and emitter != null:
		emitter.position = pos
		emitter.emitting = true


func spawn_decal(pos: Vector3) -> void:
	var dec_color := Color(pos.x, pos.y, pos.z, time)
	splat_pos.set_pixel(splat_count, 0, dec_color)
	splat_count += 1


func update_data_texture() -> void:
	if particle_pool.is_empty():
		return

	var active_count: int = 0
	particle_data.fill(0.0)
	
	for p: Particle in particle_pool:
		if not p.is_active:
			continue
			
		var pos: Vector3 = p.global_position
		var idx: int = active_count * 4
		
		particle_data[idx] = pos.x
		particle_data[idx + 1] = pos.y
		particle_data[idx + 2] = pos.z
		particle_data[idx + 3] = p.current_radius
		
		active_count += 1
		
	if active_count > 0:
		var byte_data := particle_data.to_byte_array()
		data_texture.set_data(1024, 1, false, Image.FORMAT_RGBAF, byte_data)
		tc.update(data_texture)

	if first_decal != null:
		splat_tex.update(splat_pos)
		if first_decal.has_method(&"set_n_decals"):
			first_decal.call(&"set_n_decals", splat_count)
		if first_decal.has_method(&"set_pos_tex"):
			first_decal.call(&"set_pos_tex", splat_tex)
			
	if particle_pool.size() > 0:
		var ref_particle := particle_pool[0]
		if ref_particle != null:
			ref_particle.update_n_particles(active_count)
			ref_particle.set_particle_image(tc)
