@tool
## Positioned volumetric cloud canopy for ocean scenes.
##
## Renders fast, non-repeating domain-warped volumetric clouds at a real world altitude above
## an ocean. Centers its canopy mesh on the active camera XZ at runtime while sampling clouds
## in world space so motion stays anchored and never tiles.
class_name OceanClouds
extends Node3D

## Shader uniform key for wind direction vector.
const PARAM_WIND_DIRECTION: StringName = &"wind_direction"
## Shader uniform key for horizontal cloud travel speed.
const PARAM_WIND_SPEED: StringName = &"wind_speed"
## Shader uniform key for internal cloud churn speed.
const PARAM_EVOLUTION_SPEED: StringName = &"evolution_speed"
## Shader uniform key for world-space noise scale.
const PARAM_CLOUD_SCALE: StringName = &"cloud_scale"
## Shader uniform key for macro cloud coverage.
const PARAM_CLOUD_COVERAGE: StringName = &"cloud_coverage"
## Shader uniform key for optical density multiplier.
const PARAM_CLOUD_DENSITY: StringName = &"cloud_density"
## Shader uniform key for virtual slab thickness in meters.
const PARAM_CLOUD_THICKNESS: StringName = &"cloud_thickness"
## Shader uniform key for volumetric raymarch step count.
const PARAM_MARCH_STEPS: StringName = &"march_steps"
## Shader uniform key for normalized direction toward the sun.
const PARAM_SUN_DIRECTION: StringName = &"sun_direction"
## Shader uniform key for sunlit cloud albedo color.
const PARAM_CLOUD_COLOR: StringName = &"cloud_color"
## Shader uniform key for shadowed underbelly color.
const PARAM_SHADOW_COLOR: StringName = &"shadow_color"
## Shader uniform key for direct sun tint color.
const PARAM_SUN_COLOR: StringName = &"sun_color"
## Shader uniform key for forward-scattering silver lining intensity.
const PARAM_SILVER_LINING: StringName = &"silver_lining"
## Shader uniform key for radial horizon fade radius.
const PARAM_CANOPY_RADIUS: StringName = &"canopy_radius"
## Shader uniform key for vertex horizon curvature droop.
const PARAM_HORIZON_CURVATURE: StringName = &"horizon_curvature"

## Squared XZ camera movement threshold in meters before recentering canopy.
const FOLLOW_THRESHOLD_SQ: float = 1.0
## Default fallback direction toward the sun when no [DirectionalLight3D] exists.
const DEFAULT_SUN_DIR: Vector3 = Vector3(0.45, 0.65, -0.60)

@export_group("Wind & Motion")
## Horizontal wind travel direction in world XZ space.
@export var wind_direction: Vector2 = Vector2(1.0, 0.35):
	set(value):
		wind_direction = value
		_set_param(PARAM_WIND_DIRECTION, wind_direction)

## Horizontal cloud drift speed in world meters per second.
@export_range(0.0, 120.0, 0.5) var wind_speed: float = 18.0:
	set(value):
		wind_speed = value
		_set_param(PARAM_WIND_SPEED, wind_speed)

## Speed at which cloud edges warp and churn over time.
@export_range(0.0, 2.0, 0.05) var evolution_speed: float = 0.25:
	set(value):
		evolution_speed = value
		_set_param(PARAM_EVOLUTION_SPEED, evolution_speed)

@export_group("Cloud Shape")
## World-space frequency scale of cloud formations.
@export_range(0.0003, 0.02, 0.0001) var cloud_scale: float = 0.0022:
	set(value):
		cloud_scale = value
		_set_param(PARAM_CLOUD_SCALE, cloud_scale)

## Base cloud sky coverage fraction.
@export_range(0.0, 1.0, 0.01) var cloud_coverage: float = 0.52:
	set(value):
		cloud_coverage = value
		_set_param(PARAM_CLOUD_COVERAGE, cloud_coverage)

## Optical density multiplier controlling cloud opacity and thickness.
@export_range(0.1, 5.0, 0.05) var cloud_density: float = 1.6:
	set(value):
		cloud_density = value
		_set_param(PARAM_CLOUD_DENSITY, cloud_density)

## Virtual volumetric slab thickness in meters.
@export_range(10.0, 400.0, 5.0) var cloud_thickness: float = 120.0:
	set(value):
		cloud_thickness = value
		_set_param(PARAM_CLOUD_THICKNESS, cloud_thickness)

## Volumetric raymarch steps per fragment (higher is smoother, costlier).
@export_range(2, 8, 1) var march_steps: int = 4:
	set(value):
		march_steps = value
		_set_param(PARAM_MARCH_STEPS, march_steps)

@export_group("Lighting & Color")
## Optional [DirectionalLight3D] providing sun direction and color; auto-detected if unset.
@export var sun_light: DirectionalLight3D = null:
	set(value):
		sun_light = value
		sync_sun_light()

## Sunlit cloud body color.
@export var cloud_color: Color = Color(0.96, 0.97, 1.0, 1.0):
	set(value):
		cloud_color = value
		_set_param(PARAM_CLOUD_COLOR, cloud_color)

## Shadowed cloud base and ambient bounce color.
@export var shadow_color: Color = Color(0.32, 0.38, 0.48, 1.0):
	set(value):
		shadow_color = value
		_set_param(PARAM_SHADOW_COLOR, shadow_color)

## Direct sunlight scatter tint used when [member sun_light] is unset.
@export var sun_color: Color = Color(1.0, 0.95, 0.86, 1.0):
	set(value):
		sun_color = value
		_set_param(PARAM_SUN_COLOR, sun_color)

## Forward-scattering silver lining intensity around the sun.
@export_range(0.0, 1.5, 0.05) var silver_lining: float = 0.45:
	set(value):
		silver_lining = value
		_set_param(PARAM_SILVER_LINING, silver_lining)

@export_group("Canopy Geometry")
## Half-extent radius of the cloud canopy mesh in meters.
@export_range(200.0, 6000.0, 50.0) var canopy_radius: float = 1800.0:
	set(value):
		canopy_radius = value
		_update_canopy_geometry()

## Downward horizon curvature factor simulating Earth curvature at distance.
@export_range(0.0, 0.0002, 0.000005) var horizon_curvature: float = 0.00004:
	set(value):
		horizon_curvature = value
		_set_param(PARAM_HORIZON_CURVATURE, horizon_curvature)

## Centers canopy XZ on the active [Camera3D] at runtime for infinite ocean travel.
@export var follow_camera_xz: bool = true:
	set(value):
		follow_camera_xz = value
		if is_inside_tree():
			set_process(follow_camera_xz and not Engine.is_editor_hint())

## Cached shader material bound to [member _cloud_mesh].
var _material: ShaderMaterial = null
## Cached mesh child rendering the cloud canopy.
@onready var _cloud_mesh: MeshInstance3D = $CloudMesh as MeshInstance3D


## Initializes canopy mesh, shader uniforms, sun sync, and camera-follow gating.
func _ready() -> void:
	assert(is_instance_valid(_cloud_mesh), "OceanClouds requires a CloudMesh child.")
	_ensure_unique_material()
	_configure_mesh_flags()
	_update_canopy_geometry()
	_apply_all_uniforms()
	sync_sun_light()
	set_process(follow_camera_xz and not Engine.is_editor_hint())


## Keeps canopy centered on active camera XZ at runtime while preserving placed Y altitude.
func _process(_delta: float) -> void:
	var viewport: Viewport = get_viewport()
	if not is_instance_valid(viewport):
		return
	var cam: Camera3D = viewport.get_camera_3d()
	if not is_instance_valid(cam):
		return
	var cam_pos: Vector3 = cam.global_position
	var cur_pos: Vector3 = global_position
	var dx: float = cam_pos.x - cur_pos.x
	var dz: float = cam_pos.z - cur_pos.z
	if (dx * dx + dz * dz) >= FOLLOW_THRESHOLD_SQ:
		global_position = Vector3(cam_pos.x, cur_pos.y, cam_pos.z)


## Syncs shader sun direction and color from [member sun_light] or first scene sun.
func sync_sun_light() -> void:
	if not is_inside_tree():
		return
	var target_sun: DirectionalLight3D = sun_light
	if not is_instance_valid(target_sun):
		target_sun = _find_scene_directional_light()
	if is_instance_valid(target_sun):
		var toward_sun: Vector3 = target_sun.global_basis.z.normalized()
		_set_param(PARAM_SUN_DIRECTION, toward_sun)
		_set_param(PARAM_SUN_COLOR, target_sun.light_color)
	else:
		_set_param(PARAM_SUN_DIRECTION, DEFAULT_SUN_DIR.normalized())
		_set_param(PARAM_SUN_COLOR, sun_color)


## Binds a cached [MaterialCache] variant of [ShaderMaterial] for per-instance uniforms.
func _ensure_unique_material() -> void:
	if not is_instance_valid(_cloud_mesh):
		return
	var existing: Material = _cloud_mesh.material_override
	if existing is ShaderMaterial:
		var variant_key: String = String(get_path()) if is_inside_tree() else String(name)
		if variant_key.is_empty():
			variant_key = str(get_instance_id())
		var cached_mat: Material = MaterialCache.get_variant(existing, variant_key)
		if cached_mat is ShaderMaterial:
			_material = cached_mat as ShaderMaterial
			_cloud_mesh.material_override = _material


## Applies volumetric render layer and disables shadow casting and GI on the canopy mesh.
func _configure_mesh_flags() -> void:
	if not is_instance_valid(_cloud_mesh):
		return
	_cloud_mesh.layers = CollisionLayers.RENDER_MASK_VOLUMETRICS
	_cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cloud_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_cloud_mesh.extra_cull_margin = 500.0


## Resizes the canopy [PlaneMesh] to match [member canopy_radius] and updates shader uniform.
func _update_canopy_geometry() -> void:
	if not is_inside_tree() or not is_instance_valid(_cloud_mesh):
		return
	if _cloud_mesh.mesh is PlaneMesh:
		var plane: PlaneMesh = _cloud_mesh.mesh as PlaneMesh
		var diameter: float = canopy_radius * 2.0
		plane.size = Vector2(diameter, diameter)
	_set_param(PARAM_CANOPY_RADIUS, canopy_radius)


## Pushes all exported parameters to the bound [ShaderMaterial].
func _apply_all_uniforms() -> void:
	_set_param(PARAM_WIND_DIRECTION, wind_direction)
	_set_param(PARAM_WIND_SPEED, wind_speed)
	_set_param(PARAM_EVOLUTION_SPEED, evolution_speed)
	_set_param(PARAM_CLOUD_SCALE, cloud_scale)
	_set_param(PARAM_CLOUD_COVERAGE, cloud_coverage)
	_set_param(PARAM_CLOUD_DENSITY, cloud_density)
	_set_param(PARAM_CLOUD_THICKNESS, cloud_thickness)
	_set_param(PARAM_MARCH_STEPS, march_steps)
	_set_param(PARAM_CLOUD_COLOR, cloud_color)
	_set_param(PARAM_SHADOW_COLOR, shadow_color)
	_set_param(PARAM_SUN_COLOR, sun_color)
	_set_param(PARAM_SILVER_LINING, silver_lining)
	_set_param(PARAM_CANOPY_RADIUS, canopy_radius)
	_set_param(PARAM_HORIZON_CURVATURE, horizon_curvature)


## Writes a single shader parameter safely when the node and material are valid.
func _set_param(param: StringName, value: Variant) -> void:
	if not is_inside_tree() or not is_instance_valid(_material):
		return
	_material.set_shader_parameter(param, value)


## Locates the first [DirectionalLight3D] inside the current scene root.
func _find_scene_directional_light() -> DirectionalLight3D:
	var tree: SceneTree = get_tree()
	if not is_instance_valid(tree):
		return null
	var root: Node = tree.current_scene
	if not is_instance_valid(root):
		root = get_parent()
	if not is_instance_valid(root):
		return null
	var lights: Array[Node] = root.find_children("*", "DirectionalLight3D", true, false)
	for node: Node in lights:
		if node is DirectionalLight3D:
			return node as DirectionalLight3D
	return null
