@tool
class_name RenderingContext extends Object
## A wrapper around [RenderingDevice] that handles basic memory management/allocation


class DeletionQueue:
	var queue: Array[RID] = []

	func push(rid: RID) -> RID:
		queue.push_back(rid)
		return rid

	func flush(device: RenderingDevice) -> void:
		# We work backwards in order of allocation when freeing resources
		for i in range(queue.size() - 1, -1, -1):
			if not queue[i].is_valid():
				continue
			device.free_rid(queue[i])
		queue.clear()

	func free_rid(device: RenderingDevice, rid: RID) -> void:
		var rid_idx := queue.find(rid)
		assert(rid_idx != -1, "RID was not found in deletion queue!")
		device.free_rid(queue.pop_at(rid_idx))


class Descriptor:
	var rid: RID
	var type: RenderingDevice.UniformType

	func _init(rid_: RID, type_: RenderingDevice.UniformType) -> void:
		rid = rid_
		type = type_


var device: RenderingDevice
var deletion_queue := DeletionQueue.new()
var shader_cache: Dictionary
var needs_sync := false


static func create(target_device: RenderingDevice = null) -> RenderingContext:
	var context := RenderingContext.new()
	context.device = (RenderingServer.create_local_rendering_device() if not target_device else target_device)
	return context


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# All resources must be freed after use to avoid memory leaks.
		deletion_queue.flush(device)
		shader_cache.clear()
		if device != RenderingServer.get_rendering_device():
			device.free()


# --- WRAPPER FUNCTIONS ---
func submit() -> void:
	device.submit()
	needs_sync = true


func sync() -> void:
	device.sync()
	needs_sync = false


func compute_list_begin() -> int:
	return device.compute_list_begin()


func compute_list_end() -> void:
	device.compute_list_end()


func compute_list_add_barrier(compute_list: int) -> void:
	device.compute_list_add_barrier(compute_list)


# --- HELPER FUNCTIONS ---
func load_shader(path: String) -> RID:
	if not shader_cache.has(path):
		var shader_file := load(path) as RDShaderFile
		var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
		shader_cache[path] = deletion_queue.push(device.shader_create_from_spirv(shader_spirv))
	return shader_cache[path]


func create_storage_buffer(size: int, data: PackedByteArray = [], usage := 0) -> Descriptor:
	if size > data.size():
		var padding := PackedByteArray()
		padding.resize(size - data.size())
		data += padding
	return Descriptor.new(
		deletion_queue.push(device.storage_buffer_create(maxi(size, data.size()), data, usage)),
		RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	)


func create_uniform_buffer(size: int, data: PackedByteArray = []) -> Descriptor:
	size = maxi(16, size)
	if size > data.size():
		var padding := PackedByteArray()
		padding.resize(size - data.size())
		data += padding
	return Descriptor.new(
		deletion_queue.push(device.uniform_buffer_create(maxi(size, data.size()), data)),
		RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	)


# CHANGED: Default num_layers is now 1 to prevent assertion failure
func create_texture(
	dimensions: Vector2i,
	format: RenderingDevice.DataFormat,
	usage := 0x18B,
	num_layers := 1,
	view := RDTextureView.new(),
	data: PackedByteArray = []
) -> Descriptor:
	assert(num_layers >= 1, "Texture must have at least 1 layer.")
	var texture_format := RDTextureFormat.new()
	texture_format.array_layers = num_layers
	texture_format.format = format
	texture_format.width = dimensions.x
	texture_format.height = dimensions.y
	texture_format.texture_type = (
		RenderingDevice.TEXTURE_TYPE_2D if num_layers == 1 else RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	)
	texture_format.usage_bits = usage
	return Descriptor.new(
		deletion_queue.push(device.texture_create(texture_format, view, data)), RenderingDevice.UNIFORM_TYPE_IMAGE
	)


## Creates a descriptor set. The ordering of the provided descriptors matches the binding ordering
## within the shader.
func create_descriptor_set(descriptors: Array[Descriptor], shader: RID, descriptor_set_index := 0) -> RID:
	var uniforms: Array[RDUniform] = []
	for i in range(descriptors.size()):
		var uniform := RDUniform.new()
		uniform.uniform_type = descriptors[i].type
		uniform.binding = i  # This matches the binding in the shader.
		uniform.add_id(descriptors[i].rid)
		uniforms.push_back(uniform)
	return deletion_queue.push(device.uniform_set_create(uniforms, shader, descriptor_set_index))


## Returns a [Callable] which will dispatch a compute pipeline.
func create_pipeline(block_dimensions: Array, descriptor_sets: Array, shader: RID) -> Callable:
	var pipeline := deletion_queue.push(device.compute_pipeline_create(shader))

	return func(
		ctx: RenderingContext,
		compute_list: int,
		push_constant: PackedByteArray = [],
		descriptor_set_overwrites: Array = [],
		block_dimensions_overwrite_buffer := RID(),
		block_dimensions_overwrite_buffer_byte_offset := 0
	) -> void:
		var current_device := ctx.device
		var sets := descriptor_sets if descriptor_set_overwrites.is_empty() else descriptor_set_overwrites

		assert(
			block_dimensions.size() == 3 or block_dimensions_overwrite_buffer.is_valid(),
			"Must specify block dimensions or specify a dispatch indirect buffer!"
		)
		assert(sets.size() >= 1, "Must specify at least one descriptor set!")

		current_device.compute_list_bind_compute_pipeline(compute_list, pipeline)
		if push_constant.size() > 0:
			current_device.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())

		for i in range(sets.size()):
			current_device.compute_list_bind_uniform_set(compute_list, sets[i], i)

		if block_dimensions_overwrite_buffer.is_valid():
			current_device.compute_list_dispatch_indirect(
				compute_list, block_dimensions_overwrite_buffer, block_dimensions_overwrite_buffer_byte_offset
			)
		else:
			current_device.compute_list_dispatch(
				compute_list, block_dimensions[0], block_dimensions[1], block_dimensions[2]
			)


## Returns a [PackedByteArray] from the provided data, whose size is rounded up to the nearest
## multiple of 16 for memory alignment.
static func create_push_constant(data: Array) -> PackedByteArray:
	var packed_size := data.size() * 4
	assert(packed_size <= 128, "Push constant size must be at most 128 bytes!")

	var padding := ceili(packed_size / 16.0) * 16 - packed_size
	var packed_data := PackedByteArray()
	packed_data.resize(packed_size + (padding if padding > 0 else 0))
	packed_data.fill(0)

	for i in range(data.size()):
		match typeof(data[i]):
			TYPE_INT, TYPE_BOOL:
				packed_data.encode_s32(i * 4, data[i])
			TYPE_FLOAT:
				packed_data.encode_float(i * 4, float(data[i]))
	return packed_data
