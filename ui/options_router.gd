## Coordinates options category tabs, diorama sandbox isolation, and preview camera routing.
class_name OptionsRouter
extends Control

## Emitted when the player clicks the master back button to exit the options menu.
@warning_ignore("unused_signal")
signal back_requested

## Visual layer bitmask assigned to diorama preview geometry (3D Render Layer 11).
const PREVIEW_LAYER_MASK: int = 1 << 10

## Visual layer bitmask assigned to volumetric fog volumes (3D Render Layer 10).
const VOLUMETRIC_LAYER_MASK: int = 1 << 9

## Preloaded 3D diorama scene instantiated inside the isolated preview SubViewport.
const SETTINGS_LEVEL_SCENE: PackedScene = preload("res://player/settings_level.tscn")

## Cached reference to the primary graphics preview camera in the diorama.
var _graphics_camera: Camera3D = null

## Currently active category settings panel.
var _current_panel: Panel = null

## Cached reference to the preview post-process shader canvas layer.
var _preview_layer: CanvasLayer = null

## Cached list of vision assist silhouette meshes inside the diorama.
var _vision_meshes: Array[MeshInstance3D] = []

## Cached array of all cameras residing inside the diorama scene.
var _all_diorama_cameras: Array[Camera3D] = []

## Cached runtime instance of the diorama 3D level.
var _instantiated_diorama: Node3D = null

## Reference to the video settings panel.
@onready var video_panel: Panel = %VideoOptionsPanel

## Reference to the audio settings panel.
@onready var audio_panel: Panel = %AudioPanel

## Reference to the gameplay settings panel.
@onready var gameplay_panel: Panel = %GameplayPanel

## Reference to the controls settings panel.
@onready var controls_panel: Panel = %ControlsPanel

## Reference to the accessibility settings panel.
@onready var accessibility_panel: Panel = %AccessibilityPanel

## Category tab button for video settings.
@onready var video_button: Button = %VideoButton

## Category tab button for audio settings.
@onready var audio_button: Button = %AudioButton

## Category tab button for gameplay settings.
@onready var gameplay_button: Button = (
	%GameplayPanelButton if has_node("%GameplayPanelButton") else %GameplayButton
)

## Category tab button for controls settings.
@onready var controls_button: Button = %ControlsButton

## Category tab button for accessibility settings.
@onready var accessibility_button: Button = %AccessibilityButton

## Master back button returning the player to the main/pause menu.
@onready var master_back_button: Button = %MasterBackButton

## Reset to defaults button for active settings panels.
@onready var reset_defaults_button: Button = %ResetDefaultsButton

## TextureRect displaying the live diorama inside the video settings panel.
@onready var video_display: TextureRect = (
	video_panel.find_child("VideoDioramaDisplay", true, false) as TextureRect
)

## TextureRect displaying the live diorama inside the accessibility settings panel.
@onready var access_display: TextureRect = (
	accessibility_panel.find_child("AccessDioramaDisplay", true, false) as TextureRect
)

## Isolated SubViewport hosting the 3D settings diorama.
@onready
var diorama_viewport: SubViewport = find_child("DioramaViewport", true, false) as SubViewport


## Initializes the options router, configures the isolated diorama sandbox, and binds tabs.
func _ready() -> void:
	print("OptionsRouter: Initializing options router and diorama sandbox.")
	set_process(false)
	set_physics_process(false)

	_isolate_viewport_scenario()
	_connect_tab_buttons()

	if is_instance_valid(master_back_button):
		master_back_button.pressed.connect(_on_master_back_pressed)

	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

	visibility_changed.connect(_on_visibility_changed)
	_current_panel = video_panel
	_update_reset_button_visibility()
	_route_diorama_view(video_panel)
	_evaluate_diorama_state()


## Returns all options category panels as a typed array.
func get_all_panels() -> Array[Control]:
	return [
		video_panel,
		audio_panel,
		gameplay_panel,
		controls_panel,
		accessibility_panel,
	]


## Returns all category tab navigation buttons as a typed array.
func get_all_tab_buttons() -> Array[Button]:
	return [
		video_button,
		audio_button,
		gameplay_button,
		controls_button,
		accessibility_button,
	]


## Selects a category tab by its zero-based index.
func select_tab_by_index(index: int) -> void:
	var panels: Array[Control] = get_all_panels()
	if index >= 0 and index < panels.size():
		_on_tab_pressed(panels[index] as Panel)


## Puts the diorama sandbox into dormant sleep and purges it from memory.
func teardown_diorama() -> void:
	_purge_diorama()


## Configures the diorama [SubViewport] to completely dormant state.
func _isolate_viewport_scenario() -> void:
	if not is_instance_valid(diorama_viewport):
		return
	if not is_instance_valid(diorama_viewport.world_3d):
		diorama_viewport.world_3d = World3D.new()
	diorama_viewport.own_world_3d = true
	var dio_w: World3D = diorama_viewport.find_world_3d()
	if is_instance_valid(dio_w):
		dio_w.environment = null
	diorama_viewport.disable_3d = true
	diorama_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	diorama_viewport.process_mode = Node.PROCESS_MODE_DISABLED


## Instantiates the 3D diorama scene from scratch and neutralizes physics collisions.
func _rebuild_diorama() -> void:
	if not is_instance_valid(diorama_viewport):
		return
	if is_instance_valid(_instantiated_diorama):
		return

	print("OptionsRouter: Building fresh diorama sandbox from scratch.")
	if not is_instance_valid(diorama_viewport.world_3d):
		diorama_viewport.world_3d = World3D.new()
	diorama_viewport.own_world_3d = true

	VideoApplier.configure_diorama_sandbox(diorama_viewport)

	var raw_instance: Node = SETTINGS_LEVEL_SCENE.instantiate()
	if raw_instance is Node3D:
		_instantiated_diorama = raw_instance as Node3D
		diorama_viewport.add_child(_instantiated_diorama)
	elif is_instance_valid(raw_instance):
		raw_instance.queue_free()

	_neutralize_diorama_hotspots()
	_bind_diorama_textures()
	diorama_viewport.disable_3d = false
	diorama_viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	diorama_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE


## Destroys the diorama level, nullifies environment, and purges all GPU resources.
func _purge_diorama() -> void:
	print("OptionsRouter: Purging diorama sandbox from memory and GPU.")
	_deactivate_all_diorama_cameras()
	_set_preview_shader_active(false)

	if is_instance_valid(_instantiated_diorama):
		_instantiated_diorama.queue_free()
		_instantiated_diorama = null

	_graphics_camera = null
	_all_diorama_cameras.clear()
	_vision_meshes.clear()

	if is_instance_valid(diorama_viewport):
		diorama_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_viewport.process_mode = Node.PROCESS_MODE_DISABLED
		diorama_viewport.disable_3d = true
		var dio_w: World3D = diorama_viewport.find_world_3d()
		if is_instance_valid(dio_w):
			dio_w.environment = null

	GraphicsManager.set_diorama_mode(false)


## Binds the shared diorama [ViewportTexture] to the video and accessibility display rects.
func _bind_diorama_textures() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	var tex: ViewportTexture = diorama_viewport.get_texture()

	if is_instance_valid(video_display):
		video_display.texture = tex
		video_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		video_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	if is_instance_valid(access_display):
		access_display.texture = tex
		access_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		access_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	_preview_layer = diorama_viewport.get_node_or_null("PreviewShaderLayer") as CanvasLayer
	if not is_instance_valid(_preview_layer):
		_preview_layer = get_node_or_null("PreviewShaderLayer") as CanvasLayer

	_vision_meshes.clear()
	var meshes: Array[Node] = diorama_viewport.find_children(
		"VisionAssistMesh", "MeshInstance3D", true, false
	)
	for node: Node in meshes:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if is_instance_valid(mesh_inst):
			_vision_meshes.append(mesh_inst)


## Connects category tab buttons using typed Callables.
func _connect_tab_buttons() -> void:
	if is_instance_valid(video_button):
		video_button.pressed.connect(_on_tab_pressed.bind(video_panel))
	if is_instance_valid(audio_button):
		audio_button.pressed.connect(_on_tab_pressed.bind(audio_panel))
	if is_instance_valid(gameplay_button):
		gameplay_button.pressed.connect(_on_tab_pressed.bind(gameplay_panel))
	if is_instance_valid(controls_button):
		controls_button.pressed.connect(_on_tab_pressed.bind(controls_panel))
	if is_instance_valid(accessibility_button):
		accessibility_button.pressed.connect(_on_tab_pressed.bind(accessibility_panel))


## Disables physics processing on diorama props, assigns Layer 11, and caches cameras.
func _neutralize_diorama_hotspots() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	var env_nodes: Array[Node] = diorama_viewport.find_children(
		"*", "WorldEnvironment", true, false
	)
	for env_node: Node in env_nodes:
		var we: WorldEnvironment = env_node as WorldEnvironment
		if is_instance_valid(we) and is_instance_valid(we.environment):
			we.environment = we.environment.duplicate()
			var dio_world: World3D = diorama_viewport.find_world_3d()
			if is_instance_valid(dio_world):
				dio_world.environment = we.environment

	var bodies: Array[Node] = diorama_viewport.find_children("*", "CollisionObject3D", true, false)
	for b_node: Node in bodies:
		var c_obj: CollisionObject3D = b_node as CollisionObject3D
		if is_instance_valid(c_obj):
			c_obj.collision_layer = 0
			c_obj.collision_mask = 0
			c_obj.process_mode = Node.PROCESS_MODE_DISABLED

	_assign_visual_layer_recursive(diorama_viewport, 11)

	_all_diorama_cameras.clear()
	_graphics_camera = null
	var cams: Array[Node] = diorama_viewport.find_children("*", "Camera3D", true, false)
	for c_node: Node in cams:
		var cam: Camera3D = c_node as Camera3D
		if is_instance_valid(cam):
			cam.current = false
			if cam is ExtendedCamera3D:
				(cam as ExtendedCamera3D).is_player_camera = false
			_all_diorama_cameras.append(cam)
			if cam.name == &"Camera_graphics" or cam.name == &"Camera_Graphics":
				_graphics_camera = cam


## Evaluates whether the diorama should be active when options visibility changes.
func _on_visibility_changed() -> void:
	if not is_inside_tree():
		return
	_evaluate_diorama_state()


## Switches the active category tab and updates diorama routing.
func _on_tab_pressed(active_panel: Panel) -> void:
	if not is_instance_valid(active_panel):
		return
	print("OptionsRouter: Switching to category tab -> ", active_panel.name)
	_current_panel = active_panel

	video_panel.visible = (active_panel == video_panel)
	audio_panel.visible = (active_panel == audio_panel)
	gameplay_panel.visible = (active_panel == gameplay_panel)
	controls_panel.visible = (active_panel == controls_panel)
	accessibility_panel.visible = (active_panel == accessibility_panel)

	_update_reset_button_visibility()
	_route_diorama_view(active_panel)
	_evaluate_diorama_state()


## Shows the Reset Defaults button on tabs that support resetting (Video and Controls).
func _update_reset_button_visibility() -> void:
	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.visible = (
			_current_panel == video_panel or _current_panel == controls_panel
		)


## Routes the active diorama camera and vision assist meshes for the current tab.
func _route_diorama_view(active_panel: Panel) -> void:
	var is_video: bool = active_panel == video_panel
	var is_access: bool = active_panel == accessibility_panel

	for mesh: MeshInstance3D in _vision_meshes:
		if is_instance_valid(mesh):
			mesh.visible = is_access

	if is_video:
		_activate_graphics_camera()
	elif is_access:
		if (
			is_instance_valid(accessibility_panel)
			and accessibility_panel.has_method(&"_setup_diorama_cameras")
		):
			accessibility_panel.call(&"_setup_diorama_cameras")
	else:
		_deactivate_all_diorama_cameras()


## Synchronizes diorama viewport isolation via [GraphicsManager].
func _evaluate_diorama_state() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	var is_preview_tab: bool = (
		_current_panel == video_panel or _current_panel == accessibility_panel
	)
	var should_render: bool = is_visible_in_tree() and is_preview_tab

	if should_render:
		_rebuild_diorama()
		GraphicsManager.set_diorama_mode(true)
		_route_diorama_view(_current_panel)
	else:
		_purge_diorama()

	_set_preview_shader_active(should_render)


## Activates the primary graphics preview camera inside the diorama [SubViewport].
func _activate_graphics_camera() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	_deactivate_all_diorama_cameras()

	if is_instance_valid(_graphics_camera):
		_graphics_camera.cull_mask = PREVIEW_LAYER_MASK | VOLUMETRIC_LAYER_MASK
		_graphics_camera.current = true
		_graphics_camera.process_mode = Node.PROCESS_MODE_ALWAYS


## Deactivates all cameras belonging to the diorama [SubViewport].
func _deactivate_all_diorama_cameras() -> void:
	for cam: Camera3D in _all_diorama_cameras:
		if is_instance_valid(cam):
			cam.current = false
			cam.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_graphics_camera):
		_graphics_camera.current = false
		_graphics_camera.process_mode = Node.PROCESS_MODE_DISABLED


## Toggles the preview post-process shader layer inside the diorama.
func _set_preview_shader_active(is_active: bool) -> void:
	if is_instance_valid(_preview_layer):
		_preview_layer.visible = is_active
		_preview_layer.process_mode = (
			Node.PROCESS_MODE_ALWAYS if is_active else Node.PROCESS_MODE_DISABLED
		)


## Handles clicks on the master back button.
func _on_master_back_pressed() -> void:
	print("OptionsRouter: Master back button pressed.")
	teardown_diorama()
	back_requested.emit()


## Invokes `reset_to_defaults()` on the active panel (Video or Controls).
func _on_reset_defaults_pressed() -> void:
	print("OptionsRouter: Reset to defaults pressed.")
	if is_instance_valid(_current_panel) and _current_panel.has_method(&"reset_to_defaults"):
		_current_panel.call(&"reset_to_defaults")


## Recursively assigns 3D render layer bitmasks to all visual instances in the diorama.
func _assign_visual_layer_recursive(root: Node, layer_idx: int) -> void:
	var mask: int = 1 << (layer_idx - 1)
	var light_cull: int = mask | VOLUMETRIC_LAYER_MASK
	for child: Node in root.get_children():
		if child is Light3D:
			var light_node: Light3D = child as Light3D
			light_node.layers = mask
			light_node.light_cull_mask = light_cull
		elif child is FogVolume:
			(child as FogVolume).layers = VOLUMETRIC_LAYER_MASK
		elif child is VisualInstance3D:
			(child as VisualInstance3D).layers = mask
		_assign_visual_layer_recursive(child, layer_idx)
