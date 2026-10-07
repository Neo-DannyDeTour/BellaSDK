var parameter_stubs: Variant = GutUtils.Stubs.new()
var action_stubs: Variant = GutUtils.Stubs.new()

var _lgr: Variant = GutUtils.get_logger()
var _strutils: Variant = GutUtils.Strutils.new()
# Since StubParams can be chained, add_params does not get the completely
# configured instance.  All stubs are added to this cache first, then whenever
# a retrieval is attempted the cache is flushed into parameter_stubs and
# action_stubs.  This was introduced because it was easier to keep parameter
# defaults separate from action stubs.  The only way to do that though is to
# parse the stubs after they have been added.
var _stub_cache: Array = []


func _flush_cache() -> void:
	for stub_params in _stub_cache:
		stub_params.logger = _lgr

		if stub_params.is_defaults_override():
			parameter_stubs.add_stub(stub_params)

		if !stub_params.is_default_override_only():
			action_stubs.add_stub(stub_params)

		if !stub_params.is_script_default:
			stub_params.validate()
		# lock the params so that any changes that would affect which bucket
		# the params were put in can't be changed.
		stub_params.locked = true
	_stub_cache.clear()


# Searches returns for an entry that matches the instance or the class that
# passed in obj is.
#
# obj can be an instance, class, or a path.
func _find_action_stub(obj: Variant, method: Variant, parameters: Variant = null) -> Variant:
	_flush_cache()

	var to_return: Variant = null
	var matches: Variant = action_stubs.get_all_stubs(obj, method)
	var param_match: Variant = null
	var null_match: Variant = null
	var default_match: Variant = null

	if matches.size() == 0:
		return null

	for i in range(matches.size()):
		var cur_stub: Variant = matches[i]
		if cur_stub.is_script_default:
			default_match = cur_stub
		elif cur_stub.parameters == parameters:
			param_match = cur_stub
		elif (
			cur_stub._method_meta != {}
			and cur_stub.parameters != null
			and cur_stub.parameters.size() < cur_stub._method_meta.args.size()
		):
			var params: Variant = cur_stub.parameters
			var defaults: Variant = get_parameter_defaults(obj, method)
			if params != null:
				if defaults != null:
					for j in range(params.size() - 1, defaults.size() - params.size()):
						params.append(defaults[j + 1])
				else:
					pass
					# print("NO DEFAULTS for ", obj, '.', method)
			if params == cur_stub.parameters:
				param_match = cur_stub
		elif cur_stub.parameters == null and !cur_stub.is_default_override_only():
			null_match = cur_stub

	if default_match != null:
		to_return = default_match

	# We have matching parameter values so return the stub value for that
	if param_match != null:
		to_return = param_match
	# We found a case where the parameters were not specified so return
	# parameters for that.  Only do this if the null match is not *just*
	# a paramerter override stub.
	elif null_match != null:
		to_return = null_match

	return to_return


# ##############
# Public
# ##############


func add_stub(stub_params: Variant) -> void:
	if typeof(stub_params.stub_target) == TYPE_STRING:
		if !FileAccess.file_exists(stub_params.stub_target):
			return

	_stub_cache.append(stub_params)


# It will use the optional list of parameter values to find a value.  If
# the object was stubbed with no parameters than any parameters will match.
# If it was stubbed with specific parameter values then it will try to match.
# If the parameters do not match BUT there was also an empty parameter list stub
# then it will return those.
# If it cannot find anything that matches then null is returned.
#
# Parameters
# obj:  this should be an instance of a doubled object.
# method:  the method name
# parameters:  optional array of parameter vales to find a return value for.
func get_return(obj: Variant, method: Variant, parameters: Variant = null) -> Variant:
	var stub_info: Variant = _find_action_stub(obj, method, parameters)
	if stub_info != null:
		return stub_info.return_val
	else:
		var default: Variant = parameter_stubs.get_default_stub(obj, method)
		var to_return: Variant = null
		if default != null:
			# This ensures that the values are unique and that any changes made
			# to them in a test are not propigated to future calls of the same
			# method.
			to_return = GutConstants.get_default_return_value(default.return_type)
		_lgr.info(
			str(
				"Call to [",
				method,
				"] was not stubbed for the supplied parameters ",
				parameters,
				".  [",
				to_return,
				"] was returned."
			)
		)
		return to_return


func should_call_super(obj: Variant, method: Variant, parameters: Variant = null) -> Variant:
	var stub_info: Variant = _find_action_stub(obj, method, parameters)

	var is_partial: bool = false
	if typeof(obj) != TYPE_STRING:  # some stubber tests test with strings
		is_partial = obj.__gutdbl.is_partial
	var should: Variant = is_partial

	if stub_info != null:
		should = stub_info.call_super
	elif !is_partial:
		# this log message is here because of how the generated doubled scripts
		# are structured.  With this log msg here, you will only see one
		# "unstubbed" info instead of multiple.
		_lgr.info("Unstubbed call to " + method + "::" + _strutils.type2str(obj))
		should = false

	return should


func get_call_this(obj: Variant, method: Variant, parameters: Variant = null) -> Variant:
	var stub_info: Variant = _find_action_stub(obj, method, parameters)

	if stub_info != null:
		return stub_info.call_this


func get_parameter_defaults(obj: Variant, method: Variant) -> Variant:
	_flush_cache()
	var the_defaults: Array = []
	var script_defaults: Array = []
	var matches: Variant = parameter_stubs.get_all_stubs(obj, method)

	var i: Variant = matches.size() - 1
	while i >= 0 and the_defaults.is_empty():
		if matches[i].is_defaults_override():
			if matches[i].is_script_default:
				script_defaults = matches[i].parameter_defaults
			else:
				the_defaults = matches[i].parameter_defaults
		i -= 1

	if the_defaults.is_empty() and !script_defaults.is_empty():
		the_defaults = script_defaults
	return the_defaults


func get_default_value(obj: Variant, method: Variant, p_index: Variant) -> Variant:
	var the_defaults: Variant = get_parameter_defaults(obj, method)
	var to_return: Variant = null
	if the_defaults != null and the_defaults.size() > p_index:
		to_return = the_defaults[p_index]
	return to_return


func clear() -> void:
	_stub_cache.clear()
	if parameter_stubs != null:
		parameter_stubs.clear()
	if action_stubs != null:
		action_stubs.clear()


func get_logger() -> Variant:
	return _lgr


func set_logger(logger: Variant) -> void:
	_lgr = logger


func to_s() -> Variant:
	return str(
		"Parameter Stubs:\n", parameter_stubs.to_s(), "\nAction Stubs:\n", action_stubs.to_s()
	)


func stub_defaults_from_meta(target: Variant, method_meta: Variant) -> void:
	var params: Variant = GutUtils.StubParams.new(target, method_meta)
	params.is_script_default = true
	add_stub(params)
