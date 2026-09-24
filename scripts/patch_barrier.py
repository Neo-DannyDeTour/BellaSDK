import re

with open("addons/SunshineClouds2/SunshineClouds.gd", "r") as f:
    code = f.read()

# Add a compute barrier before retrieving async data
search = """			if not position_resetting and position_querying:
				position_resetting = true
				rd.buffer_get_data_async(point_sample_data_buffer, retrieve_position_queries.bind())"""

replace = """			if not position_resetting and position_querying:
				position_resetting = true
				rd.barrier(RenderingDevice.BARRIER_MASK_COMPUTE)
				rd.buffer_get_data_async(point_sample_data_buffer, retrieve_position_queries.bind())"""

new_code = code.replace(search, replace)
if new_code == code:
    print("Failed to replace barrier block")

with open("addons/SunshineClouds2/SunshineClouds.gd", "w") as f:
    f.write(new_code)
