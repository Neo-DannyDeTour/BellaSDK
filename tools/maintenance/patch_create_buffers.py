import re

with open("addons/SunshineClouds2/SunshineClouds.gd", "r") as f:
    code = f.read()

# I also need to remove the recreation of `general_data_buffer`, `light_data_buffer`, and `point_sample_data_buffer`
# in the uniform update loop if they are already valid, OR I can just create them if they are invalid.
# Since we didn't free them in `needs_uniform_update` `else` block, they are still valid!

search = """					# We need to recreate these uniform buffers because they were freed during needs_uniform_update
					general_data_buffer = rd.uniform_buffer_create(1024)"""

replace = """					if needs_full_rebuild or not general_data_buffer.is_valid():
						general_data_buffer = rd.uniform_buffer_create(1024)"""

new_code = code.replace(search, replace)
if new_code == code:
    print("Failed to replace general_data_buffer creation block")

search_light = """					light_data_buffer = rd.uniform_buffer_create(6272)"""
replace_light = """					if needs_full_rebuild or not light_data_buffer.is_valid():
						light_data_buffer = rd.uniform_buffer_create(6272)"""

new_code = new_code.replace(search_light, replace_light)

search_point = """					## Array holding uniform data for sample data.
					var sample_data: PackedByteArray = PackedByteArray()
					sample_data.resize(512)
					point_sample_data_buffer = rd.storage_buffer_create(512, sample_data)"""
replace_point = """					if needs_full_rebuild or not point_sample_data_buffer.is_valid():
						## Array holding uniform data for sample data.
						var sample_data: PackedByteArray = PackedByteArray()
						sample_data.resize(512)
						point_sample_data_buffer = rd.storage_buffer_create(512, sample_data)"""

new_code = new_code.replace(search_point, replace_point)

with open("addons/SunshineClouds2/SunshineClouds.gd", "w") as f:
    f.write(new_code)
