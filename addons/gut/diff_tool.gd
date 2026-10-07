extends "res://addons/gut/compare_result.gd"
const INDENT: String = "    "
enum { DEEP, SIMPLE }

var _strutils: Variant = GutUtils.Strutils.new()
var _compare: Variant = GutUtils.Comparator.new()

var _value_1: Variant = null
var _value_2: Variant = null
var _total_count: int = 0
var _diff_type: Variant = null
var _brackets: Variant = null
var _valid: bool = true
var _desc_things: String = "somethings"


# -------- comapre_result.gd "interface" ---------------------
func set_are_equal(val: Variant) -> void:
	_block_set("are_equal", val)


func get_are_equal() -> Variant:
	if !_valid:
		return null
	else:
		return differences.size() == 0


func set_summary(val: Variant) -> void:
	_block_set("summary", val)


func get_summary() -> Variant:
	return summarize()


func get_different_count() -> Variant:
	return differences.size()


func get_total_count() -> Variant:
	return _total_count


func get_short_summary() -> Variant:
	var text: Variant = str(
		_strutils.truncate_string(str(_value_1), 50),
		" ",
		_compare.get_compare_symbol(are_equal),
		" ",
		_strutils.truncate_string(str(_value_2), 50)
	)
	if !are_equal:
		text += str(
			"  ",
			get_different_count(),
			" of ",
			get_total_count(),
			" ",
			_desc_things,
			" do not match."
		)
	return text


func get_brackets() -> Variant:
	return _brackets


# -------- comapre_result.gd "interface" ---------------------


func _invalidate() -> void:
	_valid = false
	differences = null


func _init(v1: Variant, v2: Variant, diff_type: Variant = DEEP) -> void:
	_value_1 = v1
	_value_2 = v2
	_diff_type = diff_type
	_compare.set_should_compare_int_to_float(false)
	_find_differences(_value_1, _value_2)


func _find_differences(v1: Variant, v2: Variant) -> void:
	if GutUtils.are_datatypes_same(v1, v2):
		if typeof(v1) == TYPE_ARRAY:
			_brackets = {"open": "[", "close": "]"}
			_desc_things = "indexes"
			_diff_array(v1, v2)
		elif typeof(v2) == TYPE_DICTIONARY:
			_brackets = {"open": "{", "close": "}"}
			_desc_things = "keys"
			_diff_dictionary(v1, v2)
		else:
			_invalidate()
			GutUtils.get_logger().error("Only Arrays and Dictionaries are supported.")
	else:
		_invalidate()
		GutUtils.get_logger().error("Only Arrays and Dictionaries are supported.")


func _diff_array(a1: Variant, a2: Variant) -> void:
	_total_count = max(a1.size(), a2.size())
	for i in range(a1.size()):
		var result: Variant = null
		if i < a2.size():
			if _diff_type == DEEP:
				result = _compare.deep(a1[i], a2[i])
			else:
				result = _compare.simple(a1[i], a2[i])
		else:
			result = _compare.simple(a1[i], _compare.MISSING, "index")

		if !result.are_equal:
			differences[i] = result

	if a1.size() < a2.size():
		for i in range(a1.size(), a2.size()):
			differences[i] = _compare.simple(_compare.MISSING, a2[i], "index")


func _diff_dictionary(d1: Variant, d2: Variant) -> void:
	var d1_keys: Variant = d1.keys()
	var d2_keys: Variant = d2.keys()

	# Process all the keys in d1
	_total_count += d1_keys.size()
	for key in d1_keys:
		if !d2.has(key):
			differences[key] = _compare.simple(d1[key], _compare.MISSING, "key")
		else:
			d2_keys.remove_at(d2_keys.find(key))

			var result: Variant = null
			if _diff_type == DEEP:
				result = _compare.deep(d1[key], d2[key])
			else:
				result = _compare.simple(d1[key], d2[key])

			if !result.are_equal:
				differences[key] = result

	# Process all the keys in d2 that didn't exist in d1
	_total_count += d2_keys.size()
	for i in range(d2_keys.size()):
		differences[d2_keys[i]] = _compare.simple(_compare.MISSING, d2[d2_keys[i]], "key")


func summarize() -> Variant:
	var summary: String = ""

	if are_equal:
		summary = get_short_summary()
	else:
		var formatter: Variant = load("res://addons/gut/diff_formatter.gd").new()
		formatter.set_max_to_display(max_differences)
		summary = formatter.make_it(self)

	return summary


func get_diff_type() -> Variant:
	return _diff_type


func get_value_1() -> Variant:
	return _value_1


func get_value_2() -> Variant:
	return _value_2
