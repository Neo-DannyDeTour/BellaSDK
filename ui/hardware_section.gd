## Controls GPU adapter selection and backend rendering driver configuration.
class_name HardwareSection
extends VBoxContainer

## Emitted when changing GPU adapter or rendering driver requires an application restart.
@warning_ignore("unused_signal")
signal restart_required(message: String, renderer_key: String, gpu_idx: int)

## Map associating GPU adapter display labels with physical hardware indices.
var _available_gpus: Dictionary[String, int] = {}

## Map associating renderer backend identifiers with their toggle buttons.
var _renderer_btn_map: Dictionary[String, Button] = {}

## Graphics card adapter selection [OptionButton].
@onready var gpu_options: OptionButton = %GPUAdapterOptionButton

## Forward+ (Vulkan High-End) renderer toggle [Button].
@onready var renderer_forward_button: Button = %RendererForwardButton

## Mobile (Vulkan Mobile) renderer toggle [Button].
@onready var renderer_mobile_button: Button = %RendererMobileButton

## Compatibility (OpenGL Low-End) renderer toggle [Button].
@onready var renderer_compat_button: Button = %RendererCompatButton


## Initializes hardware selector dropdowns, renderer button group, and signal bindings.
func _ready() -> void:
	print("HardwareSection: Initializing hardware settings UI.")
	set_process(false)
	set_physics_process(false)
	_setup_renderer_buttons()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Synchronizes renderer buttons and GPU selector with stored settings without emitting signals.
func load_settings() -> void:
	print("HardwareSection: Synchronizing hardware UI with active configuration.")
	var raw_renderer: Variant = GlobalSettings.get_setting("Settings", "renderer", "forward_plus")
	var cur_renderer: String = raw_renderer if raw_renderer is String else "forward_plus"
	for key: String in _renderer_btn_map.keys():
		var btn: Button = _renderer_btn_map[key]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(key == cur_renderer)

	var saved_gpu: int = GlobalSettings.get_setting_int("Settings", "gpu_adapter_index", 0)
	if saved_gpu >= 0 and saved_gpu < gpu_options.get_item_count():
		gpu_options.select(saved_gpu)


## Configures unified [ButtonGroup] and pressed visual styles for renderer buttons.
func _setup_renderer_buttons() -> void:
	_renderer_btn_map = {
		"forward_plus": renderer_forward_button,
		"mobile": renderer_mobile_button,
		"gl_compatibility": renderer_compat_button,
	}

	var group: ButtonGroup = ButtonGroup.new()
	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.06, 0.06, 0.07, 1.0)
	pressed_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	pressed_style.set_border_width_all(1)
	pressed_style.set_corner_radius_all(3)

	for btn: Button in _renderer_btn_map.values():
		if not is_instance_valid(btn):
			continue
		btn.toggle_mode = true
		btn.button_group = group
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("hover_pressed", pressed_style)
		btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7, 1.0))


## Populates the GPU adapter dropdown with the active rendering device name.
func _populate_dropdowns() -> void:
	gpu_options.clear()
	_available_gpus.clear()

	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	var adapter_name: String = (
		rd.get_device_name() if is_instance_valid(rd) else RenderingServer.get_video_adapter_name()
	)
	if adapter_name.is_empty():
		adapter_name = "Default Graphics Adapter"

	var display_text: String = adapter_name + " (Active Device)"
	_available_gpus[display_text] = 0
	gpu_options.add_item(display_text)
	gpu_options.select(0)


## Connects GPU dropdown and renderer buttons using typed Callables.
func _connect_signals() -> void:
	gpu_options.item_selected.connect(_on_gpu_selected)

	renderer_forward_button.pressed.connect(
		_on_renderer_pressed.bind("forward_plus", "Forward+ (Vulkan High-End)")
	)
	renderer_mobile_button.pressed.connect(
		_on_renderer_pressed.bind("mobile", "Mobile (Vulkan Mobile)")
	)
	renderer_compat_button.pressed.connect(
		_on_renderer_pressed.bind("gl_compatibility", "Compatibility (OpenGL Low-End)")
	)


## Handles GPU adapter selection and requests restart confirmation if changed.
func _on_gpu_selected(index: int) -> void:
	var label: String = gpu_options.get_item_text(index)
	var gpu_idx: int = _available_gpus.get(label, 0)
	var current_gpu: int = GlobalSettings.get_setting_int("Settings", "gpu_adapter_index", 0)
	if current_gpu == gpu_idx:
		return

	print("HardwareSection: Player selected GPU adapter index -> ", gpu_idx)
	var msg: String = (
		"Switching GPU adapter to '"
		+ label
		+ "' requires restarting the application.\n\nRestart now?"
	)
	restart_required.emit(msg, "", gpu_idx)


## Handles renderer backend button selection and requests restart confirmation.
func _on_renderer_pressed(rend_key: String, label: String) -> void:
	var raw_rend: Variant = GlobalSettings.get_setting("Settings", "renderer", "forward_plus")
	var current_rend: String = raw_rend if raw_rend is String else "forward_plus"
	if current_rend == rend_key:
		return

	print("HardwareSection: Player selected renderer backend -> ", rend_key)
	for key: String in _renderer_btn_map.keys():
		var btn: Button = _renderer_btn_map[key]
		if is_instance_valid(btn):
			btn.set_pressed_no_signal(key == current_rend)

	var msg: String = (
		"Changing the rendering engine to '"
		+ label
		+ "' requires restarting the game.\n\nRestart now?"
	)
	restart_required.emit(msg, rend_key, -1)
