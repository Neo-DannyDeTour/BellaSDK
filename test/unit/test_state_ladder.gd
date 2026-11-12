## Unit test suite validating [StateLadder] velocity projection, dismounts, and attach rules.
class_name TestStateLadder
extends GutTest


## Mock player class skipping full scene node assertions in unit tests.
class MockLadderPlayer:
	extends Player

	## Stubs ready hook to avoid full scene node assertions in unit tests.
	func _ready() -> void:
		return


## Mock state machine recording transitions and active state name.
class MockLadderStateMachine:
	extends StateMachine

	## Last requested state transition target.
	var last_transition: StringName = &""

	## Last transition payload dictionary.
	var last_msg: Dictionary = {}

	## Mock current state name evaluated by [method is_in_state].
	var mock_state_name: StringName = &"Ground"

	## Stubs ready hook so no child state discovery runs automatically.
	func _ready() -> void:
		return

	## Records requested transition and updates [member mock_state_name].
	func change_state(target_state_name: StringName, message: Dictionary = {}) -> bool:
		last_transition = target_state_name
		last_msg = message
		mock_state_name = target_state_name
		return true

	## Checks [member mock_state_name] against [param state_name].
	func is_in_state(state_name: StringName) -> bool:
		return mock_state_name == state_name


## Mock camera controller exposing a real [Camera3D] for look projections.
class MockLadderCameraController:
	extends CameraController

	## Stubs ready hook to avoid scene exports in unit tests.
	func _ready() -> void:
		return


## Ladder state instance under test.
var state_ladder: StateLadder = null

## Mock player instance wired into [member state_ladder].
var mock_player: MockLadderPlayer = null

## Mock state machine tracking transitions.
var mock_state_machine: MockLadderStateMachine = null

## Environment component under test.
var env_comp: PlayerEnvironmentComponent = null

## Camera3D node rotated to simulate player look pitch and yaw.
var cam_3d: Camera3D = null

## Head pivot node rotated to simulate ground look-up pitch.
var head_node: Node3D = null

## Ladder trigger node placed at world origin.
var ladder_node: Node3D = null

## Static floor collider used to establish real [method CharacterBody3D.is_on_floor] contact.
var floor_body: StaticBody3D = null


## Builds isolated player, floor, camera, environment, and ladder test fixtures.
func before_each() -> void:
	print("TestStateLadder: before_each() setup.")
	var vp: Viewport = get_viewport()
	if is_instance_valid(vp):
		var w3d: World3D = vp.find_world_3d()
		if not is_instance_valid(w3d) or not w3d.space.is_valid():
			vp.world_3d = World3D.new()

	floor_body = StaticBody3D.new()
	floor_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	floor_body.collision_mask = CollisionLayers.MASK_ALL
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(10.0, 1.0, 10.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child_autofree(floor_body)

	mock_player = MockLadderPlayer.new()
	mock_player.collision_layer = CollisionLayers.MASK_PLAYER
	mock_player.collision_mask = CollisionLayers.MASK_ENVIRONMENT
	var player_col: CollisionShape3D = CollisionShape3D.new()
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.64
	player_col.shape = capsule
	player_col.position = Vector3(0.0, 0.82, 0.0)
	mock_player.add_child(player_col)
	mock_player.position = Vector3(0.0, 2.0, 0.0)
	add_child_autofree(mock_player)

	head_node = Node3D.new()
	head_node.name = "Head"
	mock_player.add_child(head_node)

	var cam_ctrl: MockLadderCameraController = MockLadderCameraController.new()
	cam_3d = Camera3D.new()
	cam_ctrl.add_child(cam_3d)
	cam_ctrl.camera = cam_3d
	mock_player.camera_controller = cam_ctrl
	mock_player.add_child(cam_ctrl)

	var loco: PlayerLocomotionComponent = PlayerLocomotionComponent.new()
	loco.crouching = false
	mock_player.locomotion_component = loco
	mock_player.add_child(loco)

	mock_state_machine = MockLadderStateMachine.new()
	add_child_autofree(mock_state_machine)

	env_comp = PlayerEnvironmentComponent.new()
	env_comp.state_machine = mock_state_machine
	mock_player.environment_component = env_comp
	mock_player.add_child(env_comp)
	env_comp.initialize(mock_player)

	ladder_node = Node3D.new()
	add_child_autofree(ladder_node)

	state_ladder = StateLadder.new()
	state_ladder.player = mock_player
	state_ladder.state_machine = mock_state_machine
	add_child_autofree(state_ladder)


## Forces real [CharacterBody3D.is_on_floor] true by stepping down onto [member floor_body].
func _snap_mock_player_to_floor() -> void:
	mock_player.global_position = Vector3(0.0, 0.02, 0.1)
	mock_player.velocity = Vector3(0.0, -2.0, 0.0)
	mock_player.move_and_slide()


## Verifies depth pull moves monotonically toward 0.1m without pushing backwards first.
func test_depth_pull_targets_point_one_monotonically() -> void:
	print("TestStateLadder: test_depth_pull_targets_point_one_monotonically().")
	mock_player.global_position = Vector3(0.0, 2.0, 0.4)
	state_ladder.enter({&"ladder_node": ladder_node})

	state_ladder._calculate_ladder_velocity(
		mock_player,
		mock_player.locomotion_component,
		mock_player.camera_controller as CameraController,
		Vector2.ZERO
	)
	assert_lt(
		mock_player.velocity.z,
		0.0,
		"Player at z=0.4m should pull forward toward 0.1m, never backwards."
	)

	mock_player.global_position = Vector3(0.0, 2.0, 0.1)
	state_ladder._calculate_ladder_velocity(
		mock_player,
		mock_player.locomotion_component,
		mock_player.camera_controller as CameraController,
		Vector2.ZERO
	)
	assert_almost_eq(
		mock_player.velocity.z, 0.0, 0.001, "Player at z=0.1m should have zero depth velocity."
	)


## Verifies small side-look angles stay strictly vertical on forward/back input.
func test_lateral_look_threshold_blocks_slight_side_look() -> void:
	print("TestStateLadder: test_lateral_look_threshold_blocks_slight_side_look().")
	mock_player.global_position = Vector3(0.0, 2.0, 0.1)
	state_ladder.enter({&"ladder_node": ladder_node})

	cam_3d.rotation = Vector3(0.0, deg_to_rad(-55.0), 0.0)
	state_ladder._calculate_ladder_velocity(
		mock_player,
		mock_player.locomotion_component,
		mock_player.camera_controller as CameraController,
		Vector2(0.0, -1.0)
	)
	assert_almost_eq(
		mock_player.velocity.x,
		0.0,
		0.001,
		"55 deg side look should produce zero lateral movement on forward input."
	)
	assert_almost_eq(
		mock_player.velocity.y,
		StateLadder.LADDER_SPEED,
		0.001,
		"55 deg side look should maintain full vertical climb speed."
	)

	cam_3d.rotation = Vector3(0.0, deg_to_rad(-80.0), 0.0)
	state_ladder._calculate_ladder_velocity(
		mock_player,
		mock_player.locomotion_component,
		mock_player.camera_controller as CameraController,
		Vector2(0.0, -1.0)
	)
	assert_gt(
		absf(mock_player.velocity.x),
		0.5,
		"80 deg side look should engage lateral movement on forward input."
	)


## Verifies slight downward pitch keeps forward climbing up until exceeding 30 deg down.
func test_climb_down_pitch_threshold_ignores_slight_down_look() -> void:
	print("TestStateLadder: test_climb_down_pitch_threshold_ignores_slight_down_look().")
	mock_player.global_position = Vector3(0.0, 2.0, 0.1)
	state_ladder.enter({&"ladder_node": ladder_node})

	cam_3d.rotation = Vector3(deg_to_rad(-20.0), 0.0, 0.0)
	state_ladder._calculate_ladder_velocity(
		mock_player,
		mock_player.locomotion_component,
		mock_player.camera_controller as CameraController,
		Vector2(0.0, -1.0)
	)
	assert_almost_eq(
		mock_player.velocity.y,
		StateLadder.LADDER_SPEED,
		0.001,
		"20 deg down look should still climb upward on forward input."
	)

	cam_3d.rotation = Vector3(deg_to_rad(-45.0), 0.0, 0.0)
	state_ladder._calculate_ladder_velocity(
		mock_player,
		mock_player.locomotion_component,
		mock_player.camera_controller as CameraController,
		Vector2(0.0, -1.0)
	)
	assert_almost_eq(
		mock_player.velocity.y,
		-StateLadder.LADDER_SPEED,
		0.001,
		"45 deg down look should descend on forward input."
	)


## Verifies touching ground unglues only when velocity.y <= 0.0.
func test_ground_touch_unglues_when_not_ascending() -> void:
	print("TestStateLadder: test_ground_touch_unglues_when_not_ascending().")
	await get_tree().physics_frame
	await get_tree().physics_frame
	state_ladder.enter({&"ladder_node": ladder_node})
	mock_state_machine.mock_state_name = &"Ladder"
	_snap_mock_player_to_floor()
	assert_true(mock_player.is_on_floor(), "Precondition: player should be on floor.")

	mock_player.velocity.y = 5.0
	state_ladder._check_transitions(mock_player, env_comp)
	assert_eq(
		mock_state_machine.last_transition,
		&"",
		"Climbing upward from floor should stay glued on frame 1."
	)

	mock_player.velocity.y = 0.0
	state_ladder._check_transitions(mock_player, env_comp)
	assert_eq(
		mock_state_machine.last_transition,
		&"Ground",
		"Touching floor while stationary or descending should unglue to Ground."
	)
	assert_gt(env_comp.ladder_cooldown, 0.0, "Ground dismount should arm brief cooldown.")


## Verifies grounded entry stays detached while airborne jump entry glues immediately.
func test_ground_vs_air_attach_rules() -> void:
	print("TestStateLadder: test_ground_vs_air_attach_rules().")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_snap_mock_player_to_floor()
	assert_true(mock_player.is_on_floor(), "Precondition: player should start on floor.")

	mock_state_machine.mock_state_name = &"Ground"
	head_node.rotation = Vector3.ZERO
	env_comp.enter_ladder(ladder_node)
	assert_eq(
		mock_state_machine.last_transition,
		&"",
		"Grounded player looking level should stay detached from ladder."
	)

	mock_player.global_position = Vector3(0.0, 2.0, 0.1)
	mock_player.velocity = Vector3(0.0, 4.5, 0.0)
	mock_player.move_and_slide()
	mock_state_machine.mock_state_name = &"Air"
	env_comp.process_environment_physics(0.016)
	assert_eq(
		mock_state_machine.last_transition,
		&"Ladder",
		"Jumping while overlapping ladder should glue into Ladder state."
	)

	mock_state_machine.mock_state_name = &"Ground"
	mock_state_machine.last_transition = &""
	env_comp.exit_ladder(ladder_node)
	assert_eq(
		mock_state_machine.last_transition,
		&"",
		"Exiting ladder trigger while already in Ground should not force Air."
	)
