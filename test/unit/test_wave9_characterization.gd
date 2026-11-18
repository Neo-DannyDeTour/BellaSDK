## Characterization tests locking Wave 9 public APIs, constants, signals, and behavior.
class_name TestWave9Characterization
extends GutTest

const BREAKABLE_CRATE_SCENE: PackedScene = preload("res://interactables/breakable_crate.tscn")
const BURNABLE_OBSTACLE_SCENE: PackedScene = preload("res://interactables/burnable_obstacle.tscn")
const BUTTON_SCENE: PackedScene = preload("res://interactables/button.tscn")
const CINDER_BLOCK_SCENE: PackedScene = preload(
	"res://interactables/cinder_block/cinder_block.tscn"
)
const COMBINATION_LOCK_SCENE: PackedScene = preload("res://interactables/combination_lock.tscn")
const COMBUSTIBLE_OBJECT_SCRIPT: GDScript = preload("res://interactables/combustible_object.gd")
const DOOR_INTERACT_SCENE: PackedScene = preload("res://interactables/door_interact.tscn")
const DOOR_KEYPAD_SCENE: PackedScene = preload("res://interactables/door_keypad.tscn")
const DOUBLE_SLIDING_DOORS_SCENE: PackedScene = preload(
	"res://interactables/double_sliding_doors.tscn"
)
const ENGINE_RAMP_SCENE: PackedScene = preload("res://interactables/engine_ramp.tscn")
const EXPLOSIVE_BARREL_SCENE: PackedScene = preload("res://interactables/explosive_barrel.tscn")
const FEEDBACK_STATION_SCENE: PackedScene = preload("res://interactables/feedback_station.tscn")
const GAS_STOVE_SCENE: PackedScene = preload("res://interactables/gas_stove.tscn")
const GAS_STOVE_SCRIPT: GDScript = preload("res://interactables/gas_stove.gd")
const GROUND_BUTTON_SCENE: PackedScene = preload("res://interactables/ground_button.tscn")
const HEALTH_UPGRADE_SCENE: PackedScene = preload("res://interactables/health_upgrade.tscn")
const KEYCARD_LOCK_SCENE: PackedScene = preload("res://interactables/keycard_lock.tscn")
const KEYCARD_PICKUP_SCENE: PackedScene = preload("res://interactables/keycard_pickup.tscn")
const LADDER_4M_SCENE: PackedScene = preload("res://interactables/ladder_4m.tscn")
const LASER_TARGET_SCENE: PackedScene = preload("res://interactables/laser_target.tscn")
const MANNEQUIN_RAGDOLL_SCENE: PackedScene = preload("res://interactables/mannequin_ragdoll.tscn")
const NOTE_ITEM_SCENE: PackedScene = preload("res://interactables/note_item.tscn")
const PICKABLE_OBJECT_SCENE: PackedScene = preload("res://interactables/pickable_object.tscn")
const PLAYER_DRONE_SCENE: PackedScene = preload("res://interactables/player_drone.tscn")
const PORTAL_SCENE: PackedScene = preload("res://interactables/portal.tscn")
const PULLEY_SCENE: PackedScene = preload("res://interactables/pulley.tscn")
const PUZZLE_SOCKET_SCENE: PackedScene = preload("res://interactables/puzzle_socket.tscn")
const REFLECTOR_MIRROR_SCENE: PackedScene = preload("res://interactables/reflector_mirror.tscn")
const UNIVERSAL_CABLE_SCRIPT: GDScript = preload("res://interactables/universal_cable_3d.gd")
const VALVE_BASE_SCENE: PackedScene = preload("res://interactables/valve_base.tscn")


## Restores default input mouse mode after each test.
func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Verifies [BreakableCrate] constants, signals, exports, and damage-to-break contract.
func test_breakable_crate_contracts() -> void:
	assert_eq(BreakableCrate.PARAM_FADE, &"fade")
	assert_eq(BreakableCrate.DEBRIS_MASS, 1.8)
	assert_eq(BreakableCrate.RADIAL_BLAST_STRENGTH, 3.5)
	assert_eq(BreakableCrate.HIT_IMPULSE_TRANSFER, 0.35)
	assert_eq(BreakableCrate.DEBRIS_LIFETIME, 6.0)
	assert_eq(BreakableCrate.DEBRIS_FADE_DURATION, 1.0)
	assert_eq(BreakableCrate.DEBRIS_TORQUE_STRENGTH, 1.5)
	assert_eq(BreakableCrate.SELF_DAMAGE_SPEED_RATIO, 1.5)
	assert_eq(BreakableCrate.PLAYER_STOMP_SPEED_THRESHOLD, -7.0)
	assert_eq(BreakableCrate.CRATE_FALL_SPEED_THRESHOLD, -6.0)
	assert_eq(BreakableCrate.FALL_DAMAGE_RATIO, 4.0)

	var crate: BreakableCrate = BREAKABLE_CRATE_SCENE.instantiate() as BreakableCrate
	assert_not_null(crate)
	add_child_autofree(crate)
	assert_has_signal(crate, &"broken")
	assert_eq(crate.max_health, 25.0)
	assert_not_null(crate.intact_mesh)
	assert_not_null(crate.intact_collision)
	assert_not_null(crate.debris_root)

	watch_signals(crate)
	crate.take_damage(100, Vector3.ZERO, Vector3.FORWARD)
	assert_signal_emitted(crate, &"broken")


## Verifies [BurnableObstacle] defaults, mesh_size setter, and node resolution.
func test_burnable_obstacle_contracts() -> void:
	var obstacle: BurnableObstacle = BURNABLE_OBSTACLE_SCENE.instantiate() as BurnableObstacle
	assert_not_null(obstacle)
	add_child_autofree(obstacle)

	assert_eq(obstacle.burn_duration, 2.0)
	assert_true(is_instance_valid(obstacle.mesh_instance))
	assert_true(is_instance_valid(obstacle.collision_shape))
	assert_true(is_instance_valid(obstacle.trigger_area))

	obstacle.set_mesh_size(Vector2(3.5, 2.5))
	assert_eq(obstacle.mesh_size, Vector2(3.5, 2.5))


## Verifies [LogicButton] defaults, transmitter sync, and cooldown state.
func test_logic_button_contracts() -> void:
	var button: LogicButton = BUTTON_SCENE.instantiate() as LogicButton
	assert_not_null(button)
	add_child_autofree(button)

	assert_eq(button.global_event_name, "")
	assert_true(button.can_press)
	assert_true(is_instance_valid(button.interact_component))

	var target: Node3D = Node3D.new()
	add_child_autofree(target)
	button.targets = [target]
	if is_instance_valid(button.transmitter):
		assert_eq(button.transmitter.targets.size(), 1)


## Verifies [CinderBlock] constants, mass, and throw impulse contract.
func test_cinder_block_contracts() -> void:
	assert_eq(CinderBlock.BLOCK_MASS_KG, 17.0)
	assert_eq(CinderBlock.IMPACT_VEL_SQ_THRESHOLD, 4.0)
	assert_eq(CinderBlock.PARAM_GRIME_SEED, &"grime_seed")

	var block: CinderBlock = CINDER_BLOCK_SCENE.instantiate() as CinderBlock
	assert_not_null(block)
	add_child_autofree(block)

	assert_almost_eq(block.mass, CinderBlock.BLOCK_MASS_KG, 0.01)
	assert_not_null(block.mesh_instance)
	assert_not_null(block.collision_shape)
	assert_true(block.has_method(&"apply_throw_impulse"))


## Verifies [CombinationLock] exports and secret_code normalization.
func test_combination_lock_contracts() -> void:
	var lock: CombinationLock = COMBINATION_LOCK_SCENE.instantiate() as CombinationLock
	assert_not_null(lock)
	lock.secret_code = "abcde"
	add_child_autofree(lock)

	assert_eq(lock.secret_code, "ABC")
	assert_false(lock.use_letters)
	assert_false(lock.enable_auto_light)
	assert_null(lock.interacting_player)


## Verifies [CombustibleObject] constants, signals, heat accumulation, ignition, and extinguish.
func test_combustible_object_contracts() -> void:
	assert_eq(CombustibleObject.DEFAULT_IGNITION_THRESHOLD, 100.0)
	assert_eq(CombustibleObject.INTERACTIVE_PHYSICS_LAYER, 4)
	assert_eq(CombustibleObject.PROPAGATION_PHYSICS_MASK, 30)

	var obj: CombustibleObject = COMBUSTIBLE_OBJECT_SCRIPT.new() as CombustibleObject
	assert_not_null(obj)
	add_child_autofree(obj)

	assert_has_signal(obj, &"ignited")
	assert_has_signal(obj, &"burned_down")
	assert_has_signal(obj, &"temperature_changed")
	assert_eq(obj.collision_layer, CombustibleObject.INTERACTIVE_PHYSICS_LAYER)
	assert_eq(obj.temperature, 0.0)

	watch_signals(obj)
	obj.apply_heat(40.0)
	assert_almost_eq(obj.temperature, 40.0, 0.01)
	assert_signal_emitted(obj, &"temperature_changed")
	assert_signal_not_emitted(obj, &"ignited")

	obj.apply_heat(60.0)
	assert_signal_emitted(obj, &"ignited")

	obj.extinguish()
	assert_eq(obj.temperature, 0.0)


## Verifies [DoorInteract] exports, manual toggle, and cooldown contract.
func test_door_interact_contracts() -> void:
	var door: DoorInteract = DOOR_INTERACT_SCENE.instantiate() as DoorInteract
	assert_not_null(door)
	add_child_autofree(door)

	assert_eq(door.required_power, 1)
	assert_false(door.open)
	assert_false(door.is_on_cooldown)

	if not door.is_powered_door:
		door.interact()
		assert_true(door.open)
		assert_true(door.is_on_cooldown)


## Verifies [DoorKeypad] signals, defaults, and 3D-to-viewport coordinate mapping.
func test_door_keypad_contracts() -> void:
	var keypad: DoorKeypad = DOOR_KEYPAD_SCENE.instantiate() as DoorKeypad
	assert_not_null(keypad)
	add_child_autofree(keypad)

	assert_has_signal(keypad, &"code_accepted")
	assert_eq(keypad.valid_code, "1234")
	assert_false(keypad.captures_wasd)
	assert_almost_eq(keypad.numeric_mouse_sensitivity_scale, 0.5, 0.001)
	assert_true(keypad.has_method(&"clear_mouse_hover"))
	assert_true(keypad.has_method(&"request_viewport_refresh"))
	assert_true(keypad.has_method(&"get_viewport_pos_from_3d"))
	assert_true(keypad.has_method(&"inject_mouse_motion"))
	assert_true(keypad.has_method(&"inject_mouse_click"))


## Verifies [DoubleSlidingDoors] enum, defaults, state transitions, and reset.
func test_double_sliding_doors_contracts() -> void:
	assert_eq(DoubleSlidingDoors.State.CLOSED, 0)
	assert_eq(DoubleSlidingDoors.State.RIGHT_OPEN, 1)
	assert_eq(DoubleSlidingDoors.State.LEFT_OPEN, 2)

	var doors: DoubleSlidingDoors = DOUBLE_SLIDING_DOORS_SCENE.instantiate() as DoubleSlidingDoors
	assert_not_null(doors)
	add_child_autofree(doors)

	assert_eq(doors.slide_dist, 2.0)
	assert_eq(doors.speed, 0.4)
	assert_eq(doors.double_click_delay, 300)
	assert_eq(doors.current_state, DoubleSlidingDoors.State.CLOSED)
	assert_false(doors.is_processing())

	doors.transition_to(DoubleSlidingDoors.State.RIGHT_OPEN)
	assert_eq(doors.current_state, DoubleSlidingDoors.State.RIGHT_OPEN)

	doors.reset_doors()
	assert_eq(doors.current_state, DoubleSlidingDoors.State.CLOSED)


## Verifies [EngineRamp] constants, signals, exports, and toggle/power contracts.
func test_engine_ramp_contracts() -> void:
	assert_almost_eq(EngineRamp.MIN_ANGLE_DELTA_DEG, 0.05, 0.001)

	var ramp: EngineRamp = ENGINE_RAMP_SCENE.instantiate() as EngineRamp
	assert_not_null(ramp)
	add_child_autofree(ramp)

	assert_has_signal(ramp, &"ramp_started")
	assert_has_signal(ramp, &"ramp_stopped")
	assert_has_signal(ramp, &"lever_toggled")
	assert_eq(ramp.ramp_length, 4.0)
	assert_eq(ramp.ramp_width, 2.0)
	assert_eq(ramp.max_angle_deg, 110.0)
	assert_eq(ramp.deg_per_sec, 35.0)
	assert_true(ramp.has_method(&"interact_with"))
	assert_true(ramp.has_method(&"toggle"))
	assert_true(ramp.has_method(&"power_on"))
	assert_true(ramp.has_method(&"power_off"))


## Verifies [ExplosiveBarrel] exports and inheritance from [PickableObject].
func test_explosive_barrel_contracts() -> void:
	var barrel: ExplosiveBarrel = EXPLOSIVE_BARREL_SCENE.instantiate() as ExplosiveBarrel
	assert_not_null(barrel)
	add_child_autofree(barrel)

	assert_true(barrel is PickableObject)
	assert_eq(barrel.max_health, 10)
	assert_eq(barrel.max_distance, 3.0)
	assert_eq(barrel.max_force, 50.0)
	assert_eq(barrel.chain_reaction_threshold, 1.5)
	assert_eq(barrel.shockwave_radius, 5.0)
	assert_true(barrel.has_method(&"take_damage"))
	assert_true(barrel.has_method(&"explode"))


## Verifies [FeedbackStation] default URL and focus/unfocus label modulate state.
func test_feedback_station_contracts() -> void:
	var station: FeedbackStation = FEEDBACK_STATION_SCENE.instantiate() as FeedbackStation
	assert_not_null(station)
	add_child_autofree(station)

	assert_eq(station.form_url, "https://forms.gle/JnrmTWLiLv5Mhzfg8")
	assert_true(is_instance_valid(station.interact_comp))
	station._on_focused()
	if is_instance_valid(station.label):
		assert_eq(station.label.modulate, Color(0.2, 1.0, 0.2))
	station._on_unfocused()
	if is_instance_valid(station.label):
		assert_eq(station.label.modulate, Color.WHITE)


## Verifies GasStove constants, physics layers, idle processing, and grime export.
func test_gas_stove_contracts() -> void:
	assert_eq(GAS_STOVE_SCRIPT.get(&"STOVE_SIZE"), Vector3(0.85, 0.78, 0.55))
	assert_eq(GAS_STOVE_SCRIPT.get(&"STOVE_MASS"), 45.0)
	assert_eq(GAS_STOVE_SCRIPT.get(&"PARAM_GRIME"), &"grime_amount")

	var stove: RigidBody3D = GAS_STOVE_SCENE.instantiate() as RigidBody3D
	assert_not_null(stove)
	add_child_autofree(stove)

	assert_almost_eq(stove.mass, 45.0, 0.01)
	assert_eq(stove.collision_layer, CollisionLayers.MASK_DEBRIS)
	assert_true(stove.can_sleep)
	assert_false(stove.is_processing())
	assert_false(stove.is_physics_processing())


## Verifies [GroundButton] body counting, press/release state, and target syncing.
func test_ground_button_contracts() -> void:
	var btn: GroundButton = GROUND_BUTTON_SCENE.instantiate() as GroundButton
	assert_not_null(btn)
	add_child_autofree(btn)

	assert_eq(btn.bodies_on_button, 0)
	assert_false(btn.is_pressed)
	assert_false(btn.is_processing())

	var dummy: Node3D = Node3D.new()
	add_child_autofree(dummy)
	btn._on_area_3d_body_entered(dummy)
	assert_eq(btn.bodies_on_button, 1)
	assert_true(btn.is_pressed)

	btn._on_area_3d_body_exited(dummy)
	assert_eq(btn.bodies_on_button, 0)
	assert_false(btn.is_pressed)


## Verifies [HealthUpgrade] default bonus and prompt visibility on focus.
func test_health_upgrade_contracts() -> void:
	var upgrade: HealthUpgrade = HEALTH_UPGRADE_SCENE.instantiate() as HealthUpgrade
	assert_not_null(upgrade)
	add_child_autofree(upgrade)

	assert_eq(upgrade.health_bonus, 25)
	assert_true(upgrade.has_method(&"interact_with"))
	if is_instance_valid(upgrade.prompt_label):
		assert_false(upgrade.prompt_label.visible)


## Verifies [KeycardLock] exports, signals, and default card settings.
func test_keycard_lock_contracts() -> void:
	var lock: KeycardLock = KEYCARD_LOCK_SCENE.instantiate() as KeycardLock
	assert_not_null(lock)
	add_child_autofree(lock)

	assert_has_signal(lock, &"access_granted")
	assert_eq(lock.required_card_id, &"R")
	assert_eq(lock.lock_color, Color.RED)
	assert_true(is_instance_valid(lock.interact_component))


## Verifies [KeycardPickup] exports and safe no-op when card_data is null.
func test_keycard_pickup_contracts() -> void:
	var pickup: KeycardPickup = KEYCARD_PICKUP_SCENE.instantiate() as KeycardPickup
	assert_not_null(pickup)
	add_child_autofree(pickup)

	assert_true(is_instance_valid(pickup.interact_component))
	assert_true(is_instance_valid(pickup.top_face_sprite))
	pickup.card_data = null
	pickup._on_interacted(null)
	assert_false(pickup.is_queued_for_deletion())


## Verifies [Ladder4M] idle processing and climbable state synchronization.
func test_ladder_4m_contracts() -> void:
	var ladder: Ladder4M = LADDER_4M_SCENE.instantiate() as Ladder4M
	assert_not_null(ladder)
	add_child_autofree(ladder)

	assert_true(ladder.climbable)
	assert_false(ladder.is_processing())
	assert_false(ladder.is_physics_processing())

	ladder.climbable = false
	assert_false(ladder.climbable)
	ladder.climbable = true
	assert_true(ladder.climbable)


## Verifies [LaserTarget] signals and power_on/power_off state emission.
func test_laser_target_contracts() -> void:
	var target: LaserTarget = LASER_TARGET_SCENE.instantiate() as LaserTarget
	assert_not_null(target)
	add_child_autofree(target)

	assert_has_signal(target, &"activated")
	assert_has_signal(target, &"deactivated")

	watch_signals(target)
	target.power_on()
	assert_signal_emitted(target, &"activated")
	target.power_off()
	assert_signal_emitted(target, &"deactivated")


## Verifies [MannequinRagdoll] constants, signals, skeleton, and physical bone queries.
func test_mannequin_ragdoll_contracts() -> void:
	assert_eq(MannequinRagdoll.GROUP_DAMAGEABLE, &"damageable")
	assert_eq(MannequinRagdoll.BONE_PELVIS, &"Pelvis")
	assert_eq(MannequinRagdoll.BONE_CHEST, &"Chest")
	assert_almost_eq(MannequinRagdoll.DEFAULT_LINEAR_DAMP, 0.45, 0.001)
	assert_almost_eq(MannequinRagdoll.DEFAULT_ANGULAR_DAMP, 2.20, 0.001)

	var ragdoll: MannequinRagdoll = MANNEQUIN_RAGDOLL_SCENE.instantiate() as MannequinRagdoll
	assert_not_null(ragdoll)
	add_child_autofree(ragdoll)

	assert_has_signal(ragdoll, &"ragdoll_activated")
	assert_not_null(ragdoll.get_skeleton())
	assert_gt(ragdoll.get_physical_bone_count(), 0)
	assert_not_null(ragdoll.get_physical_bone(MannequinRagdoll.BONE_PELVIS))


## Verifies [NoteItem] collision layer, prompt text, and public interaction methods.
func test_note_item_contracts() -> void:
	var note: NoteItem = NOTE_ITEM_SCENE.instantiate() as NoteItem
	assert_not_null(note)
	add_child_autofree(note)

	assert_eq(note.collision_layer, CollisionLayers.MASK_INTERACTIVE)
	assert_eq(note.collision_mask, CollisionLayers.MASK_NONE)
	assert_eq(note.get_interaction_prompt(), "Read Note")
	assert_almost_eq(note.max_size_meters, 0.3, 0.001)
	assert_true(note.has_method(&"set_highlight"))
	assert_true(note.has_method(&"interact"))
	assert_true(note.has_method(&"interact_with"))


## Verifies [PickableObject] constants, defaults, and public carry/drop API.
func test_pickable_object_contracts() -> void:
	assert_almost_eq(PickableObject.MIN_HOLD_DISTANCE, 1.2, 0.001)

	var obj: PickableObject = PICKABLE_OBJECT_SCENE.instantiate() as PickableObject
	assert_not_null(obj)
	add_child_autofree(obj)

	assert_almost_eq(obj.float_force, 1.3, 0.001)
	assert_almost_eq(obj.heavy_mass_threshold, 10.0, 0.001)
	assert_eq(obj.projectile_damage, 20)
	assert_true(obj.lock_on_player_stand)
	assert_true(obj.has_method(&"pick_up"))
	assert_true(obj.has_method(&"drop"))
	assert_true(obj.has_method(&"throw"))
	assert_true(obj.has_method(&"is_on_floor_approx"))
	assert_true(obj.has_method(&"set_model_transparency"))


## Verifies [PlayerDrone] defaults and possess/exit state transitions.
func test_player_drone_contracts() -> void:
	var drone: PlayerDrone = PLAYER_DRONE_SCENE.instantiate() as PlayerDrone
	assert_not_null(drone)
	add_child_autofree(drone)

	assert_eq(drone.move_speed, 8.0)
	assert_eq(drone.vertical_speed, 5.0)
	assert_false(drone.is_possessed)
	assert_false(drone.camera.current)

	drone.possess_drone()
	assert_true(drone.is_possessed)
	assert_true(drone.camera.current)

	drone.exit_drone()
	assert_false(drone.is_possessed)
	assert_false(drone.camera.current)


## Verifies [Portal] default settings and viewport/far-plane invariants.
func test_portal_contracts() -> void:
	var portal: Portal = PORTAL_SCENE.instantiate() as Portal
	assert_not_null(portal)
	add_child_autofree(portal)

	assert_eq(portal.max_render_distance, 30.0)
	assert_eq(portal.max_viewport_size, Vector2i(512, 512))
	assert_eq(portal.cull_far, 35.0)


## Verifies [PulleyConstraint3D] defaults and rope length calibration.
func test_pulley_constraint_contracts() -> void:
	var pulley: PulleyConstraint3D = PULLEY_SCENE.instantiate() as PulleyConstraint3D
	assert_not_null(pulley)
	add_child_autofree(pulley)

	assert_eq(pulley.tension_stiffness, 250.0)
	assert_eq(pulley.damping, 10.0)
	assert_eq(pulley.max_travel_meters, 0.0)
	assert_eq(pulley.hard_stop_stiffness, 1000.0)
	assert_true(pulley.has_method(&"calibrate_rope_length"))


## Verifies [PuzzleSocket] constants, signals, and power_source/plug contracts.
func test_puzzle_socket_contracts() -> void:
	assert_eq(PuzzleSocket.PREVIEW_PARTICLES_NAME, "EditorPowerSourcePreview")

	var socket: PuzzleSocket = PUZZLE_SOCKET_SCENE.instantiate() as PuzzleSocket
	assert_not_null(socket)
	add_child_autofree(socket)

	assert_has_signal(socket, &"socket_powered_on")
	assert_has_signal(socket, &"socket_powered_off")
	assert_true(socket.can_be_unplugged)
	assert_true(socket.has_method(&"interact_with"))
	assert_true(socket.has_method(&"plug_in"))
	assert_true(socket.has_method(&"unplug"))


## Verifies [ReflectorMirror] constants, reflection normal calculation, and RID query.
func test_reflector_mirror_contracts() -> void:
	assert_almost_eq(ReflectorMirror.DETACH_COOLDOWN_SEC, 0.35, 0.001)
	assert_almost_eq(ReflectorMirror.REATTACH_COOLDOWN_SEC, 0.4, 0.001)
	assert_almost_eq(ReflectorMirror.ALIGN_TWEEN_DURATION_SEC, 0.3, 0.001)

	var mirror: ReflectorMirror = REFLECTOR_MIRROR_SCENE.instantiate() as ReflectorMirror
	assert_not_null(mirror)
	add_child_autofree(mirror)

	assert_almost_eq(mirror.rotation_speed, 1.5, 0.001)
	assert_almost_eq(mirror.mouse_sensitivity, 0.003, 0.0001)
	var rids: Array[RID] = mirror.get_all_rids()
	assert_true(rids.has(mirror.get_rid()))
	var refl: Vector3 = mirror.get_reflection_normal(Vector3.UP)
	assert_almost_eq(refl.length(), 1.0, 0.001)


## Verifies [UniversalCable3D] default 2-point curve initialization and cylinder updates.
func test_universal_cable_3d_contracts() -> void:
	var cable: UniversalCable3D = UNIVERSAL_CABLE_SCRIPT.new() as UniversalCable3D
	assert_not_null(cable)
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	cable.add_child(mesh_inst)
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	cable.add_child(col_shape)
	add_child_autofree(cable)

	assert_not_null(cable.curve)
	assert_eq(cable.curve.get_point_count(), 2)
	assert_true(mesh_inst.mesh is CylinderMesh)
	assert_true(col_shape.shape is CylinderShape3D)


## Verifies [Valve] enum, constants, defaults, and installation settings.
func test_valve_contracts() -> void:
	assert_eq(Valve.TurnMode.SETTINGS_DEFAULT, 0)
	assert_eq(Valve.TurnMode.HOLD, 1)
	assert_eq(Valve.TurnMode.ONE_TIME_PRESS, 2)
	assert_eq(Valve.TurnMode.RAPID_MASH, 3)
	assert_almost_eq(Valve.DOUBLE_TAP_DELAY, 0.3, 0.001)
	assert_almost_eq(Valve.MASH_IMPULSE_STEP, 0.15, 0.001)

	var valve: Valve = VALVE_BASE_SCENE.instantiate() as Valve
	assert_not_null(valve)
	add_child_autofree(valve)

	assert_eq(valve.turn_duration, 3.0)
	assert_eq(valve.visual_rotations, 2.0)
	assert_true(valve.turn_clockwise)
	assert_false(valve.is_back_and_forth)
	assert_eq(valve.spin_axis, Vector3(0.0, 1.0, 0.0))
