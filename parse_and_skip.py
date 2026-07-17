import os
import subprocess

skipped_files = []

# Get list of all GDScript files natively to avoid shell=True command injection risks
gd_files = []
for root, _, files in os.walk("."):
    for file in files:
        if file.endswith(".gd"):
            filepath = os.path.join(root, file)
            # Normalize path separators for consistent filtering
            filepath_forward = filepath.replace(os.sep, "/")

            # Apply filters
            if "addons/" in filepath_forward:
                continue

            filepath_lower = filepath_forward.lower()
            if "player_old.gd" in filepath_lower:
                continue
            if "main_menu.gd" in filepath_lower:
                continue
            if "playerenum_test.gd" in filepath_lower:
                continue

            gd_files.append(filepath_forward)

for file in gd_files:

    # Try formatting
    fmt_res = subprocess.run(['gdformat', file], capture_output=True, text=True)
    if fmt_res.returncode != 0:
        skipped_files.append((file, "Formatting failed"))
        subprocess.run(['git', 'checkout', '--', file])
        continue

    # Try linting
    lint_res = subprocess.run(['gdlint', file], capture_output=True, text=True)
    if lint_res.returncode != 0:
        skipped_files.append((file, "Linting failed"))
        subprocess.run(['git', 'checkout', '--', file])
        continue

    # Check for untyped variables (basic check)
    with open(file, 'r') as f:
        content = f.read()
        lines = content.split('\n')
        has_untyped = False
        for line in lines:
            line_stripped = line.strip()
            # Simple heuristic for untyped var, parameter, or for loop variable
            if line_stripped.startswith("var ") and ":" not in line_stripped.split("=")[0] and "var " in line_stripped:
                has_untyped = True
                break
            if line_stripped.startswith("for ") and " in " in line_stripped:
                # check if `for var_name:` is missing `:` after var_name (or rather `: type`)
                parts = line_stripped.split(" in ")
                var_decl = parts[0].replace("for ", "").strip()
                if ":" not in var_decl:
                    has_untyped = True
                    break
            if line_stripped.startswith("func ") and "->" not in line_stripped:
                 # It might be void, check if `-> void` or similar exists
                 if not "->" in line_stripped:
                     has_untyped = True
                     break

        if has_untyped:
            skipped_files.append((file, "Untyped variables or functions found"))
            subprocess.run(['git', 'checkout', '--', file])
            continue

# Output the list of skipped files to a file
with open('skipped_files_run.txt', 'w') as f:
    for file, reason in skipped_files:
        f.write(f"{file}: {reason}\n")

print(f"Processed {len(gd_files)} files. Skipped {len(skipped_files)} files.")
