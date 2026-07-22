import os
import re

def get_all_files(exts):
    files = []
    for root, dirs, filenames in os.walk('.'):
        if '.git' in root or '.jules' in root:
            continue
        for filename in filenames:
            if any(filename.endswith(ext) for ext in exts):
                files.append(os.path.join(root, filename))
    return files

png_wav_files = get_all_files(['.png', '.wav', '.exr', '.gd', '.svg'])
all_files = get_all_files(['.tscn', '.tres', '.gd', '.import', '.material'])

unused = []
for target in png_wav_files:
    target_name = os.path.basename(target)
    if "scan_unused" in target_name:
        continue
    found = False
    for f in all_files:
        if f == target:
            continue
        try:
            with open(f, 'r', encoding='utf-8') as file:
                content = file.read()
                if target_name in content:
                    found = True
                    break
        except:
            pass
    if not found:
        unused.append(target)

print("Possible unused files:")
for u in unused:
    print(u)
