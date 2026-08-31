## Global autoload managing the serialization and deserialization of the game state.
##
## Handles capturing viewport thumbnails, writing JSON metadata, and saving/loading
## nodes grouped in the 'saveable' group using binary .dat files.
extends Node

## Emitted when a save sequence completely finishes writing to disk.
signal save_completed

## Security variable: The encryption key used to protect binary game state data files.
const ENCRYPTION_KEY: String = "bella_sec_v1_99238"

## The internal OS path where all save files are kept.
const SAVES_DIR: String = "user://saves/"

## Target width in pixels for generated save file thumbnails.
const THUMB_WIDTH: int = 320

## Target height in pixels for generated save file thumbnails.
const THUMB_HEIGHT: int = 180

## Cache for the last checkpoint [Vector3] position the player crossed.
var last_checkpoint_pos: Vector3 = Vector3.ZERO


## Called when the node enters the scene tree.
## Ensures the save directory exists and sets the process mode.
func _ready() -> void:
	print("SaveManager: _ready() called. Initializing save directory...")
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dir: DirAccess = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("saves"):
			print("SaveManager: 'saves' directory not found. Creating it...")
			var err: Error = dir.make_dir("saves")
			if err != OK:
				push_error("SaveManager: Failed to create 'saves' dir. Error: " + str(err))
		else:
			print("SaveManager: 'saves' directory verified.")
	else:
		push_error("SaveManager: CRITICAL: Failed to open user:// directory!")


## Iterates through the saves directory to check if any valid save .dat files exist.
func has_saves() -> bool:
	print("SaveManager: has_saves() called.")
	var dir: DirAccess = DirAccess.open(SAVES_DIR)
	if not dir:
		return false

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".dat"):
			return true
		file_name = dir.get_next()
	return false


## Initiates a save sequence. Captures a thumbnail, gathers node data, and writes to disk.
func create_save(custom_name: String = "", is_fav: bool = false, existing_id: String = "") -> void:
	print("SaveManager: create_save() called.")
	get_tree().call_group("hide_on_save", "hide")

	await RenderingServer.frame_post_draw

	var viewport_texture: Texture2D = get_viewport().get_texture()
	var viewport_img: Image = viewport_texture.get_image()

	get_tree().call_group("hide_on_save", "show")

	var timestamp: String = Time.get_datetime_string_from_system()
	var save_id: String = existing_id if existing_id != "" else str(Time.get_ticks_usec())
	var display_name: String = custom_name if custom_name != "" else timestamp
	var base_path: String = SAVES_DIR + "save_" + save_id

	if viewport_img != null and not viewport_img.is_empty():
		WorkerThreadPool.add_task(_process_and_save_thumbnail.bind(viewport_img, base_path))
	else:
		push_warning("SaveManager: Failed to capture viewport image.")

	_write_metadata(base_path + ".meta", display_name, timestamp, is_fav)
	_write_game_state(base_path + ".dat")

	print("SaveManager: Save sequence finalized. Emitting save_completed.")
	save_completed.emit()


## A background thread function that resizes and encodes the viewport image.
func _process_and_save_thumbnail(img: Image, base_path: String) -> void:
	print("SaveManager: _process_and_save_thumbnail() background task started.")
	img.resize(THUMB_WIDTH, THUMB_HEIGHT, Image.INTERPOLATE_BILINEAR)
	var img_err: Error = img.save_webp(base_path + ".webp")
	if img_err != OK:
		push_warning("SaveManager: Threaded thumbnail save failed: " + str(img_err))


## Constructs and saves the lightweight JSON file used by the load menu.
func _write_metadata(path: String, display_name: String, time_str: String, fav: bool) -> void:
	print("SaveManager: _write_metadata() called for: ", path)
	var current_scene_path: String = ""
	var current_scene: Node = get_tree().current_scene
	if current_scene:
		current_scene_path = current_scene.scene_file_path

	var meta_dict: Dictionary = {
		"name": display_name,
		"timestamp": time_str,
		"is_favorite": fav,
		"level_path": current_scene_path
	}

	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(meta_dict))
		file.close()
	else:
		push_error(
			"SaveManager: Failed to write metadata. Error: " + str(FileAccess.get_open_error())
		)


## Gathers all nodes in the 'saveable' group and calls get_save_data() on them.
func _write_game_state(path: String) -> void:
	print("SaveManager: _write_game_state() called for: ", path)
	var total_state: Dictionary = {}
	var saveables: Array[Node] = get_tree().get_nodes_in_group("saveable")

	if saveables.is_empty():
		push_warning("SaveManager: No saveable nodes found.")

	var saved_nodes_count: int = 0
	for node: Node in saveables:
		if node.has_method("get_save_data"):
			var node_data: Dictionary = node.call("get_save_data")
			var node_key: String = str(node.get_path())
			total_state[node_key] = node_data
			saved_nodes_count += 1
		else:
			push_warning("SaveManager: Node missing 'get_save_data': " + node.name)

	var thread_safe_state: Dictionary = total_state.duplicate(true)
	WorkerThreadPool.add_task(_threaded_write_data.bind(path, thread_safe_state, saved_nodes_count))


## Background thread function that writes the large binary dictionary to disk encrypted.
## [param path] The file path to write to.
## [param data] The dictionary data to serialize.
## [param count] The number of nodes being saved.
func _threaded_write_data(path: String, data: Dictionary, count: int) -> void:
	print("SaveManager: _threaded_write_data() background task started.")
	var file: FileAccess = FileAccess.open_encrypted_with_pass(
		path, FileAccess.WRITE, ENCRYPTION_KEY
	)
	if file:
		file.store_var(data)
		file.close()
		print("SaveManager: Game state securely written. Total nodes saved: ", count)
	else:
		var err: Error = FileAccess.get_open_error()
		push_error("SaveManager: Failed to securely write game state. Error: " + str(err))


## Reads the binary dictionary from disk and pushes data back into active scene nodes.
## Includes a fallback to read unencrypted legacy saves.
## [param path] The file path to load from.
func _load_game_state(path: String) -> void:
	print("SaveManager: _load_game_state() called for: ", path)
	if not FileAccess.file_exists(path):
		push_error("SaveManager: Load failed: File does not exist at path.")
		return

	var file: FileAccess = FileAccess.open_encrypted_with_pass(
		path, FileAccess.READ, ENCRYPTION_KEY
	)
	if not file:
		var err: Error = FileAccess.get_open_error()
		print(
			"SaveManager: Failed to decrypt file. Attempting unencrypted fallback. Error: ",
			str(err)
		)
		file = FileAccess.open(path, FileAccess.READ)
		if not file:
			var fb_err: Error = FileAccess.get_open_error()
			push_error(
				"SaveManager: Load failed: Cannot open unencrypted file. Error: " + str(fb_err)
			)
			return

	var loaded_data: Variant = file.get_var()
	file.close()
	print("SaveManager: Game state loaded successfully.")

	if not loaded_data is Dictionary:
		push_error("SaveManager: Corrupted data file.")
		return

	var total_state: Dictionary = loaded_data as Dictionary
	var keys: Array = total_state.keys()
	var loaded_nodes_count: int = 0

	for node_path_str: String in keys:
		var node: Node = get_node_or_null(node_path_str)
		if node:
			if node.has_method("load_save_data"):
				var node_data: Dictionary = total_state[node_path_str]
				node.call("load_save_data", node_data)
				loaded_nodes_count += 1
			else:
				push_warning("SaveManager: Missing 'load_save_data': " + node.name)
		else:
			push_warning("SaveManager: Node not in tree: " + node_path_str)

	print("SaveManager: Game state loaded. Total nodes restored: ", loaded_nodes_count)


## Scans the saves directory and returns a parsed list of all save file metadata.
func get_all_saves() -> Array[Dictionary]:
	print("SaveManager: get_all_saves() called.")
	var saves: Array[Dictionary] = []
	var dir: DirAccess = DirAccess.open(SAVES_DIR)
	if not dir:
		return saves

	dir.list_dir_begin()
	var file_name: String = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".meta"):
			var base_path: String = SAVES_DIR + file_name.replace(".meta", "")
			var meta_file: FileAccess = FileAccess.open(SAVES_DIR + file_name, FileAccess.READ)
			if meta_file:
				var data: Dictionary = JSON.parse_string(meta_file.get_as_text())
				data["base_path"] = base_path
				data["id"] = file_name.replace("save_", "").replace(".meta", "")
				saves.append(data)
		file_name = dir.get_next()

	saves.sort_custom(_sort_saves)
	return saves


## Custom sorting function for save slots by favorite status and ID.
func _sort_saves(a: Dictionary, b: Dictionary) -> bool:
	var a_fav: bool = a.get("is_favorite", false)
	var b_fav: bool = b.get("is_favorite", false)

	if a_fav != b_fav:
		return a_fav

	return a.get("id", "0").to_int() > b.get("id", "0").to_int()


## Overwrites an existing save's metadata file without touching the binary .dat file.
func update_save_meta(save_id: String, new_name: String, is_favorite: bool) -> void:
	print("SaveManager: update_save_meta() called for ID: ", save_id)
	var path: String = SAVES_DIR + "save_" + save_id + ".meta"
	if not FileAccess.file_exists(path):
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	_write_metadata(path, new_name, data.get("timestamp", ""), is_favorite)


## Orchestrates a full load sequence: reads metadata, swaps scenes, and loads state.
func load_save_game(base_path: String) -> void:
	print("SaveManager: load_save_game() called for: ", base_path)
	var meta_path: String = base_path + ".meta"
	var dat_path: String = base_path + ".dat"

	if not FileAccess.file_exists(meta_path) or not FileAccess.file_exists(dat_path):
		push_error("SaveManager: Missing save files at: " + base_path)
		return

	var file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	var meta_data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	var level_path: String = meta_data.get("level_path", "")
	var current_scene: Node = get_tree().current_scene
	var current_path: String = current_scene.scene_file_path if current_scene else ""

	if level_path != "" and current_path != level_path:
		var err: Error = get_tree().change_scene_to_file(level_path)
		if err != OK:
			push_error("SaveManager: Failed to load level: " + level_path)
			return

		await get_tree().process_frame
		await get_tree().process_frame

	_load_game_state(dat_path)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
