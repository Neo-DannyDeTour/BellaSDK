## Root coordinator managing high-level UI visibility,
## inputs, and routing to specialized sub-components.
class_name UIController
extends CanvasLayer

## Reference to the screen post-processing effect manager.
@onready var screen_effects: ScreenEffectsManager = $ScreenEffectsManager

## Reference to the center reticle HUD.
@onready var crosshair_hud: CrosshairHUD = $CrosshairHUD

## Reference to the player health and debuff status indicators.
@onready var player_status_hud: PlayerStatusHUD = $PlayerStatusHUD

## Reference to the notification and note reading overlay manager.
@onready var notification_hud: NotificationHUD = $NotificationHUD

## Reference to the developer debug tools overlay.
@onready var debug_overlay: DebugOverlay = $DebugOverlay

## Reference to the performance metrics panel.
@onready var metrics_panel: PanelContainer = $MetricsPanel

## Reference to the frame time graph visualizer.
@onready var frame_graph: ColorRect = $FrameGraph

## Reference to the render diagnostics panel.
@onready var diagnostics_panel: RenderDiagnosticsPanel = %DiagnosticsPanel

## Tracks whether the user interface is currently hidden for clean screenshots.
var is_ui_hidden: bool = false

## Security variable: Indicates if debug commands are allowed via input or events.
var is_debug_allowed: bool = OS.has_feature("debug")


## Initializes UI processing modes, connects top-level UI signals, and checks testbed status.
func _ready() -> void:
	print("UIController: _ready() called. Initializing UI coordinator.")
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false

	if is_instance_valid(metrics_panel):
		metrics_panel.hide()
	if is_instance_valid(frame_graph):
		frame_graph.hide()

	_connect_signals()
	call_deferred("_check_if_testbed")


## Binds top-level event bus listeners.
func _connect_signals() -> void:
	print("UIController: Connecting top-level event bus signals.")
	if not Events.player_health_changed.is_connected(_on_player_health_changed):
		Events.player_health_changed.connect(_on_player_health_changed)
	if not Events.ui_visibility_toggle_requested.is_connected(_toggle_ui_elements):
		Events.ui_visibility_toggle_requested.connect(_toggle_ui_elements)
	if not Events.metrics_panel_toggle_requested.is_connected(_toggle_metrics_panel):
		Events.metrics_panel_toggle_requested.connect(_toggle_metrics_panel)
	if not Events.render_diagnostics_toggle_requested.is_connected(_toggle_diagnostics_panel):
		Events.render_diagnostics_toggle_requested.connect(_toggle_diagnostics_panel)


## Intercepts global debug hotkeys and blocked movement inputs.
## [param event] The [InputEvent] received from the engine.
func _input(event: InputEvent) -> void:
	if not is_debug_allowed:
		return

	if (
		(
			(InputMap.has_action(&"console") and event.is_action_pressed(&"console"))
			or (InputMap.has_action(&"debug_menu") and event.is_action_pressed(&"debug_menu"))
			or (
				event is InputEventKey
				and event.pressed
				and event.keycode in [KEY_QUOTELEFT, KEY_ASCIITILDE, KEY_F3]
			)
		)
		and not event.is_echo()
	):
		print("UIController: Console toggle requested. Emitting console_toggle_requested.")
		Events.console_toggle_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if player_status_hud.is_immobilized:
			if (
				event.is_action_pressed(&"forward")
				or event.is_action_pressed(&"backward")
				or event.is_action_pressed(&"left")
				or event.is_action_pressed(&"right")
				or event.is_action_pressed(&"jump")
				or event.is_action_pressed(&"sprint")
			):
				print("UIController: Movement blocked - immobilized.")
				notification_hud.show_warning_message("Can't move!", 2.0)
		elif player_status_hud.is_sprint_blocked:
			if event.is_action_pressed(&"sprint"):
				print("UIController: Movement blocked - sprint cooldown.")
				notification_hud.show_warning_message("Can't sprint", 2.0)


## Routes health changes to the screen effects manager for pain or heal flashes.
## [param new_health] The new total health value.
func _on_player_health_changed(new_health: int) -> void:
	if new_health < player_status_hud.current_health:
		screen_effects.trigger_pain_effect()
	elif new_health > player_status_hud.current_health:
		screen_effects.trigger_heal_effect()


## Toggles gameplay HUD visibility for clean screenshots or immersion.
func _toggle_ui_elements() -> void:
	is_ui_hidden = !is_ui_hidden
	var visibility: bool = !is_ui_hidden
	print("UIController: UI visibility toggled -> ", visibility)

	if is_instance_valid(crosshair_hud):
		crosshair_hud.visible = visibility
	if is_instance_valid(player_status_hud):
		player_status_hud.visible = visibility
	if is_instance_valid(screen_effects):
		screen_effects.visible = visibility

	if is_instance_valid(debug_overlay) and is_instance_valid(debug_overlay.hide_ui_button):
		debug_overlay.hide_ui_button.text = "Show UI" if is_ui_hidden else "Hide UI"


## Toggles metrics panel and frame graph visibility.
func _toggle_metrics_panel() -> void:
	print("UIController: Toggling metrics panel.")
	if is_instance_valid(metrics_panel) and metrics_panel.has_method("toggle_window"):
		metrics_panel.toggle_window()

		if is_instance_valid(frame_graph):
			frame_graph.visible = metrics_panel.visible

		if is_instance_valid(debug_overlay.metrics_button):
			debug_overlay.metrics_button.text = (
				"Metrics ON" if metrics_panel.visible else "Metrics OFF"
			)


## Toggles the render diagnostics panel visibility.
func _toggle_diagnostics_panel() -> void:
	print("UIController: Toggling diagnostics panel.")
	if is_instance_valid(diagnostics_panel) and diagnostics_panel.has_method("toggle_window"):
		var is_open: bool = diagnostics_panel.toggle_window()
		if is_instance_valid(debug_overlay.render_diagnostic_button):
			debug_overlay.render_diagnostic_button.text = (
				"Diagnostics ON" if is_open else "Render Diagnostics"
			)


## Checks if the current scene is a testbed level to automatically show metrics.
func _check_if_testbed() -> void:
	print("UIController: Checking if current scene is TestbedMap.")
	var current_scene: Node = get_tree().current_scene

	if current_scene and "testbed.scn" in current_scene.scene_file_path.to_lower():
		_toggle_metrics_panel()
