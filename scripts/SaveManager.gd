extends Node

signal save_completed

const SAVES_DIR: String = "user://saves/"
const THUMB_WIDTH: int = 320
const THUMB_HEIGHT: int = 180


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[SaveManager] Initializing...")
	
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("saves"):
			print("[SaveManager] 'saves' directory not found. Creating it...")
			var err := dir.make_dir("saves")
			if err != OK:
				push_error("[SaveManager] Failed to create 'saves' dir. Error: " + str(err))
		else:
			print("[SaveManager] 'saves' directory verified.")
	else:
		push_error("[SaveManager] CRITICAL: Failed to open user:// directory!")


func has_saves() -> bool:
	var dir := DirAccess.open(SAVES_DIR)
	if not dir:
		return false
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".dat"):
			return true
		file_name = dir.get_next()
	return false


func create_save(custom_name: String = "", is_fav: bool = false, existing_id: String = "") -> void:
	print("\n--- [SaveManager] STARTING SAVE PROCESS ---")
	var ui_nodes: Array[Node] = get_tree().get_nodes_in_group("hide_on_save")
	for node: Node in ui_nodes:
		if node is CanvasItem:
			node.hide()
			
	# OPTIMIZATION: Wait exactly until the renderer is done, no arbitrary timers.
	await RenderingServer.frame_post_draw
	
	var viewport_texture: Texture2D = get_viewport().get_texture()
	var viewport_img: Image = viewport_texture.get_image()
	
	for node: Node in ui_nodes:
		if node is CanvasItem:
			node.show()
			
	var timestamp: String = Time.get_datetime_string_from_system()
	var save_id: String = existing_id if existing_id != "" else str(Time.get_ticks_usec())
	var display_name: String = custom_name if custom_name != "" else timestamp
	var base_path: String = SAVES_DIR + "save_" + save_id
	
	if viewport_img != null and not viewport_img.is_empty():
		# Offload the heavy image processing and saving to a background thread
		WorkerThreadPool.add_task(_process_and_save_thumbnail.bind(viewport_img, base_path))
	else:
		push_warning("[SaveManager] Failed to capture viewport image.")
		
	_write_metadata(base_path + ".meta", display_name, timestamp, is_fav)
	_write_game_state(base_path + ".dat")
	
	print("--- [SaveManager] SAVE PROCESS COMPLETE ---\n")
	save_completed.emit()


# The threaded function to prevent main-thread stutter
func _process_and_save_thumbnail(img: Image, base_path: String) -> void:
	img.resize(THUMB_WIDTH, THUMB_HEIGHT, Image.INTERPOLATE_BILINEAR)
	var img_err: Error = img.save_webp(base_path + ".webp")
	if img_err != OK:
		push_warning("[SaveManager] Threaded thumbnail save failed: " + str(img_err))


func _write_metadata(path: String, display_name: String, time_str: String, fav: bool) -> void:
	print("[SaveManager] Writing metadata to: ", path)
	
	var current_scene_path: String = ""
	var current_scene := get_tree().current_scene
	if current_scene:
		current_scene_path = current_scene.scene_file_path
		print("[SaveManager] Detected current level: ", current_scene_path)
		
	var meta_dict: Dictionary = {
		"name": display_name,
		"timestamp": time_str,
		"is_favorite": fav,
		"level_path": current_scene_path
	}
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(meta_dict))
		file.close()
		print("[SaveManager] Metadata written successfully.")
	else:
		push_error("[SaveManager] Failed to write metadata. Error: " + str(FileAccess.get_open_error()))


func _write_game_state(path: String) -> void:
	print("[SaveManager] Writing game state to: ", path)
	var total_state: Dictionary = {}
	var saveables := get_tree().get_nodes_in_group("saveable")
	print("[SaveManager] Found ", saveables.size(), " nodes in 'saveable' group.")
	
	if saveables.is_empty():
		push_warning("[SaveManager] No saveable nodes found! Are they added to the group?")
	
	var saved_nodes_count: int = 0
	for node: Node in saveables:
		if node.has_method("get_save_data"):
			var node_data: Dictionary = node.call("get_save_data")
			var node_key: String = str(node.get_path())
			total_state[node_key] = node_data
			saved_nodes_count += 1
			print("   -> Saved data for: ", node.name)
		else:
			push_warning("[SaveManager] Node missing 'get_save_data' method: " + node.name)

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_var(total_state)
		file.close()
		print("[SaveManager] Game state written. Total nodes saved: ", saved_nodes_count)
	else:
		push_error("[SaveManager] Failed to write game state. Error: " + str(FileAccess.get_open_error()))


func _load_game_state(path: String) -> void:
	print("\n--- [SaveManager] STARTING LOAD PROCESS ---")
	print("[SaveManager] Attempting to load from: ", path)
	
	if not FileAccess.file_exists(path):
		push_error("[SaveManager] Load failed: File does not exist at path.")
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		var err := FileAccess.get_open_error()
		push_error("[SaveManager] Load failed: Cannot open file. Error: " + str(err))
		return
		
	var loaded_data: Variant = file.get_var()
	file.close()
	
	if not loaded_data is Dictionary:
		push_error("[SaveManager] Load failed: Data file is corrupted or invalid format.")
		return
		
	var total_state: Dictionary = loaded_data as Dictionary
	file.close()
	
	var keys: Array = total_state.keys()
	print("[SaveManager] Loaded file successfully. Contains data for ", keys.size(), " nodes.")

	var loaded_nodes_count: int = 0
	for node_path_str: String in keys:
		var node := get_node_or_null(node_path_str)
		if node:
			if node.has_method("load_save_data"):
				var node_data: Dictionary = total_state[node_path_str]
				node.call("load_save_data", node_data)
				loaded_nodes_count += 1
				print("   -> Applied data to: ", node.name)
			else:
				push_warning("[SaveManager] Target node missing 'load_save_data': " + node.name)
		else:
			push_warning("[SaveManager] Could not find target node in tree: " + node_path_str)
			
	print("--- [SaveManager] LOAD PROCESS COMPLETE. Nodes updated: ", loaded_nodes_count, " ---\n")

func get_all_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var dir := DirAccess.open(SAVES_DIR)
	if not dir:
		return saves
		
	dir.list_dir_begin()
	var file_name := dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".meta"):
			var base_path := SAVES_DIR + file_name.replace(".meta", "")
			var meta_file := FileAccess.open(SAVES_DIR + file_name, FileAccess.READ)
			if meta_file:
				var data: Dictionary = JSON.parse_string(meta_file.get_as_text())
				data["base_path"] = base_path 
				data["id"] = file_name.replace("save_", "").replace(".meta", "")
				saves.append(data)
		file_name = dir.get_next()
		
	saves.sort_custom(_sort_saves)
	return saves


func _sort_saves(a: Dictionary, b: Dictionary) -> bool:
	var a_fav: bool = a.get("is_favorite", false)
	var b_fav: bool = b.get("is_favorite", false)
	
	if a_fav and not b_fav:
		return true
	if not a_fav and b_fav:
		return false
		
	return a.get("id", "0").to_int() > b.get("id", "0").to_int()


func update_save_meta(save_id: String, new_name: String, is_favorite: bool) -> void:
	var path := SAVES_DIR + "save_" + save_id + ".meta"
	if not FileAccess.file_exists(path):
		return
		
	var file := FileAccess.open(path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	
	_write_metadata(path, new_name, data.get("timestamp", ""), is_favorite)


func load_save_game(base_path: String) -> void:
	print("\n--- [SaveManager] INITIATING FULL LOAD ---")
	var meta_path := base_path + ".meta"
	var dat_path := base_path + ".dat"

	if not FileAccess.file_exists(meta_path) or not FileAccess.file_exists(dat_path):
		push_error("[SaveManager] Missing save files at: " + base_path)
		return

	# 1. Read Metadata to find out which level to load
	var file := FileAccess.open(meta_path, FileAccess.READ)
	var meta_data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	var level_path: String = meta_data.get("level_path", "")

	# 2. Change Scene if we aren't already in it
	var current_scene := get_tree().current_scene
	var current_path := current_scene.scene_file_path if current_scene else ""
	
	if level_path != "" and current_path != level_path:
		print("[SaveManager] Changing scene to: ", level_path)
		var err := get_tree().change_scene_to_file(level_path)
		
		if err != OK:
			push_error("[SaveManager] Failed to load level: " + level_path)
			return
			
		# We MUST wait for Godot to swap the scenes and run _ready() on the new nodes
		# Waiting for two process frames ensures the new scene tree is fully built
		await get_tree().process_frame
		await get_tree().process_frame

	# 3. Apply the game state to the newly loaded level
	_load_game_state(dat_path)
	
	# --- NEW: UNPAUSE THE GAME ---
	# The old menu was destroyed, so we must manually unpause the global tree.
	get_tree().paused = false
	
	# Re-capture the mouse so the player can look around immediately.
	# (If your player script normally handles this on _ready, you can skip this line, 
	# but it's a good safety net).
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
