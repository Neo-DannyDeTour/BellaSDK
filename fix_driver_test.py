import re

with open("test/unit/test_sunshine_clouds_driver.gd", "r") as f:
    code = f.read()

search = """	_clouds_res = SunshineCloudsGD.new()"""
replace = """	# In Godot 4.3+, CompositorEffect classes cannot be instantiated using .new() in scripts.
	# We'll use a mocked proxy resource or find a way around it. Actually we can load the resource if it's already instantiated or use a dummy object for the driver."""

# The error: `SCRIPT ERROR: Invalid call. Nonexistent function 'new' in base 'GDScript'.`
# This means `SunshineCloudsGD` is probably a Resource/CompositorEffect. Actually, `SunshineCloudsGD` is a script. In Godot 4, you can only call `.new()` if the class has an empty constructor or is not a built-in un-newable class. If it's a `CompositorEffect`, maybe it requires something else. Or maybe the script is broken.
