# What if Godot requires binding 8 in Main Compute?
# No, we supply bindings 0 to 16 in GDScript for Main Compute!
# Wait! In Main Compute GDScript:
# 					var camera_data_uniform: RDUniform = RDUniform.new()
# 					camera_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
# 					camera_data_uniform.binding = 17
# 					camera_data_uniform.add_id(camera_data)
# 					uniforms_array.append(camera_data_uniform)
# I REMOVED THIS FROM GDSCRIPT.
# So Main Compute GDScript supplies 0 to 16.
# Main Compute Shader defines 0 to 16. (I removed `layout(binding = 17)`!)
# BUT if it was Main Compute failing, it would say "Binding (17), set (0) was not provided"!
# It said "Binding (8), set (0) was not provided".
# That means it is POSTPASS!
# Postpass Shader original:
# layout(binding = 6) uniform uniformBuffer genericData
# layout(binding = 7) uniform LightsBuffer
# layout(binding = 8) uniform SceneDataBlock scene_data_block
# I removed binding 8. GDScript provides 0 to 7.
# So if it complains about binding 8, it means Postpass Shader SPIRV still has binding 8.
# WHICH MEANS Godot loaded a cached `SunshineCloudsPostCompute.glsl` or `SunshineCloudsPostCompute.msaa.glsl`.
