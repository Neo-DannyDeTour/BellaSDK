@tool
## Coordinator for clean planar mirror reflection, oblique frustum projection,
## and visibility/distance gating.
class_name Mirror
extends Node3D

## Group tag excluding mirror [SubViewport] from global post-processing overrides.
const GROUP_IGNORE_SETTINGS: StringName = &"ignore_global_video_settings"

## Render layers visible in reflection: Layer 1 (Env) + Layer 2 (Player) + Layer 3 (Interactive).
const REFLECTION_CULL_MASK: int = (
	CollisionLayers.RENDER_MASK_ENVIRONMENT
	| CollisionLayers.RENDER_MASK_PLAYER
	| CollisionLayers.RENDER_MASK_INTERACTIVE
)

## Shared empty compositor resource bypassing global compute passes.
static var _shared_empty_compositor: Compositor = null

## Dimensions of the mirror surface in world units.
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

## Cached root [Viewport] providing the active scene camera.
var _viewport: Viewport = null

## Quad mesh instance displaying the planar reflection shader.
@onready var _mirror_quad: MeshInstance3D = $Quad as MeshInstance3D

## Reflection [SubViewport] rendering the off-axis camera view.
@onready var _sub_viewport: SubViewport = $MirrorSubViewport as SubViewport

## Off-axis frustum [Camera3D] inside the reflection [SubViewport].
@onready var _mirror_camera: Camera3D = $MirrorSubViewport/Camera3D as Camera3D

## Screen visibility notifier gating [_process] and [SubViewport] updates.
@onready
var _notifier: VisibleOnScreenNotifier3D = $MirrorVisibilityNotifier as VisibleOnScreenNotifier3D

## Box collider shape on the static mirror body.
@onready var _collision_shape: CollisionShape3D = $MirrorBody/CollisionShape3D as CollisionShape3D


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

	if Engine.is_editor_hint():
		set_physics_process(false)
		set_process(true)
		return

	Utilities.safe_connect(_notifier.screen_entered, _on_screen_entered)
	Utilities.safe_connect(_notifier.screen_exited, _on_screen_exited)
	set_physics_process(false)
	set_process(_notifier.is_on_screen())


## Disconnects notifier signals on tree exit.
func _exit_tree() -> void:
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


## Configures [SubViewport] shadow, AA, LOD, empty compositor, and render layer settings.
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
	_mirror_camera.environment = null


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


## Enables [_process] and triggers immediate refresh when mirror enters screen frustum.
func _on_screen_entered() -> void:
	_last_cam_transform = Transform3D.IDENTITY
	set_process(true)


## Disables [_process] and halts [SubViewport] rendering when mirror exits screen frustum.
func _on_screen_exited() -> void:
	set_process(false)
	if is_instance_valid(_sub_viewport):
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
