import re

with open("addons/SunshineClouds2/SunshineClouds.gd", "r") as f:
    code = f.read()

# Fix the ignore_accumilation toggle logic:
# Remove the rendertarget != last_render_target reset entirely.
search = """			if rendertarget != last_render_target:
				last_render_target = rendertarget
				ignore_accumilation = true
			else:
				ignore_accumilation = false"""

replace = """			ignore_accumilation = false
			if size != last_size:
				ignore_accumilation = true"""

new_code = code.replace(search, replace)
if new_code == code:
    print("Failed to replace ignore_accumilation block")

with open("addons/SunshineClouds2/SunshineClouds.gd", "w") as f:
    f.write(new_code)
