# Oh wait... The error message "Uniforms were never supplied for set (0) at the time of drawing" is generic Godot error for BOTH drawing AND compute dispatch!
# Look at `rendering_device.cpp:6756`. "Uniforms were never supplied for set (0) at the time of drawing".
# So it could be ANY of the passes.
# Prepass, Main Compute, Postpass, Display.
# We checked Postpass. It has bindings 0-7. GDScript provides 0-7.
# We checked Display. It has binding 0. GDScript provides 0.
# We checked Prepass.
grep "binding =" addons/SunshineClouds2/SunshineCloudsPreCompute.glsl
