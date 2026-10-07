extends RefCounted

static var _base_script_text: Variant = GutUtils.get_file_as_text(
	"res://addons/gut/double_templates/script_template.txt"
)
static var _singleton_script_text: Variant = GutUtils.get_file_as_text(
	"res://addons/gut/double_templates/singleton_template.txt"
)
static var _double_data_text: Variant = GutUtils.get_file_as_text(
	"res://addons/gut/double_templates/double_data_template.txt"
)

var _script_collector: Variant = GutUtils.ScriptCollector.new()
var _singleton_parser: Variant = GutUtils.SingletonParser.new()

# used by tests for debugging purposes.
var print_source: bool = false
var inner_class_registry: Variant = GutUtils.inner_class_registry

# ###############
# Properties
# ###############
var _stubber: Variant = GutUtils.Stubber.new()


func get_stubber() -> Variant:
	return _stubber


func set_stubber(stubber: Variant) -> void:
	_stubber = stubber


var _lgr: Variant = GutUtils.get_logger()


func get_logger() -> Variant:
	return _lgr


func set_logger(logger: Variant) -> void:
	_lgr = logger
	_method_maker.set_logger(logger)


var _spy: Variant = null


func get_spy() -> Variant:
	return _spy


func set_spy(spy: Variant) -> void:
	_spy = spy


var _gut: Variant = null


func get_gut() -> Variant:
	return _gut


func set_gut(gut: Variant) -> void:
	_gut = gut


var _strategy: Variant = null


func get_strategy() -> Variant:
	return _strategy


func set_strategy(strategy: Variant) -> void:
	if GutUtils.DOUBLE_STRATEGY.values().has(strategy):
		_strategy = strategy
	else:
		_lgr.error(str("doubler.gd:  invalid double strategy ", strategy))


var _method_maker: Variant = GutUtils.MethodMaker.new()


func get_method_maker() -> Variant:
	return _method_maker


var _ignored_methods: Variant = GutUtils.OneToMany.new()


func get_ignored_methods() -> Variant:
	return _ignored_methods


# ###############
# Private
# ###############
func _init(strategy: Variant = GutUtils.DOUBLE_STRATEGY.SCRIPT_ONLY) -> void:
	set_logger(GutUtils.get_logger())
	_strategy = strategy


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _stubber != null:
			_stubber.clear()


func _get_indented_line(indents: Variant, text: Variant) -> Variant:
	var to_return: String = ""
	for _i in range(indents):
		to_return += "\t"
	return str(to_return, text, "\n")


func _stub_to_call_super(parsed: Variant, method_name: Variant) -> void:
	if !parsed.get_method(method_name).is_eligible_for_doubling():
		return

	var params: Variant = null
	if parsed.is_native:
		params = GutUtils.StubParams.new(parsed._native_class, method_name, parsed.subpath)
	else:
		params = GutUtils.StubParams.new(parsed.script_path, method_name, parsed.subpath)
	params.to_call_super()
	params.is_script_default = true
	_stubber.add_stub(params)


func _get_base_script_text(
	parsed: Variant, override_path: Variant, partial: Variant, included_methods: Variant
) -> Variant:
	var path: Variant = parsed.script_path
	if override_path != null:
		path = override_path

	var stubber_id: int = -1
	if _stubber != null:
		stubber_id = _stubber.get_instance_id()

	var spy_id: int = -1
	if _spy != null:
		spy_id = _spy.get_instance_id()

	var gut_id: int = -1
	if _gut != null:
		gut_id = _gut.get_instance_id()

	var extends_text: Variant = parsed.get_extends_text()
	var double_data_values: Variant = {
		"path": path,
		"subpath": GutUtils.nvl(parsed.subpath, ""),
		"stubber_id": stubber_id,
		"spy_id": spy_id,
		"gut_id": gut_id,
		"singleton_name": "",
		"singleton_id": -1,
		"is_partial": partial,
		"doubled_methods": included_methods,
	}

	var values: Variant = {
		"extends": extends_text,
		"double_data": _double_data_text.format(double_data_values),
	}

	return _base_script_text.format(values)


func _get_singleton_text(
	parsed: Variant, included_methods: Variant, is_partial: Variant
) -> Variant:
	var stubber_id: int = -1
	if _stubber != null:
		stubber_id = _stubber.get_instance_id()

	var spy_id: int = -1
	if _spy != null:
		spy_id = _spy.get_instance_id()

	var gut_id: int = -1
	if _gut != null:
		gut_id = _gut.get_instance_id()

	var double_data_values: Variant = {
		"path": "",
		"subpath": "",
		"stubber_id": stubber_id,
		"spy_id": spy_id,
		"gut_id": gut_id,
		"singleton_name": parsed.singleton_name,
		"singleton_id": parsed.singleton_id,
		"is_partial": is_partial,
		"doubled_methods": included_methods,
	}

	var values: Variant = {
		"extends": "extends RefCounted",
		"double_data": _double_data_text.format(double_data_values),
		"signals": parsed.get_all_signal_text(),
		"constants": parsed.get_all_constants_text(),
		"properties": parsed.get_all_properties_text()
	}

	var src: Variant = _singleton_script_text.format(values)
	return src


func _is_method_eligible_for_doubling(parsed_script: Variant, parsed_method: Variant) -> Variant:
	return (
		!parsed_method.is_accessor()
		and parsed_method.is_eligible_for_doubling()
		and !_ignored_methods.has(parsed_script.resource, parsed_method.meta.name)
	)


# Disable the native_method_override setting so that doubles do not generate
# errors or warnings when doubling with INCLUDE_NATIVE or when a method has
# been added because of param_count stub.
func _create_script_no_warnings(src: Variant) -> Variant:
	var prev_native_override_value: Variant = null
	var native_method_override: String = "debug/gdscript/warnings/native_method_override"
	prev_native_override_value = ProjectSettings.get_setting(native_method_override)
	ProjectSettings.set_setting(native_method_override, 0)

	var DblClass: Variant = GutUtils.create_script_from_source(src)

	ProjectSettings.set_setting(native_method_override, prev_native_override_value)
	return DblClass


func _create_double(
	parsed: Variant, strategy: Variant, override_path: Variant, partial: Variant
) -> Variant:
	var dbl_src: String = ""
	var included_methods: Array = []

	for method in parsed.get_local_methods():
		if _is_method_eligible_for_doubling(parsed, method):
			included_methods.append(method.meta.name)
			dbl_src += _method_maker.get_function_text(method)

	if strategy == GutUtils.DOUBLE_STRATEGY.INCLUDE_NATIVE:
		for method in parsed.get_super_methods():
			if _is_method_eligible_for_doubling(parsed, method):
				included_methods.append(method.meta.name)
				_stub_to_call_super(parsed, method.meta.name)
				dbl_src += _method_maker.get_function_text(method)

	var base_script: Variant = _get_base_script_text(
		parsed, override_path, partial, included_methods
	)
	dbl_src = base_script + "\n\n" + dbl_src

	if print_source:
		var to_print: String = GutUtils.add_line_numbers(dbl_src)
		to_print = to_print.rstrip("\n")
		_lgr.log(str(to_print))

	var DblClass: Variant = _create_script_no_warnings(dbl_src)
	if _stubber != null:
		_stub_method_default_values(parsed)

	if print_source:
		_lgr.log(str("  path | ", DblClass.resource_path, "\n"))

	return DblClass


func _create_singleton_double(singleton: Variant, is_partial: Variant) -> Variant:
	var parsed: Variant = _singleton_parser.parse(singleton)
	var dbl_src: Variant = _get_singleton_text(parsed, parsed.methods_by_name.keys(), is_partial)

	for key in parsed.methods_by_name:
		if !_ignored_methods.has(singleton, key):
			dbl_src += (
				_method_maker.get_function_text(parsed.methods_by_name[key], singleton) + "\n"
			)

	if print_source:
		var to_print: String = GutUtils.add_line_numbers(dbl_src)
		to_print = to_print.rstrip("\n")
		_lgr.log(str(to_print))

	var DblClass: Variant = GutUtils.create_script_from_source(dbl_src)
	if _stubber != null:
		for key in parsed.methods_by_name:
			var meta: Variant = parsed.methods_by_name[key].meta
			if meta != {} and !meta.flags & METHOD_FLAG_VARARG:
				_stubber.stub_defaults_from_meta(singleton, meta)

	return DblClass


func _stub_method_default_values(parsed: Variant) -> void:
	for method in parsed.get_local_methods():
		if (
			method.is_eligible_for_doubling()
			and !_ignored_methods.has(parsed.resource, method.meta.name)
		):
			_stubber.stub_defaults_from_meta(parsed.resource, method.meta)


func _double_scene_and_script(scene: Variant, strategy: Variant, partial: Variant) -> Variant:
	var dbl_bundle: Variant = scene._bundled.duplicate(true)
	var script_obj: Variant = GutUtils.get_scene_script_object(scene)
	# I'm not sure if the script object for the root node of a packed scene is
	# always the first entry in "variants" so this tries to find it.
	var script_index: Variant = dbl_bundle["variants"].find(script_obj)
	var script_dbl: Variant = null

	if script_obj != null:
		if partial:
			script_dbl = _partial_double(script_obj, strategy, scene.get_path())
		else:
			script_dbl = _double(script_obj, strategy, scene.get_path())

	if script_index != -1:
		dbl_bundle["variants"][script_index] = script_dbl

	var doubled_scene: PackedScene = PackedScene.new()
	doubled_scene._set_bundled_scene(dbl_bundle)

	return doubled_scene


func _get_inst_id_ref_str(inst: Variant) -> Variant:
	var ref_str: String = "null"
	if inst:
		ref_str = str("instance_from_id(", inst.get_instance_id(), ")")
	return ref_str


func _parse_script(obj: Variant) -> Variant:
	var parsed: Variant = null

	if GutUtils.is_inner_class(obj):
		if inner_class_registry.has(obj):
			parsed = _script_collector.parse(inner_class_registry.get_base_resource(obj), obj)
		else:
			(
				_lgr
				. error(
					"Doubling Inner Classes requires you register them first.  Call register_inner_classes passing the script that contains the inner class."
				)
			)
	else:
		parsed = _script_collector.parse(obj)

	return parsed


# Override path is used with scenes.
func _double(obj: Variant, strategy: Variant, override_path: Variant = null) -> Variant:
	var parsed: Variant = _parse_script(obj)
	if parsed != null:
		return _create_double(parsed, strategy, override_path, false)


func _partial_double(obj: Variant, strategy: Variant, override_path: Variant = null) -> Variant:
	var parsed: Variant = _parse_script(obj)
	if parsed != null:
		return _create_double(parsed, strategy, override_path, true)


# -------------------------
# Public
# -------------------------


# double a script/object
func double(obj: Variant, strategy: Variant = _strategy) -> Variant:
	return _double(obj, strategy)


func partial_double(obj: Variant, strategy: Variant = _strategy) -> Variant:
	return _partial_double(obj, strategy)


# double a scene
func double_scene(scene: Variant, strategy: Variant = _strategy) -> Variant:
	return _double_scene_and_script(scene, strategy, false)


func partial_double_scene(scene: Variant, strategy: Variant = _strategy) -> Variant:
	return _double_scene_and_script(scene, strategy, true)


func double_gdnative(which: Variant) -> Variant:
	return _double(which, GutUtils.DOUBLE_STRATEGY.INCLUDE_NATIVE)


func partial_double_gdnative(which: Variant) -> Variant:
	return _partial_double(which, GutUtils.DOUBLE_STRATEGY.INCLUDE_NATIVE)


func double_inner(parent: Variant, inner: Variant, strategy: Variant = _strategy) -> Variant:
	var parsed: Variant = _script_collector.parse(parent, inner)
	return _create_double(parsed, strategy, null, false)


func partial_double_inner(
	parent: Variant, inner: Variant, strategy: Variant = _strategy
) -> Variant:
	var parsed: Variant = _script_collector.parse(parent, inner)
	return _create_double(parsed, strategy, null, true)


func double_singleton(obj: Variant) -> Variant:
	return _create_singleton_double(obj, false)


func partial_double_singleton(obj: Variant) -> Variant:
	return _create_singleton_double(obj, true)


func add_ignored_method(obj: Variant, method_name: Variant) -> void:
	_ignored_methods.add(obj, method_name)

# ##############################################################################
#(G)odot (U)nit (T)est class
#
# ##############################################################################
# The MIT License (MIT)
# =====================
#
# Copyright (c) 2025 Tom "Butch" Wesley
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# ##############################################################################
