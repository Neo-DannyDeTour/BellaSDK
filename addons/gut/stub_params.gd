var _is_return_override: bool = false
var _is_defaults_override: bool = false
var _is_call_override: bool = false
var _method_meta: Dictionary = {}

var _lgr: Variant = GutUtils.get_logger()
var logger: Variant = _lgr:
	get:
		return _lgr
	set(val):
		_lgr = val

var return_val: Variant = GutConstants.NOT_SET:
	get():
		if GutConstants.is_not_set(return_val):
			return null
		else:
			return return_val
var return_type: Variant = TYPE_NIL
var stub_target: Variant = null
var parameters: Variant = null  # the parameter values to match method call on.
var stub_method: Variant = null
var call_super: bool = false
var call_this: Variant = null
var locked: bool = false

# When this stub is a parameter stub, this indicates that these are the defaults
# defined in the script
# When this stub is an action stub, this indicates it is a default stub added
# by the stubber.  This is currently used to stub native methods to call super
# by default, but still be able to override that stub with any other stub.
var is_script_default: bool = false

var parameter_count: Variant = -1:
	get():
		_lgr.deprecated("parameter count deprecated")
		return -1

# Default values for parameters.  This is used to store default values for
# scripts and to override those values.  I'm not sure if there is a need to
# override them anymore, since I think this was introduced for stubbing vararg
# methods, but you still can for now.  This value should only be used if
# is_defaults_override is true.
var parameter_defaults: Array = []

const NOT_SET: String = "|_1_this_is_not_set_1_|"


func _init(target: Variant = null, method: Variant = null, _subpath: Variant = null) -> void:
	stub_target = target
	stub_method = method

	if typeof(target) == TYPE_CALLABLE:
		stub_target = target.get_object()
		stub_method = target.get_method()
		parameters = target.get_bound_arguments()
		if parameters.size() == 0:
			parameters = null
	elif typeof(target) == TYPE_STRING:
		if target.is_absolute_path():
			stub_target = load(str(target))
		else:
			_lgr.warn(str(target, " is not a valid path"))

	if stub_target is PackedScene:
		stub_target = GutUtils.get_scene_script_object(stub_target)

	# this is used internally to stub default parameters for everything that is
	# doubled...or something.  Look for stub_defaults_from_meta for usage.  This
	# behavior is not to be used by end users.
	if typeof(method) == TYPE_DICTIONARY:
		_method_meta = method
		_load_defaults_from_metadata(method)
		is_script_default = true
	elif stub_target != null and stub_method != null and typeof(stub_target) != TYPE_STRING:
		var method_list: Variant = null
		if typeof(stub_target) == TYPE_OBJECT and stub_target is GDScript:
			method_list = stub_target.get_script_method_list()
		elif !GutUtils.is_native_class(stub_target):
			method_list = stub_target.get_method_list()
		if method_list != null:
			var meta: Variant = GutUtils.find_method_meta(method_list, stub_method)
			if meta != null:
				_method_meta = meta


func _load_defaults_from_metadata(meta: Variant) -> void:
	stub_method = meta.name
	var values: Variant = meta.default_args.duplicate()
	while values.size() < meta.args.size():
		values.push_front(null)

	param_defaults(values)
	return_type = meta.return.type
	return_val = GutConstants.get_default_return_value(meta.return.type)


func _get_method_meta() -> Variant:
	if _method_meta == {} and typeof(stub_target) == TYPE_OBJECT:
		var found_meta: Variant = GutUtils.get_method_meta(stub_target, stub_method)
		if found_meta != null:
			_method_meta = found_meta
	return _method_meta


func _error_if_locked() -> Variant:
	if locked:
		push_error("Cannot change stub as it has been locked.")
		return true
	else:
		return false


func _is_return_value_valid(val: Variant) -> Variant:
	var is_valid: bool = true
	var meta: Variant = _get_method_meta()
	if (
		(
			meta.return.type != 0
			or (meta.return.type == 0 and !(meta.return.usage && PROPERTY_USAGE_NIL_IS_VARIANT))
		)
		and meta.return.type != typeof(return_val)
	):
		is_valid = false
	return is_valid


# -------------------------
# Public
# -------------------------
func validate() -> bool:
	var meta: Variant = _get_method_meta()
	var to_return: bool = true

	if stub_method != "_init" and meta != {} and call_this == null:
		if !_is_return_value_valid(return_val):
			_lgr.error(
				str(
					"Method [",
					stub_method,
					"] was stubbed to return invalid value [",
					return_val,
					"]."
				)
			)
			to_return = false

	return to_return


func to_return(val: Variant) -> Variant:
	if _error_if_locked():
		return
	return_val = val
	call_super = false
	_is_return_override = true

	return self


func to_do_nothing() -> Variant:
	var meta: Variant = _get_method_meta()
	if meta != {}:
		to_return(GutConstants.get_default_return_value(meta.return.type))
	return self


func to_call_super() -> Variant:
	if _error_if_locked():
		return

	call_super = true
	_is_call_override = true
	return self


func to_use_singleton() -> Variant:
	return to_call_super()


func to_call(callable: Callable) -> Variant:
	if _error_if_locked():
		return

	call_this = callable
	_is_call_override = true
	return self


func when_passed(
	p1: Variant = NOT_SET,
	p2: Variant = NOT_SET,
	p3: Variant = NOT_SET,
	p4: Variant = NOT_SET,
	p5: Variant = NOT_SET,
	p6: Variant = NOT_SET,
	p7: Variant = NOT_SET,
	p8: Variant = NOT_SET,
	p9: Variant = NOT_SET,
	p10: Variant = NOT_SET
) -> Variant:
	parameters = [p1, p2, p3, p4, p5, p6, p7, p8, p9, p10]
	var idx: int = 0
	while idx < parameters.size():
		if str(parameters[idx]) == NOT_SET:
			parameters.remove_at(idx)
		else:
			idx += 1
	return self


func param_count(_x: Variant) -> Variant:
	_lgr.deprecated("Stubbing param_count is no longer required or supported.")
	return self


func param_defaults(values: Variant) -> Variant:
	if _error_if_locked():
		return

	var meta: Variant = _get_method_meta()
	if meta != {} and meta.flags & METHOD_FLAG_VARARG:
		_lgr.error("Cannot stub defaults for methods with varargs:  " + meta.name)
	else:
		parameter_defaults = values
		_is_defaults_override = true
	return self


func is_default_override_only() -> Variant:
	return is_defaults_override() and !is_return_override() and !is_call_override()


func is_return_override() -> Variant:
	return _is_return_override


func is_defaults_override() -> Variant:
	return _is_defaults_override


func is_call_override() -> Variant:
	return _is_call_override


func to_s() -> Variant:
	var base_string: Variant = str(stub_target, ".", stub_method)

	if parameter_defaults.size() > 0:
		if is_script_default:
			base_string += " SCRIPT DEFAULTS"
		else:
			base_string += " STUB DEFAULTS"
		base_string += str(" ", parameter_defaults)

	if call_super:
		base_string += " to call SUPER"

	if call_this != null:
		base_string += str(" to call ", call_this)

	if parameters != null:
		base_string += str(" with params (", parameters, ") returns ", return_val)
	else:
		base_string += str(" returns ", return_val)

	return base_string
