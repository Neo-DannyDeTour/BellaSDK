# "All the shader bindings for the given set must be covered by the uniforms provided. Binding (8), set (0) was not provided."
# "Uniforms were never supplied for set (0) at the time of drawing, which are required by the pipeline."
# WAIT. Could it be `display_shader` expects binding 8?
# Let's check `SunshineCloudsDisplay.glsl`!
# It includes `CloudsInc.comp`! Does `CloudsInc.comp` define anything?
# Wait! Does `CloudsInc.comp` define a genericData uniform block? NO, it defines `struct GenericData`.
# Does `SunshineCloudsDisplay.glsl` define `layout(binding = 8)`? No.
# Then WHY does it complain about Binding 8 when it draws?
# "at the time of drawing"
# Actually, could "at the time of drawing" mean a compute dispatch?
# rd.compute_list_dispatch(...) -> "at the time of dispatching"
# rd.draw_list_draw(...) -> "at the time of drawing"
# Yes! `rd.draw_list_draw()` applies to Raster Pipelines, not Compute Pipelines!
# SO THE ERROR IS HAPPENING DURING `rd.draw_list_draw`!
# The `display_pipeline` requires binding 8? WHY?
# Let's read `SunshineCloudsDisplay.rast` again!
