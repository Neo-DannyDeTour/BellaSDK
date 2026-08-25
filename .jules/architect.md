# Architecture Journal

- Always verify docstrings explicitly encapsulate internal class references with `[ClassName]` when formatting BBCode comments for Godot APIs.
- Some Python regex replacements using `\bClass\b` could miss if previously styled improperly. Better to write robust parsers to check for GDScript variable boundaries rather than brute force.
- The `##` class description must always immediately precede `class_name`. If `class_name` is on line 1, it must be the first line of the file after any `@tool` annotations.
- `gdformat` enforces correct line lengths and indentations but will not automatically fix incorrectly ordered structures (`class_name` below `extends` if `extends` has no docs).
