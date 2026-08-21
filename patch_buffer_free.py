import re

with open("addons/SunshineClouds2/SunshineClouds.gd", "r") as f:
    code = f.read()

search = """				if needs_uniform_update:
					if needs_full_rebuild:
						initialize_compute()
						initialize_raster_pipelines(
							buffers.get_color_layer(0, is_msaa_on),
							buffers.get_depth_layer(0, is_msaa_on)
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

					uniform_sets.clear()"""

replace = """				if needs_uniform_update:
					if needs_full_rebuild:
						initialize_compute()
						initialize_raster_pipelines(
							buffers.get_color_layer(0, is_msaa_on),
							buffers.get_depth_layer(0, is_msaa_on)
						)
						accumulation_textures.clear()
					else:
						for uset: RID in uniform_sets:
							if uset.is_valid():
								rd.free_rid(uset)

					uniform_sets.clear()"""

new_code = code.replace(search, replace)
if new_code == code:
    print("Failed to replace buffer freeing block")

with open("addons/SunshineClouds2/SunshineClouds.gd", "w") as f:
    f.write(new_code)
