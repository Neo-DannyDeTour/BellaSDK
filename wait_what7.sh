# Godot 4 uses `.glsl` imported as `RDShaderFile`.
# The actual spirv binary is stored inside `.godot/imported/` which is ignored in `.gitignore`.
# BUT if `.godot` didn't exist, it generated it from scratch.
# IF it generated it from scratch, WHY did it compile `SunshineCloudsPostCompute.comp` with binding 8??
# Because Godot imported the files, and it compiled them.
# DOES `SunshineCloudsPostCompute.comp` have a binding 8? NO!
# Wait! Let's check `SunshineCloudsPostCompute.msaa.glsl`!!!
cat addons/SunshineClouds2/SunshineCloudsPostCompute.msaa.glsl
