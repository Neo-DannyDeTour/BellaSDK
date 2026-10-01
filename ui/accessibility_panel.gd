## Controls accessibility, visual, and gameplay ergonomics options.
class_name AccessibilityPanel
extends Panel

## Section managing vision assist and high contrast silhouettes.
@export var vision_section: AccessibilityVisionSection

## Section managing environment adjustments and screen filters.
@export var visuals_section: AccessibilityVisualsSection

## Section managing display scale, typography, and FOV.
@export var display_ui_section: AccessibilityDisplayUISection

## Section managing gameplay controls, vibration, and sensitivity.
@export var controls_section: AccessibilityControlsSection

## Section managing subtitles, TTS, and mono audio mixing.
@export var subs_audio_section: AccessibilitySubsAudioSection

## TabContainer organizing settings sections into distinct tabs.
@export var settings_tabs: TabContainer


## Lifecycle initialization method orchestrating child components.
func _ready() -> void:
	print("AccessibilityPanel: Initializing accessibility panel.")
	_resolve_section_references()
	_connect_event_bus()
	_connect_tab_routing()
	_connect_section_hover_routing()
	_load_all_sections()
	visible = true


## Resolves section node references via Scene Unique Names or NodeQuery.
func _resolve_section_references() -> void:
	print("AccessibilityPanel: Resolving section node references.")
	if vision_section == null:
		vision_section = get_node_or_null("%VisionSection") as AccessibilityVisionSection
	if visuals_section == null:
		visuals_section = get_node_or_null("%VisualsSection") as AccessibilityVisualsSection
	if display_ui_section == null:
		display_ui_section = get_node_or_null("%DisplayUISection") as AccessibilityDisplayUISection
	if controls_section == null:
		controls_section = get_node_or_null("%ControlsSection") as AccessibilityControlsSection
	if subs_audio_section == null:
		subs_audio_section = get_node_or_null("%SubsAudioSection") as AccessibilitySubsAudioSection
	if settings_tabs == null:
		settings_tabs = get_node_or_null("%SettingsTabs") as TabContainer


## Connects tab selection events to toggle preview shaders.
func _connect_tab_routing() -> void:
	print("AccessibilityPanel: Connecting tab routing signals.")
	if is_instance_valid(settings_tabs):
		settings_tabs.tab_changed.connect(_on_tab_changed)


## Handles tab switching in [TabContainer] to disable preview shaders.
func _on_tab_changed(tab_index: int) -> void:
	print("AccessibilityPanel: Switched to tab index: ", tab_index)
	if not is_instance_valid(settings_tabs) or not is_instance_valid(vision_section):
		return
	var active_tab: Node = settings_tabs.get_child(tab_index)
	var is_vision_active: bool = (
		active_tab == vision_section or active_tab.is_ancestor_of(vision_section)
	)
	vision_section.set_preview_effects_active(is_vision_active)


## Connects mouse hover events to toggle preview shaders.
func _connect_section_hover_routing() -> void:
	print("AccessibilityPanel: Binding section hover routing.")
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
	print("AccessibilityPanel: Loading all section configurations.")
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


## Subscribes to global [Events] bus signals to sync UI with commands.
func _connect_event_bus() -> void:
	print("AccessibilityPanel: Connecting to global Events bus.")
	Events.colorblind_mode_changed.connect(_on_external_colorblind_changed)
	Events.high_contrast_toggled.connect(_on_external_high_contrast_changed)
	Events.photosensitivity_mode_toggled.connect(_on_external_photosensitivity_changed)
	Events.vision_assist_toggled.connect(_on_external_vision_assist_changed)
	Events.font_scale_changed.connect(_on_font_scale_changed)


## Forwards external colorblind changes to the visuals section.
func _on_external_colorblind_changed(mode: int) -> void:
	print("AccessibilityPanel: Colorblind mode changed to: ", mode)
	if is_instance_valid(visuals_section):
		visuals_section.sync_external_colorblind(mode)


## Forwards external high contrast changes to visuals section.
func _on_external_high_contrast_changed(active: bool) -> void:
	print("AccessibilityPanel: High contrast toggled: ", active)
	if is_instance_valid(visuals_section):
		visuals_section.sync_external_high_contrast(active)


## Forwards external photosensitivity changes to visuals section.
func _on_external_photosensitivity_changed(active: bool) -> void:
	print("AccessibilityPanel: Photosensitivity toggled: ", active)
	if is_instance_valid(visuals_section):
		visuals_section.sync_external_photosensitivity(active)


## Forwards external vision assist toggle changes to vision section.
func _on_external_vision_assist_changed(active: bool) -> void:
	print("AccessibilityPanel: Vision assist toggled: ", active)
	if is_instance_valid(vision_section):
		vision_section.sync_external_vision_assist(active)


## Responds to global font scaling updates and refreshes theme.
func _on_font_scale_changed(scale_factor: float) -> void:
	print("AccessibilityPanel: Font scale changed: ", scale_factor)
	if is_instance_valid(display_ui_section):
		display_ui_section.apply_font_scale_to_theme(scale_factor)
	_propagate_theme_refresh(self)


## Notifies control nodes down subtree to invalidate theme caches.
func _propagate_theme_refresh(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is Control:
		(node as Control).notification(Control.NOTIFICATION_THEME_CHANGED)
	for child: Node in node.get_children():
		_propagate_theme_refresh(child)


## Refreshes docked diorama cameras and resets preview shader.
func _setup_diorama_cameras() -> void:
	print("AccessibilityPanel: Refreshing diorama cameras.")
	if is_instance_valid(vision_section):
		vision_section.cache_diorama_cameras()
		vision_section.set_preview_effects_active(false)
	if is_instance_valid(display_ui_section):
		display_ui_section.apply_current_fov_to_preview()
