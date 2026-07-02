class_name CitadelCore
extends Node3D

@export_group("Core Sync Settings")
@export var transition_time: float = 1.0
@export var pause_time: float = 2.0
@export var wave_duration_offset: float = 0.1

# Direct node references mapped precisely to your scene tree
@onready var glowing_circle: MeshInstance3D = $GlowingCircle
@onready var wave_mesh: MeshInstance3D = $WaveMesh
@onready var outer_liquid_shell: MeshInstance3D = $OuterLiquidShell

var _circle_mat: ShaderMaterial
var _wave_mat: ShaderMaterial
var _slime_mat: ShaderMaterial

var _current_wave_alpha: float = 0.0

func _ready() -> void:
	_initialize_materials()
	_apply_initial_shader_timings()

func _initialize_materials() -> void:
	_circle_mat = _setup_material(glowing_circle)
	_wave_mat = _setup_material(wave_mesh)
	_slime_mat = _setup_material(outer_liquid_shell)

func _setup_material(mesh_node: MeshInstance3D) -> ShaderMaterial:
	if not mesh_node:
		return null
		
	var mat: Material = mesh_node.get_active_material(0)
	if mat is ShaderMaterial:
		var unique_mat: ShaderMaterial = mat.duplicate() as ShaderMaterial
		mesh_node.material_override = unique_mat
		return unique_mat
		
	return null

func _apply_initial_shader_timings() -> void:
	print("CitadelCore: Pushing exported timings down to the GlowingCircle shader.")
	if _circle_mat:
		_circle_mat.set_shader_parameter("transition_time", transition_time)
		_circle_mat.set_shader_parameter("pause_time", pause_time)

# ------------------------------------------------------------------------------
# Callable Functions
# ------------------------------------------------------------------------------

func update_core_timing(new_transition: float, new_pause: float) -> void:
	print("CitadelCore: Player/System updated core timing. Transition: ", new_transition, ", Pause: ", new_pause)
	transition_time = new_transition
	pause_time = new_pause
	
	if _circle_mat:
		_circle_mat.set_shader_parameter("transition_time", transition_time)
		_circle_mat.set_shader_parameter("pause_time", pause_time)

# ------------------------------------------------------------------------------
# 60 FPS Sync Logic
# ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Time.get_ticks_msec() / 1000.0 inherently mirrors the shader's internal TIME
	var current_time: float = Time.get_ticks_msec() / 1000.0
	
	# Replicate the cycle math from the GlowingCircle shader
	var cycle_length: float = (transition_time + pause_time) * 2.0
	var t: float = fmod(current_time, cycle_length)
	
	var is_wave_active: bool = false
	
	# Calculate Phase 1: Maximum Size Pause
	var max_pause_start: float = transition_time
	var max_pause_end: float = max_pause_start + pause_time - wave_duration_offset
	
	# Calculate Phase 2: Minimum Size Pause
	var min_pause_start: float = (transition_time * 2.0) + pause_time
	var min_pause_end: float = min_pause_start + pause_time - wave_duration_offset
	
	if (t >= max_pause_start and t <= max_pause_end) or (t >= min_pause_start and t <= min_pause_end):
		is_wave_active = true
		
	# Smoothly lerp the alpha for a clean visual transition rather than an instant pop
	var target_alpha: float = 1.0 if is_wave_active else 0.0
	_current_wave_alpha = move_toward(_current_wave_alpha, target_alpha, delta * 15.0)
	
	if _wave_mat:
		_wave_mat.set_shader_parameter("wave_visibility", _current_wave_alpha)
