extends PanelContainer

const HISTORY_NUM_FRAMES: int = 150

@onready var metrics_label: RichTextLabel = $MetricsLabel

var player: CharacterBody3D

# Performance arrays and rolling sums
var _last_tick: int = 0
var _total_history: Array[float] = []
var _cpu_history: Array[float] = []
var _gpu_history: Array[float] = []

var _total_sum: float = 0.0
var _cpu_sum: float = 0.0
var _gpu_sum: float = 0.0

# Cached strings for things that rarely/never change
var _hardware_info_str: String = ""
var _settings_info_str: String = ""


func _ready() -> void:
	visible = false

	player = get_tree().get_first_node_in_group("player") as CharacterBody3D

	metrics_label.bbcode_enabled = true
	metrics_label.add_theme_color_override("font_outline_color", Color.BLACK)
	metrics_label.add_theme_constant_override("outline_size", 4)

	# Enable hardware rendering time measurements
	var vp_rid: RID = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)

	_cache_hardware_info()
	_cache_settings_info()
	get_viewport().size_changed.connect(_cache_settings_info)


func _process(_delta: float) -> void:
	if not visible or not player:
		return

	_update_frametime_history()

	var fps: float = Engine.get_frames_per_second()
	var vel: Vector3 = player.velocity
	var speed: float = vel.length()

	var fps_color: String = "green"
	if fps >= 60.0:
		fps_color = "green"
	elif fps >= 30.0:
		fps_color = "yellow"
	else:
		fps_color = "red"

	var current_input: Vector2 = Input.get_vector("left", "right", "forward", "backward")
	var is_pressing_keys: bool = current_input.length() > 0.1

	var state: String = "UNKNOWN"
	if player.get("system_menu") and player.system_menu.flying:
		state = "NOCLIP"
	elif player.get("state_machine") and player.state_machine.state:
		state = player.state_machine.state.name.to_upper()
		if state == "GROUND":
			if player.crouching:
				state = "CROUCHING" if is_pressing_keys else "CROUCH IDLE"
			elif player.sprint_active:
				state = "SPRINTING"
			elif is_pressing_keys:
				state = "WALKING"
			else:
				state = "IDLE"

	var static_mem: int = OS.get_static_memory_usage()
	var vram_usage: int = int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	var flashlight_str: String = "OFF"
	var flashlight: Node = player.get_node_or_null("%Flashlight")
	if flashlight:
		flashlight_str = "ON" if flashlight.visible else "OFF"

	var weapon_str: String = "NONE"
	var weapon_holder: Node = player.get_node_or_null("%WeaponHolder")
	if weapon_holder and weapon_holder.get_child_count() > 0:
		weapon_str = weapon_holder.get_child(0).name

	# --- TEXT ASSEMBLY ---
	var text: String = ""
	text += "[color=%s][b]%d FPS[/b][/color]\n\n" % [fps_color, int(fps)]

	# Use a BBCode table to align the frametime data perfectly
	text += "[table=5]\n"
	text += "[cell][/cell][cell] [color=gray]Average[/color] [/cell]"
	text += "[cell] [color=gray]Best[/color] [/cell]"
	text += "[cell] [color=gray]Worst[/color] [/cell][cell] [color=gray]Last[/color] [/cell]\n"

	text += _format_metric_row("Total:", _total_sum, _total_history)
	text += _format_metric_row("CPU:", _cpu_sum, _cpu_history)
	text += _format_metric_row("GPU:", _gpu_sum, _gpu_history)
	text += "[/table]\n"
	
	# Append the cached hardware/settings matching the requested image layout
	text += "[color=gray]" + _hardware_info_str + _settings_info_str + "[/color]\n"

	text += "\n[color=gray]--- MEMORY & RENDERING ---[/color]\n"
	text += "RAM: %s\n" % String.humanize_size(static_mem)
	text += "VRAM: %s\n" % String.humanize_size(vram_usage)
	text += "Draw Calls: %d\n" % draw_calls
	text += "Objects: %d\n" % objects
	text += "Primitives: %d\n" % primitives

	text += "\n[color=gray]--- PLAYER STATE ---[/color]\n"
	text += "STATE: %s\n" % state
	text += "WEAPON: %s\n" % weapon_str
	text += "SPEED: %.2f m/s\n" % speed
	text += "POS: %s\n" % var_to_str(player.global_position).replace("Vector3", "")
	text += "GROUNDED: %s\n" % ("YES" if player.is_on_floor() else "NO")
	text += "FLASHLIGHT: %s\n" % flashlight_str

	metrics_label.text = text


func toggle_window() -> void:
	visible = !visible


func _update_frametime_history() -> void:
	var current_tick: int = Time.get_ticks_usec()
	var frametime_total: float = (current_tick - _last_tick) * 0.001
	_last_tick = current_tick

	var vp_rid: RID = get_viewport().get_viewport_rid()
	var frame_setup: float = RenderingServer.get_frame_setup_time_cpu()
	var frametime_cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + frame_setup
	var frametime_gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)

	_total_sum += frametime_total
	_total_history.push_back(frametime_total)
	if _total_history.size() > HISTORY_NUM_FRAMES:
		_total_sum -= _total_history.pop_front()

	_cpu_sum += frametime_cpu
	_cpu_history.push_back(frametime_cpu)
	if _cpu_history.size() > HISTORY_NUM_FRAMES:
		_cpu_sum -= _cpu_history.pop_front()

	_gpu_sum += frametime_gpu
	_gpu_history.push_back(frametime_gpu)
	if _gpu_history.size() > HISTORY_NUM_FRAMES:
		_gpu_sum -= _gpu_history.pop_front()


func _format_metric_row(title: String, sum_val: float, history: Array[float]) -> String:
	if history.is_empty():
		return ""
	
	var avg_val: float = sum_val / history.size()
	var min_val: float = history.min()
	var max_val: float = history.max()
	var last_val: float = history.back()
	
	return "[cell]%s [/cell][cell][color=%s]%.2f[/color][/cell][cell][color=%s]%.2f[/color][/cell][cell][color=%s]%.2f[/color][/cell][cell][color=%s]%.2f[/color][/cell]\n" % [
		title,
		_get_ms_color(avg_val), avg_val,
		_get_ms_color(min_val), min_val,
		_get_ms_color(max_val), max_val,
		_get_ms_color(last_val), last_val
	]


func _get_ms_color(ms: float) -> String:
	if ms < 8.34: return "#38bdf8"    # Cyan (120+ FPS)
	if ms < 16.67: return "#80e25f"   # Green (60+ FPS)
	if ms < 33.34: return "#facc15"   # Yellow (30+ FPS)
	return "#ef4444"                  # Red (Below 30 FPS)


func _cache_hardware_info() -> void:
	var cpu_name: String = OS.get_processor_name().replace("(R)", "").replace("(TM)", "")
	var threads: int = OS.get_processor_count()
	var os_name: String = OS.get_name()
	var bitness: String = "64-bit" if OS.has_feature("64") else "32-bit"
	
	var gpu_name: String = RenderingServer.get_video_adapter_name().trim_suffix("/PCIe/SSE2")
	var api_ver: String = RenderingServer.get_video_adapter_api_version()
	
	var driver: String = str(ProjectSettings.get_setting("rendering/rendering_device/driver"))
	var api_str: String = "Vulkan" if driver == "vulkan" else driver.capitalize()

	_hardware_info_str = "%s, %d threads\n%s %s, %s %s\n%s\n" % [
		cpu_name, threads, os_name, bitness, api_str, api_ver, gpu_name
	]


func _cache_settings_info() -> void:
	_settings_info_str = ""
	var method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	var method_str: String = "Forward+" if method == "forward_plus" else method.capitalize()
	_settings_info_str += "Rendering Method: %s\n" % method_str

	var vp: Viewport = get_viewport()
	var res: Vector2i = vp.size
	_settings_info_str += "Viewport: %d×%d\n" % [res.x, res.y]

	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return
		
	var world: World3D = cam.get_world_3d()
	if world and world.environment:
		var env: Environment = world.environment
		if env.ssr_enabled: _settings_info_str += "SSR: %d Steps\n" % env.ssr_max_steps
		if env.ssao_enabled: _settings_info_str += "SSAO: On\n"
		if env.ssil_enabled: _settings_info_str += "SSIL: On\n"
		if env.sdfgi_enabled: _settings_info_str += "SDFGI: %d Cascades\n" % env.sdfgi_cascades
		if env.glow_enabled: _settings_info_str += "Glow: On\n"
		if env.volumetric_fog_enabled: _settings_info_str += "Volumetric Fog: On\n"
