import re

with open("test/unit/test_health_modifier.gd", "r") as f:
    code = f.read()

# get_overlapping_bodies is a native C++ method on Area3D, GUT cannot partial_double native methods easily unless they are virtual.
# We will just manually construct the scene or use an array override if it has one. Let's check health_modifier.gd.
