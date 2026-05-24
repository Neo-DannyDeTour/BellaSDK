import os
import re

def to_screaming_snake_case(name):
    # Convert something like MyConst or my_const to MY_CONST
    s1 = re.sub('([a-z0-9])([A-Z])', r'\1_\2', name)
    return s1.upper()

def get_line_type(lines_block):
    # Use the first non-comment/annotation/blank line to determine type
    s = ""
    for l in lines_block:
        ls = l.strip()
        if not ls or ls.startswith('#'):
            continue
        if ls.startswith('@'):
            if ls == '@onready' or ls.startswith('@export') or ls == '@tool':
                pass # let it be evaluated by the actual var/class line
            else:
                pass
        s = ls
        if s: break

    if not s:
        # Just comments/blanks
        return 'comment'

    if s.startswith('@tool'): return 'tool'
    if s.startswith('class_name '): return 'class_name'
    if s.startswith('extends '): return 'extends'
    if s.startswith('signal '): return 'signal'
    if s.startswith('enum ') or s.startswith('enum{') or s.startswith('enum\n'): return 'enum'
    if s.startswith('const '): return 'const'

    for l in lines_block:
        ls = l.strip()
        if ls.startswith('@tool'): return 'tool'
        if ls.startswith('class_name '): return 'class_name'
        if ls.startswith('extends '): return 'extends'
        if ls.startswith('signal '): return 'signal'
        if ls.startswith('enum ') or ls.startswith('enum{') or ls.startswith('enum\n'): return 'enum'
        if ls.startswith('const '): return 'const'
        if ls.startswith('@export') or ls.startswith('@export_'): return 'export'
        if ls.startswith('@onready'): return 'onready'
        if ls.startswith('var ') or ls.startswith('static var '):
            m = re.search(r'(?:static\s+)?var\s+(_\w+)', ls)
            if m: return 'private_var'
            else: return 'public_var'

    return 'code'

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    lines = content.split('\n')
    header_lines = []
    body_lines = []

    in_header = True
    for line in lines:
        if in_header:
            if re.match(r'^(func|class)\b', line) and not line.startswith('class_name '):
                in_header = False
                body_lines.append(line)
            else:
                header_lines.append(line)
        else:
            body_lines.append(line)

    while header_lines and header_lines[-1].strip() == '':
        header_lines.pop()

    if not header_lines:
        return

    blocks = []
    current_block_lines = []
    paren_count = brack_count = brace_count = 0
    in_multiline_string = False
    quote_char = None

    def update_counts(line):
        nonlocal paren_count, brack_count, brace_count, in_multiline_string, quote_char
        i = 0
        while i < len(line):
            c = line[i]
            if c == '\\':
                i += 2
                continue

            if in_multiline_string:
                if line[i:i+3] == quote_char*3:
                    in_multiline_string = False
                    quote_char = None
                    i += 3
                    continue
            else:
                if line[i:i+3] == '"""' or line[i:i+3] == "'''":
                    in_multiline_string = True
                    quote_char = line[i]
                    i += 3
                    continue

                if c in ('"', "'"):
                    str_char = c
                    i += 1
                    while i < len(line):
                        if line[i] == '\\':
                            i += 2
                            continue
                        if line[i] == str_char:
                            break
                        i += 1
                    i += 1
                    continue

                if c == '(': paren_count += 1
                elif c == ')': paren_count -= 1
                elif c == '[': brack_count += 1
                elif c == ']': brack_count -= 1
                elif c == '{': brace_count += 1
                elif c == '}': brace_count -= 1
            i += 1

    for line in header_lines:
        is_continuation = False
        if paren_count > 0 or brack_count > 0 or brace_count > 0 or in_multiline_string:
            is_continuation = True
        elif current_block_lines and current_block_lines[-1].strip().endswith('\\'):
            is_continuation = True
        elif current_block_lines and line.startswith('\t') and get_line_type(current_block_lines) not in ('blank', 'comment', 'code'):
            is_continuation = True
        elif current_block_lines:
            last_line = current_block_lines[-1].strip()
            if last_line in ('@onready', '@export', '@tool') or last_line.startswith('@export'):
                is_continuation = True

        if is_continuation:
            current_block_lines.append(line)
            update_counts(line)
        else:
            if current_block_lines:
                blocks.append(current_block_lines)
            current_block_lines = [line]
            update_counts(line)

    if current_block_lines:
        blocks.append(current_block_lines)

    final_blocks = []
    buffer = []

    for block in blocks:
        lt = get_line_type(block)
        if lt in ('blank', 'comment', 'code'):
            buffer.extend(block)
        else:
            final_blocks.append({'type': lt, 'lines': buffer + block, 'idx': len(final_blocks)})
            buffer = []

    if buffer:
        final_blocks.append({'type': 'leftover', 'lines': buffer, 'idx': len(final_blocks)})

    for fb in final_blocks:
        if fb['type'] == 'const':
            for j in range(len(fb['lines'])):
                l = fb['lines'][j]
                if l.strip().startswith('const '):
                    m = re.match(r'^(\s*const\s+)([a-zA-Z0-9_]+)(.*)', l)
                    if m:
                        prefix, name, suffix = m.groups()
                        new_name = to_screaming_snake_case(name)
                        fb['lines'][j] = f"{prefix}{new_name}{suffix}"

    order = {
        'tool': 1,
        'class_name': 2,
        'extends': 3,
        'signal': 4,
        'enum': 5,
        'const': 6,
        'export': 7,
        'public_var': 8,
        'private_var': 9,
        'onready': 10,
        'leftover': 11
    }

    final_blocks.sort(key=lambda b: (order.get(b['type'], 99), b['idx']))

    new_header_lines = []
    for b in final_blocks:
        new_header_lines.extend(b['lines'])

    while new_header_lines and new_header_lines[-1].strip() == '':
        new_header_lines.pop()

    cleaned_header_lines = []
    prev_was_blank = False
    for line in new_header_lines:
        if line.strip() == '':
            if not prev_was_blank:
                cleaned_header_lines.append(line)
                prev_was_blank = True
        else:
            cleaned_header_lines.append(line)
            prev_was_blank = False

    new_header_lines = cleaned_header_lines

    if body_lines:
        new_header_lines.extend(['', ''])

    new_content = '\n'.join(new_header_lines + body_lines)
    if content.endswith('\n') and not new_content.endswith('\n'):
        new_content += '\n'

    if content != new_content:
        with open(filepath, 'w') as f:
            f.write(new_content)

import subprocess
res = subprocess.run('find . -name "*.gd" -not -path "./addons/*"', shell=True, capture_output=True, text=True)
for file in res.stdout.strip().split('\n'):
    if os.path.exists(file):
        process_file(file)

print("Done!")
