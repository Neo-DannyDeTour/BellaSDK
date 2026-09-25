## Controls GPU device selection, backend drivers, and benchmark runs.
class_name HardwareSection
extends VBoxContainer

## Emitted when changing GPU or renderer backend to request confirmation.
signal restart_required(message: String, renderer_key: String, gpu_idx: int)

## Emitted when the user starts the automated 60 FPS tuning benchmark pass.
signal auto_tune_requested

## Reference to the video card selection [OptionButton].
@onready var gpu_options: OptionButton = %GPUAdapterOptionButton
## Forward+ renderer toggle [Button].
@onready var renderer_forward_button: Button = %RendererForwardButton
## Mobile renderer toggle [Button].
@onready var renderer_mobile_button: Button = %RendererMobileButton
## Compatibility renderer toggle [Button].
@onready var renderer_compat_button: Button = %RendererCompatButton
## Reference to the auto-optimization benchmark [Button].
@onready var auto_tune_button: Button = %AutoTuneButton

## Map storing GPU adapter names mapped to their physical hardware index.
var _available_gpus: Dictionary = {}
## Lookup map associating renderer keys with toggle buttons.
var _renderer_btn_map: Dictionary[String, Button] = {}


## Lifecycle method initializing hardware widgets and connecting signals.
func _ready() -> void:
	print("HardwareSection: Initializing hardware settings.")
	_setup_renderer_buttons()
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Configures button groups and visual styles for renderer buttons.
func _setup_renderer_buttons() -> void:
	print("HardwareSection: Configuring renderer toggle buttons.")
	_renderer_btn_map = {
		"forward_plus": renderer_forward_button,
		"mobile": renderer_mobile_button,
		"gl_compatibility": renderer_compat_button,
	}
	_setup_group(_renderer_btn_map)


## Assigns a unified [ButtonGroup] and pressed visual styles to buttons.
func _setup_group(mapping: Dictionary[String, Button]) -> void:
	var group: ButtonGroup = ButtonGroup.new()

	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.06, 0.06, 0.07, 1.0)
	pressed_style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	pressed_style.set_border_width_all(1)
	pressed_style.set_corner_radius_all(3)

	for btn: Button in mapping.values():
		btn.toggle_mode = true
		btn.button_group = group
		btn.add_theme_stylebox_override("pressed", pressed_style)
		btn.add_theme_stylebox_override("hover_pressed", pressed_style)
		btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.7, 0.7, 1.0))


## Queries available hardware devices and populates dropdown selectors.
func _populate_dropdowns() -> void:
	print("HardwareSection: Populating GPU adapter list.")
	gpu_options.clear()
	_available_gpus.clear()

	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	var adapter_name: String = ""
	if is_instance_valid(rd):
		adapter_name = rd.get_device_name()
	else:
		adapter_name = RenderingServer.get_video_adapter_name()

	if adapter_name.is_empty():
		adapter_name = "Default Graphics Adapter"

	var display_text: String = adapter_name + " (Active Device)"
	_available_gpus[display_text] = 0
	gpu_options.add_item(display_text)
	gpu_options.select(0)


## Connects all widget selection signals to their corresponding handlers.
func _connect_signals() -> void:
	print("HardwareSection: Connecting hardware widget signals.")
	gpu_options.item_selected.connect(_on_gpu_selected)
	auto_tune_button.pressed.connect(_on_auto_tune_pressed)

	renderer_forward_button.pressed.connect(
		_on_renderer_pressed.bind("forward_plus", "Forward+ (Vulkan High-End)")
	)
	renderer_mobile_button.pressed.connect(
		_on_renderer_pressed.bind("mobile", "Mobile (Vulkan Mobile)")
	)
	renderer_compat_button.pressed.connect(
		_on_renderer_pressed.bind("gl_compatibility", "Compatibility (OpenGL Low-End)")
	)


## Synchronizes renderer and GPU selections with stored settings.
func load_settings() -> void:
	print("HardwareSection: Loading hardware settings from configuration.")
	var cur_renderer: String = (
		GlobalSettings.get_setting("Settings", "renderer", "forward_plus") as String
	)
	for key: String in _renderer_btn_map.keys():
		_renderer_btn_map[key].button_pressed = (key == cur_renderer)

	var saved_gpu: int = GlobalSettings.get_setting("Settings", "gpu_adapter_index", 0) as int
	if saved_gpu < gpu_options.get_item_count():
		gpu_options.select(saved_gpu)


## Updates benchmark button visual state during automated passes.
func set_benchmark_state(is_running: bool) -> void:
	print("HardwareSection: Updating auto-tune button state: ", is_running)
	auto_tune_button.disabled = is_running
	auto_tune_button.text = ("Benchmarking..." if is_running else "Auto-Tune for 60 FPS")


## Handles GPU adapter selection and dispatches restart confirmation.
func _on_gpu_selected(index: int) -> void:
	var label: String = gpu_options.get_item_text(index)
	var gpu_idx: int = _available_gpus.get(label, 0) as int
	var current_gpu: int = GlobalSettings.get_setting("Settings", "gpu_adapter_index", 0) as int
	if current_gpu == gpu_idx:
		return

	print("HardwareSection: Selected GPU adapter index: ", gpu_idx)
	var msg: String = (
		"Switching GPU adapter to '"
		+ label
		+ "' requires restarting the application.\n\nRestart now?"
	)
	restart_required.emit(msg, "", gpu_idx)


## Handles renderer toggle and dispatches restart confirmation signal.
func _on_renderer_pressed(rend_key: String, label: String) -> void:
	print("HardwareSection: Selected rendering engine: ", rend_key)
	var current_rend: String = (
		GlobalSettings.get_setting("Settings", "renderer", "forward_plus") as String
	)
	if current_rend == rend_key:
		return

	var msg: String = (
		"Changing the rendering engine to '"
		+ label
		+ "' requires restarting the game.\n\nRestart now?"
	)
	restart_required.emit(msg, rend_key, -1)


## Handles auto-tune benchmark trigger button.
func _on_auto_tune_pressed() -> void:
	print("HardwareSection: Auto-tune button pressed.")
	auto_tune_requested.emit()
