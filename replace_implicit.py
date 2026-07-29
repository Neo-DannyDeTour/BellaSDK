import sys
import re
import os

with open("inferred_vars.txt", "r") as f:
    inferred = f.readlines()

for line in inferred:
    parts = line.strip().split(':')
    filepath = parts[0]
    line_num = int(parts[1]) - 1

    with open(filepath, "r") as pf:
        content = pf.readlines()

    line_content = content[line_num]

    # Very safe regex to extract the RHS
    match = re.search(r'(\bvar\s+[a-zA-Z0-9_]+\s*):=(.*)', line_content)
    if match:
        rhs = match.group(2).strip()

        t = None
        if rhs.startswith('Vector3('): t = 'Vector3'
        elif rhs.startswith('Vector2('): t = 'Vector2'
        elif rhs.startswith('Color('): t = 'Color'
        elif rhs.startswith('Transform3D('): t = 'Transform3D'
        elif rhs.startswith('Basis('): t = 'Basis'
        elif rhs.startswith('Quaternion('): t = 'Quaternion'
        elif '.new()' in rhs:
            m = re.search(r'([a-zA-Z0-9_]+)\.new\(', rhs)
            if m: t = m.group(1)
        elif 'create_tween()' in rhs: t = 'Tween'
        elif rhs == 'true' or rhs == 'false': t = 'bool'
        elif rhs.startswith('"') or rhs.startswith("'"): t = 'String'
        elif rhs.startswith('['): t = 'Array'
        elif rhs.startswith('{'): t = 'Dictionary'
        elif re.match(r'^-?\d+\.\d+f?$', rhs): t = 'float'
        elif re.match(r'^-?\d+$', rhs): t = 'int'
        elif rhs.endswith('.normalized()'):
            if 'Vector2' in rhs: t = 'Vector2'
            else: t = 'Vector3'
        elif 'get_vector(' in rhs: t = 'Vector2'
        elif 'InputMap.action_get_events' in rhs: t = 'Array[InputEvent]'
        elif '.as_text()' in rhs: t = 'String'
        elif '.split(' in rhs: t = 'PackedStringArray'
        elif 'PhysicsRayQueryParameters3D.create' in rhs: t = 'PhysicsRayQueryParameters3D'
        elif rhs.endswith(' as PlayerLocomotionComponent'): t = 'PlayerLocomotionComponent'
        elif rhs.endswith(' as MonkeyBarVolume'): t = 'MonkeyBarVolume'
        elif rhs.endswith(' as MeshInstance3D'): t = 'MeshInstance3D'
        elif 'to_global(' in rhs: t = 'Vector3'
        elif 'get_world_3d().direct_space_state' in rhs: t = 'PhysicsDirectSpaceState3D'
        elif 'get_point_position(' in rhs: t = 'Vector3'

        if t:
            new_line = re.sub(r':=', f': {t} =', line_content, count=1)
            content[line_num] = new_line
            with open(filepath, "w") as pf:
                pf.writelines(content)
