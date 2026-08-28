import sys
import subprocess

out = subprocess.run(["godot4", "--headless", "-s", "addons/gut/gut_cmdln.gd"], capture_output=True, text=True)
print(out.stdout)
print(out.stderr)
