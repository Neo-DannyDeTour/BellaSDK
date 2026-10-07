@tool
var default_script_name_no_extension: String = "gut_dynamic_script"
var default_script_resource_path: String = "res://addons/gut/not_a_real_file/"
var default_script_extension: String = "gd"

var _created_script_count: int = 0


# Creates a loaded script from the passed in source.  This loaded script is
# returned unless there is an error.  When an error occcurs the error number
# is returned instead.
func create_script_from_source(source: Variant, override_path: Variant = null) -> Variant:
	_created_script_count += 1
	var r_path: Variant = str(
		default_script_resource_path,
		default_script_name_no_extension,
		"_",
		_created_script_count,
		".",
		default_script_extension
	)

	if override_path != null:
		r_path = override_path

	var DynamicScript: GDScript = GDScript.new()
	DynamicScript.source_code = source.dedent()
	# The resource_path must be unique or Godot thinks it is trying
	# to load something it has already loaded and generates an error like
	# ERROR: Another resource is loaded from path 'workaround for godot
	# issue #65263' (possible cyclic resource inclusion).
	DynamicScript.resource_path = r_path
	var result: Variant = DynamicScript.reload()
	if result != OK:
		DynamicScript = result

	return DynamicScript
