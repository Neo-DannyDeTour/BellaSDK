## Unit tests verifying TimberJibCrane v3 (single-circle base, 2.5x wide boom, PushWheelState).
class_name TestTimberJibCrane
extends GutTest

## Packed crane scene preloaded for instantiation tests.
const CRANE_SCENE: PackedScene = preload("res://interactables/timber_jib_crane.tscn")

## Packed player scene preloaded for state machine integration tests.
const PLAYER_SCENE: PackedScene = preload("res://player/player.tscn")

## Crane instance under test.
var crane: TimberJibCrane = null


## Instantiates a fresh TimberJibCrane before each test.
func before_each() -> void:
	crane = CRANE_SCENE.instantiate() as TimberJibCrane
	assert_not_null(crane, "TimberJibCrane scene should instantiate.")
	add_child_autofree(crane)
	await get_tree().process_frame


## Verifies single-circle base collider, 2.5x wide boom, scoped highlights, and climb groups.
func test_single_circle_base_wide_boom_and_scoped_highlights() -> void:
	assert_not_null(crane.wheel, "PivotBody wheel reference should be assigned.")
	assert_almost_eq(crane.rail_height, 9.75, 0.01, "2x crane rail_height should be 9.75m.")
	assert_almost_eq(
		crane.rail_end_offset, 13.85, 0.01, "2x crane rail_end_offset should be 13.85m."
	)
	assert_false(crane.is_processing(), "Crane should disable _process when idle.")
	assert_false(crane.is_physics_processing(), "Crane should disable _physics_process.")

	var base_col: CollisionShape3D = crane.get_node_or_null("BaseCollision") as CollisionShape3D
	assert_not_null(base_col, "BaseCollision should exist.")
	var base_cyl: CylinderShape3D = base_col.shape as CylinderShape3D
	assert_not_null(base_cyl, "BaseCollision shape should be CylinderShape3D.")
	assert_almost_eq(
		base_cyl.radius, 3.20, 0.05, "Single-circle base radius should be 3.20m (6.40m diameter)."
	)
	assert_lte(
		base_cyl.height,
		StairController.MAX_STEP_HEIGHT,
		"Base height (0.20m) must be <= MAX_STEP_HEIGHT (0.55m) for zero-jump walk-up."
	)

	var boom_col: CollisionShape3D = (
		crane.get_node_or_null("PivotBody/BoomCollision") as CollisionShape3D
	)
	assert_not_null(boom_col, "BoomCollision should exist.")
	var boom_box: BoxShape3D = boom_col.shape as BoxShape3D
	assert_not_null(boom_box, "BoomCollision shape should be BoxShape3D.")
	assert_almost_eq(
		boom_box.size.x, 1.60, 0.05, "Top timber boom collider width should be 2.5x wider (1.60m)."
	)

	assert_false(
		crane.wheel.is_in_group(&"not_climbable"),
		"PivotBody should allow VaultController mantling onto the 2.5x wide top boom."
	)
	assert_false(
		crane.is_in_group(&"interactable"),
		"Root crane must not be in interactable group so looking at mast/boom does not grab wheel."
	)
	assert_true(
		crane._capstan_body.is_in_group(&"interactable"),
		"CapstanGrabBody should be in interactable group."
	)
	assert_true(
		crane._capstan_body.is_in_group(&"not_climbable"),
		"CapstanGrabBody should stay in not_climbable group."
	)
	assert_true(
		crane._jib_grab_body.is_in_group(&"interactable"),
		"JibGrabBody should be in interactable group."
	)
	assert_true(
		crane._jib_grab_body.is_in_group(&"not_climbable"),
		"JibGrabBody should stay in not_climbable group."
	)

	assert_eq(
		crane._base_highlight._cached_meshes.size(),
		1,
		"Base HighlightComponent should only target CapstanVisual."
	)
	assert_eq(
		crane._base_highlight._cached_meshes[0],
		crane._capstan_visual,
		"Base HighlightComponent target must be CapstanVisual."
	)
	assert_eq(
		crane._jib_highlight._cached_meshes.size(),
		1,
		"Jib HighlightComponent should only target JibRailVisual."
	)
	assert_eq(
		crane._jib_highlight._cached_meshes[0],
		crane._jib_rail_visual,
		"Jib HighlightComponent target must be JibRailVisual."
	)


## Verifies base pushwheel proximity gate and PushWheelState mount/dismount contract.
func test_base_capstan_mount_and_push_wheel_state_contract() -> void:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(p, "Player scene should instantiate.")
	add_child_autofree(p)
	await get_tree().process_frame

	p.global_position = crane.global_position + Vector3(2.2, 0.20, 0.0)
	assert_true(
		crane.is_player_near_capstan(p),
		"Player standing on the 3.2m base circle (2.2m from center) should be able to attach."
	)

	crane._on_base_interacted(p)
	assert_true(
		p.state_machine.is_in_state(&"PushWheel"),
		"Interacting with base capstan should transition Player into PushWheel state without error."
	)
	assert_true(crane._is_base_pushed, "on_push_started(player) should set _is_base_pushed = true.")
	assert_not_null(
		crane.current_active_anchor,
		"current_active_anchor must be a valid Marker3D for PushWheelState."
	)
	assert_almost_eq(
		crane.current_active_anchor.position.y,
		TimberJibCrane.BASE_SURFACE_Y,
		0.01,
		"Player stand anchor should rest flush on top of the 0.20m base circle."
	)

	p.state_machine.transition_to(&"Ground")
	assert_false(
		crane._is_base_pushed,
		"Exiting PushWheelState should call on_push_ended(player) and clear _is_base_pushed."
	)


## Verifies clamped base rotation, progress calculation, and angle_changed signal emission.
func test_clamped_base_push_and_progress() -> void:
	crane.limit_rotation = true
	crane.min_angle_deg = -90.0
	crane.max_angle_deg = 90.0
	crane.initial_angle_deg = 0.0
	crane.current_angle_deg = 0.0
	crane.turn_clockwise = true
	crane.seconds_for_full_rotation = 4.0

	watch_signals(crane)

	crane.push(1.0)
	assert_almost_eq(
		crane.current_angle_deg, 90.0, 0.01, "Pushing 1s at 90 deg/s should reach +90 deg."
	)
	assert_almost_eq(crane.progress, 1.0, 0.01, "Progress at max_angle_deg should be 1.0.")
	assert_signal_emitted(crane, "angle_changed")


## Verifies overhead jib mounting, below-bar height lock, pendulum swing, and jump launch.
func test_state_jib_crane_swing_and_below_bar_lock() -> void:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	assert_not_null(p, "Player scene should instantiate.")
	add_child_autofree(p)
	await get_tree().process_frame

	p.global_position = crane.get_rail_world_position(8.0) + Vector3(0.0, -1.95, 0.0)
	crane._on_jib_interacted(p)

	assert_true(
		p.state_machine.is_in_state(&"JibCrane"),
		"Interacting with JibGrabBody should transition Player into JibCrane state."
	)

	var jib_state: StateJibCrane = p.state_machine.current_state as StateJibCrane
	assert_not_null(jib_state, "Current state should be StateJibCrane.")

	var rail_y: float = crane.get_rail_world_position(8.0).y
	assert_lt(
		p.global_position.y,
		rail_y - 1.4,
		"Player origin must stay strictly below the jib bar (no climbing on top of boom)."
	)

	# Pump perpendicular pendulum swing
	for i: int in range(25):
		jib_state._update_pendulum_swing(1.0, 0.016)
	assert_gt(
		absf(jib_state._swing_angle_rad),
		0.15,
		"Pumping perpendicular input should build Mirror's Edge pendulum swing angle."
	)

	# Jump launch at swing arc
	jib_state._perform_dismount(p, true)
	assert_true(
		p.state_machine.is_in_state(&"Air"),
		"Jumping from JibCrane swing should transition Player to Air state."
	)
	assert_gt(
		p.velocity.y,
		StateJibCrane.JUMP_VERTICAL_SPEED,
		"Jumping during a swing should add upward swing launch bonus."
	)
