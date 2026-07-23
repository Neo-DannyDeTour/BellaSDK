# To ensure Godot compiles all shaders from scratch during the pre-commit checks, we MUST remove all .import files for the shaders.
find addons/SunshineClouds2/ -name "*.glsl.import" -delete
find addons/SunshineClouds2/ -name "*.comp.import" -delete
