@tool
## Coordinator for armored planar mirror reflection, oblique frustum projection,
## visibility/distance gating, and per-instance fracture state.
class_name Mirror
extends Node3D

## Emitted when the armored mirror glass takes impact damage and updates fracture state.
signal mirror_cracked(impact_uv: Vector2, intensity: float)

## Per-instance shader uniform controlling crack propagation [0.0..1.0].
const PARAM_CRACK_INTENSITY: StringName = &"crack_intensity"

## Per-instance shader uniform storing normalized UV coordinates of impact.
const PARAM_IMPACT_UV: StringName = &"impact_uv"

## Group tag excluding mirror [SubViewport] from global post-processing overrides.
const GROUP_IGNORE_SETTINGS: StringName = &"ignore_global_video_settings"

## Render layers visible in reflection: Layer 1 (Env) + Layer 2 (Player) + Layer 3 (Interactive).
const REFLECTION_CULL_MASK: int = (
	CollisionLayers.RENDER_MASK_ENVIRONMENT
	| CollisionLayers.RENDER_MASK_PLAYER
	| CollisionLayers.RENDER_MASK_INTERACTIVE
)

## Shared stripped environment resource eliminating per-instance heap allocations.
static var _shared_mirror_env: Environment = null

## Shared empty compositor resource bypassing global compute passes.
static var _shared_empty_compositor: Compositor = null

## Dimensions of the armored mirror surface in world units.
@export var size: Vector2 = Vector2(1.5, 2.0):
	set(value):
		size = value.clamp(Vector2(0.1, 0.1), Vector2(16.0, 16.0))
		if is_inside_tree():
			_resize_resources()

## Viewport pixel resolution multiplier per world unit.
@export_range(8, 256, 1) var pixels_per_unit: int = 64:
	set(value):
		pixels_per_unit = value
		if is_inside_tree():
			_resize_resources()

## Maximum resolution clamp for the [SubViewport] reflection buffer.
@export_range(64, 2048, 16) var max_viewport_size: int = 512:
	set(value):
		max_viewport_size = value
		if is_inside_tree():
			_resize_resources()

## Maximum distance in meters to evaluate reflection camera updates.
@export_range(1.0, 100.0, 0.5) var max_update_distance: float = 15.0:
	set(value):
		max_update_distance = value
		_max_dist_sq = value * value

## Near-plane clipping offset for oblique reflection frustum.
@export_range(0.0, 1.0, 0.01) var cull_near: float = 0.02

## Far-plane culling distance for oblique reflection frustum.
@export_range(5.0, 250.0, 1.0) var cull_far: float = 40.0

## Cached main camera transform used to skip static frames.
var _last_cam_transform: Transform3D = Transform3D.IDENTITY

## Precalculated squared maximum update distance.
var _max_dist_sq: float = 225.0

## Current normalized fracture intensity in range [0.0, 1.0].
var _crack_intensity: float = 0.0

## Current normalized UV coordinates of the latest impact point.
var _impact_uv: Vector2 = Vector2(0.5, 0.5)

## Active [Tween] interpolating fracture shader parameter.
var _crack_tween: Tween = null

## Cached root [Viewport] providing the active scene camera.
var _viewport: Viewport = null

## Quad mesh instance displaying the armored reflection shader.
@onready var _mirror_quad: MeshInstance3D = $Quad as MeshInstance3D

## Reflection [SubViewport] rendering the off-axis camera view.
@onready var _sub_viewport: SubViewport = $MirrorSubViewport as SubViewport

## Off-axis frustum [Camera3D] inside the reflection [SubViewport].
@onready var _mirror_camera: Camera3D = $MirrorSubViewport/Camera3D as Camera3D

## Screen visibility notifier gating [_process] and [SubViewport] updates.
@onready
var _notifier: VisibleOnScreenNotifier3D = $MirrorVisibilityNotifier as VisibleOnScreenNotifier3D

## Box collider shape on the static armor body.
@onready var _collision_shape: CollisionShape3D = $ArmorBody/CollisionShape3D as CollisionShape3D


## Validates child nodes, caches root [Viewport], configures [SubViewport], and gates [_process].
func _ready() -> void:
	assert(is_instance_valid(_mirror_quad), "Mirror: missing Quad MeshInstance3D")
	assert(is_instance_valid(_sub_viewport), "Mirror: missing MirrorSubViewport")
	assert(is_instance_valid(_mirror_camera), "Mirror: missing Camera3D")
	assert(is_instance_valid(_notifier), "Mirror: missing MirrorVisibilityNotifier")
	assert(is_instance_valid(_collision_shape), "Mirror: missing CollisionShape3D")

	_max_dist_sq = max_update_distance * max_update_distance
	_viewport = get_viewport()
	_configure_viewport()
	_resize_resources()

	_mirror_quad.set_instance_shader_parameter(PARAM_CRACK_INTENSITY, _crack_intensity)
	_mirror_quad.set_instance_shader_parameter(PARAM_IMPACT_UV, _impact_uv)

	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(true)
		return

	Utilities.safe_connect(_notifier.screen_entered, _on_screen_entered)
	Utilities.safe_connect(_notifier.screen_exited, _on_screen_exited)
	set_physics_process(false)
	set_process(_notifier.is_on_screen())


## Disconnects notifier signals and kills active [Tween] on tree exit.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_crack_tween)
	if not Engine.is_editor_hint() and is_instance_valid(_notifier):
		if _notifier.screen_entered.is_connected(_on_screen_entered):
			_notifier.screen_entered.disconnect(_on_screen_entered)
		if _notifier.screen_exited.is_connected(_on_screen_exited):
			_notifier.screen_exited.disconnect(_on_screen_exited)


## Updates oblique reflection camera when player camera is in front, within range, and moving.
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return
	if not is_instance_valid(_viewport):
		return
	var main_cam: Camera3D = _viewport.get_camera_3d()
	if not is_instance_valid(main_cam):
		return

	var quad_xform: Transform3D = _mirror_quad.global_transform
	var mirror_pos: Vector3 = quad_xform.origin
	var mirror_normal: Vector3 = quad_xform.basis.z.normalized()
	var cam_xform: Transform3D = main_cam.global_transform
	var cam_pos: Vector3 = cam_xform.origin

	var signed_dist: float = (cam_pos - mirror_pos).dot(mirror_normal)
	if signed_dist <= cull_near:
		return
	if cam_pos.distance_squared_to(mirror_pos) > _max_dist_sq:
		return
	if _last_cam_transform.is_equal_approx(cam_xform):
		return

	_last_cam_transform = cam_xform
	_update_reflection(main_cam, quad_xform, mirror_normal, signed_dist)


## Routes weapon and melee damage hits into localized fracture impacts.
func take_damage(
	amount: float, hit_position: Vector3 = Vector3.ZERO, _hit_dir: Vector3 = Vector3.ZERO
) -> void:
	var impact_pos: Vector3 = (
		global_position if hit_position.is_equal_approx(Vector3.ZERO) else hit_position
	)
	var delta_intensity: float = clampf(amount / 100.0, 0.15, 0.5)
	apply_impact(impact_pos, delta_intensity)


## Applies localized fracture impact at [param world_pos] without shattering embedded wire cage.
func apply_impact(world_pos: Vector3, intensity_delta: float = 0.35) -> void:
	if not is_instance_valid(_mirror_quad):
		return
	var local_hit: Vector3 = _mirror_quad.to_local(world_pos)
	var uv_x: float = clampf((local_hit.x / maxf(size.x, 0.001)) + 0.5, 0.05, 0.95)
	var uv_y: float = clampf(0.5 - (local_hit.y / maxf(size.y, 0.001)), 0.05, 0.95)
	_impact_uv = Vector2(uv_x, uv_y)
	var target_crack: float = clampf(_crack_intensity + intensity_delta, 0.0, 1.0)

	_mirror_quad.set_instance_shader_parameter(PARAM_IMPACT_UV, _impact_uv)
	_crack_tween = Utilities.reset_tween_ext(self, _crack_tween, Tween.TRANS_EXPO, Tween.EASE_OUT)
	if is_instance_valid(_crack_tween):
		_crack_tween.tween_method(_set_crack_level, _crack_intensity, target_crack, 0.18)
	_crack_intensity = target_crack
	_last_cam_transform = Transform3D.IDENTITY
	print("ArmoredMirror: impact at UV=", _impact_uv, " crack=", _crack_intensity)
	mirror_cracked.emit(_impact_uv, _crack_intensity)


## Resets glass fracture state back to intact armored glass.
func repair_mirror() -> void:
	Utilities.safe_kill_tween(_crack_tween)
	_crack_intensity = 0.0
	if is_instance_valid(_mirror_quad):
		_mirror_quad.set_instance_shader_parameter(PARAM_CRACK_INTENSITY, 0.0)
	_last_cam_transform = Transform3D.IDENTITY
	print("ArmoredMirror: repaired")


## Configures [SubViewport] shadow, AA, LOD, stripped environment, and render layer settings.
func _configure_viewport() -> void:
	if not is_instance_valid(_sub_viewport) or not is_instance_valid(_mirror_camera):
		return
	if not _sub_viewport.is_in_group(GROUP_IGNORE_SETTINGS):
		_sub_viewport.add_to_group(GROUP_IGNORE_SETTINGS)
	if not _mirror_camera.is_in_group(GROUP_IGNORE_SETTINGS):
		_mirror_camera.add_to_group(GROUP_IGNORE_SETTINGS)
	_sub_viewport.positional_shadow_atlas_size = 0
	_sub_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_sub_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_sub_viewport.use_taa = false
	_sub_viewport.use_debanding = false
	_sub_viewport.mesh_lod_threshold = 2.0
	_sub_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_mirror_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_mirror_camera.cull_mask = REFLECTION_CULL_MASK

	if _shared_empty_compositor == null:
		_shared_empty_compositor = Compositor.new()
		_shared_empty_compositor.compositor_effects = []
	_mirror_camera.compositor = _shared_empty_compositor

	if _shared_mirror_env == null:
		var env: Environment = Environment.new()
		env.volumetric_fog_enabled = false
		env.sdfgi_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.glow_enabled = false
		env.ssr_enabled = false
		env.fog_enabled = false
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.2, 0.22, 0.28, 1.0)
		env.ambient_light_energy = 1.0
		_shared_mirror_env = env
	_mirror_camera.environment = _shared_mirror_env


## Resizes quad mesh, notifier AABB, physics collider, and [SubViewport] resolution.
func _resize_resources() -> void:
	if not is_instance_valid(_mirror_quad) or not is_instance_valid(_sub_viewport):
		return
	var quad_mesh: QuadMesh = _mirror_quad.mesh as QuadMesh
	if is_instance_valid(quad_mesh):
		quad_mesh.size = size
	if is_instance_valid(_notifier):
		_notifier.aabb = AABB(
			Vector3(-size.x * 0.5, -size.y * 0.5, -0.05), Vector3(size.x, size.y, 0.1)
		)
	if is_instance_valid(_collision_shape):
		var box: BoxShape3D = _collision_shape.shape as BoxShape3D
		if is_instance_valid(box):
			box.size = Vector3(size.x, size.y, 0.06)

	var res_x: int = clampi(int(size.x * float(pixels_per_unit)), 16, max_viewport_size)
	var res_y: int = clampi(int(size.y * float(pixels_per_unit)), 16, max_viewport_size)
	var target_size: Vector2i = Vector2i(res_x, res_y)
	if _sub_viewport.size != target_size:
		_sub_viewport.size = target_size
	_last_cam_transform = Transform3D.IDENTITY


## Computes right-handed reflected pose and off-axis oblique frustum for [param main_cam].
func _update_reflection(
	main_cam: Camera3D, quad_xform: Transform3D, mirror_normal: Vector3, signed_dist: float
) -> void:
	var cam_pos: Vector3 = main_cam.global_position
	var proxy_pos: Vector3 = cam_pos - (2.0 * signed_dist * mirror_normal)

	# Right-handed basis (det = +1) coplanar with mirror quad; camera looks along +mirror_normal.
	var proxy_x: Vector3 = -quad_xform.basis.x.normalized()
	var proxy_y: Vector3 = quad_xform.basis.y.normalized()
	var proxy_z: Vector3 = -mirror_normal
	var proxy_basis: Basis = Basis(proxy_x, proxy_y, proxy_z)
	_mirror_camera.global_transform = Transform3D(proxy_basis, proxy_pos)

	var delta_to_quad: Vector3 = quad_xform.origin - proxy_pos
	var local_offset: Vector2 = Vector2(delta_to_quad.dot(proxy_x), delta_to_quad.dot(proxy_y))
	var near_plane: float = maxf(signed_dist + cull_near, 0.01)
	var scale_ratio: float = near_plane / maxf(signed_dist, 0.001)
	var frustum_width: float = size.x * scale_ratio
	var frustum_offset: Vector2 = local_offset * scale_ratio

	_mirror_camera.set_frustum(frustum_width, frustum_offset, near_plane, near_plane + cull_far)
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Updates reflection in editor viewport when `@tool` script is active.
func _update_editor_preview() -> void:
	var editor_vp: Viewport = get_viewport()
	if not is_instance_valid(editor_vp):
		return
	var editor_cam: Camera3D = editor_vp.get_camera_3d()
	if not is_instance_valid(editor_cam):
		return
	var quad_xform: Transform3D = _mirror_quad.global_transform
	var mirror_normal: Vector3 = quad_xform.basis.z.normalized()
	var signed_dist: float = (editor_cam.global_position - quad_xform.origin).dot(mirror_normal)
	if signed_dist > cull_near:
		_update_reflection(editor_cam, quad_xform, mirror_normal, signed_dist)


## Callback for [Tween] interpolation of per-instance shader fracture uniform.
func _set_crack_level(val: float) -> void:
	if is_instance_valid(_mirror_quad):
		_mirror_quad.set_instance_shader_parameter(PARAM_CRACK_INTENSITY, val)


## Enables [_process] and triggers immediate refresh when mirror enters screen frustum.
func _on_screen_entered() -> void:
	_last_cam_transform = Transform3D.IDENTITY
	set_process(true)


## Disables [_process] and halts [SubViewport] rendering when mirror exits screen frustum.
func _on_screen_exited() -> void:
	set_process(false)
	if is_instance_valid(_sub_viewport):
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
