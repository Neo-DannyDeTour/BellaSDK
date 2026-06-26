import os
import subprocess
import re

find_cmd = 'find . -name "*.gd" | grep -v "addons/" | grep -iv "player_old.gd" | grep -iv "playerENUM_TEST.gd"'
result = subprocess.run(find_cmd, shell=True, capture_output=True, text=True)
gd_files = [f for f in result.stdout.strip().split('\n') if f]

report = {
    "Strict Static Typing": [],
    "GDLint Compliance": [],
    "Execution Traceability": [],
    "Performance Bottlenecks": [],
    "Structural Consistency": []
}

def analyze_file(filepath):
    # Linting
    lint_res = subprocess.run(['gdlint', filepath], capture_output=True, text=True)
    if lint_res.returncode != 0:
        errors = lint_res.stdout.split('\n')
        # Extract meaningful error messages, not the whole traceback
        error_msgs = [e.strip() for e in errors if e.strip() and not e.startswith("Linting") and not e.startswith("=")]
        report["GDLint Compliance"].append(f"**{filepath}**: Linting errors - {', '.join(error_msgs[:3])}...")

    with open(filepath, 'r') as f:
        content = f.read()
        lines = content.split('\n')

        has_untyped_func = False
        has_untyped_var = False
        has_missing_print = False

        for i, line in enumerate(lines):
            line_stripped = line.strip()

            # Typing checks
            if line_stripped.startswith("var ") and ":" not in line_stripped.split("=")[0] and "var " in line_stripped:
                has_untyped_var = True
            if line_stripped.startswith("func ") and "->" not in line_stripped:
                 has_untyped_func = True

            # Execution Traceability - specifically checking 'func ' inside player/ directories or player logic
            if "player" in filepath.lower() and line_stripped.startswith("func ") and not line_stripped.startswith("func _ready") and not line_stripped.startswith("func _process") and not line_stripped.startswith("func _physics_process"):
                 # Check next few lines for print()
                 found_print = False
                 for j in range(i+1, min(i+10, len(lines))):
                     if "print(" in lines[j] or "print_debug(" in lines[j] or "print_rich(" in lines[j]:
                         found_print = True
                         break
                     elif lines[j].strip() == "" or lines[j].strip().startswith("#"):
                         continue
                     elif lines[j].strip().startswith("super"):
                         continue
                     else:
                         # Reached actual logic without print
                         if not "print" in content[content.find(line):content.find("func ", content.find(line)+5) if content.find("func ", content.find(line)+5) != -1 else len(content)]:
                            # A rough check if print exists in the function body
                            pass

                 # Better check for missing print in player actions
                 # Just flag it if there's no print anywhere near the function start
                 func_body = ""
                 for j in range(i+1, len(lines)):
                     if lines[j].startswith("func "):
                         break
                     func_body += lines[j] + "\n"
                 if "print(" not in func_body and "print_debug(" not in func_body:
                     has_missing_print = True

            # Performance bottlenecks (get_node in process, heavy loops)
            if ("_process" in content or "_physics_process" in content):
                if line_stripped.startswith("func _process") or line_stripped.startswith("func _physics_process"):
                    # Check body
                    func_body = ""
                    for j in range(i+1, len(lines)):
                        if lines[j].startswith("func "):
                            break
                        func_body += lines[j] + "\n"
                    if "get_node(" in func_body or "$" in func_body:
                         report["Performance Bottlenecks"].append(f"**{filepath}**: Suboptimal node lookup in `_process`/`_physics_process` (use `@onready` instead).")
                    if "for " in func_body:
                         report["Performance Bottlenecks"].append(f"**{filepath}**: Loop in `_process`/`_physics_process` which could impact 60 FPS target.")

        if has_untyped_var:
             report["Strict Static Typing"].append(f"**{filepath}**: Missing static typing for `var` declarations.")
        if has_untyped_func:
             report["Strict Static Typing"].append(f"**{filepath}**: Missing return type for functions (`->`).")
        if has_missing_print:
             report["Execution Traceability"].append(f"**{filepath}**: Missing `print()` statement in player/action function.")

for f in gd_files:
    try:
        analyze_file(f)
    except Exception as e:
        print(f"Error analyzing {f}: {e}")

print("Analysis Complete.")
# Save report to a file so we can format it
import json
with open("report.json", "w") as f:
    json.dump(report, f)
