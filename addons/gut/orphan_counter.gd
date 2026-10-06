# ------------------------------------------------------------------------------
# It keeps track of the orphans...so this is best name it could ever have.
# ------------------------------------------------------------------------------
class GutOrphanage:
	const UNGROUPED: String = "Outside Tests"
	const SUBGROUP_SEP: String = '->'

	var orphan_ids: Dictionary = {}
	var oprhans_by_group: Dictionary = {}
	var strutils: Variant = GutUtils.Strutils.new()

	# wrapper for stubbing
	func _get_system_orphan_node_ids() -> Variant:
		return Node.get_orphan_node_ids()


	func _make_group_key(group: Variant = null, subgroup: Variant = null) -> Variant:
		var to_return: Variant = UNGROUPED
		if(group != null):
			to_return = group

		if(subgroup == null):
			to_return += str(SUBGROUP_SEP, UNGROUPED)
		else:
			to_return += str(SUBGROUP_SEP, subgroup)

		return to_return


	func _add_orphan_by_group(id: Variant, group: Variant, subgroup: Variant) -> void:
		var key: Variant = _make_group_key(group, subgroup)
		if(oprhans_by_group.has(key)):
			oprhans_by_group[key].append(id)
		else:
			oprhans_by_group[key] = [id]


	func process_orphans(group: Variant = null, subgroup: Variant = null) -> Variant:
		var new_orphans: Array = []
		for orphan_id in _get_system_orphan_node_ids():
			if(!orphan_ids.has(orphan_id)):
				new_orphans.append(orphan_id)
				orphan_ids[orphan_id] = {
					"group":GutUtils.nvl(group, UNGROUPED),
					"subgroup":GutUtils.nvl(subgroup, UNGROUPED),
					"instance":instance_from_id(orphan_id)
				}
				_add_orphan_by_group(orphan_id, group, subgroup)

		return new_orphans


	func get_orphan_ids(group: Variant = null, subgroup: Variant = null) -> Variant:
		var key: Variant = _make_group_key(group, subgroup)
		return oprhans_by_group.get(key, [])


	# Given the likely size, this was way easier than making a dictionary
	# of dictionaries of arrays.
	func get_all_group_orphans(group: Variant) -> Variant:
		var to_return: Array = []
		for key in oprhans_by_group:
			if(key == group or key.begins_with(str(group, SUBGROUP_SEP))):
				to_return.append_array(oprhans_by_group[key])
		return to_return


	# clears out anything that is not still an orphan.
	func clean() -> void:
		oprhans_by_group.clear()
		for key in orphan_ids.keys():
			var inst: Variant = orphan_ids[key].instance
			if(!is_instance_valid(inst) or inst.get_parent() != null and not orphan_ids.has(inst.get_parent().get_instance_id())):
				orphan_ids.erase(key)
			else:
				_add_orphan_by_group(key, orphan_ids[key].group, orphan_ids[key].subgroup)




# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
var _strutils: GutStringUtils = GutStringUtils.new()

var orphanage : GutOrphanage = GutOrphanage.new()
var logger: Variant = GutUtils.get_logger()
var autofree: Variant = GutUtils.AutoFree.new()


func _count_all_children(instance: Variant) -> Variant:
	var count: Variant = instance.get_child_count()
	for child in instance.get_children():
		count += _count_all_children(child)
	return count


func get_orphan_list_text(orphan_ids: Variant) -> Variant:
	var text: String = ""
	for id in orphan_ids:
		var kid_count_text: String = ''
		var inst: Variant = orphanage.orphan_ids[id].instance
		if(is_instance_valid(inst) and inst.get_parent() == null):
			var kid_count: Variant = _count_all_children(inst)
			if(kid_count != 0):
				kid_count_text = str(' + ', kid_count)

			var autofree_text: String = ''
			if(autofree.has_instance_id(id)):
				autofree_text = (" (autofree)")

			if(text != ''):
				text += "\n"
			text += str('* [', _strutils.type2str(inst), ']', kid_count_text, autofree_text)

	return text


func orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func record_orphans(group: Variant, subgroup: Variant = null) -> Variant:
	return orphanage.process_orphans(group, subgroup)


func convert_instance_ids_to_valid_instances(instance_ids: Variant) -> Variant:
	var to_return: Array = []
	for entry in instance_ids:
		if(is_instance_id_valid(entry)):
			to_return.append(instance_from_id(entry))
	return to_return


func end_script(script_path: Variant, should_log: Variant) -> void:
	record_orphans(script_path)
	var orphans: Variant = orphanage.get_all_group_orphans(script_path)
	if(orphans.size() > 0 and should_log):
		logger.orphan(str(orphans.size(), ' orphans'))


func end_test(script_path: Variant, test_name: Variant, should_log: bool = true) -> void:
	record_orphans(script_path, test_name)
	orphanage.clean()
	# Must get all the orphans and not just the results of record_orphans
	# because record_orphans may have been called for this group/subgroup
	# already.
	var orphans: Variant = get_orphan_ids(script_path, test_name)
	if(orphans.size() > 0 and should_log):
		logger.orphan(str(orphans.size(), ' Orphans'))
		logger.inc_indent()
		logger.orphan(get_orphan_list_text(orphans))
		logger.dec_indent()


func get_orphan_ids(group: Variant = null, subgroup: Variant = null) -> Variant:
	var ids: Array = []
	if(group == null):
		ids = orphanage.orphan_ids.keys()
	elif(subgroup == null):
		ids = orphanage.get_all_group_orphans(group)
	else:
		ids = orphanage.get_orphan_ids(group, subgroup)

	return ids


func get_count() -> int:
	return orphan_count()


func log_all() -> void:
	var last_script: String = ''
	var last_test: String = ''

	for id in orphanage.orphan_ids:
		var entry: Variant = orphanage.orphan_ids[id]

		if(last_script != entry.group):
			last_script = entry.group
			last_test = ''
			logger.log(entry.group)

		if(last_test != entry.subgroup):
			logger.inc_indent()
			logger.log(str('- ', entry.subgroup))
			last_test = entry.subgroup
			logger.inc_indent()
			var orphan_ids: Variant = orphanage.get_orphan_ids(last_script, last_test)
			logger.orphan(get_orphan_list_text(orphan_ids))
			logger.dec_indent()
			logger.dec_indent()


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
