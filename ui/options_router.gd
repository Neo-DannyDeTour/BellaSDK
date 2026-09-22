## Coordinates options tabs, diorama display routing, and viewport updates.
class_name OptionsRouter
extends Control

@warning_ignore("unused_signal")
## Emitted when the player activates [member master_back_button] to exit.
signal back_requested

## Visual layer bitmask assigned to diorama preview geometry (Layer 11).
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

## Cached array of all secondary cameras residing in the diorama scene.
var _all_diorama_cameras: Array[Camera3D] = []


## Lifecycle initialization hooking textures, scenarios, and signals.
func _ready() -> void:
	print("OptionsRouter: Initializing UI router and isolating diorama.")
	_isolate_viewport_scenario()
	_neutralize_diorama_hotspots()
	_bind_diorama_textures()
	_connect_tab_buttons()

	if is_instance_valid(master_back_button):
		master_back_button.pressed.connect(_on_master_back_pressed)

	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

	visibility_changed.connect(_on_visibility_changed)
	_current_panel = video_panel

	_route_diorama_view(video_panel)
	_evaluate_diorama_state()


## Assigns an isolated [World3D] instance safely to prevent scenario cross-talk.
func _isolate_viewport_scenario() -> void:
	print("OptionsRouter: Verifying DioramaViewport scenario isolation.")
	if not is_instance_valid(diorama_viewport):
		return

	diorama_viewport.own_world_3d = true
	if diorama_viewport.world_3d == null or diorama_viewport.world_3d == get_tree().root.world_3d:
		var iso_world: World3D = World3D.new()
		iso_world.environment = Environment.new()
		diorama_viewport.world_3d = iso_world
		print("OptionsRouter: Instantiated distinct World3D and Environment.")


## Binds the shared diorama ViewportTexture to preview displays.
func _bind_diorama_textures() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	print("OptionsRouter: Binding ViewportTexture to preview sockets.")
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
	print("OptionsRouter: Connecting category tab signals.")
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


## Strips physics collisions and isolates render layers inside the preview.
func _neutralize_diorama_hotspots() -> void:
	print("OptionsRouter: Neutralizing collisions and lights in preview.")
	if not is_instance_valid(diorama_viewport):
		return

	# Strip all collisions inside the diorama to prevent physics space contamination
	var bodies: Array[Node] = diorama_viewport.find_children("*", "CollisionObject3D", true, false)
	for b_node: Node in bodies:
		var c_obj: CollisionObject3D = b_node as CollisionObject3D
		if is_instance_valid(c_obj):
			c_obj.collision_layer = 0
			c_obj.collision_mask = 0
			c_obj.process_mode = Node.PROCESS_MODE_DISABLED

	_assign_visual_layer_recursive(diorama_viewport, 11)

	_all_diorama_cameras.clear()
	var cams: Array[Node] = diorama_viewport.find_children("*", "Camera3D", true, false)
	for c_node: Node in cams:
		var cam: Camera3D = c_node as Camera3D
		if is_instance_valid(cam):
			cam.current = false
			_all_diorama_cameras.append(cam)

	var mirrors: Array[Node] = diorama_viewport.find_children("*", "Mirror", true, false)
	for m_node: Node in mirrors:
		m_node.process_mode = Node.PROCESS_MODE_DISABLED
		if m_node is Node3D:
			(m_node as Node3D).visible = false


## Returns all options sub-panels as a typed array.
func get_all_panels() -> Array[Control]:
	return [video_panel, audio_panel, gameplay_panel, controls_panel, accessibility_panel]


## Returns all category tab buttons as a typed array.
func get_all_tab_buttons() -> Array[Button]:
	return [video_button, audio_button, gameplay_button, controls_button, accessibility_button]


## Opens a specific tab by integer index and updates diorama.
func select_tab_by_index(index: int) -> void:
	print("OptionsRouter: Selecting tab index: ", index)
	var panels: Array[Control] = get_all_panels()
	if index >= 0 and index < panels.size():
		_on_tab_pressed(panels[index] as Panel)


## Intercepts visibility changes on the options overlay.
func _on_visibility_changed() -> void:
	print("OptionsRouter: Panel visibility changed: ", is_visible_in_tree())
	_evaluate_diorama_state()


## Switches active tab and updates diorama camera routing.
func _on_tab_pressed(active_panel: Panel) -> void:
	print("OptionsRouter: Selected panel: ", active_panel.name)
	_current_panel = active_panel

	video_panel.visible = (active_panel == video_panel)
	audio_panel.visible = (active_panel == audio_panel)
	gameplay_panel.visible = (active_panel == gameplay_panel)
	controls_panel.visible = (active_panel == controls_panel)
	accessibility_panel.visible = (active_panel == accessibility_panel)

	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.visible = (active_panel == controls_panel)

	_route_diorama_view(active_panel)
	_evaluate_diorama_state()


## Routes camera and shaders to match the active tab without reparenting.
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
			and accessibility_panel.has_method("_setup_diorama_cameras")
		):
			accessibility_panel.call("_setup_diorama_cameras")
	else:
		_deactivate_all_diorama_cameras()


## Evaluates conditions and sets [SubViewport] update mode.
func _evaluate_diorama_state() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	var is_preview: bool = _current_panel == video_panel or _current_panel == accessibility_panel
	var should_render: bool = is_visible_in_tree() and is_preview
	print("OptionsRouter: Diorama render update mode: ", should_render)

	if should_render:
		diorama_viewport.process_mode = Node.PROCESS_MODE_INHERIT
		diorama_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_activate_graphics_camera()
	else:
		diorama_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_viewport.process_mode = Node.PROCESS_MODE_DISABLED
		_deactivate_all_diorama_cameras()

	_set_preview_shader_active(should_render)


## Forcibly deactivates diorama rendering and camera to release GPU resources.
func teardown_diorama() -> void:
	print("OptionsRouter: Tearing down diorama viewport safely.")
	_deactivate_all_diorama_cameras()
	if is_instance_valid(diorama_viewport):
		diorama_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		diorama_viewport.process_mode = Node.PROCESS_MODE_DISABLED
	_set_preview_shader_active(false)


## Activates and isolates the preview camera node inside [SubViewport].
func _activate_graphics_camera() -> void:
	if not is_instance_valid(diorama_viewport):
		return

	_deactivate_all_diorama_cameras()

	if not is_instance_valid(_graphics_camera):
		_graphics_camera = diorama_viewport.find_child("Camera_graphics", true, false) as Camera3D
		if not is_instance_valid(_graphics_camera):
			_graphics_camera = (
				diorama_viewport.find_child("Camera_Graphics", true, false) as Camera3D
			)

	if is_instance_valid(_graphics_camera):
		_graphics_camera.cull_mask = PREVIEW_LAYER_MASK | VOLUMETRIC_LAYER_MASK
		_graphics_camera.current = true
		_graphics_camera.process_mode = Node.PROCESS_MODE_INHERIT


## Deactivates ONLY cameras belonging strictly to the diorama subviewport.
func _deactivate_all_diorama_cameras() -> void:
	print("OptionsRouter: Safely disabling diorama-only camera nodes.")
	for cam: Camera3D in _all_diorama_cameras:
		if is_instance_valid(cam):
			cam.current = false
	if is_instance_valid(_graphics_camera):
		_graphics_camera.current = false


## Controls the preview shader pass canvas layer.
func _set_preview_shader_active(is_active: bool) -> void:
	if is_instance_valid(_preview_layer):
		_preview_layer.visible = is_active
		_preview_layer.process_mode = (
			Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
		)


## Handles master back button clicks and notifies the main menu coordinator.
func _on_master_back_pressed() -> void:
	print("OptionsRouter: Master back button clicked.")
	teardown_diorama()
	back_requested.emit()


## Relays reset call to [ControlsPanel] if currently active and visible.
func _on_reset_defaults_pressed() -> void:
	if is_instance_valid(controls_panel) and controls_panel.visible:
		if controls_panel.has_method("reset_to_defaults"):
			controls_panel.call("reset_to_defaults")


## Traverses node hierarchy and applies 3D visual layer bitmask.
func _assign_visual_layer_recursive(root: Node, layer_idx: int) -> void:
	var mask: int = 1 << (layer_idx - 1)
	for child: Node in root.get_children():
		if child is VisualInstance3D:
			(child as VisualInstance3D).layers = mask
		elif child is Light3D:
			(child as Light3D).light_cull_mask = mask
		_assign_visual_layer_recursive(child, layer_idx)
