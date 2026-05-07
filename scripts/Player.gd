extends CharacterBody3D

# BASED GODOT YOUTUBERS
# LUKKY - https://www.youtube.com/watch?v=xIKErMgJ1Yk - FPS CONTROLLER
# https://www.youtube.com/@stayathomedev - FPS CONTROLLER + HE HELPED ME STARTED

# PLAYER NODES

@onready var head: Node3D = $Head
@onready var eyes: Node3D = $Head/Eyes
@onready var standing_collision_shape: CollisionShape3D = $StandingCollisionShape
@onready var crouching_collision_shape: CollisionShape3D = $CrouchingCollisionShape
@onready var crouch_cast_check: RayCast3D = $CrouchCastCheck
@onready var cam: Camera3D = $Head/Eyes/Camera3D
@onready var camera_anims: AnimationPlayer = $Head/Eyes/CameraAnims
@onready var omni_light_3d: OmniLight3D = $Head/Eyes/Camera3D/OmniLight3D

@onready var flash_light_node: Node3D = $Head/Eyes/Camera3D/FlashLightNode
@onready var flashlight: SpotLight3D = $Head/Eyes/Camera3D/FlashLightNode/Flashlight

@onready var interact_shapecast: ShapeCast3D = %InteractShapeCast
@onready var hold_position: Marker3D = $Head/Eyes/Camera3D/SpringArm3D/HoldPosition

# --- ADD TO THE TOP OF Player.gd (Node Caching) ---
@onready var weapon_holder: Node3D = %WeaponHolder
@onready var stairs_below_cast: RayCast3D = %StairsBelowCast
@onready var stairs_ahead_cast: RayCast3D = %StairsAheadCast

@onready var screen_water_ui: ColorRect = $CanvasLayer/WaterRippleOverlay


# --------------------------------------
# @EXPORTS
# --------------------------------------
@export var walking_speed: float = 5.0
@export var sprinting_speed: float = 6.5
@export var crouching_speed: float = 3.0
@export var swimming_speed: float = 4.0

@export var sway_amount: float = 5.0
@export var smooth_speed: float = 10.0

@export var base_fov: float = 75.0
@export var sprint_fov: float = 85.0

@export var jump_buffer_duration: float = 0.15
@export var coyote_time_duration: float = 0.15
@export var fall_gravity_multiplier: float = 1.5 # For snappier falling

var fullbright_env: Environment

var jump_buffer_timer: float = 0.0
var coyote_timer: float = 0.0

# SPEED VARS
var current_speed: float = 0.0
const jump_velocity: float = 4.5
const crouch_jump_velocity: float = 3.5
const sprint_jump_velocity: float = 5.0

# SPEED STATES
var walking: bool = false
var sprinting: bool = false
var crouching: bool = false
var sprint_active: bool = false
var flying: bool = false
var swimming: bool = false

var can_sprint: bool = true

var is_heavy_lifting: bool = false:
	set(value):
		is_heavy_lifting = value
		if is_heavy_lifting:
			heavy_lift_yaw_base = rotation.y # Remember our starting angle

var heavy_lift_yaw_base: float = 0.0

var is_stunned: bool = false
var is_vaulting: bool = false

# INPUT VARS

var mouse_sensitivity: float = 0.05
var mouse_sensitivity_base: float = 0.05
var mouse_sensitivity_zoom: float = mouse_sensitivity / 10.0
var direction: Vector3 = Vector3.ZERO

# HEADBOB VARS
const head_bobbing_sprinting_speed: float = 22.0
const head_bobbing_walking_speed: float = 14.0
const head_bobbing_crouching_speed: float = 10.0
const head_bobbing_idle_speed: float = 3.0

const head_bobbing_sprinting_intensity: float = 0.2
const head_bobbing_walking_intensity: float = 0.1
const head_bobbing_crouching_intensity: float = 0.08
const head_bobbing_idle_intensity: float = 0.02

var head_bobbing_index: float = 0.0
var head_bobbing_current_intensity: float = 0.0

# MOVEMENT VARS
var lerp_speed: float = 15.0
var air_lerp_speed: float = 3.0
var crouching_depth: float = 0.7
var last_velocity: Vector3 = Vector3.ZERO

const CameraTiltLeft: float = 3.0
const CameraTiltRight: float = -3.0

var stair_offset: float = 0.0
var headbob_offset: Vector2 = Vector2.ZERO

# --- ADD TO THE MOVEMENT VARS SECTION (Optimization) ---
var _motion_params := PhysicsTestMotionParameters3D.new()
var _motion_result := PhysicsTestMotionResult3D.new()

## FLASHLIGHT VARS
var flashlight_rotation_smoothness: float = 10.0
var flashlight_position_smoothness: float = 10.0

var default_flashlight_pos: Vector3 = Vector3.ZERO
var sway_target: Vector2 = Vector2.ZERO

# HL2-like flashlight
var default_spot_angle: float = 45.0
var flashlight_maintain_distance: float = 1.5 # Starts compensating when closer than 1.5 meters

# --- INSTABILITY VARIABLES ---
@export var base_energy: float = 10.0

# Electrical Instability
var flicker_timer: float = 0.0
var is_flickering: bool = false

# Physical Instability (Shaky Hand)
var jitter_noise := FastNoiseLite.new()
var noise_time: float = 0.0

# SPRINT FOV VARS
var zoom_fov: float = 10.0
var fov_change_speed: float = 12.0
var target_fov: float = base_fov

# INTERACT VARS
var current_interactable: Interact_Component = null
var held_object: PickableObject = null

# STAIRS AND STEEP SURFACES VARS
const MAX_STEP_HEIGHT: float = 0.5
var _snapped_to_stairs_last_frame: bool = false
var _last_frame_was_on_floor: int = -999999 # Safe integer instead of -INF

# LADDER VARS
var on_ladder: bool = false
var LADDER_SPEED: float = 5.0

# ROPE VARS
var current_rope: RigidBody3D = null
var rope_offset: float = 0.0
const ROPE_CLIMB_SPEED: float = 1.0
var rope_local_grab_dir := Vector3.ZERO
var rope_lerp_weight: float = 0.0

# FAST ROPE VARS
var on_fast_rope: bool = false

# SWIM VARS
var swim_up_speed: float = 5.0
var base_light_energy: float = 1.0
var base_spot_range: float = 10.0
var is_swimming: bool = false
var head_in_water: bool = false

var water_clear_tween: Tween
var was_head_in_water: bool = false

# UPDRAFT VARS
var in_updraft: bool = false
var current_updraft_strength: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float

# DEVTOOLS VARS
var noclip_speed_multiplier: float = 8.0
var is_menu_open: bool = false

# ZIPLINE VARS
var current_zipline: Node3D
var zipline_grab_timer: float = 0.0
var is_auto_sliding: bool = false
var on_zipline: bool = false
var zipline_start: Vector3
var zipline_end: Vector3
var zipline_dir: Vector3
var zipline_length: float
var zipline_progress: float = 0.0
var is_zipline_sliding: bool = false
var is_zipline_transitioning: bool = false
var zipline_grace_timer: float = 0.0

var ZIPLINE_SLIDE_SPEED: float = 8.0
var ZIPLINE_HANG_OFFSET: float = 2.0 # Adjust this until your hands line up with the rope

var zipline_speed := 30.0 # How fast you move
var zipline_gravity_pull := 5.0 # How much the slope pulls you down

# MONKE VARS
var current_monkey_bar_path: Path3D = null
var available_monkey_bar: Node3D = null
var monkey_bar_cooldown: float = 0.0
var on_monkey_bars: bool = false
var MONKEY_BAR_SPEED: float = 2.5
var MONKEY_BAR_HANG_OFFSET: float = 2.1
var current_monkey_bar_volume: Node3D = null

# Add these receiver functions anywhere in your player script
func set_available_monkey_bar(bar: Node3D) -> void:
	available_monkey_bar = bar

func clear_available_monkey_bar(bar: Node3D) -> void:
	if available_monkey_bar == bar:
		available_monkey_bar = null

# SHOOT VARS
var damage: int = 100

# PAUSE VARS
var is_paused: bool = false
var menu_scene: PackedScene = preload("res://scenes/menus/main_menu.tscn")
var menu_instance: CanvasLayer

# VAULT SCANNER VARS
var vault_indicator: MeshInstance3D
var can_vault_current_ledge: bool = false
var current_ledge_point: Vector3 = Vector3.ZERO
var current_vault_height: float = 0.0
var current_vault_requires_crouch: bool = false

# --- TERMINAL MODE VARS ---
var is_in_terminal_mode: bool = false
var active_terminal: Node3D = null
var terminal_start_pos: Vector3

# UI & Sensitivity Variables (Assign player_ui in the Inspector!)
@export var player_ui: CanvasLayer

# SHAPECAST REACH VARS
var base_reach: float = 0.5
var floor_reach: float = 2.2 # 2m height + 0.2m margin

# OTHER VARS
var input_dir: Vector2 = Vector2.ZERO
var _frames_since_grounded: int = 0
var is_using_zoom: bool = false
var overlapping_water_areas: Array[Area3D] = []

# --------------------------------------
# MAIN SCRIPT
# --------------------------------------
func _ready() -> void:
	# --- DYNAMIC VAULT INDICATOR ---
	vault_indicator = MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.03
	dot_mesh.height = 0.06
	vault_indicator.mesh = dot_mesh

	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color.WHITE
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot_mat.albedo_color.a = 0.6
	dot_mat.no_depth_test = true

	vault_indicator.material_override = dot_mat
	vault_indicator.top_level = true
	add_child(vault_indicator)
	vault_indicator.hide()

	# Spawn menu
	menu_instance = menu_scene.instantiate() as CanvasLayer
	add_child(menu_instance)
	menu_instance.hide()

	Events.debug_menu_toggled.connect(_on_debug_menu_toggled)
	Events.noclip_ui_button_pressed.connect(toggle_noclip)

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	default_flashlight_pos = flash_light_node.position
	flashlight.visible = false
	if omni_light_3d:
		omni_light_3d.visible = false
	#flashlight_decal.top_level = true
	#flashlight_decal.hide()
	if flashlight:
		base_light_energy = flashlight.light_energy
		base_spot_range = flashlight.spot_range
		default_spot_angle = flashlight.spot_angle
		
	jitter_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	jitter_noise.frequency = 0.8
	
	var config := ConfigFile.new()
	var err := config.load("user://settings.cfg")

	if err == OK and config.has_section_key("Settings", "mouse_sensitivity"):
		# The player has played before and saved a preference. Load it.
		var saved_sens: float = config.get_value("Settings", "mouse_sensitivity")
		_apply_sensitivity(saved_sens)
	else:
		# First time playing! Or the file was deleted/corrupted.
		# Apply your newly tested, comfortable default.
		_apply_sensitivity(mouse_sensitivity_base)
	
	Events.fullbright_toggled.connect(_on_fullbright_toggled)
	
	# Pre-build our custom debug environment
	fullbright_env = Environment.new()
	fullbright_env.background_mode = Environment.BG_COLOR
	fullbright_env.background_color = Color(0.5, 0.5, 0.5)
	fullbright_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	fullbright_env.ambient_light_color = Color.WHITE
	fullbright_env.ambient_light_energy = 2.0
	
	# Disable expensive/shadow effects
	fullbright_env.ssao_enabled = false
	fullbright_env.ssil_enabled = false
	fullbright_env.sdfgi_enabled = false
	fullbright_env.glow_enabled = false
	
func _unhandled_input(event: InputEvent) -> void:
	if is_paused or is_menu_open:
		return

	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			noclip_speed_multiplier = min(100.0, noclip_speed_multiplier * 1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			noclip_speed_multiplier = max(0.1, noclip_speed_multiplier * 0.9)

	# --- 1. TERMINAL MODE CLICKING OVERRIDE ---
	if is_in_terminal_mode and is_instance_valid(active_terminal):
		# Handle left-clicking the keypad buttons
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			shoot_terminal_raycast(true)
			get_viewport().set_input_as_handled()
			return # IMPORTANT: Stop running this function so we don't shoot the gun!

	# --- 2. COMBAT & THROW INPUTS ---
	if event.is_action_pressed("shoot"):
		if held_object:
			var throw_force: float = 12.0
			var throw_direction: Vector3 = - cam.global_transform.basis.z.normalized()
			throw_direction.y += 0.2
			held_object.throw(throw_direction.normalized() * throw_force)
			held_object = null

			if weapon_holder:
				weapon_holder.show()

		else:
			if weapon_holder and weapon_holder.get_child_count() > 0:
				var current_weapon: Node = weapon_holder.get_child(0)
				if current_weapon.has_method("shoot"):
					current_weapon.call("shoot", cam)

func _input(event: InputEvent) -> void:
	if is_menu_open or is_paused:
		return
	if is_stunned:
		return

	# MOUSE LOOKING LOGIC
	if event is InputEventMouseMotion:
		# --- THE FIX ---
		# 1. Grab whatever sensitivity _process wants us to use
		var active_sens: float = mouse_sensitivity

		# 2. If using the keypad, crush the sensitivity down to 10%!
		if is_in_terminal_mode:
			active_sens = mouse_sensitivity * 0.5

		# 3. Apply the 'active_sens' to your movement logic
		if is_heavy_lifting:
			# --- THE NECK CLAMP ---
			var new_yaw: float = rotation.y - deg_to_rad(event.relative.x * active_sens)
			var diff: float = angle_difference(heavy_lift_yaw_base, new_yaw)
			var clamped_diff: float = clampf(diff, deg_to_rad(-15.0), deg_to_rad(15.0))
			rotation.y = heavy_lift_yaw_base + clamped_diff
		else:
			# Normal turning
			rotate_y(deg_to_rad(-event.relative.x * active_sens))

		head.rotate_x(deg_to_rad(-event.relative.y * active_sens))
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		sway_target += event.relative

# --------------------------------------
# SMOOTH STAIRS AND OTHER DIFFICULT TERRAIN
# --------------------------------------
func is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle

func _run_body_test_motion(from: Transform3D, motion: Vector3, result: PhysicsTestMotionResult3D = null) -> bool:
	_motion_params.from = from
	_motion_params.motion = motion
	# Using the PhysicsServer directly is faster than body_test_motion on the node
	return PhysicsServer3D.body_test_motion(self.get_rid(), _motion_params, result if result else _motion_result)

func _snap_down_to_stairs_check() -> void:
	var did_snap: bool = false
	var floor_below: bool = stairs_below_cast.is_colliding() and not is_surface_too_steep(stairs_below_cast.get_collision_normal())
	var was_on_floor_last_frame: bool = Engine.get_physics_frames() - _last_frame_was_on_floor == 1

	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or _snapped_to_stairs_last_frame) and floor_below:
		var body_test_result := PhysicsTestMotionResult3D.new()
		if _run_body_test_motion(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			var travel_y: float = body_test_result.get_travel().y

			if travel_y < -0.05:
				var old_pos_y: float = self.global_position.y
				self.position.y += travel_y
				apply_floor_snap()
				did_snap = true
				_apply_camera_smoothing(self.global_position.y - old_pos_y)

	_snapped_to_stairs_last_frame = did_snap

func _snap_up_stairs_check(delta: float) -> bool:
	if not is_on_floor() and not _snapped_to_stairs_last_frame: return false
	if self.velocity.y > 0 or (self.velocity * Vector3(1, 0, 1)).length() == 0: return false

	var expected_move_motion: Vector3 = self.velocity * Vector3(1, 0, 1) * delta
	var step_pos_with_clearance: Transform3D = self.global_transform

	# 1. Test moving UP safely
	var up_test := PhysicsTestMotionResult3D.new()
	_run_body_test_motion(step_pos_with_clearance, Vector3(0, MAX_STEP_HEIGHT * 2, 0), up_test)
	step_pos_with_clearance.origin += up_test.get_travel()

	# 2. Test moving FORWARD safely
	var forward_test := PhysicsTestMotionResult3D.new()
	_run_body_test_motion(step_pos_with_clearance, expected_move_motion, forward_test)
	step_pos_with_clearance.origin += forward_test.get_travel()

	# 3. NOW test moving DOWN onto the step
	var down_check_result := PhysicsTestMotionResult3D.new()
	if (_run_body_test_motion(step_pos_with_clearance, Vector3(0, -MAX_STEP_HEIGHT * 2, 0), down_check_result)
	and (down_check_result.get_collider().is_class("StaticBody3D") or down_check_result.get_collider().is_class("CSGShape3D"))):
		var step_height: float = ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y

		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_collision_point() - self.global_position).y > MAX_STEP_HEIGHT: return false

		stairs_ahead_cast.global_position = down_check_result.get_collision_point() + Vector3(0, MAX_STEP_HEIGHT, 0) + expected_move_motion.normalized() * 0.1
		stairs_ahead_cast.force_raycast_update()

		if stairs_ahead_cast.is_colliding() and not is_surface_too_steep(stairs_ahead_cast.get_collision_normal()):
			var old_pos_y: float = self.global_position.y
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			_snapped_to_stairs_last_frame = true
			_apply_camera_smoothing(self.global_position.y - old_pos_y)
			return true

	return false

func _apply_camera_smoothing(snap_amount: float) -> void:
	stair_offset -= snap_amount
	stair_offset = clampf(stair_offset, -0.5, 0.5)

func _slide_camera_smooth_back_to_origin(delta: float) -> void:
	if stair_offset == 0.0:
		return

	var move_amount: float = maxf(self.velocity.length() * delta, walking_speed / 2.0 * delta)
	stair_offset = move_toward(stair_offset, 0.0, move_amount)

func _physics_process(delta: float) -> void:
	if is_paused or is_stunned or is_menu_open: # <--- ADDED HERE
		velocity = Vector3.ZERO
		#move_and_slide()
		return

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	if Input.is_action_pressed("zoom"):
		input_dir = Vector2.ZERO

	var is_truly_grounded: bool = _frames_since_grounded < 3
	if is_on_floor(): _last_frame_was_on_floor = Engine.get_physics_frames()

	if is_on_floor() or _snapped_to_stairs_last_frame:
		_frames_since_grounded = 0
	else:
		_frames_since_grounded += 1

	is_swimming = _handle_water_physics(delta)
	if not is_swimming: swimming = false

	if not is_vaulting and not is_paused:
		_scan_for_ledges()
	elif vault_indicator:
		vault_indicator.hide()
		can_vault_current_ledge = false

	if Input.is_action_just_pressed("noclip"):
		toggle_noclip()

	if is_vaulting:
		return

	if flying:
		_handle_noclip_physics(delta)
	elif is_swimming:
		pass
	elif on_ladder:
		_handle_ladder_physics(delta)
	elif on_monkey_bars:
		_handle_monkey_bars_physics(delta)
	elif on_zipline and not is_zipline_transitioning:
		_handle_zipline_physics(delta)
	elif current_rope != null:
		_handle_rope_physics(delta)
		return
	elif on_fast_rope:
		_handle_fast_rope_physics(delta)
		return # Crucial! Skips move_and_slide and stair checks
	else:
		_handle_ground_physics(delta, is_truly_grounded)

	last_velocity = velocity

	if not _snap_up_stairs_check(delta):
		move_and_slide()
		_snap_down_to_stairs_check()

	# --- THE ZIPLINE CHECK ---
	# We only check if we are actually crouching, and NOT already on the zipline or vaulting
	if not on_zipline and not is_vaulting:
		_check_zipline_collisions()
	# -------------------------------------------

	_slide_camera_smooth_back_to_origin(delta)

	if monkey_bar_cooldown > 0:
		monkey_bar_cooldown -= delta

	if not is_on_floor() and available_monkey_bar != null and monkey_bar_cooldown <= 0:
		if not on_monkey_bars:
		# 1. Calculate the exact height the player's body should hang at
			var hang_height: float = available_monkey_bar.global_position.y - MONKEY_BAR_HANG_OFFSET

			# 2. Check how physically close the player is to that hang spot
			var distance_to_hang: float = absf(hang_height - global_position.y)

			# --- THE UPDATED FIX ---
			# ONLY grab the bar if we are within 1.5 meters of it (magnet radius)
			# AND our jump has slowed down below 2.0 m/s (near the peak of our jump)
			# OR if we are flying fast but have perfectly reached the bar's height (distance < 0.4)
			if distance_to_hang < 1.5 and (velocity.y < 2.0 or distance_to_hang < 0.4):
				current_monkey_bar_volume = available_monkey_bar
				enter_monkey_bars(available_monkey_bar)
				
	if SmokeManager:
		SmokeManager.update_player_position(global_position)
		
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_pause()

	if is_paused or is_menu_open: # <--- ADDED HERE
		return

	if is_in_terminal_mode:
		# --- NEW: Exit if the player starts moving with WASD ---
		# Replace these strings with your actual movement Input Map names!
		if Input.is_action_pressed("forward") or Input.is_action_pressed("backward") or \
		   Input.is_action_pressed("left") or Input.is_action_pressed("right"):
			exit_terminal_mode()
			return

		# Exit if the player jumps or crouches
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch"):
			exit_terminal_mode()
			return

		# Exit if the player drifts/walks more than 1 meter away
		if global_position.distance_to(terminal_start_pos) > 1.0:
			exit_terminal_mode()
			return

		# Exit if the player looks more than 45 degrees away from the terminal
		if active_terminal:
			var dir_to_terminal := cam.global_position.direction_to(active_terminal.global_position)
			var camera_forward := -cam.global_transform.basis.z

			if rad_to_deg(camera_forward.angle_to(dir_to_terminal)) > 45.0:
				exit_terminal_mode()
				return

		# Press Interact again, or Esc, to leave the keypad
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_cancel"):
			exit_terminal_mode()
			return

	# Move the flashlight update ABOVE the terminal return block
	# so it keeps rendering and swaying while looking at the keypad!
	update_flashlight(delta)

	if is_in_terminal_mode:
		return # Now it safely blocks zooming/interacting without breaking the flashlight

	if Input.is_action_just_pressed("flashlight"):
		flashlight.visible = !flashlight.visible
		if omni_light_3d:
			omni_light_3d.visible = flashlight.visible

	# --- 1. DYNAMIC REACH FIX ---
	# Get the up/down look angle (pitch).
	# Looking forward is 0, looking straight down is roughly -PI/2 (-1.57 radians).
	var look_pitch: float = interact_shapecast.global_rotation.x
	# Calculate how far down we are looking (0.0 = forward, 1.0 = straight down)
	var down_weight: float = clamp(-look_pitch / (PI / 2.0), 0.0, 1.0)
	# Extend the Z length of the target_position based on our look angle
	var current_reach: float = lerp(base_reach, floor_reach, down_weight)
	interact_shapecast.target_position = Vector3(0, 0, -current_reach)
	# Optional: Force update if you need the cast to reflect the new length immediately
	# interact_shapecast.force_shapecast_update()

	# --- 2. INTERACTION LOGIC ---
	current_interactable = get_interactable_component_at_shapecast()
	if current_interactable:
		# Get the hit point. (See the note below on why index 0 might be tricky!)
		var hit_point: Vector3 = interact_shapecast.get_collision_point(0)

		# 2. Send the player AND the hit point to the rope's component
		current_interactable.hover_cursor(self , hit_point)

	if Input.is_action_just_pressed("interact"):
		if held_object:
			held_object.drop()
			held_object = null
			if weapon_holder:
				weapon_holder.show()

		elif current_interactable:
			current_interactable.interact_with(self )
			var parent_node: Node = current_interactable.get_parent()

			if parent_node is PickableObject:
				held_object = parent_node as PickableObject
				held_object.pick_up(hold_position, self )

				if weapon_holder:
					weapon_holder.hide()

	if Input.is_action_just_pressed("zoom"):
		Events.player_zoomed.emit(true)
		is_using_zoom = true
	elif Input.is_action_just_released("zoom"):
		Events.player_zoomed.emit(false)
		is_using_zoom = false

	if Input.is_action_pressed("zoom"):
		target_fov = zoom_fov
		mouse_sensitivity = mouse_sensitivity_zoom
	elif sprint_active and input_dir.length() > 0.1 and not is_swimming:
		target_fov = sprint_fov
		mouse_sensitivity = mouse_sensitivity_base
	else:
		target_fov = base_fov
		mouse_sensitivity = mouse_sensitivity_base

	cam.fov = lerpf(cam.fov, target_fov, delta * fov_change_speed)

func update_flashlight(delta: float) -> void:
	var target_pos: Vector3 = default_flashlight_pos
	var light_intensity: float = head_bobbing_current_intensity

	# Flashlight bobs exactly like the head (synced)
	target_pos.x += sin(head_bobbing_index / 2.0) * (light_intensity * 1.5)
	target_pos.y += sin(head_bobbing_index) * light_intensity

	# Smooth the positional movement and rotation (Sway/Lag)
	flash_light_node.position = flash_light_node.position.lerp(target_pos, delta * flashlight_position_smoothness)

	# Calculate target rotation for sway (when looking around)
	var max_sway: float = 150.0
	sway_target.x = clampf(sway_target.x, -max_sway, max_sway)
	sway_target.y = clampf(sway_target.y, -max_sway, max_sway)

	# Adjusted the multiplier to make the sway noticeable
	var target_rot := Vector3(
		sway_target.y * (sway_amount * 0.0015),
		sway_target.x * (sway_amount * 0.0015),
		0.0
	)
	# Move the flashlight towards the target
	flash_light_node.rotation = flash_light_node.rotation.lerp(target_rot, delta * flashlight_rotation_smoothness)

	# Recover the target back to zero much slower than the node rotates.
	# This creates that natural heavy "lag and catch-up" feeling.
	sway_target = sway_target.lerp(Vector2.ZERO, delta * (smooth_speed * 0.5))

	# ---------------------------------------------------------
	# --- THE TRUE AAA FLASHLIGHT (PUSH-BACK TRICK) ---
	# ---------------------------------------------------------
	if flashlight.visible:
		var space_state := get_world_3d().direct_space_state
		var forward_dir := -cam.global_transform.basis.z

		# Raycast forward 1.5 meters
		var ray_start := cam.global_position
		var ray_end := ray_start + (forward_dir * flashlight_maintain_distance)

		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.exclude = [ self.get_rid()]
		query.hit_from_inside = false
		var result := space_state.intersect_ray(query)

		if result:
			var distance_to_wall: float = ray_start.distance_to(result.position)

			# 1. Base Push-Back: Slide it backward to keep it at exactly 1.5m virtual distance
			var base_push_back: float = flashlight_maintain_distance - distance_to_wall

			# 2. The 25% Growth: Push it back slightly further as you get closer!
			var proximity: float = clampf(1.0 - (distance_to_wall / flashlight_maintain_distance), 0.0, 1.0)
			var extra_growth_push: float = (flashlight_maintain_distance * 0.25) * proximity

			var final_push_back: float = base_push_back + extra_growth_push

			# 3. Apply the movement (+Z is backward in Godot local space)
			flashlight.position.z = lerpf(flashlight.position.z, final_push_back, delta * 15.0)
		else:
			# No wall nearby, smoothly return the flashlight to the camera
			flashlight.position.z = lerpf(flashlight.position.z, 0.0, delta * 15.0)
		
		apply_instability(delta)
		
func get_interactable_component_at_shapecast() -> Interact_Component:
	var closest_comp: Interact_Component = null
	var closest_dist: float = INF
	var cast_origin: Vector3 = interact_shapecast.global_position

	for i: int in interact_shapecast.get_collision_count():
		var collider: Object = interact_shapecast.get_collider(i)

		if not is_instance_valid(collider) or collider == self:
			continue

		if collider is Node:
			var comp: Node = collider.get_node_or_null("Interact_Component")
			if comp is Interact_Component:
				# ---------------------------------------------------------
				# NEW: HEAVY BOX ANTI-STAND CHECK
				# ---------------------------------------------------------
				# We use has_method so we don't crash if the collider 
				# is a door or switch that doesn't have this function.
				if collider.has_method("is_valid_pickup_position"):
					# Assuming 'self' is the player script calling this
					if not collider.is_valid_pickup_position(self):
						continue 
				# ---------------------------------------------------------
				# Calculate how far away THIS specific hit point is
				var hit_point: Vector3 = interact_shapecast.get_collision_point(i)
				var dist: float = cast_origin.distance_squared_to(hit_point)

				# Only keep it if it's the closest one we've found so far
				if dist < closest_dist:
					closest_dist = dist
					closest_comp = comp

	return closest_comp

func enter_ladder() -> void:
	on_ladder = true

func exit_ladder() -> void:
	on_ladder = false

# --------------------------------------
# MONKE BARS
# --------------------------------------
func enter_monkey_bars(volume_node: Node3D) -> void:
	if on_monkey_bars and current_monkey_bar_volume == volume_node:
		return

	if not on_monkey_bars and is_on_floor() and velocity.y <= 0:
		return

	var was_already_on_bars: bool = on_monkey_bars

	on_monkey_bars = true
	current_monkey_bar_volume = volume_node

	if not was_already_on_bars:
		velocity.y = 0

func exit_monkey_bars(volume_node: Node3D = null) -> void:
	if not on_monkey_bars: return

	if volume_node != null and volume_node != current_monkey_bar_volume:
		return

	on_monkey_bars = false
	current_monkey_bar_volume = null

	if camera_anims:
		camera_anims.play("RESET", 0.3)
		camera_anims.speed_scale = 1.0

	velocity.y = -2.0

	monkey_bar_cooldown = 0.5

func _handle_monkey_bars_physics(_delta: float) -> void:
	sprinting = false
	crouching = false

	var look_dir: Vector3 = - cam.global_transform.basis.z
	var right_dir: Vector3 = cam.global_transform.basis.x
	look_dir.y = 0.0; right_dir.y = 0.0
	look_dir = look_dir.normalized(); right_dir = right_dir.normalized()

	var bar_vel: Vector3 = (look_dir * -input_dir.y) + (right_dir * input_dir.x)
	velocity.x = bar_vel.x * MONKEY_BAR_SPEED
	velocity.z = bar_vel.z * MONKEY_BAR_SPEED

	# <-- SYNC VARIABLES HERE
	current_speed = MONKEY_BAR_SPEED
	var flat_vel: Vector3 = Vector3(velocity.x, 0, velocity.z)
	if flat_vel.length() > 0:
		direction = flat_vel.normalized()

	# (The rest of your monkey bar volume pulling/animation code stays the same)
	if current_monkey_bar_volume and is_instance_valid(current_monkey_bar_volume):
		# ...
		# THE FIX: Area3Ds don't have a "size", so we just use the Area's center point
		var target_y: float = current_monkey_bar_volume.global_position.y - MONKEY_BAR_HANG_OFFSET
		var distance_to_target: float = target_y - global_position.y

		if absf(distance_to_target) > 4.0:
			exit_monkey_bars()
			return

		var pull_speed: float = distance_to_target * 12.0
		velocity.y = clampf(pull_speed, -6.0, 6.0)
	else:
		exit_monkey_bars()

	if input_dir.length() > 0.1:
		if camera_anims.current_animation != "MonkeMoves":
			camera_anims.play("MonkeMoves", 0.3)
		camera_anims.speed_scale = 1.0 if input_dir.y < 0 else -1.0
	else:
		if camera_anims.current_animation == "MonkeMoves":
			camera_anims.play("RESET", 0.3)
			camera_anims.speed_scale = 1.0

	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch"):
		exit_monkey_bars()

# --------------------------------------
# ROPES
# --------------------------------------
var on_rope: bool = false
func _on_rope_grabbed(rope_body: RigidBody3D) -> void:
	current_rope = rope_body

	var rope_root: Node3D = current_rope.get_parent() as Node3D
	var can_swing: bool = rope_root.get("is_swingable") as bool if "is_swingable" in rope_root else false

	# --- Momentum Transfer ---
	if can_swing:
		var entry_momentum := Vector3(velocity.x, velocity.y * 0.2, velocity.z)
		current_rope.apply_impulse(entry_momentum * 1.5, global_position - current_rope.global_position)

	# Safely lock the player
	velocity = Vector3.ZERO
	add_collision_exception_with(current_rope)
	on_rope = true
	rope_lerp_weight = 4.0

	# Calculate starting vertical offset
	var local_pos: Vector3 = current_rope.to_local(global_position)
	rope_offset = local_pos.y

	# Clamp the initial grab so you don't grab above or below the rope limits
	var local_top: float = current_rope.to_local(rope_root.global_position).y
	var max_length: float = rope_root.get("rope_length") as float if "rope_length" in rope_root else 10.0
	var top_limit: float = local_top - 2.5
	var bottom_limit: float = local_top - max_length + 0.5
	rope_offset = clampf(rope_offset, bottom_limit, top_limit)

	# Smoothly turn the camera to face the rope exactly when you grab it
	var face_pos := Vector3(current_rope.global_position.x, global_position.y, current_rope.global_position.z)
	if global_position.distance_to(face_pos) > 0.1:
		var target_transform := global_transform.looking_at(face_pos, Vector3.UP)
		var tween := create_tween()
		tween.tween_property(self , "quaternion", target_transform.basis.get_rotation_quaternion(), 0.3).set_trans(Tween.TRANS_SINE)

func _on_rope_released(target_forward: Vector3 = Vector3.ZERO) -> void:
	if current_rope:
		# Restore collision BEFORE clearing variables
		remove_collision_exception_with(current_rope)

		if current_rope.get_parent().has_method("on_player_released"):
			current_rope.get_parent().call("on_player_released")

	current_rope = null
	on_rope = false

	var release_forward: Vector3
	if target_forward != Vector3.ZERO:
		release_forward = Vector3(target_forward.x, 0.0, target_forward.z).normalized()
	else:
		release_forward = Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z).normalized()

	if release_forward.length_squared() < 0.001:
		release_forward = - global_transform.basis.z

	var target_basis := Basis.looking_at(release_forward, Vector3.UP)
	var release_tween := create_tween().set_parallel(true)

	release_tween.tween_property(self , "quaternion", target_basis.get_rotation_quaternion(), 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	release_tween.tween_property(eyes, "rotation", Vector3.ZERO, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ----------------------------
# WATER MECHANICS
# -----------------------------
func _handle_water_physics(delta: float) -> bool:
	if flying:
		if head_in_water:
			head_in_water = false
			# This will play your cinematic wipe animation as if you just surfaced
			screen_water_ui.hide()

		return false

	# 1. Faster check: only true if the detector is inside a water area
	var in_water: bool = not overlapping_water_areas.is_empty()

	# 2. Only do the expensive "head in water" check if we are actually in water
	var chest_in_water: bool = false
	was_head_in_water = head_in_water
	head_in_water = false

	if in_water:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var query := PhysicsPointQueryParameters3D.new()
		query.collide_with_areas = true
		query.collide_with_bodies = false

		# --- CHECK HEAD ---
		query.position = cam.global_position - Vector3(0.0, 0.2, 0.0)
		var head_results: Array[Dictionary] = space_state.intersect_point(query)
		for result: Dictionary in head_results:
			var collider: Object = result.get("collider")
			if collider is Area3D and collider.is_in_group("water_area"):
				head_in_water = true
				break

		# --- CHECK CHEST ---
		# We check 1 meter below the camera to see if the body is submerged
		query.position = cam.global_position - Vector3(0.0, 1.0, 0.0)
		var chest_results: Array[Dictionary] = space_state.intersect_point(query)
		for result: Dictionary in chest_results:
			var collider: Object = result.get("collider")
			if collider is Area3D and collider.is_in_group("water_area"):
				chest_in_water = true
				break

	var target_energy: float = base_light_energy * 4.0 if head_in_water else base_light_energy
	var target_range: float = base_spot_range * 2.0 if head_in_water else base_spot_range

	if flashlight:
		flashlight.light_energy = lerpf(flashlight.light_energy, target_energy, 4.0 * delta)
		flashlight.spot_range = lerpf(flashlight.spot_range, target_range, 4.0 * delta)

	if not in_water:
		# Clean up swimming states if we just left the water
		if swimming:
			swimming = false
			# Reset anything else needed here
		return false

	walking = false
	sprinting = false
	crouching = false
	sprint_active = false
	flying = false
	swimming = true

	standing_collision_shape.disabled = false
	crouching_collision_shape.disabled = true
	head.position.y = lerpf(head.position.y, 1.8, delta * lerp_speed)

	input_dir = Input.get_vector("left", "right", "forward", "backward")
	var swim_dir: Vector3 = (cam.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var target_velocity: Vector3 = swim_dir * swimming_speed

	var actively_swimming_vertical: bool = false
	var just_water_jumped: bool = false

	# 1. Attempt to climb/vault out of the water
	if Input.is_action_just_pressed("jump") and not head_in_water:
		if _try_vault():
			actively_swimming_vertical = true
			just_water_jumped = true
			# We successfully grabbed a ledge!

	# 2. If we aren't vaulting, handle normal swimming
	elif Input.is_action_pressed("crouch"):
		target_velocity.y -= swim_up_speed
		actively_swimming_vertical = true

	elif Input.is_action_pressed("jump") or Input.is_action_pressed("sprint"):
		# Allow swimming up if we are underwater or chest-deep to fight the sinking!
		if head_in_water or chest_in_water:
			target_velocity.y += swim_up_speed
			actively_swimming_vertical = true

	if not actively_swimming_vertical:
		if head_in_water:
			# ZONE 3: UNDERWATER
			# The horror pull. You must hold Swim Up to survive.
			target_velocity.y = -1.8

		elif chest_in_water:
			# ZONE 2: THE SURFACE
			# Your chest is in, but your head is out. Safe zone!
			target_velocity.y = 0.0

		else:
			# ZONE 1: ENTERING WATER
			# Shallow water or falling off a ledge.
			if velocity.y < -1.0:
				target_velocity.y = velocity.y # Let momentum carry your plunge!
			else:
				target_velocity.y = -5.0 # Strong downward pull so you quickly submerge

	var target_xz := Vector2(target_velocity.x, target_velocity.z)
	var current_xz := Vector2(velocity.x, velocity.z)
	current_xz = current_xz.lerp(target_xz, 8.0 * delta)
	velocity.x = current_xz.x
	velocity.z = current_xz.y

	if not just_water_jumped:
		velocity.y = lerpf(velocity.y, target_velocity.y, 4.0 * delta)

	var target_anim: String = ""
	if input_dir.x > 0.1:
		target_anim = "swimming_underwater_sideways_right"
		eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(CameraTiltRight * 2), delta * lerp_speed / 3.0)
	elif input_dir.x < -0.1:
		target_anim = "swimming_underwater_sideways_left"
		eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(CameraTiltLeft * 2), delta * lerp_speed / 3.0)
	elif absf(input_dir.y) > 0.1:
		target_anim = "swimming"
		eyes.rotation.z = lerpf(eyes.rotation.z, 0.0, delta * lerp_speed / 3.0)
	elif (Input.is_action_pressed("jump") or Input.is_action_pressed("sprint")) and head_in_water:
		target_anim = "swimming_up"
		eyes.rotation.z = lerpf(eyes.rotation.z, 0.0, delta * lerp_speed / 3.0)
	else:
		target_anim = "RESET"
		eyes.rotation.z = lerpf(eyes.rotation.z, 0.0, delta * lerp_speed / 3.0)

	if target_anim != "" and camera_anims.current_animation != target_anim:
		camera_anims.play(target_anim, 2.0)

	# --- SCREEN EFFECT MANAGER ---
	if head_in_water:
		# We are underwater: keep the screen blurry and wet!
		if not was_head_in_water:
			if water_clear_tween and water_clear_tween.is_valid():
				water_clear_tween.kill() # Stop any wipe animation if we dive back in
			screen_water_ui.show()
			(screen_water_ui.material as ShaderMaterial).set_shader_parameter("clear_progress", 0.0)

	elif was_head_in_water and not head_in_water:
		# We JUST surfaced: Trigger the cinematic wipe!
		_trigger_screen_water_wipe()

	return true

func enter_updraft(strength: float) -> void:
	in_updraft = true
	current_updraft_strength = strength

func exit_updraft() -> void:
	in_updraft = false
	current_updraft_strength = 0.0

func toggle_noclip() -> void:
	walking = false
	sprinting = false
	crouching = false

	flying = !flying
	noclip_speed_multiplier = 8.0

	if flying:
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = true
	else:
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = false
		
		# Reset velocity so you stop instantly
		velocity = Vector3.ZERO 

	Events.noclip_toggled.emit(flying)

func _on_zipline_grabbed(zipline_ref: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	current_zipline = zipline_ref
	zipline_start = start_pos
	zipline_end = end_pos
	zipline_dir = (zipline_end - zipline_start).normalized()
	zipline_length = zipline_start.distance_to(zipline_end)

	on_zipline = true
	zipline_grace_timer = 0.0
	is_zipline_transitioning = true

	var line_vec := zipline_end - zipline_start
	var player_vec := global_position - zipline_start
	var t := player_vec.dot(line_vec) / line_vec.length_squared()
	zipline_progress = clampf(t, 0.0, 1.0)

	var is_start_highest: bool = zipline_start.y > zipline_end.y
	var top_progress: float = 0.0 if is_start_highest else 1.0
	var grabbed_at_top: bool = absf(zipline_progress - top_progress) < 0.10

	is_auto_sliding = grabbed_at_top

	velocity = Vector3.ZERO
	scale = Vector3.ONE

	# --- HANG OFFSET APPLIED HERE ---
	var real_target_pos := zipline_start.lerp(zipline_end, zipline_progress)
	real_target_pos.y -= ZIPLINE_HANG_OFFSET

	var attach_tween := create_tween().set_parallel(true)
	attach_tween.tween_property(self , "global_position", real_target_pos, 0.25).set_trans(Tween.TRANS_SINE)

	if grabbed_at_top:
		var downhill_dir := zipline_dir if is_start_highest else -zipline_dir
		var target_quat := Basis.looking_at(downhill_dir, Vector3.UP).get_rotation_quaternion()
		attach_tween.tween_property(self , "quaternion", target_quat, 0.25).set_trans(Tween.TRANS_SINE)

	attach_tween.set_parallel(false)
	attach_tween.tween_callback(func() -> void:
		is_zipline_transitioning = false
	)

func _on_zipline_released() -> void:
	if current_zipline and current_zipline.has_method("on_player_released"):
		current_zipline.on_player_released()

	on_zipline = false
	current_zipline = null
	is_zipline_transitioning = false
	scale = Vector3.ONE

	# Fix "Standing Up" on release
	var current_fwd := -global_transform.basis.z
	var flat_fwd := Vector3(current_fwd.x, 0, current_fwd.z).normalized()
	if flat_fwd.length_squared() < 0.01: flat_fwd = Vector3.FORWARD

	var upright_basis := Basis.looking_at(flat_fwd, Vector3.UP)

	var detach_tween := create_tween().set_parallel(true)
	detach_tween.tween_property(self , "quaternion", upright_basis.get_rotation_quaternion(), 0.15) \
		.set_trans(Tween.TRANS_SINE)

	# Reset camera shake/tilt
	detach_tween.tween_property(eyes, "rotation:z", 0.0, 0.15)

func _on_debug_menu_toggled(is_open: bool) -> void:
	is_menu_open = is_open

func _handle_ground_physics(delta: float, is_truly_grounded: bool) -> void:
	if Input.is_action_pressed("left"):
		eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(CameraTiltLeft), delta * lerp_speed)
	elif Input.is_action_pressed("right"):
		eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(CameraTiltRight), delta * lerp_speed)
	else:
		eyes.rotation.z = lerpf(eyes.rotation.z, 0.0, delta * lerp_speed)

	if Input.is_action_pressed("crouch") and is_truly_grounded:
		if not crouching:
			Events.player_crouch_changed.emit(true)
		crouching = true
		current_speed = lerpf(current_speed, crouching_speed, delta * lerp_speed)
		head.position.y = lerpf(head.position.y, crouching_depth, delta * lerp_speed)
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false
		walking = false
		sprinting = false

	elif not crouch_cast_check.is_colliding():
		if crouching:
			Events.player_crouch_changed.emit(false)
		crouching = false
		standing_collision_shape.disabled = false
		crouching_collision_shape.disabled = true
		head.position.y = lerpf(head.position.y, 1.8, delta * lerp_speed)

	var is_moving: bool = input_dir.length() > 0.1

	if Input.is_action_pressed("sprint") and standing_collision_shape.disabled == false and is_moving and is_on_floor() and can_sprint:
		sprint_active = true
	else:
		sprint_active = false

	if sprint_active:
		current_speed = lerpf(current_speed, sprinting_speed, delta * lerp_speed)
		walking = false
		sprinting = true
	elif is_moving and crouching_collision_shape.disabled == true:
		# --- NEW: Check if we are lifting something heavy ---
		if is_heavy_lifting:
			current_speed = lerpf(current_speed, crouching_speed, delta * lerp_speed)
		else:
			current_speed = lerpf(current_speed, walking_speed, delta * lerp_speed)
		# ----------------------------------------------------
		walking = true
		sprinting = false

	_handle_headbob(delta)

	if Input.is_action_just_pressed("jump"):
		# --- NEW: Quick-release the box instead of jumping! ---
		if is_heavy_lifting and held_object:
			held_object.drop()
		# ------------------------------------------------------
		elif _try_vault():
			camera_anims.play("jump")
		elif is_on_floor():
			if sprinting:
				velocity.y = sprint_jump_velocity
			elif crouching:
				velocity.y = crouch_jump_velocity
			else:
				velocity.y = jump_velocity
			camera_anims.play("jump")

	if is_on_floor():
		coyote_timer = coyote_time_duration
	else:
		coyote_timer -= delta

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_duration
	else:
		jump_buffer_timer -= delta
	# -----------------------------------------------

	# --- REFACTORED: Buffered & Coyote Jump Logic ---
	if jump_buffer_timer > 0.0:
		if is_heavy_lifting and held_object:
			held_object.drop()
			jump_buffer_timer = 0.0 # Consume input
		elif _try_vault():
			camera_anims.play("jump")
			jump_buffer_timer = 0.0 # Consume input
			coyote_timer = 0.0 # Consume floor state
		elif coyote_timer > 0.0:
			if sprinting:
				velocity.y = sprint_jump_velocity
			elif crouching:
				velocity.y = crouch_jump_velocity
			else:
				velocity.y = jump_velocity
			camera_anims.play("jump")

			# Consume both timers to prevent double-jumping
			jump_buffer_timer = 0.0
			coyote_timer = 0.0

	if is_on_floor() and not _snapped_to_stairs_last_frame:
		if last_velocity.y < -2.0:
			if sprinting:
				camera_anims.play("jump_landing")
			else:
				camera_anims.play("landing")

	if is_on_floor():
		direction = direction.lerp((transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * lerp_speed)
	else:
		if input_dir != Vector2.ZERO:
			direction = direction.lerp((transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta * air_lerp_speed)

	if direction.length() > 0:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)

	if in_updraft:
		velocity.y = lerpf(velocity.y, current_updraft_strength, delta * 4.0)
	elif not is_on_floor():
		if velocity.y < 0.0:
			# Falling: Apply heavier gravity
			velocity.y -= gravity * fall_gravity_multiplier * delta
		else:
			# Rising: Apply standard gravity
			velocity.y -= gravity * delta

func _handle_ladder_physics(_delta: float) -> void:
	sprinting = false
	crouching = Input.is_action_pressed("crouch")

	var look_dir: Vector3 = - cam.global_transform.basis.z
	var right_dir: Vector3 = cam.global_transform.basis.x

	if Input.is_action_pressed("crouch"):
		velocity = Vector3.DOWN * sprinting_speed
		current_speed = sprinting_speed # <-- SYNC
	else:
		var ladder_vel: Vector3 = (look_dir * -input_dir.y) + (right_dir * input_dir.x)
		velocity = ladder_vel.normalized() * LADDER_SPEED
		current_speed = LADDER_SPEED # <-- SYNC

	# <-- SYNC DIRECTION SO GROUND PHYSICS DOESN'T DEAD-STOP YOU
	var flat_vel: Vector3 = Vector3(velocity.x, 0, velocity.z)
	if flat_vel.length() > 0:
		direction = flat_vel.normalized()

	# (Your jump logic remains exactly the same below)
	if Input.is_action_just_pressed("jump"):
		on_ladder = false
		var jump_back_dir: Vector3 = cam.global_transform.basis.z
		jump_back_dir.y = 0
		velocity = jump_back_dir.normalized() * 5.0
		velocity.y = 5.0

		# Optional: Sync jump off too just to be pristine
		direction = Vector3(velocity.x, 0, velocity.z).normalized()
		current_speed = 5.0

func _handle_zipline_physics(delta: float) -> void:
	if not on_zipline or is_zipline_transitioning:
		return

	zipline_grace_timer += delta

	sprinting = false
	crouching = false
	walking = false

	var downhill_sign := 1.0 if zipline_dir.y < 0 else -1.0
	var downhill_vector := zipline_dir * downhill_sign

	var look_forward := -cam.global_transform.basis.z
	var look_dot_downhill := look_forward.dot(downhill_vector)

	var is_looking_downhill: bool = look_dot_downhill > 0.1
	var is_looking_uphill: bool = look_dot_downhill < -0.1

	var is_pressing_w: bool = input_dir.y < -0.1
	var is_pressing_s: bool = input_dir.y > 0.1

	var frame_movement: float = 0.0

	if is_auto_sliding:
		var fast_slide_speed := ZIPLINE_SLIDE_SPEED * 1.8
		frame_movement = downhill_sign * (fast_slide_speed / zipline_length) * delta
	else:
		if is_looking_downhill and is_pressing_w:
			is_auto_sliding = true
		else:
			var climb_speed := 4.0
			var climb_amount := (climb_speed / zipline_length) * delta

			if is_looking_uphill and is_pressing_w:
				frame_movement = - downhill_sign * climb_amount
			elif is_looking_downhill and is_pressing_s:
				frame_movement = - downhill_sign * climb_amount
			elif is_looking_uphill and is_pressing_s:
				frame_movement = downhill_sign * climb_amount

	zipline_progress += frame_movement
	zipline_progress = clampf(zipline_progress, 0.0, 1.0)

	# --- HANG OFFSET APPLIED HERE ---
	var target_pos: Vector3 = zipline_start.lerp(zipline_end, zipline_progress)
	target_pos.y -= ZIPLINE_HANG_OFFSET

	global_position = target_pos
	velocity = Vector3.ZERO

	_handle_headbob(delta)

	if zipline_grace_timer > 0.5:
		if zipline_progress >= 0.999 or zipline_progress <= 0.001:
			_on_zipline_released()

	if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("crouch"):
		_on_zipline_released()

func _handle_rope_physics(delta: float) -> void:
	sprinting = false
	crouching = false
	walking = false

	# 1. SETUP & REUSE VARIABLES
	var rope_root: Node3D = current_rope.get_parent() as Node3D
	var rope_up: Vector3 = current_rope.global_transform.basis.y.normalized()
	var look_dir := -cam.global_transform.basis.z

	# Common Calculations
	var center_grab_pos: Vector3 = current_rope.to_global(Vector3(0.0, rope_offset, 0.0))
	var look_dot_rope: float = look_dir.dot(rope_up)

	# Logic Flags
	var can_swing: bool = rope_root.get("is_swingable") as bool if "is_swingable" in rope_root else false
	var force_amount: float = rope_root.get("swing_force") as float if "swing_force" in rope_root else 300.0
	var swing_angle_deg: float = rad_to_deg(acos(clampf(rope_up.dot(Vector3.UP), -1.0, 1.0)))
	var is_actively_swinging: bool = swing_angle_deg > 5.0 or current_rope.angular_velocity.length() > 0.2

	var is_pressing_w: bool = input_dir.y < -0.1
	var is_pressing_s: bool = input_dir.y > 0.1
	var is_looking_up: bool = look_dot_rope > 0.6
	var is_looking_down: bool = look_dot_rope < -0.2
	var is_sliding: bool = Input.is_action_pressed("crouch") and is_looking_down

	var intent_is_climbing: bool = false
	var climb_direction: float = 0.0

	# --- CLIMBING LOGIC ---
	if not is_sliding:
		if is_looking_up:
			if is_pressing_w:
				intent_is_climbing = true
				climb_direction = 1.0
			elif is_pressing_s and not is_actively_swinging:
				intent_is_climbing = true
				climb_direction = -1.0
		elif is_looking_down:
			if is_pressing_w and not is_actively_swinging:
				intent_is_climbing = true
				climb_direction = -1.0

	var is_climbing_actively: bool = false
	var local_top: float = current_rope.to_local(rope_root.global_position).y
	var max_length: float = rope_root.get("rope_length") as float if "rope_length" in rope_root else 10.0
	var top_limit: float = local_top - 2.5
	var bottom_limit: float = local_top - max_length + 0.5

	if is_sliding:
		rope_offset -= (ROPE_CLIMB_SPEED * 7.0) * delta
		rope_offset = clampf(rope_offset, bottom_limit, top_limit)
	elif intent_is_climbing:
		rope_offset += climb_direction * ROPE_CLIMB_SPEED * delta
		rope_offset = clampf(rope_offset, bottom_limit, top_limit)
		is_climbing_actively = true
	else:
		# --- SWINGING LOGIC ---
		if can_swing and input_dir.length() > 0.01:
			current_rope.sleeping = false
			var flat_fwd := Vector3(look_dir.x, 0.0, look_dir.z).normalized()
			var flat_right := flat_fwd.cross(Vector3.UP).normalized()
			var push_dir := (flat_fwd * -input_dir.y) + (flat_right * input_dir.x)

			if push_dir.length_squared() > 0.01:
				current_rope.apply_force(push_dir.normalized() * force_amount, center_grab_pos - current_rope.global_position)

	if is_climbing_actively:
		if has_method("_handle_headbob"):
			_handle_headbob(delta, 0.6)
	else:
		cam.transform.origin = cam.transform.origin.lerp(Vector3.ZERO, delta * 10.0)
	# -------------------------------------------

	# --- APPLY POSITIONS & COMFORT ---
	var cam_fwd := -cam.global_transform.basis.z.normalized()
	var cam_right := -cam.global_transform.basis.x.normalized()

	var orbit_fwd := Vector3(cam_fwd.x, 0, cam_fwd.z).normalized()
	var orbit_right := Vector3(cam_right.x, 0, cam_right.z).normalized()

	var target_pos: Vector3
	if can_swing:
		# Move backward and LEFT so the swingable rope is on your RIGHT
		target_pos = center_grab_pos - (orbit_fwd * 0.7) + (orbit_right * 0.5)
	else:
		# Static rope: strictly locked in the middle
		target_pos = center_grab_pos - (orbit_fwd * 0.2)

	if rope_lerp_weight < 45.0:
		rope_lerp_weight += delta * 150.0
		global_position = global_position.lerp(target_pos, delta * 15.0)
	else:
		global_position = target_pos

	global_rotation.x = 0.0
	global_rotation.z = 0.0

	var tilt_quat := Quaternion(Vector3.UP, rope_up)
	eyes.quaternion = Quaternion.IDENTITY.slerp(tilt_quat, 0.15)

	velocity = Vector3.ZERO

	# --- DISMOUNTS ---
	if Input.is_action_just_pressed("jump"):
		var grab_offset: Vector3 = global_position - current_rope.global_position
		var rope_momentum: Vector3 = current_rope.angular_velocity.cross(grab_offset)
		var jump_dir := -cam.global_transform.basis.z.normalized()
		var flat_jump_dir := Vector3(jump_dir.x, 0.0, jump_dir.z).normalized()

		var vertical_hop: float = 0.0
		var forward_push: float = 0.0

		if can_swing and input_dir.length() > 0.1:
			current_rope.apply_impulse(-flat_jump_dir * 12.0, Vector3.ZERO)

			var directional_momentum: float = rope_momentum.dot(jump_dir)
			var swing_boost: float = maxf(0.0, directional_momentum)
			var camera_lift: float = maxf(jump_dir.y, 0.0) * 2.5

			vertical_hop = 5.0 + camera_lift + (swing_boost * 0.4)
			forward_push = 8.0 + (swing_boost * 2.5)
		else:
			vertical_hop = 4.5
			forward_push = 7.0

		_on_rope_released(jump_dir)

		velocity = (flat_jump_dir * forward_push) + Vector3(0, vertical_hop, 0)
		direction = flat_jump_dir
		current_speed = forward_push
		global_position += jump_dir * 0.5

	elif Input.is_action_just_pressed("interact"):
		if rope_lerp_weight > 10.0:
			_on_rope_released(-cam.global_transform.basis.z)

func _handle_noclip_physics(delta: float) -> void:
	# 1. Get the base movement from your WASD input, relative to the camera
	var fly_dir: Vector3 = cam.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)

	# 2. Get vertical input (assuming "crouch" is CTRL and "jump" is SPACE)
	# This returns 1 if only jump is pressed, -1 if crouch is pressed, or 0 if neither/both.
	var vertical_input: float = Input.get_axis("crouch", "jump")

	# 3. Add the vertical input to the global up direction
	fly_dir += Vector3.UP * vertical_input

	# 4. Normalize after adding vertical input to keep speed consistent diagonally
	fly_dir = fly_dir.normalized()

	current_speed = sprinting_speed * noclip_speed_multiplier

	Events.noclip_speed_changed.emit(noclip_speed_multiplier)

	if fly_dir.length() > 0:
		velocity = fly_dir * current_speed
	else:
		velocity = Vector3.ZERO
		direction = Vector3.ZERO

	if not swimming:
		if Input.is_action_pressed("left"):
			eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(CameraTiltLeft), delta * lerp_speed)
		elif Input.is_action_pressed("right"):
			eyes.rotation.z = lerpf(eyes.rotation.z, deg_to_rad(CameraTiltRight), delta * lerp_speed)
		else:
			eyes.rotation.z = lerpf(eyes.rotation.z, 0.0, delta * lerp_speed)

func _handle_headbob(delta: float, intensity_modifier: float = 1.0) -> void:
	var is_climbing_rope: bool = (current_rope != null)
	var is_zipline_moving: bool = (on_zipline and not is_auto_sliding and absf(input_dir.y) > 0.1)

	# Calculate how fast to increment the bob index based on state
	var bob_speed: float = head_bobbing_idle_speed
	if is_climbing_rope:
		bob_speed = 12.6 # Standardized rope speed
		head_bobbing_current_intensity = head_bobbing_walking_intensity * 1.5
	elif is_zipline_moving:
		bob_speed = 6.0
		head_bobbing_current_intensity = head_bobbing_walking_intensity
	elif sprinting and input_dir != Vector2.ZERO:
		bob_speed = head_bobbing_sprinting_speed
		head_bobbing_current_intensity = head_bobbing_sprinting_intensity
	elif walking and input_dir != Vector2.ZERO:
		bob_speed = head_bobbing_walking_speed
		head_bobbing_current_intensity = head_bobbing_walking_intensity
	elif crouching and input_dir != Vector2.ZERO:
		bob_speed = head_bobbing_crouching_speed
		head_bobbing_current_intensity = head_bobbing_crouching_intensity
	else:
		head_bobbing_current_intensity = head_bobbing_idle_intensity

	# Increment the shared timer
	head_bobbing_index += bob_speed * delta * (1.0 if input_dir.length() > 0.1 or is_zipline_moving or is_climbing_rope else 0.5)

	# Calculate actual offsets (Sine waves)
	# Vector2(X = Side-to-Side, Y = Up-and-Down)
	var target_bob_y: float = sin(head_bobbing_index) * (head_bobbing_current_intensity / 2.0) * intensity_modifier
	var target_bob_x: float = sin(head_bobbing_index / 2.0) * head_bobbing_current_intensity * intensity_modifier

	# Smooth the transition to the new bob position
	headbob_offset.y = lerpf(headbob_offset.y, target_bob_y, delta * lerp_speed)
	headbob_offset.x = lerpf(headbob_offset.x, target_bob_x, delta * lerp_speed)

	# Apply to camera container (Eyes)
	eyes.position.y = headbob_offset.y + stair_offset
	eyes.position.x = headbob_offset.x

var _stun_tween: Tween

func teleport_to(new_position: Vector3, stun_time: float = 0.1) -> void:
	global_position = new_position

	velocity = Vector3.ZERO
	last_velocity = Vector3.ZERO
	direction = Vector3.ZERO
	input_dir = Vector2.ZERO

	# 1. Cancel any existing stun timers immediately
	if _stun_tween and _stun_tween.is_valid():
		_stun_tween.kill()

	# 2. Handle zero stun time instantly
	if stun_time <= 0.0:
		is_stunned = false
		return

	# 3. Apply stun and create a safe, trackable delay
	is_stunned = true
	_stun_tween = create_tween()
	_stun_tween.tween_interval(stun_time)
	_stun_tween.tween_callback(func() -> void: is_stunned = false)

func toggle_pause() -> void:
	is_paused = !is_paused

	get_tree().paused = is_paused

	if is_paused:
		menu_instance.show()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		menu_instance.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _scan_for_ledges() -> void:
	# 1. Reset state upfront
	can_vault_current_ledge = false
	if vault_indicator:
		vault_indicator.hide()

	var space_state := get_world_3d().direct_space_state

	# Speed Optimization: Cache the RID array once per frame
	var exclude_rids := [get_rid()]

	var forward_dir := -cam.global_transform.basis.z
	forward_dir.y = 0.0
	forward_dir = forward_dir.normalized()

	# --- FORWARD CAST (Find Wall) ---
	var detect_start := global_position + Vector3(0, 0.5, 0)
	var forward_query := PhysicsRayQueryParameters3D.create(detect_start, detect_start + forward_dir * 1.2)
	forward_query.exclude = exclude_rids

	var forward_result := space_state.intersect_ray(forward_query)

	# Guard Clause: Abort if we didn't hit a wall
	if forward_result.is_empty():
		return

	var wall_normal: Vector3 = forward_result["normal"]
	# Guard Clause: Abort if the wall is sloped (not vertical enough)
	if absf(wall_normal.y) > 0.2:
		return

	# --- DOWNWARD CAST (Find Ledge) ---
	var wall_hit: Vector3 = forward_result["position"]
	var down_start := wall_hit - (wall_normal * 0.15) + Vector3(0, 2.0, 0)

	var down_query := PhysicsRayQueryParameters3D.create(down_start, down_start + Vector3(0, -2.5, 0))
	down_query.exclude = exclude_rids

	var down_result := space_state.intersect_ray(down_query)

	# Guard Clause: Abort if there is no top surface
	if down_result.is_empty():
		return

	var ledge_point: Vector3 = down_result["position"]
	var vault_height := ledge_point.y - global_position.y

	# Guard Clause: Abort if ledge is too high or too low
	if vault_height <= MAX_STEP_HEIGHT or vault_height > 1.8:
		return

	# --- CLEARANCE CAST (Headroom Check) ---
	var clearance_start := ledge_point + (forward_dir * 0.15) + Vector3(0, 0.05, 0)
	var clearance_end := clearance_start + Vector3(0, 1.8, 0)
	var clearance_query := PhysicsRayQueryParameters3D.create(clearance_start, clearance_end)
	clearance_query.exclude = exclude_rids

	var requires_crouch := false
	var clearance_result := space_state.intersect_ray(clearance_query)

	if not clearance_result.is_empty():
		var hit_height: float = clearance_result["position"].y - ledge_point.y
		# Guard Clause: Abort if the gap is smaller than 0.9m
		if hit_height < 0.9:
			return

		# Gap is between 0.9m and 1.8m
		requires_crouch = true

	# --- SUCCESS ---
	# We passed all checks. Save parameters.
	can_vault_current_ledge = true
	current_ledge_point = ledge_point
	current_vault_height = vault_height
	current_vault_requires_crouch = requires_crouch

	# UI Indicator Logic
	if vault_height > 1.6 and vault_indicator:
		var exact_edge := wall_hit
		exact_edge.y = ledge_point.y + 0.03
		exact_edge += wall_normal * 0.05

		vault_indicator.global_position = exact_edge
		vault_indicator.show()

func _try_vault() -> bool:
	if can_vault_current_ledge:
		var forward_dir: Vector3 = - cam.global_transform.basis.z
		forward_dir.y = 0.0
		forward_dir = forward_dir.normalized()

		vault_indicator.hide()
		# PASS THE NEW CROUCH FLAG HERE:
		_perform_vault(current_ledge_point, forward_dir, current_vault_height, current_vault_requires_crouch)
		return true

	return false

func _perform_vault(target_point: Vector3, forward_dir: Vector3, vault_height: float, force_crouch: bool = false) -> void:
	is_vaulting = true
	velocity = Vector3.ZERO

	# We still instantly change the collision shapes so the physics engine
	# lets you through the window, but we removed the instant head snap!
	if force_crouch:
		if not crouching:
			Events.player_crouch_changed.emit(true)
		crouching = true
		standing_collision_shape.disabled = true
		crouching_collision_shape.disabled = false

	var vault_time: float = clampf(vault_height * 0.75, 0.4, 1.5)
	var final_pos: Vector3 = target_point + (forward_dir * 0.2)

	var vault_tween: Tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	vault_tween.set_parallel(true)

	vault_tween.tween_property(self , "global_position:y", final_pos.y + 0.1, vault_time * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	vault_tween.tween_property(self , "global_position", final_pos, vault_time * 0.3).set_trans(Tween.TRANS_LINEAR).set_delay(vault_time * 0.7)

	# --- NEW: Smoothly animate the camera down into the crouch ---
	if force_crouch:
		vault_tween.tween_property(head, "position:y", crouching_depth, vault_time * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var tilt_amount: float = deg_to_rad(5.0)
	vault_tween.tween_property(eyes, "rotation:z", tilt_amount, vault_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	vault_tween.tween_property(eyes, "rotation:z", 0.0, vault_time * 0.5).set_delay(vault_time * 0.5)

	vault_tween.chain().tween_callback(func() -> void:
		is_vaulting = false
		eyes.rotation.z = 0.0
	)

func _on_water_detector_area_entered(area: Area3D) -> void:
	if area.is_in_group("water_area"):
		overlapping_water_areas.append(area)

func _on_water_detector_area_exited(area: Area3D) -> void:
	if area.is_in_group("water_area"):
		overlapping_water_areas.erase(area)

func _trigger_screen_water_wipe() -> void:
	if not screen_water_ui: return

	var mat: ShaderMaterial = screen_water_ui.material as ShaderMaterial
	if not mat: return

	screen_water_ui.show()
	mat.set_shader_parameter("clear_progress", 0.0)

	if water_clear_tween and water_clear_tween.is_valid():
		water_clear_tween.kill()

	water_clear_tween = create_tween()

	# 1. Hold the fully wet screen for 0.5 seconds
	water_clear_tween.tween_interval(0.5)

	# 2. Animate the wipe to 1.0 (dry) over 1.5 seconds
	water_clear_tween.tween_property(mat, "shader_parameter/clear_progress", 1.0, 1.5).set_trans(Tween.TRANS_SINE)

	# 3. Hide the UI when it's totally dry
	water_clear_tween.tween_callback(screen_water_ui.hide)


# -----------------------------------------------
# TERMINAL / KEYPAD
# -----------------------------------------------
func enter_terminal_mode(terminal: Node3D) -> void:
	is_in_terminal_mode = true
	active_terminal = terminal
	terminal_start_pos = global_position

	# Just tell the UI to shrink the crosshair!
	Events.terminal_mode_toggled.emit(true)

func exit_terminal_mode() -> void:
	is_in_terminal_mode = false
	active_terminal = null

	# Just tell the UI to restore the crosshair!
	Events.terminal_mode_toggled.emit(false)

func shoot_terminal_raycast(is_click: bool) -> void:
	# Get the exact center of the player's screen (where your 8x8 dot is!)
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_center := viewport_size / 2.0

	# Translate that center point into a 3D laser pointer
	var ray_origin := cam.project_ray_origin(screen_center)
	var ray_normal := cam.project_ray_normal(screen_center)
	var ray_end := ray_origin + ray_normal * 3.0 # 3 meters of reach

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	var space_state := get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)

	# If the laser hits the keypad, send the exact 3D point to it!
	if result and result.collider == active_terminal:
		if is_click:
			active_terminal.inject_mouse_click(result.position)
		else:
			active_terminal.inject_mouse_motion(result.position)

func _check_zipline_collisions() -> void:
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()

		# Prevent crashes if the collider is null
		if not collider:
			continue

		var zipline_node := collider

		# Check if the node has the method, otherwise check its parent
		if not zipline_node.has_method("force_grab_zipline"):
			zipline_node = collider.get_parent()

		# Make sure zipline_node exists before trying to use it
		if zipline_node and zipline_node.has_method("force_grab_zipline"):
			# 1. Did we hit the TOP of the zipline?
			# Godot's Y-axis points DOWN. A surface pointing UP has a negative Y normal.
			var hit_top: bool = collision.get_normal().y < -0.5

			# 2. Were we falling before this collision happened?
			# Positive Y velocity means we are moving DOWN (falling).
			var was_falling: bool = last_velocity.y > 0.0

			# ONLY grab if we landed on top of it while falling
			if hit_top and was_falling:
				zipline_node.force_grab_zipline(self )
				return

func _apply_sensitivity(value: float) -> void:
	mouse_sensitivity_base = value
	mouse_sensitivity = value
	mouse_sensitivity_zoom = value / 10.0

# --------------------------------------
# FAST ROPE
# --------------------------------------
func enter_fast_rope() -> void:
	on_fast_rope = true
	velocity = Vector3.ZERO

	# Drop anything heavy we are holding so it doesn't look weird
	if is_heavy_lifting and held_object:
		held_object.drop()

func exit_fast_rope() -> void:
	on_fast_rope = false

func _handle_fast_rope_physics(delta: float) -> void:
	sprinting = false
	crouching = false
	walking = false

	# Add an aggressive camera shake (headbob) to sell the high-speed ascension!
	_handle_headbob(delta, 1.8)

	# Notice we do NOT apply gravity or call move_and_slide() here.
	# The FastRope Node is taking complete control of our global_position.

func apply_instability(delta: float) -> void:
	# ---------------------------------------------------------
	# 1. ELECTRICAL INSTABILITY (The Failing Bulb)
	# ---------------------------------------------------------
	# Very small chance every frame to trigger a major flicker event
	if not is_flickering and randf() < 0.003: 
		is_flickering = true
		flicker_timer = randf_range(0.1, 0.6) # Flicker lasts a fraction of a second

	if is_flickering:
		flicker_timer -= delta
		# Rapid, aggressive jumps in light energy (looks like failing wiring)
		# Drops low, sometimes spikes a tiny bit higher than base
		flashlight.light_energy = randf_range(2.0, base_energy * 1.1) 
		
		if flicker_timer <= 0.0:
			is_flickering = false
			flashlight.light_energy = base_energy
	else:
		# THE SUBLIMINAL BUZZ: Even when "stable", it's never perfectly 10.0
		# It constantly fluctuates by tiny margins. This creates subconscious tension.
		var micro_fluctuation := randf_range(-0.4, 0.4)
		flashlight.light_energy = lerpf(flashlight.light_energy, base_energy + micro_fluctuation, delta * 20.0)

	# ---------------------------------------------------------
	# 2. PHYSICAL INSTABILITY (The Shaking Hand)
	# ---------------------------------------------------------
	noise_time += delta * 4.0 # Speed of the trembling
	
	# Generate tiny random offsets
	var jitter_x := jitter_noise.get_noise_2d(noise_time, 0.0) * 0.003
	var jitter_y := jitter_noise.get_noise_2d(0.0, noise_time) * 0.003
	
	# Apply directly to the node's rotation
	# Because this runs after your sway lerp, it layers the jitter ON TOP of the smooth movement
	flash_light_node.rotation.x += jitter_x
	flash_light_node.rotation.y += jitter_y

func _on_fullbright_toggled(is_fullbright: bool) -> void:
	# 1. Handle the Environment via the Camera
	if is_fullbright:
		# Override the world graphics with our debug environment
		cam.environment = fullbright_env
	else:
		# Setting it to null instantly restores the global WorldEnvironment!
		cam.environment = null
		
	# 2. Handle the Sun
	# Grab the sun from the group we just made
	var sun := get_tree().get_first_node_in_group("sun") as DirectionalLight3D
	if sun:
		# If fullbright is ON, sun is hidden/disabled. Vice versa.
		sun.visible = not is_fullbright
		sun.shadow_enabled = not is_fullbright
