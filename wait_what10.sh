# What if it's the postpass shader that is failing!
# "Binding (8), set (0) was not provided"
# Let's check `SunshineCloudsPostCompute.comp` AGAIN.
# We REMOVED binding 8!
# But in Godot 4, Compute Shaders are created from `.glsl` files via `RDShaderFile`.
# The pipeline creates `.glsl.import` which tells Godot how to compile it.
# The user ran the Godot project and it failed.
# Why did it fail? BECAUSE Godot uses cached `.spv` from `.godot/imported/` AND I DELETED IT!
# Wait, if I deleted it, Godot recreated it from `.glsl`.
# Does `SunshineCloudsPostCompute.msaa.glsl` include `CloudsInc.comp` and `SunshineCloudsPostCompute.comp`?
# YES.
# Let's verify `SunshineCloudsPostCompute.comp` DOES NOT contain `binding = 8` ANYWHERE.
grep "binding =" addons/SunshineClouds2/SunshineCloudsPostCompute.comp
