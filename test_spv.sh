# Let's clean .spv caches in the system?
# I'll just change the uniform bindings in GDScript back to what they were! Wait, no.
# What if it's the `uniform_sets[(view * 4) + 3]`?
# `uniform_sets` contains:
# [0] prepass
# [1] main
# [2] postpass
# [3] display
# Is it possible that `display_shader` somehow inherited a binding 8 from an old compile cache?
# "at the time of drawing"
