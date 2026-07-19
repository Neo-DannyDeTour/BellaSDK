class_name Portal extends Area3D

## The destination portal this portal connects to.
## Used as the anchor point to calculate relative positions for rendering and teleportation.
@export var linked_portal: Portal

## The main active player camera.
## Tracked so we can simulate the player's perspective accurately from the linked portal.
@export var player_camera: Camera3D

## The viewport that renders the scene from the linked portal.
## This acts as the texture source for the portal mesh shader.
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


func _ready() -> void:
	print("Portal initialized: ", name)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# CRITICAL FIX: Duplicate the material so Portals don't fight over the same resource!
	var mat: Material = portal_mesh.get_active_material(0)
	if mat and mat is ShaderMaterial:
		mat = mat.duplicate()
		portal_mesh.set_surface_override_material(0, mat)

		print("Portal: Injecting ViewportTexture into unique shader for ", name)
		mat.set_shader_parameter("viewport_texture", sub_viewport.get_texture())
	else:
		push_warning("Portal: No ShaderMaterial found on PortalMesh!")

	# Keep the rendering resolution matched to avoid visual stretching
	sub_viewport.size = get_viewport().size
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	if not is_instance_valid(player_camera):
		_find_and_assign_player_camera()

	# Inject the isolation setup here
	_isolate_portal_environment()


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


func _on_viewport_size_changed() -> void:
	print("Updating Portal SubViewport size to match main viewport.")
	sub_viewport.size = get_viewport().size


func _process(_delta: float) -> void:
	if not is_instance_valid(linked_portal) or not is_instance_valid(player_camera):
		return

	# Calculate the player camera's transform relative to this portal.
	var relative_transform: Transform3D = (
		global_transform.affine_inverse() * player_camera.global_transform
	)

	# CRITICAL FIX: Rotate the relative transform by 180 degrees (PI) on the Y axis.
	# This flips the perspective so entering the "front" looks out the "front".
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO)

	# Apply the flipped relative transform to the linked portal's global transform.
	portal_camera.global_transform = linked_portal.global_transform * half_turn * relative_transform

	# Sync camera settings to prevent visual artifacts.
	portal_camera.fov = player_camera.fov

	# REMOVED: portal_camera.cull_mask = player_camera.cull_mask
	# We no longer sync the cull mask so the inspector settings (excluding the cloud layer) are preserved.


func _physics_process(_delta: float) -> void:
	var keys: Array = _tracked_bodies.keys()
	for body: Node3D in keys:
		if not is_instance_valid(body):
			_tracked_bodies.erase(body)
			continue

		var current_side: float = _get_side(body.global_position)
		var previous_side: float = _tracked_bodies[body]

		# Determine if the body crossed the portal plane by checking sign change.
		if sign(current_side) != sign(previous_side):
			print("Teleporting body: ", body.name)
			_teleport_body(body)
			# Remove from tracking to prevent double teleporting;
			# it will be tracked by the other portal when entering its area.
			_tracked_bodies.erase(body)
		else:
			_tracked_bodies[body] = current_side


func _get_side(pos: Vector3) -> float:
	# Use the portal's forward vector (Z-axis) to determine the side.
	var dir_to_body: Vector3 = pos - global_position
	return global_transform.basis.z.dot(dir_to_body)


func _teleport_body(body: Node3D) -> void:
	if not is_instance_valid(linked_portal):
		return

	# Calculate the relative transform.
	var relative_trans: Transform3D = global_transform.affine_inverse() * body.global_transform

	# Apply the exact same 180-degree flip so the player's body rotates correctly upon exit.
	var half_turn: Transform3D = Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3.ZERO)
	body.global_transform = linked_portal.global_transform * half_turn * relative_trans

	# Rotate the momentum/velocity vector so you don't fly sideways out of angled portals.
	if "velocity" in body:
		var relative_velocity: Vector3 = global_transform.basis.inverse() * body.get("velocity")
		body.set(
			"velocity", (linked_portal.global_transform.basis * half_turn.basis) * relative_velocity
		)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D or body is RigidBody3D:
		print("Tracking body entered portal zone: ", body.name)
		_tracked_bodies[body] = _get_side(body.global_position)


func _on_body_exited(body: Node3D) -> void:
	if _tracked_bodies.has(body):
		print("Body exited portal zone: ", body.name)
		_tracked_bodies.erase(body)


func _isolate_portal_environment() -> void:
	print("Portal: Isolating viewport from global weather and clouds.")

	# 1. Create a blank environment to override the global sky and standard fog
	var blank_env: Environment = Environment.new()
	blank_env.background_mode = Environment.BG_CLEAR_COLOR
	blank_env.sky = null
	blank_env.volumetric_fog_enabled = false
	blank_env.fog_enabled = false

	portal_camera.environment = blank_env

	# 2. Assign an empty compositor to block global compositor effects (Sunshine Clouds)
	# Checking if the property exists ensures it doesn't crash on older Godot 4 builds
	if "compositor" in portal_camera:
		var empty_compositor: Compositor = Compositor.new()
		portal_camera.set("compositor", empty_compositor)
