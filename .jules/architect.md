# Architect Journal - GDScript Standardization Learnings

## Godot 4 Typing Edge Cases
- **Inline Setters**: When using inline setters with typed exported variables (e.g., `@export var prop: float = 1.0: set(v):`), do not add explicit type hints to the setter parameter (e.g., `set(v: float):`) as it causes parser errors in `gdtoolkit`. The type is inherited automatically.
- **Headless Environment**: The `godot` executable may be missing from the CI/sandbox environment, meaning headless unit tests via GUT cannot be executed. Fall back to strict static linting via `gdlint`.

## Documentation (Godot 4 BBCode)
- Function parameters require the `[param name]` tag.
- Function references require the `[method name]` tag.
- Godot 4's internal documentation generator doesn't natively support a `[return]` BBCode tag; standard practice is to simply write `Returns ...`.

## Refactoring Process
- Be extremely careful when using automated `sed` or `python` replace scripts to add documentation, as it can easily lead to duplicated docstrings. Always verify the output.
