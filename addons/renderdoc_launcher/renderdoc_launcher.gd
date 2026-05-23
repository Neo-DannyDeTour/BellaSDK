@tool
extends EditorPlugin

static var button_res: PackedScene = preload("res://addons/renderdoc_launcher/res/renderdoc_button.tscn")
static var path_tres: String = "res://addons/renderdoc_launcher/res/renderdoc_path.tres"
static var renderdoc_settings_path: String = "res://addons/renderdoc_launcher/res/settings.cap"

var thread: Thread
var renderdoc_path: RenderDocPath
var button: Control
var file_dialog: FileDialog
var option_button: OptionButton

var added: bool = false


func _enter_tree() -> void:
	if create_renderdoc_path_tres() != OK:
		printerr("Failed to create renderdoc_path.tres.")
		return

	button = button_res.instantiate()
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, button)

	var container = button.get_node("Panel/HBoxContainer")
	container.get_node("RenderDocButton").pressed.connect(open_renderdoc)

	option_button = container.get_node("OptionButton")
	option_button.add_item("Main")
	option_button.add_item("Current")

	file_dialog = button.get_node("FileDialog")
	file_dialog.file_selected.connect(save_path)
	file_dialog.title = "RenderDoc Location"

	added = true
	print("Added RenderDoc Launcher Button to Toolbar.")


func _exit_tree() -> void:
	if added and is_instance_valid(button):
		remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, button)
		button.queue_free()  # Safely destroy the node to prevent memory leaks/ghost signals
		added = false
		print("Removed RenderDoc Launcher Button from Toolbar.")


func open_renderdoc() -> void:
	if create_renderdoc_path_tres() != OK:
		printerr("Failed to create renderdoc_path.tres.")
		return

	var path = get_renderdoc_path()
	if path == null or path == "" or not FileAccess.file_exists(path):
		print("RenderDoc path empty or not valid, please locate RenderDoc on your system.")
		print("Typical Windows installation would be at 'C:\\Program Files\\RenderDoc\\qrenderdoc.exe'.")
		file_dialog.popup_centered()
	else:
		execute_renderdoc()


func execute_renderdoc() -> void:
	if create_renderdoc_settings() != OK:
		printerr("Error creating settings.cap for RenderDoc!")
		return

	var file = FileAccess.open(renderdoc_settings_path, FileAccess.READ)
	if not file:
		printerr("Error opening settings.cap!")
		return

	var text = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(text)
	var data

	if error == OK:
		data = json.data
		match option_button.get_selected_id():
			0:
				data["settings"]["commandLine"] = ('--path "%s"' % ProjectSettings.globalize_path("res://"))
			1:
				var current_scene = get_editor_interface().get_edited_scene_root()
				if current_scene:
					var scene_path = current_scene.scene_file_path
					var abs_scene_path = ProjectSettings.globalize_path(scene_path)
					var abs_project_path = ProjectSettings.globalize_path("res://")
					data["settings"]["commandLine"] = ('--path "%s" --scene "%s"' % [abs_project_path, abs_scene_path])

		data["settings"]["executable"] = OS.get_executable_path()
	else:
		print("JSON Parse Error: ", error)
		return

	file.close()  # Ensure the read handle is released before opening in WRITE mode

	file = FileAccess.open(renderdoc_settings_path, FileAccess.WRITE)
	if not file:
		printerr("Error opening settings.cap for writing!")
		return

	file.store_string(json.stringify(data))
	file.close()

	await get_tree().process_frame
	print("Launching RenderDoc.")

	# Always globalize paths before passing them to external processes
	var global_settings_path = ProjectSettings.globalize_path(renderdoc_settings_path)
	OS.create_process(get_renderdoc_path(), [global_settings_path])


func save_path(path: String) -> void:
	match OS.get_name():
		"Windows":
			renderdoc_path.win_path = path
		"macOS":
			renderdoc_path.osx_path = path
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			renderdoc_path.x11_path = path
		_:
			printerr("RenderDoc can only be launched from a desktop platform!")
			return

	var error = ResourceSaver.save(renderdoc_path, path_tres)
	if error != OK:
		printerr("Error saving RenderDoc path in renderdoc_path.tres!")
		return

	print("Saved '%s' as the RenderDoc location for the OS %s." % [path, OS.get_name()])
	execute_renderdoc()


func get_renderdoc_path() -> String:
	match OS.get_name():
		"Windows":
			return renderdoc_path.win_path
		"macOS":
			return renderdoc_path.osx_path
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return renderdoc_path.x11_path
		_:
			printerr("RenderDoc can only be launched from a desktop platform!")
			return ""


func create_renderdoc_path_tres() -> Error:
	# Safely check if the file exists without locking the file handle
	if not FileAccess.file_exists(path_tres):
		renderdoc_path = RenderDocPath.new()
		var error = ResourceSaver.save(renderdoc_path, path_tres)
		if error == OK:
			print("Created renderdoc_path.tres.")
		return error
	else:
		renderdoc_path = ResourceLoader.load(path_tres)
		return OK if renderdoc_path != null else ERR_FILE_CANT_OPEN


func create_renderdoc_settings() -> Error:
	if not FileAccess.file_exists(renderdoc_settings_path):
		var default_path = "res://addons/renderdoc_launcher/res/default_settings.cap"

		if not FileAccess.file_exists(default_path):
			printerr("Default Renderdoc settings not found!")
			return ERR_FILE_NOT_FOUND

		var default_settings_file = FileAccess.open(default_path, FileAccess.READ)
		var content = default_settings_file.get_as_text()
		default_settings_file.close()

		var renderdoc_settings_file = FileAccess.open(renderdoc_settings_path, FileAccess.WRITE)
		if not renderdoc_settings_file:
			return ERR_FILE_CANT_WRITE

		renderdoc_settings_file.store_string(content)
		renderdoc_settings_file.close()

	return OK
