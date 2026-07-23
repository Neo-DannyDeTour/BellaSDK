# Oh my god.
# "All the shader bindings for the given set must be covered by the uniforms provided. Binding (8), set (0) was not provided."
# Wait, let's look at GDScript `SunshineClouds.gd` line 799!
# noise_uniform.binding = 8 + i
# Which is bindings 8, 9, 10, 11!
# Wait! In my previous `sed` commands, I did:
# sed -i '/## Array holding uniform data for camera data./,/uniforms_array.append(camera_data_uniform)/d' addons/SunshineClouds2/SunshineClouds.gd
# Wait, did I mess up the `uniform_sets.append(rd.uniform_set_create(uniforms_array, shader, 0))` call?
# Let's check where the error happened: "Parameter "uniform_set" is null."
# Which uniform set? Main Compute Uniforms!
# In Main Compute, `uniform_sets.append(rd.uniform_set_create(uniforms_array, shader, 0))` is failing because `uniforms_array` is missing binding 8?
# Let's see `SunshineClouds.gd` Main Compute Uniforms array.
cat -n addons/SunshineClouds2/SunshineClouds.gd | sed -n '753,865p'
