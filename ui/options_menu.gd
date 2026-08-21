## Manages routing between options categories and reparents the shared
## preview diorama viewport between the video and accessibility panels.
class_name OptionsRouter
extends Control

## Reference to the video settings [Panel].
@onready var video_panel: Panel = %VideoOptionsPanel
## Reference to the audio settings [Panel].
@onready var audio_panel: Panel = %AudioPanel
## Reference to the gameplay settings [Panel].
@onready var gameplay_panel: Panel = %GameplayPanel
## Reference to the controls settings [Panel].
@onready var controls_panel: Panel = %ControlsPanel
## Reference to the accessibility settings [Panel].
@onready var accessibility_panel: Panel = %AccessibilityPanel

## Button to switch to the video panel.
@onready var video_button: Button = %VideoButton
## Button to switch to the audio panel.
@onready var audio_button: Button = %AudioButton
## Button to switch to the gameplay panel.
@onready var gameplay_button: Button = %GameplayButton
## Button to switch to the controls panel.
@onready var controls_button: Button = %ControlsButton
## Button to switch to the accessibility panel.
@onready var accessibility_button: Button = %AccessibilityButton

## Reference to the shared diorama container widget.
var diorama_container: SubViewportContainer = null
## Placeholder socket node inside the video options panel.
var video_socket: Control = null
## Placeholder socket node inside the accessibility panel.
var access_socket: Control = null
## Cached reference to the dedicated graphics overview camera.
var _graphics_camera: Camera3D = null


## Lifecycle initialization discovering sockets and the diorama container safely.
func _ready() -> void:
	print("UI: Options routing system initialized.")

	_discover_diorama_nodes()

	video_button.pressed.connect(_on_tab_pressed.bind(video_panel))
	audio_button.pressed.connect(_on_tab_pressed.bind(audio_panel))
	gameplay_button.pressed.connect(_on_tab_pressed.bind(gameplay_panel))
	controls_button.pressed.connect(_on_tab_pressed.bind(controls_panel))
	accessibility_button.pressed.connect(_on_tab_pressed.bind(accessibility_panel))

	_on_tab_pressed(video_panel)


## Switches visibility of settings tabs and moves the diorama to the active socket.
## [param active_panel] The panel that was selected.
func _on_tab_pressed(active_panel: Panel) -> void:
	print("UI: Player swapped options tab to: ", active_panel.name)

	video_panel.visible = (active_panel == video_panel)
	audio_panel.visible = (active_panel == audio_panel)
	gameplay_panel.visible = (active_panel == gameplay_panel)
	controls_panel.visible = (active_panel == controls_panel)
	accessibility_panel.visible = (active_panel == accessibility_panel)

	_route_diorama(active_panel)


## Reparents the single preview diorama container into the active panel socket.
## [param active_panel] The currently displayed settings panel.
func _route_diorama(active_panel: Panel) -> void:
	if not is_instance_valid(diorama_container):
		return

	var target_parent: Node = null
	if active_panel == video_panel and is_instance_valid(video_socket):
		target_parent = video_socket
	elif active_panel == accessibility_panel and is_instance_valid(access_socket):
		target_parent = access_socket

	if target_parent != null:
		if diorama_container.get_parent() != target_parent:
			print("UI: Reparenting shared diorama into ", target_parent.name)
			diorama_container.reparent(target_parent)

		diorama_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		diorama_container.size_flags_horizontal = (Control.SIZE_EXPAND | Control.SIZE_FILL)
		diorama_container.size_flags_vertical = (Control.SIZE_EXPAND | Control.SIZE_FILL)
		diorama_container.stretch = true
		diorama_container.visible = true

		var is_access_tab: bool = active_panel == accessibility_panel
		_set_diorama_vision_assist_active(is_access_tab)

		if active_panel == video_panel:
			_activate_graphics_camera()
		elif active_panel == accessibility_panel:
			if (
				is_instance_valid(accessibility_panel)
				and accessibility_panel.has_method("_setup_diorama_cameras")
			):
				accessibility_panel.call("_setup_diorama_cameras")
	else:
		diorama_container.visible = false


## Activates the dedicated clean CCTV graphics preview camera.
func _activate_graphics_camera() -> void:
	if not is_instance_valid(_graphics_camera):
		_graphics_camera = diorama_container.find_child("Camera_graphics", true, false) as Camera3D
		if not is_instance_valid(_graphics_camera):
			_graphics_camera = (
				diorama_container.find_child("Camera_Graphics", true, false) as Camera3D
			)

	if is_instance_valid(_graphics_camera):
		print("UI: Activating Graphics CCTV preview camera.")
		_graphics_camera.make_current()


## Toggles visibility on all diorama vision assist quad meshes.
## [param enable_assist] Flag determining if accessibility shaders are active.
func _set_diorama_vision_assist_active(enable_assist: bool) -> void:
	print("UI: Setting diorama vision assist meshes active: ", enable_assist)
	if not is_instance_valid(diorama_container):
		return

	var vision_meshes: Array[Node] = diorama_container.find_children(
		"VisionAssistMesh", "MeshInstance3D", true, false
	)
	for mesh_node: Node in vision_meshes:
		var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
		mesh_instance.visible = enable_assist


## Dynamically locates the diorama container and socket nodes across sub-panels.
func _discover_diorama_nodes() -> void:
	print("UI: Discovering diorama container and panel sockets.")
	diorama_container = (find_child("DioramaContainer", true, false) as SubViewportContainer)

	if is_instance_valid(video_panel):
		video_socket = (video_panel.find_child("VideoDioramaSocket", true, false) as Control)

	if is_instance_valid(accessibility_panel):
		access_socket = (
			accessibility_panel.find_child("AccessibilityDioramaSocket", true, false) as Control
		)

	if not is_instance_valid(diorama_container):
		push_warning("UI: Shared DioramaContainer node could not be found.")
