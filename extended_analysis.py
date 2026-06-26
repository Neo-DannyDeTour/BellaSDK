import os
import subprocess
import re
import json

find_cmd = 'find . -name "*.gd" | grep -v "addons/" | grep -iv "player_old.gd" | grep -iv "playerENUM_TEST.gd"'
result = subprocess.run(find_cmd, shell=True, capture_output=True, text=True)
gd_files = [f for f in result.stdout.strip().split('\n') if f]

report = {
    "Scene Decoupling & Signal Auditing": [],
    "Developer Experience (API Review)": [],
    "Memory and Resource Management": [],
    "Edge Cases and Null Safety": [],
    "State Management": []
}

api_name_regex = re.compile(r'^func\s+([A-Z]\w*|[a-z]+[A-Z]\w*)\(') # Detects PascalCase or camelCase functions
api_var_regex = re.compile(r'^var\s+([A-Z]\w*)\s*[:=]') # Detects PascalCase vars (public)

for filepath in gd_files:
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()

        for i, line in enumerate(lines):
            line_stripped = line.strip()

            # 1. Scene Decoupling
            if "get_parent().get_parent()" in line_stripped or "get_node(\"../" in line_stripped:
                report["Scene Decoupling & Signal Auditing"].append(f"**{filepath}**: Line {i+1} uses relative path traversing up the tree (`{line_stripped}`). This is tightly coupled. Replace with an Event Bus or Signal.")

            # 2. Developer Experience (API Review)
            # Only check public funcs (not starting with _)
            if line_stripped.startswith("func ") and not line_stripped.startswith("func _"):
                match = api_name_regex.match(line_stripped)
                if match:
                    func_name = match.group(1)
                    report["Developer Experience (API Review)"].append(f"**{filepath}**: Public function `{func_name}` does not follow Godot's standard `snake_case` naming convention. Consider renaming for a better developer experience.")

            if line_stripped.startswith("var "):
                match = api_var_regex.match(line_stripped)
                if match:
                    var_name = match.group(1)
                    report["Developer Experience (API Review)"].append(f"**{filepath}**: Public variable `{var_name}` uses PascalCase. Standardize to `snake_case`.")

            # 3. Memory and Resource Management
            # Finding synchronous load() inside functions (not at class level)
            if "load(" in line_stripped and not "preload(" in line_stripped and not line_stripped.startswith("var ") and not line_stripped.startswith("const "):
                if "ResourceLoader.load(" in line_stripped or "load(\"res://" in line_stripped:
                    report["Memory and Resource Management"].append(f"**{filepath}**: Line {i+1} uses synchronous `load()` dynamically during execution (`{line_stripped}`). This will cause frame drops. Move to `preload()` at the top of the script or use background loading.")

            # 4. Null Safety
            # Looking for unsafe chaining like get_collider().method()
            if ".get_collider()." in line_stripped or "get_parent()." in line_stripped or "get_node(" in line_stripped and ").method" in line_stripped:
                # A simple heuristic: if they call a method right after a getter that could return null
                if re.search(r'(get_collider|get_parent|get_node|get_tree)\(.*?\)[\.\w]+\(', line_stripped):
                    # Check if there is an 'if' checking for null on the same line or line before (rough heuristic)
                    if not "if " in line_stripped:
                        report["Edge Cases and Null Safety"].append(f"**{filepath}**: Line {i+1} performs unsafe chaining (`{line_stripped}`). If the node/collider is missing, this will crash. Verify with `if is_instance_valid(node):` or `if node != null:` before calling.")

    except Exception as e:
        print(f"Error reading {filepath}: {e}")

# 5. State Management
# Check project.godot for Autoloads
try:
    with open("project.godot", "r") as f:
        content = f.read()
        if "[autoload]" in content:
            autoloads_section = content.split("[autoload]")[1].split("[")[0].strip()
            if autoloads_section:
                report["State Management"].append(f"**Current Autoloads Detected:**\n```ini\n{autoloads_section}\n```")
                report["State Management"].append("**Feedback:** The project currently uses singletons/autoloads which is good for data persistence. Ensure that save data, player inventory, and progression states are centralized in a dedicated `SaveManager` or `GameState` Autoload to prevent data loss across scene transitions.")
            else:
                report["State Management"].append("**Feedback:** The `project.godot` file has an `[autoload]` section but it seems empty or improperly formatted. It is highly recommended to implement a unified Autoload/Singleton state manager for preserving player state and game events across scenes.")
        else:
            report["State Management"].append("**Feedback:** No `[autoload]` section found in `project.godot`. A unified Autoload/Singleton state manager is heavily needed to manage persistent state across level loads without data loss.")
except Exception as e:
    print(f"Error reading project.godot: {e}")


with open("extended_report.json", "w") as f:
    json.dump(report, f)

print("Extended analysis complete.")
