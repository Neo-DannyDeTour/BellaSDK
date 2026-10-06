const IGNORE: int = 0
const WARN: int = 1
const ERROR: int = 2


const WARNING_LOOKUP: Variant = {
	IGNORE : 'IGNORE',
	WARN : 'WARN',
	ERROR : 'ERROR'
}

const DIRECTORY_EXCLUDE: int = 0
const DIRECTORY_INCLUDE: int = 1

const GDSCRIPT_WARNING: String = 'debug/gdscript/warnings/'
const DIRECTORY_RULES: String = 'debug/gdscript/warnings/directory_rules'

const GUT_PATH: String = 'res://addons/gut'
const DYNAMIC_FILES_PATH: String = 'res://addons/gut/not_a_real_file'


# ---------------------------------------
# Static
# ---------------------------------------
static var _static_init_called: bool = false
# This is static and set in _static_init so that we can get the current settings as
# soon as possible.
static var _project_warnings : Dictionary = {}

static var _disabled: bool = false
# should never be true, unless it is, but it shouldn't be.  Whatever it is, it
# should stay the same for the entire run.  Read only.
static var disabled: Variant = _disabled:
	get: return _disabled
	set(val):pass

static var project_warnings: Variant = {} :
	get:
		# somehow this gets called before _project_warnings is initialized when
		# loading a project in the editor.  It causes an error stating that
		# duplicate can't be called on nil.  It seems there might be an
		# implicit "get" call happening.  Using push_error I saw a message
		# in this method, but not one from _static_init upon loading the project
		if(_static_init_called):
			return _project_warnings.duplicate()
		else:
			return {}
	set(val): pass


static func _static_init() -> void:
	_project_warnings = create_warnings_dictionary_from_project_settings()
	_static_init_called = true
	if(disabled):
		print("""
		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		!! Warnings Manager has been disabled
		!!
		!! Do not push this up buddy
		!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
		""".dedent())


static func are_warnings_enabled() -> Variant:
	return ProjectSettings.get(str(GDSCRIPT_WARNING, 'enable'))


## Turn all warnings on/off.  Use reset_warnings to restore the original value.
static func enable_warnings(should: bool = true) -> void:
	if(disabled):
		return
	ProjectSettings.set(str(GDSCRIPT_WARNING, 'enable'), should)


static func exclude_gut(should: bool = true) -> void:
	var val: Variant = DIRECTORY_INCLUDE
	if(should):
		val = DIRECTORY_EXCLUDE
	var dir_rules: Variant = ProjectSettings.get(DIRECTORY_RULES)
	dir_rules[GUT_PATH] = val
	ProjectSettings.set(DIRECTORY_RULES, dir_rules)

static func exclude_dynamic_files() -> void:
	var dir_rules: Variant = ProjectSettings.get(DIRECTORY_RULES)
	dir_rules[DYNAMIC_FILES_PATH] = DIRECTORY_EXCLUDE
	ProjectSettings.set(DIRECTORY_RULES, dir_rules)


## Resets warning settings to what they are set to in Project Settings
static func reset_warnings() -> void:
	apply_warnings_dictionary(_project_warnings)



static func set_project_setting_warning(warning_name : String, value : Variant) -> void:
	if(disabled):
		return

	var property_name: Variant = str(GDSCRIPT_WARNING, warning_name)
	# This check will generate a warning if the setting does not exist
	if(property_name in ProjectSettings):
		ProjectSettings.set(property_name, value)


static func apply_warnings_dictionary(warning_values : Dictionary) -> void:
	if(disabled):
		return

	for key in warning_values:
		set_project_setting_warning(key, warning_values[key])


static func create_ignore_all_dictionary() -> Variant:
	return replace_warnings_values(project_warnings, -1, IGNORE)


static func create_warn_all_warnings_dictionary() -> Variant:
	return replace_warnings_values(project_warnings, -1, WARN)


static func replace_warnings_with_ignore(dict: Variant) -> Variant:
	return replace_warnings_values(dict, WARN, IGNORE)


static func replace_errors_with_warnings(dict: Variant) -> Variant:
	return replace_warnings_values(dict, ERROR, WARN)


static func replace_warnings_values(dict: Variant, replace_this: Variant, with_this: Variant) -> Variant:
	var to_return: Variant = dict.duplicate()
	for key in to_return:
		if(typeof(to_return[key]) == TYPE_INT and (replace_this == -1 or to_return[key] == replace_this)):
			to_return[key] = with_this
	return to_return


static func create_warnings_dictionary_from_project_settings() -> Dictionary:
	var props: Variant = ProjectSettings.get_property_list()
	var to_return: Dictionary = {}
	for i in props.size():
		if(props[i].name.begins_with(GDSCRIPT_WARNING)):
			var prop_name: Variant = props[i].name.replace(GDSCRIPT_WARNING, '')
			to_return[prop_name] = ProjectSettings.get(props[i].name)
	return to_return


static func print_warnings_dictionary(which : Dictionary) -> Variant:
	var is_valid: bool = true
	for key in which:
		var value_str: Variant = str(which[key])
		if(_project_warnings.has(key)):
			if(typeof(which[key]) == TYPE_INT):
				if(WARNING_LOOKUP.has(which[key])):
					value_str = WARNING_LOOKUP[which[key]]
				else:
					push_warning(str(which[key], ' is not a valid value for ', key))
					is_valid = false
		else:
			push_warning(str(key, ' is not a valid warning setting'))
			is_valid = false
		var s: Variant = str(key, ' = ', value_str)
		print(s)
	return is_valid


static func load_script_ignoring_all_warnings(path : String) -> Variant:
	return load_script_using_custom_warnings(path, create_ignore_all_dictionary())


static func load_script_using_custom_warnings(path : String, warnings_dictionary : Dictionary) -> Variant:
	var current_warns: Variant = create_warnings_dictionary_from_project_settings()
	apply_warnings_dictionary(warnings_dictionary)
	var s: Variant = load(path)
	apply_warnings_dictionary(current_warns)

	return s
