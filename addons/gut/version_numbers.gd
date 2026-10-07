# ##############################################################################
#
# ##############################################################################
class VerNumTools:
	static func _make_version_array_from_string(v: String) -> Array:
		var parts: Array = Array(v.split("."))
		for i in range(parts.size()):
			var int_val: int = (parts[i] as String).to_int()
			if str(int_val) == parts[i]:
				parts[i] = (parts[i] as String).to_int()
		return parts

	static func make_version_array(v: Variant, min_spots: int = 3) -> Array:
		var to_return: Array = []
		if typeof(v) == TYPE_STRING:
			to_return = _make_version_array_from_string(v)
		elif typeof(v) == TYPE_DICTIONARY:
			return [v.major, v.minor, v.patch]
		elif typeof(v) == TYPE_ARRAY:
			to_return = v

		if to_return.size() < min_spots:
			for i in range(min_spots - to_return.size()):
				to_return.append(0)

		return to_return

	static func make_version_string(version_parts: Variant) -> String:
		var to_return: String = "x.x.x"
		if typeof(version_parts) == TYPE_ARRAY:
			to_return = ".".join(version_parts)
		elif typeof(version_parts) == TYPE_DICTIONARY:
			to_return = str(version_parts.major, ".", version_parts.minor, ".", version_parts.patch)
		elif typeof(version_parts) == TYPE_STRING:
			to_return = str(version_parts)
		return to_return

	static func is_version_gte(version: Variant, required: Variant) -> bool:
		var is_ok: Variant = null
		var v: Variant = make_version_array(version)
		var r: Variant = make_version_array(required)

		var idx: int = 0
		while is_ok == null and idx < v.size() and idx < r.size():
			if v[idx] > r[idx]:
				is_ok = true
			elif v[idx] < r[idx]:
				is_ok = false

			idx += 1

		# still null means each index was the same.
		return GutUtils.nvl(is_ok, true)

	static func is_version_lte(version: Variant, required: Variant) -> bool:
		var is_lt: Variant = null
		var v: Variant = make_version_array(version)
		var r: Variant = make_version_array(required)

		var idx: int = 0

		while is_lt == null and idx < v.size() and idx < r.size():
			if v[idx] < r[idx]:
				is_lt = true
			elif v[idx] > r[idx]:
				is_lt = false

			idx += 1

		# still null means each index was the same.
		return GutUtils.nvl(is_lt, true)

	static func is_version_eq(version: Variant, expected: Variant) -> bool:
		var version_array: Variant = make_version_array(version)
		var expected_array: Variant = make_version_array(expected)

		if expected_array.size() > version_array.size():
			return false

		var is_version: bool = true
		var i: int = 0
		while i < expected_array.size() and i < version_array.size() and is_version:
			if expected_array[i] == version_array[i]:
				i += 1
			else:
				is_version = false

		return is_version

	static func is_godot_version_eq(expected: Variant) -> bool:
		return VerNumTools.is_version_eq(Engine.get_version_info(), expected)

	static func is_godot_version_gte(expected: Variant) -> bool:
		return VerNumTools.is_version_gte(Engine.get_version_info(), expected)


# ##############################################################################
#
# ##############################################################################
var gut_version: String = "0.0.0"


func _init(gut_v: Variant = gut_version) -> void:
	gut_version = gut_v


# ------------------------------------------------------------------------------
# Blurb of text with GUT and Godot versions.
# ------------------------------------------------------------------------------
func get_version_text() -> String:
	var v_info: Dictionary = Engine.get_version_info()
	var gut_version_info: String = str("GUT version:  ", gut_version)
	var godot_version_info: String = str(
		"Godot version:  ",
		v_info.get("major", 0),
		".",
		v_info.get("minor", 0),
		".",
		v_info.get("patch", 0)
	)
	return godot_version_info + "\n" + gut_version_info


func make_godot_version_string() -> String:
	return VerNumTools.make_version_string(Engine.get_version_info())
