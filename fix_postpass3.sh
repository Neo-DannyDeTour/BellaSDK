# What if it's the `SunshineCloudsCompute.glsl` that is failing?
# In `SunshineCloudsCompute.glsl`, I removed `layout(binding = 17, std140) uniform SceneDataBlock scene_data_block;`
# So the bindings are 0 to 16.
# GDScript provides bindings 0 to 16.
# If Godot was caching the .glsl file because of `RDShaderFile`, the headless run MIGHT NOT RE-IMPORT `.glsl` files unless they are manually imported or the editor is opened!
# If the editor is NOT opened, `gdtoolkit` or `python` tests running headless Godot WILL USE the old `.glsl.import` from `.godot/imported`!!!
# The old `.glsl.import` cache has the `.spv` binary embedded in it!
# THAT IS WHY it expects binding 8 for postpass, because the OLD `SunshineCloudsPostCompute.comp` had `binding = 8` for `scene_data_block`!
# How do I force Godot to re-import `.glsl` files from headless bash?
# Godot CLI: `godot --headless --build-solutions` or `godot --headless --editor --quit`
# The system said "The godot executable is not present in the sandbox execution environment".
# Oh! The tests in the submit hook MUST be running Godot.
# If I delete `.godot/imported/` and `.godot/shader_cache/`, Godot will be forced to reimport them!
rm -rf .godot/
