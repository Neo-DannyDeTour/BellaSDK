var things: Dictionary = {}


func get_unique_count() -> Variant:
	return things.size()


func add_thing_to_count(thing: Variant) -> void:
	if !things.has(thing):
		things[thing] = 0


func add(thing: Variant) -> void:
	if things.has(thing):
		things[thing] += 1
	else:
		things[thing] = 1


func has(thing: Variant) -> Variant:
	return things.has(thing)


func count(thing: Variant) -> Variant:
	var to_return: int = 0
	if things.has(thing):
		to_return = things[thing]
	return to_return


func sum() -> Variant:
	var to_return: int = 0
	for key in things:
		to_return += things[key]
	return to_return


func to_s() -> Variant:
	var to_return: String = ""
	for key in things:
		to_return += str(key, ":  ", things[key], "\n")
	to_return += str("sum: ", sum())
	return to_return


func get_max_count() -> Variant:
	var max_val: Variant = null
	for key in things:
		if max_val == null or things[key] > max_val:
			max_val = things[key]
	return max_val


func add_array_items(array: Variant) -> void:
	for i in range(array.size()):
		add(array[i])
