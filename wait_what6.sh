# There is NO .godot directory!
# That means it runs Godot during submit, which creates `.godot` from scratch, BUT then why did it use cached shaders?
# Because the user checked in the `.glsl.import` files into git!
ls -la addons/SunshineClouds2/*.glsl.import
