extends StaticBody3D

@export_category("CCTV Settings")
@export var camera_vp: SubViewport
@export var camera_locations: Array[Node3D] = []
@export var pan_speed: float = 60.0
@export var zoom_speed: float = 5.0
@export var min_fov: float = 30.0
@export var max_fov: float = 75.0

@onready var screen_mesh: MeshInstance3D = $ScreenMesh
@onready var interact_comp: Node = $Interact_Component
@onready var cctv_camera: Camera3D = $CameraViewport/CCTVCamera

var screen_mat_override: StandardMaterial3D
var active_cam_idx: int = 0
var is_controlling: bool = false
var current_player: CharacterBody3D = null
var target_fov: float = 75.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0

var _interaction_cooldown: float = 0.0

func _ready() -> void:
	if interact_comp and not interact_comp.interacted.is_connected(_on_interacted):
		interact_comp.interacted.connect(_on_interacted)

	screen_mat_override = screen_mesh.get_material_override() as StandardMaterial3D
	
	if not screen_mat_override:
		screen_mat_override = screen_mesh.get_surface_override_material(0) as StandardMaterial3D
		
	if not screen_mat_override:
		screen_mat_override = StandardMaterial3D.new()
		screen_mesh.material_override = screen_mat_override

	if screen_mat_override and camera_vp:
		screen_mat_override.albedo_texture = camera_vp.get_texture()
		# Draw a single starting frame, then automatically disable rendering
		camera_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	if is_instance_valid(cctv_camera):
		target_fov = cctv_camera.fov
		cctv_camera.make_current()

	if not camera_locations.is_empty():
		_set_camera(0)

func _process(delta: float) -> void:
	if _interaction_cooldown > 0.0:
		_interaction_cooldown -= delta

	if not is_controlling or not is_instance_valid(cctv_camera):
		return

	_pan_camera(delta)
	_handle_zoom(delta)

func _input(event: InputEvent) -> void:
	if not is_controlling:
		return

	if event.is_action_pressed("interact") and _interaction_cooldown <= 0.0:
		print("[CCTV] Detaching from screen...")
		_stop_controlling()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("shoot"):
		print("[CCTV] Cycling to next camera...")
		_cycle_camera()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			print("[CCTV] Zooming IN")
			target_fov -= zoom_speed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			print("[CCTV] Zooming OUT")
			target_fov += zoom_speed
			get_viewport().set_input_as_handled()

func _on_interacted(player: CharacterBody3D) -> void:
	if is_controlling or _interaction_cooldown > 0.0:
		return

	print("[CCTV] Attached to TV Screen!")
	is_controlling = true
	current_player = player
	_interaction_cooldown = 0.3 

	# Activate the viewport rendering so the screen visually updates
	if camera_vp:
		camera_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	if current_player and current_player.system_menu:
		current_player.system_menu.is_stunned = true

func _stop_controlling() -> void:
	is_controlling = false
	_interaction_cooldown = 0.3 

	# Disable the viewport to reclaim frame rates
	if camera_vp:
		camera_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

	if current_player and current_player.system_menu:
		current_player.system_menu.is_stunned = false

	current_player = null

func _set_camera(index: int) -> void:
	if index < 0 or index >= camera_locations.size():
		return

	var target_loc: Node3D = camera_locations[index]
	if not is_instance_valid(target_loc):
		return

	active_cam_idx = index
	cctv_camera.global_position = target_loc.global_position
	
	var marker_rot: Vector3 = target_loc.global_rotation
	current_yaw = marker_rot.y
	current_pitch = marker_rot.x
	
	cctv_camera.rotation.y = current_yaw
	cctv_camera.rotation.x = current_pitch
	cctv_camera.rotation.z = 0.0

func _cycle_camera() -> void:
	if camera_locations.is_empty():
		return

	var next_idx: int = (active_cam_idx + 1) % camera_locations.size()
	_set_camera(next_idx)
	
func _pan_camera(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"left", "right", "forward", "backward"
	)

	if input_dir.length_squared() < 0.01:
		return

	print("[CCTV] Panning camera. Input Dir: ", input_dir)

	var pan_rad: float = deg_to_rad(pan_speed)
	current_yaw += -input_dir.x * pan_rad * delta
	current_pitch += -input_dir.y * pan_rad * delta
	
	current_pitch = clampf(current_pitch, deg_to_rad(-80.0), deg_to_rad(80.0))
	
	cctv_camera.rotation.y = current_yaw
	cctv_camera.rotation.x = current_pitch
	cctv_camera.rotation.z = 0.0

func _handle_zoom(delta: float) -> void:
	target_fov = clampf(target_fov, min_fov, max_fov)
	cctv_camera.fov = lerpf(cctv_camera.fov, target_fov, 10.0 * delta)
