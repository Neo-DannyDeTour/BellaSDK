## GUT unit tests for [GodivaFollower] following, repath timer, link traversal, and headroom checks.
extends GutTest

## Preloaded Godiva scene using [GodivaFollower] and [NavigationAgent3D].
const GODIVA_SCENE: PackedScene = preload("res://npcs/godiva/godiva.tscn")
## Preloaded interactive warehouse shelf scene.
const SHELF_SCENE: PackedScene = preload("res://props/factory_workshop/warehouse_shelf.tscn")
## Preloaded 4m factory doorway scene with chokepoint sensor.
const DOORWAY_SCENE: PackedScene = preload(
	"res://environment/factory_shells/factory_doorway_4m.tscn"
)
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
		&"shelf_crawl_through",
		&"shelf_climb_over",
		&"shelf_vault_through",
		&"shelf_push_aside",
		&"shelf_topple",
		&"wall_hug_idle",
		&"sidestep_left",
		&"sidestep_right",
	]:
		assert_true(
			anim_player.has_animation(clip_name),
			"godiva_rigged.glb must contain clip: " + String(clip_name)
		)


## Verifies InteractiveShelf push_aside, topple, cleared state, and linked_nav_link disable.
func test_interactive_shelf_push_and_topple_state() -> void:
	var static_shelf: InteractiveShelf = SHELF_SCENE.instantiate() as InteractiveShelf
	assert_not_null(static_shelf, "warehouse_shelf.tscn root must be InteractiveShelf.")
	add_child_autofree(static_shelf)
	assert_false(static_shelf.pushable, "WarehouseShelf must default to pushable = false.")
	assert_false(static_shelf.can_manipulate(), "Non-pushable shelf must report cannot manipulate.")

	var container: Node3D = Node3D.new()
	add_child_autofree(container)

	var push_link: NavigationLink3D = NavigationLink3D.new()
	push_link.name = "PushLink"
	container.add_child(push_link)

	var push_shelf: InteractiveShelf = SHELF_SCENE.instantiate() as InteractiveShelf
	push_shelf.name = "PushShelf"
	push_shelf.pushable = true
	push_shelf.linked_nav_link = NodePath("../PushLink")
	container.add_child(push_shelf)

	watch_signals(push_shelf)
	var start_pos: Vector3 = push_shelf.global_position
	push_shelf.push_aside(Vector3(0.0, 0.0, -1.0), 0.1)
	await wait_for_signal(push_shelf.shelf_manipulated, 0.5)
	assert_signal_emitted_with_parameters(
		push_shelf, "shelf_manipulated", [InteractiveShelf.ACTION_PUSH_ASIDE]
	)
	assert_true(push_shelf.is_cleared(), "Push-aside must mark shelf cleared.")
	assert_false(push_shelf.can_manipulate(), "Cleared shelf must not be manipulable again.")
	assert_false(push_link.enabled, "Push-aside must disable linked NavigationLink3D.")
	assert_gt(
		push_shelf.global_position.distance_to(start_pos),
		1.4,
		"Push-aside must slide shelf ~1.6m sideways."
	)

	var topple_link: NavigationLink3D = NavigationLink3D.new()
	topple_link.name = "ToppleLink"
	container.add_child(topple_link)

	var topple_shelf: InteractiveShelf = SHELF_SCENE.instantiate() as InteractiveShelf
	topple_shelf.name = "ToppleShelf"
	topple_shelf.pushable = true
	topple_shelf.linked_nav_link = NodePath("../ToppleLink")
	container.add_child(topple_shelf)

	watch_signals(topple_shelf)
	topple_shelf.topple(Vector3(0.0, 0.0, -1.0), 0.1)
	await wait_for_signal(topple_shelf.shelf_manipulated, 0.5)
	assert_signal_emitted_with_parameters(
		topple_shelf, "shelf_manipulated", [InteractiveShelf.ACTION_TOPPLE]
	)
	assert_true(topple_shelf.is_cleared(), "Topple must mark shelf cleared.")
	assert_false(topple_link.enabled, "Topple must disable linked NavigationLink3D.")
	assert_almost_eq(
		absf(topple_shelf.global_transform.basis.y.dot(Vector3.UP)),
		0.0,
		0.1,
		"Toppled shelf local +Y must tip ~90 deg onto floor."
	)


## Verifies contextual shelf mode selection across urgency, clearance, cramped, and cleared states.
func test_select_shelf_traversal_contextual_modes() -> void:
	var arena: Node3D = Node3D.new()
	add_child_autofree(arena)

	var player_stub: Node3D = Node3D.new()
	player_stub.add_to_group(&"player")
	arena.add_child(player_stub)

	var shelf: InteractiveShelf = SHELF_SCENE.instantiate() as InteractiveShelf
	shelf.pushable = true
	arena.add_child(shelf)
	shelf.global_position = Vector3(0.0, 0.0, -2.0)

	var entry_pos: Vector3 = Vector3(0.0, 0.0, -0.8)
	var exit_pos: Vector3 = Vector3(0.0, 0.0, -3.2)
	_godiva.global_position = entry_pos
	_godiva.start_following()

	# Normal urgency + open overhead -> climb over.
	player_stub.global_position = Vector3(0.0, 0.0, -4.0)
	_godiva._update_follow_target()
	assert_eq(
		_godiva.select_shelf_traversal(shelf, entry_pos, exit_pos),
		GodivaFollower.TRAVERSAL_SHELF_CLIMB,
		"Normal urgency with clear overhead must select shelf_climb_over."
	)

	# Normal urgency + low overhead ceiling -> crawl through.
	var low_ceil: StaticBody3D = StaticBody3D.new()
	low_ceil.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var ceil_col: CollisionShape3D = CollisionShape3D.new()
	var ceil_box: BoxShape3D = BoxShape3D.new()
	ceil_box.size = Vector3(4.0, 0.2, 4.0)
	ceil_col.shape = ceil_box
	low_ceil.add_child(ceil_col)
	arena.add_child(low_ceil)
	low_ceil.global_position = Vector3(0.0, 2.7, -2.0)
	await get_tree().physics_frame
	assert_eq(
		_godiva.select_shelf_traversal(shelf, entry_pos, exit_pos),
		GodivaFollower.TRAVERSAL_SHELF_CRAWL,
		"Low overhead clearance above shelf top must select shelf_crawl_through."
	)
	low_ceil.global_position = Vector3(0.0, 12.0, -2.0)
	await get_tree().physics_frame

	# High urgency (run_distance <= dist < run_distance * 1.5) -> vault through.
	player_stub.global_position = Vector3(0.0, 0.0, -7.5)
	_godiva._update_follow_target()
	assert_eq(
		_godiva.select_shelf_traversal(shelf, entry_pos, exit_pos),
		GodivaFollower.TRAVERSAL_SHELF_VAULT,
		"High urgency below 1.5x run_distance must select shelf_vault_through."
	)

	# Very high urgency (>= 1.5x run_distance) + pushable + open space -> topple.
	player_stub.global_position = Vector3(0.0, 0.0, -12.0)
	_godiva._update_follow_target()
	assert_eq(
		_godiva.select_shelf_traversal(shelf, entry_pos, exit_pos),
		GodivaFollower.TRAVERSAL_SHELF_TOPPLE,
		"Very high urgency on pushable shelf in open space must select shelf_topple."
	)

	# Very high urgency + cramped forward wall -> push aside.
	var back_wall: StaticBody3D = StaticBody3D.new()
	back_wall.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var wall_col: CollisionShape3D = CollisionShape3D.new()
	var wall_box: BoxShape3D = BoxShape3D.new()
	wall_box.size = Vector3(4.0, 3.0, 0.3)
	wall_col.shape = wall_box
	back_wall.add_child(wall_col)
	arena.add_child(back_wall)
	back_wall.global_position = Vector3(0.0, 1.5, -3.6)
	await get_tree().physics_frame
	assert_eq(
		_godiva.select_shelf_traversal(shelf, entry_pos, exit_pos),
		GodivaFollower.TRAVERSAL_SHELF_PUSH,
		"Cramped forward space behind pushable shelf must select shelf_push_aside."
	)

	# Deterministic override takes precedence when shelf is not cleared.
	_godiva.shelf_mode_override = GodivaFollower.TRAVERSAL_SHELF_CRAWL
	assert_eq(
		_godiva.select_shelf_traversal(shelf, entry_pos, exit_pos),
		GodivaFollower.TRAVERSAL_SHELF_CRAWL,
		"shelf_mode_override must force selected shelf traversal mode."
	)
	_godiva.shelf_mode_override = &""

	# Cleared shelf returns empty StringName so Godiva walks straight through.
	shelf.push_aside(Vector3(0.0, 0.0, -1.0), 0.0)
	assert_eq(
		_godiva.select_shelf_traversal(shelf, entry_pos, exit_pos),
		&"",
		"Cleared InteractiveShelf must return empty mode to walk straight through."
	)


## Verifies all 4 shelf traversal modes execute multi-phase tweens and manipulate shelf on push.
func test_all_four_shelf_traversal_modes_execute_and_finish() -> void:
	var arena: Node3D = Node3D.new()
	add_child_autofree(arena)

	var shelf: InteractiveShelf = SHELF_SCENE.instantiate() as InteractiveShelf
	shelf.name = "TestShelf"
	shelf.pushable = true
	arena.add_child(shelf)
	shelf.global_position = Vector3(0.0, 0.0, -2.0)

	var shelf_link: NavigationLink3D = NavigationLink3D.new()
	shelf_link.name = "ShelfLink"
	shelf_link.set_meta(&"traversal_type", "shelf_interact")
	shelf_link.set_meta(&"shelf_node_path", NodePath("../TestShelf"))
	arena.add_child(shelf_link)

	_godiva.start_following()
	watch_signals(_godiva)

	var entry_pos: Vector3 = Vector3(0.0, 0.0, -0.8)
	var exit_pos: Vector3 = Vector3(0.0, 0.0, -3.2)

	for mode: StringName in [
		GodivaFollower.TRAVERSAL_SHELF_CRAWL,
		GodivaFollower.TRAVERSAL_SHELF_CLIMB,
		GodivaFollower.TRAVERSAL_SHELF_VAULT,
		GodivaFollower.TRAVERSAL_SHELF_PUSH,
	]:
		_godiva.global_position = entry_pos
		_godiva.shelf_mode_override = mode
		(
			_godiva
			. nav_agent
			. link_reached
			. emit(
				{
					"link_entry_position": entry_pos,
					"link_exit_position": exit_pos,
					"owner": shelf_link,
				}
			)
		)
		assert_signal_emitted_with_parameters(_godiva, "traversal_started", [mode])
		var dur: float = _godiva._get_clip_duration(
			mode, _godiva._get_default_traversal_duration(mode)
		)
		await wait_for_signal(_godiva.traversal_finished, dur + 0.6)
		assert_signal_emitted_with_parameters(_godiva, "traversal_finished", [mode])
		assert_lt(
			_godiva.global_position.distance_to(exit_pos),
			0.1,
			"Shelf traversal '" + String(mode) + "' must land Godiva at exit_pos."
		)

	assert_true(
		shelf.is_cleared(),
		"TRAVERSAL_SHELF_PUSH must trigger InteractiveShelf.push_aside and clear the shelf."
	)


## Verifies FactoryDoorway4m chokepoint yield, wall-hug sidestep, and resume on clear or timeout.
func test_doorway_chokepoint_yield_and_resume() -> void:
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

	var doorway: StaticBody3D = DOORWAY_SCENE.instantiate() as StaticBody3D
	arena.add_child(doorway)
	doorway.global_position = Vector3(0.0, 0.0, 0.0)

	var sensor: Area3D = doorway.get_node_or_null(^"ChokepointSensor") as Area3D
	assert_not_null(sensor, "FactoryDoorway4m must contain ChokepointSensor Area3D.")
	assert_true(sensor.is_in_group(&"chokepoint"), "ChokepointSensor must be in group chokepoint.")

	var player_stub: Node3D = Node3D.new()
	player_stub.add_to_group(&"player")
	arena.add_child(player_stub)
	player_stub.global_position = Vector3(0.0, 0.0, 2.5)

	_godiva.global_position = Vector3(0.1, 0.0, 0.0)
	_godiva.start_following()
	watch_signals(_godiva)

	await get_tree().physics_frame

	# Player approaches Godiva inside doorway (< 3.5m).
	player_stub.global_position = Vector3(0.0, 0.0, 2.0)
	_godiva._physics_process(0.16)
	assert_true(
		_godiva.is_yielding_doorway(),
		"Godiva inside FactoryDoorway4m must yield when player approaches within 3.5m."
	)
	assert_signal_emitted_with_parameters(_godiva, "doorway_yield_changed", [true])

	var start_x: float = _godiva.global_position.x
	for step_idx: int in range(25):
		_godiva._physics_process(1.0 / 60.0)
		assert_gte(step_idx, 0)
	assert_gt(
		absf(_godiva.global_position.x - start_x),
		0.15,
		"Godiva must sidestep off-center toward nearest doorway wall while yielding."
	)

	# Player passes through and clears > 2.5m -> Godiva resumes following.
	player_stub.global_position = Vector3(0.0, 0.0, -2.0)
	_godiva._physics_process(1.0 / 60.0)
	player_stub.global_position = Vector3(0.0, 0.0, -3.2)
	_godiva._physics_process(1.0 / 60.0)
	assert_false(
		_godiva.is_yielding_doorway(), "Godiva must resume following once player clears > 2.5m."
	)
	assert_signal_emitted_with_parameters(_godiva, "doorway_yield_changed", [false])


## Verifies untagged narrow corridor (< 2.6m) triggers yield via throttled 2-ray check and timeout.
func test_untagged_narrow_corridor_yield_and_timeout() -> void:
	var arena: Node3D = Node3D.new()
	add_child_autofree(arena)

	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(12.0, 0.5, 12.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(floor_col)
	arena.add_child(floor_body)

	# Two untagged parallel walls 2.0m apart (< 2.6m threshold).
	for side_x: float in [-1.0, 1.0]:
		var wall: StaticBody3D = StaticBody3D.new()
		wall.collision_layer = CollisionLayers.MASK_ENVIRONMENT
		var w_col: CollisionShape3D = CollisionShape3D.new()
		var w_box: BoxShape3D = BoxShape3D.new()
		w_box.size = Vector3(0.2, 3.0, 6.0)
		w_col.shape = w_box
		wall.add_child(w_col)
		arena.add_child(wall)
		wall.global_position = Vector3(side_x, 1.5, 0.0)

	var player_stub: Node3D = Node3D.new()
	player_stub.add_to_group(&"player")
	arena.add_child(player_stub)
	player_stub.global_position = Vector3(0.0, 0.0, 2.2)

	_godiva.global_position = Vector3(0.0, 0.0, 0.0)
	_godiva.start_following()
	await get_tree().physics_frame

	player_stub.global_position = Vector3(0.0, 0.0, 1.8)
	_godiva._physics_process(0.16)
	assert_true(
		_godiva.is_yielding_doorway(),
		"Untagged narrow corridor (< 2.6m) must trigger doorway yield via 2-ray check."
	)

	# Hold player in place past 4.0s timeout -> must auto-resume.
	for tick: int in range(42):
		_godiva._physics_process(0.1)
		assert_gte(tick, 0)
	assert_false(
		_godiva.is_yielding_doorway(), "Doorway yield must auto-resume after 4.0s timeout."
	)


## Verifies direct shelf collision trigger, cooldown guard, and cleared-shelf rejection.
func test_shelf_collision_trigger_cooldown_and_cleared_guard() -> void:
	var arena: Node3D = Node3D.new()
	add_child_autofree(arena)

	var shelf: InteractiveShelf = SHELF_SCENE.instantiate() as InteractiveShelf
	shelf.name = "CollisionShelf"
	shelf.pushable = true
	arena.add_child(shelf)
	shelf.global_position = Vector3(0.0, 0.0, -2.0)

	_godiva.global_position = Vector3(0.0, 0.0, -0.8)
	_godiva.shelf_mode_override = GodivaFollower.TRAVERSAL_SHELF_VAULT
	_godiva.start_following()
	watch_signals(_godiva)

	assert_true(
		_godiva._try_trigger_shelf_collision(shelf),
		"Direct collision with uncleared InteractiveShelf must trigger traversal."
	)
	assert_signal_emitted_with_parameters(
		_godiva, "traversal_started", [GodivaFollower.TRAVERSAL_SHELF_VAULT]
	)

	var dur: float = (
		_godiva
		. _get_clip_duration(
			GodivaFollower.TRAVERSAL_SHELF_VAULT,
			_godiva._get_default_traversal_duration(GodivaFollower.TRAVERSAL_SHELF_VAULT),
		)
	)
	await wait_for_signal(_godiva.traversal_finished, dur + 0.6)
	assert_signal_emitted_with_parameters(
		_godiva, "traversal_finished", [GodivaFollower.TRAVERSAL_SHELF_VAULT]
	)
	assert_gt(
		_godiva._shelf_collision_cooldown_sec,
		0.0,
		"Completing a shelf traversal must arm _shelf_collision_cooldown_sec."
	)
	assert_false(
		_godiva._try_trigger_shelf_collision(shelf),
		"Active shelf collision cooldown must block immediate re-trigger."
	)

	_godiva._shelf_collision_cooldown_sec = 0.0
	shelf.push_aside(Vector3(0.0, 0.0, -1.0), 0.0)
	assert_true(shelf.is_cleared(), "Shelf must report cleared after push_aside.")
	assert_false(
		_godiva._try_trigger_shelf_collision(shelf),
		"Cleared shelf must not trigger collision traversal."
	)


## Verifies GodivaIKController TwoBoneIK3D setup, hand targets, and prone foot-IK suppression.
func test_ik_controller_setup_hand_targets_and_prone_suppression() -> void:
	var ik: GodivaIKController = _godiva.ik_controller
	assert_not_null(ik, "GodivaFollower must wire GodivaIKController.")

	var foot_ik: TwoBoneIK3D = ik.get_foot_ik()
	var hand_ik: TwoBoneIK3D = ik.get_hand_ik()
	assert_not_null(foot_ik, "GodivaIKController must attach FootIK TwoBoneIK3D.")
	assert_not_null(hand_ik, "GodivaIKController must attach HandIK TwoBoneIK3D.")
	assert_eq(foot_ik.get_setting_count(), 2, "FootIK must configure both left and right legs.")
	assert_eq(hand_ik.get_setting_count(), 2, "HandIK must configure both left and right arms.")
	assert_eq(
		foot_ik.get_parent(), _godiva.get_skeleton(), "FootIK must be a direct child of Skeleton3D."
	)
	assert_eq(
		hand_ik.get_parent(), _godiva.get_skeleton(), "HandIK must be a direct child of Skeleton3D."
	)

	ik.set_hand_targets(Vector3(-0.24, 1.2, -0.5), Vector3(0.24, 1.2, -0.5), 0.85)
	assert_true(ik.is_hand_ik_active(), "set_hand_targets must activate hand IK.")
	for step: int in range(20):
		ik._physics_process(1.0 / 60.0)
		assert_gte(step, 0)
	assert_gt(hand_ik.influence, 0.6, "HandIK influence must blend up toward target weight.")

	ik.clear_hand_targets()
	assert_false(ik.is_hand_ik_active(), "clear_hand_targets must deactivate hand IK.")
	for step_out: int in range(30):
		ik._physics_process(1.0 / 60.0)
		assert_gte(step_out, 0)
	assert_lt(hand_ik.influence, 0.05, "HandIK influence must damp back toward 0.0 after clear.")

	_godiva._apply_stance(GodivaFollower.Stance.PRONE, true)
	assert_true(ik.is_foot_ik_suppressed(), "Prone stance must suppress foot grounding IK.")
	foot_ik.influence = 0.8
	for step_prone: int in range(25):
		ik._physics_process(1.0 / 60.0)
		assert_gte(step_prone, 0)
	assert_lt(foot_ik.influence, 0.05, "Suppressed FootIK influence must damp toward 0.0.")

	_godiva._apply_stance(GodivaFollower.Stance.STAND, true)
	assert_false(ik.is_foot_ik_suppressed(), "Standing stance must re-enable foot grounding IK.")


## Verifies NpcActor parametric locomotion BlendSpace1D blending and scripted clip override.
func test_npc_actor_parametric_locomotion_blend_space() -> void:
	assert_true(
		_godiva.has_locomotion_blend_space(),
		"NpcActor must build locomotion BlendSpace1D when idle, walk, and run exist."
	)
	var tree: AnimationTree = _godiva.get_animation_tree()
	assert_not_null(tree, "AnimationTree must exist.")

	_godiva.set_locomotion_blend(0.38)
	var raw_walk_blend: Variant = tree.get(NpcActor.PARAM_LOCOMOTION_BLEND)
	var walk_blend: float = raw_walk_blend if raw_walk_blend is float else -1.0
	assert_almost_eq(walk_blend, 0.38, 0.005, "Walk speed ratio must drive blend_position=0.38.")
	assert_eq(
		_godiva.get_current_animation(),
		NpcActor.STATE_LOCOMOTION,
		"set_locomotion_blend must switch state machine to locomotion."
	)

	_godiva.set_locomotion_blend(1.0)
	var raw_run_blend: Variant = tree.get(NpcActor.PARAM_LOCOMOTION_BLEND)
	var run_blend: float = raw_run_blend if raw_run_blend is float else -1.0
	assert_almost_eq(run_blend, 1.0, 0.005, "Run speed ratio must drive blend_position=1.0.")

	_godiva.play_animation("a_pose")
	_godiva.set_locomotion_blend(0.5)
	assert_eq(
		_godiva.get_current_animation(),
		&"a_pose",
		"Scripted clip must prevent set_locomotion_blend from overriding playback."
	)
	_godiva.stop_animation()
	assert_eq(_godiva.get_current_animation(), &"idle", "stop_animation must return to idle.")


## Verifies motion warping anchor probing snaps wall face, ledge top, and landing floor.
func test_motion_warping_anchor_probing_snaps_wall_ledge_and_floor() -> void:
	var arena: Node3D = Node3D.new()
	add_child_autofree(arena)

	var ledge_block: StaticBody3D = StaticBody3D.new()
	ledge_block.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	var ledge_col: CollisionShape3D = CollisionShape3D.new()
	var ledge_box: BoxShape3D = BoxShape3D.new()
	ledge_box.size = Vector3(4.0, 1.4, 2.0)
	ledge_col.shape = ledge_box
	ledge_block.add_child(ledge_col)
	arena.add_child(ledge_block)
	# Front face at Z=-1.0, top surface at Y=1.4.
	ledge_block.global_position = Vector3(0.0, 0.7, -2.0)

	await get_tree().physics_frame

	var anchors: Dictionary[StringName, Variant] = (
		_godiva
		. _probe_traversal_anchors(
			GodivaFollower.TRAVERSAL_CLIMB_MID,
			Vector3(0.0, 0.0, 0.0),
			Vector3(0.0, 1.55, -1.5),
			null,
		)
	)
	var raw_has_wall: Variant = anchors.get(GodivaFollower.ANCHOR_HAS_WALL, false)
	var has_wall: bool = raw_has_wall if raw_has_wall is bool else false
	assert_true(has_wall, "Wall face ray must hit front face of climbable block.")

	var raw_wall_pos: Variant = anchors.get(GodivaFollower.ANCHOR_WALL_POS, Vector3.ZERO)
	var wall_pos: Vector3 = raw_wall_pos if raw_wall_pos is Vector3 else Vector3.ZERO
	assert_almost_eq(wall_pos.z, -1.0, 0.05, "Wall contact Z must snap to block face at Z=-1.0.")

	var raw_ledge_y: Variant = anchors.get(GodivaFollower.ANCHOR_LEDGE_Y, 0.0)
	var ledge_y: float = raw_ledge_y if raw_ledge_y is float else 0.0
	assert_almost_eq(ledge_y, 1.4, 0.05, "Ledge ray must snap to exact top surface Y=1.4.")

	var raw_floor_y: Variant = anchors.get(GodivaFollower.ANCHOR_FLOOR_Y, 0.0)
	var floor_y: float = raw_floor_y if raw_floor_y is float else 0.0
	assert_almost_eq(
		floor_y, 1.4, 0.05, "Landing floor ray must snap floating exit_pos.y=1.55 down to Y=1.4."
	)

	var shelf: InteractiveShelf = SHELF_SCENE.instantiate() as InteractiveShelf
	arena.add_child(shelf)
	shelf.global_position = Vector3(0.0, 2.0, -4.0)
	var shelf_climb: Dictionary[StringName, Variant] = (
		_godiva
		. _probe_traversal_anchors(
			GodivaFollower.TRAVERSAL_SHELF_CLIMB,
			Vector3(0.0, 2.0, -3.0),
			Vector3(0.0, 2.0, -5.0),
			shelf,
		)
	)
	var raw_climb_y: Variant = shelf_climb.get(GodivaFollower.ANCHOR_LEDGE_Y, 0.0)
	var climb_y: float = raw_climb_y if raw_climb_y is float else 0.0
	assert_almost_eq(
		climb_y, 3.975, 0.01, "Shelf climb anchor must snap to shelf.y + 1.975 deck top."
	)


## Verifies testbed.tscn disables Link_Platform_OverheadSlab and bakes CSGBox3D11 into navmesh.
func test_testbed_navmesh_covers_csgbox11_and_disables_floating_link() -> void:
	var packed: PackedScene = ResourceLoader.load("res://levels/testbed.tscn") as PackedScene
	assert_not_null(packed, "levels/testbed.tscn must load cleanly.")
	var state: SceneState = packed.get_state()

	var found_disabled_overhead: bool = false
	var found_csg11_link: bool = false
	var nav_mesh: NavigationMesh = null

	for n_idx: int in range(state.get_node_count()):
		var node_name: StringName = state.get_node_name(n_idx)
		if node_name == &"Link_Platform_OverheadSlab":
			for p_idx: int in range(state.get_node_property_count(n_idx)):
				if state.get_node_property_name(n_idx, p_idx) == &"enabled":
					var raw_en: Variant = state.get_node_property_value(n_idx, p_idx)
					if raw_en is bool and not raw_en:
						found_disabled_overhead = true
		elif node_name == &"Link_OverheadSlab_To_CSGBox11":
			found_csg11_link = true
		elif node_name == &"GodivaNavigationRegion3D":
			for p_idx: int in range(state.get_node_property_count(n_idx)):
				if state.get_node_property_name(n_idx, p_idx) == &"navigation_mesh":
					var raw_nm: Variant = state.get_node_property_value(n_idx, p_idx)
					if raw_nm is NavigationMesh:
						nav_mesh = raw_nm as NavigationMesh

	assert_true(
		found_disabled_overhead, "Link_Platform_OverheadSlab must be disabled (enabled = false)."
	)
	assert_true(
		found_csg11_link, "Link_OverheadSlab_To_CSGBox11 must exist under GodivaNavigationRegion3D."
	)
	assert_not_null(nav_mesh, "GodivaNavigationRegion3D must have a NavigationMesh.")
	assert_eq(
		nav_mesh.filter_baking_aabb,
		AABB(Vector3(93.0, 31.5, -226.0), Vector3(28.0, 11.0, 44.0)),
		"NavigationMesh_godiva_test filter_baking_aabb must cover CSGBox3D11."
	)

	var csg11_vert_count: int = 0
	for v: Vector3 in nav_mesh.get_vertices():
		if v.z <= -214.0 and v.z >= -226.0 and v.y >= 37.0 and v.y <= 38.5:
			csg11_vert_count += 1
	assert_gt(
		csg11_vert_count, 0, "Baked NavigationMesh_godiva_test must include CSGBox3D11 vertices."
	)
