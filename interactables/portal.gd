## Handles 3D portal perspective projection and seamless body teleportation.
class_name Portal
extends Area3D

## The destination portal this [Portal] connects to.
@export var linked_portal: Portal

## Maximum distance from player camera to update portal viewport.
@export var max_render_distance: float = 30.0

## The active player [Camera3D] tracked for calculating perspective offsets.
var player_camera: Camera3D

## The [SubViewport] rendering scene from portal perspective.
@onready var sub_viewport: SubViewport = $PortalSubViewport

## The [Camera3D] capturing view for portal.
@onready var portal_camera: Camera3D = $PortalSubViewport/PortalCamera

## The [MeshInstance3D] displaying portal shader.
@onready var portal_mesh: MeshInstance3D = $PortalMesh

## Dictionary storing tracked bodies and their last known side.
var _tracked_bodies: Dictionary = {}

## On-screen visibility notifier used to cull off-screen portal render passes.
var _screen_notifier: VisibleOnScreenNotifier3D = null

## Tracks if portal mesh is currently inside player camera frustum.
var _is_on_screen: bool = true

## Cached empty [Compositor] applied to isolate from compute effects.
var _empty_compositor: Compositor = null

## Cached original environment applied to portal camera prior to overrides.
var _original_camera_environment: Environment = null

## Cached squared maximum render distance avoiding runtime sqrt calls.
var _max_render_distance_sq: float = 900.0


## Restores original camera environment on exit tree.
func _exit_tree() -> void:
	print("Portal: Restoring camera environment on exit: ", name)
	if is_instance_valid(portal_camera) and is_instance_valid(_original_camera_environment):
		portal_camera.environment = _original_camera_environment


## Initializes portal listeners, caches materials, and sets up culling.
func _ready() -> void:
	print("Portal: Initializing: ", name)
	_max_render_distance_sq = max_render_distance * max_render_distance

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	portal_camera.current = true
	_configure_sub_viewport()
	_isolate_portal_camera_compositor()
	_configure_portal_environment()
	_configure_portal_camera_cull_mask()

	Events.player_camera_registered.connect(_on_player_camera_registered)
	_setup_screen_notifier()

	var mat: Material = portal_mesh.get_active_material(0)
	if mat is ShaderMaterial:
		var variant_key: String = "portal_%d" % get_instance_id()
		var cached_mat: Material = MaterialCache.get_variant(mat, variant_key)
		portal_mesh.set_surface_override_material(0, cached_mat)
		_update_mesh_texture.call_deferred()

	_on_viewport_size_changed()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	if not is_instance_valid(player_camera):
		_find_and_assign_player_camera()


## Strips shadow passes, AA, and LOD overhead from [member sub_viewport].
func _configure_sub_viewport() -> void:
	print("Portal: Configuring SubViewport graphics limits for: ", name)
	if not is_instance_valid(sub_viewport):
		return
	sub_viewport.positional_shadow_atlas_size = 0
	sub_viewport.msaa_3d = Viewport.MSAA_DISABLED
	sub_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	sub_viewport.use_taa = false
	sub_viewport.use_debanding = false
	sub_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	sub_viewport.mesh_lod_threshold = 2.0


## Overrides [member portal_camera] compositor to disable compute shaders.
func _isolate_portal_camera_compositor() -> void:
	print("Portal: Isolating compositor for: ", portal_camera.name)
	_empty_compositor = Compositor.new()
	_empty_compositor.compositor_effects = []
	portal_camera.compositor = _empty_compositor


## Configures isolated environment disabling heavy fog and GI passes.
func _configure_portal_environment() -> void:
	print("Portal: Configuring isolated environment for: ", portal_camera.name)
	if is_instance_valid(portal_camera) and _original_camera_environment == null:
		_original_camera_environment = portal_camera.environment

	var env: Environment = Environment.new()
	env.sdfgi_enabled = false
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.28, 1.0)
	env.ambient_light_energy = 1.0
	portal_camera.environment = env


## Culls portal and volumetric layers from [member portal_camera] mask.
func _configure_portal_camera_cull_mask() -> void:
	print("Portal: Configuring camera cull mask for: ", portal_camera.name)
	if not is_instance_valid(portal_camera):
		return
	# Layer 4 (Portals = 8) and Layer 10 (Volumetrics = 512): ~520
	portal_camera.cull_mask = portal_camera.cull_mask & ~520


## Sets up a [VisibleOnScreenNotifier3D] to cull updates when out of view.
func _setup_screen_notifier() -> void:
	print("Portal: Setting up screen visibility notifier for: ", name)
	_screen_notifier = VisibleOnScreenNotifier3D.new()
	add_child(_screen_notifier)

	if portal_mesh and portal_mesh.mesh:
		_screen_notifier.aabb = portal_mesh.mesh.get_aabb()
	else:
		_screen_notifier.aabb = AABB(Vector3(-1.0, -1.0, -0.1), Vector3(2.0, 2.0, 0.2))

	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)


## Assigns linked portal's viewport texture to mesh shader.
func _update_mesh_texture() -> void:
	print("Portal: Updating mesh texture binding for: ", name)
	if not is_instance_valid(linked_portal) or not is_instance_valid(portal_mesh):
		return

	var target_vp: SubViewport = linked_portal.sub_viewport
	if not is_instance_valid(target_vp):
		return

	var mat: Material = portal_mesh.get_surface_override_material(0)
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat as ShaderMaterial
		var target_texture: ViewportTexture = target_vp.get_texture()
		shader_mat.set_shader_parameter("viewport_texture", target_texture)


## Automatically connects to primary player camera if unassigned.
func _find_and_assign_player_camera() -> void:
	print("Portal: Searching for active player camera.")
	var viewport_cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(viewport_cam) and viewport_cam != portal_camera:
		player_camera = viewport_cam
		return

	var player_node: Node = NodeQuery.get_single_node_in_group(get_tree(), &"player")
	if is_instance_valid(player_node):
		var found_cam: Camera3D = (
			NodeQuery.find_first_child_of_type(player_node, Camera3D) as Camera3D
		)
		if is_instance_valid(found_cam):
			player_camera = found_cam


## Callback receiving registered player camera from global event bus.
func _on_player_camera_registered(cam: Camera3D) -> void:
	print("Portal: Received player camera registration: ", cam.name)
	player_camera = cam


## Resizes [SubViewport] texture when window resolution changes.
func _on_viewport_size_changed() -> void:
	print("Portal: Scaling SubViewport size.")
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var half_size: Vector2i = Vector2i(vp_size * 0.5)
	sub_viewport.size = half_size.max(Vector2i(256, 256))


## Synchronizes linked portal camera with player perspective.
func _process(_delta: float) -> void:
	if not is_instance_valid(player_camera):
		var active_cam: Camera3D = get_viewport().get_camera_3d()
		if is_instance_valid(active_cam) and active_cam != portal_camera:
			player_camera = active_cam
		else:
			return

	if not _is_on_screen or not is_instance_valid(linked_portal):
		if is_instance_valid(linked_portal):
			linked_portal._set_viewport_mode(SubViewport.UPDATE_DISABLED)
		return

	var to_player: Vector3 = player_camera.global_position - global_position
	var is_in_front: bool = global_transform.basis.z.dot(to_player) > 0.0
	var dist_sq: float = global_position.distance_squared_to(player_camera.global_position)
	var in_range: bool = dist_sq <= _max_render_distance_sq

	if not is_in_front or not in_range:
		linked_portal._set_viewport_mode(SubViewport.UPDATE_DISABLED)
		return

	linked_portal._set_viewport_mode(SubViewport.UPDATE_WHEN_VISIBLE)

	var rel_trans: Transform3D = global_transform.affine_inverse() * player_camera.global_transform
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3.ZERO)

	var target_cam: Camera3D = linked_portal.portal_camera
	target_cam.global_transform = (linked_portal.global_transform * half_turn * rel_trans)
	target_cam.fov = player_camera.fov
	target_cam.near = player_camera.near
	target_cam.far = player_camera.far
	target_cam.keep_aspect = player_camera.keep_aspect
	target_cam.projection = player_camera.projection
	target_cam.h_offset = 0.0005


## Checks crossed bodies and performs portal teleportation.
func _physics_process(_delta: float) -> void:
	var keys: Array = _tracked_bodies.keys()
	for body: Node3D in keys:
		if not is_instance_valid(body):
			_tracked_bodies.erase(body)
			continue

		var current_side: float = _get_side(body.global_position)
		var previous_side: float = _tracked_bodies[body]

		if signf(current_side) != signf(previous_side):
			print("Portal: Teleporting body: ", body.name)
			_teleport_body(body)
			_tracked_bodies.erase(body)
		else:
			_tracked_bodies[body] = current_side


## Calculates which side of portal plane a position resides on.
func _get_side(pos: Vector3) -> float:
	var dir_to_body: Vector3 = pos - global_position
	return global_transform.basis.z.dot(dir_to_body)


## Teleports a body through to linked portal with inverted momentum.
func _teleport_body(body: Node3D) -> void:
	if not is_instance_valid(linked_portal):
		return

	var relative_trans: Transform3D = global_transform.affine_inverse() * body.global_transform
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3.ZERO)
	body.global_transform = (linked_portal.global_transform * half_turn * relative_trans)

	if "velocity" in body:
		var relative_velocity: Vector3 = (
			global_transform.basis.inverse() * (body.get("velocity") as Vector3)
		)
		var final_velocity: Vector3 = (
			(linked_portal.global_transform.basis * half_turn.basis) * relative_velocity
		)
		body.set("velocity", final_velocity)


## Registers entering physics bodies for plane crossing detection.
func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D or body is RigidBody3D:
		print("Portal: Tracking body entered zone: ", body.name)
		_tracked_bodies[body] = _get_side(body.global_position)


## Deregisters exiting physics bodies from tracking.
func _on_body_exited(body: Node3D) -> void:
	if _tracked_bodies.has(body):
		print("Portal: Body exited zone: ", body.name)
		_tracked_bodies.erase(body)


## Enables processing when portal bounds enter camera frustum.
func _on_screen_entered() -> void:
	print("Portal: Entered camera frustum: ", name)
	_is_on_screen = true
	_update_mesh_texture()


## Disables viewport updates when portal bounds leave camera frustum.
func _on_screen_exited() -> void:
	print("Portal: Exited camera frustum: ", name)
	_is_on_screen = false
	if is_instance_valid(linked_portal):
		linked_portal._set_viewport_mode(SubViewport.UPDATE_DISABLED)


## Helper method to safely toggle [member SubViewport.render_target_update_mode].
func _set_viewport_mode(mode: SubViewport.UpdateMode) -> void:
	if sub_viewport.render_target_update_mode != mode:
		print("Portal: Setting update mode: ", mode)
		sub_viewport.render_target_update_mode = mode
