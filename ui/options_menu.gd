## Coordinates options tabs, socket reparenting, and diorama rendering state.
## Enforces UPDATE_DISABLED on [SubViewport] whenever preview tabs are inactive
## to protect frame rate budget.
class_name OptionsRouter
extends Control

@warning_ignore("unused_signal")
## Emitted when the player clicks the master back button.
signal back_requested

## Target resolution width for the preview viewport when rendering.
const PREVIEW_WIDTH: int = 640

## Target resolution height for the preview viewport when rendering.
const PREVIEW_HEIGHT: int = 360

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

## Shared diorama container holding the preview viewport.
var diorama_container: SubViewportContainer = null

## Target mount socket in the video panel.
var video_socket: Control = null

## Target mount socket in the accessibility panel.
var access_socket: Control = null

## Default home base container when diorama is detached from sub-panels.
var home_holder: Control = null

## Cached reference to the preview SubViewport node.
var _diorama_viewport: SubViewport = null

## Cached reference to the preview 3D camera.
var _graphics_camera: Camera3D = null

## Currently selected settings panel.
var _current_panel: Panel = null

## Cached reference to the preview shader layer.
var _preview_layer: CanvasLayer = null

## Cached list of vision assist mesh nodes inside the diorama.
var _vision_meshes: Array[MeshInstance3D] = []


## Lifecycle initialization discovering sockets, buttons, and diorama nodes.
func _ready() -> void:
	print("UI: OptionsRouter initialized.")
	_discover_diorama_nodes()
	_connect_tab_buttons()

	if is_instance_valid(master_back_button):
		master_back_button.pressed.connect(_on_master_back_pressed)

	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)

	visibility_changed.connect(_on_visibility_changed)
	_on_tab_pressed(video_panel)


## Connects all tab navigation buttons to their respective handlers.
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


## Returns all options sub-panels as a typed array.
## [return] Array of panel control instances.
func get_all_panels() -> Array[Control]:
	return [video_panel, audio_panel, gameplay_panel, controls_panel, accessibility_panel]


## Returns all category tab buttons as a typed array.
## [return] Array of button instances.
func get_all_tab_buttons() -> Array[Button]:
	return [video_button, audio_button, gameplay_button, controls_button, accessibility_button]


## Opens a specific tab by integer index and enforces diorama evaluation.
## [param index] Index corresponding to the options panel.
func select_tab_by_index(index: int) -> void:
	var panels: Array[Control] = get_all_panels()
	if index >= 0 and index < panels.size():
		_on_tab_pressed(panels[index] as Panel)


## Intercepts visibility changes on the options overlay.
func _on_visibility_changed() -> void:
	print("UI: OptionsRouter visibility changed -> ", is_visible_in_tree())
	_evaluate_diorama_state()


## Switches active settings tab visibility and re-routes preview widgets.
## [param active_panel] Target panel selected by player.
func _on_tab_pressed(active_panel: Panel) -> void:
	print("UI: Swapped options category tab -> ", active_panel.name)
	_current_panel = active_panel

	video_panel.visible = (active_panel == video_panel)
	audio_panel.visible = (active_panel == audio_panel)
	gameplay_panel.visible = (active_panel == gameplay_panel)
	controls_panel.visible = (active_panel == controls_panel)
	accessibility_panel.visible = (active_panel == accessibility_panel)

	if is_instance_valid(reset_defaults_button):
		reset_defaults_button.visible = (active_panel == controls_panel)

	_dock_diorama(active_panel)
	_evaluate_diorama_state()


## Reparents the diorama container into the active panel preview socket.
## [param active_panel] Active settings panel.
func _dock_diorama(active_panel: Panel) -> void:
	if not is_instance_valid(diorama_container):
		return

	var target_parent: Node = null
	if active_panel == video_panel and is_instance_valid(video_socket):
		target_parent = video_socket
	elif active_panel == accessibility_panel and is_instance_valid(access_socket):
		target_parent = access_socket

	if target_parent != null:
		if diorama_container.get_parent() != target_parent:
			print("UI: Docking DioramaContainer into socket: ", target_parent.name)
			diorama_container.reparent(target_parent)

		diorama_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		diorama_container.size_flags_horizontal = (Control.SIZE_EXPAND | Control.SIZE_FILL)
		diorama_container.size_flags_vertical = (Control.SIZE_EXPAND | Control.SIZE_FILL)
		diorama_container.stretch = true
		diorama_container.visible = true

		var is_access: bool = active_panel == accessibility_panel
		_set_diorama_vision_assist_active(is_access)

		if active_panel == video_panel:
			_activate_graphics_camera()
		elif active_panel == accessibility_panel:
			if (
				is_instance_valid(accessibility_panel)
				and accessibility_panel.has_method("_setup_diorama_cameras")
			):
				accessibility_panel.call("_setup_diorama_cameras")
	else:
		if is_instance_valid(home_holder):
			if diorama_container.get_parent() != home_holder:
				print("UI: Undocking DioramaContainer to home holder.")
				diorama_container.reparent(home_holder)
		diorama_container.visible = false


## Evaluates conditions and sets [SubViewport] update mode.
func _evaluate_diorama_state() -> void:
	if not is_instance_valid(_diorama_viewport):
		_discover_diorama_nodes()

	if not is_instance_valid(_diorama_viewport):
		return

	var is_preview_tab: bool = (
		_current_panel == video_panel or _current_panel == accessibility_panel
	)
	var is_rendered: bool = is_visible_in_tree() and is_preview_tab

	print("UI: OptionsRouter -> Diorama update mode evaluated. Active: ", is_rendered)

	_diorama_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_diorama_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if is_rendered else SubViewport.UPDATE_DISABLED
	)
	_diorama_viewport.process_mode = (
		Node.PROCESS_MODE_INHERIT if is_rendered else Node.PROCESS_MODE_DISABLED
	)

	if is_rendered:
		if _current_panel == video_panel:
			_activate_graphics_camera()
		elif _current_panel == accessibility_panel:
			if (
				is_instance_valid(accessibility_panel)
				and accessibility_panel.has_method("_setup_diorama_cameras")
			):
				accessibility_panel.call("_setup_diorama_cameras")

	_set_preview_shader_active(is_rendered)


## Activates the CCTV preview camera node.
func _activate_graphics_camera() -> void:
	if not is_instance_valid(diorama_container):
		return

	if not is_instance_valid(_graphics_camera):
		# Find ANY Camera3D inside the diorama viewport if the specific name is missing
		_graphics_camera = (
			diorama_container.find_child("Camera_graphics", true, false) as Camera3D
		)
		if not is_instance_valid(_graphics_camera):
			_graphics_camera = (
				diorama_container.find_child("Camera_Graphics", true, false) as Camera3D
			)
		if not is_instance_valid(_graphics_camera) and is_instance_valid(_diorama_viewport):
			var cams: Array[Node] = _diorama_viewport.find_children("", "Camera3D", true, false)
			if not cams.is_empty():
				_graphics_camera = cams[0] as Camera3D

	if is_instance_valid(_graphics_camera):
		print("UI: Activating Graphics preview Camera3D: ", _graphics_camera.get_path())
		_graphics_camera.current = true
	else:
		push_error("UI ERROR: No Camera3D found inside DioramaViewport!")


## Toggles vision assist quad meshes inside the preview scene.
## [param enable_assist] True if accessibility overlays should show.
func _set_diorama_vision_assist_active(enable_assist: bool) -> void:
	if not is_instance_valid(diorama_container):
		return

	print("UI: Toggling VisionAssistMesh instances: ", enable_assist)
	var vision_meshes: Array[Node] = diorama_container.find_children(
		"VisionAssistMesh", "MeshInstance3D", true, false
	)
	for mesh_node: Node in vision_meshes:
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		mesh_instance.visible = enable_assist


## Controls the preview shader pass canvas layer.
## [param is_active] True if shader pass is active.
func _set_preview_shader_active(is_active: bool) -> void:
	var preview_layer: CanvasLayer = get_node_or_null("PreviewShaderLayer") as CanvasLayer
	if not is_instance_valid(preview_layer):
		preview_layer = (
			get_tree().root.find_child("PreviewShaderLayer", true, false) as CanvasLayer
		)

	if is_instance_valid(preview_layer):
		print("UI: Setting PreviewShaderLayer visibility: ", is_active)
		preview_layer.visible = is_active
		preview_layer.process_mode = (
			Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
		)


## Discovers viewport, container, and target socket nodes safely.
func _discover_diorama_nodes() -> void:
	print("UI: Discovering diorama nodes and panel sockets.")
	home_holder = find_child("SharedDioramaHolder", true, false) as Control
	diorama_container = (find_child("DioramaContainer", true, false) as SubViewportContainer)

	if is_instance_valid(diorama_container):
		# Setting stretch_shrink to 2 or 3 divides internal viewport pixel dimensions
		# by 2 or 3 while keeping UI socket bounding intact.
		diorama_container.stretch = true
		diorama_container.stretch_shrink = 2
		_diorama_viewport = (
			diorama_container.find_child("DioramaViewport", true, false) as SubViewport
		)
	else:
		_diorama_viewport = find_child("DioramaViewport", true, false) as SubViewport

	if is_instance_valid(_diorama_viewport):
		_diorama_viewport.own_world_3d = true
		# Do NOT set _diorama_viewport.size manually here; stretch_shrink handles it.
		_diorama_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_diorama_viewport.process_mode = Node.PROCESS_MODE_DISABLED
		_diorama_viewport.positional_shadow_atlas_size = 512
		_diorama_viewport.msaa_3d = Viewport.MSAA_DISABLED
		_diorama_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_diorama_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

	if is_instance_valid(diorama_container):
		_vision_meshes.clear()
		var meshes: Array[Node] = diorama_container.find_children(
			"VisionAssistMesh", "MeshInstance3D", true, false
		)
		for node: Node in meshes:
			_vision_meshes.append(node as MeshInstance3D)

	_preview_layer = get_node_or_null("PreviewShaderLayer") as CanvasLayer
	if not is_instance_valid(_preview_layer):
		_preview_layer = (
			get_tree().root.find_child("PreviewShaderLayer", true, false) as CanvasLayer
		)

	if is_instance_valid(video_panel):
		video_socket = (video_panel.find_child("VideoDioramaSocket", true, false) as Control)

	if is_instance_valid(accessibility_panel):
		access_socket = (
			accessibility_panel.find_child("AccessibilityDioramaSocket", true, false) as Control
		)


## Handles master back button clicks and notifies the main menu coordinator.
func _on_master_back_pressed() -> void:
	print("UI: Options MasterBackButton pressed.")
	back_requested.emit()


## Relays reset call to [ControlsPanel] if currently active and visible.
func _on_reset_defaults_pressed() -> void:
	print("UI: Reset defaults requested on active panel.")
	if is_instance_valid(controls_panel) and controls_panel.visible:
		if controls_panel.has_method("reset_to_defaults"):
			controls_panel.call("reset_to_defaults")
