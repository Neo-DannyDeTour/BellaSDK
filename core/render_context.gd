@tool
## Wrapper around [RenderingDevice] providing basic memory and allocation handling.
class_name RenderingContext extends Object


## Queue tracking allocated [RID] instances to batch cleanup and prevent leaks.
class DeletionQueue:
	## List of tracked [RID] allocations.
	var queue: Array[RID] = []

	## Adds an [RID] to the queue and returns it.
	func push(rid: RID) -> RID:
		queue.push_back(rid)
		return rid

	## Releases all active [RID] instances tracked by the queue.
	func flush(current_device: RenderingDevice) -> void:
		for i: int in range(queue.size() - 1, -1, -1):
			if not queue[i].is_valid():
				continue
			current_device.free_rid(queue[i])
		queue.clear()

	## Removes and frees a specific [RID] from the device.
	func free_rid(current_device: RenderingDevice, rid: RID) -> void:
		var rid_idx: int = queue.find(rid)
		assert(rid_idx != -1, "RID was not found in deletion queue!")
		var popped_rid: RID = queue.pop_at(rid_idx)
		current_device.free_rid(popped_rid)


## Encapsulates an allocated [RID] alongside its [enum RenderingDevice.UniformType].
class Descriptor:
	## Target resource [RID].
	var rid: RID
	## Target [enum RenderingDevice.UniformType].
	var type: RenderingDevice.UniformType

	## Initializes descriptor with an [RID] and its uniform type.
	func _init(new_rid: RID, new_type: RenderingDevice.UniformType) -> void:
		rid = new_rid
		type = new_type


## The core Godot [RenderingDevice] instance used for GPU operations.
var device: RenderingDevice
## Specialized queue tracking allocated [RID] instances to prevent leaks.
var deletion_queue: DeletionQueue = DeletionQueue.new()
## Maps file paths to compiled shader [RID] instances.
var shader_cache: Dictionary
## Indicates whether device submissions require synchronization.
var needs_sync: bool = false


## Instantiates a [RenderingContext] targeting an active or default device.
static func create(target_device: RenderingDevice = null) -> RenderingContext:
	var context: RenderingContext = RenderingContext.new()
	var global_device: RenderingDevice = RenderingServer.get_rendering_device()
	context.device = global_device if not target_device else target_device
	return context


## Flushes queues and releases resources prior to object destruction.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		deletion_queue.flush(device)
		shader_cache.clear()
		if device != RenderingServer.get_rendering_device():
			device.free()


## Submits queued GPU compute commands and marks sync state.
func submit() -> void:
	device.submit()
	needs_sync = true


## Blocks execution until GPU submissions complete.
func sync() -> void:
	device.sync()
	needs_sync = false


## Begins a compute list on the device and returns the list ID.
func compute_list_begin() -> int:
	return device.compute_list_begin()


## Ends an active compute list on the device.
func compute_list_end() -> void:
	device.compute_list_end()


## Inserts a pipeline memory barrier into the active compute list.
func compute_list_add_barrier(compute_list: int) -> void:
	device.compute_list_add_barrier(compute_list)


## Compiles and loads a shader from disk or retrieves it from cache.
func load_shader(path: String) -> RID:
	if not shader_cache.has(path):
		var raw_file: Variant = load(path)
		var shader_file: RDShaderFile = raw_file if raw_file is RDShaderFile else null
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
		var compiled_shader: RID = device.shader_create_from_spirv(shader_spirv)
		shader_cache[path] = deletion_queue.push(compiled_shader)
	var cached_rid: Variant = shader_cache[path]
	return cached_rid if cached_rid is RID else RID()


## Creates an [RID] storage buffer descriptor.
func create_storage_buffer(size: int, data: PackedByteArray = [], usage: int = 0) -> Descriptor:
	if size > data.size():
		var padding: PackedByteArray = PackedByteArray()
		padding.resize(size - data.size())
		data += padding
	var buf_size: int = maxi(size, data.size())
	return Descriptor.new(
		deletion_queue.push(device.storage_buffer_create(buf_size, data, usage)),
		RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	)


## Creates an [RID] uniform buffer descriptor.
func create_uniform_buffer(size: int, data: PackedByteArray = []) -> Descriptor:
	size = maxi(16, size)
	if size > data.size():
		var padding: PackedByteArray = PackedByteArray()
		padding.resize(size - data.size())
		data += padding
	var buf_size: int = maxi(size, data.size())
	return Descriptor.new(
		deletion_queue.push(device.uniform_buffer_create(buf_size, data)),
		RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	)


## Creates an [RID] 2D or 2D-array texture descriptor.
func create_texture(
	dimensions: Vector2i,
	format: RenderingDevice.DataFormat,
	usage: int = 0x18B,
	num_layers: int = 1,
	view: RDTextureView = RDTextureView.new(),
	data: PackedByteArray = []
) -> Descriptor:
	assert(num_layers >= 1, "Texture must have at least 1 layer.")
	var texture_format: RDTextureFormat = RDTextureFormat.new()
	texture_format.array_layers = num_layers
	texture_format.format = format
	texture_format.width = dimensions.x
	texture_format.height = dimensions.y
	texture_format.texture_type = (
		RenderingDevice.TEXTURE_TYPE_2D
		if num_layers == 1
		else RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	)
	texture_format.usage_bits = usage
	return Descriptor.new(
		deletion_queue.push(device.texture_create(texture_format, view, data)),
		RenderingDevice.UNIFORM_TYPE_IMAGE
	)


## Assembles an array of [Descriptor] items into a uniform set [RID].
func create_descriptor_set(
	descriptors: Array[Descriptor], shader: RID, descriptor_set_index: int = 0
) -> RID:
	var uniforms: Array[RDUniform] = []
	for i: int in range(descriptors.size()):
		var uniform: RDUniform = RDUniform.new()
		uniform.uniform_type = descriptors[i].type
		uniform.binding = i
		uniform.add_id(descriptors[i].rid)
		uniforms.push_back(uniform)
	return deletion_queue.push(device.uniform_set_create(uniforms, shader, descriptor_set_index))


## Builds a dispatch callable for a compute pipeline and bound resources.
func create_pipeline(
	block_dimensions: Array[int], descriptor_sets: Array[RID], shader: RID
) -> Callable:
	var pipeline: RID = deletion_queue.push(device.compute_pipeline_create(shader))

	return func(
		ctx: RenderingContext,
		compute_list: int,
		push_constant: PackedByteArray = [],
		descriptor_set_overwrites: Array[RID] = [],
		block_dimensions_overwrite_buffer: RID = RID(),
		block_dimensions_overwrite_buffer_byte_offset: int = 0
	) -> void:
		var current_device: RenderingDevice = ctx.device
		var sets: Array[RID] = (
			descriptor_sets if descriptor_set_overwrites.is_empty() else descriptor_set_overwrites
		)

		assert(
			block_dimensions.size() == 3 or block_dimensions_overwrite_buffer.is_valid(),
			"Must specify block dimensions or indirect buffer!"
		)
		assert(sets.size() >= 1, "Must specify at least one descriptor set!")

		current_device.compute_list_bind_compute_pipeline(compute_list, pipeline)
		if push_constant.size() > 0:
			current_device.compute_list_set_push_constant(
				compute_list, push_constant, push_constant.size()
			)

		for i: int in range(sets.size()):
			var set_rid: RID = sets[i]
			current_device.compute_list_bind_uniform_set(compute_list, set_rid, i)

		if block_dimensions_overwrite_buffer.is_valid():
			current_device.compute_list_dispatch_indirect(
				compute_list,
				block_dimensions_overwrite_buffer,
				block_dimensions_overwrite_buffer_byte_offset
			)
		else:
			var dim_x: int = block_dimensions[0]
			var dim_y: int = block_dimensions[1]
			var dim_z: int = block_dimensions[2]
			current_device.compute_list_dispatch(compute_list, dim_x, dim_y, dim_z)


## Serializes array data into an aligned push constant [PackedByteArray].
static func create_push_constant(data: Array) -> PackedByteArray:
	var packed_size: int = data.size() * 4
	assert(packed_size <= 128, "Push constant size must be at most 128 bytes!")

	var padding: int = ceili(packed_size / 16.0) * 16 - packed_size
	var packed_data: PackedByteArray = PackedByteArray()
	packed_data.resize(packed_size + (padding if padding > 0 else 0))
	packed_data.fill(0)

	for i: int in range(data.size()):
		var val: Variant = data[i]
		match typeof(val):
			TYPE_INT:
				var int_val: int = val if val is int else 0
				packed_data.encode_s32(i * 4, int_val)
			TYPE_BOOL:
				var bool_val: bool = val if val is bool else false
				packed_data.encode_s32(i * 4, 1 if bool_val else 0)
			TYPE_FLOAT:
				var float_val: float = val if val is float else 0.0
				packed_data.encode_float(i * 4, float_val)
	return packed_data
