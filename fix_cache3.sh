# Oh wait, Godot editor creates `.import` files on startup. Since I'm running in headless, it'll recreate them.
# The `submit` command might have run a headless Godot instance which used the old cached `.import` files because `CloudsInc.comp` and `SunshineCloudsPostCompute.comp` are included files!
# Godot 4 `RDShaderFile` doesn't automatically detect changes in `#include` files if the parent `.glsl` file wasn't touched!
# Let's `touch` the parent `.glsl` files to force their timestamps to be newer, which triggers recompilation!
touch addons/SunshineClouds2/*.glsl
