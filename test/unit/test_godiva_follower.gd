## GUT unit tests for [GodivaFollower] following, repath timer, link traversal, and headroom checks.
extends GutTest

## Preloaded Godiva scene using [GodivaFollower] and [NavigationAgent3D].
const GODIVA_SCENE: PackedScene = preload("res://npcs/godiva/godiva.tscn")
## Preloaded [EventSequenceTrigger] script for NPC_FOLLOW integration testing.
const EVENT_TRIGGER_SCRIPT: GDScript = preload(
	"res://addons/detour_event_sequencer/event_sequence_trigger.gd"
)
## Preloaded [EventStep] resource script for sequence step construction.
const EVENT_STEP_SCRIPT: GDScript = preload("res://addons/detour_event_sequencer/event_step.gd")

## Active follower instance under test.
var _godiva: GodivaFollower = null


## Instantiates a fresh [GodivaFollower] inside the scene tree before each test.
func before_each() -> void:
	var inst: Node = GODIVA_SCENE.instantiate()
	assert_true(inst is GodivaFollower, "godiva.tscn root must be GodivaFollower.")
	_godiva = inst as GodivaFollower
	add_child_autofree(_godiva)


## Verifies [NavigationAgent3D] setup, capsule defaults, and idle physics sleep on _ready.
func test_follower_navigation_and_idle_sleep() -> void:
	assert_not_null(_godiva.nav_agent, "GodivaFollower must expose NavigationAgent3D.")
	assert_almost_eq(_godiva.nav_agent.radius, 0.24, 0.005, "Agent radius must be 0.24m.")
	assert_almost_eq(_godiva.nav_agent.height, 1.64, 0.005, "Agent height must be 1.64m.")
	assert_false(_godiva.is_following(), "Follower must start idle unless auto_start is set.")
	assert_false(_godiva.is_physics_processing(), "Physics process must sleep while not following.")

	var repath_timer: Timer = _godiva.get_node_or_null(^"FollowRepathTimer") as Timer
	assert_not_null(repath_timer, "FollowRepathTimer must exist.")
	assert_almost_eq(repath_timer.wait_time, 0.25, 0.005, "Repath timer must use 0.25s interval.")
	assert_true(repath_timer.is_stopped(), "Repath timer must stay stopped until following.")


## Verifies start_following / stop_following API and EventSequenceTrigger NPC_FOLLOW dispatch.
func test_start_stop_following_and_sequencer_hook() -> void:
	watch_signals(_godiva)
	_godiva.start_following("")
	assert_true(_godiva.is_following(), "start_following must enable following.")
	assert_true(_godiva.is_physics_processing(), "Physics process must run while following.")
	assert_signal_emitted_with_parameters(_godiva, "follow_state_changed", [true])

	var repath_timer: Timer = _godiva.get_node_or_null(^"FollowRepathTimer") as Timer
	assert_false(repath_timer.is_stopped(), "Repath timer must run while following.")

	_godiva.stop_following("")
	assert_false(_godiva.is_following(), "stop_following must disable following.")
	assert_signal_emitted_with_parameters(_godiva, "follow_state_changed", [false])
	assert_true(repath_timer.is_stopped(), "Repath timer must stop when following stops.")

	var container: Node3D = Node3D.new()
	add_child_autofree(container)
	var follower: GodivaFollower = GODIVA_SCENE.instantiate() as GodivaFollower
	follower.name = "Godiva"
	container.add_child(follower)

	var trigger: Area3D = EVENT_TRIGGER_SCRIPT.new() as Area3D
	trigger.name = "FollowTrigger"
	container.add_child(trigger)

	var start_step: EventStep = EVENT_STEP_SCRIPT.new() as EventStep
	start_step.step_type = EventStep.StepType.NPC_FOLLOW
	start_step.exec_mode = EventStep.ExecMode.SEQUENTIAL
	start_step.target_path = trigger.get_path_to(follower)
	start_step.parameter = "true"

	var steps_start: Array[EventStep] = [start_step]
	trigger.set(&"steps", steps_start)
	trigger.call(&"trigger_sequence", null)
	await get_tree().process_frame
	assert_true(follower.is_following(), "NPC_FOLLOW true must start following.")

	var stop_step: EventStep = EVENT_STEP_SCRIPT.new() as EventStep
	stop_step.step_type = EventStep.StepType.NPC_FOLLOW
	stop_step.exec_mode = EventStep.ExecMode.SEQUENTIAL
	stop_step.target_path = trigger.get_path_to(follower)
	stop_step.parameter = "false"

	var steps_stop: Array[EventStep] = [stop_step]
	trigger.set(&"steps", steps_stop)
	trigger.call(&"trigger_sequence", null)
	await get_tree().process_frame
	assert_false(follower.is_following(), "NPC_FOLLOW false must stop following.")


## Verifies walk (< 6.0m), run (>= 6.0m), and stop (<= 2.0m) behavior plus off-screen follow.
func test_walk_run_stop_distances_and_offscreen_follow() -> void:
	var player_stub: Node3D = Node3D.new()
	player_stub.add_to_group(&"player")
	add_child_autofree(player_stub)

	player_stub.global_position = Vector3(0.0, 0.0, -8.0)
	_godiva.start_following()
	_godiva._on_screen_exited()
	assert_true(
		_godiva.is_physics_processing(), "Follower must keep physics active when off-screen."
	)
	assert_eq(_godiva._select_move_clip(), &"run", "Distance >= 6.0m must select run clip.")
	assert_almost_eq(
		_godiva._select_move_speed(),
		_godiva.run_speed,
		0.01,
		"Distance >= 6.0m must select run_speed."
	)

	player_stub.global_position = Vector3(0.0, 0.0, -4.0)
	_godiva._update_follow_target()
	assert_eq(_godiva._select_move_clip(), &"walk", "Distance < 6.0m must select walk clip.")
	assert_almost_eq(
		_godiva._select_move_speed(),
		_godiva.walk_speed,
		0.01,
		"Distance < 6.0m must select walk_speed."
	)

	player_stub.global_position = Vector3(0.0, 0.0, -1.5)
	_godiva._update_follow_target()
	assert_true(
		_godiva._should_stop_following(), "Follower must stop within ~2.0m of reachable player."
	)


## Verifies elevated player within 2.0m 3D distance does not stop follower below the ledge.
func test_elevated_player_within_stop_distance_does_not_stop_below_ledge() -> void:
	var arena: Node3D = Node3D.new()
	add_child_autofree(arena)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.agent_radius = 0.24
	nav_mesh.agent_height = 1.64
	nav_mesh.vertices = PackedVector3Array(
		[
			Vector3(-4.0, 0.0, -2.0),
			Vector3(-4.0, 0.0, 2.0),
			Vector3(4.0, 0.0, 2.0),
			Vector3(4.0, 0.0, -2.0),
			Vector3(-4.0, 1.2, -4.0),
			Vector3(-4.0, 1.2, -1.0),
			Vector3(4.0, 1.2, -1.0),
			Vector3(4.0, 1.2, -4.0),
		]
	)
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	nav_mesh.add_polygon(PackedInt32Array([0, 2, 3]))
	nav_mesh.add_polygon(PackedInt32Array([4, 5, 6]))
	nav_mesh.add_polygon(PackedInt32Array([4, 6, 7]))
	nav_region.navigation_mesh = nav_mesh
	arena.add_child(nav_region)

	var climb_link: NavigationLink3D = NavigationLink3D.new()
	climb_link.start_position = Vector3(0.0, 0.0, -0.5)
	climb_link.end_position = Vector3(0.0, 1.2, -1.5)
	climb_link.set_meta(&"traversal_type", "climb_mid")
	nav_region.add_child(climb_link)

	var player_stub: Node3D = Node3D.new()
	player_stub.add_to_group(&"player")
	arena.add_child(player_stub)
	player_stub.global_position = Vector3(0.0, 1.2, -1.5)

	var nav_map: RID = nav_region.get_navigation_map()
	var start_iter: int = NavigationServer3D.map_get_iteration_id(nav_map)
	var region_rid: RID = nav_region.get_rid()
	for sync_idx: int in range(15):
		await get_tree().physics_frame
		if (
			NavigationServer3D.map_get_iteration_id(nav_map) > start_iter
			and (
				NavigationServer3D.map_get_closest_point_owner(nav_map, player_stub.global_position)
				== region_rid
			)
		):
			break
		assert_gte(sync_idx, 0)

	_godiva.global_position = Vector3(0.0, 0.0, -0.3)
	_godiva.start_following()
	_godiva.nav_agent.get_next_path_position()
	assert_false(
		_godiva._should_stop_following(),
		"Follower below elevated player (< 2.0m 3D dist) must keep pathing to climb link."
	)

	_godiva.global_position = Vector3(0.0, 1.2, -2.5)
	_godiva._update_follow_target()
	_godiva.nav_agent.get_next_path_position()
	assert_true(
		_godiva._should_stop_following(),
		"Follower on same elevation within stop_distance must stop."
	)


## Verifies unreachable flying player walks to closest navmesh point, idles, and keeps look-at.
func test_unreachable_flying_player_projects_and_tracks_gaze() -> void:
	var arena: Node3D = Node3D.new()
	add_child_autofree(arena)

	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(20.0, 0.5, 20.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(floor_col)
	arena.add_child(floor_body)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.agent_radius = 0.24
	nav_mesh.agent_height = 1.64
	nav_mesh.vertices = PackedVector3Array(
		[
			Vector3(-8.0, 0.0, -8.0),
			Vector3(-8.0, 0.0, 8.0),
			Vector3(8.0, 0.0, 8.0),
			Vector3(8.0, 0.0, -8.0),
		]
	)
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	nav_mesh.add_polygon(PackedInt32Array([0, 2, 3]))
	nav_region.navigation_mesh = nav_mesh
	arena.add_child(nav_region)

	var player_stub: Node3D = Node3D.new()
	player_stub.add_to_group(&"player")
	arena.add_child(player_stub)
	player_stub.global_position = Vector3(0.0, 6.0, -4.0)

	var nav_map: RID = nav_region.get_navigation_map()
	var start_iter: int = NavigationServer3D.map_get_iteration_id(nav_map)
	var region_rid: RID = nav_region.get_rid()
	for sync_idx: int in range(15):
		await get_tree().physics_frame
		if (
			NavigationServer3D.map_get_iteration_id(nav_map) > start_iter
			and (
				NavigationServer3D.map_get_closest_point_owner(nav_map, player_stub.global_position)
				== region_rid
			)
		):
			break
		assert_gte(sync_idx, 0)

	_godiva.global_position = Vector3(0.0, 0.0, 0.0)
	_godiva.set_look_target(player_stub)
	_godiva._on_screen_entered()
	_godiva.start_following()

	assert_almost_eq(
		_godiva.nav_agent.target_position.y,
		0.0,
		0.25,
		"Flying player target must project down onto closest navmesh point."
	)
	assert_lt(
		_godiva.nav_agent.target_position.z,
		-3.0,
		"Projected navmesh point must lie beneath flying player XZ."
	)

	for step_idx: int in range(200):
		_godiva._physics_process(1.0 / 60.0)
		_godiva._process(1.0 / 60.0)
		assert_gte(step_idx, 0)

	assert_true(
		_godiva.global_position.distance_to(Vector3(0.0, 0.0, -4.0)) < 1.0,
		"Godiva must reach closest reachable navmesh point below flying player."
	)
	assert_eq(
		_godiva.get_current_animation(),
		&"idle",
		"Godiva must stop in idle at closest reachable point."
	)
	var look_target: Marker3D = _godiva.get_node_or_null(^"LookTarget") as Marker3D
	assert_gt(
		look_target.global_position.y,
		3.0,
		"LookAtModifier3D target must keep tracking high flying player."
	)


## Verifies NavigationLink3D metadata contract and bidirectional vertical delta fallback.
func test_link_traversal_metadata_contract_and_fallback() -> void:
	var link: NavigationLink3D = NavigationLink3D.new()
	add_child_autofree(link)

	for tag: String in [
		"step_up",
		"climb_mid",
		"pull_up_high",
		"crouch_walk",
		"prone_crawl",
		"drop_down",
	]:
		link.set_meta(&"traversal_type", tag)
		var entry: Vector3 = Vector3.ZERO
		var exit_pt: Vector3 = Vector3(0.0, -1.2 if tag == "drop_down" else 1.0, -1.0)
		assert_eq(
			_godiva.resolve_traversal_type(link, entry, exit_pt),
			StringName(tag),
			"Metadata tag '" + tag + "' must resolve verbatim in primary direction."
		)

	link.set_meta(&"traversal_type", "climb_mid")
	assert_eq(
		_godiva.resolve_traversal_type(link, Vector3(0.0, 2.0, 0.0), Vector3(0.0, 0.4, -1.0)),
		&"drop_down",
		"Bidirectional climb link traversed downward must resolve to drop_down."
	)

	link.set_meta(&"traversal_type", "prone_crawl")
	assert_eq(
		_godiva.resolve_traversal_type(link, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.2, -1.0)),
		&"prone_crawl",
		"Prone crawl link must stay prone_crawl in either direction."
	)

	var bare_link: NavigationLink3D = NavigationLink3D.new()
	add_child_autofree(bare_link)
	assert_eq(
		_godiva.resolve_traversal_type(bare_link, Vector3.ZERO, Vector3(0.0, 0.8, -1.0)),
		&"step_up",
		"Fallback dy=0.8m must resolve to step_up."
	)
	assert_eq(
		_godiva.resolve_traversal_type(bare_link, Vector3.ZERO, Vector3(0.0, 1.5, -1.0)),
		&"climb_mid",
		"Fallback dy=1.5m must resolve to climb_mid."
	)
	assert_eq(
		_godiva.resolve_traversal_type(bare_link, Vector3.ZERO, Vector3(0.0, 2.6, -1.0)),
		&"pull_up_high",
		"Fallback dy=2.6m must resolve to pull_up_high."
	)
	assert_eq(
		_godiva.resolve_traversal_type(bare_link, Vector3(0.0, 2.0, 0.0), Vector3.ZERO),
		&"drop_down",
		"Fallback dy=-2.0m must resolve to drop_down."
	)


## Verifies crouch/prone capsule shrinking and overhead clearance checks before standing up.
func test_crouch_prone_capsule_and_headroom_check() -> void:
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(6.0, 0.5, 6.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(floor_col)
	add_child_autofree(floor_body)

	var ceiling_body: StaticBody3D = StaticBody3D.new()
	ceiling_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var ceiling_col: CollisionShape3D = CollisionShape3D.new()
	var ceiling_box: BoxShape3D = BoxShape3D.new()
	ceiling_box.size = Vector3(4.0, 0.2, 4.0)
	ceiling_col.shape = ceiling_box
	ceiling_body.add_child(ceiling_col)
	add_child_autofree(ceiling_body)
	ceiling_body.global_position = Vector3(0.0, 3.50, 0.0)

	await get_tree().physics_frame

	var prone_link: NavigationLink3D = NavigationLink3D.new()
	prone_link.set_meta(&"traversal_type", "prone_crawl")
	add_child_autofree(prone_link)

	_godiva.start_following()
	(
		_godiva
		. nav_agent
		. link_reached
		. emit(
			{
				"link_entry_position": Vector3(0.0, 0.0, 0.0),
				"link_exit_position": Vector3(0.0, 0.0, -1.2),
				"owner": prone_link,
			}
		)
	)
	await get_tree().create_timer(0.25).timeout

	ceiling_body.global_position = Vector3(0.0, 0.70, 0.0)
	await get_tree().physics_frame

	var col_shape: CollisionShape3D = (
		_godiva.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	)
	var cap: CapsuleShape3D = col_shape.shape as CapsuleShape3D
	assert_almost_eq(cap.height, 0.42, 0.02, "Prone capsule height must shrink to ~0.42m.")
	assert_eq(
		_godiva.get_current_stance(),
		GodivaFollower.Stance.PRONE,
		"Stance must become PRONE on prone_crawl link."
	)
	assert_false(_godiva.has_stand_headroom(), "Low ceiling at 0.70m must block standing up.")
	assert_false(_godiva.has_crouch_headroom(), "Low ceiling at 0.70m must block crouching.")

	ceiling_body.global_position = Vector3(0.0, 1.30, 0.0)
	await get_tree().physics_frame
	assert_true(_godiva.has_crouch_headroom(), "1.30m ceiling must allow crouching (1.05m).")
	assert_false(_godiva.has_stand_headroom(), "1.30m ceiling must still block standing (1.64m).")

	ceiling_body.global_position = Vector3(0.0, 3.50, 0.0)
	await get_tree().physics_frame
	assert_true(_godiva.has_stand_headroom(), "Clear overhead space must allow standing up.")


## Verifies climb/drop link triggers multi-phase Tween to exit position while pausing gravity.
func test_climb_link_tween_pauses_gravity_and_reaches_exit() -> void:
	var ledge_body: StaticBody3D = StaticBody3D.new()
	ledge_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var ledge_col: CollisionShape3D = CollisionShape3D.new()
	var ledge_box: BoxShape3D = BoxShape3D.new()
	ledge_box.size = Vector3(2.0, 0.2, 2.0)
	ledge_col.shape = ledge_box
	ledge_body.add_child(ledge_col)
	add_child_autofree(ledge_body)
	ledge_body.global_position = Vector3(0.0, 1.4, -1.2)

	var climb_link: NavigationLink3D = NavigationLink3D.new()
	climb_link.set_meta(&"traversal_type", "climb_mid")
	add_child_autofree(climb_link)

	_godiva.start_following()
	watch_signals(_godiva)
	var exit_pos: Vector3 = Vector3(0.0, 1.5, -1.2)
	(
		_godiva
		. nav_agent
		. link_reached
		. emit(
			{
				"link_entry_position": Vector3.ZERO,
				"link_exit_position": exit_pos,
				"owner": climb_link,
			}
		)
	)

	assert_signal_emitted_with_parameters(_godiva, "traversal_started", [&"climb_mid"])
	_godiva._physics_process(0.1)
	assert_almost_eq(_godiva.velocity.y, 0.0, 0.001, "Gravity must pause during climb tween.")

	var clip_len: float = _godiva._get_clip_duration(&"climb_mid", 1.17)
	await wait_for_signal(_godiva.traversal_finished, clip_len + 0.5)
	assert_signal_emitted_with_parameters(_godiva, "traversal_finished", [&"climb_mid"])
	assert_lt(
		_godiva.global_position.distance_to(exit_pos),
		0.05,
		"Climb tween must land Godiva at link_exit_position."
	)


## Verifies all locomotion, crouch, prone, and obstacle traversal clips exist in AnimationPlayer.
func test_godiva_traversal_animation_clips_registered() -> void:
	var anim_player: AnimationPlayer = (
		_godiva.model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	)
	assert_not_null(anim_player, "AnimationPlayer must exist.")
	for clip_name: StringName in [
		&"idle",
		&"walk",
		&"run",
		&"crouch_idle",
		&"crouch_walk",
		&"prone_idle",
		&"prone_crawl",
		&"crouch_to_prone",
		&"prone_to_crouch",
		&"step_up",
		&"climb_mid",
		&"pull_up_high",
		&"drop_down",
	]:
		assert_true(
			anim_player.has_animation(clip_name),
			"godiva_rigged.glb must contain clip: " + String(clip_name)
		)
