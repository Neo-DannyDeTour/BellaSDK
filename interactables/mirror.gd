@tool
## A flat reflective surface that generates real-time reflections using a dedicated [SubViewport].
##
## Manages its own rendering optimizations by limiting updates based on distance, interleaving
## camera frames, and aligning custom frustum culling.
class_name Mirror
extends Node3D

@export_group("Mirror Settings")
## The 2D dimensions of the mirror's physical mesh surface.
@export var size: Vector2 = Vector2(1.0, 1.0):
	set(v):
		size = v
		if is_inside_tree() and Engine.is_editor_hint():
			_update_mirror_size()

## Used to dynamically calculate viewport resolution based on the [member size].
@export var pixels_per_unit: int = 50
## The distance threshold beyond which the mirror pauses rendering to save GPU budget.
@export var max_update_distance: float = 15.0
## Hard cap for the generated viewport resolution to prevent VRAM allocation spikes.
@export var max_viewport_size: Vector2i = Vector2i(512, 512)

@export_group("Culling Settings")
## Minimum near-plane culling distance applied to the proxy camera.
@export var cull_near: float = 0.05
## Maximum far-plane culling distance applied to the proxy camera.
@export var cull_far: float = 20.0
## Determines which visual layers are rendered within the reflection.
@export_flags_3d_render var cull_mask: int = 0xFFFFF

@export_group("Internal References")
## Viewport responsible for storing the reflection texture data.
@export var mirror_viewport: SubViewport
## Proxy camera moved and rotated to mimic the player's perspective reversed.
@export var mirror_camera: Camera3D
## The [MeshInstance3D] mapping the generated texture onto the world geometry.
@export var mirror_quad: MeshInstance3D

## The active player or editor camera driving the viewpoint.
var _main_cam: Camera3D
## Caches the previous camera location to detect movement.
var _last_cam_transform: Transform3D
## Frame counter ensuring initial buffers generate fully before mapping the texture.
var _init_frames: int = 0
## Indicates if the viewport texture proxy has been correctly assigned to the material.
var _texture_assigned: bool = false
## Toggles boolean state to perform interlaced frame-skipping optimizations.
var _skip_frame: bool = false


## Converts accidental node scaling into structural dimensions and clones materials.
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
	if is_instance_valid(quad_mesh) and not quad_mesh.resource_local_to_scene:
		mirror_quad.mesh = quad_mesh.duplicate()
	elif not is_instance_valid(quad_mesh):
		printerr("Mirror Error: Mesh is not a QuadMesh!")
		return

	_setup_mirror()


## Sets up culling masks, viewport modes, and duplicate materials required for the effect.
func _setup_mirror() -> void:
	print("Mirror system: Initializing viewport and assigning target camera.")

	if is_instance_valid(mirror_camera):
		mirror_camera.cull_mask = cull_mask

	if is_instance_valid(mirror_viewport):
		mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_update_mirror_size()

	if is_instance_valid(mirror_quad):
		var mat: Material = mirror_quad.get_active_material(0)
		if is_instance_valid(mat):
			var local_mat: Material = mat.duplicate()
			mirror_quad.set_surface_override_material(0, local_mat)

	_main_cam = _find_camera()
	if is_instance_valid(_main_cam):
		_sync_camera_settings()


## Copies fundamental optical settings (like FOV) from the main camera to the proxy.
func _sync_camera_settings() -> void:
	if not is_instance_valid(_main_cam) or not is_instance_valid(mirror_camera):
		return
	_last_cam_transform = _main_cam.global_transform
	mirror_camera.fov = _main_cam.fov


## Injects the viewport render target texture directly into the shader or standard material.
func _assign_texture() -> void:
	if not is_instance_valid(mirror_viewport) or not is_instance_valid(mirror_quad):
		return

	var mat: Material = mirror_quad.get_active_material(0)
	if not is_instance_valid(mat):
		return

	var tex: ViewportTexture = mirror_viewport.get_texture()

	if mat is ShaderMaterial:
		mat.set_shader_parameter(&"tex", tex)
	elif mat is StandardMaterial3D:
		mat.albedo_texture = tex


## Safely detects the active viewing camera for both editor previews and live runtime execution.
## Returns the resolved [Camera3D] node or null.
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


## Dynamically adjusts the allocated viewport resolution buffers to match mesh sizing.
func _update_mirror_size() -> void:
	if not is_instance_valid(mirror_quad) or not is_instance_valid(mirror_viewport):
		return

	var q_mesh: QuadMesh = mirror_quad.mesh as QuadMesh
	if is_instance_valid(q_mesh):
		q_mesh.size = size

	var target_x: int = int(size.x * float(pixels_per_unit))
	var target_y: int = int(size.y * float(pixels_per_unit))

	target_x = mini(target_x, max_viewport_size.x)
	target_y = mini(target_y, max_viewport_size.y)

	mirror_viewport.size = Vector2i(target_x, target_y)


## Calculates the inverted reflection matrix across the mirror's specific plane.
## [param normal]: The normal vector of the mirror surface.
## [param pos]: The global coordinate of the mirror node.
## Returns the mirrored coordinate transform.
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


## Repositions the proxy camera, constructs the reflected view frustum, and sets culling ranges.
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

	# Fix: Prevent looking_at() math explosion if origin and target are identical
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


## Manages the rendering loop, including interlaced frames and suspending logic by distance.
## [param _delta]: Frame delta time.
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
		_last_cam_transform = cur_trans
		_update_cam()
		return

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
			return  # OPTIMIZATION: Skip camera math entirely when too far away

		# Interleave updates: Only render the mirror on alternating frames
		_skip_frame = not _skip_frame
		if _skip_frame:
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		else:
			# Keep disabled on the off-frame to save compute budget
			mirror_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return  # OPTIMIZATION: Skip camera math entirely on off-frames

	_last_cam_transform = cur_trans
	_update_cam()
