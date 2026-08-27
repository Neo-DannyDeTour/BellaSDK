# Architecture Journal

- Always verify docstrings explicitly encapsulate internal class references with `[ClassName]` when formatting BBCode comments for Godot APIs.
- Some Python regex replacements using `\bClass\b` could miss if previously styled improperly. Better to write robust parsers to check for GDScript variable boundaries rather than brute force.
- The `##` class description must always immediately precede `class_name`. If `class_name` is on line 1, it must be the first line of the file after any `@tool` annotations.
- `gdformat` enforces correct line lengths and indentations but will not automatically fix incorrectly ordered structures (`class_name` below `extends` if `extends` has no docs).
- **CRITICAL:** Do not add `class_name` to files that act as Godot Autoload Singletons. Adding a `class_name` to a singleton will cause parser conflicts where Godot treats the singleton as a static class type, breaking scripts that call its non-static methods directly using the singleton name (e.g., `GestureInputManager.is_action_just_triggered()`).
- When documenting GDScript methods with `##`, explicitly document all parameters (using `@param param_name description`) and return values to satisfy strict project documentation standards.
- To resolve Godot 4 compilation errors when accessing properties on generic types like `Node3D` (due to strict static typing), use dynamic access via `.get("property")` (e.g., `bool(body.get("noclip"))`) instead of direct member calls.
