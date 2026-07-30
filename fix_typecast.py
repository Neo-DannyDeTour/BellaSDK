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

                # Check for var my_var : Type = get_node(...) without a cast
                match = re.search(r'var\s+([a-zA-Z0-9_]+)\s*:\s*([a-zA-Z0-9_]+)\s*=\s*(.*?get_node.*?\(.*\))$', line)
                if match:
                    var_type = match.group(2)
                    if var_type != 'Node':
                        # Make sure it doesn't already have 'as Type'
                        if not re.search(r'as\s+' + var_type, line):
                            new_line = line.replace(match.group(3), match.group(3) + f' as {var_type}')
                            lines[i] = new_line
                            changed = True
                            total_replaced += 1

                # Check for _get_first_node_of_type
                match = re.search(r'var\s+([a-zA-Z0-9_]+)\s*:\s*([a-zA-Z0-9_]+)\s*=\s*(.*?_get_first_node_of_type.*?\(.*\))$', line)
                if match:
                    var_type = match.group(2)
                    if var_type != 'Node':
                        if not re.search(r'as\s+' + var_type, line):
                            new_line = line.replace(match.group(3), match.group(3) + f' as {var_type}')
                            lines[i] = new_line
                            changed = True
                            total_replaced += 1

                # Check for get_parent
                match = re.search(r'var\s+([a-zA-Z0-9_]+)\s*:\s*([a-zA-Z0-9_]+)\s*=\s*(.*?get_parent.*?\(.*\))$', line)
                if match:
                    var_type = match.group(2)
                    if var_type != 'Node':
                        if not re.search(r'as\s+' + var_type, line):
                            new_line = line.replace(match.group(3), match.group(3) + f' as {var_type}')
                            lines[i] = new_line
                            changed = True
                            total_replaced += 1

            if changed:
                with open(filepath, 'w') as f:
                    f.writelines(lines)

print(f"Replaced {total_replaced} missing casts")
