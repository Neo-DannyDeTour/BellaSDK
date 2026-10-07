@tool
# ------------------------------------------------------------------------------
# Static
# ------------------------------------------------------------------------------
static var usage_counter: Variant = load("res://addons/gut/thing_counter.gd").new()
static var WarningsManager: Variant = load("res://addons/gut/warnings_manager.gd")


static func load_all() -> void:
	for key in usage_counter.things:
		key.get_loaded()


static func print_usage() -> void:
	for key in usage_counter.things:
		print(key._path, "  (", usage_counter.things[key], ")")


static func clear() -> void:
	usage_counter.things.clear()


# ------------------------------------------------------------------------------
# Class
# ------------------------------------------------------------------------------
var _loaded: Variant = null
var _path: Variant = null


func _init(path: Variant) -> void:
	_path = path
	usage_counter.add_thing_to_count(self)


func get_loaded() -> Variant:
	if _loaded == null:
		_loaded = WarningsManager.load_script_ignoring_all_warnings(_path)
	usage_counter.add(self)
	return _loaded
