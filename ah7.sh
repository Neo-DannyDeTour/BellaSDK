# "All the shader bindings for the given set must be covered by the uniforms provided. Binding (8), set (0) was not provided."
# Let's count bindings in `SunshineCloudsCompute.glsl` (Main Compute Uniforms):
# 0: accum
# 1: accum
# 2: accum
# 3: accum
# 4: accum
# 5: accum
# 6: depth_uniform
# 7: extra_noise_uniform
# 8: noise_uniform (large)
# 9: noise_uniform (medium)
# 10: noise_uniform (small)
# 11: noise_uniform (curl)
# 12: dither_noise_uniform
# 13: height_gradient_uniform
# 14: camera_uniform
# 15: light_data_uniform
# 16: point_sample_data_uniform
#
# Wait, look at `SunshineCloudsCompute.glsl`!
# layout(binding = 16, std430) restrict buffer SamplePointsBuffer
# Is there a binding 17?
# Yes! `layout(binding = 17, std140) uniform SceneDataBlock` was there before I removed it!
# Wait! Look at `SunshineClouds.gd` line 799!
# noise_uniform.binding = 8 + i
# If `i` is 0 to 3, then it provides bindings 8, 9, 10, 11!
# Wait, what if I DID NOT provide binding 8?
# Let's look at GDScript `SunshineClouds.gd` line 800-802:
# 							noise_uniform.add_id(linear_sampler)
# 							noise_uniform.add_id(
# 								RenderingServer.texture_get_rd_texture(noise_samplers[i].get_rid())
# 							)
# 							uniforms_array.append(noise_uniform)
# Wait, if `noise_samplers` has a null texture?
# No, `noise_samplers` is `[large_scale_noise, medium_scale_noise, small_scale_noise, curl_noise]`.
# If `large_scale_noise` is null, its `get_rid()` is invalid, `texture_get_rd_texture` returns a dummy or null, then Godot might not bind it correctly?
# But `large_scale_noise` is initialized in `initialize_compute()`.
