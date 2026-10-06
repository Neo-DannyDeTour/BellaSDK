# ------------------------------------------------------------------------------
# This class handles calling out to the test parser and maintaining an array of
# collected_script.gd.  This is used for both calling the tests and tracking
# the results of each script and test's execution.
#
# This also handles exporting and importing tests.
# ------------------------------------------------------------------------------
var CollectedScript: Variant = GutUtils.CollectedScript
var CollectedTest: Variant = GutUtils.CollectedTest

var _test_prefix: String = 'test_'
var _test_class_prefix: String = 'Test'

var _lgr: Variant = GutUtils.get_logger()


# Array of CollectedScripts.
var scripts: Array = []


func _does_inherit_from_test(thing: Variant) -> Variant:
	var base_script: Variant = thing.get_base_script()
	var to_return: bool = false
	if(base_script != null):
		var base_path: Variant = base_script.get_path()
		if(base_path == 'res://addons/gut/test.gd'):
			to_return = true
		else:
			to_return = _does_inherit_from_test(base_script)
	return to_return


func _populate_tests(test_script: Variant) -> Variant:
	var script: Variant = test_script.load_script()
	if(script == null):
		print('  !!! ', test_script.path, ' could not be loaded')
		return false

	test_script.is_loaded = true
	var methods: Variant = script.get_script_method_list()
	for i in range(methods.size()):
		var name: Variant = methods[i]['name']
		if(name.begins_with(_test_prefix)):
			var t: CollectedTest = CollectedTest.new()
			t.name = name
			t.arg_count = methods[i]['args'].size()
			test_script.tests.append(t)
			t.collected_script = weakref(test_script)


func _get_inner_test_class_names(loaded: Variant) -> Variant:
	var inner_classes: Array = []
	var const_map: Variant = loaded.get_script_constant_map()
	for key in const_map:
		var thing: Variant = const_map[key]
		if(GutUtils.is_gdscript(thing)):
			if(key.begins_with(_test_class_prefix)):
				if(_does_inherit_from_test(thing)):
					inner_classes.append(key)
				else:
					_lgr.warn(str('Ignoring Inner Class ', key,
						' because it does not extend GutTest'))

			# This could go deeper and find inner classes within inner classes
			# but requires more experimentation.  Right now I'm keeping it at
			# one level since that is what the previous version did and there
			# has been no demand for deeper nesting.
			# _populate_inner_test_classes(thing)
	return inner_classes


func _parse_script(test_script: Variant) -> Variant:
	var inner_classes: Array = []
	var scripts_found: Array = []

	var loaded: Variant = GutUtils.WarningsManager.load_script_using_custom_warnings(
		test_script.path,
		GutUtils.warnings_when_loading_test_scripts)

	GutUtils.inner_class_registry.register(loaded)
	if(_does_inherit_from_test(loaded)):
		_populate_tests(test_script)
		scripts_found.append(test_script.path)
		inner_classes = _get_inner_test_class_names(loaded)
	else:
		return []

	for i in range(inner_classes.size()):
		var loaded_inner: Variant = loaded.get(inner_classes[i])
		if(_does_inherit_from_test(loaded_inner)):
			var ts: CollectedScript = CollectedScript.new(_lgr)
			ts.path = test_script.path
			ts.inner_class_name = inner_classes[i]
			_populate_tests(ts)
			scripts.append(ts)
			scripts_found.append(test_script.path + '[' + inner_classes[i] +']')

	return scripts_found


# -----------------
# Public
# -----------------
func add_script(path: Variant) -> Variant:
	# SHORTCIRCUIT
	if(has_script(path)):
		return []

	# SHORTCIRCUIT
	if(!FileAccess.file_exists(path)):
		# This check was added so tests could create dynmaic scripts and add
		# them to be run through gut.  This helps cut down on creating test
		# scripts to be used in test/resources.
		if(ResourceLoader.has_cached(path)):
			_lgr.debug("Using cached version of " + path)
		else:
			_lgr.error('Could not find script:  ' + path)
			return

	var ts: CollectedScript = CollectedScript.new(_lgr)
	ts.path = path
	# Append right away because if we don't test_doubler.gd.TestInitParameters
	# will HARD crash.  I couldn't figure out what was causing the issue but
	# appending right away, and then removing if it's not valid seems to fix
	# things.  It might have to do with the ordering of the test classes in
	# the test collecter.  I'm not really sure.
	scripts.append(ts)
	var parse_results: Variant = _parse_script(ts)

	if(parse_results.find(path) == -1):
		_lgr.warn(str('Ignoring script ', path, ' because it does not extend GutTest'))
		scripts.remove_at(scripts.find(ts))

	return parse_results


func clear() -> void:
	scripts.clear()


func has_script(path: Variant) -> Variant:
	var found: bool = false
	var idx: int = 0
	while(idx < scripts.size() and !found):
		if(scripts[idx].get_full_name() == path):
			found = true
		else:
			idx += 1
	return found


func export_tests(path: Variant) -> Variant:
	var success: bool = true
	var f: ConfigFile = ConfigFile.new()
	for i in range(scripts.size()):
		scripts[i].export_to(f, str('CollectedScript-', i))
	var result: Variant = f.save(path)
	if(result != OK):
		_lgr.error(str('Could not save exported tests to [', path, '].  Error code:  ', result))
		success = false
	return success


func import_tests(path: Variant) -> Variant:
	var success: bool = false
	var f: ConfigFile = ConfigFile.new()
	var result: Variant = f.load(path)
	if(result != OK):
		_lgr.error(str('Could not load exported tests from [', path, '].  Error code:  ', result))
	else:
		var sections: Variant = f.get_sections()
		for key in sections:
			var ts: CollectedScript = CollectedScript.new(_lgr)
			ts.import_from(f, key)
			_populate_tests(ts)
			scripts.append(ts)
		success = true
	return success


func get_script_named(name: Variant) -> Variant:
	return GutUtils.search_array(scripts, 'get_filename_and_inner', name)


func get_test_named(script_name: Variant, test_name: Variant) -> Variant:
	var s: Variant = get_script_named(script_name)
	if(s != null):
		return s.get_test_named(test_name)
	else:
		return null


func to_s() -> Variant:
	var to_return: String = ''
	for i in range(scripts.size()):
		to_return += scripts[i].to_s() + "\n"
	return to_return

# ---------------------
# Accessors
# ---------------------
func get_logger() -> Variant:
	return _lgr


func set_logger(logger: Variant) -> void:
	_lgr = logger


func get_test_prefix() -> Variant:
	return _test_prefix


func set_test_prefix(test_prefix: Variant) -> void:
	_test_prefix = test_prefix


func get_test_class_prefix() -> Variant:
	return _test_class_prefix


func set_test_class_prefix(test_class_prefix: Variant) -> void:
	_test_class_prefix = test_class_prefix


func get_scripts() -> Variant:
	return scripts


func get_ran_test_count() -> Variant:
	var count: int = 0
	for s in scripts:
		count += s.get_ran_test_count()
	return count


func get_ran_script_count() -> Variant:
	var count: int = 0
	for s in scripts:
		if(s.was_run):
			count += 1
	return count

func get_test_count() -> Variant:
	var count: int = 0
	for s in scripts:
		count += s.tests.size()
	return count


func get_assert_count() -> Variant:
	var count: int = 0
	for s in scripts:
		count += s.get_assert_count()
	return count


func get_pass_count() -> Variant:
	var count: int = 0
	for s in scripts:
		count += s.get_pass_count()
	return count


func get_fail_count() -> Variant:
	var count: int = 0
	for s in scripts:
		count += s.get_fail_count()
	return count


func get_pending_count() -> Variant:
	var count: int = 0
	for s in scripts:
		count += s.get_pending_count()
	return count

