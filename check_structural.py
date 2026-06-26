import os
import subprocess

find_cmd = 'find . -name "*.gd" | grep -v "addons/" | grep -iv "player_old.gd" | grep -iv "playerENUM_TEST.gd"'
result = subprocess.run(find_cmd, shell=True, capture_output=True, text=True)
gd_files = [f for f in result.stdout.strip().split('\n') if f]

signal_files = []
direct_ref_files = []

for filepath in gd_files:
    with open(filepath, 'r') as f:
        content = f.read()
        if "emit_signal" in content or "signal " in content:
            signal_files.append(filepath)

        # very simple heuristic for cross-node calls without signals
        if ".get_node(" in content and "emit_signal" not in content and "connect" not in content:
            direct_ref_files.append(filepath)

print(f"Files using signals: {len(signal_files)}")
print(f"Files using direct refs: {len(direct_ref_files)}")
