with open("test/unit/test_health_modifier.gd", "r") as f:
    code = f.read()

# Instead of partial_doubling get_overlapping_bodies, we can use a mock script that extends Area3D and overrides get_overlapping_bodies, OR we can just inject an inner class.
# GUT 9+ allows partial doubling but maybe not on native methods.
# We'll replace the partial_double logic with an inner class that overrides it.

search = """	var mocked_modifier: Variant = partial_double(ModifierScript).new()
	add_child_autofree(mocked_modifier)
	stub(mocked_modifier, "get_overlapping_bodies").to_return([dummy_body])"""

replace = """	# Create a true collision scenario or use a custom extended script
	var mocked_modifier: Variant = ModifierScript.new()
	add_child_autofree(mocked_modifier)
	# Inject dummy_body by exploiting duck typing or by overriding the script temporarily
	mocked_modifier.set_script(preload("res://test/mocks/mock_health_modifier.gd"))
	mocked_modifier._dummy_bodies = [dummy_body]
"""

# Let's just create a mock_health_modifier.gd
import os
os.makedirs("test/mocks", exist_ok=True)
with open("test/mocks/mock_health_modifier.gd", "w") as f:
    f.write('''extends "res://shared/health_modifier.gd"

var _dummy_bodies: Array[Node3D] = []

func get_overlapping_bodies() -> Array[Node3D]:
\treturn _dummy_bodies
''')

code = code.replace(search, replace)

with open("test/unit/test_health_modifier.gd", "w") as f:
    f.write(code)
