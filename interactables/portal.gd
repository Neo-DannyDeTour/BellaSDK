## Handles 3D portal perspective projection, dynamic viewport culling, and seamless teleportation.
class_name Portal
extends Area3D

## The destination portal this portal connects to.
## Used as the anchor point to calculate relative positions for rendering and teleportation.
@export var linked_portal: Portal

## Maximum distance from the player camera to update the portal viewport.
@export var max_render_distance: float = 30.0

## The active player camera tracked for calculating perspective offsets.
var player_camera: Camera3D

## The viewport that renders the scene from this portal's perspective.
## This acts as the texture source for the linked portal mesh shader.
@onready var sub_viewport: SubViewport = $SubViewport

## The camera capturing the view for the portal.
## Positioned relative to this portal when looked through from the linked portal.
@onready var portal_camera: Camera3D = $SubViewport/PortalCamera

## The mesh instance displaying the portal shader.
## Used to dynamically inject the viewport texture at runtime.
@onready var portal_mesh: MeshInstance3D = $PortalMesh

## Dictionary storing tracked bodies and their last known side relative to the portal.
## Prevents false triggers and calculates exact crossing moments using dot products.
var _tracked_bodies: Dictionary = {}

## On-screen visibility notifier used to cull off-screen portal render passes.
var _screen_notifier: VisibleOnScreenNotifier3D = null

## Tracks if this portal's mesh is currently inside the player's camera frustum.
var _is_on_screen: bool = true


## Initializes portal listeners, duplicates shaders, and wires culling hooks.
func _ready() -> void:
	print("Portal: Initializing ", name)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	portal_camera.current = true

	if Events and Events.has_signal("player_camera_registered"):
		Events.player_camera_registered.connect(_on_player_camera_registered)

	_setup_screen_notifier()

	var mat: Material = portal_mesh.get_active_material(0)
	if mat and mat is ShaderMaterial:
		mat = mat.duplicate()
		portal_mesh.set_surface_override_material(0, mat)
		_update_mesh_texture.call_deferred()
	else:
		push_warning("Portal: No ShaderMaterial found on PortalMesh!")

	sub_viewport.size = get_viewport().size
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_assign_world_3d.call_deferred()

	if not is_instance_valid(player_camera):
		_find_and_assign_player_camera()


## Safely attaches the parent 3D world to the portal viewport once the scene tree is ready.
func _assign_world_3d() -> void:
	print("Portal: Binding World3D to SubViewport for ", name)
	var parent_world: World3D = get_viewport().find_world_3d()
	if is_instance_valid(parent_world):
		sub_viewport.world_3d = parent_world
	else:
		push_warning("Portal: Main World3D not found for SubViewport!")


## Sets up and attaches a [VisibleOnScreenNotifier3D] to cull updates when out of view.
func _setup_screen_notifier() -> void:
	print("Portal: Setting up screen visibility notifier for ", name)
	_screen_notifier = VisibleOnScreenNotifier3D.new()
	add_child(_screen_notifier)

	if portal_mesh and portal_mesh.mesh:
		_screen_notifier.aabb = portal_mesh.mesh.get_aabb()
	else:
		_screen_notifier.aabb = AABB(Vector3(-1.0, -1.0, -0.1), Vector3(2.0, 2.0, 0.2))

	_screen_notifier.screen_entered.connect(_on_screen_entered)
	_screen_notifier.screen_exited.connect(_on_screen_exited)


## Assigns the linked portal's viewport texture to this portal's shader.
func _update_mesh_texture() -> void:
	print("Portal: Updating mesh texture binding for ", name)
	if not is_instance_valid(linked_portal) or not is_instance_valid(portal_mesh):
		return

	var target_vp: SubViewport = linked_portal.sub_viewport
	if not is_instance_valid(target_vp):
		target_vp = linked_portal.get_node_or_null("SubViewport") as SubViewport
		if not is_instance_valid(target_vp):
			print("Portal: Linked SubViewport not ready yet on ", linked_portal.name)
			return

	var mat: Material = portal_mesh.get_surface_override_material(0)
	if mat and mat is ShaderMaterial:
		var target_texture: ViewportTexture = target_vp.get_texture()
		mat.set_shader_parameter("viewport_texture", target_texture)
		print("Portal: Bound linked ViewportTexture from ", linked_portal.name, " to ", name)


## Automatically connects to the primary player camera if unassigned.
func _find_and_assign_player_camera() -> void:
	print("Portal: Attempting to find player camera dynamically...")
	var viewport_cam: Camera3D = get_viewport().get_camera_3d()
	if is_instance_valid(viewport_cam) and viewport_cam != portal_camera:
		player_camera = viewport_cam
		print("Portal: Bound active main Camera3D: ", player_camera.name)
		return

	var player_node: Node = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player_node):
		var found_cam: Camera3D = player_node.find_child("*Camera*", true, false) as Camera3D
		if is_instance_valid(found_cam):
			player_camera = found_cam
			print("Portal: Bound Camera3D in player group: ", player_camera.name)


## Callback receiving the registered player camera from the global event bus.
## [param cam] The active [Camera3D] instance.
func _on_player_camera_registered(cam: Camera3D) -> void:
	print("Portal: [", name, "] Received player camera reference: ", cam.name)
	player_camera = cam


## Resizes the SubViewport texture when window resolution changes.
func _on_viewport_size_changed() -> void:
	print("Portal: Updating SubViewport size to match main viewport.")
	sub_viewport.size = get_viewport().size


## Synchronizes the destination portal camera with the player camera perspective.
## [param _delta] Frame elapsed time.
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

	var dist_sq: float = global_position.distance_squared_to(player_camera.global_position)
	if dist_sq > (max_render_distance * max_render_distance):
		linked_portal._set_viewport_mode(SubViewport.UPDATE_DISABLED)
		return

	linked_portal._set_viewport_mode(SubViewport.UPDATE_ALWAYS)

	var relative_transform: Transform3D = (
		global_transform.affine_inverse() * player_camera.global_transform
	)
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3.ZERO)

	linked_portal.portal_camera.global_transform = (
		linked_portal.global_transform * half_turn * relative_transform
	)
	linked_portal.portal_camera.fov = player_camera.fov
	linked_portal.portal_camera.near = player_camera.near
	linked_portal.portal_camera.far = player_camera.far
	linked_portal.portal_camera.keep_aspect = player_camera.keep_aspect
	linked_portal.portal_camera.projection = player_camera.projection


## Checks crossed bodies and performs portal teleportation.
## [param _delta] Physics step elapsed time.
func _physics_process(_delta: float) -> void:
	var keys: Array = _tracked_bodies.keys()
	for body: Node3D in keys:
		if not is_instance_valid(body):
			_tracked_bodies.erase(body)
			continue

		var current_side: float = _get_side(body.global_position)
		var previous_side: float = _tracked_bodies[body]

		if sign(current_side) != sign(previous_side):
			print("Portal: Teleporting body: ", body.name)
			_teleport_body(body)
			_tracked_bodies.erase(body)
		else:
			_tracked_bodies[body] = current_side


## Calculates which side of the portal plane a point resides on.
## [param pos] Target position vector.
## [return] Dot product against the portal front vector.
func _get_side(pos: Vector3) -> float:
	var dir_to_body: Vector3 = pos - global_position
	return global_transform.basis.z.dot(dir_to_body)


## Teleports a body through to the linked portal with inverted momentum.
## [param body] The [Node3D] being translated.
func _teleport_body(body: Node3D) -> void:
	if not is_instance_valid(linked_portal):
		return

	var relative_trans: Transform3D = global_transform.affine_inverse() * body.global_transform
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3.ZERO)
	body.global_transform = (linked_portal.global_transform * half_turn * relative_trans)

	if "velocity" in body:
		var relative_velocity: Vector3 = global_transform.basis.inverse() * body.get("velocity")
		body.set(
			"velocity", (linked_portal.global_transform.basis * half_turn.basis) * relative_velocity
		)


## Registers entering bodies for plane crossing detection.
## [param body] Entering body instance.
func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D or body is RigidBody3D:
		print("Portal: Tracking body entered portal zone: ", body.name)
		_tracked_bodies[body] = _get_side(body.global_position)


## Deregisters exiting bodies from tracking.
## [param body] Exiting body instance.
func _on_body_exited(body: Node3D) -> void:
	if _tracked_bodies.has(body):
		print("Portal: Body exited portal zone: ", body.name)
		_tracked_bodies.erase(body)


## Enables processing when portal bounds enter view.
func _on_screen_entered() -> void:
	print("Portal: Screen entered for ", name)
	_is_on_screen = true
	_update_mesh_texture()


## Disables viewport updates when portal bounds leave view.
func _on_screen_exited() -> void:
	print("Portal: Screen exited for ", name)
	_is_on_screen = false
	if is_instance_valid(linked_portal):
		linked_portal._set_viewport_mode(SubViewport.UPDATE_DISABLED)


## Helper method to safely toggle SubViewport update modes.
## [param mode] New target [enum SubViewport.UpdateMode].
func _set_viewport_mode(mode: SubViewport.UpdateMode) -> void:
	if sub_viewport.render_target_update_mode != mode:
		print("Portal: Setting SubViewport mode to ", mode, " on ", name)
		sub_viewport.render_target_update_mode = mode
