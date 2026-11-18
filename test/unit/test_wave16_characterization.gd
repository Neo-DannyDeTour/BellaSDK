## Characterization tests locking Wave 16 player APIs, constants, signals, and behavior.
class_name TestWave16Characterization
extends GutTest

const DRUNK_EFFECT_SCRIPT: GDScript = preload("res://player/drunk_effect.gd")
const REVOLVER_SCRIPT: GDScript = preload("res://player/procedural_revolver.gd")
const FAST_ROPE_SCENE: PackedScene = preload("res://player/fast_rope.tscn")
const ZIPLINE_SCENE: PackedScene = preload("res://player/zipline.tscn")


## Verifies [BreakableRope3D] constants, exports, signal, and damage cutting behavior.
func test_breakable_rope_contracts() -> void:
	assert_eq(BreakableRope3D.INTERACTIVE_LAYER_MASK, 1 << 2)

	var rope: BreakableRope3D = BreakableRope3D.new()
	add_child_autofree(rope)

	assert_true(rope.has_signal(&"rope_broken"))
	assert_eq(rope.local_start_point, Vector3.ZERO)
	assert_eq(rope.local_end_point, Vector3(0.0, -3.0, 0.0))
	assert_almost_eq(rope.rope_radius, 0.04, 0.001)
	assert_eq(rope.rope_color, Color(0.25, 0.18, 0.12))
	assert_true(rope.spawn_dynamic_halves)
	assert_false(rope.is_broken)
	assert_true(rope.has_method(&"get_start_global_position"))
	assert_true(rope.has_method(&"get_end_global_position"))
	assert_true(rope.has_method(&"take_damage"))
	assert_true(rope.has_method(&"cut_rope_at"))

	watch_signals(rope)
	rope.spawn_dynamic_halves = false
	rope.take_damage(1, Vector3(0.0, -1.5, 0.0), Vector3.FORWARD)
	assert_true(rope.is_broken)
	assert_signal_emitted(rope, "rope_broken")


## Verifies [ExtendedCamera3D] constants, exports, and shader/vision-assist methods.
func test_extended_camera_3d_contracts() -> void:
	assert_eq(ExtendedCamera3D.PARAM_INTENSITY, &"intensity")

	var cam: ExtendedCamera3D = ExtendedCamera3D.new()
	add_child_autofree(cam)

	assert_true(cam.is_player_camera)
	assert_almost_eq(cam.noise_speed, 50.0, 0.001)
	assert_almost_eq(cam.max_offset_x, 0.5, 0.001)
	assert_almost_eq(cam.max_offset_y, 0.5, 0.001)
	assert_almost_eq(cam.max_roll_z, 2.0, 0.001)
	assert_true(cam.has_method(&"set_motion_blur_strength"))
	assert_true(cam.has_method(&"set_lens_dirt"))
	assert_true(cam.has_method(&"set_vision_assist_mode"))

	cam.set_motion_blur_strength(0.0)
	cam.set_lens_dirt(false, 0.0)
	cam.set_vision_assist_mode("Off")


## Verifies [CameraController] constants, defaults, sensitivity, and orientation helpers.
func test_camera_controller_contracts() -> void:
	assert_almost_eq(CameraController.HEAD_BOBBING_SPRINTING_SPEED, 22.0, 0.001)
	assert_almost_eq(CameraController.HEAD_BOBBING_WALKING_SPEED, 14.0, 0.001)
	assert_almost_eq(CameraController.HEAD_BOBBING_CROUCHING_SPEED, 10.0, 0.001)
	assert_almost_eq(CameraController.HEAD_BOBBING_IDLE_SPEED, 3.0, 0.001)
	assert_almost_eq(CameraController.HEAD_BOBBING_SPRINTING_INTENSITY, 0.2, 0.001)
	assert_almost_eq(CameraController.HEAD_BOBBING_WALKING_INTENSITY, 0.1, 0.001)
	assert_almost_eq(CameraController.HEAD_BOBBING_CROUCHING_INTENSITY, 0.08, 0.001)
	assert_almost_eq(CameraController.HEAD_BOBBING_IDLE_INTENSITY, 0.02, 0.001)

	var ctrl: CameraController = CameraController.new()
	assert_almost_eq(ctrl.mouse_sensitivity_base, 0.05, 0.001)
	var body: CharacterBody3D = CharacterBody3D.new()
	var head: Node3D = Node3D.new()
	var eyes: Node3D = Node3D.new()
	var cam: Camera3D = Camera3D.new()
	ctrl.player_body = body
	ctrl.head = head
	ctrl.eyes = eyes
	ctrl.camera = cam
	add_child_autofree(body)
	add_child_autofree(head)
	add_child_autofree(eyes)
	add_child_autofree(cam)
	add_child_autofree(ctrl)

	assert_almost_eq(ctrl.base_fov, 75.0, 0.001)
	assert_almost_eq(ctrl.sprint_fov, 85.0, 0.001)
	assert_almost_eq(ctrl.zoom_fov, 10.0, 0.001)
	assert_almost_eq(ctrl.fov_change_speed, 12.0, 0.001)
	assert_almost_eq(ctrl.lerp_speed, 15.0, 0.001)
	assert_almost_eq(ctrl.camera_tilt_amount, 3.0, 0.001)
	assert_true(ctrl.aim_assist_mode is int)
	assert_almost_eq(ctrl.aim_assist_amount, 0.5, 0.001)
	assert_almost_eq(ctrl.aim_assist_max_range, 50.0, 0.001)

	ctrl.set_mouse_sensitivity(0.12)
	assert_almost_eq(ctrl.mouse_sensitivity, 0.12, 0.001)
	ctrl.add_stair_offset(0.35)
	assert_almost_eq(ctrl.stair_offset, -0.35, 0.001)
	ctrl.apply_saved_rotation(0.2, 1.0)
	assert_almost_eq(head.rotation.x, 0.2, 0.001)
	assert_almost_eq(body.rotation.y, 1.0, 0.001)
	ctrl.reset_head_yaw()
	assert_almost_eq(head.rotation.y, 0.0, 0.001)
	assert_true(ctrl.get_camera_look_dir() is Vector3)
	assert_true(ctrl.get_camera_right_dir() is Vector3)


## Verifies drunk effect constants, exports, signal, and intensity transition contract.
func test_drunk_effect_contracts() -> void:
	var post_rect: ColorRect = ColorRect.new()
	post_rect.material = ShaderMaterial.new()
	add_child_autofree(post_rect)
	var cam: Camera3D = Camera3D.new()
	add_child_autofree(cam)

	var drunk: CanvasLayer = DRUNK_EFFECT_SCRIPT.new() as CanvasLayer
	assert_not_null(drunk)
	drunk.set(&"post_rect", post_rect)
	drunk.set(&"target_camera", cam)
	add_child_autofree(drunk)

	assert_true(drunk.has_signal(&"transition_completed"))
	assert_true(drunk.has_method(&"transition_intensity"))
	assert_almost_eq(float(drunk.get(&"sway_speed")), 2.5, 0.001)
	assert_almost_eq(float(drunk.get(&"max_roll_rad")), 0.08, 0.001)
	assert_almost_eq(float(drunk.get(&"max_fov_pulse")), 8.0, 0.001)
	assert_false(drunk.is_processing())

	drunk.call(&"transition_intensity", 0.5, 0.2)
	assert_true(drunk.is_processing())


## Verifies [PlayerEnvironmentComponent] constants, initialization, and zone tracking.
func test_environment_component_contracts() -> void:
	assert_eq(PlayerEnvironmentComponent.GROUP_WATERFALL, &"waterfall_area")
	assert_eq(PlayerEnvironmentComponent.STATE_LADDER, &"Ladder")
	assert_eq(PlayerEnvironmentComponent.STATE_AIR, &"Air")
	assert_eq(PlayerEnvironmentComponent.STATE_GROUND, &"Ground")
	assert_eq(PlayerEnvironmentComponent.STATE_SWIM, &"Swim")
	assert_eq(PlayerEnvironmentComponent.STATE_VAULT, &"Vault")
	assert_eq(PlayerEnvironmentComponent.STATE_ZIPLINE, &"Zipline")
	assert_eq(PlayerEnvironmentComponent.STATE_ROPE, &"Rope")
	assert_eq(PlayerEnvironmentComponent.STATE_TERMINAL, &"Terminal")
	assert_eq(PlayerEnvironmentComponent.ACTION_FORWARD, &"forward")
	assert_eq(PlayerEnvironmentComponent.KEY_LADDER_NODE, &"ladder_node")
	assert_almost_eq(PlayerEnvironmentComponent.LADDER_GROUND_ATTACH_PITCH, 0.50, 0.001)

	var body: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(body)
	var env_comp: PlayerEnvironmentComponent = PlayerEnvironmentComponent.new()
	add_child_autofree(env_comp)
	env_comp.initialize(body)
	assert_eq(env_comp.player, body)

	env_comp.start_zipline_cooldown(0.75)
	assert_almost_eq(env_comp.zipline_cooldown, 0.75, 0.001)

	env_comp.enter_updraft(12.0, 20.0)
	assert_true(env_comp.in_updraft)
	assert_almost_eq(env_comp.updraft_strength, 12.0, 0.001)
	assert_almost_eq(env_comp.updraft_top_y, 20.0, 0.001)
	env_comp.exit_updraft()
	assert_false(env_comp.in_updraft)


## Verifies [FastRope] scene instantiation, exports, and attach/detach methods.
func test_fast_rope_contracts() -> void:
	var rope: FastRope = FAST_ROPE_SCENE.instantiate() as FastRope
	assert_not_null(rope)
	add_child_autofree(rope)

	assert_almost_eq(rope.rope_length, 10.0, 0.001)
	assert_almost_eq(rope.ascend_speed, 15.0, 0.001)
	assert_almost_eq(rope.launch_velocity, 7.7, 0.001)
	assert_almost_eq(rope.label_offset_amount, 0.35, 0.001)
	assert_almost_eq(rope.climb_radius, 0.6, 0.001)
	assert_null(rope.attached_player)
	assert_true(rope.has_method(&"attach"))
	assert_true(rope.has_method(&"detach"))


## Verifies [FlashlightController] constants, exports, and default state.
func test_flashlight_controller_contracts() -> void:
	assert_almost_eq(FlashlightController.MAX_SWAY_BOUND, 150.0, 0.001)

	var spot: SpotLight3D = SpotLight3D.new()
	add_child_autofree(spot)
	var ctrl: FlashlightController = FlashlightController.new()
	ctrl.flashlight = spot
	add_child_autofree(ctrl)

	assert_false(spot.visible)

	assert_almost_eq(ctrl.flashlight_maintain_distance, 1.5, 0.001)
	assert_almost_eq(ctrl.base_energy, 10.0, 0.001)
	assert_almost_eq(ctrl.volumetric_energy, 8.0, 0.001)
	assert_almost_eq(ctrl.sway_amount, 5.0, 0.001)
	assert_almost_eq(ctrl.smooth_speed, 10.0, 0.001)
	assert_almost_eq(ctrl.flashlight_pos_smoothness, 10.0, 0.001)
	assert_almost_eq(ctrl.flashlight_rot_smoothness, 10.0, 0.001)
	assert_false(ctrl.is_flickering)


## Verifies [FootstepManager] surface constants, intervals, and public methods.
func test_footstep_manager_contracts() -> void:
	assert_eq(FootstepManager.SURFACE_ICE, &"ice")
	assert_eq(FootstepManager.SURFACE_METAL, &"metal")
	assert_eq(FootstepManager.SURFACE_STONE, &"stone")
	assert_eq(FootstepManager.SURFACE_WET, &"wet_dirt")
	assert_eq(FootstepManager.SURFACE_SNOW, &"snow")
	assert_almost_eq(FootstepManager.SLIDE_CARVE_DIST_SQ, 0.09, 0.001)
	assert_almost_eq(FootstepManager.MIN_CRATER_FALL_SPEED, 2.0, 0.001)

	var body: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(body)
	var fm: FootstepManager = FootstepManager.new()
	fm.player_body = body
	add_child_autofree(fm)

	assert_almost_eq(fm.walk_step_interval, 0.45, 0.001)
	assert_almost_eq(fm.sprint_step_interval, 0.28, 0.001)
	assert_almost_eq(fm.crouch_step_interval, 0.65, 0.001)
	assert_almost_eq(fm.ladder_step_interval, 0.55, 0.001)
	assert_almost_eq(fm.monkey_bar_step_interval, 0.65, 0.001)
	assert_almost_eq(fm.snow_stamp_radius, 24.0, 0.001)
	assert_almost_eq(fm.snow_slide_radius, 34.0, 0.001)
	assert_true(fm.has_method(&"process_surface_and_footsteps"))
	assert_true(fm.has_method(&"carve_slide"))
	assert_true(fm.has_method(&"stop_looping_sounds"))
	assert_true(fm.has_method(&"stamp_landing_crater"))
	fm.stop_looping_sounds()


## Verifies [NoteReader] shader constant, exports, and note lifecycle methods.
func test_note_reader_contracts() -> void:
	assert_not_null(NoteReader.ZOOM_SHADER)

	var reader: NoteReader = NoteReader.new()
	add_child_autofree(reader)

	assert_almost_eq(reader.sway_multiplier, 0.002, 0.0001)
	assert_almost_eq(reader.max_sway_angle, 0.1, 0.001)
	assert_almost_eq(reader.sway_return_speed, 5.0, 0.001)
	assert_almost_eq(reader.key_rotation_speed, 3.0, 0.001)
	assert_almost_eq(reader.mouse_rotation_speed, 0.005, 0.0001)
	assert_almost_eq(reader.hover_tilt_strength, 0.15, 0.001)
	assert_almost_eq(reader.reading_distance, 0.6, 0.001)
	assert_almost_eq(reader.max_radius, 0.4, 0.001)
	assert_almost_eq(reader.min_radius, 0.15, 0.001)
	assert_almost_eq(reader.max_zoom, 5.0, 0.001)
	assert_almost_eq(reader.min_zoom, 1.5, 0.001)
	assert_true(reader.has_method(&"open_note"))
	assert_true(reader.has_method(&"close_note"))


## Verifies [PlayerInteractionComponent] constants, defaults, and initialization.
func test_player_interaction_component_contracts() -> void:
	assert_almost_eq(PlayerInteractionComponent.HEAVY_OBJECT_MASS_THRESHOLD, 10.0, 0.001)
	assert_eq(PlayerInteractionComponent.DROP_REPICK_COOLDOWN_MSEC, 400)
	assert_almost_eq(PlayerInteractionComponent.CLAW_ATTACK_RANGE, 10.0, 0.001)
	assert_almost_eq(PlayerInteractionComponent.CLAW_ATTACK_RANGE_SQ, 100.0, 0.001)
	assert_almost_eq(PlayerInteractionComponent.CLAW_AIM_DOT_THRESHOLD, 0.819, 0.001)
	assert_almost_eq(PlayerInteractionComponent.CLAW_LUNGE_SPEED, 35.0, 0.001)
	assert_eq(PlayerInteractionComponent.CLAW_ATTACK_DAMAGE, 100)
	assert_eq(PlayerInteractionComponent.CLAW_TARGET_GROUPS, [&"enemy", &"enemies"])

	var body: CharacterBody3D = CharacterBody3D.new()
	add_child_autofree(body)
	var comp: PlayerInteractionComponent = PlayerInteractionComponent.new()
	add_child_autofree(comp)
	comp.initialize(body)

	assert_eq(comp.player, body)
	assert_almost_eq(comp.throw_strength, 15.0, 0.001)
	assert_null(comp.held_item)
	assert_false(comp.is_operating_machine)
	assert_false(comp.is_heavy_carrying)
	assert_false(comp.is_heavy_lifting)
	assert_false(comp.is_in_terminal_mode)
	assert_true(comp.has_method(&"process_interaction"))
	assert_true(comp.has_method(&"throw_held_item"))
	assert_true(comp.has_method(&"drop_held_item"))
	assert_true(comp.has_method(&"force_clear_hands"))
	assert_true(comp.has_method(&"force_grab_item"))
	assert_true(comp.has_method(&"attach_item_to_weapon_holder"))


## Verifies [InteractionScanner] signals, constants, exports, and master link setup.
func test_interaction_scanner_contracts() -> void:
	assert_eq(InteractionScanner.COMPONENT_NAME, &"InteractComponent")
	assert_eq(InteractionScanner.PROP_DISPLAY_NAME, &"display_name")
	assert_eq(InteractionScanner.PROP_IS_ENABLED, &"is_enabled")
	assert_eq(InteractionScanner.ACTION_INTERACT, &"interact")
	assert_eq(InteractionScanner.ACTION_SHOOT, &"shoot")
	assert_eq(InteractionScanner.ACTION_RELOAD, &"reload")
	assert_almost_eq(InteractionScanner.TERMINAL_RAYCAST_INTERVAL, 0.05, 0.001)

	var scanner: InteractionScanner = InteractionScanner.new()
	add_child_autofree(scanner)

	assert_true(scanner.has_signal(&"terminal_mode_toggled"))
	assert_true(scanner.has_signal(&"heavy_lift_state_changed"))
	assert_true(scanner.has_signal(&"object_hover_focused"))
	assert_almost_eq(scanner.base_reach, 0.7, 0.001)
	assert_almost_eq(scanner.floor_reach, 2.2, 0.001)
	assert_almost_eq(scanner.scan_interval, 0.1, 0.001)

	var master: PlayerInteractionComponent = PlayerInteractionComponent.new()
	add_child_autofree(master)
	scanner.setup_master_link(master)
	assert_eq(scanner.master_component, master)

	watch_signals(scanner)
	scanner.set_heavy_lifting(true)
	assert_true(scanner.is_heavy_lifting)
	assert_signal_emitted(scanner, "heavy_lift_state_changed")


## Verifies [PlayerState] input constants and base lifecycle interface.
func test_player_state_contracts() -> void:
	assert_eq(PlayerState.ACTION_LEFT, &"left")
	assert_eq(PlayerState.ACTION_RIGHT, &"right")
	assert_eq(PlayerState.ACTION_FORWARD, &"forward")
	assert_eq(PlayerState.ACTION_BACKWARD, &"backward")
	assert_eq(PlayerState.ACTION_JUMP, &"jump")
	assert_eq(PlayerState.ACTION_CROUCH, &"crouch")
	assert_eq(PlayerState.ACTION_SPRINT, &"sprint")
	assert_eq(PlayerState.ACTION_INTERACT, &"interact")
	assert_eq(PlayerState.ACTION_ZOOM, &"zoom")

	var p_state: PlayerState = PlayerState.new()
	add_child_autofree(p_state)
	assert_null(p_state.get_player())
	assert_true(p_state.has_method(&"enter"))
	assert_true(p_state.has_method(&"exit"))
	assert_true(p_state.has_method(&"handle_input"))
	assert_true(p_state.has_method(&"update"))
	assert_true(p_state.has_method(&"physics_update"))


## Verifies [PlayerStateMachine] signal and state transition routing.
func test_player_state_machine_contracts() -> void:
	var fsm: PlayerStateMachine = PlayerStateMachine.new()
	var state_a: PlayerState = PlayerState.new()
	state_a.name = "Ground"
	var state_b: PlayerState = PlayerState.new()
	state_b.name = "Air"
	fsm.add_child(state_a)
	fsm.add_child(state_b)
	add_child_autofree(fsm)

	assert_true(fsm.has_signal(&"transitioned"))
	watch_signals(fsm)
	var ok: bool = fsm.transition_to(&"Air")
	assert_true(ok)
	assert_eq(fsm.state, state_b)
	assert_signal_emitted_with_parameters(fsm, "transitioned", ["Air"])
	assert_false(fsm.transition_to(&"NonExistent"))


## Verifies procedural revolver constants, exports, signals, and ammo methods.
func test_procedural_revolver_contracts() -> void:
	var revolver: Node3D = REVOLVER_SCRIPT.new() as Node3D
	assert_not_null(revolver)
	add_child_autofree(revolver)

	assert_true(revolver.has_signal(&"shot_fired"))
	assert_true(revolver.has_signal(&"reload_completed"))
	assert_eq(revolver.get(&"weapon_tag"), "revolver")
	assert_eq(revolver.get(&"default_slot"), 1)
	assert_eq(revolver.get(&"ammo_type"), &"revolver_ammo")
	assert_eq(revolver.get(&"reserve_ammo"), 30)
	assert_true(revolver.has_method(&"sync_ammo_ui"))
	assert_true(revolver.has_method(&"shoot"))
	assert_true(revolver.has_method(&"reload"))
	assert_true(revolver.has_method(&"inspect"))


## Verifies [ProceduralStairs] defaults and smooth ramp mesh generation.
func test_procedural_stairs_contracts() -> void:
	var stairs: ProceduralStairs = ProceduralStairs.new()
	add_child_autofree(stairs)

	assert_eq(stairs.step_count, 10)
	assert_almost_eq(stairs.total_height, 2.0, 0.001)
	assert_almost_eq(stairs.total_length, 3.0, 0.001)
	assert_almost_eq(stairs.stair_width, 1.5, 0.001)
	assert_almost_eq(stairs.landing_extra_length, 1.0, 0.001)
	assert_almost_eq(stairs.top_landing_length, 1.5, 0.001)
	assert_true(stairs.fill_to_floor)
	assert_almost_eq(stairs.step_thickness, 0.2, 0.001)
	assert_true(stairs.generate_smooth_ramp)
	assert_not_null(stairs.mesh)
	assert_not_null(stairs.ramp_body)
	assert_not_null(stairs.ramp_collision)


## Verifies [ScreenVFXManager] defaults and rain/water/waterfall state transitions.
func test_screen_vfx_manager_contracts() -> void:
	var vfx: ScreenVFXManager = ScreenVFXManager.new()
	add_child_autofree(vfx)

	assert_false(vfx.in_rain_volume)
	assert_almost_eq(vfx.current_drop_intensity, 0.0, 0.001)
	assert_almost_eq(vfx.current_wash_intensity, 0.0, 0.001)
	assert_false(vfx.in_waterfall)

	vfx.set_rain_volume(true)
	assert_true(vfx.in_rain_volume)
	vfx.set_rain_volume(false)
	assert_false(vfx.in_rain_volume)

	vfx.enter_waterfall()
	assert_true(vfx.in_waterfall)
	vfx.exit_waterfall()
	assert_false(vfx.in_waterfall)
	vfx.set_underwater_state(false)
	vfx.trigger_surface_wipe()


## Verifies [StateLadder] constants and ladder enter/exit state lifecycle.
func test_state_ladder_contracts() -> void:
	assert_almost_eq(StateLadder.LADDER_SPEED, 5.0, 0.001)
	assert_almost_eq(StateLadder.MAX_LADDER_SIDE_DIST, 0.6, 0.001)
	assert_almost_eq(StateLadder.LADDER_CENTER_SNAP_SPEED, 8.0, 0.001)
	assert_almost_eq(StateLadder.LADDER_DEPTH_OFFSET, 0.1, 0.001)
	assert_almost_eq(StateLadder.LADDER_DEPTH_PULL_SPEED, 8.0, 0.001)
	assert_almost_eq(StateLadder.CLIMB_FACING_DOT_MIN, 0.6428, 0.0001)
	assert_almost_eq(StateLadder.CLIMB_DOWN_LOOK_PITCH, -0.50, 0.001)
	assert_almost_eq(StateLadder.GROUND_DISMOUNT_COOLDOWN, 0.15, 0.001)
	assert_almost_eq(StateLadder.JUMP_EJECT_COOLDOWN, 0.5, 0.001)
	assert_eq(StateLadder.STATE_GROUND, &"Ground")
	assert_eq(StateLadder.STATE_AIR, &"Air")
	assert_eq(StateLadder.KEY_LADDER_NODE, &"ladder_node")

	var ladder_state: StateLadder = StateLadder.new()
	add_child_autofree(ladder_state)
	var ladder_node: Node3D = Node3D.new()
	add_child_autofree(ladder_node)

	ladder_state.enter({StateLadder.KEY_LADDER_NODE: ladder_node})
	assert_null(ladder_state.current_ladder)
	ladder_state.exit()
	assert_null(ladder_state.current_ladder)


## Verifies [SystemMenuController] signals, defaults, and noclip/pause methods.
func test_system_menu_controller_contracts() -> void:
	assert_not_null(SystemMenuController.DEFAULT_MENU_SCENE)

	var ctrl: SystemMenuController = SystemMenuController.new()
	add_child_autofree(ctrl)

	assert_true(ctrl.has_signal(&"pause_toggled"))
	assert_true(ctrl.has_signal(&"noclip_toggled"))
	assert_almost_eq(ctrl.base_sprinting_speed, 6.5, 0.001)
	assert_almost_eq(ctrl.default_noclip_speed_multiplier, 8.0, 0.001)
	assert_almost_eq(ctrl.camera_tilt_amount, 3.0, 0.001)
	assert_almost_eq(ctrl.lerp_speed, 15.0, 0.001)
	assert_false(ctrl.is_paused)
	assert_false(ctrl.is_menu_open)
	assert_false(ctrl.flying)
	assert_true(ctrl.has_method(&"toggle_pause"))
	assert_true(ctrl.has_method(&"toggle_noclip"))
	assert_true(ctrl.has_method(&"process_noclip"))


## Verifies [VaultController] signals, defaults, and scan/vault methods.
func test_vault_controller_contracts() -> void:
	var vault: VaultController = VaultController.new()
	add_child_autofree(vault)

	assert_true(vault.has_signal(&"vault_started"))
	assert_true(vault.has_signal(&"vault_finished"))
	assert_true(vault.has_signal(&"crouch_state_changed"))
	assert_almost_eq(vault.max_step_height, 0.5, 0.001)
	assert_almost_eq(vault.crouching_depth, 0.7, 0.001)
	assert_almost_eq(vault.vault_depth_clearance, 0.5, 0.001)
	assert_almost_eq(vault.max_reach, 2.1, 0.001)
	assert_true(vault.auto_scan)
	assert_false(vault.is_vaulting)
	assert_false(vault.can_vault_current_ledge)
	assert_false(vault.try_vault(false))


## Verifies [Zipline] scene instantiation, constants, exports, and velocity getter.
func test_zipline_contracts() -> void:
	assert_eq(Zipline.GROUP_INTERACTABLE, &"interactable")

	var zip: Zipline = ZIPLINE_SCENE.instantiate() as Zipline
	assert_not_null(zip)
	add_child_autofree(zip)

	assert_almost_eq(zip.label_offset_amount, 0.35, 0.001)
	assert_false(zip.player_on_zipline)
	assert_null(zip.current_player)
	assert_eq(zip.get_current_travel_velocity(), Vector3.ZERO)
	assert_true(zip.has_method(&"force_grab_zipline"))
	assert_true(zip.has_method(&"interact_with"))
	assert_true(zip.has_method(&"on_player_released"))
