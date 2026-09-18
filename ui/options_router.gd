## Coordinates options tabs, diorama display routing, and viewport updates.
class_name OptionsRouter
extends Control

@warning_ignore("unused_signal")
## Emitted when the player clicks the master back button.
signal back_requested

## Visual layer bitmask assigned to diorama geometry (Layer 11).
const PREVIEW_LAYER_MASK: int = 1 << 10
## Visual layer bitmask assigned to volumetric fog volumes (Layer 10).
const VOLUMETRIC_LAYER_MASK: int = 1 << 9

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

## Button switching to video settings.
@onready var video_button: Button = %VideoButton

## Button switching to audio settings.
@onready var audio_button: Button = %AudioButton

## Button switching to gameplay settings.
@onready var gameplay_button: Button = %GameplayButton

## Button switching to controls settings.
@onready var controls_button: Button = %ControlsButton

## Button switching to accessibility settings.
@onready var accessibility_button: Button = %AccessibilityButton

## Master exit button returning the player to the primary title screen view.
@onready var master_back_button: Button = %MasterBackButton

## Button to reset active panel settings back to default.
@onready var reset_defaults_button: Button = %ResetDefaultsButton

## TextureRect displaying diorama in video panel.
@onready var video_display: TextureRect = (
	video_panel.find_child("VideoDioramaDisplay", true, false) as TextureRect
)

## TextureRect displaying diorama in accessibility panel.
@onready var access_display: TextureRect = (
	accessibility_panel.find_child("AccessDioramaDisplay", true, false) as TextureRect
)

## Cached reference to the preview SubViewport node.
@onready
var diorama_viewport: SubViewport = find_child("DioramaViewport", true, false) as SubViewport

## Cached reference to the preview 3D camera.
var _graphics_camera: Camera3D = null

## Currently selected settings panel.
var _current_panel: Panel = null

## Cached reference to the preview shader layer.
var _preview_layer: CanvasLayer = null

## Cached list of vision assist mesh nodes inside the diorama.
var _vision_meshes: Array[MeshInstance3D] = []


## Lifecycle initialization hooking textures and event signals.
func _ready() -> void:
	print("UI: OptionsRouter initialized.")
	_bind_diorama_textures()
	_connect_tab_buttons()

	if is_instance_valid(master_back_button):
		master_back_button.pressed.connect(_on_master_back_pressed)

	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

	visibility_changed.connect(_on_visibility_changed)
	_current_panel = video_panel

	if is_instance_valid(diorama_viewport):
		if not diorama_viewport.own_world_3d:
			print("UI: Forcing own_world_3d on diorama initialization.")
			diorama_viewport.own_world_3d = true

		var settings_lvl: Node = diorama_viewport.find_child("SettingsLevel", true, false)
		if is_instance_valid(settings_lvl):
			print("UI: Isolating SettingsLevel nodes to visual layer 11.")
			_assign_visual_layer_recursive(settings_lvl, 11)

	_route_diorama_view(video_panel)
	_evaluate_diorama_state()


## Binds the shared diorama ViewportTexture to preview displays.
func _bind_diorama_textures() -> void:
	if not is_instance_valid(diorama_viewport):
		push_error("UI ERROR: DioramaViewport not found.")
		return

	print("UI: Binding Diorama ViewportTexture to static sockets.")
	var tex: ViewportTexture = diorama_viewport.get_texture()

	if is_instance_valid(video_display):
		video_display.texture = tex
		video_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		video_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	if is_instance_valid(access_display):
		access_display.texture = tex
		access_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		access_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

	_preview_layer = get_node_or_null("PreviewShaderLayer") as CanvasLayer
	if not is_instance_valid(_preview_layer):
		_preview_layer = (
			get_tree().root.find_child("PreviewShaderLayer", true, false) as CanvasLayer
		)

	_vision_meshes.clear()
	var meshes: Array[Node] = diorama_viewport.find_children(
		"VisionAssistMesh", "MeshInstance3D", true, false
	)
	for node: Node in meshes:
		_vision_meshes.append(node as MeshInstance3D)


## Connects all tab navigation buttons to their respective handlers.
func _connect_tab_buttons() -> void:
	print("UI: Connecting tab navigation buttons.")
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


## Returns all options sub-panels as a typed array.
func get_all_panels() -> Array[Control]:
	print("UI: Querying all options sub-panels.")
	return [video_panel, audio_panel, gameplay_panel, controls_panel, accessibility_panel]


## Returns all category tab buttons as a typed array.
func get_all_tab_buttons() -> Array[Button]:
	print("UI: Querying all category tab buttons.")
	return [video_button, audio_button, gameplay_button, controls_button, accessibility_button]


## Opens a specific tab by integer index and updates diorama.
## [param index] Category tab index.
func select_tab_by_index(index: int) -> void:
	print("UI: Selecting tab by index: ", index)
	var panels: Array[Control] = get_all_panels()
	if index >= 0 and index < panels.size():
		_on_tab_pressed(panels[index] as Panel)


## Intercepts visibility changes on the options overlay.
func _on_visibility_changed() -> void:
	print("UI: OptionsRouter visibility changed -> ", is_visible_in_tree())
	_evaluate_diorama_state()


## Switches active tab and updates diorama camera routing.
## [param active_panel] Target panel to display.
func _on_tab_pressed(active_panel: Panel) -> void:
	print("UI: Swapped options category tab -> ", active_panel.name)
	_current_panel = active_panel

	video_panel.visible = active_panel == video_panel
	audio_panel.visible = active_panel == audio_panel
	gameplay_panel.visible = active_panel == gameplay_panel
	controls_panel.visible = active_panel == controls_panel
	accessibility_panel.visible = active_panel == accessibility_panel

	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.visible = active_panel == controls_panel

	_route_diorama_view(active_panel)
	_evaluate_diorama_state()


## Routes camera and shaders to match the active tab without reparenting.
## [param active_panel] Active settings subpanel.
func _route_diorama_view(active_panel: Panel) -> void:
	print("UI: Routing diorama view for panel -> ", active_panel.name)
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
			and accessibility_panel.has_method("_setup_diorama_cameras")
		):
			accessibility_panel.call("_setup_diorama_cameras")
	else:
		_deactivate_graphics_camera()


## Evaluates conditions and sets [SubViewport] update mode.
func _evaluate_diorama_state() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	var is_preview: bool = _current_panel == video_panel or _current_panel == accessibility_panel
	var should_render: bool = is_visible_in_tree() and is_preview
	print("UI: Diorama rendering state updated -> ", should_render)

	if should_render:
		diorama_viewport.process_mode = Node.PROCESS_MODE_INHERIT
		diorama_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_activate_graphics_camera()
	else:
		diorama_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_viewport.process_mode = Node.PROCESS_MODE_DISABLED
		_deactivate_graphics_camera()

	_set_preview_shader_active(should_render)


## Forcibly deactivates diorama rendering and camera to release GPU resources.
func teardown_diorama() -> void:
	print("UI: Tearing down diorama viewport.")
	_deactivate_graphics_camera()
	if is_instance_valid(diorama_viewport):
		diorama_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_viewport.process_mode = Node.PROCESS_MODE_DISABLED
	_set_preview_shader_active(false)


## Renders two warmup frames to pre-allocate GPU froxels and pipelines.
func warmup_diorama() -> void:
	if not is_instance_valid(diorama_viewport):
		return
	print("UI: Pre-allocating diorama pipeline buffers.")
	if not diorama_viewport.own_world_3d:
		diorama_viewport.own_world_3d = true

	_activate_graphics_camera()
	diorama_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	diorama_viewport.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().process_frame
	await get_tree().process_frame

	# Check active panel state rather than unconditionally killing the viewport
	_evaluate_diorama_state()


## Activates and isolates the preview camera node inside [SubViewport].
func _activate_graphics_camera() -> void:
	print("UI: Activating diorama graphics camera.")
	if not is_instance_valid(diorama_viewport):
		return

	if not is_instance_valid(_graphics_camera):
		_graphics_camera = diorama_viewport.find_child("Camera_graphics", true, false) as Camera3D
		if not is_instance_valid(_graphics_camera):
			_graphics_camera = (
				diorama_viewport.find_child("Camera_Graphics", true, false) as Camera3D
			)

	if is_instance_valid(_graphics_camera):
		# Render Layer 11 (Geometry) and Layer 10 (Volumetrics)
		_graphics_camera.cull_mask = PREVIEW_LAYER_MASK | VOLUMETRIC_LAYER_MASK
		_graphics_camera.current = true
		_graphics_camera.process_mode = Node.PROCESS_MODE_INHERIT


## Deactivates the preview camera so it yields priority to gameplay cameras.
func _deactivate_graphics_camera() -> void:
	print("UI: Deactivating diorama graphics camera.")
	if is_instance_valid(_graphics_camera):
		_graphics_camera.current = false


## Controls the preview shader pass canvas layer.
## [param is_active] True if active.
func _set_preview_shader_active(is_active: bool) -> void:
	if is_instance_valid(_preview_layer):
		_preview_layer.visible = is_active
		_preview_layer.process_mode = (
			Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
		)


## Handles master back button clicks and notifies the main menu coordinator.
func _on_master_back_pressed() -> void:
	print("UI: Master back button pressed.")
	teardown_diorama()
	back_requested.emit()


## Relays reset call to [ControlsPanel] if currently active and visible.
func _on_reset_defaults_pressed() -> void:
	print("UI: Reset defaults pressed.")
	if is_instance_valid(controls_panel) and controls_panel.visible:
		if controls_panel.has_method("reset_to_defaults"):
			controls_panel.call("reset_to_defaults")


## Traverses node hierarchy and applies 3D visual layer bitmask.
## [param root] Target branch node.
## [param layer_idx] 1-based visual layer index.
func _assign_visual_layer_recursive(root: Node, layer_idx: int) -> void:
	var mask: int = 1 << (layer_idx - 1)
	for child: Node in root.get_children():
		if child is VisualInstance3D:
			(child as VisualInstance3D).layers = mask
		elif child is Light3D:
			(child as Light3D).light_cull_mask = mask
		_assign_visual_layer_recursive(child, layer_idx)
