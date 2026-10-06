class GutEditorPref:
	var gut_pref_prefix: String = 'gut/'
	var pname: String = '__not_set__'
	var default: Variant = null
	var value: String = '__not_set__'
	var _settings: Variant = null

	func _init(n: Variant, d: Variant, s: Variant) -> void:
		pname = n
		default = d
		_settings = s
		load_it()

	func _prefstr() -> Variant:
		var to_return: Variant = str(gut_pref_prefix, pname)
		return to_return

	func save_it() -> void:
		_settings.set_setting(_prefstr(), value)

	func load_it() -> void:
		if(_settings.has_setting(_prefstr())):
			value = _settings.get_setting(_prefstr())
		else:
			value = default

	func erase() -> void:
		_settings.erase(_prefstr())


const EMPTY: String = '-- NOT_SET --'

# -- Editor ONLY Settings --
var output_font_name: Variant = null
var output_font_size: Variant = null
var hide_result_tree: Variant = null
var hide_output_text: Variant = null
var hide_settings: Variant = null
var use_colors: Variant = null	# ? might be output panel
var run_externally: Variant = null
var run_externally_options_dialog_size: Variant = null
var shortcuts_dialog_size: Variant = null
var gut_window_size: Variant = null
var gut_window_on_top: Variant = null


func _init(editor_settings: Variant) -> void:
	output_font_name = GutEditorPref.new('output_font_name', 'CourierPrime', editor_settings)
	output_font_size = GutEditorPref.new('output_font_size', 30, editor_settings)
	hide_result_tree = GutEditorPref.new('hide_result_tree', false, editor_settings)
	hide_output_text = GutEditorPref.new('hide_output_text', false, editor_settings)
	hide_settings = GutEditorPref.new('hide_settings', false, editor_settings)
	use_colors = GutEditorPref.new('use_colors', true, editor_settings)
	run_externally = GutEditorPref.new('run_externally', false, editor_settings)
	run_externally_options_dialog_size = GutEditorPref.new('run_externally_options_dialog_size', Vector2i(-1, -1), editor_settings)
	shortcuts_dialog_size = GutEditorPref.new('shortcuts_dialog_size', Vector2i(-1, -1), editor_settings)
	gut_window_size = GutEditorPref.new('editor_window_size', Vector2i(-1, -1), editor_settings)
	gut_window_on_top = GutEditorPref.new('editor_window_on_top', false, editor_settings)


func save_it() -> void:
	for prop in get_property_list():
		var val: Variant = get(prop.name)
		if(val is GutEditorPref):
			val.save_it()


func load_it() -> void:
	for prop in get_property_list():
		var val: Variant = get(prop.name)
		if(val is GutEditorPref):
			val.load_it()


func erase_all() -> void:
	for prop in get_property_list():
		var val: Variant = get(prop.name)
		if(val is GutEditorPref):
			val.erase()
