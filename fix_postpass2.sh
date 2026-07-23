# What if it's the postpass shader dispatch that failed?
# Look at the error:
# ERROR: All the shader bindings for the given set must be covered by the uniforms provided. Binding (8), set (0) was not provided.
# ERROR: servers/rendering/rendering_device.cpp:6756 - Parameter "uniform_set" is null.
# "Parameter uniform_set is null."
# This means `rd.uniform_set_create` returned `RID()`!
# Which one?
# If it returned `RID()`, then `uniform_sets.append(RID())`!
# Then later: `rd.draw_list_bind_uniform_set(display_list, uniform_sets[(view * 4) + 3], 0)`
# Or `rd.compute_list_bind_uniform_set(postpass_list, uniform_sets[(view * 4) + 2], 0)`
# Godot 4 throws "Uniforms were never supplied for set (0) at the time of drawing" during DISPATCH or DRAW.
# Ah! "at the time of drawing" is specifically for Compute OR Raster in Godot (the error string in `rendering_device.cpp` is used for both).
# BUT `Parameter "uniform_set" is null` comes from `compute_list_bind_uniform_set` OR `draw_list_bind_uniform_set`.
# If `rd.uniform_set_create(postpass_uniforms_array, postpass_shader, 0)` failed, it returns `RID()`.
# Why did it fail? "Binding (8), set (0) was not provided."
# This perfectly means `postpass_shader` REQUIRES binding 8, but we provided 0-7!
# YES!
# WHY does `postpass_shader` require binding 8?
# Let's check `SunshineCloudsPostCompute.comp` AGAIN.
