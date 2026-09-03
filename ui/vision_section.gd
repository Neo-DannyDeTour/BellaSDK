## Controls vision assist, background desaturation shaders, and color highlights.
## Attached to the VisionSection GridContainer.
class_name AccessibilityVisionSection
extends GridContainer

## Available palette color options for high contrast silhouette groups.
const COLOR_NAMES: Array[String] = [
	"Cyan", "Blue", "Yellow", "Green", "Red", "Magenta", "White", "Black"
]

## Available background mode tags for vision assist.
const VISION_MODES: Array[String] = ["Black & White", "Blue", "Pure Black", "Grey", "Desaturated"]

## Identifier keys mapping directly to background mode shader parameters.
const VISION_MODE_KEYS: Array[String] = [
	"black_and_white", "blue", "pure_black", "grey", "desaturated"
]

## Default constant value for vision assist high-contrast rendering.
const DEFAULT_VISION_ASSIST: bool = false

## Default constant index for vision assist background modes.
const DEFAULT_VISION_ASSIST_MODE: int = 1

## Toggle switch for vision assist high-contrast silhouette rendering.
@onready var vision_assist_toggle: CheckButton = get_node_or_null("%VisionAssistToggle")

## Dropdown menu for selecting vision assist background desaturation mode.
@onready var vision_mode_option: OptionButton = get_node_or_null("%VisionModeOption")

## Color selection dropdown for the friendly allies highlight group.
@onready var color_friends_option: OptionButton = get_node_or_null("%ColorFriendsOption")

## Color selection dropdown for the enemy threat highlight group.
@onready var color_enemies_option: OptionButton = get_node_or_null("%ColorEnemiesOption")

## Color selection dropdown for the interactable items highlight group.
@onready var color_interact_option: OptionButton = get_node_or_null("%ColorInteractOption")

## Color selection dropdown for the traversal navigation highlight group.
@onready var color_traversal_option: OptionButton = get_node_or_null("%ColorTraversalOption")

## Color selection dropdown for narrative clues and notes highlight group.
@onready var color_clues_option: OptionButton = get_node_or_null("%ColorCluesOption")

## Color selection dropdown for defensive cover highlight group.
@onready var color_cover_option: OptionButton = get_node_or_null("%ColorCoverOption")

## Dictionary caching camera nodes in the diorama keyed by group name.
var _diorama_cameras: Dictionary[String, Camera3D] = {}

## Active camera instance currently rendering the preview.
var _active_diorama_camera: Camera3D

## Active tween interpolating preview camera movements.
var _camera_tween: Tween


## Lifecycle initialization method populating options and binding controls.
func _ready() -> void:
	print("UI: Initializing Vision Section.")
	_populate_dropdowns()
	_connect_signals()


## Populates vision assist mode and palette dropdowns.
func _populate_dropdowns() -> void:
	if is_instance_valid(vision_mode_option):
		vision_mode_option.clear()
		for mode: String in VISION_MODES:
			vision_mode_option.add_item(mode)

	var group_dropdowns: Array[OptionButton] = [
		color_friends_option,
		color_enemies_option,
		color_interact_option,
		color_traversal_option,
		color_clues_option,
		color_cover_option
	]
	for dropdown: OptionButton in group_dropdowns:
		if is_instance_valid(dropdown):
			dropdown.clear()
			for col: String in COLOR_NAMES:
				dropdown.add_item(col)


## Connects UI input signals for vision modes and color pickers.
func _connect_signals() -> void:
	if is_instance_valid(vision_assist_toggle):
		vision_assist_toggle.toggled.connect(_on_vision_assist_toggled)
	if is_instance_valid(vision_mode_option):
		vision_mode_option.item_selected.connect(_on_vision_mode_selected)

	_connect_color_dropdown(color_friends_option, "friends")
	_connect_color_dropdown(color_enemies_option, "enemies")
	_connect_color_dropdown(color_interact_option, "interactables")
	_connect_color_dropdown(color_traversal_option, "traversal")
	_connect_color_dropdown(color_clues_option, "clues")
	_connect_color_dropdown(color_cover_option, "cover")


## Connects palette dropdown instances to the Vision Assist bus and camera switching.
## [param dropdown] The [OptionButton] instance.
## [param group_name] Target scene group identifier.
func _connect_color_dropdown(dropdown: OptionButton, group_name: String) -> void:
	if not is_instance_valid(dropdown):
		return

	dropdown.mouse_entered.connect(
		func() -> void:
			set_preview_effects_active(true)
			_switch_diorama_camera(group_name)
	)

	dropdown.item_selected.connect(
		func(index: int) -> void:
			var col_name: String = COLOR_NAMES[index].to_lower()
			print("Player changed color for [", group_name, "] to: ", col_name)
			GlobalSettings.save_setting("VisionAssist", group_name + "_color", index)

			var events: Node = get_node_or_null("/root/Events")
			if is_instance_valid(events) and events.has_signal("vision_assist_color_changed"):
				events.vision_assist_color_changed.emit(group_name, col_name)
				events.vision_assist_color_changed.emit(group_name.capitalize(), col_name)

			set_preview_effects_active(true)
			_apply_diorama_colors()
			_switch_diorama_camera(group_name)
	)


## Loads stored vision settings from GlobalSettings.
func load_settings() -> void:
	print("UI: Loading Vision Assist settings.")
	var vision_enabled: bool = bool(
		GlobalSettings.get_setting("VisionAssist", "enabled", DEFAULT_VISION_ASSIST)
	)
	if is_instance_valid(vision_assist_toggle):
		vision_assist_toggle.set_pressed_no_signal(vision_enabled)

	if is_instance_valid(vision_mode_option):
		var mode_idx: int = int(
			GlobalSettings.get_setting("VisionAssist", "mode", DEFAULT_VISION_ASSIST_MODE)
		)
		vision_mode_option.selected = mode_idx
		_apply_vision_assist_mode(mode_idx)

	_load_group_color_setting(color_friends_option, "friends", 0)
	_load_group_color_setting(color_enemies_option, "enemies", 3)
	_load_group_color_setting(color_interact_option, "interactables", 1)
	_load_group_color_setting(color_traversal_option, "traversal", 2)
	_load_group_color_setting(color_clues_option, "clues", 4)
	_load_group_color_setting(color_cover_option, "cover", 5)


## Loads and configures an OptionButton dropdown for group colors.
## [param dropdown] Target [OptionButton].
## [param group_name] Setting group key.
## [param default_index] Fallback color index.
func _load_group_color_setting(
	dropdown: OptionButton, group_name: String, default_index: int
) -> void:
	if not is_instance_valid(dropdown):
		return
	var idx: int = int(
		GlobalSettings.get_setting("VisionAssist", group_name + "_color", default_index)
	)
	dropdown.selected = idx
	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events) and events.has_signal("vision_assist_color_changed"):
		events.vision_assist_color_changed.emit(group_name, COLOR_NAMES[idx].to_lower())
		events.vision_assist_color_changed.emit(
			group_name.capitalize(), COLOR_NAMES[idx].to_lower()
		)


## Handles toggling of the vision assist rendering system for the player.
## [param toggled_on] Enabled state.
func _on_vision_assist_toggled(toggled_on: bool) -> void:
	print("Player toggled Vision Assist to: ", toggled_on)
	GlobalSettings.save_setting("VisionAssist", "enabled", toggled_on)
	var player: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and "camera_controller" in player and player.camera_controller:
		var p_cam: Camera3D = player.camera_controller.get_node_or_null("Camera3D") as Camera3D
		if is_instance_valid(p_cam) and p_cam.has_method("_on_vision_assist_toggled"):
			p_cam.call("_on_vision_assist_toggled", toggled_on)
		var p_mesh: MeshInstance3D = (
			player.camera_controller.get_node_or_null("Camera3D/VisionAssistMesh") as MeshInstance3D
		)
		if is_instance_valid(p_mesh):
			p_mesh.visible = toggled_on

	var events: Node = get_node_or_null("/root/Events")
	if is_instance_valid(events) and events.has_signal("vision_assist_toggled"):
		events.vision_assist_toggled.emit(toggled_on)


## Handles vision assist background desaturation mode dropdown selection.
## [param index] Selected mode index.
func _on_vision_mode_selected(index: int) -> void:
	print("Player selected Vision Assist mode index: ", index)
	GlobalSettings.save_setting("VisionAssist", "mode", index)
	_apply_vision_assist_mode(index)


## Broadcasts vision assist background style changes across the EventBus.
## [param index] Selected mode index.
func _apply_vision_assist_mode(index: int) -> void:
	if index >= 0 and index < VISION_MODE_KEYS.size():
		var mode_key: String = VISION_MODE_KEYS[index]
		_update_diorama_mode(mode_key)
		var events: Node = get_node_or_null("/root/Events")
		if is_instance_valid(events) and events.has_signal("vision_assist_mode_changed"):
			events.vision_assist_mode_changed.emit(mode_key)


## Synchronizes UI toggle state from external EventBus broadcasts.
## [param active] Enabled state.
func sync_external_vision_assist(active: bool) -> void:
	if is_instance_valid(vision_assist_toggle) and vision_assist_toggle.button_pressed != active:
		vision_assist_toggle.set_pressed_no_signal(active)


## Finds the root Node3D instance inside the docked diorama viewport safely.
## [return] The diorama root [Node] or `null`.
func _get_diorama_instance() -> Node:
	var socket: Control = get_node_or_null("%AccessibilityDioramaSocket")
	var viewport: SubViewport = null
	if is_instance_valid(socket):
		viewport = socket.find_child("DioramaViewport", true, false) as SubViewport
	if not is_instance_valid(viewport):
		viewport = get_tree().root.find_child("DioramaViewport", true, false) as SubViewport
	if not is_instance_valid(viewport):
		return null

	var inst: Node = viewport.get_node_or_null("SettingsLevel")
	if not is_instance_valid(inst):
		inst = viewport.get_node_or_null("FastDioramaMap")
	if not is_instance_valid(inst):
		for child: Node in viewport.get_children():
			if child is Node3D:
				inst = child
				break
	return inst


## Discovers and caches all Camera3D instances present in the docked diorama.
func cache_diorama_cameras() -> void:
	print("UI: Caching diorama camera nodes.")
	_diorama_cameras.clear()
	var diorama_root: Node = _get_diorama_instance()
	if not is_instance_valid(diorama_root):
		return

	var mode_idx: int = int(
		GlobalSettings.get_setting("VisionAssist", "mode", DEFAULT_VISION_ASSIST_MODE)
	)
	var mode_key: String = (
		VISION_MODE_KEYS[mode_idx]
		if mode_idx >= 0 and mode_idx < VISION_MODE_KEYS.size()
		else "aaa_blue"
	)

	var camera_nodes: Array[Node] = diorama_root.find_children("Camera_*", "Camera3D", true, false)
	for node: Node in camera_nodes:
		var cam: Camera3D = node as Camera3D
		var key: String = cam.name.trim_prefix("Camera_").to_lower()
		_diorama_cameras[key] = cam

		if "is_player_camera" in cam:
			cam.is_player_camera = false
		cam.set_process(false)

		var mesh: MeshInstance3D = cam.get_node_or_null("VisionAssistMesh") as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.visible = false

		if cam.has_method("set_vision_assist_mode"):
			cam.call("set_vision_assist_mode", mode_key)

	if _diorama_cameras.has("default"):
		_switch_diorama_camera("default")
	elif not _diorama_cameras.is_empty():
		_switch_diorama_camera(_diorama_cameras.keys()[0])


## Switches active diorama viewport rendering to the specified group camera.
## [param group_name] The target scene group identifier.
func _switch_diorama_camera(group_name: String) -> void:
	if _diorama_cameras.is_empty():
		cache_diorama_cameras()

	var clean_key: String = group_name.to_lower()
	var target_cam: Camera3D = _diorama_cameras.get(clean_key)
	if not is_instance_valid(target_cam):
		target_cam = _diorama_cameras.get("default")

	var diorama_root: Node = _get_diorama_instance()
	if not is_instance_valid(target_cam) and is_instance_valid(diorama_root):
		_focus_diorama_on_group(group_name, diorama_root)
		return

	if not is_instance_valid(target_cam) or target_cam == _active_diorama_camera:
		return

	print("UI: Switching active diorama camera to: ", target_cam.name)
	for cam: Camera3D in _diorama_cameras.values():
		if is_instance_valid(cam):
			var mesh: MeshInstance3D = cam.get_node_or_null("VisionAssistMesh") as MeshInstance3D
			if is_instance_valid(mesh):
				mesh.visible = (cam == target_cam)

	target_cam.make_current()
	_active_diorama_camera = target_cam

	var mode_idx: int = int(
		GlobalSettings.get_setting("VisionAssist", "mode", DEFAULT_VISION_ASSIST_MODE)
	)
	var mode_key: String = (
		VISION_MODE_KEYS[mode_idx]
		if mode_idx >= 0 and mode_idx < VISION_MODE_KEYS.size()
		else "aaa_blue"
	)
	if target_cam.has_method("set_vision_assist_mode"):
		target_cam.call("set_vision_assist_mode", mode_key)

	_apply_diorama_colors()


## Tweens camera to center bounding box of nodes in a given group.
## [param group_name] Target scene group identifier.
## [param diorama_root] Preview root node.
func _focus_diorama_on_group(group_name: String, diorama_root: Node) -> void:
	if not is_instance_valid(_active_diorama_camera) or not is_instance_valid(diorama_root):
		return

	var nodes: Array[Node] = diorama_root.find_children("*", "Node3D", true, false)
	var group_nodes: Array[Node3D] = []
	for n: Node in nodes:
		if (n.is_in_group(group_name) or n.is_in_group(group_name.capitalize())) and n is Node3D:
			group_nodes.append(n as Node3D)

	if group_nodes.is_empty():
		return

	var bounds: AABB = AABB(group_nodes[0].global_position, Vector3.ZERO)
	for n: Node3D in group_nodes:
		bounds = bounds.expand(n.global_position)

	var center: Vector3 = bounds.get_center()
	var offset_dist: float = maxf(bounds.size.length() * 1.5, 2.5)
	var target_pos: Vector3 = center + Vector3(0.0, offset_dist * 0.4, offset_dist)

	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill()

	_camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)
	_camera_tween.tween_property(_active_diorama_camera, "global_position", target_pos, 0.6)
	var look_transform: Transform3D = _active_diorama_camera.global_transform.looking_at(
		center, Vector3.UP
	)
	_camera_tween.tween_property(
		_active_diorama_camera, "global_transform:basis", look_transform.basis, 0.6
	)


## Updates shader keywords across all cached diorama preview cameras.
## [param mode_key] Shader mode parameter string.
func _update_diorama_mode(mode_key: String) -> void:
	for cam: Camera3D in _diorama_cameras.values():
		if is_instance_valid(cam) and cam.has_method("set_vision_assist_mode"):
			cam.call("set_vision_assist_mode", mode_key)


## Applies silhouette highlight colors directly to all diorama models.
func _apply_diorama_colors() -> void:
	var diorama_root: Node = _get_diorama_instance()
	if not is_instance_valid(diorama_root):
		return

	var vision_mgr: Node = get_node_or_null("/root/VisionAssistManager")
	if is_instance_valid(vision_mgr):
		if vision_mgr.has_method("apply_diorama_colors"):
			vision_mgr.call("apply_diorama_colors", diorama_root)
		elif vision_mgr.has_method("set_diorama_overlays_active"):
			vision_mgr.call("set_diorama_overlays_active", diorama_root, true)


## Toggles vision assist post-process shader meshes and model overlay effects.
## [param active] Whether post-process shader should be visible.
func set_preview_effects_active(active: bool) -> void:
	print("UI: Vision preview effects active -> ", active)
	var diorama_root: Node = _get_diorama_instance()
	var socket: Control = get_node_or_null("%AccessibilityDioramaSocket")

	if not active:
		if is_instance_valid(socket):
			var meshes: Array[Node] = socket.find_children(
				"VisionAssistMesh", "MeshInstance3D", true, false
			)
			for node: Node in meshes:
				(node as MeshInstance3D).visible = false

		var vision_mgr: Node = get_node_or_null("/root/VisionAssistManager")
		if is_instance_valid(vision_mgr) and is_instance_valid(diorama_root):
			if vision_mgr.has_method("set_diorama_overlays_active"):
				vision_mgr.call("set_diorama_overlays_active", diorama_root, false)

		var def_cam: Camera3D = _diorama_cameras.get("default")
		if is_instance_valid(def_cam):
			def_cam.make_current()
			_active_diorama_camera = def_cam
		return

	if _diorama_cameras.is_empty():
		cache_diorama_cameras()

	if is_instance_valid(_active_diorama_camera):
		var active_mesh: MeshInstance3D = (
			_active_diorama_camera.get_node_or_null("VisionAssistMesh") as MeshInstance3D
		)
		if is_instance_valid(active_mesh):
			active_mesh.visible = true

	_apply_diorama_colors()
