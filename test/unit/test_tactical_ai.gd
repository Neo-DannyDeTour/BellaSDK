## Unit tests for Two-Tier Hybrid Dynamic Squad Tactical AI.
class_name TestTacticalAI
extends GutTest

var _coordinator: SquadCoordinator = null
var _created_nodes: Array[Node] = []


## Creates a fresh [SquadCoordinator] before each test.
func before_each() -> void:
	_coordinator = SquadCoordinator.new()
	_created_nodes.append(_coordinator)


## Frees all allocated test nodes after each test.
func after_each() -> void:
	for node: Node in _created_nodes:
		if is_instance_valid(node):
			node.free()
	_created_nodes.clear()
	_coordinator = null


func _make_agent(pos: Vector3, hp: float = 100.0, aggro: bool = true) -> TacticalAgent:
	var agent: TacticalAgent = TacticalAgent.new()
	agent.use_position_override = true
	agent.position_override = pos
	agent.max_hp = 100.0
	agent.current_hp = hp
	agent.is_alive = true
	agent.set_aggro(aggro, Vector3(20.0, 0.0, 0.0))
	_created_nodes.append(agent)
	_coordinator.register_agent(agent)
	return agent


## Verifies clustering within R_form=12m, hard cap=3 overflow, and dissolution rules.
func test_clustering_cap_and_dissolution() -> void:
	var a1: TacticalAgent = _make_agent(Vector3(0.0, 0.0, 0.0))
	var a2: TacticalAgent = _make_agent(Vector3(4.0, 0.0, 0.0))
	var a3: TacticalAgent = _make_agent(Vector3(8.0, 0.0, 0.0))
	var a4: TacticalAgent = _make_agent(Vector3(10.0, 0.0, 0.0))
	var a5: TacticalAgent = _make_agent(Vector3(11.0, 0.0, 0.0))

	_coordinator.update_squads(0.1)
	assert_eq(_coordinator.get_squad_count(), 2, "5 nearby agents should form 3 + 2 squads.")

	var sq1: SquadCoordinator.SquadData = _coordinator.get_agent_squad(a1)
	var sq2: SquadCoordinator.SquadData = _coordinator.get_agent_squad(a4)
	assert_not_null(sq1, "First agent should belong to a squad.")
	assert_not_null(sq2, "Overflow agent should belong to parallel squad.")
	assert_ne(sq1.id, sq2.id, "Overflow squad must have distinct ID.")
	assert_eq(sq1.members.size(), 3, "First squad must respect hard cap of 3.")
	assert_eq(sq2.members.size(), 2, "Parallel squad should hold remaining 2 agents.")
	assert_eq(_coordinator.get_agent_squad(a2).id, sq1.id)
	assert_eq(_coordinator.get_agent_squad(a3).id, sq1.id)
	assert_eq(_coordinator.get_agent_squad(a5).id, sq2.id)

	# Spread > 24m dissolves squad 2
	a5.position_override = Vector3(50.0, 0.0, 0.0)
	_coordinator.update_squads(0.1)
	assert_eq(_coordinator.get_squad_count(), 1, "Spread > 24m should dissolve squad 2.")
	assert_eq(a4.squad_id, -1, "Dissolved member should have squad_id = -1.")

	# Dropping below 2 living members dissolves remaining squad
	a2.apply_damage(100.0)
	a3.apply_damage(100.0)
	a4.apply_damage(100.0)
	_coordinator.update_squads(0.1)
	assert_eq(_coordinator.get_squad_count(), 0, "Squad with <2 living members must dissolve.")


## Verifies morale deltas, out-of-LoS recovery, and PUSH/CONSERVATIVE/FLEE transitions.
func test_morale_and_mood_transitions() -> void:
	var a1: TacticalAgent = _make_agent(Vector3(0.0, 0.0, 0.0))
	var a2: TacticalAgent = _make_agent(Vector3(3.0, 0.0, 0.0))
	a1.has_los_to_target = false
	a2.has_los_to_target = false
	_coordinator.update_squads(0.1)

	var sq: SquadCoordinator.SquadData = _coordinator.get_agent_squad(a1)
	assert_not_null(sq)
	# Default morale 0.75 + 0.03 * 0.1 = 0.753
	assert_almost_eq(sq.morale, 0.753, 0.005, "Out-of-LoS should recover morale at +0.03/s.")
	assert_eq(sq.mood, TacticalTypes.MoodState.PUSH, "Full HP + 0.75 morale should be PUSH.")

	# Ally downed (-0.15) -> ~0.603 -> CONSERVATIVE
	a2.apply_damage(85.0, 20.0)
	assert_almost_eq(sq.morale, 0.603, 0.01, "Ally downed should reduce morale by 0.15.")
	assert_eq(sq.mood, TacticalTypes.MoodState.CONSERVATIVE)

	# Target damaged (+0.15)
	a1.report_target_damaged(25.0)
	assert_almost_eq(sq.morale, 0.753, 0.01, "Target damaged should raise morale by 0.15.")

	# Ally killed (-0.35) -> ~0.403; with low HP -> FLEE
	a1.current_hp = 20.0
	var a3: TacticalAgent = _make_agent(Vector3(2.0, 0.0, 0.0), 20.0)
	sq.members.append(a3)
	a3.squad_id = sq.id
	a3.apply_damage(100.0)
	assert_almost_eq(sq.morale, 0.403, 0.01, "Ally killed should reduce morale by 0.35.")
	var expected_eff: float = SquadCoordinator.compute_effective_mood(sq.morale, 0.175)
	assert_lt(expected_eff, SquadCoordinator.MOOD_FLEE_THRESHOLD)
	assert_eq(sq.mood, TacticalTypes.MoodState.FLEE, "Low morale + low HP should trigger FLEE.")


## Verifies greedy role auction, +0.25 hysteresis, elevation climb, and 3-imp StackSlam.
func test_role_auction_hysteresis_climb_and_stack_slam() -> void:
	var a1: TacticalAgent = _make_agent(Vector3(0.0, 0.0, 0.0))
	var a2: TacticalAgent = _make_agent(Vector3(2.0, 0.0, 0.0))
	var a3: TacticalAgent = _make_agent(Vector3(4.0, 0.0, 0.0))
	a1.last_known_target_pos = Vector3(10.0, 0.0, 0.0)
	a2.last_known_target_pos = Vector3(10.0, 0.0, 0.0)
	a3.last_known_target_pos = Vector3(10.0, 0.0, 0.0)

	watch_signals(_coordinator)
	_coordinator.update_squads(0.1)
	assert_signal_emitted(_coordinator, "stack_slam_triggered", "3 close PUSH imps trigger slam.")
	assert_eq(a1.current_role, TacticalTypes.Role.STACK_SLAM)
	assert_eq(a2.current_role, TacticalTypes.Role.STACK_SLAM)
	assert_eq(a3.current_role, TacticalTypes.Role.STACK_SLAM)

	# Spread one beyond 6m from centroid so STACK_SLAM stops and greedy auction + CLIMB runs
	a3.position_override = Vector3(12.0, 0.0, 0.0)
	a1.last_known_target_pos = Vector3(10.0, 5.0, 0.0)
	a2.last_known_target_pos = Vector3(10.0, 5.0, 0.0)
	a3.last_known_target_pos = Vector3(10.0, 5.0, 0.0)

	var link: NavigationLink3D = NavigationLink3D.new()
	link.start_position = Vector3(5.0, 0.0, 0.0)
	link.end_position = Vector3(8.0, 5.0, 0.0)
	_created_nodes.append(link)
	_coordinator.register_nav_link(link)

	var sq: SquadCoordinator.SquadData = _coordinator.get_agent_squad(a1)
	_coordinator.run_role_auction(sq)
	var has_climb: bool = (
		a1.current_role == TacticalTypes.Role.CLIMB
		or a2.current_role == TacticalTypes.Role.CLIMB
		or a3.current_role == TacticalTypes.Role.CLIMB
	)
	assert_true(has_climb, "Elevation > 2m with nearby NavigationLink3D should assign CLIMB.")

	# Hysteresis (+0.25) keeps current role over slight utility changes
	var prev_role_a1: TacticalTypes.Role = a1.current_role
	_coordinator.run_role_auction(sq)
	assert_eq(a1.current_role, prev_role_a1, "Hysteresis should prevent role oscillation.")


## Verifies SmartObject reservation exclusivity and release on death.
func test_smart_object_reservation() -> void:
	var a1: TacticalAgent = _make_agent(Vector3.ZERO)
	var a2: TacticalAgent = _make_agent(Vector3(1.0, 0.0, 0.0))
	var prop: RigidBody3D = RigidBody3D.new()
	prop.add_to_group(TacticalTypes.GROUP_THROWABLE)
	_created_nodes.append(prop)

	assert_true(a1.claim_smart_object(prop), "First agent should claim available prop.")
	assert_false(a2.claim_smart_object(prop), "Second agent cannot claim already-claimed prop.")
	a1.apply_damage(100.0)
	assert_true(a2.claim_smart_object(prop), "Prop should become available after claimer dies.")


## Verifies direct chest ballistic mode vs high-arc balcony-clearing ballistic mode.
func test_ballistic_solver_dual_mode() -> void:
	var origin: Vector3 = Vector3(0.0, 1.0, 0.0)
	var target: Vector3 = Vector3(12.0, 1.0, 0.0)

	var direct: TacticalTypes.BallisticSolution = TacticalAgent.solve_ballistic_throw(
		origin, target, 1.0, true
	)
	assert_true(direct.valid, "Direct ballistic solution should be valid.")
	assert_false(direct.is_high_arc, "Direct LoS should select direct chest mode.")
	assert_gt(direct.velocity.x, 0.0, "Direct velocity should point toward target X.")

	var obstacle_y: float = 4.0
	var high_arc: TacticalTypes.BallisticSolution = TacticalAgent.solve_ballistic_throw(
		origin, target, obstacle_y, false
	)
	assert_true(high_arc.valid, "High-arc ballistic solution should be valid.")
	assert_true(high_arc.is_high_arc, "Obstructed LoS should select high-arc mode.")
	assert_almost_eq(
		high_arc.apex_y,
		obstacle_y + TacticalAgent.HIGH_ARC_CLEARANCE,
		0.01,
		"High-arc apex must clear max_obstacle_y + 1.2m."
	)

	# Verify kinematic landing position at flight_time reaches LKP + 0.5m
	var t: float = high_arc.flight_time
	var end_pos: Vector3 = (
		origin
		+ high_arc.velocity * t
		+ Vector3(0.0, -0.5 * TacticalAgent.DEFAULT_GRAVITY * t * t, 0.0)
	)
	var expected_dest: Vector3 = target + Vector3(0.0, TacticalAgent.HIGH_ARC_LKP_Y_OFFSET, 0.0)
	assert_almost_eq(end_pos.x, expected_dest.x, 0.05)
	assert_almost_eq(end_pos.y, expected_dest.y, 0.05)
	assert_almost_eq(end_pos.z, expected_dest.z, 0.05)


## Verifies 8-point dynamic cover ring generation and LoS-breaking selection.
func test_eight_point_cover_probe() -> void:
	var pillar_center: Vector3 = Vector3(5.0, 0.0, 0.0)
	var ring: Array[Vector3] = TacticalAgent.generate_cover_ring_points(pillar_center, 1.2)
	assert_eq(ring.size(), 8, "Cover probe must generate 8 points around collider.")

	var agent_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
	var threat_pos: Vector3 = Vector3(12.0, 0.0, 0.0)
	var res: TacticalTypes.CoverProbeResult = TacticalAgent.probe_best_cover(
		agent_pos, threat_pos, [pillar_center]
	)
	assert_true(res.found, "Cover probe should find a valid point.")
	assert_true(res.breaks_los, "Selected cover point should break LoS to threat.")
	assert_lt(res.position.x, pillar_center.x, "Cover point should be on shielded side of pillar.")
