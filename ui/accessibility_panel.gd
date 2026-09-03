## Controls accessibility, visual, and gameplay ergonomics options.
## Coordinates child section components, event subscriptions, and theme updates.
class_name AccessibilityPanel
extends Panel

## Child section managing vision assist and high contrast silhouettes.
@onready var vision_section: AccessibilityVisionSection = get_node_or_null(
	"MarginContainer/VBoxContainer/HBoxContainer/SettingsScroll/SettingsVBox/VisionSection"
)

## Child section managing environment adjustments and screen filters.
@onready var visuals_section: AccessibilityVisualsSection = get_node_or_null(
	"MarginContainer/VBoxContainer/HBoxContainer/SettingsScroll/SettingsVBox/VisualsSection"
)

## Child section managing display scale, typography, and FOV.
@onready var display_ui_section: AccessibilityDisplayUISection = get_node_or_null(
	"MarginContainer/VBoxContainer/HBoxContainer/SettingsScroll/SettingsVBox/DisplayUISection"
)

## Child section managing gameplay controls, vibration, and sensitivity.
@onready var controls_section: AccessibilityControlsSection = get_node_or_null(
	"MarginContainer/VBoxContainer/HBoxContainer/SettingsScroll/SettingsVBox/ControlsSection"
)

## Child section managing subtitles, TTS, and mono audio mixing.
@onready var subs_audio_section: AccessibilitySubsAudioSection = get_node_or_null(
	"MarginContainer/VBoxContainer/HBoxContainer/SettingsScroll/SettingsVBox/SubsAudioSection"
)


## Lifecycle initialization method orchestrating child components and event subscriptions.
func _ready() -> void:
	print("UI: Accessibility Panel orchestrator initialized.")
	_connect_event_bus()
	_connect_section_hover_routing()
	_load_all_sections()
	visible = true


## Connects mouse hover events so preview shaders only activate in the Vision section.
func _connect_section_hover_routing() -> void:
	if is_instance_valid(vision_section):
		vision_section.mouse_entered.connect(
			func() -> void:
				if is_instance_valid(vision_section):
					vision_section.set_preview_effects_active(true)
		)

	var non_vision_sections: Array[Control] = [
		visuals_section, display_ui_section, controls_section, subs_audio_section
	]
	for section: Control in non_vision_sections:
		if is_instance_valid(section):
			section.mouse_entered.connect(
				func() -> void:
					if is_instance_valid(vision_section):
						vision_section.set_preview_effects_active(false)
			)


## Delegates settings loading to each individual section controller.
func _load_all_sections() -> void:
	print("UI: Triggering section loads.")
	if is_instance_valid(vision_section):
		vision_section.load_settings()
	if is_instance_valid(visuals_section):
		visuals_section.load_settings()
	if is_instance_valid(display_ui_section):
		display_ui_section.load_settings()
	if is_instance_valid(controls_section):
		controls_section.load_settings()
	if is_instance_valid(subs_audio_section):
		subs_audio_section.load_settings()


## Subscribes to global EventBus signals to sync UI when console commands run.
func _connect_event_bus() -> void:
	if not has_node("/root/Events"):
		return
	var events: Node = get_node("/root/Events")
	if events.has_signal("colorblind_mode_changed"):
		events.colorblind_mode_changed.connect(_on_external_colorblind_changed)
	if events.has_signal("high_contrast_toggled"):
		events.high_contrast_toggled.connect(_on_external_high_contrast_changed)
	if events.has_signal("photosensitivity_mode_toggled"):
		events.photosensitivity_mode_toggled.connect(_on_external_photosensitivity_changed)
	if events.has_signal("vision_assist_toggled"):
		events.vision_assist_toggled.connect(_on_external_vision_assist_changed)
	if events.has_signal("font_scale_changed"):
		events.font_scale_changed.connect(_on_font_scale_changed)


## Forwards external colorblind changes to the visuals section.
## [param mode] Mode index passed by console.
func _on_external_colorblind_changed(mode: int) -> void:
	if is_instance_valid(visuals_section):
		visuals_section.sync_external_colorblind(mode)


## Forwards external high contrast changes to the visuals section.
## [param active] Enabled state passed by console.
func _on_external_high_contrast_changed(active: bool) -> void:
	if is_instance_valid(visuals_section):
		visuals_section.sync_external_high_contrast(active)


## Forwards external photosensitivity changes to the visuals section.
## [param active] Enabled state passed by console.
func _on_external_photosensitivity_changed(active: bool) -> void:
	if is_instance_valid(visuals_section):
		visuals_section.sync_external_photosensitivity(active)


## Forwards external vision assist toggle changes to the vision section.
## [param active] Enabled state passed by console.
func _on_external_vision_assist_changed(active: bool) -> void:
	if is_instance_valid(vision_section):
		vision_section.sync_external_vision_assist(active)


## Responds to global font scaling updates and triggers tree theme notification.
## [param scale_factor] Multiplier for UI font scaling.
func _on_font_scale_changed(scale_factor: float) -> void:
	if is_instance_valid(display_ui_section):
		display_ui_section.apply_font_scale_to_theme(scale_factor)
	_propagate_theme_refresh(self)


## Notifies control nodes down the subtree to invalidate their theme caches.
## [param node] The parent [Node] starting point.
func _propagate_theme_refresh(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is Control:
		(node as Control).notification(Control.NOTIFICATION_THEME_CHANGED)
	for child: Node in node.get_children():
		_propagate_theme_refresh(child)


## Refreshes docked diorama cameras and resets preview shader to normal.
func _setup_diorama_cameras() -> void:
	print("UI: OptionsRouter notified AccessibilityPanel to refresh diorama cameras.")
	if is_instance_valid(vision_section):
		vision_section.cache_diorama_cameras()
		vision_section.set_preview_effects_active(false)
	if is_instance_valid(display_ui_section):
		display_ui_section.apply_current_fov_to_preview()
