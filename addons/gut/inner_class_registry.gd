var _registry: Dictionary = {}


func _create_reg_entry(base_path: Variant, subpath: Variant) -> Variant:
	var to_return: Variant = {
		"base_path": base_path,
		"subpath": subpath,
		"base_resource": load(base_path),
		"full_path": str("'", base_path, "'", subpath)
	}
	return to_return


func _register_inners(base_path: Variant, obj: Variant, prev_inner: String = "") -> void:
	var const_map: Variant = obj.get_script_constant_map()
	var consts: Variant = const_map.keys()
	var const_idx: int = 0

	while const_idx < consts.size():
		var key: Variant = consts[const_idx]
		var thing: Variant = const_map[key]

		if typeof(thing) == TYPE_OBJECT and thing.resource_path == "":
			var cur_inner: Variant = str(prev_inner, ".", key)
			_registry[thing] = _create_reg_entry(base_path, cur_inner)
			_register_inners(base_path, thing, cur_inner)

		const_idx += 1


func register(base_script: Variant) -> void:
	var base_path: Variant = base_script.resource_path
	_register_inners(base_path, base_script)


func get_extends_path(inner_class: Variant) -> Variant:
	if _registry.has(inner_class):
		return _registry[inner_class].full_path
	else:
		return null


# returns the subpath for the inner class.  This includes the leading "." in
# the path.
func get_subpath(inner_class: Variant) -> Variant:
	if _registry.has(inner_class):
		return _registry[inner_class].subpath
	else:
		return ""


func get_base_path(inner_class: Variant) -> Variant:
	if _registry.has(inner_class):
		return _registry[inner_class].base_path


func has(inner_class: Variant) -> Variant:
	return _registry.has(inner_class)


func get_base_resource(inner_class: Variant) -> Variant:
	if _registry.has(inner_class):
		return _registry[inner_class].base_resource


func get_full_path(inner_class: Variant) -> Variant:
	if _registry.has(inner_class):
		var entry: Variant = _registry[inner_class]
		return str(entry.base_path.get_file(), entry.subpath.replace(".", "/"))
	else:
		return "/Unregistered-Inner-Class"


func to_s() -> Variant:
	var text: String = ""
	for key in _registry:
		text += str(key, ": ", _registry[key], "\n")
	return text
