# What about prepass_shader? Did it have a binding 8? No, it has 0, 1, 2.
# So Postpass GDScript supplies 0 to 7.
# "All the shader bindings for the given set must be covered by the uniforms provided. Binding (8), set (0) was not provided."
# Wait, if POSTPASS SHADER compiled with binding 8 still in it (because Godot loaded from cache), then it would expect binding 8!
# "Parameter 'uniform_set' is null" means `rd.uniform_set_create` returned `RID()`.
# When `rd.draw_list_bind_uniform_set` is called, it checks `uniform_sets[(view * 4) + 3]`!
# Wait!
# uniform_sets[view * 4] = prepass (index 0)
# uniform_sets[view * 4 + 1] = compute (index 1)
# uniform_sets[view * 4 + 2] = postpass (index 2)
# uniform_sets[view * 4 + 3] = display (index 3)
# If ANY of them returned `RID()`, it pushes `RID()` to the array!
# "Uniforms were never supplied for set (0) at the time of drawing"
# Godot prints "at the time of drawing" inside `compute_list_dispatch` too!
# Let me look at Godot Engine source code for "at the time of drawing":
# `servers/rendering/rendering_device.cpp`:
#   if (uniform_set.is_null()) {
#       ERR_PRINT("Uniforms were never supplied for set (" + itos(i) + ") at the time of drawing, which are required by the pipeline.");
#   }
# This happens in BOTH `draw_list_draw()` AND `compute_list_dispatch()`!
# SO Godot is compiling the Compute Shader and it STILL expects Binding 8!
# Because we didn't force a cache clear!
# When the `submit` command runs, it runs Godot. Godot loads the cached imported resources.
# How do I force Godot to re-import the shaders before submitting?
# Let's delete the `.godot` folder again. I am SURE `.godot` doesn't exist right now, but Godot `submit` hook will run it.
# If I delete `addons/SunshineClouds2/*.glsl.import`, Godot will REGENERATE them!
# BUT Wait! `SunshineCloudsPostCompute.msaa.glsl` ALSO includes `SunshineCloudsPostCompute.comp`!
# Let's check `SunshineCloudsPostCompute.msaa.glsl.import`.
# Godot 4 caches compute shaders in `.godot/imported/`. If we don't delete the import file, it uses the cached import!
rm -f addons/SunshineClouds2/*.glsl.import
