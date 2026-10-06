var _are_equal: bool = false
var are_equal: Variant = false :
	get:
		return get_are_equal()
	set(val):
		set_are_equal(val)

var _summary: Variant = null
var summary: Variant = null :
	get:
		return get_summary()
	set(val):
		set_summary(val)

var _max_differences: int = 30
var max_differences: Variant = 30 :
	get:
		return get_max_differences()
	set(val):
		set_max_differences(val)

var _differences: Dictionary = {}
var differences :
	get:
		return get_differences()
	set(val):
		set_differences(val)

func _block_set(which: Variant, val: Variant) -> void:
	push_error(str('cannot set ', which, ', value [', val, '] ignored.'))

func _to_string() -> String:
	return str(get_summary()) # could be null, gotta str it.

func get_are_equal() -> Variant:
	return _are_equal

func set_are_equal(r_eq: Variant) -> void:
	_are_equal = r_eq

func get_summary() -> Variant:
	return _summary

func set_summary(smry: Variant) -> void:
	_summary = smry

func get_total_count() -> void:
	pass

func get_different_count() -> void:
	pass

func get_short_summary() -> Variant:
	return summary

func get_max_differences() -> Variant:
	return _max_differences

func set_max_differences(max_diff: Variant) -> void:
	_max_differences = max_diff

func get_differences() -> Variant:
	return _differences

func set_differences(diffs: Variant) -> void:
	_block_set('differences', diffs)

func get_brackets() -> Variant:
	return null

