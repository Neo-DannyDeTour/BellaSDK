# Let's check `SunshineClouds.gd` line 927 for postpass uniform.
# Wait! In `SunshineClouds.gd` I changed `postpass_camera_uniform.binding` to 6, AND it used to be 6! Wait!
# Let me look at the original postpass layout in `SunshineCloudsPostCompute.comp`:
# layout(binding = 0) uniform sampler2D input_data_image;
# layout(binding = 1) uniform sampler2D input_color_image;
# layout(rgba16f, binding = 2) uniform image2D reflections_sample;
# layout(binding = 3) uniform Sampler2DMSAA input_screen_image;
# layout(rgba16f, binding = 4) restrict uniform Image2DMSAA output_screen_image;
# layout(binding = 5) uniform Sampler2DMSAA depth_image;
# layout(binding = 6) uniform uniformBuffer genericData;
# layout(binding = 7) uniform LightsBuffer;
# layout(binding = 8, std140) uniform SceneDataBlock scene_data_block;
#
# Wait, original `SunshineClouds.gd` postpass uniforms:
# prepass_color_data_uniform.binding = 0
# prepass_color_uniform.binding = 1
# postpass_reflections_uniform.binding = 2
# postpass_input_screen_uniform.binding = 3
# postpass_output_screen_uniform.binding = 4
# postpass_depth_uniform.binding = 5
# postpass_camera_uniform.binding = 6
# postpass_light_data_uniform.binding = 7
# postpass_camera_data_uniform.binding = 8 -> THIS was removed by me.
#
# BUT! In `SunshineClouds.gd`, `postpass_camera_data_uniform` was removed, so we only provide bindings 0 to 7!
# And in the SHADER `SunshineCloudsPostCompute.comp`, I removed `layout(binding = 8, std140) uniform SceneDataBlock`!
# SO the shader expects 0 to 7. GDScript provides 0 to 7.
# Why did it complain about Binding 8???
