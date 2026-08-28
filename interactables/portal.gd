## Handles 3D portal perspective projection, dynamic viewport culling, and seamless teleportation.
class_name Portal
extends Area3D

## The destination portal this portal connects to.
## Used as the anchor point to calculate relative positions for rendering and teleportation.
@export var linked_portal: Portal

## The main active player camera.
## Tracked so we can simulate the player's perspective accurately from the linked portal.
@export var player_camera: Camera3D

## Maximum distance from the player camera to update the portal viewport.
@export var max_render_distance: float = 30.0

## The viewport that renders the scene from this portal's perspective.
## This acts as the texture source for the linked portal mesh shader.
@onready var sub_viewport: SubViewport = $SubViewport

## The camera capturing the view for the portal.
## Positioned relative to the linked portal based on the player's offset from this portal.
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
var _is_on_screen: bool = false


## Initializes portal listeners, duplicates shaders, and wires culling hooks.
func _ready() -> void:
	print("Portal initialized: ", name)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_setup_screen_notifier()

	# Duplicate material to prevent instance texture bleeding
	var mat: Material = portal_mesh.get_active_material(0)
	if mat and mat is ShaderMaterial:
		mat = mat.duplicate()
		portal_mesh.set_surface_override_material(0, mat)
		_update_mesh_texture.call_deferred()
	else:
		push_warning("Portal: No ShaderMaterial found on PortalMesh!")

	# Initial resolution match and viewport gating
	sub_viewport.size = get_viewport().size
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	if not is_instance_valid(player_camera):
		_find_and_assign_player_camera()

	_isolate_portal_environment()


## Sets up and attaches a [VisibleOnScreenNotifier3D] to cull updates when out of view.
func _setup_screen_notifier() -> void:
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
	var player_node: Node = get_tree().get_first_node_in_group("player")

	if is_instance_valid(player_node) and player_node is Player:
		if is_instance_valid(player_node.camera_controller):
			player_camera = player_node.camera_controller.camera
			print("Portal: Successfully connected to player camera!")
		else:
			print("Portal: Player found, but CameraController is missing.")
	else:
		print("Portal: No player found in the 'player' group.")


## Resizes the SubViewport texture when window resolution changes.
func _on_viewport_size_changed() -> void:
	print("Updating Portal SubViewport size to match main viewport.")
	sub_viewport.size = get_viewport().size


## Synchronizes portal camera transforms based on player positioning.
func _process(_delta: float) -> void:
	if not _is_on_screen:
		return

	if not is_instance_valid(linked_portal) or not is_instance_valid(player_camera):
		return

	var dist_sq: float = global_position.distance_squared_to(player_camera.global_position)
	if dist_sq > (max_render_distance * max_render_distance):
		_set_viewport_mode(SubViewport.UPDATE_DISABLED)
		return

	_set_viewport_mode(SubViewport.UPDATE_ALWAYS)

	var relative_transform: Transform3D = (
		global_transform.affine_inverse() * player_camera.global_transform
	)
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO)

	portal_camera.global_transform = linked_portal.global_transform * half_turn * relative_transform
	portal_camera.fov = player_camera.fov


## Checks crossed bodies and performs portal teleportation.
func _physics_process(_delta: float) -> void:
	var keys: Array = _tracked_bodies.keys()
	for body: Node3D in keys:
		if not is_instance_valid(body):
			_tracked_bodies.erase(body)
			continue

		var current_side: float = _get_side(body.global_position)
		var previous_side: float = _tracked_bodies[body]

		if sign(current_side) != sign(previous_side):
			print("Teleporting body: ", body.name)
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
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO)
	body.global_transform = linked_portal.global_transform * half_turn * relative_trans

	if "velocity" in body:
		var relative_velocity: Vector3 = global_transform.basis.inverse() * body.get("velocity")
		body.set(
			"velocity", (linked_portal.global_transform.basis * half_turn.basis) * relative_velocity
		)


## Registers entering bodies for plane crossing detection.
## [param body] Entering body instance.
func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D or body is RigidBody3D:
		print("Tracking body entered portal zone: ", body.name)
		_tracked_bodies[body] = _get_side(body.global_position)


## Deregisters exiting bodies from tracking.
## [param body] Exiting body instance.
func _on_body_exited(body: Node3D) -> void:
	if _tracked_bodies.has(body):
		print("Body exited portal zone: ", body.name)
		_tracked_bodies.erase(body)


## Enables processing when portal bounds enter view.
func _on_screen_entered() -> void:
	_is_on_screen = true
	_update_mesh_texture()


## Disables viewport updates when portal bounds leave view.
func _on_screen_exited() -> void:
	_is_on_screen = false
	_set_viewport_mode(SubViewport.UPDATE_DISABLED)


## Helper method to safely toggle SubViewport update modes.
## [param mode] New target [enum SubViewport.UpdateMode].
func _set_viewport_mode(mode: SubViewport.UpdateMode) -> void:
	if sub_viewport.render_target_update_mode != mode:
		sub_viewport.render_target_update_mode = mode


## Strips global atmospheric and compositor passes from the portal camera.
func _isolate_portal_environment() -> void:
	print("Portal: Isolating viewport from global weather and clouds.")

	var blank_env: Environment = Environment.new()
	blank_env.background_mode = Environment.BG_CLEAR_COLOR
	blank_env.sky = null
	blank_env.volumetric_fog_enabled = false
	blank_env.fog_enabled = false

	portal_camera.environment = blank_env

	if "compositor" in portal_camera:
		var empty_compositor: Compositor = Compositor.new()
		portal_camera.set("compositor", empty_compositor)
