## Controls volumetric underwater fog density, edge sharpness, and camera-aligned
## visibility fade plane in response to player flashlight state and camera submersion.
class_name HydrogenFogVolume
extends FogVolume

const PARAM_BASE_DENSITY: StringName = &"base_density"
const PARAM_EDGE_FADE: StringName = &"edge_fade"
const PARAM_CAMERA_POS: StringName = &"camera_pos"
const PARAM_CAMERA_FORWARD: StringName = &"camera_forward"
const PARAM_FADE_PLANE_DIST: StringName = &"fade_plane_dist"

## Volumetric fog density when player flashlight is off.
@export_range(0.0, 1.0, 0.005) var base_density: float = 0.12

## Reduced volumetric fog density when player flashlight is on.
@export_range(0.0, 1.0, 0.005) var flashlight_density: float = 0.04

## Camera-forward visibility plane distance (meters) when flashlight is off.
@export_range(0.5, 50.0, 0.5) var base_fade_dist: float = 3.0

## Extended visibility plane distance (meters) when flashlight is on.
@export_range(0.5, 50.0, 0.5) var flashlight_fade_dist: float = 6.0

## Lerp rate between baseline and flashlight fog states.
@export_range(0.1, 20.0, 0.1) var transition_speed: float = 2.5

## Distance-gating threshold (meters) from active camera.
@export_range(10.0, 500.0, 1.0) var max_update_distance: float = 95.0

var _current_density: float = 0.12
var _current_fade_dist: float = 3.0
var _material_rid: RID = RID()
var _cached_flashlight: SpotLight3D = null


## Caches FogVolume ShaderMaterial RID and initializes baseline fog uniforms.
func _ready() -> void:
	layers = 512
	_current_density = base_density
	_current_fade_dist = base_fade_dist
	if material is ShaderMaterial:
		_material_rid = (material as ShaderMaterial).get_rid()
		RenderingServer.material_set_param(_material_rid, PARAM_BASE_DENSITY, _current_density)
		RenderingServer.material_set_param(_material_rid, PARAM_FADE_PLANE_DIST, _current_fade_dist)


## Updates camera fade plane, edge fade sharpness, and flashlight density interpolation.
func _process(delta: float) -> void:
	if not _material_rid.is_valid():
		return

	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if not is_instance_valid(cam):
		return

	var half_len: float = size.length() * 0.5
	var max_dist: float = max_update_distance + half_len
	if global_position.distance_squared_to(cam.global_position) > max_dist * max_dist:
		return

	var flashlight_active: bool = _is_player_flashlight_on()
	var target_density: float = flashlight_density if flashlight_active else base_density
	var target_fade: float = flashlight_fade_dist if flashlight_active else base_fade_dist
	var weight: float = clampf(transition_speed * delta, 0.0, 1.0)

	_current_density = lerpf(_current_density, target_density, weight)
	_current_fade_dist = lerpf(_current_fade_dist, target_fade, weight)

	var submerged: bool = _is_parent_water_submerged()
	var target_edge_fade: float = 0.05 if submerged else 0.15

	RenderingServer.material_set_param(_material_rid, PARAM_BASE_DENSITY, _current_density)
	RenderingServer.material_set_param(_material_rid, PARAM_FADE_PLANE_DIST, _current_fade_dist)
	RenderingServer.material_set_param(_material_rid, PARAM_EDGE_FADE, target_edge_fade)
	RenderingServer.material_set_param(_material_rid, PARAM_CAMERA_POS, cam.global_position)
	RenderingServer.material_set_param(
		_material_rid, PARAM_CAMERA_FORWARD, -cam.global_transform.basis.z
	)


## Queries parent HydrogenWaterBody submersion status if available.
func _is_parent_water_submerged() -> bool:
	var parent_node: Node = get_parent()
	if (
		is_instance_valid(parent_node)
		and parent_node.has_method(&"should_draw_camera_underwater_effect")
	):
		return bool(parent_node.call(&"should_draw_camera_underwater_effect"))
	return false


## Locates and checks player's flashlight_controller.flashlight SpotLight3D visibility.
func _is_player_flashlight_on() -> bool:
	if is_instance_valid(_cached_flashlight):
		return _cached_flashlight.visible and _cached_flashlight.is_visible_in_tree()

	if not is_inside_tree():
		return false

	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	for player: Node in players:
		var fc: Variant = player.get(&"flashlight_controller")
		if fc is Object:
			var light_var: Variant = (fc as Object).get(&"flashlight")
			if light_var is SpotLight3D:
				_cached_flashlight = light_var as SpotLight3D
				return _cached_flashlight.visible and _cached_flashlight.is_visible_in_tree()
	return false
