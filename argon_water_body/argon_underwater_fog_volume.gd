## Controls underwater [FogVolume] density and fallback depth fog based on player flashlight state.
class_name ArgonUnderwaterFogVolume
extends FogVolume

## Group name used to locate the active player node.
const GROUP_PLAYER: StringName = &"player"
## Property name on the player node referencing the flashlight controller.
const PROP_FLASHLIGHT_CTRL: StringName = &"flashlight_controller"
## Property name for checking visibility on a flashlight controller.
const PROP_VISIBLE: StringName = &"visible"
## Optional method name on flashlight controller for active state query.
const METHOD_IS_ON: StringName = &"is_flashlight_on"
## Shader uniform name for fog density.
const PARAM_DENSITY: StringName = &"density"
## Shader uniform name for planar clipping plane.
const PARAM_FADE_PLANE: StringName = &"fade_plane"
## Shader uniform name for SDF edge fade.
const PARAM_EDGE_FADE: StringName = &"edge_fade"

## Base volumetric fog density when the player's flashlight is off.
@export var base_density: float = 0.12
## Reduced volumetric fog density when the player's flashlight is on.
@export var flashlight_density: float = 0.04
## Base visibility fade distance in meters when the flashlight is off.
@export var base_fade_dist: float = 3.0
## Extended visibility fade distance in meters when the flashlight is on.
@export var flashlight_fade_dist: float = 6.0
## Interpolation speed for density and distance transitions.
@export var transition_speed: float = 2.5

var _player_node: Node3D = null
var _flashlight_obj: Object = null
var _active_env: Environment = null
var _is_submerged: bool = false
var _current_density: float = 0.12
var _current_fade_dist: float = 3.0


## Initializes default fog values and disables per-frame processing until needed.
func _ready() -> void:
	_current_density = base_density
	_current_fade_dist = base_fade_dist
	_apply_fog_parameters()
	set_process(false)


## Smoothly interpolates density and visibility distance toward target flashlight state.
func _process(delta: float) -> void:
	if not is_instance_valid(_player_node):
		_cache_player_reference()
	var light_on: bool = _is_flashlight_visible()
	var target_density: float = flashlight_density if light_on else base_density
	var target_dist: float = flashlight_fade_dist if light_on else base_fade_dist
	var step: float = clampf(delta * transition_speed, 0.0, 1.0)
	_current_density = lerpf(_current_density, target_density, step)
	_current_fade_dist = lerpf(_current_fade_dist, target_dist, step)
	_apply_fog_parameters()


## Sets camera submersion state and binds the active [Environment] for non-volumetric fallback.
func set_submerged_state(submerged: bool, env: Environment) -> void:
	_is_submerged = submerged
	_active_env = env
	if submerged:
		_cache_player_reference()
		set_process(true)
		_apply_fog_parameters()
	else:
		set_process(false)


## Updates the edge fade parameter on the attached [ShaderMaterial] or [FogMaterial].
func set_edge_fade_value(fade_val: float) -> void:
	var mat: Material = material
	if mat is ShaderMaterial:
		var smat: ShaderMaterial = mat as ShaderMaterial
		smat.set_shader_parameter(PARAM_EDGE_FADE, fade_val)
	elif mat is FogMaterial:
		var fmat: FogMaterial = mat as FogMaterial
		fmat.edge_fade = fade_val


## Locates and caches the player node and its [member PROP_FLASHLIGHT_CTRL] reference.
func _cache_player_reference() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var first_player: Node = tree.get_first_node_in_group(GROUP_PLAYER)
	_player_node = first_player as Node3D
	_flashlight_obj = null
	if is_instance_valid(_player_node):
		var raw_ctrl: Variant = _player_node.get(PROP_FLASHLIGHT_CTRL)
		if typeof(raw_ctrl) == TYPE_OBJECT:
			_flashlight_obj = raw_ctrl as Object


## Returns true when the player's flashlight controller exists and is currently visible/on.
func _is_flashlight_visible() -> bool:
	if not is_instance_valid(_flashlight_obj):
		return false
	if _flashlight_obj.has_method(METHOD_IS_ON):
		var res: Variant = _flashlight_obj.call(METHOD_IS_ON)
		if typeof(res) == TYPE_BOOL:
			return bool(res)
	var vis_val: Variant = _flashlight_obj.get(PROP_VISIBLE)
	if typeof(vis_val) == TYPE_BOOL:
		return bool(vis_val)
	return false


## Writes interpolated density and fade distance to material uniforms and fallback environment fog.
func _apply_fog_parameters() -> void:
	var mat: Material = material
	if mat is ShaderMaterial:
		var smat: ShaderMaterial = mat as ShaderMaterial
		smat.set_shader_parameter(PARAM_DENSITY, _current_density)
		var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		if is_instance_valid(cam):
			var fwd: Vector3 = -cam.global_transform.basis.z.normalized()
			var limit_pos: Vector3 = cam.global_position + fwd * _current_fade_dist
			var plane_d: float = fwd.dot(limit_pos)
			var plane_vec: Vector4 = Vector4(-fwd.x, -fwd.y, -fwd.z, plane_d)
			smat.set_shader_parameter(PARAM_FADE_PLANE, plane_vec)
		else:
			smat.set_shader_parameter(PARAM_FADE_PLANE, Vector4(0.0, 1.0, 0.0, 999.0))
	elif mat is FogMaterial:
		var fmat: FogMaterial = mat as FogMaterial
		fmat.density = _current_density

	if _is_submerged and is_instance_valid(_active_env):
		if not _active_env.volumetric_fog_enabled:
			_active_env.fog_depth_begin = _current_fade_dist * 0.15
			_active_env.fog_depth_end = _current_fade_dist
