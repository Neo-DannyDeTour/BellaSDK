## Global autoload managing binary game state serialization and disk save files.
extends Node

## Emitted when save sequence finishes writing to disk.
signal save_completed

## Encryption password string for binary save payloads.
const ENCRYPTION_KEY: String = "bella_sec_v1_99238"
## Directory storing serialized save files.
const SAVES_DIR: String = "user://saves/"
## Thumbnail pixel width for save slots.
const THUMB_WIDTH: int = 320
## Thumbnail pixel height for save slots.
const THUMB_HEIGHT: int = 180

## Cached checkpoint position marker in 3D space.
var last_checkpoint_pos: Vector3 = Vector3.ZERO


## Verifies user save directory exists and sets always process mode.
func _ready() -> void:
	print("SaveManager: Initializing save system directory.")
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dir: DirAccess = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("saves"):
			var err: Error = dir.make_dir("saves")
			if err != OK:
				push_error("SaveManager: Failed creating saves folder: " + str(err))
	else:
		push_error("SaveManager: Failed accessing user directory.")


## Returns true if at least one valid dat save file exists on disk.
func has_saves() -> bool:
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


## Captures viewport snapshot and triggers background file writing.
func create_save(custom_name: String = "", is_fav: bool = false, existing_id: String = "") -> void:
	print("SaveManager: Initiating save sequence.")
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
		push_warning("SaveManager: Viewport capture failed.")

	_write_metadata(base_path + ".meta", display_name, timestamp, is_fav)
	_write_game_state(base_path + ".dat")

	print("SaveManager: Save complete. Emitting signal.")
	save_completed.emit()


## Resizes captured image and writes webp thumbnail on background thread.
func _process_and_save_thumbnail(img: Image, base_path: String) -> void:
	img.resize(THUMB_WIDTH, THUMB_HEIGHT, Image.INTERPOLATE_BILINEAR)
	var img_err: Error = img.save_webp(base_path + ".webp")
	if img_err != OK:
		push_warning("SaveManager: Thumbnail save failed: " + str(img_err))


## Encodes slot metadata dictionary into JSON file on disk.
func _write_metadata(path: String, display_name: String, time_str: String, fav: bool) -> void:
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
		push_error("SaveManager: Failed metadata write: " + path)


## Collects data from saveable group and dispatches encrypted disk write.
func _write_game_state(path: String) -> void:
	var total_state: Dictionary = {}
	var saveables: Array[Node] = get_tree().get_nodes_in_group("saveable")

	var saved_nodes_count: int = 0
	for node: Node in saveables:
		if node.has_method("get_save_data"):
			var node_data: Dictionary = node.call("get_save_data") as Dictionary
			var node_key: String = str(node.get_path())
			total_state[node_key] = node_data
			saved_nodes_count += 1
		else:
			push_warning("SaveManager: Missing get_save_data: " + node.name)

	var thread_safe_state: Dictionary = total_state.duplicate(true)
	WorkerThreadPool.add_task(_threaded_write_data.bind(path, thread_safe_state, saved_nodes_count))


## Writes encrypted binary game state dictionary on background thread.
func _threaded_write_data(path: String, data: Dictionary, count: int) -> void:
	var file: FileAccess = FileAccess.open_encrypted_with_pass(
		path, FileAccess.WRITE, ENCRYPTION_KEY
	)
	if file:
		file.store_var(data)
		file.close()
		print("SaveManager: Game state saved. Count: ", count)
	else:
		push_error("SaveManager: Encrypted write failed: " + path)


## Reads encrypted or unencrypted file and applies state back to nodes.
func _load_game_state(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("SaveManager: Target save missing: " + path)
		return

	var file: FileAccess = FileAccess.open_encrypted_with_pass(
		path, FileAccess.READ, ENCRYPTION_KEY
	)
	if not file:
		file = FileAccess.open(path, FileAccess.READ)
		if not file:
			push_error("SaveManager: Cannot open save file: " + path)
			return

	var loaded_data: Variant = file.get_var()
	file.close()

	if not (loaded_data is Dictionary):
		push_error("SaveManager: Corrupted data in: " + path)
		return

	var total_state: Dictionary = loaded_data as Dictionary
	var loaded_nodes_count: int = 0

	for node_path_str: String in total_state.keys():
		var node: Node = get_node_or_null(node_path_str)
		if node:
			if node.has_method("load_save_data"):
				var node_data: Dictionary = total_state[node_path_str] as Dictionary
				node.call("load_save_data", node_data)
				loaded_nodes_count += 1
			else:
				push_warning("SaveManager: Missing load_save_data: " + node.name)
		else:
			push_warning("SaveManager: Node missing from tree: " + node_path_str)

	print("SaveManager: Restored nodes count: ", loaded_nodes_count)


## Returns parsed and sorted metadata list for all discovered save files.
func get_all_saves() -> Array[Dictionary]:
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
				var raw_text: String = meta_file.get_as_text()
				meta_file.close()
				var parsed: Variant = JSON.parse_string(raw_text)
				if parsed is Dictionary:
					var data: Dictionary = parsed as Dictionary
					data["base_path"] = base_path
					data["id"] = file_name.replace("save_", "").replace(".meta", "")
					saves.append(data)
		file_name = dir.get_next()

	saves.sort_custom(_sort_saves)
	return saves


## Compares two save records by favorite flag and ID timestamp order.
func _sort_saves(a: Dictionary, b: Dictionary) -> bool:
	var a_fav: bool = a.get("is_favorite", false) as bool
	var b_fav: bool = b.get("is_favorite", false) as bool

	if a_fav != b_fav:
		return a_fav

	return (a.get("id", "0") as String).to_int() > (b.get("id", "0") as String).to_int()


## Reads existing metadata, updates display fields, and rewrites file.
func update_save_meta(save_id: String, new_name: String, is_favorite: bool) -> void:
	var path: String = SAVES_DIR + "save_" + save_id + ".meta"
	if not FileAccess.file_exists(path):
		return

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed is Dictionary:
		var data: Dictionary = parsed as Dictionary
		_write_metadata(path, new_name, data.get("timestamp", "") as String, is_favorite)


## Loads metadata, switches active scene if required, and applies game state.
func load_save_game(base_path: String) -> void:
	print("SaveManager: Loading game from base path: ", base_path)
	var clean_base: String = base_path
	for ext: String in [".meta", ".dat", ".webp", ".save"]:
		if clean_base.ends_with(ext):
			clean_base = clean_base.left(-ext.length())
			break

	var meta_path: String = clean_base + ".meta"
	var dat_path: String = clean_base + ".dat"

	if not FileAccess.file_exists(meta_path) or not FileAccess.file_exists(dat_path):
		push_error("SaveManager: Missing save file set for: " + clean_base)
		return

	var file: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
	if not file:
		return
	var raw_text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		return
	var meta_data: Dictionary = parsed as Dictionary

	var level_path: String = meta_data.get("level_path", "") as String
	var current_scene: Node = get_tree().current_scene
	var current_path: String = current_scene.scene_file_path if current_scene else ""

	if level_path != "" and current_path != level_path:
		var err: Error = get_tree().change_scene_to_file(level_path)
		if err != OK:
			push_error("SaveManager: Failed changing scene to: " + level_path)
			return

		await get_tree().process_frame
		await get_tree().process_frame

	_load_game_state(dat_path)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Compatibility alias routing load_game calls to [method load_save_game].
func load_game(target_path: String) -> void:
	load_save_game(target_path)
