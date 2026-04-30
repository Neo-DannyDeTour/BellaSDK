extends Node
# SmokeManager.gd (Autoload)

var active_holes: Array[Dictionary] = []
var current_player_pos: Vector3 = Vector3.ZERO

# GPU Variables
var rd: RenderingDevice
var shader: RID
var pipeline: RID
var texture_rid: RID

# We make the Buffer and Uniforms global so we don't delete them mid-frame
var buffer_rid: RID
var uniform_set: RID

# Pre-allocate memory for up to 50 simultaneous bullet holes (50 holes * 32 bytes)
const MAX_HOLES = 50
const BUFFER_SIZE = MAX_HOLES * 32

# Assign this from your main level script so the compute shader knows exactly where the fog is!
var active_fog_volume: FogVolume 

func _ready() -> void:
	rd = RenderingServer.get_rendering_device()
	_initialize_gpu()

func _initialize_gpu() -> void:
	var shader_file: RDShaderFile = load("res://scripts/smoke_simulation/smoke_compute.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(shader)
	
	# 1. Create 3D Texture (Make sure this matches the shader's rgba8 requirement!)
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.width = 64
	fmt.height = 64
	fmt.depth = 64
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	var view := RDTextureView.new()
	texture_rid = rd.texture_create(fmt, view)
	
	# 2. Create a persistent Storage Buffer filled with blank data
	var empty_bytes := PackedByteArray()
	empty_bytes.resize(BUFFER_SIZE)
	buffer_rid = rd.storage_buffer_create(BUFFER_SIZE, empty_bytes)
	
	# 3. Create Uniforms ONCE
	var tex_uniform := RDUniform.new()
	tex_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	tex_uniform.binding = 0
	tex_uniform.add_id(texture_rid)
	
	var buf_uniform := RDUniform.new()
	buf_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	buf_uniform.binding = 1
	buf_uniform.add_id(buffer_rid)
	
	uniform_set = rd.uniform_set_create([tex_uniform, buf_uniform], shader, 0)

func update_player_position(pos: Vector3) -> void:
	current_player_pos = pos

func add_bullet_hole(start: Vector3, dir: Vector3, length: float, radius: float = 1.0, intensity: float = 1.0) -> void:
	active_holes.append({
		"start": start,
		"end": start + (dir * length),
		"radius": radius,
		"intensity": intensity,
		"time_alive": 0.0 
	})

func _process(delta: float) -> void:
	# 1. Update and cull old bullet holes
	for i in range(active_holes.size() - 1, -1, -1):
		active_holes[i].time_alive += delta
		if active_holes[i].time_alive > 2.0:
			active_holes.remove_at(i)
			
	_dispatch_to_compute_shader(delta)
	
func _dispatch_to_compute_shader(delta: float) -> void:
	if not rd or not pipeline: return
	
	# --- DYNAMIC FOG BOUNDS ---
	# We dynamically calculate the bounds so it always aligns perfectly with your FogVolume node
	var grid_pos := Vector3.ZERO
	var grid_size := 20.0
	if active_fog_volume:
		grid_size = active_fog_volume.size.x
		# Fog volumes scale from their center. This calculates the bottom-left corner.
		grid_pos = active_fog_volume.global_position - (active_fog_volume.size / 2.0)

	# --- UPDATE BUFFER SAFELY ---
	var hole_data := PackedFloat32Array()
	var holes_to_process: int = min(active_holes.size(), MAX_HOLES)
	for i in range(holes_to_process):
		var hole := active_holes[i]
		hole_data.append(hole.start.x)
		hole_data.append(hole.start.y)
		hole_data.append(hole.start.z)
		hole_data.append(hole.radius)
		hole_data.append(hole.end.x)
		hole_data.append(hole.end.y)
		hole_data.append(hole.end.z)
		hole_data.append(hole.intensity)
		
	var hole_bytes := hole_data.to_byte_array()
	if hole_bytes.size() > 0:
		# Instead of recreating the buffer, we just overwrite the existing memory. Very fast.
		rd.buffer_update(buffer_rid, 0, hole_bytes.size(), hole_bytes)
	
	# --- PACK PUSH CONSTANTS PERFECTLY ---
	# GLSL std430 alignment requires vec3s to align to 16 bytes. 
	# This 12-float array exactly matches the shader's memory expectation (48 bytes total).
	var push_constants := PackedFloat32Array([
		current_player_pos.x, current_player_pos.y, current_player_pos.z, 
		float(holes_to_process),
		grid_pos.x, grid_pos.y, grid_pos.z, 
		grid_size,
		delta, 0.0, 0.0, 0.0 # <--- The Delta Time and 3 padding floats to lock the alignment
	]).to_byte_array()
	
	# --- DISPATCH TO GPU ---
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list, 8, 8, 8) # Warning gone!
	rd.compute_list_end()
