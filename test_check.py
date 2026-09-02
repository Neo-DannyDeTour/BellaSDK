import re

with open('test/unit/test_killfield.gd', 'r') as f:
    code = f.read()

code = code.replace('add_child(_killfield)', 'add_child_autofree(_killfield)')
code = code.replace('add_child(_player)', 'add_child_autofree(_player)')
code = code.replace('add_child(other_body)', 'add_child_autofree(other_body)')

with open('test/unit/test_killfield.gd', 'w') as f:
    f.write(code)
