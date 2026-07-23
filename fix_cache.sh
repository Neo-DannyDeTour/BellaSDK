# Let's delete the `.godot/imported` folder and all `.import` files for the shaders we touched, so Godot is forced to recompile them!
# Actually we can just touch the .glsl files. Wait, if it runs in headless, we just need to delete the cache!
rm -rf .godot/
