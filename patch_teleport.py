import re

with open('test/unit/test_teleport.gd', 'r') as f:
    code = f.read()

# Replace free() with autofree. Wait, `free()` deletes immediately, whereas `queue_free()` defers it.
# The `Test script has 14 unfreed children.` warning comes from using Area3D.new() and AudioStreamPlayer.new() and NOT using autofree().
# We should use `autofree` where possible.
# In `before_each`, we should use `add_child_autofree()` instead of `add_child()`.

code = code.replace('add_child(_teleport)', 'add_child_autofree(_teleport)')
code = code.replace('add_child(_target_portal)', 'add_child_autofree(_target_portal)')
code = code.replace('add_child(_player)', 'add_child_autofree(_player)')
code = code.replace('add_child(other_body)', 'add_child_autofree(other_body)')

with open('test/unit/test_teleport.gd', 'w') as f:
    f.write(code)
