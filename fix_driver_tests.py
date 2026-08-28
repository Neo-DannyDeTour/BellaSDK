import re

with open("test/unit/test_sunshine_clouds_driver.gd", "r") as f:
    code = f.read()

# Instead of instantiating CompositorEffect directly which fails in Headless mode/GDScript due to engine bug or missing RenderServer things:
# We'll use a mocked object for `_clouds_res` which is what we did in other tests. Wait, GUT provides `double()`. Let's mock it using GUT `double()` or a dummy object. But `SunshineCloudsGD` has an explicit type in the test.
# Actually, the error says: "Invalid call. Nonexistent function 'new' in base 'GDScript'."
# This occurs if `SunshineCloudsGD` is loaded as a script but not named via `class_name` correctly, or if `new()` is missing because it's a `CompositorEffect` which cannot be instantiated directly via GDScript in some engine versions.
# Let's check `SunshineCloudsGD`. It has `class_name SunshineCloudsGD` and `extends CompositorEffect`.
# Let's replace `SunshineCloudsGD.new()` with a dummy class or just use Godot's `Object` if typing allows, or `double(SunshineCloudsGD).new()`.

# Let's check the type of `_clouds_res`: `var _clouds_res: SunshineCloudsGD`. This is strict.

# We'll use double(SunshineCloudsGD).new() if possible. Or we can just load the Example resource.
replace_str = """	# Use the example resource instead of instantiating a new CompositorEffect which fails in some headless environments
	_clouds_res = preload("res://addons/SunshineClouds2/ExampleCloudsResource.tres")"""

code = code.replace("_clouds_res = SunshineCloudsGD.new()", replace_str)

with open("test/unit/test_sunshine_clouds_driver.gd", "w") as f:
    f.write(code)
