## Manages citadel core pulsing energy cycles and synchronized visual shaders.
class_name CitadelCore
extends Node3D

@export_group("Core Sync Settings")
## Duration in seconds for core cycle transition phases.
@export var transition_time: float = 1.0

## Duration in seconds for core cycle pause phases.
@export var pause_time: float = 2.0

## Time offset before pause phase ends to activate wave pulse.
@export var wave_duration_offset: float = 0.1

## Central glowing circle mesh rendering pulse shader.
@export var glowing_circle: MeshInstance3D

## Expanding energetic wave mesh instance.
@export var wave_mesh: MeshInstance3D

## Outer protective liquid slime shell mesh.
@export var outer_liquid_shell: MeshInstance3D

## Cached [ShaderMaterial] for the glowing circle.
var _circle_mat: ShaderMaterial

## Cached [ShaderMaterial] for the shockwave mesh.
var _wave_mat: ShaderMaterial

## Cached [ShaderMaterial] for the liquid shell mesh.
var _slime_mat: ShaderMaterial

## Current interpolated alpha transparency for shockwave visibility.
var _current_wave_alpha: float = 0.0


## Initializes cached materials and configures core pulse shader timings.
func _ready() -> void:
	print("CitadelCore: Initializing citadel core in _ready().")
	if glowing_circle == null:
		glowing_circle = get_node_or_null("GlowingCircle") as MeshInstance3D
	if wave_mesh == null:
		wave_mesh = get_node_or_null("WaveMesh") as MeshInstance3D
	if outer_liquid_shell == null:
		outer_liquid_shell = get_node_or_null("OuterLiquidShell") as MeshInstance3D

	_initialize_materials()
	_apply_initial_shader_timings()


## Binds shader materials to core meshes using [MaterialCache].
func _initialize_materials() -> void:
	print("CitadelCore: Binding materials via MaterialCache.")
	_circle_mat = _setup_material(glowing_circle)
	_wave_mat = _setup_material(wave_mesh)
	_slime_mat = _setup_material(outer_liquid_shell)


## Retrieves or creates a cached [ShaderMaterial] for [param mesh_node].
func _setup_material(mesh_node: MeshInstance3D) -> ShaderMaterial:
	var target_name: StringName = mesh_node.name if is_instance_valid(mesh_node) else &"null"
	print("CitadelCore: Setting up material for: ", target_name)
	if not is_instance_valid(mesh_node):
		return null

	var mat: Material = mesh_node.get_active_material(0)
	if mat is ShaderMaterial:
		var variant_key: String = "%d_%s" % [get_instance_id(), mesh_node.name]
		var cached_mat: Material = MaterialCache.get_variant(mat, variant_key)
		if cached_mat is ShaderMaterial:
			var shader_mat: ShaderMaterial = cached_mat if cached_mat is ShaderMaterial else null
			mesh_node.material_override = shader_mat
			return shader_mat

	return null


## Pushes exported timing settings to the circle shader.
func _apply_initial_shader_timings() -> void:
	print("CitadelCore: Pushing initial shader timings.")
	if is_instance_valid(_circle_mat):
		_circle_mat.set_shader_parameter("transition_time", transition_time)
		_circle_mat.set_shader_parameter("pause_time", pause_time)


## Updates core pulse cycle timing parameters from gameplay systems.
func update_core_timing(new_transition: float, new_pause: float) -> void:
	print("CitadelCore: Updating core timing. Trans: ", new_transition, " Pause: ", new_pause)
	transition_time = new_transition
	pause_time = new_pause

	if is_instance_valid(_circle_mat):
		_circle_mat.set_shader_parameter("transition_time", transition_time)
		_circle_mat.set_shader_parameter("pause_time", pause_time)


## Drives wave visibility interpolation synchronized to internal shader clock.
func _process(delta: float) -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var cycle_length: float = (transition_time + pause_time) * 2.0
	var t: float = fmod(current_time, cycle_length)

	var is_wave_active: bool = false
	var max_pause_start: float = transition_time
	var max_pause_end: float = max_pause_start + pause_time - wave_duration_offset
	var min_pause_start: float = (transition_time * 2.0) + pause_time
	var min_pause_end: float = min_pause_start + pause_time - wave_duration_offset

	if (
		(t >= max_pause_start and t <= max_pause_end)
		or (t >= min_pause_start and t <= min_pause_end)
	):
		is_wave_active = true

	var target_alpha: float = 1.0 if is_wave_active else 0.0
	_current_wave_alpha = move_toward(_current_wave_alpha, target_alpha, delta * 15.0)

	if is_instance_valid(_wave_mat):
		_wave_mat.set_shader_parameter("wave_visibility", _current_wave_alpha)
