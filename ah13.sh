# Main Compute bindings are 0 to 16.
# GDScript Main Compute Uniforms:
# accum: 0 to 5
# depth: 6
# extra_noise: 7
# noise: 8, 9, 10, 11
# dither: 12
# height_gradient: 13
# camera_uniform: 14
# light_data: 15
# point_sample: 16
# TOTAL IS 17 BINDINGS! (0 through 16).
#
# BUT WAIT. Does `noise_uniform.binding = 8 + i` run for i=0 to 3 correctly?
# Yes.
# Does `point_sample_data_uniform.binding = 16` run? Yes.
#
# Let's count again!
# What if the user ran tests on the `.gd` script and it failed because ONE of the textures is null/missing, so `RDUniform.new()` generates an invalid binding?
# If `height_gradient` is not valid, `RenderingServer.texture_get_rd_texture(height_gradient.get_rid())` is invalid.
# But "Binding (8), set (0) was not provided" specifically points to BINDING 8.
# Binding 8 is `large_noise`.
# Wait, `noise_samplers[0]` is `large_scale_noise`.
# If `large_scale_noise` is null, or `RenderingServer.texture_get_rd_texture(large_scale_noise.get_rid())` returns RID(), then binding 8 fails!
# Why would `large_scale_noise` be null?
# Let's check `SunshineClouds.gd`: `initialize_compute()`.
