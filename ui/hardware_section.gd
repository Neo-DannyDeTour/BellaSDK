## Controls GPU device selection, backend drivers, and benchmark runs.
class_name HardwareSection
extends VBoxContainer

## Emitted when switching GPU or renderer backend to request confirmation dialog.
signal restart_required(message: String, renderer_key: String, gpu_idx: int)
## Emitted when the user starts the automated 60 FPS tuning benchmark pass.
signal auto_tune_requested

## Reference to the video card selection [OptionButton].
@onready var gpu_options: OptionButton = %GPUAdapterOptionButton
## Reference to the renderer selection [OptionButton].
@onready var renderer_options: OptionButton = %RendererOptionButton
## Reference to the auto-optimization benchmark [Button].
@onready var auto_tune_button: Button = %AutoTuneButton

## Map storing GPU adapter names mapped to their physical hardware index.
var _available_gpus: Dictionary = {}


## Populates hardware dropdowns and hooks UI widget signals.
func _ready() -> void:
	print("HardwareSection: Initializing hardware settings.")
	_populate_dropdowns()
	_connect_signals()
	load_settings()


## Queries available hardware devices and populates dropdown selectors.
func _populate_dropdowns() -> void:
	print("HardwareSection: Populating backend and device options.")
	renderer_options.clear()
	for key: String in VideoConfig.RENDERER_MODES.keys():
		renderer_options.add_item(key)

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


## Connects all widget selection signals to their corresponding handler methods.
func _connect_signals() -> void:
	print("HardwareSection: Connecting hardware widget signals.")
	gpu_options.item_selected.connect(_on_gpu_selected)
	renderer_options.item_selected.connect(_on_renderer_selected)
	auto_tune_button.pressed.connect(_on_auto_tune_pressed)


## Synchronizes renderer selection with stored settings.
func load_settings() -> void:
	print("HardwareSection: Loading hardware settings from configuration.")
	var cur_renderer: String = (
		GlobalSettings.get_setting("Settings", "renderer", "forward_plus") as String
	)
	for i: int in range(renderer_options.get_item_count()):
		var label: String = renderer_options.get_item_text(i)
		if VideoConfig.RENDERER_MODES[label] == cur_renderer:
			renderer_options.select(i)
			break

	var saved_gpu: int = GlobalSettings.get_setting("Settings", "gpu_adapter_index", 0) as int
	if saved_gpu < gpu_options.get_item_count():
		gpu_options.select(saved_gpu)


## Updates benchmark button visual state during automated passes.
## [param is_running] True if benchmark is executing, false when completed.
func set_benchmark_state(is_running: bool) -> void:
	print("HardwareSection: Updating auto-tune button state: ", is_running)
	auto_tune_button.disabled = is_running
	auto_tune_button.text = "Benchmarking..." if is_running else "Auto-Tune for 60 FPS"


## Handles GPU adapter selection and dispatches restart confirmation signal.
## [param index] Item index selected.
func _on_gpu_selected(index: int) -> void:
	var label: String = gpu_options.get_item_text(index)
	var gpu_idx: int = _available_gpus.get(label, 0) as int
	print("HardwareSection: Selected GPU adapter index: ", gpu_idx)
	var msg: String = (
		"Switching GPU adapter to '"
		+ label
		+ "' requires restarting the application.\n\nRestart now?"
	)
	restart_required.emit(msg, "", gpu_idx)


## Handles rendering engine selection and dispatches restart confirmation signal.
## [param index] Item index selected.
func _on_renderer_selected(index: int) -> void:
	var label: String = renderer_options.get_item_text(index)
	var rend_key: String = VideoConfig.RENDERER_MODES[label] as String
	print("HardwareSection: Selected rendering engine: ", rend_key)
	var msg: String = (
		"Changing the rendering engine to '"
		+ label
		+ "' requires restarting the game.\n\nRestart now?"
	)
	restart_required.emit(msg, rend_key, -1)


## Handles benchmark button trigger.
func _on_auto_tune_pressed() -> void:
	print("HardwareSection: Auto-tune button pressed.")
	auto_tune_requested.emit()
