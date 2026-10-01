@tool
## Planar reflection surface projecting inverted camera views onto quads.
class_name Mirror
extends Node3D

## Shared stripped environment resource eliminating per-instance heap allocations.
static var _shared_mirror_env: Environment = null

## Shared empty compositor resource bypassing global compute passes.
static var _shared_empty_compositor: Compositor = null

@export_group("Mirror Settings")
## Dimensions of the mirror surface in world units.
@export var size: Vector2 = Vector2(1.0, 1.0):
	set(v):
		size = v
		if is_inside_tree() and Engine.is_editor_hint():
			_update_mirror_size()

## Viewport pixel resolution multiplier per unit.
@export var pixels_per_unit: int = 50

## Maximum distance in meters to update reflection.
@export var max_update_distance: float = 15.0

## Maximum resolution clamp for the viewport buffer.
@export var max_viewport_size: Vector2i = Vector2i(512, 512)

@export_group("Culling Settings")
## Near-plane clipping distance for proxy camera.
@export var cull_near: float = 0.05

## Far-plane culling distance for proxy camera.
@export var cull_far: float = 20.0

## Render cull mask for objects visible in mirror.
@export_flags_3d_render var cull_mask: int = CollisionLayers.RENDER_MASK_ALL

@export_group("Internal References")
## SubViewport rendering reflection camera texture.
@export var mirror_viewport: SubViewport

## Perspective camera capturing mirrored world view.
@export var mirror_camera: Camera3D

## Quad mesh instance displaying reflection material.
@export var mirror_quad: MeshInstance3D

## Active scene camera driving mirror view matrix.
var _main_cam: Camera3D = null

## Cached camera transform detecting static frames.
var _last_cam_transform: Transform3D = Transform3D()

## Frame counter ensuring initial buffer draws.
var _init_frames: int = 0

## Flag indicating viewport texture assignment.
var _texture_assigned: bool = false

## Frame-skipping flag to cut update frequency.
var _skip_frame: bool = false

## Original camera environment cached for restore.
var _original_camera_environment: Environment = null


## Validates exported nodes and initializes mirror resources.
func _ready() -> void:
	print("Mirror: Initializing node instance -> ", name)
	if not is_instance_valid(mirror_quad) or not is_instance_valid(mirror_viewport):
		printerr("Mirror Error: Missing exported node references on ", name)
		return
	if not is_instance_valid(mirror_camera):
		printerr("Mirror Error: Missing exported mirror_camera on ", name)
		return

	if not scale.is_equal_approx(Vector3.ONE):
		size = Vector2(size.x * scale.x, size.y * scale.y)
		scale = Vector3.ONE

	var quad_mesh: QuadMesh = mirror_quad.mesh as QuadMesh
	if is_instance_valid(quad_mesh) and not quad_mesh.resource_local_to_scene:
		mirror_quad.mesh = quad_mesh.duplicate()
		mirror_quad.mesh.resource_local_to_scene = true
	elif not is_instance_valid(quad_mesh):
		printerr("Mirror Error: Mesh on mirror_quad is not a QuadMesh!")
		return

	_setup_mirror()


## Restores original camera environment when mirror exits scene tree.
func _exit_tree() -> void:
	print("Mirror: _exit_tree() restoring camera environment on: ", name)
	if is_instance_valid(mirror_camera) and _original_camera_environment != null:
		mirror_camera.environment = _original_camera_environment


## Updates mirror camera transforms and evaluates throttled render frames.
func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return

	if not is_instance_valid(_main_cam):
		_main_cam = _find_camera()
		if not is_instance_valid(_main_cam):
			return
		_sync_camera_settings()

	var cur_trans: Transform3D = _main_cam.global_transform

	if _init_frames < 2:
		if is_instance_valid(mirror_viewport):
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_init_frames += 1
		_last_cam_transform = cur_trans
		_update_cam()
		return

	if not _texture_assigned:
		_assign_texture()
		_texture_assigned = true

	var mirror_norm: Vector3 = mirror_quad.global_basis.z
	var to_cam: Vector3 = cur_trans.origin - mirror_quad.global_position
	var is_in_front: bool = mirror_norm.dot(to_cam) > 0.0

	var diff: Vector3 = global_position - cur_trans.origin
	var dist_sq: float = diff.length_squared()
	var in_range: bool = dist_sq <= (max_update_distance * max_update_distance)

	if not is_in_front or not in_range:
		if is_instance_valid(mirror_viewport):
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	if _last_cam_transform.is_equal_approx(cur_trans):
		if is_instance_valid(mirror_viewport):
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	if is_instance_valid(mirror_viewport):
		_skip_frame = not _skip_frame
		if _skip_frame:
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_last_cam_transform = cur_trans
			_update_cam()
		else:
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Configures proxy camera, pipeline limits, and surface materials.
func _setup_mirror() -> void:
	print("Mirror: Configuring camera, pipeline, and material for: ", name)
	if is_instance_valid(mirror_camera):
		mirror_camera.current = true
		mirror_camera.cull_mask = cull_mask
		_isolate_mirror_camera_compositor()
		_configure_mirror_environment()

	_configure_viewport_pipeline()
	_update_mirror_size()

	if is_instance_valid(mirror_quad):
		var mat: Material = mirror_quad.get_active_material(0)
		if is_instance_valid(mat) and not mat.resource_local_to_scene:
			var mat_key: StringName = StringName("mirror_mat_" + str(get_instance_id()))
			var cached_mat: Material = MaterialCache.get_variant(
				mat_key,
				func() -> Material:
					var m: Material = mat.duplicate()
					m.resource_local_to_scene = true
					return m
			)
			mirror_quad.set_surface_override_material(0, cached_mat)

	_main_cam = _find_camera()
	if is_instance_valid(_main_cam):
		_sync_camera_settings()


## Strips shadow maps and anti-aliasing passes from the reflection [SubViewport].
func _configure_viewport_pipeline() -> void:
	print("Mirror: Stripping heavy rendering passes from SubViewport on: ", name)
	if not is_instance_valid(mirror_viewport):
		return

	mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mirror_viewport.positional_shadow_atlas_size = 0
	mirror_viewport.msaa_3d = Viewport.MSAA_DISABLED
	mirror_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	mirror_viewport.use_taa = false
	mirror_viewport.use_debanding = false
	mirror_viewport.mesh_lod_threshold = 2.0
	mirror_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR


## Synchronizes optical properties such as FOV from the active scene camera.
func _sync_camera_settings() -> void:
	print("Mirror: Synchronizing camera FOV from active camera.")
	if not is_instance_valid(_main_cam) or not is_instance_valid(mirror_camera):
		return
	_last_cam_transform = _main_cam.global_transform
	mirror_camera.fov = _main_cam.fov


## Assigns generated viewport texture to quad mesh material parameters.
func _assign_texture() -> void:
	print("Mirror: Assigning ViewportTexture to quad material.")
	if not is_instance_valid(mirror_viewport) or not is_instance_valid(mirror_quad):
		return

	var mat: Material = mirror_quad.get_active_material(0)
	if not is_instance_valid(mat):
		return

	var tex: ViewportTexture = mirror_viewport.get_texture()
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter(&"tex", tex)
	elif mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_texture = tex


## Resolves active 3D camera from editor interface or scene tree.
func _find_camera() -> Camera3D:
	print("Mirror: Searching scene tree for active Camera3D.")
	if Engine.is_editor_hint():
		var ed_interface: Object = Engine.get_singleton(&"EditorInterface")
		if is_instance_valid(ed_interface):
			var ed_vp: SubViewport = ed_interface.get_editor_viewport_3d()
			if is_instance_valid(ed_vp):
				return ed_vp.get_camera_3d()
		return null

	var tree: SceneTree = get_tree()
	if is_instance_valid(tree) and is_instance_valid(tree.root):
		var vp: Viewport = tree.root.get_viewport()
		if is_instance_valid(vp):
			var cam: Camera3D = vp.get_camera_3d()
			if is_instance_valid(cam):
				return cam

	var local_vp: Viewport = get_viewport()
	if is_instance_valid(local_vp):
		return local_vp.get_camera_3d()

	return null


## Recalculates viewport pixel resolution buffers according to quad dimensions.
func _update_mirror_size() -> void:
	print("Mirror: Updating buffer resolutions for size: ", size)
	if not is_instance_valid(mirror_quad) or not is_instance_valid(mirror_viewport):
		return

	var q_mesh: QuadMesh = mirror_quad.mesh as QuadMesh
	if is_instance_valid(q_mesh):
		q_mesh.size = size

	var target_x: int = int(size.x * float(pixels_per_unit))
	var target_y: int = int(size.y * float(pixels_per_unit))

	target_x = clampi(target_x, 16, max_viewport_size.x)
	target_y = clampi(target_y, 16, max_viewport_size.y)

	mirror_viewport.size = Vector2i(target_x, target_y)


## Generates reflection matrix across the mirror surface plane.
func _get_mirror_transform(normal: Vector3, pos: Vector3) -> Transform3D:
	var d: float = normal.dot(pos)
	var px: float = -2.0 * normal.x
	var py: float = -2.0 * normal.y
	var pz: float = -2.0 * normal.z

	var m: Basis = Basis(
		Vector3(1.0 + px * normal.x, px * normal.y, px * normal.z),
		Vector3(py * normal.x, 1.0 + py * normal.y, py * normal.z),
		Vector3(pz * normal.x, pz * normal.y, 1.0 + pz * normal.z)
	)
	return Transform3D(m, normal * (2.0 * d))


## Repositions proxy camera and recalculates asymmetrical oblique frustum planes.
func _update_cam() -> void:
	if not is_instance_valid(_main_cam) or not is_instance_valid(mirror_camera):
		return
	if not is_instance_valid(mirror_quad):
		return

	var mirror_norm: Vector3 = mirror_quad.global_basis.z
	var mirror_trans: Transform3D = _get_mirror_transform(mirror_norm, global_position)
	mirror_camera.global_transform = mirror_trans * _main_cam.global_transform

	var target: Vector3 = MathUtils.get_midpoint(
		mirror_camera.global_position, _last_cam_transform.origin
	)

	if not mirror_camera.global_position.is_equal_approx(target):
		mirror_camera.global_transform = mirror_camera.global_transform.looking_at(
			target, mirror_quad.global_basis.y
		)

	var offset: Vector3 = mirror_quad.global_position - mirror_camera.global_position
	var near: float = absf(offset.dot(mirror_norm)) + cull_near
	var far: float = offset.length() + cull_far
	var inv_basis: Basis = mirror_camera.global_basis.inverse()
	var offset_local: Vector3 = inv_basis * offset

	var frustum_offset: Vector2 = Vector2(offset_local.x, offset_local.y)
	mirror_camera.set_frustum(size.x, frustum_offset, near, far)


## Assigns shared empty compositor to bypass global compute passes.
func _isolate_mirror_camera_compositor() -> void:
	print("Mirror: Isolating compositor for: ", mirror_camera.name)
	if _shared_empty_compositor == null:
		_shared_empty_compositor = Compositor.new()
		_shared_empty_compositor.compositor_effects = []
	mirror_camera.compositor = _shared_empty_compositor


## Configures stripped environment without expensive screen-space passes.
func _configure_mirror_environment() -> void:
	print("Mirror: Configuring stripped environment on: ", mirror_camera.name)
	if _original_camera_environment == null and is_instance_valid(mirror_camera.environment):
		_original_camera_environment = mirror_camera.environment

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

	mirror_camera.environment = _shared_mirror_env
