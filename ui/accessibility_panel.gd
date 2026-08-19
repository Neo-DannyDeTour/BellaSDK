## Controls accessibility, visual, and gameplay ergonomics options.
class_name AccessibilityPanel
extends Panel

## Default constant value for mouse sensitivity.
const DEFAULT_MOUSE_SENSITIVITY: float = 1.0
## Default constant value for world environment brightness.
const DEFAULT_BRIGHTNESS: float = 1.0
## Default constant value for world environment contrast.
const DEFAULT_CONTRAST: float = 1.0
## Default constant value for world environment saturation.
const DEFAULT_SATURATION: float = 1.0
## Default constant value for camera base field of view.
const DEFAULT_FOV: float = 75.0
## Default constant value for dynamic sprint FOV expansion toggle.
const DEFAULT_DISABLE_SPRINT_FOV: bool = false
## Default constant value for user interface scale factor.
const DEFAULT_UI_SCALE: float = 1.0
## Default constant index for active colorblind shader correction filter.
const DEFAULT_COLORBLIND_MODE: int = 0
## Default constant index for typography font mode.
const DEFAULT_FONT_MODE: int = 0
## Default constant value for high contrast UI mode.
const DEFAULT_HIGH_CONTRAST: bool = false
## Default constant value for motion sickness reduction.
const DEFAULT_REDUCE_MOTION: bool = false
## Default constant index for subtitle text scale.
const DEFAULT_SUB_SIZE: int = 1
## Default constant value for subtitle panel background opacity.
const DEFAULT_SUB_BG_OPACITY: float = 0.5
## Default constant value for distinct character subtitle colors.
const DEFAULT_SUB_COLORS: bool = true
## Default constant value for post-process film grain effect intensity.
const DEFAULT_FILM_GRAIN: float = 0.0
## Default constant value for Text-to-Speech narration system.
const DEFAULT_TTS_ENABLED: bool = false
## Default constant value for photosensitivity safe mode.
const DEFAULT_PHOTOSENSITIVITY: bool = false
## Default constant value for gamepad vibration strength.
const DEFAULT_VIBRATION: float = 1.0
## Default constant value for aim assistance strength.
const DEFAULT_AIM_ASSIST_AMOUNT: float = 0.5
## Default constant value for aim assistance toggle.
const DEFAULT_AIM_ASSIST: bool = true
## Default constant value for vertical camera look inversion.
const DEFAULT_INVERT_Y: bool = false
## Default constant value for crouch toggle mode.
const DEFAULT_TOGGLE_CROUCH: bool = false
## Default constant value for sprint toggle mode.
const DEFAULT_TOGGLE_SPRINT: bool = false
## Default constant value for canceling crouch on jump.
const DEFAULT_CANCEL_CROUCH_ON_JUMP: bool = true
## Default constant value for mono audio channel mixing.
const DEFAULT_MONO_AUDIO: bool = false
## Default constant value for vision assist high-contrast rendering.
const DEFAULT_VISION_ASSIST: bool = false
## Default constant index for vision assist background modes.
const DEFAULT_VISION_ASSIST_MODE: int = 1
## Default constant index for screen filters.
const DEFAULT_SCREEN_FILTER: int = 0

## Diorama packed scene to instantiate into the preview viewport.
@export var diorama_scene: PackedScene

## Target SubViewport containing the active preview scene.
@onready var diorama_viewport: SubViewport = get_node_or_null("%DioramaViewport")

# --- VISION ASSIST & HIGH CONTRAST CONTROLS ---
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

# --- VISUALS & SHADERS CONTROLS ---
## Dropdown menu for selecting colorblind shader correction filters.
@onready var colorblind_option: OptionButton = get_node_or_null("%ColorblindOption")
## Dropdown menu for selecting post-process screen filters.
@onready var screen_filter_option: OptionButton = get_node_or_null("%ScreenFilterOption")
## Slider for adjusting world brightness.
@onready var brightness_slider: HSlider = get_node_or_null("%BrightnessSlider")
## Text input for manual brightness entry.
@onready var brightness_input: LineEdit = get_node_or_null("%BrightnessLine")
## Slider for adjusting world contrast.
@onready var contrast_slider: HSlider = get_node_or_null("%ContrastSlider")
## Text input for manual contrast entry.
@onready var contrast_input: LineEdit = get_node_or_null("%ContrastLine")
## Slider for adjusting world color saturation.
@onready var saturation_slider: HSlider = get_node_or_null("%SaturationSlider")
## Text input for manual saturation entry.
@onready var saturation_input: LineEdit = get_node_or_null("%SaturationLine")
## Slider for adjusting film grain intensity.
@onready var film_grain_slider: HSlider = get_node_or_null("%FilmGrainSlider")
## Text input for manual film grain intensity entry.
@onready var film_grain_input: LineEdit = get_node_or_null("%FilmGrainEdit")
## Toggle switch for photosensitivity safety mode.
@onready var photosensitivity_toggle: CheckButton = get_node_or_null("%PhotosensitivityToggle")

# --- DISPLAY & UI CONTROLS ---
## Slider for adjusting camera field of view.
@onready var fov_slider: HSlider = get_node_or_null("%FOVSlider")
## Text input for manual FOV entry.
@onready var fov_input: LineEdit = get_node_or_null("%FOVLine")
## Checkbox toggle for disabling sprint camera FOV adjustments.
@onready var sprint_fov_checkbox: CheckButton = get_node_or_null("%SprintFovCheckbox")
## Slider for adjusting UI scaling factor.
@onready var ui_scale_slider: HSlider = get_node_or_null("%UIScaleSlider")
## Text input for manual UI scaling factor entry.
@onready var ui_scale_input: LineEdit = get_node_or_null("%UIScaleLine")
## Dropdown menu for typography font mode override.
@onready var font_option: OptionButton = get_node_or_null("%FontOption")
## Toggle switch for high-contrast UI mode.
@onready var high_contrast_toggle: CheckButton = get_node_or_null("%HighContrastToggle")

# --- SUBTITLES & AUDIO CONTROLS ---
## Dropdown menu for subtitle text size.
@onready var sub_size_option: OptionButton = get_node_or_null("%SubSizeOption")
## Slider for subtitle background opacity.
@onready var sub_bg_opacity_slider: HSlider = get_node_or_null("%SubBgOpacitySlider")
## Text input for manual subtitle background opacity entry.
@onready var sub_bg_opacity_input: LineEdit = get_node_or_null("%SubBgOpacityLine")
## Toggle switch for colored character names in subtitles.
@onready var sub_colors_toggle: CheckButton = get_node_or_null("%SubColorsToggle")
## Toggle switch for text-to-speech audio narration.
@onready var tts_toggle: CheckButton = get_node_or_null("%TTSToggle")
## Toggle switch for mono audio mixing.
@onready var mono_audio_toggle: CheckButton = get_node_or_null("%MonoAudioToggle")

# --- CONTROLS & GAMEPLAY CONTROLS ---
## Slider for adjusting mouse sensitivity.
@onready var mouse_sens_slider: HSlider = get_node_or_null("%MouseSensitivitySlider")
## Text input for manual mouse sensitivity entry.
@onready var mouse_sens_input: LineEdit = get_node_or_null("%MouseSensitivityLine")
## Toggle switch for vertical camera axis inversion.
@onready var invert_y_toggle: CheckButton = get_node_or_null("%InvertYToggle")
## Toggle switch for crouch key toggle behavior.
@onready var toggle_crouch_button: CheckButton = get_node_or_null("%ToggleCrouchButton")
## Toggle switch for sprint key toggle behavior.
@onready var toggle_sprint_button: CheckButton = get_node_or_null("%ToggleSprintButton")
## Toggle switch for canceling crouch when jumping.
@onready var cancel_crouch_jump_button: CheckButton = get_node_or_null("%CancelCrouchOnJumpButton")
## Toggle switch for aim assistance enabling.
@onready var aim_assist_toggle: CheckButton = get_node_or_null("%AimAssistToggle")
## Slider for adjusting aim assistance strength.
@onready var aim_assist_slider: HSlider = get_node_or_null("%AimAssistSlider")
## Text input for manual aim assistance strength entry.
@onready var aim_assist_input: LineEdit = get_node_or_null("%AimAssistLine")
## Slider for adjusting vibration strength.
@onready var vibration_slider: HSlider = get_node_or_null("%VibrationSlider")
## Text input for manual vibration strength entry.
@onready var vibration_input: LineEdit = get_node_or_null("%VibrationLine")
## Toggle switch for camera motion and screenshake reduction.
@onready var reduce_motion_toggle: CheckButton = get_node_or_null("%ReduceMotionToggle")

## Available palette color options for high contrast silhouette groups.
const COLOR_NAMES: Array[String] = ["Cyan", "Blue", "Yellow", "Green", "Red", "Magenta", "White"]
## Available background mode tags for vision assist.
const VISION_MODES: Array[String] = ["Black & White", "Blue", "Pure Black", "Grey", "Desaturated"]
## Identifier keys mapping directly to background mode shader parameters.
const VISION_MODE_KEYS: Array[String] = [
	"black_and_white", "blue", "pure_black", "grey", "desaturated"
]
const SCREEN_FILTERS: Array[String] = [
	"Off",
	"CRT",
	"VHS",
	"Pixelate",
	"Toon",
	"Gameboy",
	"Glitch",
	"Grain",
	"Halftone",
	"Nightvision",
	"Kuwahara",
	"ASCII",
	"90Anime",
	"Manga",
	"Handdrawn",
	"Moebius",
	"Obra",
	"Psychedelic",
	"BotW",
	"Ghibli"
]

## Active preview camera instance inside the diorama viewport.
var _diorama_camera: Camera3D
## Active tween interpolating preview camera movements.
var _camera_tween: Tween
## Cached reference to the instantiated preview diorama root node.
var _diorama_instance: Node = null
## Dictionary caching camera nodes in the diorama keyed by group name.
var _diorama_cameras: Dictionary[String, Camera3D] = {}
## Active camera instance currently rendering the preview.
var _active_diorama_camera: Camera3D


## Lifecycle initialization method connecting controls, event bus, and loading settings.
func _ready() -> void:
	print("UI: Accessibility Panel initialized.")
	_setup_diorama()
	_populate_dropdowns()
	_connect_signals()
	_connect_event_bus()
	_load_accessibility_settings()
	visible = true


## Instantiates and attaches the configured diorama scene into the preview SubViewport.
func _setup_diorama() -> void:
	if not diorama_viewport:
		return
	if not diorama_scene:
		print("UI: No diorama scene configured in AccessibilityPanel inspector.")
		return

	var existing_map: Node = diorama_viewport.get_node_or_null("FastDioramaMap")
	if existing_map:
		existing_map.queue_free()

	_diorama_instance = diorama_scene.instantiate()
	_diorama_instance.name = "FastDioramaMap"
	diorama_viewport.add_child(_diorama_instance)
	print("UI: Loaded diorama scene into preview viewport: ", _diorama_instance.name)

	_setup_diorama_cameras()


## Discovers and caches all Camera3D instances present in the diorama scene.
func _setup_diorama_cameras() -> void:
	print("UI: Caching diorama camera nodes.")
	_diorama_cameras.clear()

	if not is_instance_valid(_diorama_instance):
		return

	var is_vision_active: bool = (
		GlobalSettings.get_setting("VisionAssist", "enabled", DEFAULT_VISION_ASSIST) as bool
	)
	var mode_idx: int = (
		GlobalSettings.get_setting("VisionAssist", "mode", DEFAULT_VISION_ASSIST_MODE) as int
	)
	var mode_key: String = (
		VISION_MODE_KEYS[mode_idx]
		if mode_idx >= 0 and mode_idx < VISION_MODE_KEYS.size()
		else "aaa_blue"
	)

	var camera_nodes: Array[Node] = _diorama_instance.find_children(
		"Camera_*", "Camera3D", true, false
	)
	for node: Node in camera_nodes:
		var cam: Camera3D = node as Camera3D
		var key: String = cam.name.trim_prefix("Camera_").to_lower()
		_diorama_cameras[key] = cam
		print("UI: Found and registered diorama camera: ", key)

		if cam.has_method("set_vision_assist_mode"):
			cam.call("set_vision_assist_mode", mode_key)
		if cam.has_method("_on_vision_assist_toggled"):
			cam.call("_on_vision_assist_toggled", is_vision_active)

	if _diorama_cameras.has("default"):
		_switch_diorama_camera("default")
	elif not _diorama_cameras.is_empty():
		var first_key: String = _diorama_cameras.keys()[0]
		_switch_diorama_camera(first_key)


## Switches active diorama viewport rendering to the specified group's camera.
## [param group_name] The target scene group identifier.
func _switch_diorama_camera(group_name: String) -> void:
	var clean_key: String = group_name.to_lower()
	var target_cam: Camera3D = _diorama_cameras.get(clean_key)

	if not is_instance_valid(target_cam):
		target_cam = _diorama_cameras.get("default")

	if not is_instance_valid(target_cam):
		_focus_diorama_on_group(group_name)
		return

	if target_cam == _active_diorama_camera:
		return

	print("UI: Switching diorama active camera to: ", target_cam.name)
	target_cam.make_current()
	_active_diorama_camera = target_cam
	_diorama_camera = target_cam

	if is_instance_valid(fov_slider):
		target_cam.fov = fov_slider.value


## Tweens the preview camera to cleanly frame the centroid of all nodes in a group.
## [param group_name] The scene group to frame.
func _focus_diorama_on_group(group_name: String) -> void:
	if not is_instance_valid(_diorama_camera) or not is_instance_valid(_diorama_instance):
		return

	var nodes: Array[Node] = _diorama_instance.find_children("*", "Node3D", true, false)
	var group_nodes: Array[Node3D] = []
	for n: Node in nodes:
		if n.is_in_group(group_name) and n is Node3D:
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
	_camera_tween.tween_property(_diorama_camera, "global_position", target_pos, 0.6)

	var look_transform: Transform3D = _diorama_camera.global_transform.looking_at(
		center, Vector3.UP
	)
	_camera_tween.tween_property(
		_diorama_camera, "global_transform:basis", look_transform.basis, 0.6
	)


## Populates OptionButton items for palettes, modes, filters, fonts, and sizes.
func _populate_dropdowns() -> void:
	print("UI: Populating OptionButton dropdown menus.")
	if vision_mode_option:
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
		if dropdown:
			dropdown.clear()
			for col: String in COLOR_NAMES:
				dropdown.add_item(col)

	if screen_filter_option:
		screen_filter_option.clear()
		for filter_name: String in SCREEN_FILTERS:
			screen_filter_option.add_item(filter_name)

	if colorblind_option:
		colorblind_option.clear()
		var colorblind_modes: Array[String] = [
			"Normal", "Protanopia", "Deuteranopia", "Tritanopia", "Achromatopsia"
		]
		for mode: String in colorblind_modes:
			colorblind_option.add_item(mode)

	if font_option:
		font_option.clear()
		var font_modes: Array[String] = ["Default", "Dyslexic", "Papyrus", "Comic"]
		for font: String in font_modes:
			font_option.add_item(font)

	if sub_size_option:
		sub_size_option.clear()
		var size_modes: Array[String] = ["Small", "Medium", "Large"]
		for size_mode: String in size_modes:
			sub_size_option.add_item(size_mode)


## Connects all internal UI element input and adjustment signals safely.
func _connect_signals() -> void:
	print("UI: Connecting accessibility signals.")
	if vision_assist_toggle:
		vision_assist_toggle.toggled.connect(_on_vision_assist_toggled)
	if vision_mode_option:
		vision_mode_option.item_selected.connect(_on_vision_mode_selected)
	_connect_color_dropdown(color_friends_option, "friends")
	_connect_color_dropdown(color_enemies_option, "enemies")
	_connect_color_dropdown(color_interact_option, "interactables")
	_connect_color_dropdown(color_traversal_option, "traversal")
	_connect_color_dropdown(color_clues_option, "clues")
	_connect_color_dropdown(color_cover_option, "cover")

	if colorblind_option:
		colorblind_option.item_selected.connect(_on_colorblind_selected)
	if screen_filter_option:
		screen_filter_option.item_selected.connect(_on_screen_filter_selected)
	_connect_adjustment_signals(
		brightness_slider, brightness_input, "brightness", 0.0, 3.0, "Settings"
	)
	_connect_adjustment_signals(contrast_slider, contrast_input, "contrast", 0.0, 3.0, "Settings")
	_connect_adjustment_signals(
		saturation_slider, saturation_input, "saturation", 0.0, 3.0, "Settings"
	)
	_connect_adjustment_signals(
		film_grain_slider, film_grain_input, "film_grain_intensity", 0.0, 20.0, "Settings"
	)
	if photosensitivity_toggle:
		photosensitivity_toggle.toggled.connect(_on_photosensitivity_toggled)

	if fov_slider and fov_input:
		fov_slider.value_changed.connect(_on_fov_changed)
		fov_slider.drag_ended.connect(_on_fov_drag_ended)
		fov_input.text_submitted.connect(_on_fov_input_submitted)
		fov_input.focus_entered.connect(_on_fov_focus_entered)
		fov_input.focus_exited.connect(_on_fov_focus_exited)
	if sprint_fov_checkbox:
		sprint_fov_checkbox.toggled.connect(_on_sprint_fov_toggled)
	_connect_adjustment_signals(ui_scale_slider, ui_scale_input, "ui_scale", 0.5, 2.5, "Settings")
	if font_option:
		font_option.item_selected.connect(_on_font_selected)
	if high_contrast_toggle:
		high_contrast_toggle.toggled.connect(_on_high_contrast_toggled)

	if sub_size_option:
		sub_size_option.item_selected.connect(_on_sub_size_selected)
	_connect_adjustment_signals(
		sub_bg_opacity_slider,
		sub_bg_opacity_input,
		"subtitle_bg_opacity",
		0.0,
		1.0,
		"Accessibility"
	)
	if sub_colors_toggle:
		sub_colors_toggle.toggled.connect(_on_sub_colors_toggled)
	if tts_toggle:
		tts_toggle.toggled.connect(_on_tts_toggled)
	if mono_audio_toggle:
		mono_audio_toggle.toggled.connect(_on_mono_audio_toggled)

	_connect_adjustment_signals(
		mouse_sens_slider, mouse_sens_input, "mouse_sensitivity", 0.05, 5.0, "Controls"
	)
	if invert_y_toggle:
		invert_y_toggle.toggled.connect(_on_invert_y_toggled)
	if toggle_crouch_button:
		toggle_crouch_button.toggled.connect(_on_toggle_crouch_toggled)
	if toggle_sprint_button:
		toggle_sprint_button.toggled.connect(_on_toggle_sprint_toggled)
	if cancel_crouch_jump_button:
		cancel_crouch_jump_button.toggled.connect(_on_cancel_crouch_jump_toggled)
	if aim_assist_toggle:
		aim_assist_toggle.toggled.connect(_on_aim_assist_toggled)
	_connect_adjustment_signals(
		aim_assist_slider, aim_assist_input, "aim_assist_amount", 0.0, 1.0, "Gameplay"
	)
	_connect_adjustment_signals(
		vibration_slider, vibration_input, "vibration_strength", 0.0, 2.0, "Gameplay"
	)
	if reduce_motion_toggle:
		reduce_motion_toggle.toggled.connect(_on_reduce_motion_toggled)


## Connects palette selection OptionButton instances to the Vision Assist bus and camera switching.
## [param dropdown] The [OptionButton] instance.
## [param group_name] Target scene group identifier.
func _connect_color_dropdown(dropdown: OptionButton, group_name: String) -> void:
	if not dropdown:
		return

	dropdown.mouse_entered.connect(_switch_diorama_camera.bind(group_name))
	dropdown.focus_entered.connect(_switch_diorama_camera.bind(group_name))

	dropdown.item_selected.connect(
		func(index: int) -> void:
			var col_name: String = COLOR_NAMES[index].to_lower()
			print("Player changed color for [", group_name, "] to: ", col_name)
			GlobalSettings.save_setting("VisionAssist", group_name + "_color", index)
			if has_node("/root/Events"):
				var events: Node = get_node("/root/Events")
				if events.has_signal("vision_assist_color_changed"):
					events.vision_assist_color_changed.emit(group_name, col_name)
			_switch_diorama_camera(group_name)
	)


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


## Loads stored user preferences from GlobalSettings into UI components.
func _load_accessibility_settings() -> void:
	print("UI: Loading accessibility data from GlobalSettings.")
	var vision_enabled: bool = (
		GlobalSettings.get_setting("VisionAssist", "enabled", DEFAULT_VISION_ASSIST) as bool
	)
	if vision_assist_toggle:
		vision_assist_toggle.button_pressed = vision_enabled
	_on_vision_assist_toggled(vision_enabled)

	if vision_mode_option:
		var mode_idx: int = (
			GlobalSettings.get_setting("VisionAssist", "mode", DEFAULT_VISION_ASSIST_MODE) as int
		)
		vision_mode_option.selected = mode_idx
		_apply_vision_assist_mode(mode_idx)

	_load_group_color_setting(color_friends_option, "friends", 0)
	_load_group_color_setting(color_enemies_option, "enemies", 3)
	_load_group_color_setting(color_interact_option, "interactables", 1)
	_load_group_color_setting(color_traversal_option, "traversal", 2)
	_load_group_color_setting(color_clues_option, "clues", 4)
	_load_group_color_setting(color_cover_option, "cover", 5)

	if colorblind_option:
		colorblind_option.selected = (
			GlobalSettings.get_setting("Settings", "colorblind_mode", DEFAULT_COLORBLIND_MODE)
			as int
		)
		_apply_colorblind_settings()
	if screen_filter_option:
		var initial_filter: int = (
			GlobalSettings.get_setting("Settings", "screen_filter", DEFAULT_SCREEN_FILTER) as int
		)
		screen_filter_option.selected = initial_filter
		_on_screen_filter_selected(initial_filter)

	_load_slider_setting(
		brightness_slider, brightness_input, "brightness", DEFAULT_BRIGHTNESS, "Settings"
	)
	_load_slider_setting(contrast_slider, contrast_input, "contrast", DEFAULT_CONTRAST, "Settings")
	_load_slider_setting(
		saturation_slider, saturation_input, "saturation", DEFAULT_SATURATION, "Settings"
	)
	_load_slider_setting(
		film_grain_slider, film_grain_input, "film_grain_intensity", DEFAULT_FILM_GRAIN, "Settings"
	)
	_apply_visual_settings()

	if photosensitivity_toggle:
		photosensitivity_toggle.set_pressed_no_signal(
			(
				GlobalSettings.get_setting(
					"Accessibility", "photosensitivity", DEFAULT_PHOTOSENSITIVITY
				)
				as bool
			)
		)

	_load_slider_setting(fov_slider, fov_input, "base_fov", DEFAULT_FOV, "Settings", true)
	if sprint_fov_checkbox:
		sprint_fov_checkbox.button_pressed = (
			GlobalSettings.get_setting("Settings", "disable_sprint_fov", DEFAULT_DISABLE_SPRINT_FOV)
			as bool
		)
	_apply_fov_settings()

	_load_slider_setting(ui_scale_slider, ui_scale_input, "ui_scale", DEFAULT_UI_SCALE, "Settings")
	_apply_ui_scale_settings()

	if font_option:
		font_option.selected = (
			GlobalSettings.get_setting("Settings", "font_mode", DEFAULT_FONT_MODE) as int
		)
		_apply_font_settings()
	if high_contrast_toggle:
		high_contrast_toggle.set_pressed_no_signal(
			(
				GlobalSettings.get_setting(
					"Accessibility", "high_contrast_ui", DEFAULT_HIGH_CONTRAST
				)
				as bool
			)
		)

	if sub_size_option:
		sub_size_option.selected = (
			GlobalSettings.get_setting("Accessibility", "subtitle_size", DEFAULT_SUB_SIZE) as int
		)
	_load_slider_setting(
		sub_bg_opacity_slider,
		sub_bg_opacity_input,
		"subtitle_bg_opacity",
		DEFAULT_SUB_BG_OPACITY,
		"Accessibility"
	)
	if sub_colors_toggle:
		sub_colors_toggle.set_pressed_no_signal(
			(
				GlobalSettings.get_setting("Accessibility", "subtitle_colors", DEFAULT_SUB_COLORS)
				as bool
			)
		)
	if tts_toggle:
		tts_toggle.set_pressed_no_signal(
			GlobalSettings.get_setting("Accessibility", "tts_enabled", DEFAULT_TTS_ENABLED) as bool
		)
	if mono_audio_toggle:
		mono_audio_toggle.set_pressed_no_signal(
			GlobalSettings.get_setting("Audio", "mono_audio", DEFAULT_MONO_AUDIO) as bool
		)

	_load_slider_setting(
		mouse_sens_slider,
		mouse_sens_input,
		"mouse_sensitivity",
		DEFAULT_MOUSE_SENSITIVITY,
		"Controls"
	)
	_apply_mouse_sensitivity()
	if invert_y_toggle:
		invert_y_toggle.set_pressed_no_signal(
			GlobalSettings.get_setting("Controls", "invert_y", DEFAULT_INVERT_Y) as bool
		)
	if toggle_crouch_button:
		toggle_crouch_button.set_pressed_no_signal(
			GlobalSettings.get_setting("Controls", "toggle_crouch", DEFAULT_TOGGLE_CROUCH) as bool
		)
	if toggle_sprint_button:
		toggle_sprint_button.set_pressed_no_signal(
			GlobalSettings.get_setting("Controls", "toggle_sprint", DEFAULT_TOGGLE_SPRINT) as bool
		)
	if cancel_crouch_jump_button:
		cancel_crouch_jump_button.set_pressed_no_signal(
			(
				GlobalSettings.get_setting(
					"Gameplay", "cancel_crouch_on_jump", DEFAULT_CANCEL_CROUCH_ON_JUMP
				)
				as bool
			)
		)
	if aim_assist_toggle:
		aim_assist_toggle.set_pressed_no_signal(
			GlobalSettings.get_setting("Gameplay", "aim_assist", DEFAULT_AIM_ASSIST) as bool
		)
	_load_slider_setting(
		aim_assist_slider,
		aim_assist_input,
		"aim_assist_amount",
		DEFAULT_AIM_ASSIST_AMOUNT,
		"Gameplay"
	)
	_load_slider_setting(
		vibration_slider, vibration_input, "vibration_strength", DEFAULT_VIBRATION, "Gameplay"
	)
	if reduce_motion_toggle:
		reduce_motion_toggle.set_pressed_no_signal(
			(
				GlobalSettings.get_setting("Accessibility", "reduce_motion", DEFAULT_REDUCE_MOTION)
				as bool
			)
		)


## Loads and configures an OptionButton dropdown for group colors.
## [param dropdown] Target [OptionButton].
## [param group_name] Setting group key.
## [param default_index] Fallback color index.
func _load_group_color_setting(
	dropdown: OptionButton, group_name: String, default_index: int
) -> void:
	if not dropdown:
		return
	var idx: int = (
		GlobalSettings.get_setting("VisionAssist", group_name + "_color", default_index) as int
	)
	dropdown.selected = idx
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("vision_assist_color_changed"):
			events.vision_assist_color_changed.emit(group_name, COLOR_NAMES[idx].to_lower())


## Handles toggling of the vision assist rendering system.
## [param toggled_on] Enabled state.
func _on_vision_assist_toggled(toggled_on: bool) -> void:
	print("Player toggled Vision Assist to: ", toggled_on)
	GlobalSettings.save_setting("VisionAssist", "enabled", toggled_on)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("vision_assist_toggled"):
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
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("vision_assist_mode_changed"):
				events.vision_assist_mode_changed.emit(mode_key)


## Handles screen filter dropdown selections.
## [param index] Selected screen filter index.
func _on_screen_filter_selected(index: int) -> void:
	var filter_name: String = SCREEN_FILTERS[index].to_lower()
	print("Player selected Screen Filter: ", filter_name)
	GlobalSettings.save_setting("Settings", "screen_filter", index)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("screen_filter_changed"):
			events.screen_filter_changed.emit(filter_name)


## Handles mono audio mix toggling.
## [param toggled_on] Enabled state.
func _on_mono_audio_toggled(toggled_on: bool) -> void:
	print("Player toggled Mono Audio to: ", toggled_on)
	GlobalSettings.save_setting("Audio", "mono_audio", toggled_on)


## Reads a float setting and synchronizes slider and LineEdit representations.
## [param slider] The target [HSlider] node.
## [param input_box] The target [LineEdit] node.
## [param key] Setting key identifier.
## [param default_val] Fallback float value.
## [param section] GlobalSettings section category.
## [param is_int] Whether to format as integer display text.
func _load_slider_setting(
	slider: HSlider,
	input_box: LineEdit,
	key: String,
	default_val: float,
	section: String = "Settings",
	is_int: bool = false
) -> void:
	if slider:
		var val: float = GlobalSettings.get_setting(section, key, default_val) as float
		slider.value = val
		if input_box:
			input_box.text = str(int(val)) if is_int else ("%.2f" % val)


## Attaches interactive events to companion slider and LineEdit pairs.
## [param slider] The [HSlider] instance.
## [param input_box] The [LineEdit] instance.
## [param setting_name] Key identifier for the setting.
## [param min_val] Minimum clamp limit.
## [param max_val] Maximum clamp limit.
## [param section] GlobalSettings category section.
func _connect_adjustment_signals(
	slider: HSlider,
	input_box: LineEdit,
	setting_name: String,
	min_val: float = 0.0,
	max_val: float = 3.0,
	section: String = "Settings"
) -> void:
	if slider:
		slider.min_value = min_val
		slider.max_value = max_val
		slider.value_changed.connect(_on_adjustment_changed.bind(input_box, setting_name))
		slider.drag_ended.connect(_on_adjustment_drag_ended.bind(setting_name, slider, section))
	if input_box:
		input_box.text_submitted.connect(
			_on_adjustment_input_submitted.bind(setting_name, slider, section, min_val, max_val)
		)
		input_box.focus_entered.connect(_on_adjustment_focus_entered.bind(input_box))
		input_box.focus_exited.connect(
			_on_adjustment_focus_exited.bind(
				input_node_ref(input_box), slider, setting_name, section, min_val, max_val
			)
		)


## Helper getter resolving LineEdit node for bind callbacks.
## [param node] The target [LineEdit].
## [return] The [LineEdit] instance.
func input_node_ref(node: LineEdit) -> LineEdit:
	return node


## Responds to live slider changes and updates companion textboxes.
## [param value] Current numeric slider value.
## [param input_node] Companion text input field.
## [param setting_name] Target setting name.
func _on_adjustment_changed(value: float, input_node: LineEdit, setting_name: String) -> void:
	print("UI: Adjustment changed for ", setting_name, " to ", value)
	if input_node and not input_node.has_focus():
		input_node.text = "%.2f" % value

	if setting_name == "ui_scale":
		_apply_ui_scale_settings()
	elif setting_name == "mouse_sensitivity":
		_apply_mouse_sensitivity()
	elif setting_name == "film_grain_intensity":
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("film_grain_changed"):
				events.film_grain_changed.emit(value)
	elif setting_name in ["brightness", "contrast", "saturation"]:
		_apply_visual_settings()


## Commits slider values to GlobalSettings on drag completion.
## [param value_changed] Flag indicating if the value changed.
## [param setting_name] Setting key identifier.
## [param slider_node] The target [HSlider].
## [param section] GlobalSettings category section.
func _on_adjustment_drag_ended(
	value_changed: bool, setting_name: String, slider_node: HSlider, section: String
) -> void:
	if value_changed and slider_node:
		print("Player adjusted ", setting_name, " slider to: ", slider_node.value)
		GlobalSettings.save_setting(section, setting_name, slider_node.value)
		if setting_name == "mouse_sensitivity":
			_apply_mouse_sensitivity()
		elif setting_name == "film_grain_intensity":
			if has_node("/root/Events"):
				var events: Node = get_node("/root/Events")
				if events.has_signal("film_grain_changed"):
					events.film_grain_changed.emit(slider_node.value)


## Validates and submits manual numeric text inputs into companion sliders.
## [param new_text] Typed input string.
## [param setting_name] Setting key identifier.
## [param slider_node] The target [HSlider].
## [param section] GlobalSettings category section.
## [param min_val] Minimum clamp limit.
## [param max_val] Maximum clamp limit.
func _on_adjustment_input_submitted(
	new_text: String,
	setting_name: String,
	slider_node: HSlider,
	section: String,
	min_val: float,
	max_val: float
) -> void:
	var new_val: float = clampf(new_text.to_float(), min_val, max_val)
	if slider_node:
		slider_node.value = new_val
		slider_node.release_focus()
	print("Player manually typed ", setting_name, " input: ", new_val)
	GlobalSettings.save_setting(section, setting_name, new_val)
	if setting_name == "mouse_sensitivity":
		_apply_mouse_sensitivity()
	elif setting_name == "film_grain_intensity":
		if has_node("/root/Events"):
			var events: Node = get_node("/root/Events")
			if events.has_signal("film_grain_changed"):
				events.film_grain_changed.emit(new_val)
	elif setting_name in ["brightness", "contrast", "saturation"]:
		_apply_visual_settings()


## Clears LineEdit text box when editing focus begins.
## [param input_node] The focused [LineEdit].
func _on_adjustment_focus_entered(input_node: LineEdit) -> void:
	print("UI: Player editing LineEdit input.")
	if input_node:
		input_node.text = ""


## Reverts or submits LineEdit content when focus is lost.
## [param input_node] The defocused [LineEdit].
## [param slider_node] The companion [HSlider].
## [param setting_name] Setting key identifier.
## [param section] GlobalSettings category section.
## [param min_val] Minimum clamp limit.
## [param max_val] Maximum clamp limit.
func _on_adjustment_focus_exited(
	input_node: LineEdit,
	slider_node: HSlider,
	setting_name: String,
	section: String,
	min_val: float,
	max_val: float
) -> void:
	if not input_node:
		return
	var current_text: String = input_node.text.strip_edges()
	if current_text == "" and slider_node:
		input_node.text = "%.2f" % slider_node.value
	else:
		_on_adjustment_input_submitted(
			current_text, setting_name, slider_node, section, min_val, max_val
		)


## Applies mouse sensitivity settings to the player's camera controller.
func _apply_mouse_sensitivity() -> void:
	if not mouse_sens_slider:
		return
	var sens: float = mouse_sens_slider.value
	print("Engine: Applying Mouse Sensitivity: ", sens)
	var player: Node = _get_player()
	if player and "camera_controller" in player and is_instance_valid(player.camera_controller):
		if player.camera_controller.has_method("set_mouse_sensitivity"):
			player.camera_controller.set_mouse_sensitivity(sens)
		else:
			player.camera_controller.mouse_sensitivity_base = sens
			player.camera_controller.mouse_sensitivity = sens


## Finds the active WorldEnvironment node in the tree with fallbacks.
## [return] The [WorldEnvironment] node if located, otherwise `null`.
func _find_world_environment() -> WorldEnvironment:
	var env_nodes: Array[Node] = get_tree().get_nodes_in_group("world_environment")
	if not env_nodes.is_empty():
		return env_nodes[0] as WorldEnvironment

	var root: Node = get_tree().current_scene
	if not root:
		root = get_tree().root
	return _find_first_child_of_type(root, "WorldEnvironment") as WorldEnvironment


## Recursively searches a subtree for the first node matching a type name.
## [param parent] Starting parent [Node].
## [param type_str] String name of the target node class.
## [return] The matching [Node] instance or `null`.
func _find_first_child_of_type(parent: Node, type_str: String) -> Node:
	if not parent:
		return null
	if parent.is_class(type_str) or parent.get_class() == type_str:
		return parent
	for child: Node in parent.get_children():
		var found: Node = _find_first_child_of_type(child, type_str)
		if found:
			return found
	return null


## Applies brightness, contrast, and saturation adjustments to the active WorldEnvironment.
func _apply_visual_settings() -> void:
	if not brightness_slider or not contrast_slider or not saturation_slider:
		return
	print("Engine: Applying visual adjustments to WorldEnvironment.")
	var env_node: WorldEnvironment = _find_world_environment()
	if env_node and env_node.environment:
		env_node.environment.adjustment_enabled = true
		env_node.environment.adjustment_brightness = brightness_slider.value
		env_node.environment.adjustment_contrast = contrast_slider.value
		env_node.environment.adjustment_saturation = saturation_slider.value


## Adjusts window content scaling factor for user interface elements.
func _apply_ui_scale_settings() -> void:
	if not ui_scale_slider:
		return
	var current_scale: float = ui_scale_slider.value
	print("Engine: Applying UI Scale adjustments: ", current_scale)
	get_window().content_scale_factor = current_scale


## Handles user selection of colorblind dropdown options.
## [param index] Selected mode index.
func _on_colorblind_selected(index: int) -> void:
	print("Player changed colorblind mode to index: ", index)
	GlobalSettings.save_setting("Settings", "colorblind_mode", index)
	_apply_colorblind_settings()


## Broadcasts selected colorblind mode to global event bus.
func _apply_colorblind_settings() -> void:
	if not colorblind_option:
		return
	var mode: int = colorblind_option.selected
	print("Engine: Applying Colorblind shader mode: ", mode)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("colorblind_mode_changed"):
			events.emit_signal("colorblind_mode_changed", mode)


## Handles external colorblind changes originating from the console.
## [param mode] Mode index passed by console.
func _on_external_colorblind_changed(mode: int) -> void:
	if colorblind_option and colorblind_option.selected != mode:
		colorblind_option.selected = mode


## Handles external high contrast toggle changes originating from the console.
## [param active] Enabled state passed by console.
func _on_external_high_contrast_changed(active: bool) -> void:
	if high_contrast_toggle and high_contrast_toggle.button_pressed != active:
		high_contrast_toggle.set_pressed_no_signal(active)


## Handles external photosensitivity toggle changes originating from the console.
## [param active] Enabled state passed by console.
func _on_external_photosensitivity_changed(active: bool) -> void:
	if photosensitivity_toggle and photosensitivity_toggle.button_pressed != active:
		photosensitivity_toggle.set_pressed_no_signal(active)


## Handles external vision assist toggle changes originating from the console.
## [param active] Enabled state passed by console.
func _on_external_vision_assist_changed(active: bool) -> void:
	if vision_assist_toggle and vision_assist_toggle.button_pressed != active:
		vision_assist_toggle.set_pressed_no_signal(active)


## Handles font override selection changes.
## [param index] Font selection index.
func _on_font_selected(index: int) -> void:
	print("Player changed font mode to index: ", index)
	GlobalSettings.save_setting("Settings", "font_mode", index)
	_apply_font_settings()


## Broadcasts font override mode changes across the EventBus.
func _apply_font_settings() -> void:
	if not font_option:
		return
	var mode: int = font_option.selected
	print("Engine: Applying Font Override mode: ", mode)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("font_changed"):
			var font_strings: Array[String] = ["default", "dyslexic", "papyrus", "comic"]
			if mode >= 0 and mode < font_strings.size():
				events.emit_signal("font_changed", font_strings[mode])


## Handles slider FOV value changes.
## [param value] Target camera FOV.
func _on_fov_changed(value: float) -> void:
	print("UI: FOV adjusted to ", value)
	if fov_input and not fov_input.has_focus():
		fov_input.text = str(int(value))
	_apply_fov_settings()


## Commits camera FOV slider updates upon drag release.
## [param value_changed] Flag indicating if the value changed.
func _on_fov_drag_ended(value_changed: bool) -> void:
	if value_changed and fov_slider:
		print("Player adjusted FOV slider to: ", fov_slider.value)
		GlobalSettings.save_setting("Settings", "base_fov", fov_slider.value)


## Commits manual FOV text input entries.
## [param new_text] Typed input string.
func _on_fov_input_submitted(new_text: String) -> void:
	var new_val: float = clampf(new_text.to_float(), 60.0, 120.0)
	if fov_slider:
		fov_slider.value = new_val
	if fov_input:
		fov_input.release_focus()
	print("Player manually typed FOV input: ", new_val)
	GlobalSettings.save_setting("Settings", "base_fov", new_val)


## Clears FOV text input box on focus.
func _on_fov_focus_entered() -> void:
	print("UI: Player editing FOV LineEdit.")
	if fov_input:
		fov_input.text = ""


## Reverts or submits FOV LineEdit when focus is lost.
func _on_fov_focus_exited() -> void:
	if not fov_input:
		return
	var current_text: String = fov_input.text.strip_edges()
	if current_text == "" and fov_slider:
		fov_input.text = str(int(fov_slider.value))
	else:
		_on_fov_input_submitted(current_text)


## Handles toggling of dynamic sprint FOV expansion.
## [param toggled_on] Whether sprint FOV expansion is disabled.
func _on_sprint_fov_toggled(toggled_on: bool) -> void:
	print("Player toggled Sprint FOV to: ", toggled_on)
	GlobalSettings.save_setting("Settings", "disable_sprint_fov", toggled_on)
	_apply_fov_settings()


## Applies current base FOV and sprint toggle to player and preview camera controllers.
func _apply_fov_settings() -> void:
	if not fov_slider:
		return
	var current_fov: float = fov_slider.value
	print("Engine: Applying FOV settings -> ", current_fov)

	if is_instance_valid(_diorama_camera):
		_diorama_camera.fov = current_fov

	var player: Node = _get_player()
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.base_fov = current_fov
		if sprint_fov_checkbox:
			player.camera_controller.disable_sprint_fov = sprint_fov_checkbox.button_pressed


## Handles vertical axis inversion toggling.
## [param toggled_on] Enabled state.
func _on_invert_y_toggled(toggled_on: bool) -> void:
	print("Player toggled Invert Y to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "invert_y", toggled_on)
	var player: Node = _get_player()
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.invert_y = toggled_on


## Handles aim assistance system toggling.
## [param toggled_on] Enabled state.
func _on_aim_assist_toggled(toggled_on: bool) -> void:
	print("Player toggled Aim Assist to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "aim_assist", toggled_on)


## Handles toggle crouch button mode setting.
## [param toggled_on] Enabled state.
func _on_toggle_crouch_toggled(toggled_on: bool) -> void:
	print("Player toggled Toggle Crouch to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "toggle_crouch", toggled_on)


## Handles toggle sprint button mode setting.
## [param toggled_on] Enabled state.
func _on_toggle_sprint_toggled(toggled_on: bool) -> void:
	print("Player toggled Toggle Sprint to: ", toggled_on)
	GlobalSettings.save_setting("Controls", "toggle_sprint", toggled_on)


## Handles cancel crouch on jump setting.
## [param toggled_on] Enabled state.
func _on_cancel_crouch_jump_toggled(toggled_on: bool) -> void:
	print("Player toggled Cancel Crouch On Jump to: ", toggled_on)
	GlobalSettings.save_setting("Gameplay", "cancel_crouch_on_jump", toggled_on)


## Handles high contrast mode toggling.
## [param toggled_on] Enabled state.
func _on_high_contrast_toggled(toggled_on: bool) -> void:
	print("Player toggled High Contrast UI to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "high_contrast_ui", toggled_on)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("high_contrast_toggled"):
			events.high_contrast_toggled.emit(toggled_on)


## Handles motion reduction toggle updates.
## [param toggled_on] Enabled state.
func _on_reduce_motion_toggled(toggled_on: bool) -> void:
	print("Player toggled Reduce Motion to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "reduce_motion", toggled_on)
	var player: Node = _get_player()
	if player and "camera_controller" in player and player.camera_controller:
		player.camera_controller.reduce_motion = toggled_on


## Handles subtitle size dropdown changes.
## [param index] Selected subtitle size index.
func _on_sub_size_selected(index: int) -> void:
	print("Player selected Subtitle Size index: ", index)
	GlobalSettings.save_setting("Accessibility", "subtitle_size", index)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("subtitle_size_changed"):
			events.emit_signal("subtitle_size_changed", index)


## Handles subtitle speaker color distinction toggling.
## [param toggled_on] Enabled state.
func _on_sub_colors_toggled(toggled_on: bool) -> void:
	print("Player toggled Subtitle Speaker Colors to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "subtitle_colors", toggled_on)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("subtitle_colors_changed"):
			events.emit_signal("subtitle_colors_changed", toggled_on)


## Handles Text-to-Speech narration toggling.
## [param toggled_on] Enabled state.
func _on_tts_toggled(toggled_on: bool) -> void:
	print("Player toggled Text-to-Speech to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "tts_enabled", toggled_on)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("tts_state_changed"):
			events.emit_signal("tts_state_changed", toggled_on)


## Handles photosensitivity safe mode toggling.
## [param toggled_on] Enabled state.
func _on_photosensitivity_toggled(toggled_on: bool) -> void:
	print("Player toggled Photosensitivity Mode to: ", toggled_on)
	GlobalSettings.save_setting("Accessibility", "photosensitivity", toggled_on)
	if has_node("/root/Events"):
		var events: Node = get_node("/root/Events")
		if events.has_signal("photosensitivity_mode_toggled"):
			events.photosensitivity_mode_toggled.emit(toggled_on)


## Finds the active player instance within the scene tree.
## [return] The player [Node] if present, otherwise `null`.
func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")
