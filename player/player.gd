class_name Player
extends CharacterBody3D

# --------------------------------------
# EXPORTS (Shared Data for States)
# --------------------------------------
@export_category("Movement Speeds")
@export var walking_speed: float = 5.0
@export var sprinting_speed: float = 6.5
@export var crouching_speed: float = 3.0
@export var swimming_speed: float = 4.0
@export var swim_up_speed: float = 5.0

@export_category("Jump & Gravity")
@export var jump_buffer_duration: float = 0.15
@export var coyote_time_duration: float = 0.15
@export var fall_gravity_multiplier: float = 1.5

@export_category("Physics Lerping")
@export var default_lerp_speed: float = 15.0
@export var air_lerp_speed: float = 3.0
@export var ice_lerp_speed: float = 1.5

@export_category("Physics Properties")
## How heavy the player is (in kg). Essential for weighing down pulley carts and platforms.
@export var player_mass: float = 80.0

# Spam protector for 60 FPS logging
var _last_weighed_body: RigidBody3D = null

# --------------------------------------
# SHARED STATE VARIABLES
# --------------------------------------
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var sprint_active: bool = false
var crouching: bool = false
var can_sprint: bool = true
var on_ice: bool = false

var direction: Vector3 = Vector3.ZERO
var last_velocity: Vector3 = Vector3.ZERO

# Environmental Cooldowns/Detectors
var zipline_cooldown: float = 0.0
var monkey_bar_cooldown: float = 0.0
var available_monkey_bar: Node3D = null
var overlapping_waterfall_areas: Array[Area3D] = []

var in_updraft: bool = false
var updraft_strength: float = 0.0
var updraft_top_y: float = 0.0

var current_water_node: Node3D = null
var flashlight_controller: Node = null

# Item Handling
var held_item: RigidBody3D = null
var throw_strength: float = 15.0

# Tracks only the waterfalls the player is currently touching.
var active_waterfalls: Array[Area3D] = []

var is_operating_machine: bool = false
var ladder_cooldown: float = 0.0
var last_ladder: Node3D = null

# --------------------------------------
# COMPONENT REFERENCES
# --------------------------------------
@onready var state_machine: PlayerStateMachine = $StateMachine
@onready var camera_controller: CameraController = %CameraController
@onready var interaction_scanner: InteractionScanner = $InteractionScanner
@onready var footstep_manager: FootstepManager = $FootstepManager
@onready var vfx_manager: ScreenVFXManager = $ScreenVFXManager
@onready var vault_controller: VaultController = $VaultController
@onready var physics_pusher: PhysicsPusher = $PhysicsPusher
@onready var system_menu: SystemMenuController = $SystemMenuController
@onready var health_component: Node = $HealthComponent
@onready var stair_controller: StairController = $StairController
@onready var smoke_manager: Node = get_node_or_null("/root/SmokeManager")

# --------------------------------------
# NODE REFERENCES
# --------------------------------------
@onready var head: Node3D = $Head
@onready var eyes: Node3D = $Head/Eyes
@onready var camera: Camera3D = $Head/Eyes/Camera3D
@onready var standing_collision: CollisionShape3D = $StandingCollisionShape
@onready var crouching_collision: CollisionShape3D = $CrouchingCollisionShape
@onready var crouch_cast_check: RayCast3D = $CrouchCastCheck

@onready var interact_cast: ShapeCast3D = %InteractShapeCast
@onready var hold_position: Marker3D = $Head/Eyes/Camera3D/SpringArm3D/HoldPosition
@onready var weapon_holder: Node3D = %WeaponHolder

# --------------------------------------
# INITIALIZATION
# --------------------------------------
func _ready() -> void:
	print("Player: _ready() called. Initializing player node.")
	add_to_group("saveable")

	# 1. Connect Health
	if health_component.has_signal("health_changed"):
		health_component.health_changed.connect(_on_health_changed)
	if health_component.has_signal("died"):
		health_component.died.connect(_on_player_died)

	# 2. Add exceptions
	if has_node("Head/Eyes/Camera3D/SpringArm3D"):
		var spring_arm: SpringArm3D = $Head/Eyes/Camera3D/SpringArm3D
		spring_arm.add_excluded_object(self.get_rid())

	# Lock the mouse into the game window!
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Automatically hook up group-based environmental areas
	_connect_waterfall_group()

# --------------------------------------
# HARDWARE INPUT ROUTING
# --------------------------------------
func _input(event: InputEvent) -> void:
	# Route Mouse Look here to bypass GUI swallowing bugs when UI is hidden
	if event is InputEventMouseMotion:
		# Block camera rotation if paused, in a menu, or stunned
		if system_menu.is_paused or system_menu.is_menu_open or system_menu.get("is_stunned"):
			return

		# Only rotate if the mouse is actively captured by the game
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			camera_controller.handle_mouse_input(
				event,
				interaction_scanner.is_in_terminal_mode,
				interaction_scanner.is_heavy_lifting,
				interaction_scanner.heavy_lift_yaw_base
			)

func _unhandled_input(event: InputEvent) -> void:
	# 1. Block all other unhandled inputs if we are paused, in a menu, or stunned
	if system_menu.is_paused or system_menu.is_menu_open or system_menu.get("is_stunned"):
		return
		
	# 2. Item Dropping (Priority over new interactions)
	if event.is_action_pressed("interact") and is_instance_valid(held_item):
		# Specific rule to prevent dropping gliders mid-air
		if held_item is GliderItem and not is_on_floor():
			return
			
		print("Player: Interact action pressed while holding item. Dropping it.")
		_drop_held_item()
		return

	# 3. Item Throwing ('G' or Left Mouse Button)
	if (event.is_action_pressed("grenade_throw") or event.is_action_pressed("shoot")) and is_instance_valid(held_item):
		print("Player: Throw action pressed. Throwing the held physics object.")
		_throw_held_item()
		return

	# 4. Item Pickup (Priority over general interactions)
	if event.is_action_pressed("interact") and not is_instance_valid(held_item):
		if _try_pick_up():
			return # Block scanner if we successfully picked up a physics object

	# 5. Route standard Interactions and Combat to the Scanner
	if event.is_action_pressed("interact"):
		print("Player: Routing interact input to interaction scanner.")
		interaction_scanner.handle_interact_input()

	if event.is_action_pressed("shoot"):
		print("Player: Routing shoot input to interaction scanner.")
		interaction_scanner.handle_shoot_input()

# --------------------------------------
# ITEM HANDLING
# --------------------------------------
func _set_weapon_active(active: bool) -> void:
	print("Player: _set_weapon_active() called. Toggling weapon holder active state to: ", active)
	if is_instance_valid(weapon_holder):
		weapon_holder.visible = active
		weapon_holder.set_process(active)
		weapon_holder.set_physics_process(active)

func _try_pick_up() -> bool:
	print("Player: _try_pick_up() called. Scanning for objects.")
	interact_cast.force_shapecast_update()

	if interact_cast.is_colliding():
		var collision_count: int = interact_cast.get_collision_count()

		for i: int in range(collision_count):
			var collider: Object = interact_cast.get_collider(i)
			print("Player _try_pick_up: Scanning [", i, "] ", collider.name)

			var target_body: Object = collider
			if target_body is Area3D:
				target_body = target_body.get_parent()

			if target_body is RigidBody3D and target_body.has_method("pick_up"):
				print("Player _try_pick_up: Successfully grabbed ", target_body.name, "!")
				held_item = target_body as RigidBody3D

				# Attach it to the visible weapon holder
				held_item.pick_up(hold_position, self)

				# DELETE OR COMMENT OUT THIS LINE:
				# _set_weapon_active(false) 
				
				print("Player: Pick up complete. Keeping weapon holder visible.")
				return true

		print("Player _try_pick_up: Hit objects, but none were grabbable.")
	else:
		print("Player _try_pick_up: Shapecast hit nothing.")

	return false

func _throw_held_item() -> void:
	print("Player: _throw_held_item() called. Throwing held item.")
	var throw_dir: Vector3 = -camera.global_transform.basis.z.normalized()
	throw_dir.y += 0.2
	var throw_force: Vector3 = throw_dir.normalized() * throw_strength

	# Support both standard physics objects and special items
	if held_item.has_method("throw"):
		held_item.throw(throw_force)
	elif held_item.has_method("throw_item"):
		held_item.throw_item(throw_force, get_tree().current_scene)
	
	if held_item is GliderItem:
		print("Player: Threw GliderItem. Restoring ability to sprint.")
		can_sprint = true
		interaction_scanner.is_heavy_lifting = false
		
	held_item = null
	_set_weapon_active(true)

# --------------------------------------
# GLOBAL EVENT ROUTING
# --------------------------------------
func _on_health_changed(new_health: int) -> void:
	print("Player: _on_health_changed() called. Emitting signal with health: ", new_health)
	Events.player_health_changed.emit(new_health)

func _on_player_died() -> void:
	print("Player: _on_player_died() called. Player has died. Triggering game over sequence...")
	# Events.player_died.emit()

# --------------------------------------
# ENVIRONMENTAL TRIGGERS (Called by Area3Ds)
# --------------------------------------
func set_available_monkey_bar(bar: Node3D) -> void:
	if monkey_bar_cooldown <= 0.0:
		print("Player: set_available_monkey_bar() called. Assigning bar: ", bar.name)
		available_monkey_bar = bar

func clear_available_monkey_bar(bar: Node3D) -> void:
	if available_monkey_bar == bar:
		print("Player: clear_available_monkey_bar() called. Clearing bar: ", bar.name)
		available_monkey_bar = null

func teleport_to(new_position: Vector3, stun_time: float = 0.1) -> void:
	print("Player: teleport_to() called. Moving to: ", new_position)
	global_position = new_position
	velocity = Vector3.ZERO
	last_velocity = Vector3.ZERO
	direction = Vector3.ZERO

	if stun_time > 0.0:
		system_menu.is_stunned = true
		get_tree().create_timer(stun_time).timeout.connect(
			func() -> void: system_menu.is_stunned = false
		)

# --------------------------------------
# MASTER PHYSICS OVERRIDE
# --------------------------------------
func _physics_process(delta: float) -> void:
	if zipline_cooldown > 0.0:
		zipline_cooldown -= delta
	if monkey_bar_cooldown > 0.0:
		monkey_bar_cooldown -= delta
		
	if ladder_cooldown > 0.0:
		ladder_cooldown -= delta
		if ladder_cooldown <= 0.0:
			last_ladder = null  # Free the reference once cooldown is over

	# 1. Handle Pauses, Stuns & Machines
	# Added "is_operating_machine" here to lock the player in place
	if system_menu.is_paused or system_menu.is_menu_open or system_menu.get("is_stunned") or is_operating_machine:
		state_machine.set_physics_process(false)
		state_machine.set_process_unhandled_input(false)
		velocity = Vector3.ZERO
		return

	# 2. Handle Noclip (Cheat Mode)
	if system_menu.flying:
		state_machine.set_physics_process(false)
		state_machine.set_process_unhandled_input(false)
		system_menu.process_noclip(delta)
		return

	# 3. Update Screen VFX (Rain drops, etc.)
	if is_instance_valid(vfx_manager) and is_instance_valid(head):
		vfx_manager.process_vfx(delta, head.rotation.x)

	# 4. Normal Gameplay
	state_machine.set_physics_process(true)
	state_machine.set_process_unhandled_input(true)

	# 5. Apply body weight to dynamic platforms
	_apply_weight_to_floor()

	# Send the true world-space position to the compute shader
	if is_instance_valid(smoke_manager):
		smoke_manager.update_player_position(global_position)

# --------------------------------------
# ENVIRONMENTAL ADAPTERS
# --------------------------------------

# 1. Ropes
func _on_rope_grabbed(rope_body: RigidBody3D) -> void:
	print("Player: _on_rope_grabbed() called.")
	if vault_controller.is_vaulting:
		return
	state_machine.transition_to("Rope", {"rope_node": rope_body})

# 2. Ziplines
func _on_zipline_grabbed(zipline_ref: Node3D, start_pos: Vector3, end_pos: Vector3) -> void:
	print("Player: _on_zipline_grabbed() called.")
	if vault_controller.is_vaulting:
		return
	state_machine.transition_to(
		"Zipline", {"zipline_node": zipline_ref, "start_pos": start_pos, "end_pos": end_pos}
	)

# 3. Ladders
func enter_ladder(ladder_node: Node3D) -> void:
	print("Player: enter_ladder() called. Sending ladder node to StateMachine.")
	if vault_controller.is_vaulting:
		return
		
	# ONLY block if we are trying to grab the exact ladder we just jumped off
	if ladder_node == last_ladder and ladder_cooldown > 0.0:
		return
		
	state_machine.transition_to("Ladders", {"ladder_node": ladder_node})

func exit_ladder(_ladder_node: Node3D) -> void:
	if state_machine.state.name == "Ladders":
		print("Player: exit_ladder() called. Kicking player to Air state.")
		state_machine.transition_to("Air")

# 4. Fast Ropes
func _on_fastrope_grabbed() -> void:
	print("Player: _on_fastrope_grabbed() called.")
	state_machine.transition_to("FastRope")

# 5. Updraft
func enter_updraft(strength: float, top_y: float) -> void:
	print("Player: enter_updraft() called. Strength: ", strength)
	in_updraft = true
	updraft_strength = strength
	updraft_top_y = top_y

	if state_machine.state.name == "Ground":
		state_machine.transition_to("Air")

func exit_updraft() -> void:
	print("Player: exit_updraft() called.")
	in_updraft = false
	updraft_strength = 0.0

# 6. Water
func enter_water(water_volume: Node3D) -> void:
	print("Player: enter_water() called.")
	current_water_node = water_volume

	if state_machine.state.name not in ["Vault", "Zipline", "Rope"]:
		state_machine.transition_to("Swim")

func exit_water(water_volume: Node3D) -> void:
	print("Player: exit_water() called.")
	if current_water_node == water_volume:
		current_water_node = null

		if state_machine.state.name == "Swim":
			state_machine.transition_to("Air")

## 7. Terminals
#func enter_terminal_mode(terminal: Node3D) -> void:
	#print("Player: enter_terminal_mode() called. Passing to InteractionScanner.")
	#if is_instance_valid(interaction_scanner):
		#interaction_scanner.enter_terminal_mode(terminal)

# --------------------------------------
# SAVE / LOAD SYSTEM INTERFACE
# --------------------------------------
func get_save_data() -> Dictionary:
	print("Player: get_save_data() called. Serializing state.")
	var head_rot: Vector3 = camera_controller.global_rotation if is_instance_valid(camera_controller) else Vector3.ZERO
	var health_val: int = 100

	if is_instance_valid(health_component):
		if "current_health" in health_component:
			health_val = health_component.get("current_health")
		elif "health" in health_component:
			health_val = health_component.get("health")

	return {
		"pos_x": global_position.x,
		"pos_y": global_position.y,
		"pos_z": global_position.z,
		"rot_y": global_rotation.y,
		"head_rot_x": head_rot.x,
		"head_rot_y": head_rot.y,
		"health": health_val
	}

func load_save_data(data: Dictionary) -> void:
	print("Player: load_save_data() called. Restoring state.")
	global_position.x = data.get("pos_x", global_position.x)
	global_position.y = data.get("pos_y", global_position.y)
	global_position.z = data.get("pos_z", global_position.z)
	global_rotation.y = data.get("rot_y", global_rotation.y)

	if is_instance_valid(camera_controller):
		var pitch: float = data.get("head_rot_x", camera_controller.global_rotation.x)
		var yaw: float = data.get("head_rot_y", camera_controller.global_rotation.y)
		camera_controller.global_rotation = Vector3(pitch, yaw, 0.0)

	if is_instance_valid(health_component):
		var saved_health: int = data.get("health", 100)

		if "current_health" in health_component:
			health_component.set("current_health", saved_health)
		elif "health" in health_component:
			health_component.set("health", saved_health)

		_on_health_changed(saved_health)

# --------------------------------------
# WATERFALL OVERLAY TRIGGERS
# --------------------------------------
func _connect_waterfall_group() -> void:
	print("Player: _connect_waterfall_group() called. Scanning for 'waterfall_area' group...")
	var connected_count: int = 0

	for node: Node in get_tree().get_nodes_in_group("waterfall_area"):
		if node is Area3D:
			var area: Area3D = node as Area3D

			if not area.body_entered.is_connected(_on_waterfall_entered):
				area.body_entered.connect(_on_waterfall_entered.bind(area))

			if not area.body_exited.is_connected(_on_waterfall_exited):
				area.body_exited.connect(_on_waterfall_exited.bind(area))

			connected_count += 1

	print("Player: Successfully bound signals to ", connected_count, " waterfalls.")

func _on_waterfall_entered(body: Node3D, area: Area3D) -> void:
	if body != self:
		return

	print("Player: _on_waterfall_entered() called. Entering waterfall: ", area.name)

	if not overlapping_waterfall_areas.has(area):
		overlapping_waterfall_areas.append(area)

	if overlapping_waterfall_areas.size() == 1 and is_instance_valid(vfx_manager):
		vfx_manager.enter_waterfall()

func _on_waterfall_exited(body: Node3D, area: Area3D) -> void:
	if body != self:
		return

	print("Player: _on_waterfall_exited() called. Exiting waterfall: ", area.name)

	overlapping_waterfall_areas.erase(area)

	if overlapping_waterfall_areas.is_empty() and is_instance_valid(vfx_manager):
		vfx_manager.exit_waterfall()

# --------------------------------------
# RAIN OVERLAY TRIGGERS
# --------------------------------------
func enter_rain_volume() -> void:
	print("Player: enter_rain_volume() called. Enabling rain VFX.")
	if is_instance_valid(vfx_manager):
		vfx_manager.set_rain_volume(true)

func exit_rain_volume() -> void:
	print("Player: exit_rain_volume() called. Disabling rain VFX.")
	if is_instance_valid(vfx_manager):
		vfx_manager.set_rain_volume(false)

func _apply_weight_to_floor() -> void:
	if not is_on_floor():
		if is_instance_valid(_last_weighed_body):
			print("Player: Stepped off rigid body. Ceasing downward weight force.")
			_last_weighed_body = null
		return

	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()

		if collider is RigidBody3D and collision.get_normal().y > 0.5:
			# Check if the body should be ignored
			var is_cable_or_socket: bool = "CableLink" in collider.name or "Socket" in collider.name
			
			if is_cable_or_socket or collider.is_in_group("ignore_weight"):
				if _last_weighed_body != collider:
					print("Player: Stepped on ", collider.get_name(), ". Ignoring weight application.")
					_last_weighed_body = collider
				return

			var downward_force: float = player_mass * gravity
			var hit_position: Vector3 = collision.get_position() - collider.global_position
			
			collider.apply_force(Vector3.DOWN * downward_force, hit_position)

			if _last_weighed_body != collider:
				print("Player: Stepped onto ", collider.get_name(), ". Applying ", downward_force, " downward force.")
				_last_weighed_body = collider

			return


func _on_waterfall_body_entered(body: Node3D, area: Area3D) -> void:
	if body == self and area.is_in_group("waterfall_area"):
		active_waterfalls.append(area)


func _on_waterfall_body_exited(body: Node3D, area: Area3D) -> void:
	if body == self and area in active_waterfalls:
		active_waterfalls.erase(area)


func interact_with_water(area: Area3D) -> void:
	print("Player action: Interacting with waterfall area: ", area.name)


func set_machine_lock(locked: bool) -> void:
	print("Player: set_machine_lock() called. State updated to: ", locked)
	is_operating_machine = locked


func _drop_held_item() -> void:
	print("Player: _drop_held_item() called. Placing item on the ground.")
	
	# Support both standard physics objects and special items
	if held_item.has_method("drop"):
		held_item.drop()
	elif held_item.has_method("drop_item"):
		held_item.drop_item(get_tree().current_scene, global_position)
		
	if held_item is GliderItem:
		print("Player: Dropped GliderItem. Restoring sprint and camera look.")
		can_sprint = true
		interaction_scanner.is_heavy_lifting = false
		
	held_item = null
	_set_weapon_active(true)
