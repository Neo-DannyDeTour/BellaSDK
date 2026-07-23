# What if it's the `SunshineCloudsCompute.glsl`?
# In `SunshineCloudsCompute.glsl`:
# layout(binding = 16, std430) restrict buffer SamplePointsBuffer
# In `SunshineClouds.gd`:
# 						var point_sample_data_uniform: RDUniform = RDUniform.new()
# 						point_sample_data_uniform.binding = 16
# 						point_sample_data_uniform.add_id(point_sample_data_buffer)
# 						uniforms_array.append(point_sample_data_uniform)
#
# What if the user error means "Binding (8), set (0) was not provided"
# Is it from a different file?
grep -rn "binding = 8" .
