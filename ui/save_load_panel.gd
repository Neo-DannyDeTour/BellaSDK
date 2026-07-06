extends Panel

const SAVES_DIR: String = "user://saves/"

@onready var save_list_container: VBoxContainer = %SaveListContainer
@onready var save_slot_template: Control = %SaveSlotTemplate

func _ready() -> void:
	print("UI: Save/Load Panel initialized.")
	save_slot_template.hide()
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
	if visible:
		_refresh_save_list()

func _refresh_save_list() -> void:
	print("System: Refreshing save slots from directory.")
	
	# Clear existing list (excluding the template)
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
			if not dir.current_is_dir() and file_name.ends_with(".save"):
				_create_save_slot(file_name)
			file_name = dir.get_next()
			
		dir.list_dir_end()

func _create_save_slot(file_name: String) -> void:
	var new_slot: Control = save_slot_template.duplicate() as Control
	new_slot.show()
	
	# Assuming your template has a Label for the name and Buttons for actions
	var name_label: Label = new_slot.find_child("SaveNameLabel", true, false)
	var load_btn: Button = new_slot.find_child("LoadButton", true, false)
	var del_btn: Button = new_slot.find_child("DeleteButton", true, false)
	
	if name_label:
		name_label.text = file_name.get_basename()
		
	if load_btn:
		load_btn.pressed.connect(_on_load_pressed.bind(file_name))
		
	if del_btn:
		del_btn.pressed.connect(_on_delete_pressed.bind(file_name))
		
	save_list_container.add_child(new_slot)

func _on_load_pressed(file_name: String) -> void:
	print("Player clicked Load for save: ", file_name)
	var path: String = SAVES_DIR + file_name
	
	# Passing the path over to your SaveManager Autoload
	if SaveManager.has_method("load_game"):
		SaveManager.load_game(path)

func _on_delete_pressed(file_name: String) -> void:
	print("Player clicked Delete for save: ", file_name)
	var path: String = SAVES_DIR + file_name
	
	if DirAccess.remove_absolute(path) == OK:
		print("System: Successfully deleted save file: ", file_name)
		_refresh_save_list()
		
		# Tell MainMenu to hide load button if no saves remain
		if not SaveManager.has_saves():
			var main_menu: Node = get_parent()
			if main_menu and main_menu.has_method("_check_game_context"):
				main_menu._check_game_context()
	else:
		print("Error: Failed to delete save file: ", file_name)
