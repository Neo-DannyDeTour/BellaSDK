var thepath: String = ''
var subpath: String = ''
var singleton_name: Variant = null
var is_partial: Variant = null

var double_ref : WeakRef = null
var stubber_ref : WeakRef = null
var spy_ref : WeakRef = null
var gut_ref : WeakRef = null
var singleton_ref : WeakRef = null
var __gutdbl_values: Dictionary = {}

const NO_DEFAULT_VALUE: String = '!__gut__no__default__value__!'
func _init(double: Variant = null) -> void:
	if(double != null):
		var values: Variant = double.__gutdbl_values
		__gutdbl_values = double.__gutdbl_values
		double_ref = weakref(double)
		thepath = values.thepath
		subpath = values.subpath
		stubber_ref = weakref_from_id(values.stubber)
		spy_ref = weakref_from_id(values.spy)
		gut_ref = weakref_from_id(values.gut)
		singleton_ref = weakref_from_id(values.singleton)
		singleton_name = values.singleton_name
		is_partial = values.is_partial

		if(gut_ref.get_ref() != null):
			gut_ref.get_ref().get_autofree().add_free(double_ref.get_ref())


func _get_stubbed_method_to_call(method_name: Variant, called_with: Variant) -> Variant:
	var method: Variant = stubber_ref.get_ref().get_call_this(double_ref.get_ref(), method_name, called_with)
	if(method != null):
		method = method.bindv(called_with)
		return method
	return method


func weakref_from_id(inst_id: Variant) -> Variant:
	if(inst_id ==  -1):
		return weakref(null)
	else:
		return weakref(instance_from_id(inst_id))


func is_stubbed_to_call_super(method_name: Variant, called_with: Variant) -> Variant:
	if(stubber_ref.get_ref() != null):
		return stubber_ref.get_ref().should_call_super(double_ref.get_ref(), method_name, called_with)
	else:
		return false


func handle_other_stubs(method_name: Variant, called_with: Variant) -> Variant:
	if(stubber_ref.get_ref() == null):
		return

	var method: Variant = _get_stubbed_method_to_call(method_name, called_with)
	if(method != null):
		return await method.call()
	else:
		return stubber_ref.get_ref().get_return(double_ref.get_ref(), method_name, called_with)


func spy_on(method_name: Variant, called_with: Variant) -> void:
	if(spy_ref.get_ref() != null):
		spy_ref.get_ref().add_call(double_ref.get_ref(), method_name, called_with)


func default_val(method_name: Variant, p_index: Variant) -> Variant:
	if(stubber_ref.get_ref() == null):
		return null
	else:
		var result: Variant = stubber_ref.get_ref().get_default_value(double_ref.get_ref(), method_name, p_index)
		return result


func get_singleton() -> Variant:
	var to_return: Variant = singleton_ref.get_ref()
	if(to_return == null):
		push_error("Trying to get a singleton reference on a non-singleton double: ",
			__gutdbl_values.singleton_name, "/", __gutdbl_values.singleton)
	return to_return