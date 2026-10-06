## Manages save slot listing, loading, and deletion in the save/load menu.
extends Panel

# --------------------------------------
# CONSTANTS
# --------------------------------------
## Path to user filesystem directory containing persistent save files.
const SAVES_DIR: String = "user://saves/"

# --------------------------------------
# VARIABLES
# --------------------------------------
## Regular expression enforcing alphanumeric and underscore save filenames.
var _save_name_regex: RegEx = RegEx.new()

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
## Container holding dynamically instantiated save slot item controls.
@onready var save_list_container: VBoxContainer = %SaveListContainer

## Hidden prototype control template duplicated for each save file entry.
@onready var save_slot_template: Control = %SaveSlotTemplate


## Compiles name regex, binds visibility signal, and hides initial template.
func _ready() -> void:
	_save_name_regex.compile("^[a-zA-Z0-9_]+$")
	print("UI: Save/Load Panel initialized.")
	if is_instance_valid(save_slot_template):
		save_slot_template.hide()
	visibility_changed.connect(_on_visibility_changed)


## Refreshes displayed save files whenever panel visibility changes to true.
func _on_visibility_changed() -> void:
	if visible:
		_refresh_save_list()


## Validates filename extension and allowed character set for security.
func _is_valid_save_filename(file_name: String) -> bool:
	if not file_name.ends_with(".save"):
		return false
	var base_name: String = file_name.get_basename()
	var result: RegExMatch = _save_name_regex.search(base_name)
	return result != null


## Scans filesystem directory and reconstructs list of save slot entries.
func _refresh_save_list() -> void:
	print("System: Refreshing save slots from directory.")

	if not is_instance_valid(save_list_container):
		return

	for child: Node in save_list_container.get_children():
		if child != save_slot_template:
			child.queue_free()

	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		DirAccess.make_dir_absolute(SAVES_DIR)

	var dir: DirAccess = DirAccess.open(SAVES_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()

		while file_name != "":
			if not dir.current_is_dir() and _is_valid_save_filename(file_name):
				_create_save_slot(file_name)
			file_name = dir.get_next()

		dir.list_dir_end()


## Clones template control, binds action signals, and appends to container.
func _create_save_slot(file_name: String) -> void:
	if not is_instance_valid(save_slot_template):
		return
	if not is_instance_valid(save_list_container):
		return

	var new_slot: Control = save_slot_template.duplicate() as Control
	if not is_instance_valid(new_slot):
		return
	new_slot.show()

	var name_node: Node = new_slot.find_child("SaveNameLabel", true, false)
	var load_node: Node = new_slot.find_child("LoadButton", true, false)
	var del_node: Node = new_slot.find_child("DeleteButton", true, false)

	var name_label: Label = name_node as Label
	var load_btn: Button = load_node as Button
	var del_btn: Button = del_node as Button

	if is_instance_valid(name_label):
		name_label.text = file_name.get_basename()

	if is_instance_valid(load_btn):
		load_btn.pressed.connect(_on_load_pressed.bind(file_name))

	if is_instance_valid(del_btn):
		del_btn.pressed.connect(_on_delete_pressed.bind(file_name))

	save_list_container.add_child(new_slot)


## Triggers save loading via SaveManager autoload for chosen slot name.
func _on_load_pressed(file_name: String) -> void:
	if not _is_valid_save_filename(file_name):
		print("Error: Invalid save file name during load operation: ", file_name)
		return

	print("Player clicked Load for save: ", file_name)
	var path: String = SAVES_DIR + file_name

	if SaveManager.has_method("load_game"):
		SaveManager.load_game(path)


## Deletes save file from filesystem and notifies menu context when empty.
func _on_delete_pressed(file_name: String) -> void:
	if not _is_valid_save_filename(file_name):
		print("Error: Invalid save file name during delete operation: ", file_name)
		return

	print("Player clicked Delete for save: ", file_name)
	var path: String = SAVES_DIR + file_name

	if DirAccess.remove_absolute(path) == OK:
		print("System: Successfully deleted save file: ", file_name)
		_refresh_save_list()

		if not SaveManager.has_saves():
			var main_menu: Node = get_parent()
			if is_instance_valid(main_menu):
				if main_menu.has_method("_check_game_context"):
					main_menu.call("_check_game_context")
	else:
		print("Error: Failed to delete save file: ", file_name)
