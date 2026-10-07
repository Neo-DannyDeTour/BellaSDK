var _params: Variant = null
var _call_count: int = 0
var _logger: Variant = null


func _init(params: Variant = null) -> void:
	_params = params
	_logger = GutUtils.get_logger()
	if typeof(_params) != TYPE_ARRAY:
		_logger.error("You must pass an array to parameter_handler constructor.")
		_params = null


func next_parameters() -> Variant:
	_call_count += 1
	return _params[_call_count - 1]


func get_current_parameters() -> Variant:
	return _params[_call_count]


func is_done() -> Variant:
	var done: bool = true
	if _params != null:
		done = _call_count == _params.size()
	return done


func get_logger() -> Variant:
	return _logger


func set_logger(logger: Variant) -> void:
	_logger = logger


func get_call_count() -> Variant:
	return _call_count


func get_parameter_count() -> Variant:
	return _params.size()
