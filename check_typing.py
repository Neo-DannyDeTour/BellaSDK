import os
import re

def check_file(filepath):
    missing_vars = []
    missing_funcs = []
    missing_args = []

    with open(filepath, 'r') as f:
        lines = f.readlines()

    for i, line in enumerate(lines):
        line_strip = line.split('#')[0].strip()

        # Check var
        if line_strip.startswith('var ') or line_strip.startswith('@onready var ') or line_strip.startswith('@export var '):
            var_match = re.search(r'\b(?:var)\s+([a-zA-Z0-9_]+)', line)
            if var_match:
                name = var_match.group(1)
                # Check if it has `:`
                if not re.search(r'\b(?:var)\s+' + name + r'\s*:', line):
                    missing_vars.append(f"Line {i+1}: {line.strip()}")

        if line_strip.startswith('const '):
            var_match = re.search(r'\bconst\s+([a-zA-Z0-9_]+)', line)
            if var_match:
                name = var_match.group(1)
                if not re.search(r'\bconst\s+' + name + r'\s*:', line):
                    missing_vars.append(f"Line {i+1}: {line.strip()}")

        # Check func
        func_match = re.search(r'\bfunc\s+([a-zA-Z0-9_]+)\s*\((.*?)\)', line)
        if func_match:
            name = func_match.group(1)
            args = func_match.group(2)

            # Check return type
            if '->' not in line:
                missing_funcs.append(f"Line {i+1}: {line.strip()}")

            # Check args
            if args.strip():
                arg_list = args.split(',')
                for arg in arg_list:
                    if ':' not in arg and arg.strip() != "":
                        missing_args.append(f"Line {i+1}: {line.strip()}")

    return missing_vars, missing_funcs, missing_args

def main():
    total_missing = 0
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.gd'):
                filepath = os.path.join(root, file)
                v, f, a = check_file(filepath)
                if v or f or a:
                    total_missing += len(v) + len(f) + len(a)
                    print(f"File: {filepath}")
                    if v: print("  Missing var type:", v)
                    if f: print("  Missing return type:", f)
                    if a: print("  Missing arg type:", a)
    print(f"Total missing: {total_missing}")

if __name__ == '__main__':
    main()
