## Characterization tests locking Wave 11 public APIs, constants, signals, and behavior.
class_name TestWave11Characterization
extends GutTest

const DARK_MAN_SCENE: PackedScene = preload("res://enemies/dark_man/dark_man.tscn")
const ELF_DRONE_SCENE: PackedScene = preload("res://enemies/elf_drone.tscn")
const FLYING_TILE_SCENE: PackedScene = preload("res://enemies/flying_tile.tscn")
const HEX_SHIELD_SPHERE_SCENE: PackedScene = preload("res://enemies/hex_shield_sphere.tscn")
const DUMPSTER_SCENE: PackedScene = preload("res://interactables/dumpster/dumpster.tscn")
const CLIMB_ROPE_SCENE: PackedScene = preload("res://interactables/rope/climb_rope.tscn")
const SLIDE_TRACK_SCENE: PackedScene = preload("res://interactables/slide_track.tscn")
const STATIONARY_LASER_STAND_SCENE: PackedScene = preload(
	"res://interactables/stationary_laser_stand.tscn"
)
const TIMBER_JIB_CRANE_SCENE: PackedScene = preload("res://interactables/timber_jib_crane.tscn")


## Restores default input mouse mode after each test.
func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Verifies [DarkManVisuals] constants, exports, collision layers, and uniform helpers.
func test_dark_man_visuals_contracts() -> void:
	assert_eq(DarkManVisuals.PARAM_WEAR, &"wear_amount")
	assert_eq(DarkManVisuals.PARAM_TINT, &"tint_shift")
	assert_eq(DarkManVisuals.ANIM_IDLE_AXE, &"Idle_Hold_Axe")
	assert_not_null(DarkManVisuals.MAT_BODY)
	assert_not_null(DarkManVisuals.MAT_AXE)

	var dark_man: DarkManVisuals = DARK_MAN_SCENE.instantiate() as DarkManVisuals
	assert_not_null(dark_man)
	add_child_autofree(dark_man)

	assert_false(dark_man.is_processing())
	assert_false(dark_man.is_physics_processing())
	assert_eq(dark_man.collision_layer, CollisionLayers.MASK_ENEMIES)
	assert_almost_eq(dark_man.wear_amount, 0.15, 0.001)
	assert_eq(dark_man.tint_shift, Color(1.0, 1.0, 1.0, 1.0))
	assert_true(dark_man.auto_play_idle)

	var custom_tint: Color = Color(0.5, 0.6, 0.7, 1.0)
	dark_man.apply_instance_look(0.65, custom_tint)
	assert_almost_eq(dark_man.wear_amount, 0.65, 0.001)
	assert_eq(dark_man.tint_shift, custom_tint)

	dark_man.apply_instance_look(2.5, Color.WHITE)
	assert_almost_eq(dark_man.wear_amount, 1.0, 0.001)

	dark_man.play_idle_hold_axe()
	dark_man.set_axe_hitbox_active(true)
	dark_man.set_axe_hitbox_active(false)


## Verifies [ElfDrone] enums, signals, exports, and command methods.
func test_elf_drone_contracts() -> void:
	var drone: ElfDrone = ELF_DRONE_SCENE.instantiate() as ElfDrone
	assert_not_null(drone)
	add_child_autofree(drone)

	assert_has_signal(drone, &"reached_waypoint")
	assert_has_signal(drone, &"joined_flock")
	assert_eq(drone.move_speed, 7.0)
	assert_eq(drone.acceleration, 18.0)
	assert_eq(drone.arrival_distance, 1.5)
	assert_eq(drone.explore_radius, 30.0)
	assert_eq(drone.explore_interval, 4.0)
	assert_eq(drone.heal_range, 8.0)
	assert_eq(drone.task_state, ElfDrone.TaskState.EXPLORE)

	drone.set_target_position(Vector3(1.0, 2.0, 3.0))
	assert_eq(drone.target_position, Vector3(1.0, 2.0, 3.0))

	drone.join_flock()
	assert_eq(drone.task_state, ElfDrone.TaskState.JOIN_FLOCK)

	drone.start_bashing_obstacle()
	assert_eq(drone.task_state, ElfDrone.TaskState.BASH_OBSTACLE)

	drone.start_exploring()
	assert_eq(drone.task_state, ElfDrone.TaskState.EXPLORE)

	drone.navigate_to_waypoint(null)
	drone.set_healing_target(null)
	drone.set_glow_color(Color.CYAN)


## Verifies [FlyingTile] state enum, exports, and scene hierarchy.
func test_flying_tile_contracts() -> void:
	assert_eq(FlyingTile.State.IDLE, 0)
	assert_eq(FlyingTile.State.RISING, 1)
	assert_eq(FlyingTile.State.SPINNING, 2)
	assert_eq(FlyingTile.State.ATTACKING, 3)

	var tile: FlyingTile = FLYING_TILE_SCENE.instantiate() as FlyingTile
	assert_not_null(tile)
	add_child_autofree(tile)

	assert_eq(tile.damage, 1)
	assert_eq(tile.rise_height, 2.0)
	assert_eq(tile.rise_speed, 4.0)
	assert_eq(tile.spin_duration, 0.8)
	assert_eq(tile.attack_speed, 18.0)
	assert_eq(tile.lifetime_after_attack, 1.5)
	assert_not_null(tile.get_node_or_null(^"ActivationArea"))
	assert_not_null(tile.get_node_or_null(^"MeshInstance3D"))


## Verifies [HexShieldSphere] constants, signals, coverage clamping, and damage lifecycle.
func test_hex_shield_sphere_contracts() -> void:
	assert_eq(HexShieldSphere.LAYER_ENEMIES, 16)
	assert_eq(HexShieldSphere.RENDER_LAYER_ENV, 1)
	assert_eq(HexShieldSphere.PARAM_HIT_INTENSITY, &"hit_intensity")
	assert_eq(HexShieldSphere.PARAM_DAMAGE_RATIO, &"damage_ratio")
	assert_eq(HexShieldSphere.PARAM_OPACITY, &"opacity")
	assert_eq(HexShieldSphere.PROP_DISABLED, &"disabled")

	var shield: HexShieldSphere = HEX_SHIELD_SPHERE_SCENE.instantiate() as HexShieldSphere
	assert_not_null(shield)
	add_child_autofree(shield)

	assert_has_signal(shield, &"shield_hit")
	assert_has_signal(shield, &"shield_destroyed")
	assert_false(shield.is_processing())
	assert_false(shield.is_physics_processing())
	assert_eq(shield.radius, 2.0)
	assert_eq(shield.subdivisions, 2)
	assert_eq(shield.coverage, 1.0)
	assert_eq(shield.max_health, 100)
	assert_eq(shield.current_health, 100)
	assert_eq(shield.generation_duration, 0.85)
	assert_true(shield.auto_generate)

	shield.set_coverage(0.5)
	assert_almost_eq(shield.coverage, 0.5, 0.001)
	shield.set_coverage(2.0)
	assert_almost_eq(shield.coverage, 1.0, 0.001)

	watch_signals(shield)
	shield.take_damage(25, Vector3.FORWARD)
	assert_eq(shield.current_health, 75)
	assert_signal_emitted_with_parameters(shield, &"shield_hit", [75, 100, Vector3.FORWARD])

	shield.take_damage(100, Vector3.FORWARD)
	assert_eq(shield.current_health, 0)
	assert_signal_emitted(shield, &"shield_destroyed")


## Verifies [Dumpster] constants, signals, exports, and open/close state contracts.
func test_dumpster_contracts() -> void:
	assert_eq(Dumpster.NODE_LID, &"Dumpster_Body/Dumpster_Lid")
	assert_eq(Dumpster.NODE_BODY, &"Dumpster_Body")

	var dumpster: Dumpster = DUMPSTER_SCENE.instantiate() as Dumpster
	assert_not_null(dumpster)
	add_child_autofree(dumpster)

	assert_has_signal(dumpster, &"state_changed")
	assert_has_signal(dumpster, &"opened")
	assert_has_signal(dumpster, &"closed")
	assert_false(dumpster.is_processing())
	assert_false(dumpster.is_physics_processing())
	assert_eq(dumpster.open_angle_deg, -110.0)
	assert_eq(dumpster.swing_duration, 0.55)
	assert_true(dumpster.allow_player_interact)
	assert_false(dumpster.is_open)
	assert_false(dumpster.is_character_standing_inside())

	dumpster.open()
	assert_true(dumpster.is_open)
	dumpster.close()
	assert_false(dumpster.is_open)
	dumpster.toggle_open()
	assert_true(dumpster.is_open)
	dumpster.interact()
	assert_false(dumpster.is_open)


## Verifies [ClimbRope3D] enums, constants, grab clamping, and hand-point API.
func test_climb_rope_contracts() -> void:
	assert_eq(ClimbRope3D.Mode.CHAIN, 0)
	assert_eq(ClimbRope3D.Mode.SWING, 1)
	assert_eq(ClimbRope3D.MIN_GRAB_OFFSET, 1.0)
	assert_eq(ClimbRope3D.BOTTOM_GRAB_MARGIN, 0.25)
	assert_eq(ClimbRope3D.DEFAULT_REGRAB_COOLDOWN, 0.4)
	assert_eq(ClimbRope3D.STATE_ROPE, &"Rope")
	assert_eq(ClimbRope3D.KEY_ROPE, &"rope")
	assert_eq(ClimbRope3D.KEY_GRAB_DISTANCE, &"grab_distance")
	assert_eq(ClimbRope3D.ACTION_INTERACT, &"interact")

	var rope: ClimbRope3D = CLIMB_ROPE_SCENE.instantiate() as ClimbRope3D
	assert_not_null(rope)
	add_child_autofree(rope)

	assert_almost_eq(rope.clamp_grab_distance(0.0), ClimbRope3D.MIN_GRAB_OFFSET, 0.001)
	var expected_max: float = maxf(
		ClimbRope3D.MIN_GRAB_OFFSET, rope.length - ClimbRope3D.BOTTOM_GRAB_MARGIN
	)
	assert_almost_eq(rope.clamp_grab_distance(999.0), expected_max, 0.001)

	rope.set_hand_point(Vector3.ZERO, 2.0)
	rope.set_audio(false, false, 0.0)
	rope.clear_hand_point()
	rope.release(0.2)


## Verifies [SlideTrack] exports and [PathStick] synchronization in [method _ready].
func test_slide_track_contracts() -> void:
	var track: SlideTrack = SLIDE_TRACK_SCENE.instantiate() as SlideTrack
	assert_not_null(track)
	add_child_autofree(track)

	assert_eq(track.move_speed, 15.0)
	assert_eq(track.throw_speed_threshold, 8.0)
	assert_eq(track.throw_velocity_local, Vector3(0.0, 5.0, -20.0))
	assert_false(track.stay_at_end)
	assert_false(track.return_immediately)
	assert_not_null(track.path_stick)
	assert_eq(track.path_stick.move_speed, track.move_speed)
	assert_eq(track.path_stick.throw_speed_threshold, track.throw_speed_threshold)
	assert_eq(track.path_stick.throw_velocity_local, track.throw_velocity_local)
	assert_eq(track.path_stick.stay_at_end, track.stay_at_end)
	assert_eq(track.path_stick.return_immediately, track.return_immediately)


## Verifies [StationaryLaserStand] constants, exports, child nodes, and pool setup.
func test_stationary_laser_stand_contracts() -> void:
	assert_eq(StationaryLaserStand.MAX_TRAIL_DECALS, 60)
	assert_eq(StationaryLaserStand.DETACH_COOLDOWN_SEC, 0.35)
	assert_eq(StationaryLaserStand.REATTACH_COOLDOWN_SEC, 0.4)
	assert_eq(StationaryLaserStand.ALIGN_TWEEN_DURATION_SEC, 0.3)

	var stand: StationaryLaserStand = (
		STATIONARY_LASER_STAND_SCENE.instantiate() as StationaryLaserStand
	)
	assert_not_null(stand)
	add_child_autofree(stand)

	assert_eq(stand.damage_per_second, 25.0)
	assert_eq(stand.max_distance, 25.0)
	assert_eq(stand.max_bounces, 5)
	assert_eq(stand.rotation_speed, 1.5)
	assert_eq(stand.mouse_sensitivity, 0.003)
	assert_false(stand.is_controlled)
	assert_null(stand.controlling_player)
	assert_not_null(stand.turret)
	assert_not_null(stand.laser_origin)
	assert_not_null(stand.base_beam_mesh)
	assert_not_null(stand.interact_comp)
	assert_not_null(stand.trail_pool)


## Verifies [TimberJibCrane] constants, signals, rail math, and capstan push contracts.
func test_timber_jib_crane_contracts() -> void:
	assert_eq(TimberJibCrane.GROUP_INTERACTABLE, &"interactable")
	assert_eq(TimberJibCrane.GROUP_INTERACTABLES, &"interactables")
	assert_eq(TimberJibCrane.GROUP_NOT_CLIMBABLE, &"not_climbable")
	assert_eq(TimberJibCrane.STATE_PUSH_WHEEL, &"PushWheel")
	assert_eq(TimberJibCrane.STATE_JIB_CRANE, &"JibCrane")
	assert_eq(TimberJibCrane.STATE_ROPE, &"Rope")
	assert_eq(TimberJibCrane.BASE_SURFACE_Y, 0.20)

	var crane: TimberJibCrane = TIMBER_JIB_CRANE_SCENE.instantiate() as TimberJibCrane
	assert_not_null(crane)
	add_child_autofree(crane)

	assert_has_signal(crane, &"angle_changed")
	assert_has_signal(crane, &"powered_on")
	assert_has_signal(crane, &"powered_off")
	assert_has_signal(crane, &"jib_player_mounted")
	assert_has_signal(crane, &"jib_player_dismounted")

	assert_true(crane.is_installed)
	assert_false(crane.is_locked)
	assert_eq(crane.initial_angle_deg, 0.0)
	assert_true(crane.limit_rotation)
	assert_eq(crane.min_angle_deg, -90.0)
	assert_eq(crane.max_angle_deg, 90.0)
	assert_eq(crane.current_angle_deg, 0.0)

	assert_almost_eq(crane.clamp_rail_offset(0.0), crane.rail_start_offset, 0.001)
	assert_almost_eq(crane.clamp_rail_offset(999.0), crane.rail_end_offset, 0.001)
	assert_eq(crane.get_rail_point_velocity(crane.rail_start_offset), Vector3.ZERO)
	assert_almost_eq(crane.get_rail_world_direction().length(), 1.0, 0.001)
	var rail_pos: Vector3 = crane.get_rail_world_position(crane.rail_start_offset)
	assert_almost_eq(
		crane.project_world_pos_to_rail_offset(rail_pos), crane.rail_start_offset, 0.01
	)
	assert_almost_eq(crane.get_pivot_global_yaw_rad(), 0.0, 0.001)

	watch_signals(crane)
	crane.on_push_started()
	crane.push(0.5)
	assert_gt(crane.current_angle_deg, 0.0)
	assert_gt(crane.progress, 0.5)
	assert_signal_emitted(crane, &"angle_changed")
	crane.on_push_ended()
