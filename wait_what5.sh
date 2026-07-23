# "All the shader bindings for the given set must be covered by the uniforms provided. Binding (8), set (0) was not provided."
# Let's count bindings passed to postpass_shader.
# postpass_uniforms_array:
# binding = 0 (prepass_color_data_uniform)
# binding = 1 (prepass_color_uniform)
# binding = 2 (postpass_reflections_uniform)
# binding = 3 (postpass_input_screen_uniform)
# binding = 4 (postpass_output_screen_uniform)
# binding = 5 (postpass_depth_uniform)
# binding = 6 (postpass_camera_uniform)
# binding = 7 (postpass_light_data_uniform)
# Total 8 bindings provided: 0, 1, 2, 3, 4, 5, 6, 7.
# And `SunshineCloudsPostCompute.comp` has:
# layout(binding = 0) input_data_image
# layout(binding = 1) input_color_image
# layout(rgba16f, binding = 2) reflections_sample
# layout(binding = 3) input_screen_image
# layout(rgba16f, binding = 4) output_screen_image
# layout(binding = 5) depth_image
# layout(binding = 6) uniformBuffer genericData
# layout(binding = 7) LightsBuffer
#
# BUT WAIT. Did Godot Cache the `.glsl` file compilation?
# Yes! `RDShaderFile` in Godot will compile shaders and if we just run `gdformat` it doesn't do anything about Godot's cache. The user ran the Godot project and got this error!
# In Godot 4, Compute Shaders compiled via `RDShaderFile` are automatically recompiled if the source file changed? Actually, NO! If the shader is imported as a `.glsl` resource, Godot creates a `.glsl.import` and a `.res` file in `.godot/imported/`. If you edit the `.glsl` file OUTSIDE of Godot Editor while Godot is NOT running, the next time Godot runs headlessly for tests (or when the user runs it), it might NOT trigger a re-import if Godot thinks the MD5 hasn't changed or it just uses the old import cache!
# Let's look for `.import` files!
find . -name "*.glsl.import"
