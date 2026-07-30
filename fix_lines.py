import os
import re

total_replaced = 0
for root, dirs, files in os.walk('.'):
    for file in files:
        if file.endswith('.gd'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                lines = f.readlines()

            changed = False
            for i in range(len(lines)):
                line = lines[i]

                if len(line) > 100 and 'as ' in line and '=' in line and ('get_node' in line or '_get_first_node' in line):
                    match = re.search(r'(\s*var\s+[a-zA-Z0-9_]+\s*:\s*[a-zA-Z0-9_]+\s*=)\s*(.*)', line)
                    if match:
                        prefix = match.group(1)
                        rhs = match.group(2)

                        indent_match = re.match(r'(\s*)', line)
                        indent = indent_match.group(1) if indent_match else ""

                        # Fix parsing by actually using \n not literal backslash n
                        new_line = prefix + ' (\n' + indent + '\t\t' + rhs + '\n' + indent + '\t)\n'
                        lines[i] = new_line
                        changed = True
                        total_replaced += 1

            if changed:
                with open(filepath, 'w') as f:
                    f.writelines(lines)

print(f"Replaced {total_replaced} lines")
