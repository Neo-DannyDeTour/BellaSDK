## Manages developer debug overlays, noclip status alerts,
## fullbright, wireframe, and collision visualizers.
class_name DebugOverlay
extends CanvasLayer

## Container managing the layout of the noclip warning alert.
@onready var noclip_alert_container: MarginContainer = $NoclipAlertContainer

## Panel background for the noclip alert message.
@onready var noclip_message_container: PanelContainer = $NoclipAlertContainer/NoclipMessageContainer

## Label displaying the current noclip speed or status.
@onready
var noclip_label_message: Label = $NoclipAlertContainer/NoclipMessageContainer/NoclipLabelMessage

## Panel containing the developer debug buttons.
@onready var debug_panel: PanelContainer = $DebugPanel/PanelContainer

## Button to toggle noclip mode.
@onready var noclip_button: Button = $DebugPanel/PanelContainer/VBoxContainer/NoclipButton

## Button to toggle the performance metrics window.
@onready var metrics_button: Button = $DebugPanel/PanelContainer/VBoxContainer/MetricsButton

## Button to toggle visibility of collision shapes.
@onready var collision_button: Button = $DebugPanel/PanelContainer/VBoxContainer/CollisionButton

## Button to toggle fullbright rendering mode.
@onready var fullbright_button: Button = $DebugPanel/PanelContainer/VBoxContainer/FullbrightButton

## Button to toggle wireframe rendering mode.
@onready var wireframe_button: Button = $DebugPanel/PanelContainer/VBoxContainer/WireframeButton

## Button used to toggle the green wireframe material overlay.
@onready var wireframe_overlay_button: Button = %WireframeOverlayButton

## Button to hide the main user interface.
@onready var hide_ui_button: Button = $DebugPanel/PanelContainer/VBoxContainer/HideUIButton

## Button used to toggle the render diagnostic panel.
@onready var render_diagnostic_button: Button = %RenderDiagnosticButton

## Indicates if the environment is rendering without lighting.
var is_fullbright: bool = false

## Indicates if the game world is rendering as a wireframe.
var is_wireframe: bool = false

## Indicates if a wireframe overlay is applied to all meshes.
var is_wireframe_overlay: bool = false

## Indicates if physics collision shapes are drawn on screen.
var is_collision_visible: bool = false

## Security variable: Indicates if debug commands are allowed via input or events.
var is_debug_allowed: bool = OS.has_feature("debug")

## Material used to draw the green wireframe debug overlay.
var green_wireframe_material: ShaderMaterial


## Lifecycle method called when the node enters the scene tree.
## Builds dynamic debug materials and binds debug UI button signals.
func _ready() -> void:
	print("DebugOverlay: _ready() called. Initializing debug tools.")
	_build_wireframe_material()
	_initialize_button_states()
	_connect_signals()

	if is_instance_valid(debug_panel):
		debug_panel.hide()
	if is_instance_valid(noclip_message_container):
		noclip_message_container.hide()


## Compiles the runtime spatial green wireframe debug shader material.
func _build_wireframe_material() -> void:
	print("DebugOverlay: Compiling green wireframe shader material.")
	green_wireframe_material = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode wireframe, unshaded, cull_disabled;

	void fragment() {
		ALBEDO = vec3(0.0, 1.0, 0.0);
	}
	"""
	green_wireframe_material.shader = shader


## Initializes default text labels across all debug panel buttons.
func _initialize_button_states() -> void:
	print("DebugOverlay: Synchronizing debug button labels.")
	if is_instance_valid(noclip_button):
		noclip_button.text = "Noclip OFF"
	if is_instance_valid(fullbright_button):
		fullbright_button.text = "Fullbright OFF"
	if is_instance_valid(wireframe_button):
		wireframe_button.text = "Wireframe OFF"
	if is_instance_valid(wireframe_overlay_button):
		wireframe_overlay_button.text = "Wireframe Overlay OFF"
	if is_instance_valid(collision_button):
		collision_button.text = "Collisions OFF"
	if is_instance_valid(render_diagnostic_button):
		render_diagnostic_button.text = "Render Diagnostics"
	if is_instance_valid(hide_ui_button):
		hide_ui_button.text = "Hide UI"


## Connects debug button callbacks and listens for event bus state changes.
func _connect_signals() -> void:
	print("DebugOverlay: Connecting button and debug bus signals.")
	if not noclip_button.pressed.is_connected(_on_noclip_button_pressed):
		noclip_button.pressed.connect(_on_noclip_button_pressed)
	if not metrics_button.pressed.is_connected(_on_metrics_button_pressed):
		metrics_button.pressed.connect(_on_metrics_button_pressed)
	if not fullbright_button.pressed.is_connected(_on_fullbright_button_pressed):
		fullbright_button.pressed.connect(_on_fullbright_button_pressed)
	if not wireframe_button.pressed.is_connected(_on_wireframe_button_pressed):
		wireframe_button.pressed.connect(_on_wireframe_button_pressed)
	if not wireframe_overlay_button.pressed.is_connected(_on_wireframe_overlay_button_pressed):
		wireframe_overlay_button.pressed.connect(_on_wireframe_overlay_button_pressed)
	if not collision_button.pressed.is_connected(_on_collision_button_pressed):
		collision_button.pressed.connect(_on_collision_button_pressed)
	if not hide_ui_button.pressed.is_connected(_on_hide_ui_button_pressed):
		hide_ui_button.pressed.connect(_on_hide_ui_button_pressed)

	if (
		render_diagnostic_button
		and not render_diagnostic_button.pressed.is_connected(_on_render_diagnostic_button_pressed)
	):
		render_diagnostic_button.pressed.connect(_on_render_diagnostic_button_pressed)

	if not Events.noclip_toggled.is_connected(_on_noclip_toggled):
		Events.noclip_toggled.connect(_on_noclip_toggled)
	if not Events.noclip_speed_changed.is_connected(_on_noclip_speed_changed):
		Events.noclip_speed_changed.connect(_on_noclip_speed_changed)
	if not Events.debug_menu_toggled.is_connected(_on_debug_menu_toggled):
		Events.debug_menu_toggled.connect(_on_debug_menu_toggled)
	if not Events.console_toggled.is_connected(_on_console_toggled):
		Events.console_toggled.connect(_on_console_toggled)


## Emits global noclip button toggle event.
func _on_noclip_button_pressed() -> void:
	print("DebugOverlay: Noclip button pressed.")
	Events.noclip_ui_button_pressed.emit()


## Toggles on-screen noclip badge text when fly mode changes.
## [param is_flying] True if noclip is actively engaged.
func _on_noclip_toggled(is_flying: bool) -> void:
	print("DebugOverlay: Noclip state changed -> ", is_flying)
	if is_flying:
		noclip_message_container.show()
		noclip_button.text = "Noclip ON"
	else:
		noclip_message_container.hide()
		noclip_button.text = "Noclip OFF"


## Updates the noclip indicator badge label to display current speed scalar.
## [param speed] The updated flight velocity multiplier.
func _on_noclip_speed_changed(speed: float) -> void:
	noclip_label_message.text = "Noclip ON: %.1fx speed" % speed


## Toggles fullbright unshaded rendering mode across the scene.
func _on_fullbright_button_pressed() -> void:
	is_fullbright = !is_fullbright
	print("DebugOverlay: Fullbright toggled -> ", is_fullbright)
	fullbright_button.text = "Fullbright ON" if is_fullbright else "Fullbright OFF"
	Events.fullbright_toggled.emit(is_fullbright)


## Toggles world wireframe debug view mode.
func _on_wireframe_button_pressed() -> void:
	is_wireframe = !is_wireframe
	print("DebugOverlay: Wireframe toggled -> ", is_wireframe)
	wireframe_button.text = "Wireframe ON" if is_wireframe else "Wireframe OFF"
	Events.wireframe_toggled.emit(is_wireframe)


## Toggles the green wireframe material overlay across all scene geometry.
func _on_wireframe_overlay_button_pressed() -> void:
	is_wireframe_overlay = !is_wireframe_overlay
	print("DebugOverlay: Wireframe overlay toggled -> ", is_wireframe_overlay)
	wireframe_overlay_button.text = (
		"Wireframe Overlay ON" if is_wireframe_overlay else "Wireframe Overlay OFF"
	)
	Events.wireframe_overlay_toggled.emit(is_wireframe_overlay)

	var root_node: Node = get_tree().current_scene
	if root_node:
		_apply_wireframe_to_node(root_node, is_wireframe_overlay)


## Recursively applies or removes the green wireframe shader overlay on mesh nodes.
## [param node] The current branch root node to process.
## [param is_overlay] True to assign wireframe overlay, false to clear.
func _apply_wireframe_to_node(node: Node, is_overlay: bool) -> void:
	if node is MeshInstance3D or node is CSGShape3D:
		if is_overlay:
			node.material_overlay = green_wireframe_material
		else:
			node.material_overlay = null

	for child: Node in node.get_children():
		_apply_wireframe_to_node(child, is_overlay)


## Handles runtime physics collision shape rendering toggle.
func _on_collision_button_pressed() -> void:
	is_collision_visible = !is_collision_visible
	print("DebugOverlay: Collision visibility toggled -> ", is_collision_visible)
	get_tree().debug_collisions_hint = is_collision_visible
	collision_button.text = "Collisions ON" if is_collision_visible else "Collisions OFF"

	var root_node: Node = get_tree().current_scene
	if root_node:
		_force_collision_redraw(root_node, is_collision_visible)


## Forces collision visualizers to refresh their mesh representations.
## [param node] The branch root node to process.
## [param show_collisions] Target visibility state for debug collisions.
func _force_collision_redraw(node: Node, show_collisions: bool) -> void:
	if node is CollisionShape3D and node.shape:
		var temp_shape: Shape3D = node.shape
		node.shape = null
		node.shape = temp_shape
	elif node is ShapeCast3D and node.shape:
		var temp_shape: Shape3D = node.shape
		node.shape = null
		node.shape = temp_shape
	elif node is RayCast3D:
		var temp_target: Vector3 = node.target_position
		node.target_position = Vector3.ZERO
		node.target_position = temp_target

	if node is CollisionShape3D or node is RayCast3D or node is ShapeCast3D:
		node.visible = show_collisions

	for child: Node in node.get_children():
		_force_collision_redraw(child, show_collisions)


## Handles hide UI button press by emitting the visibility event.
func _on_hide_ui_button_pressed() -> void:
	print("DebugOverlay: Hide UI button pressed.")
	hide_ui_button.release_focus()
	Events.ui_visibility_toggle_requested.emit()


## Toggles metrics profiling panel visibility.
func _on_metrics_button_pressed() -> void:
	print("DebugOverlay: Metrics button pressed.")
	Events.metrics_panel_toggle_requested.emit()


## Toggles diagnostics panel visibility.
func _on_render_diagnostic_button_pressed() -> void:
	print("DebugOverlay: Diagnostics button pressed.")
	Events.render_diagnostics_toggle_requested.emit()


## Synchronizes debug drawer visibility state from global events.
## [param is_open] Target visibility state for the debug menu.
func _on_debug_menu_toggled(is_open: bool) -> void:
	if is_instance_valid(debug_panel) and debug_panel.visible != is_open:
		print("DebugOverlay: Syncing debug panel visibility -> ", is_open)
		debug_panel.visible = is_open


## Synchronizes debug drawer panel visibility when console visibility changes.
## [param is_open] Target visibility state of the developer console.
func _on_console_toggled(is_open: bool) -> void:
	if is_instance_valid(debug_panel):
		print("DebugOverlay: Syncing debug panel with console state -> ", is_open)
		debug_panel.visible = is_open
