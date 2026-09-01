import re

with open("test/unit/test_teleport.gd", "r") as f:
    content = f.read()

# Fix !is_inside_tree() errors for global_transform
# Wait, why was there an error? `_target_portal.global_transform.origin = Vector3(10, 20, 30)` BEFORE `add_child(_target_portal)`!
# Also, in test_non_player_enters_teleport, other_body is set `global_transform` BEFORE `add_child`.
# And in before_each, `_player.global_transform` is set BEFORE `add_child`.
# We need to swap the order of add_child and global_transform / global_position assignments!

content = re.sub(
    r'_target_portal\.global_transform\.origin = Vector3\(10, 20, 30\)\n\s+add_child\(_target_portal\)',
    r'add_child(_target_portal)\n\t_target_portal.global_transform.origin = Vector3(10, 20, 30)',
    content
)

content = re.sub(
    r'_player\.global_transform\.origin = Vector3\.ZERO\n\s+add_child\(_player\)',
    r'add_child(_player)\n\t_player.global_transform.origin = Vector3.ZERO',
    content
)

content = re.sub(
    r'other_body\.global_transform\.origin = Vector3\.ZERO\n\s+add_child\(other_body\)',
    r'add_child(other_body)\n\tother_body.global_transform.origin = Vector3.ZERO',
    content
)

with open("test/unit/test_teleport.gd", "w") as f:
    f.write(content)
