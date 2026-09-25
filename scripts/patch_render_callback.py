import re

with open("addons/SunshineClouds2/SunshineClouds.gd", "r") as f:
    code = f.read()

# We need to distinguish between a full pipeline/texture rebuild
# vs just updating uniforms (when only the color_images change RIDs but size matches)

search = """			if (
				size != last_size
				or uniform_sets == null
				or uniform_sets.size() != view_count * 4
				or color_images.size() == 0
				or color_images[0] != buffers.get_color_layer(0)
				or blit_screen_images.size() == 0
				or msaa_mode != last_msaa_mode
			):
				# We removed the manual 'for uset: RID in uniform_sets' loop here.
				# initialize_compute() now safely handles it at the top of clear_compute().

				initialize_compute()
				initialize_raster_pipelines(
					buffers.get_color_layer(0, is_msaa_on), buffers.get_depth_layer(0, is_msaa_on)
				)

				accumulation_textures.clear()
				uniform_sets.clear()
				color_images.clear()"""

replace = """			var needs_full_rebuild: bool = (
				size != last_size
				or msaa_mode != last_msaa_mode
				or blit_screen_images.size() == 0
				or accumulation_textures.size() == 0
			)

			var needs_uniform_update: bool = (
				needs_full_rebuild
				or uniform_sets == null
				or uniform_sets.size() != view_count * 4
				or color_images.size() == 0
				or color_images[0] != buffers.get_color_layer(0)
			)

			if needs_uniform_update:
				if needs_full_rebuild:
					initialize_compute()
					initialize_raster_pipelines(
						buffers.get_color_layer(0, is_msaa_on), buffers.get_depth_layer(0, is_msaa_on)
					)
					accumulation_textures.clear()
				else:
					for uset: RID in uniform_sets:
						if uset.is_valid():
							rd.free_rid(uset)
					if general_data_buffer.is_valid():
						rd.free_rid(general_data_buffer)
					if light_data_buffer.is_valid():
						rd.free_rid(light_data_buffer)
					if point_sample_data_buffer.is_valid():
						rd.free_rid(point_sample_data_buffer)

				uniform_sets.clear()
				color_images.clear()"""

new_code = code.replace(search, replace)
if new_code == code:
    print("Failed to replace first block")

# Next, inside the view_count loop, we don't want to re-create accumulation textures if not rebuilding
search_loop = """
				for view: int in range(view_count):
					color_images.append(buffers.get_color_layer(view, false))
					## Rendering device handle for the depth image.
					var depth_image: RID = buffers.get_depth_layer(view, false)

					## Array holding uniform data for blank image data.
					var blank_image_data: PackedByteArray = PackedByteArray()
					# OPTIMIZATION: 8 bytes per pixel instead of 16 for half-float textures
					blank_image_data.resize(new_size.x * new_size.y * 8)

					## The base colorformat used for cloud rendering.
					var base_colorformat: RDTextureFormat = rd.texture_get_format(
						color_images[view]
					)

					## Controls the blit screen format behavior.
					var blit_screen_format: RDTextureFormat = rd.texture_get_format(
						buffers.get_color_layer(view, is_msaa_on)
					)
					blit_screen_format.usage_bits |= (
						RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
						| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
					)

					blit_screen_images.append(
						rd.texture_create(blit_screen_format, RDTextureView.new())
					)

					# OPTIMIZATION: Halved memory bandwidth by switching to 16-bit floats.
					base_colorformat.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
					base_colorformat.width = new_size.x
					base_colorformat.height = new_size.y

					for _i: int in range(7):
						accumulation_textures.append(
							rd.texture_create(
								base_colorformat, RDTextureView.new(), [blank_image_data]
							)
						)

					general_data_buffer = rd.uniform_buffer_create(1024)

					## Controls the depthformat behavior.
					var depthformat: RDTextureFormat = rd.texture_get_format(depth_image)
					depthformat.width = new_size.x
					depthformat.height = new_size.y
					depthformat.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
					depthformat.usage_bits = (
						RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
						| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
					)

					resized_depth = rd.texture_create(depthformat, RDTextureView.new(), [])
"""

replace_loop = """
				for view: int in range(view_count):
					color_images.append(buffers.get_color_layer(view, false))
					## Rendering device handle for the depth image.
					var depth_image: RID = buffers.get_depth_layer(view, false)

					if needs_full_rebuild:
						## Array holding uniform data for blank image data.
						var blank_image_data: PackedByteArray = PackedByteArray()
						# OPTIMIZATION: 8 bytes per pixel instead of 16 for half-float textures
						blank_image_data.resize(new_size.x * new_size.y * 8)

						## The base colorformat used for cloud rendering.
						var base_colorformat: RDTextureFormat = rd.texture_get_format(
							color_images[view]
						)

						## Controls the blit screen format behavior.
						var blit_screen_format: RDTextureFormat = rd.texture_get_format(
							buffers.get_color_layer(view, is_msaa_on)
						)
						blit_screen_format.usage_bits |= (
							RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
							| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
						)

						blit_screen_images.append(
							rd.texture_create(blit_screen_format, RDTextureView.new())
						)

						# OPTIMIZATION: Halved memory bandwidth by switching to 16-bit floats.
						base_colorformat.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
						base_colorformat.width = new_size.x
						base_colorformat.height = new_size.y

						for _i: int in range(7):
							accumulation_textures.append(
								rd.texture_create(
									base_colorformat, RDTextureView.new(), [blank_image_data]
								)
							)

						## Controls the depthformat behavior.
						var depthformat: RDTextureFormat = rd.texture_get_format(depth_image)
						depthformat.width = new_size.x
						depthformat.height = new_size.y
						depthformat.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
						depthformat.usage_bits = (
							RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
							| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
						)

						if resized_depth.is_valid():
							rd.free_rid(resized_depth)
						resized_depth = rd.texture_create(depthformat, RDTextureView.new(), [])
					else:
						# If not full rebuild, we just update the blit screen images if needed
						if blit_screen_images.size() <= view or not blit_screen_images[view].is_valid():
							var blit_screen_format: RDTextureFormat = rd.texture_get_format(
								buffers.get_color_layer(view, is_msaa_on)
							)
							blit_screen_format.usage_bits |= (
								RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
								| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
							)
							if blit_screen_images.size() > view:
								if blit_screen_images[view].is_valid():
									rd.free_rid(blit_screen_images[view])
								blit_screen_images[view] = rd.texture_create(blit_screen_format, RDTextureView.new())
							else:
								blit_screen_images.append(
									rd.texture_create(blit_screen_format, RDTextureView.new())
								)

					# We need to recreate these uniform buffers because they were freed during needs_uniform_update
					general_data_buffer = rd.uniform_buffer_create(1024)
"""
new_code = new_code.replace(search_loop, replace_loop)
if new_code == code:
    print("Failed to replace loop block")

# Fix for blit_screen_images cleanup block which was inside needs_uniform_update logic natively but I missed it.
search_blit_clean = """				#print(
				#"SunshineCloudsGD: Successfully freed prior rendering pass "
				#+ "arrays to prevent VRAM accumulation."
				#)

				for item: RID in blit_screen_images:
					if item.is_valid():
						rd.free_rid(item)
				blit_screen_images.clear()"""

replace_blit_clean = """				if needs_full_rebuild:
					for item: RID in blit_screen_images:
						if item.is_valid():
							rd.free_rid(item)
					blit_screen_images.clear()"""

new_code = new_code.replace(search_blit_clean, replace_blit_clean)

with open("addons/SunshineClouds2/SunshineClouds.gd", "w") as f:
    f.write(new_code)
