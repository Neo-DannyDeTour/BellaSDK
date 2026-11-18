## Characterization tests locking Wave 17 player APIs, constants, signals, and behavior.
class_name TestWave17Characterization
extends GutTest


## Builds a minimal [Player] instance with required exported components wired.
func _create_minimal_player() -> Player:
	var p: Player = Player.new()
	var loco: PlayerLocomotionComponent = PlayerLocomotionComponent.new()
	var inter: PlayerInteractionComponent = PlayerInteractionComponent.new()
	var env: PlayerEnvironmentComponent = PlayerEnvironmentComponent.new()
	var cam_ctrl: CameraController = CameraController.new()
	var head: Node3D = Node3D.new()
	var eyes: Node3D = Node3D.new()
	var cam: Camera3D = Camera3D.new()

	cam_ctrl.player_body = p
	cam_ctrl.head = head
	cam_ctrl.eyes = eyes
	cam_ctrl.camera = cam

	p.locomotion_component = loco
	p.interaction_component = inter
	p.environment_component = env
	p.camera_controller = cam_ctrl

	p.add_child(head)
	head.add_child(eyes)
	eyes.add_child(cam)
	p.add_child(loco)
	p.add_child(inter)
	p.add_child(env)
	p.add_child(cam_ctrl)
	add_child_autofree(p)
	return p


## Verifies [StateMachineLock] mouse mode transitions and lifecycle methods.
func test_state_machine_lock_contracts() -> void:
	var lock_state: StateMachineLock = StateMachineLock.new()
	add_child_autofree(lock_state)

	assert_true(lock_state.has_method(&"enter"))
	assert_true(lock_state.has_method(&"exit"))
	assert_true(lock_state.has_method(&"update"))
	assert_true(lock_state.has_method(&"physics_update"))
	assert_true(lock_state.has_method(&"handle_input"))

	var p: Player = _create_minimal_player()
	p.velocity = Vector3(3.0, 2.0, -1.0)
	lock_state.player = p

	lock_state.enter({"capture_mouse": false})
	assert_eq(p.velocity, Vector3.ZERO)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)

	lock_state.enter({"capture_mouse": true})
	lock_state.exit()


## Verifies [PlayerLocomotionComponent] constants, exports, and movement calculations.
func test_locomotion_component_contracts() -> void:
	assert_almost_eq(PlayerLocomotionComponent.CHARACTER_HEIGHT, 1.64, 0.001)
	assert_almost_eq(PlayerLocomotionComponent.STANDING_HEIGHT, 1.52, 0.001)
	assert_almost_eq(PlayerLocomotionComponent.CROUCHING_HEIGHT, 0.9, 0.001)
	assert_eq(PlayerLocomotionComponent.GROUP_IGNORE_WEIGHT, &"ignore_weight")
	assert_eq(PlayerLocomotionComponent.GROUP_CABLE_LINK, &"cable_link")
	assert_eq(PlayerLocomotionComponent.GROUP_SOCKET, &"socket")
	assert_eq(PlayerLocomotionComponent.SIG_HEAVY_CARRY, &"heavy_carry_toggled")
	assert_eq(PlayerLocomotionComponent.SIG_SAND_SURFACE, &"sand_surface_toggled")
	assert_eq(PlayerLocomotionComponent.SIG_ICE_SURFACE, &"ice_surface_toggled")
	assert_eq(PlayerLocomotionComponent.SIG_SPRINT_DEBUFF, &"sprint_debuff_applied")
	assert_eq(PlayerLocomotionComponent.METHOD_REGISTER_STANDING, &"register_player_standing")

	var body: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(body)
	var loco: PlayerLocomotionComponent = PlayerLocomotionComponent.new()
	add_child_autofree(loco)
	loco.initialize(body)

	assert_almost_eq(loco.walking_speed, 5.0, 0.001)
	assert_almost_eq(loco.sprinting_speed, 6.5, 0.001)
	assert_almost_eq(loco.crouching_speed, 3.0, 0.001)
	assert_almost_eq(loco.swimming_speed, 4.0, 0.001)
	assert_almost_eq(loco.swim_up_speed, 5.0, 0.001)
	assert_almost_eq(loco.heavy_carry_speed_mult, 0.6, 0.001)
	assert_false(loco.allow_heavy_carry_jump)
	assert_almost_eq(loco.heavy_carry_jump_mult, 0.4, 0.001)
	assert_almost_eq(loco.jump_buffer_duration, 0.15, 0.001)
	assert_almost_eq(loco.coyote_time_duration, 0.15, 0.001)
	assert_almost_eq(loco.fall_gravity_multiplier, 1.5, 0.001)
	assert_almost_eq(loco.default_lerp_speed, 15.0, 0.001)
	assert_almost_eq(loco.air_lerp_speed, 3.0, 0.001)
	assert_almost_eq(loco.ice_lerp_speed, 1.5, 0.001)

	loco.set_direction(Vector3(1.0, 0.0, 0.0))
	assert_eq(loco.get_direction(), Vector3(1.0, 0.0, 0.0))
	assert_almost_eq(loco.get_effective_walk_speed(), 5.0, 0.001)
	assert_almost_eq(loco.get_effective_jump_velocity(4.5), 4.5, 0.001)

	loco.set_heavy_carry(true, 20.0)
	assert_almost_eq(loco.get_effective_walk_speed(), 3.0, 0.001)
	assert_almost_eq(loco.get_effective_jump_velocity(4.5), 0.0, 0.001)
	loco.set_heavy_carry(false)
	assert_false(loco.is_ice_hazard_active())
	assert_false(loco.is_sand_hazard_active())

	body.velocity = Vector3(2.0, 1.0, 3.0)
	loco.reset_momentum()
	assert_eq(body.velocity, Vector3.ZERO)
	assert_eq(loco.get_direction(), Vector3.ZERO)


## Verifies [Player] constants, signals, groups, and save/state APIs.
func test_player_contracts() -> void:
	assert_eq(Player.GROUP_SAND, &"sand")
	assert_eq(Player.GROUP_ICE, &"ice")
	assert_eq(Player.GROUP_SAVEABLE, &"saveable")
	assert_eq(Player.GROUP_PLAYER, &"player")
	assert_eq(Player.STATE_GROUND, &"Ground")
	assert_eq(Player.STATE_AIR, &"Air")
	assert_eq(Player.STATE_TERMINAL, &"Terminal")
	assert_eq(Player.STATE_MACHINE_LOCK, &"MachineLock")
	assert_eq(Player.STATE_PATH_SLIDE, &"PathSlide")
	assert_eq(Player.STATE_TUBE, &"Tube")
	assert_eq(Player.ACTION_DESCRIBE, &"describe_surroundings")
	assert_eq(Player.ACTION_SONAR, &"sonar_ping")
	assert_eq(Player.SIG_DESCRIBE, &"describe_surroundings_requested")
	assert_eq(Player.SIG_SONAR, &"sonar_ping_requested")
	assert_eq(Player.SIG_PLAYER_DIED, &"player_died")
	assert_eq(Player.SIG_CAMERA_REGISTERED, &"player_camera_registered")
	assert_eq(Player.SIG_HEALTH_SET, &"player_health_set_requested")
	assert_eq(Player.SIG_KILL_REQ, &"player_kill_requested")
	assert_eq(Player.SIG_TELEPORT_REQ, &"teleport_requested")
	assert_eq(Player.SIG_FLIGHT_TOGGLED, &"flight_mode_toggled")
	assert_eq(Player.SIG_CINEMATIC_LOCK, &"player_cinematic_lock_requested")
	assert_eq(Player.SIG_WOLF_TOGGLED, &"wolf_mode_toggled")
	assert_eq(Player.SIG_PSYCHIC_FINISHED, &"advisor_psychic_pulse_finished")

	var p: Player = _create_minimal_player()
	assert_true(p.has_signal(&"psychic_pulse_finished"))
	assert_true(p.is_in_group(Player.GROUP_SAVEABLE))
	assert_true(p.is_in_group(Player.GROUP_PLAYER))
	assert_false(p.is_dead)
	assert_false(p.is_in_terminal_mode)
	assert_false(p.is_cinematic_locked)
	assert_false(p.is_wolf_mode)
	assert_true(p.can_interact_with_machinery())
	assert_false(p.has_zipline_cooldown())

	p.set_terminal_mouse_sensitivity_scale(0.5)
	assert_almost_eq(p.terminal_mouse_sensitivity_scale, 0.5, 0.001)

	p.enter_updraft(10.0, 15.0)
	assert_true(p.environment_component.in_updraft)
	p.exit_updraft()
	assert_false(p.environment_component.in_updraft)

	var save_data: Dictionary = p.get_save_data()
	assert_true(save_data.has("pos_x"))
	assert_true(save_data.has("pos_y"))
	assert_true(save_data.has("pos_z"))
	assert_true(save_data.has("rot_y"))
	assert_true(save_data.has("head_rot_x"))
	assert_true(save_data.has("head_rot_y"))


## Verifies [PushWheelState] constants and lifecycle interface.
func test_push_wheel_state_contracts() -> void:
	assert_eq(PushWheelState.STATE_GROUND, &"Ground")
	assert_eq(PushWheelState.KEY_TARGET_TRANSFORM, &"target_transform")
	assert_eq(PushWheelState.KEY_WHEEL, &"wheel")
	assert_eq(PushWheelState.METHOD_PUSH, &"push")
	assert_eq(PushWheelState.METHOD_PUSH_STARTED, &"on_push_started")
	assert_eq(PushWheelState.METHOD_PUSH_ENDED, &"on_push_ended")
	assert_eq(PushWheelState.PROP_IS_INSTALLED, &"is_installed")
	assert_eq(PushWheelState.PROP_ACTIVE_ANCHOR, &"current_active_anchor")
	assert_eq(PushWheelState.PROP_TURN_CLOCKWISE, &"turn_clockwise")
	assert_eq(PushWheelState.PROP_SPIN_AXIS, &"spin_axis")
	assert_eq(PushWheelState.PROP_WHEEL_NODE, &"wheel")

	var push_state: PushWheelState = PushWheelState.new()
	add_child_autofree(push_state)
	assert_true(push_state.has_method(&"enter"))
	assert_true(push_state.has_method(&"physics_update"))
	assert_true(push_state.has_method(&"exit"))


## Verifies [StateAir] constants and lifecycle interface.
func test_state_air_contracts() -> void:
	assert_almost_eq(StateAir.JUMP_VELOCITY, 4.5, 0.001)
	assert_almost_eq(StateAir.SPRINT_JUMP_VELOCITY, 5.0, 0.001)
	assert_almost_eq(StateAir.CROUCH_JUMP_VELOCITY, 3.5, 0.001)
	assert_almost_eq(StateAir.WOLF_DOUBLE_JUMP_VELOCITY, 7.0, 0.001)
	assert_eq(StateAir.GROUP_WOLF_CLIMBABLE, &"wolf_climbable")
	assert_eq(StateAir.GROUP_SAFE_LANDING, &"safe_landing")
	assert_eq(StateAir.GROUP_SLIDE, &"slide_surface")
	assert_eq(StateAir.STATE_GROUND, &"Ground")
	assert_eq(StateAir.STATE_SLIDE, &"Slide")
	assert_eq(StateAir.STATE_SWIM, &"Swim")
	assert_eq(StateAir.STATE_VAULT, &"Vault")
	assert_eq(StateAir.STATE_GLIDE, &"Glide")
	assert_eq(StateAir.STATE_MONKEY_BARS, &"MonkeyBars")
	assert_eq(StateAir.STATE_WOLF_CLIMB, &"WolfClimb")

	var air_state: StateAir = StateAir.new()
	add_child_autofree(air_state)
	assert_true(air_state.has_method(&"enter"))
	assert_true(air_state.has_method(&"physics_update"))


## Verifies [StateFastRope] lifecycle interface.
func test_state_fast_rope_contracts() -> void:
	var fast_rope: StateFastRope = StateFastRope.new()
	add_child_autofree(fast_rope)
	assert_true(fast_rope.has_method(&"enter"))
	assert_true(fast_rope.has_method(&"exit"))
	assert_true(fast_rope.has_method(&"physics_update"))


## Verifies [StateGlide] exports and lifecycle interface.
func test_state_glide_contracts() -> void:
	var glide: StateGlide = StateGlide.new()
	add_child_autofree(glide)

	assert_almost_eq(glide.forward_speed, 12.0, 0.001)
	assert_almost_eq(glide.max_fall_speed, 2.5, 0.001)
	assert_almost_eq(glide.debug_updraft_force, 15.0, 0.001)
	assert_almost_eq(glide.turn_speed, 2.0, 0.001)
	assert_almost_eq(glide.max_bank_angle, 15.0, 0.001)
	assert_almost_eq(glide.bank_lerp_speed, 5.0, 0.001)
	assert_true(glide.has_method(&"enter"))
	assert_true(glide.has_method(&"exit"))
	assert_true(glide.has_method(&"physics_update"))


## Verifies [StateGround] constants and lifecycle interface.
func test_state_ground_contracts() -> void:
	assert_almost_eq(StateGround.JUMP_VELOCITY, 4.5, 0.001)
	assert_almost_eq(StateGround.CROUCH_JUMP_VELOCITY, 3.5, 0.001)
	assert_almost_eq(StateGround.SPRINT_JUMP_VELOCITY, 5.0, 0.001)
	assert_almost_eq(StateGround.GROUND_FRICTION, 25.0, 0.001)
	assert_eq(StateGround.GROUP_SLIDE, &"slide_surface")
	assert_eq(StateGround.GROUP_SAND, &"sand")
	assert_eq(StateGround.GROUP_SAFE_LANDING, &"safe_landing")
	assert_eq(StateGround.STATE_SLIDE, &"Slide")
	assert_eq(StateGround.STATE_SWIM, &"Swim")
	assert_eq(StateGround.STATE_AIR, &"Air")
	assert_eq(StateGround.STATE_VAULT, &"Vault")

	var ground: StateGround = StateGround.new()
	add_child_autofree(ground)
	assert_true(ground.has_method(&"enter"))
	assert_true(ground.has_method(&"physics_update"))


## Verifies [StateJibCrane] constants and lifecycle interface.
func test_state_jib_crane_contracts() -> void:
	assert_eq(StateJibCrane.STATE_AIR, &"Air")
	assert_eq(StateJibCrane.KEY_CRANE, &"crane")
	assert_eq(StateJibCrane.KEY_RAIL_OFFSET, &"rail_offset")
	assert_eq(StateJibCrane.KEY_JUMP, &"jump")
	assert_eq(StateJibCrane.KEY_RELEASE_DIR, &"release_dir")
	assert_almost_eq(StateJibCrane.JUMP_HORIZONTAL_SPEED, 6.2, 0.001)
	assert_almost_eq(StateJibCrane.SWING_LAUNCH_MAX_HORIZ_SPEED, 9.2, 0.001)
	assert_almost_eq(StateJibCrane.JUMP_VERTICAL_SPEED, 4.8, 0.001)
	assert_almost_eq(StateJibCrane.SWING_LAUNCH_BONUS_UP, 1.4, 0.001)
	assert_almost_eq(StateJibCrane.DROP_VERTICAL_SPEED, -1.5, 0.001)
	assert_almost_eq(StateJibCrane.SWING_ARM_LENGTH, 1.35, 0.001)
	assert_almost_eq(StateJibCrane.SWING_GRAVITY_SCALE, 1.75, 0.001)
	assert_almost_eq(StateJibCrane.SWING_PUMP_ACCEL, 9.5, 0.001)
	assert_almost_eq(StateJibCrane.MAX_SWING_ANGLE_RAD, 0.9075712, 0.0001)
	assert_almost_eq(StateJibCrane.SWING_ACTIVE_DAMPING, 0.55, 0.001)
	assert_almost_eq(StateJibCrane.SWING_IDLE_DAMPING, 3.2, 0.001)
	assert_almost_eq(StateJibCrane.MAX_SWING_VERTICAL_LIFT, 0.48, 0.001)
	assert_almost_eq(StateJibCrane.RAIL_SNAP_SPEED, 22.0, 0.001)
	assert_almost_eq(StateJibCrane.FIRE_STILL_SPEED_THRESHOLD, 0.15, 0.001)
	assert_almost_eq(StateJibCrane.MAX_SHIMMY_ROLL_DEG, 3.5, 0.001)
	assert_almost_eq(StateJibCrane.MAX_SWING_PITCH_DEG, 5.0, 0.001)
	assert_almost_eq(StateJibCrane.CAMERA_ROLL_LERP_SPEED, 10.0, 0.001)
	assert_almost_eq(StateJibCrane.INTERACT_DISMOUNT_GRACE, 0.25, 0.001)
	assert_almost_eq(StateJibCrane.DISMOUNT_REGRAB_COOLDOWN, 0.45, 0.001)

	var crane_state: StateJibCrane = StateJibCrane.new()
	add_child_autofree(crane_state)
	assert_true(crane_state.has_method(&"enter"))
	assert_true(crane_state.has_method(&"exit"))
	assert_true(crane_state.has_method(&"physics_update"))


## Verifies [StateMonkeyBars] constants and lifecycle interface.
func test_state_monkey_bars_contracts() -> void:
	assert_almost_eq(StateMonkeyBars.MONKEY_BAR_SPEED, 2.5, 0.001)
	assert_almost_eq(StateMonkeyBars.MONKEY_BAR_HANG_OFFSET, 2.1, 0.001)

	var bars: StateMonkeyBars = StateMonkeyBars.new()
	add_child_autofree(bars)
	assert_true(bars.has_method(&"enter"))
	assert_true(bars.has_method(&"exit"))
	assert_true(bars.has_method(&"physics_update"))


## Verifies [StatePathSlide] lifecycle interface.
func test_state_path_slide_contracts() -> void:
	var path_slide: StatePathSlide = StatePathSlide.new()
	add_child_autofree(path_slide)
	assert_true(path_slide.has_method(&"enter"))
	assert_true(path_slide.has_method(&"exit"))
	assert_true(path_slide.has_method(&"handle_input"))
	assert_true(path_slide.has_method(&"physics_update"))


## Verifies [StateRope] constants and lifecycle interface.
func test_state_rope_contracts() -> void:
	assert_almost_eq(StateRope.CHAIN_CLIMB_SPEED, 1.2, 0.001)
	assert_almost_eq(StateRope.CHAIN_SLIDE_SPEED, 6.0, 0.001)
	assert_almost_eq(StateRope.CHAIN_ORBIT_SPEED, 1.5707963, 0.0001)
	assert_almost_eq(StateRope.CHAIN_STANDOFF_RADIUS, 0.42, 0.001)
	assert_almost_eq(StateRope.CHAIN_JUMP_HORIZONTAL, 7.0, 0.001)
	assert_almost_eq(StateRope.CHAIN_JUMP_VERTICAL, 4.5, 0.001)
	assert_almost_eq(StateRope.SWING_CLIMB_SPEED, 1.6, 0.001)
	assert_almost_eq(StateRope.SWING_CLIMB_PITCH_THRESHOLD, 0.55, 0.001)
	assert_almost_eq(StateRope.SWING_SLIDE_SPEED, 4.0, 0.001)
	assert_almost_eq(StateRope.SWING_GRAVITY_SCALE, 2.1, 0.001)
	assert_almost_eq(StateRope.SWING_PUMP_ACCEL, 16.5, 0.001)
	assert_almost_eq(StateRope.SWING_MAX_PUMP_ANGLE_RAD, 1.0471976, 0.0001)
	assert_almost_eq(StateRope.SWING_DAMPING, 0.45, 0.001)
	assert_almost_eq(StateRope.SWING_IDLE_DAMPING, 2.4, 0.001)
	assert_almost_eq(StateRope.SWING_CLIMB_BRAKE_DAMPING, 4.5, 0.001)
	assert_almost_eq(StateRope.SWING_AIR_DRAG, 0.005, 0.0001)
	assert_almost_eq(StateRope.SWING_JUMP_FWD_BOOST, 6.0, 0.001)
	assert_almost_eq(StateRope.SWING_JUMP_MAX_HORIZ_SPEED, 16.5, 0.001)
	assert_almost_eq(StateRope.SWING_JUMP_BASE_UP, 5.2, 0.001)
	assert_almost_eq(StateRope.SWING_JUMP_PITCH_UP, 4.2, 0.001)
	assert_almost_eq(StateRope.SWING_STILL_SPEED_THRESHOLD, 0.75, 0.001)
	assert_almost_eq(StateRope.MAX_SWING_ROLL_DEG, 6.0, 0.001)
	assert_almost_eq(StateRope.CAMERA_ROLL_LERP_SPEED, 10.0, 0.001)
	assert_almost_eq(StateRope.BOTTOM_HOLD_DROP_TIME, 0.15, 0.001)
	assert_almost_eq(StateRope.HAND_HEIGHT_OFFSET, 1.35, 0.001)
	assert_almost_eq(StateRope.MOUNT_SNAP_SPEED, 18.0, 0.001)
	assert_almost_eq(StateRope.REGRAB_COOLDOWN, 0.4, 0.001)
	assert_almost_eq(StateRope.DISMOUNT_SEPARATION, 0.25, 0.001)
	assert_almost_eq(StateRope.INTERACT_DISMOUNT_GRACE, 0.20, 0.001)
	assert_eq(StateRope.STATE_AIR, &"Air")
	assert_eq(StateRope.KEY_ROPE, &"rope")
	assert_eq(StateRope.KEY_GRAB_DISTANCE, &"grab_distance")
	assert_eq(StateRope.KEY_JUMP, &"jump")
	assert_eq(StateRope.KEY_RELEASE_DIR, &"release_dir")

	var rope_state: StateRope = StateRope.new()
	add_child_autofree(rope_state)
	assert_true(rope_state.has_method(&"enter"))
	assert_true(rope_state.has_method(&"exit"))
	assert_true(rope_state.has_method(&"physics_update"))


## Verifies [StateSlide] exports and lifecycle interface.
func test_state_slide_contracts() -> void:
	var slide: StateSlide = StateSlide.new()
	add_child_autofree(slide)

	assert_almost_eq(slide.slide_acceleration, 15.0, 0.001)
	assert_almost_eq(slide.max_slide_speed, 25.0, 0.001)
	assert_almost_eq(slide.slide_steering_speed, 8.0, 0.001)
	assert_true(slide.has_method(&"enter"))
	assert_true(slide.has_method(&"exit"))
	assert_true(slide.has_method(&"physics_update"))


## Verifies [StateSwim] constants, exports, and lifecycle interface.
func test_state_swim_contracts() -> void:
	assert_almost_eq(StateSwim.SINK_SPEED, -1.6, 0.001)
	assert_almost_eq(StateSwim.PLUNGE_SPEED, -4.5, 0.001)
	assert_almost_eq(StateSwim.SWIM_UP_SPEED, 3.8, 0.001)
	assert_almost_eq(StateSwim.SWIM_DOWN_SPEED, -3.2, 0.001)
	assert_almost_eq(StateSwim.SURFACE_SPRING_STIFFNESS, 5.5, 0.001)
	assert_almost_eq(StateSwim.MAX_SURFACE_BOB_SPEED, 3.2, 0.001)
	assert_almost_eq(StateSwim.DROWN_TICK_INTERVAL, 0.5, 0.001)
	assert_eq(StateSwim.DROWN_DAMAGE_PER_TICK, 25)
	assert_almost_eq(StateSwim.EYE_HEIGHT_OFFSET, 1.65, 0.001)
	assert_almost_eq(StateSwim.CHEST_HEIGHT_OFFSET, 0.95, 0.001)
	assert_almost_eq(StateSwim.SURFACE_EXIT_HYSTERESIS, 0.18, 0.001)
	assert_almost_eq(StateSwim.MIN_SPLASH_EXIT_SPEED, 1.8, 0.001)
	assert_eq(StateSwim.METHOD_GET_WAVE_HEIGHT, &"get_wave_height_at_pos")
	assert_eq(StateSwim.METHOD_PLAY_SPLASH, &"play_splash_sound")

	var swim: StateSwim = StateSwim.new()
	add_child_autofree(swim)
	assert_almost_eq(swim.max_swim_duration, 10.0, 0.001)
	assert_true(swim.has_method(&"enter"))
	assert_true(swim.has_method(&"exit"))
	assert_true(swim.has_method(&"physics_update"))


## Verifies [StateTerminal] enter/exit terminal caching and locomotion suspension.
func test_state_terminal_contracts() -> void:
	var p: Player = _create_minimal_player()
	var term_state: StateTerminal = StateTerminal.new()
	add_child_autofree(term_state)
	term_state.player = p

	var terminal_node: Node3D = Node3D.new()
	add_child_autofree(terminal_node)

	term_state.enter({&"terminal": terminal_node})
	assert_eq(term_state.active_terminal, terminal_node)
	assert_false(p.locomotion_component.is_active)

	term_state.exit()
	assert_null(term_state.active_terminal)
	assert_true(p.locomotion_component.is_active)


## Verifies [StateTube] lifecycle interface.
func test_state_tube_contracts() -> void:
	var tube: StateTube = StateTube.new()
	add_child_autofree(tube)
	assert_true(tube.has_method(&"enter"))
	assert_true(tube.has_method(&"exit"))
	assert_true(tube.has_method(&"handle_input"))
	assert_true(tube.has_method(&"update"))
	assert_true(tube.has_method(&"physics_update"))


## Verifies [StateVault] enter/exit velocity reset and signal cleanup.
func test_state_vault_contracts() -> void:
	var p: Player = _create_minimal_player()
	p.velocity = Vector3(1.0, 2.0, 3.0)

	var vault_state: StateVault = StateVault.new()
	add_child_autofree(vault_state)
	vault_state.player = p

	vault_state.enter()
	assert_eq(p.velocity, Vector3.ZERO)
	vault_state.exit()
	assert_true(vault_state.has_method(&"physics_update"))


## Verifies [StateWolfClimb] constants and lifecycle interface.
func test_state_wolf_climb_contracts() -> void:
	assert_eq(StateWolfClimb.GROUP_WOLF_CLIMBABLE, &"wolf_climbable")
	assert_almost_eq(StateWolfClimb.CLIMB_SPEED, 4.5, 0.001)
	assert_almost_eq(StateWolfClimb.SLIDE_DOWN_SPEED, 7.5, 0.001)
	assert_almost_eq(StateWolfClimb.SURFACE_TRANSFER_REACH, 18.0, 0.001)
	assert_almost_eq(StateWolfClimb.SURFACE_TRANSFER_SPEED, 22.0, 0.001)

	var climb: StateWolfClimb = StateWolfClimb.new()
	add_child_autofree(climb)
	assert_true(climb.has_method(&"enter"))
	assert_true(climb.has_method(&"physics_update"))


## Verifies [StateWolfWallRun] constants and lifecycle interface.
func test_state_wolf_wall_run_contracts() -> void:
	assert_eq(StateWolfWallRun.GROUP_WOLF_CLIMBABLE, &"wolf_climbable")
	assert_almost_eq(StateWolfWallRun.WALL_RUN_SPEED, 12.0, 0.001)
	assert_almost_eq(StateWolfWallRun.MAX_WALL_RUN_TIME, 2.5, 0.001)
	assert_almost_eq(StateWolfWallRun.WALL_JUMP_KICK_IMPULSE, 20.0, 0.001)
	assert_almost_eq(StateWolfWallRun.SURFACE_TRANSFER_REACH, 18.0, 0.001)
	assert_almost_eq(StateWolfWallRun.SURFACE_TRANSFER_SPEED, 22.0, 0.001)
	assert_almost_eq(StateWolfWallRun.CAMERA_ROLL_ANGLE, 14.0, 0.001)

	var wall_run: StateWolfWallRun = StateWolfWallRun.new()
	add_child_autofree(wall_run)
	assert_true(wall_run.has_method(&"enter"))
	assert_true(wall_run.has_method(&"exit"))
	assert_true(wall_run.has_method(&"physics_update"))


## Verifies [StateZipline] constants and lifecycle interface.
func test_state_zipline_contracts() -> void:
	assert_almost_eq(StateZipline.ZIPLINE_SLIDE_SPEED, 8.0, 0.001)
	assert_almost_eq(StateZipline.ZIPLINE_HANG_OFFSET, 2.0, 0.001)
	assert_almost_eq(StateZipline.DETACH_MOMENTUM_MULTIPLIER, 1.1, 0.001)

	var zip_state: StateZipline = StateZipline.new()
	add_child_autofree(zip_state)
	assert_true(zip_state.has_method(&"enter"))
	assert_true(zip_state.has_method(&"exit"))
	assert_true(zip_state.has_method(&"physics_update"))


## Verifies [PlayerStatsComponent] defaults, save serialization, and clamping.
func test_stats_component_contracts() -> void:
	var stats: PlayerStatsComponent = PlayerStatsComponent.new()
	var health: HealthComponent = HealthComponent.new()
	health.max_health = 100
	stats.health_component = health
	add_child_autofree(health)
	add_child_autofree(stats)
	health.current_health = 75

	assert_almost_eq(stats.player_mass, 80.0, 0.001)
	var p: Player = _create_minimal_player()
	stats.initialize(p)
	assert_eq(stats.player, p)

	var saved: Dictionary = stats.get_save_data()
	assert_eq(saved.get("health"), 75)

	stats.load_save_data({"health": 999})
	assert_eq(health.current_health, 100)
	stats.load_save_data({"health": -10})
	assert_eq(health.current_health, 1)


## Verifies [WeaponInventoryComponent] constants, slot registration, and swapping.
func test_weapon_inventory_component_contracts() -> void:
	assert_eq(WeaponInventoryComponent.MAX_SLOT_COUNT, 5)
	assert_eq(WeaponInventoryComponent.LAST_WEAPON_ACTION, &"last_weapon")
	assert_eq(WeaponInventoryComponent.SLOT_ACTIONS.size(), 5)

	var inv: WeaponInventoryComponent = WeaponInventoryComponent.new()
	add_child_autofree(inv)
	assert_eq(inv.current_slot_index, -1)
	assert_eq(inv.previous_slot_index, -1)
	assert_true(inv.can_fire)

	var weapon_a: Node3D = Node3D.new()
	weapon_a.name = "WeaponA"
	add_child_autofree(weapon_a)
	var weapon_b: Node3D = Node3D.new()
	weapon_b.name = "WeaponB"
	add_child_autofree(weapon_b)

	inv.register_weapon(weapon_a)
	assert_eq(inv.current_slot_index, 0)
	assert_eq(inv.slots[0], weapon_a)

	inv.register_weapon(weapon_b)
	assert_eq(inv.current_slot_index, 1)
	assert_eq(inv.previous_slot_index, 0)
	assert_eq(inv.slots[1], weapon_b)

	inv.swap_to_previous()
	assert_eq(inv.current_slot_index, 0)

	inv.remove_weapon(weapon_a)
	assert_null(inv.slots[0])


## Verifies [WeaponProceduralAnimator] enum, constants, signals, and animation transitions.
func test_weapon_procedural_animator_contracts() -> void:
	assert_eq(WeaponProceduralAnimator.AnimationState.IDLE, 0)
	assert_eq(WeaponProceduralAnimator.AnimationState.WALKING, 1)
	assert_eq(WeaponProceduralAnimator.AnimationState.SPRINTING, 2)
	assert_eq(WeaponProceduralAnimator.AnimationState.INSPECTING, 3)
	assert_eq(WeaponProceduralAnimator.AnimationState.RELOADING, 4)
	assert_eq(WeaponProceduralAnimator.DEFAULT_REST_POSITION, Vector3(0.22, -0.22, -0.45))
	assert_eq(WeaponProceduralAnimator.DEFAULT_REST_ROTATION, Vector3.ZERO)
	assert_almost_eq(WeaponProceduralAnimator.MAX_SWAY_ROTATION, 0.12, 0.001)
	assert_almost_eq(WeaponProceduralAnimator.MAX_SWAY_POSITION, 0.025, 0.001)
	assert_almost_eq(WeaponProceduralAnimator.SWAY_SMOOTH_SPEED, 14.0, 0.001)

	var anim: WeaponProceduralAnimator = WeaponProceduralAnimator.new()
	add_child_autofree(anim)

	assert_true(anim.has_signal(&"inspect_completed"))
	assert_true(anim.has_signal(&"inspect_cancelled"))
	assert_eq(anim.state, WeaponProceduralAnimator.AnimationState.IDLE)

	watch_signals(anim)
	assert_true(anim.inspect())
	assert_eq(anim.state, WeaponProceduralAnimator.AnimationState.INSPECTING)
	assert_false(anim.inspect())
	anim.cancel_inspect()
	assert_eq(anim.state, WeaponProceduralAnimator.AnimationState.IDLE)
	assert_signal_emitted(anim, "inspect_cancelled")

	assert_true(anim.play_reload(0.2))
	assert_eq(anim.state, WeaponProceduralAnimator.AnimationState.RELOADING)
	anim.cancel_reload()
	assert_eq(anim.state, WeaponProceduralAnimator.AnimationState.IDLE)
	anim.apply_recoil(Vector3(0.0, 0.0, 0.01), Vector3(0.02, 0.0, 0.0))
