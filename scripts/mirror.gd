@tool
extends Node3D

@export_group("Mirror Settings")
@export var size: Vector2 = Vector2(1.0, 1.0):
	set(v):
		size = v
		if is_node_ready():
			_update_mirror_size()

@export var pixels_per_unit: int = 200
@export var max_update_distance: float = 100.0
@export var max_viewport_size: Vector2i = Vector2i(2048, 2048)

@export_group("Culling Settings")
@export var cull_near: float = 0.05
@export var cull_far: float = 50.0
@export_flags_3d_render var cull_mask: int = 0xFFFFF

@export_group("Internal References")
@export var mirror_viewport: SubViewport
@export var mirror_camera: Camera3D
@export var mirror_quad: MeshInstance3D

var _main_cam: Camera3D
var _last_cam_transform: Transform3D
var _init_frames: int = 0
var _texture_assigned: bool = false

var _skip_frame: bool = false  #new code


func _ready() -> void:
	if (
		not is_instance_valid(mirror_quad)
		or not is_instance_valid(mirror_viewport)
		or not is_instance_valid(mirror_camera)
	):
		printerr("Mirror Error: Missing exported node references in base scene!")
		return

	# Scale Absorber: Converts accidental standard node scaling into proper viewport size
	if not scale.is_equal_approx(Vector3.ONE):
		size = Vector2(size.x * scale.x, size.y * scale.y)
		scale = Vector3.ONE

	var quad_mesh: QuadMesh = mirror_quad.mesh as QuadMesh
	if quad_mesh != null and not quad_mesh.resource_local_to_scene:
		mirror_quad.mesh = quad_mesh.duplicate()
	elif quad_mesh == null:
		printerr("Mirror Error: Mesh is not a QuadMesh!")
		return

	_setup_mirror()


func _setup_mirror() -> void:
	if is_instance_valid(mirror_camera):
		mirror_camera.cull_mask = cull_mask

	if is_instance_valid(mirror_viewport):
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_update_mirror_size()

	if is_instance_valid(mirror_quad):
		var mat: Material = mirror_quad.get_active_material(0)
		if mat != null:
			var local_mat: Material = mat.duplicate()
			mirror_quad.set_surface_override_material(0, local_mat)

	_main_cam = _find_camera()
	if is_instance_valid(_main_cam):
		_sync_camera_settings()


func _sync_camera_settings() -> void:
	if not is_instance_valid(_main_cam) or not is_instance_valid(mirror_camera):
		return
	_last_cam_transform = _main_cam.global_transform
	mirror_camera.fov = _main_cam.fov


func _assign_texture() -> void:
	if not is_instance_valid(mirror_viewport) or not is_instance_valid(mirror_quad):
		return

	var mat: Material = mirror_quad.get_active_material(0)
	if mat == null:
		return

	var tex: ViewportTexture = mirror_viewport.get_texture()

	if mat is ShaderMaterial:
		mat.set_shader_parameter(&"tex", tex)
	elif mat is StandardMaterial3D:
		mat.albedo_texture = tex


func _find_camera() -> Camera3D:
	if Engine.is_editor_hint():
		# Call the singleton dynamically to prevent export build parse errors
		var editor_interface: Object = Engine.get_singleton(&"EditorInterface")
		if is_instance_valid(editor_interface):
			var ed_vp: SubViewport = editor_interface.get_editor_viewport_3d()
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


func _update_mirror_size() -> void:
	if not is_instance_valid(mirror_quad) or not is_instance_valid(mirror_viewport):
		return

	var q_mesh: QuadMesh = mirror_quad.mesh as QuadMesh
	if q_mesh != null:
		q_mesh.size = size

	var target_x: int = int(size.x * float(pixels_per_unit))
	var target_y: int = int(size.y * float(pixels_per_unit))

	target_x = mini(target_x, max_viewport_size.x)
	target_y = mini(target_y, max_viewport_size.y)

	mirror_viewport.size = Vector2i(target_x, target_y)


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


func _update_cam() -> void:
	if (
		not is_instance_valid(_main_cam)
		or not is_instance_valid(mirror_camera)
		or not is_instance_valid(mirror_quad)
	):
		return

	var mirror_norm: Vector3 = mirror_quad.global_basis.z
	var mirror_trans: Transform3D = _get_mirror_transform(mirror_norm, global_position)
	mirror_camera.global_transform = mirror_trans * _main_cam.global_transform

	var target: Vector3 = (mirror_camera.global_position / 2.0) + (_last_cam_transform.origin / 2.0)
	mirror_camera.global_transform = mirror_camera.global_transform.looking_at(
		target, mirror_quad.global_basis.y
	)

	var offset: Vector3 = mirror_quad.global_position - mirror_camera.global_position
	var near: float = abs(offset.dot(mirror_norm)) + cull_near
	var far: float = offset.length() + cull_far
	var inv_basis: Basis = mirror_camera.global_basis.inverse()
	var offset_local: Vector3 = inv_basis * offset

	var frustum_offset: Vector2 = Vector2(offset_local.x, offset_local.y)
	mirror_camera.set_frustum(size.x, frustum_offset, near, far)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return

	if not is_instance_valid(_main_cam):
		_main_cam = _find_camera()
		if not is_instance_valid(_main_cam):
			return
		# Sync the FOV and initial transform the moment the game camera initializes
		_sync_camera_settings()

	var cur_trans: Transform3D = _main_cam.global_transform

	# Shield Phase: Force rendering for the first 5 frames to guarantee buffer allocation
	if _init_frames < 5:
		if is_instance_valid(mirror_viewport):
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_init_frames += 1
	else:
		# Lock the generated texture proxy into the material only AFTER buffers exist
		if not _texture_assigned:
			_assign_texture()
			_texture_assigned = true

		# Optimization Phase: Resume standard culling and transform checks
		if _last_cam_transform.is_equal_approx(cur_trans):
			return

		if is_instance_valid(mirror_viewport):
			var diff: Vector3 = global_position - cur_trans.origin
			var dist_sq: float = diff.length_squared()
			var max_dist_sq: float = max_update_distance * max_update_distance

			if dist_sq > max_dist_sq:
				mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			else:
				# Interleave updates: Only render the mirror on alternating frames
				_skip_frame = not _skip_frame
				if _skip_frame:
					mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				else:
					# Keep disabled on the off-frame to save compute budget
					mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_last_cam_transform = cur_trans
	_update_cam()

	#OLD BACKUP
#func _process(_delta: float) -> void:
#if not is_visible_in_tree():
#return
#
#if not is_instance_valid(_main_cam):
#_main_cam = _find_camera()
#if not is_instance_valid(_main_cam):
#return
## Sync the FOV and initial transform the moment the game camera initializes
#_sync_camera_settings()
#
#var cur_trans: Transform3D = _main_cam.global_transform
#
## Shield Phase: Force rendering for the first 5 frames to guarantee buffer allocation
#if _init_frames < 5:
#if is_instance_valid(mirror_viewport):
#mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
#_init_frames += 1
#else:
## Lock the generated texture proxy into the material only AFTER buffers exist
#if not _texture_assigned:
#_assign_texture()
#_texture_assigned = true
#
## Optimization Phase: Resume standard culling and transform checks
#if _last_cam_transform.is_equal_approx(cur_trans):
#return
#
#if is_instance_valid(mirror_viewport):
#var diff: Vector3 = global_position - cur_trans.origin
#if diff.length_squared() > (max_update_distance * max_update_distance):
#mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
#else:
#mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
#
#_last_cam_transform = cur_trans
#_update_cam()
