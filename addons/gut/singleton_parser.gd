class GutParsedSingleton:
	var methods_by_name: Dictionary = {}
	var enums: Dictionary = {}
	var properties: Dictionary = {}
	var signals: Dictionary = {}
	var singleton_name: String = 'unknown'
	var singleton_id: int = -1
	var base_singleton: Variant = null

	func _init(singleton: Variant) -> void:
		base_singleton = singleton
		var sname: Variant = singleton.get_class()
		singleton_name = sname
		singleton_id = singleton.get_instance_id()

		for method in ClassDB.class_get_method_list(sname, true):
			var pm: Variant = GutUtils.ScriptCollector.GutParsedMethod.new(method)
			methods_by_name[method.name] = pm

		for e in ClassDB.class_get_enum_list(sname, true):
			for c in ClassDB.class_get_enum_constants(sname, e):
				enums[c] = singleton.get(c)

		# Some singletons have integer constants that are not in the enum list.
		# All enum constants appear to be integer constants, but I don't want
		# to assume that will always be true.
		for c in ClassDB.class_get_integer_constant_list(sname, true):
			# just overwrite existing or add, seems faster than checking if it
			# exists first.
			enums[c] = singleton.get(c)

		for p in ClassDB.class_get_property_list(sname, true):
			properties[p.name] = singleton.get(p.name)

		for s in ClassDB.class_get_signal_list(sname, true):
			signals[s.name] = s


	func get_signal_text(signal_meta: Variant) -> Variant:
		var text: String = ""
		for arg in signal_meta.args:
			if(text.length() > 0):
				text += ", "
			text += arg.name

		return str('signal ', signal_meta.name, '(', text, ')')


	func get_all_signal_text() -> Variant:
		var text: String = ''
		for key in signals:
			if(text.length() > 0):
				text += "\n"
			text += get_signal_text(signals[key])
		return text


	func get_all_constants_text() -> Variant:
		var text: String = ""
		for key in enums:
			text += str('const ', key, ' = ', enums[key], "\n")
		return text


	func get_all_properties_text() -> Variant:
		var text: String = ""
		# This defaults values to what the singleton is currently set to.  This was
		# easier than remembering how to turn the defaults in the meta into code.
		# This might be the wrong choice.
		for key in properties:
			# AudioServer had a property in the meta named "Fallback values" and I
			# don't know what it is, so I'm ignoring all properties with a space in
			# the name.
			if(key.find(" ") == -1):
				text += str("var ", key, " = ", singleton_name, ".", key, "\n")
		return text



# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
var singletons: Dictionary = {}

func parse(singleton: Variant) -> Variant:
	if(!singletons.has(singleton)):
		singletons[singleton] = GutParsedSingleton.new(singleton)

	return singletons[singleton]