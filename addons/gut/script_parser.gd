# These methods didn't have flags that would exclude them from being used
# in a double and they appear to break things if they are included.
const BLACKLIST: Variant = [
	'get_script',
	'has_method',
	'_to_string',
]


# ------------------------------------------------------------------------------
# Combines the meta for the method with additional information.
# * flag for whether the method is local
# * adds a 'default' property to all parameters that can be easily checked per
#   parameter
# ------------------------------------------------------------------------------
class GutParsedMethod:
	const NO_DEFAULT: String = '__no__default__'

	var _meta: Dictionary = {}
	var meta: Variant = _meta :
		get: return _meta
		set(val): return;

	var is_local: bool = false
	var args: Array = []
	var return_type_text: String = 'void'

	func _init(metadata: Variant) -> void:
		_meta = metadata
		var start_default: Variant = _meta.args.size() - _meta.default_args.size()
		for i in range(_meta.args.size()):
			var arg: Variant = _meta.args[i]
			# Add a "default" property to the metadata so we don't have to do
			# weird default paramter position math again.
			if(i >= start_default):
				arg['default'] = _meta.default_args[start_default - i]
			else:
				arg['default'] = NO_DEFAULT
			args.append(arg)

		return_type_text = _get_return_type(metadata)

	func _get_return_type(meta: Variant) -> Variant:
		var r_meta: Variant = meta["return"]
		var return_keyword: Variant = GutConstants.TYPE_KEYWORDS[r_meta.type]

		if(r_meta.type != 0):
			return_keyword = return_keyword
		elif(r_meta.usage & PROPERTY_USAGE_NIL_IS_VARIANT != 0):
			return_keyword = 'Variant'
		else:
			return_keyword = 'void'

		return return_keyword


	func is_eligible_for_doubling() -> Variant:
		var has_bad_flag: Variant = _meta.flags & \
			(METHOD_FLAG_OBJECT_CORE | METHOD_FLAG_VIRTUAL | METHOD_FLAG_STATIC)
		return !has_bad_flag and BLACKLIST.find(_meta.name) == -1


	func is_accessor() -> Variant:
		return _meta.name.begins_with('@') and \
			(_meta.name.ends_with('_getter') or _meta.name.ends_with('_setter'))


	func to_s() -> Variant:
		var s: Variant = _meta.name + "("

		for i in range(_meta.args.size()):
			var arg: Variant = _meta.args[i]
			if(str(arg.default) != NO_DEFAULT):
				var val: Variant = str(arg.default)
				if(val == ''):
					val = '""'
				s += str(arg.name, ' = ', val)
			else:
				s += str(arg.name)

			if(i != _meta.args.size() -1):
				s += ', '

		s += ")"
		return s




# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
class GutParsedScript:
	# All methods indexed by name.
	var _methods_by_name: Dictionary = {}

	var _script_path: Variant = null
	var script_path: Variant = _script_path :
		get: return _script_path
		set(val): return;

	var _subpath: Variant = null
	var subpath: Variant = null :
		get: return _subpath
		set(val): return;

	var _resource: Variant = null
	var resource: Variant = null :
		get: return _resource
		set(val): return;


	var _is_native: bool = false
	var is_native: Variant = _is_native:
		get: return _is_native
		set(val): return;

	var _native_methods: Dictionary = {}
	var _native_class_name: String = ""
	var _native_class: Variant = null



	func _init(script_or_inst: Variant, inner_class: Variant = null) -> void:
		var to_load: Variant = script_or_inst

		if(GutUtils.is_native_class(to_load)):
			_resource = to_load
			_is_native = true
			# TODO this could be done with ClassDB instead of making instance.
			var inst: Variant = to_load.new()
			_native_class = to_load
			_native_class_name = inst.get_class()
			_native_methods = inst.get_method_list()
			if(!inst is RefCounted):
				inst.free()
		else:
			if(!script_or_inst is Resource):
				to_load = load(script_or_inst.get_script().get_path())

			_script_path = to_load.resource_path
			if(inner_class != null):
				_subpath = _find_subpath(to_load, inner_class)

			if(inner_class == null):
				_resource = to_load
			else:
				_resource = inner_class
				to_load = inner_class

		_parse_methods(to_load)


	func _print_flags(meta: Variant) -> void:
		print(str(meta.name, ':').rpad(30), str(meta.flags).rpad(4), ' = ', GutUtils.dec2bistr(meta.flags, 10))


	func _get_native_methods(base_type: Variant) -> Variant:
		var to_return: Array = []
		if(base_type != null):
			var source: Variant = str('extends ', base_type)
			var inst: Variant = GutUtils.create_script_from_source(source).new()
			to_return = inst.get_method_list()
			if(! inst is RefCounted):
				inst.free()
		return to_return


	func _parse_methods(thing: Variant) -> void:
		var methods: Array = []
		if(is_native):
			methods = _native_methods.duplicate()
		else:
			var base_type: Variant = thing.get_instance_base_type()
			methods = _get_native_methods(base_type)

		for m in methods:
			var parsed: GutParsedMethod = GutParsedMethod.new(m)
			_methods_by_name[m.name] = parsed
			# _init must always be included so that we can initialize
			# double_tools
			if(m.name == '_init'):
				parsed.is_local = true


		# This loop will overwrite all entries in _methods_by_name with the local
		# method object so there is only ever one listing for a function with
		# the right "is_local" flag.
		if(!is_native):
			methods = thing.get_script_method_list()
			methods.reverse()
			for m in methods:
				var parsed_method: GutParsedMethod = GutParsedMethod.new(m)
				parsed_method.is_local = true
				_methods_by_name[m.name] = parsed_method


	func _find_subpath(parent_script: Variant, inner: Variant) -> Variant:
		var const_map: Variant = parent_script.get_script_constant_map()
		var consts: Variant = const_map.keys()
		var const_idx: int = 0
		var found: bool = false
		var to_return: Variant = null

		while(const_idx < consts.size() and !found):
			var key: Variant = consts[const_idx]
			var const_val: Variant = const_map[key]
			if(typeof(const_val) == TYPE_OBJECT):
				if(const_val == inner):
					found = true
					to_return = key
				else:
					to_return = _find_subpath(const_val, inner)
					if(to_return != null):
						to_return = str(key, '.', to_return)
						found = true

			const_idx += 1

		return to_return


	func get_method(name: Variant) -> Variant:
		return _methods_by_name[name]


	func get_super_method(name: Variant) -> Variant:
		var to_return: Variant = get_method(name)
		if(to_return.is_local):
			to_return = null

		return to_return

	func get_local_method(name: Variant) -> Variant:
		var to_return: Variant = get_method(name)
		if(!to_return.is_local):
			to_return = null

		return to_return


	func get_sorted_method_names() -> Variant:
		var keys: Variant = _methods_by_name.keys()
		keys.sort()
		return keys


	func get_local_method_names() -> Variant:
		var names: Array = []
		for method in _methods_by_name:
			if(_methods_by_name[method].is_local):
				names.append(method)

		return names


	func get_super_method_names() -> Variant:
		var names: Array = []
		for method in _methods_by_name:
			if(!_methods_by_name[method].is_local):
				names.append(method)

		return names


	func get_local_methods() -> Variant:
		var to_return: Array = []
		for key in _methods_by_name:
			var method: Variant = _methods_by_name[key]
			if(method.is_local):
				to_return.append(method)
		return to_return


	func get_super_methods() -> Variant:
		var to_return: Array = []
		for key in _methods_by_name:
			var method: Variant = _methods_by_name[key]
			if(!method.is_local):
				to_return.append(method)
		return to_return


	func get_extends_text() -> Variant:
		var text: Variant = null
		if(is_native):
			text = str("extends ", _native_class_name)
		else:
			text = str("extends '", _script_path, "'")
			if(_subpath != null):
				text += '.' + _subpath
		return text




# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
var scripts: Dictionary = {}


func _get_instance_id(thing: Variant) -> Variant:
	var inst_id: Variant = null

	if(GutUtils.is_native_class(thing)):
		var id_str: Variant = str(thing).replace("<", '').replace(">", '').split('#')[1]
		inst_id = id_str.to_int()
	elif(typeof(thing) == TYPE_STRING):
		if(FileAccess.file_exists(thing)):
			inst_id = load(thing).get_instance_id()
	else:
		inst_id = thing.get_instance_id()

	return inst_id


func parse(thing: Variant, inner_thing: Variant = null) -> Variant:
	var key: int = -1
	if(inner_thing == null):
		key = _get_instance_id(thing)
	else:
		key = _get_instance_id(inner_thing)

	var parsed: Variant = null

	if(key != null):
		if(scripts.has(key)):
			parsed = scripts[key]
		else:
			var obj: Variant = instance_from_id(_get_instance_id(thing))
			var inner: Variant = null
			if(inner_thing != null):
				inner = instance_from_id(_get_instance_id(inner_thing))

			if(obj is Resource or GutUtils.is_native_class(obj)):
				parsed = GutParsedScript.new(obj, inner)
				scripts[key] = parsed

	return parsed

