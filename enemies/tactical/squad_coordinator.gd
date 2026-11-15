## Two-Tier Squad Coordinator managing clustering, morale, and role auctions.
class_name SquadCoordinator
extends Node

## Emitted when a new squad of 2-3 aggroed agents forms.
signal squad_formed(squad_id: int, members: Array[TacticalAgent])

## Emitted when a squad dissolves due to casualties or spread > 24m.
signal squad_dissolved(squad_id: int)

## Emitted after a greedy role auction completes for a squad.
signal roles_assigned(squad_id: int, assignments: Dictionary[int, TacticalTypes.Role])

## Emitted when 3 living PUSH-mood members converge for a coordinated StackSlam.
signal stack_slam_triggered(squad_id: int, members: Array[TacticalAgent], target_pos: Vector3)

## Maximum formation radius in meters.
const R_FORM: float = 12.0

## Squared formation radius (12m^2 = 144.0).
const R_FORM_SQ: float = 144.0

## Maximum spread distance in meters before squad dissolution.
const R_DISSOLVE: float = 24.0

## Squared dissolution spread threshold (24m^2 = 576.0).
const R_DISSOLVE_SQ: float = 576.0

## Hard cap of living members per squad; overflow spawns a parallel squad.
const SQUAD_HARD_CAP: int = 3

## Minimum living, aggroed members required to maintain a squad.
const SQUAD_MIN_MEMBERS: int = 2

## Staggered interval in seconds between periodic role auctions.
const AUCTION_INTERVAL: float = 1.5

## Utility bonus added to an agent's current role to prevent oscillation.
const HYSTERESIS_BONUS: float = 0.25

## Target-above-centroid elevation delta in meters that triggers link queries.
const ELEVATION_THRESHOLD: float = 2.0

## Maximum radius in meters for querying [NavigationLink3D] climb paths.
const LINK_QUERY_RADIUS: float = 20.0

## Squared [NavigationLink3D] query radius (20m^2 = 400.0).
const LINK_QUERY_RADIUS_SQ: float = 400.0

## Default starting morale for newly formed squads.
const DEFAULT_MORALE: float = 0.75

## Morale delta when a squadmate is killed.
const MORALE_ALLY_KILLED: float = -0.35

## Morale delta when a squadmate is downed.
const MORALE_ALLY_DOWNED: float = -0.15

## Morale delta when the squad's target takes damage.
const MORALE_TARGET_DAMAGED: float = 0.15

## Morale recovery rate per second while all squadmates are out of LoS.
const MORALE_LOS_RECOVERY_PER_SEC: float = 0.03

## Effective mood threshold at or above which the squad enters PUSH.
const MOOD_PUSH_THRESHOLD: float = 0.65

## Effective mood threshold below which the squad enters FLEE.
const MOOD_FLEE_THRESHOLD: float = 0.30

## Maximum radius from centroid in meters for 3-imp StackSlam convergence.
const STACK_SLAM_RADIUS: float = 6.0

## Squared StackSlam convergence radius (6m^2 = 36.0).
const STACK_SLAM_RADIUS_SQ: float = 36.0

var _agents: Array[TacticalAgent] = []
var _nav_links: Array[NavigationLink3D] = []
var _squads: Dictionary[int, SquadData] = {}
var _next_squad_id: int = 1


## Internal state container for an active tactical squad.
class SquadData:
	extends RefCounted

	## Unique squad identifier.
	var id: int = 0
	## Active living members in this squad.
	var members: Array[TacticalAgent] = []
	## Current squad morale in [0.0, 1.0].
	var morale: float = DEFAULT_MORALE
	## Current squad mood state.
	var mood: TacticalTypes.MoodState = TacticalTypes.MoodState.PUSH
	## Last computed effective mood scalar in [0.0, 1.0].
	var effective_mood_value: float = DEFAULT_MORALE
	## Assigned role per agent instance ID.
	var role_map: Dictionary[int, TacticalTypes.Role] = {}
	## Countdown timer until the next staggered role auction.
	var auction_timer: float = 0.0
	## Mean world position of living squad members.
	var centroid: Vector3 = Vector3.ZERO
	## Shared last known target position.
	var target_pos: Vector3 = Vector3.ZERO
	## True when any member has reported a valid target position.
	var has_target: bool = false


## Discovers existing tactical agents and disables processing until active.
func _ready() -> void:
	set_process(false)
	if is_inside_tree():
		var existing: Array[Node] = get_tree().get_nodes_in_group(
			TacticalTypes.GROUP_TACTICAL_AGENT
		)
		for node: Node in existing:
			var agent: TacticalAgent = node as TacticalAgent
			if is_instance_valid(agent):
				register_agent(agent)


## Advances squad clustering, morale recovery, dissolution, and staggered auctions.
func _process(delta: float) -> void:
	if _agents.is_empty() and _squads.is_empty():
		set_process(false)
		return
	update_squads(delta)


## Registers a [TacticalAgent] and connects its lifecycle signals.
func register_agent(agent: TacticalAgent) -> void:
	if not is_instance_valid(agent) or _agents.has(agent):
		return
	_agents.append(agent)
	Utilities.safe_connect(agent.aggro_changed, _on_agent_aggro_changed)
	Utilities.safe_connect(agent.agent_died, _on_agent_died)
	Utilities.safe_connect(agent.agent_downed, _on_agent_downed)
	Utilities.safe_connect(agent.link_blocked, _on_agent_link_blocked)
	Utilities.safe_connect(agent.target_damaged, _on_agent_target_damaged)
	if is_inside_tree() and agent.is_aggroed:
		set_process(true)


## Unregisters a [TacticalAgent] and removes it from any active squad.
func unregister_agent(agent: TacticalAgent) -> void:
	_agents.erase(agent)
	if is_instance_valid(agent) and agent.squad_id != -1:
		var squad: SquadData = _squads.get(agent.squad_id, null)
		if squad != null:
			squad.members.erase(agent)
		agent.squad_id = -1


## Registers a [NavigationLink3D] for elevation climb queries.
func register_nav_link(link: NavigationLink3D) -> void:
	if is_instance_valid(link) and not _nav_links.has(link):
		_nav_links.append(link)


## Unregisters a [NavigationLink3D].
func unregister_nav_link(link: NavigationLink3D) -> void:
	_nav_links.erase(link)


## Deterministic tick driving clustering, dissolution, morale, and staggered auctions.
func update_squads(delta: float) -> void:
	_prune_invalid_agents()
	_check_dissolutions()
	cluster_unassigned_agents()

	var squad_ids: Array[int] = _squads.keys()
	for sid: int in squad_ids:
		var squad: SquadData = _squads.get(sid, null)
		if squad == null:
			continue
		_refresh_squad_kinematics(squad)
		_update_squad_morale_and_mood(squad, delta)
		squad.auction_timer -= delta
		if squad.auction_timer <= 0.0:
			squad.auction_timer = AUCTION_INTERVAL
			run_role_auction(squad)


## Clusters unassigned aggroed agents within R_form (12m) up to hard cap 3 per squad.
func cluster_unassigned_agents() -> void:
	var pool: Array[TacticalAgent] = []
	for agent: TacticalAgent in _agents:
		if not is_instance_valid(agent) or not agent.is_alive or not agent.is_aggroed:
			continue
		if agent.squad_id != -1:
			continue
		pool.append(agent)

	var used: Dictionary[int, bool] = {}
	for i: int in range(pool.size()):
		var seed_agent: TacticalAgent = pool[i]
		var seed_id: int = seed_agent.get_instance_id()
		if used.has(seed_id):
			continue

		var cluster: Array[TacticalAgent] = [seed_agent]
		var seed_pos: Vector3 = seed_agent.get_agent_position()
		for j: int in range(i + 1, pool.size()):
			if cluster.size() >= SQUAD_HARD_CAP:
				break
			var candidate: TacticalAgent = pool[j]
			var cand_id: int = candidate.get_instance_id()
			if used.has(cand_id):
				continue
			if seed_pos.distance_squared_to(candidate.get_agent_position()) <= R_FORM_SQ:
				cluster.append(candidate)

		if cluster.size() >= SQUAD_MIN_MEMBERS:
			for member: TacticalAgent in cluster:
				used[member.get_instance_id()] = true
			_create_squad(cluster)


## Runs greedy utility role auction with +0.25 hysteresis and 3-imp StackSlam check.
func run_role_auction(squad: SquadData) -> void:
	if squad == null or squad.members.is_empty():
		return
	_refresh_squad_kinematics(squad)
	_update_squad_morale_and_mood(squad, 0.0)

	# 3-imp STACK_SLAM trigger when 3 living members are in PUSH mood and close together
	if _can_trigger_stack_slam(squad):
		var slam_roles: Dictionary[int, TacticalTypes.Role] = {}
		for member: TacticalAgent in squad.members:
			var mid: int = member.get_instance_id()
			slam_roles[mid] = TacticalTypes.Role.STACK_SLAM
			member.assign_role(TacticalTypes.Role.STACK_SLAM, squad.mood)
		squad.role_map = slam_roles
		print("SquadCoordinator: STACK_SLAM triggered for squad ", squad.id)
		roles_assigned.emit(squad.id, slam_roles)
		stack_slam_triggered.emit(squad.id, squad.members.duplicate(), squad.target_pos)
		return

	var climb_links: Array[NavigationLink3D] = []
	var elev_diff: float = squad.target_pos.y - squad.centroid.y
	if squad.has_target and elev_diff > ELEVATION_THRESHOLD:
		climb_links = query_climb_links(squad.centroid, LINK_QUERY_RADIUS)
	var has_climb_link: bool = not climb_links.is_empty()

	var candidate_roles: Array[TacticalTypes.Role] = [
		TacticalTypes.Role.CLIMB,
		TacticalTypes.Role.SUPPRESS_THROW,
		TacticalTypes.Role.FLANK,
		TacticalTypes.Role.HOLD_CHOKE,
		TacticalTypes.Role.RETREAT,
		TacticalTypes.Role.WATER_DIVE,
	]

	var bids: Array[Dictionary] = []
	for member: TacticalAgent in squad.members:
		if not is_instance_valid(member) or not member.is_alive:
			continue
		var mid: int = member.get_instance_id()
		var prev_role: int = int(squad.role_map.get(mid, -1))
		var has_throwable: bool = (
			is_instance_valid(member.held_prop) or not member.query_nearby_throwables().is_empty()
		)
		for role: TacticalTypes.Role in candidate_roles:
			var utility: float = member.evaluate_role_utility(
				role, squad.mood, squad.target_pos, has_throwable, has_climb_link
			)
			if prev_role == int(role):
				utility += HYSTERESIS_BONUS
			bids.append({"score": utility, "agent": member, "role": role})

	bids.sort_custom(_sort_bids_desc)

	var assigned_agents: Dictionary[int, bool] = {}
	var taken_roles: Dictionary[int, bool] = {}
	var new_map: Dictionary[int, TacticalTypes.Role] = {}

	for bid: Dictionary in bids:
		var raw_agent: Variant = bid.get("agent", null)
		var agent: TacticalAgent = raw_agent as TacticalAgent
		if not is_instance_valid(agent):
			continue
		var aid: int = agent.get_instance_id()
		if assigned_agents.has(aid):
			continue
		var raw_role: Variant = bid.get("role", TacticalTypes.Role.FLANK)
		var role_int: int = raw_role if raw_role is int else int(TacticalTypes.Role.FLANK)
		var role: TacticalTypes.Role = role_int as TacticalTypes.Role
		var allow_shared: bool = (
			role == TacticalTypes.Role.RETREAT or role == TacticalTypes.Role.WATER_DIVE
		)
		if not allow_shared and taken_roles.has(role_int):
			continue
		assigned_agents[aid] = true
		if not allow_shared:
			taken_roles[role_int] = true
		new_map[aid] = role
		agent.assign_role(role, squad.mood)

	squad.role_map = new_map
	roles_assigned.emit(squad.id, new_map)


## Queries available [NavigationLink3D] nodes within [param radius] meters of [param origin].
func query_climb_links(
	origin: Vector3, radius: float = LINK_QUERY_RADIUS
) -> Array[NavigationLink3D]:
	var results: Array[NavigationLink3D] = []
	var radius_sq: float = radius * radius
	for link: NavigationLink3D in _nav_links:
		if not is_instance_valid(link) or not link.enabled:
			continue
		if link.has_meta(TacticalTypes.META_CLAIMED_BY):
			var raw_owner: Variant = link.get_meta(TacticalTypes.META_CLAIMED_BY)
			var owner_id: int = raw_owner if raw_owner is int else -1
			if owner_id != -1:
				continue
		var link_pos: Vector3 = (
			link.global_position if link.is_inside_tree() else link.start_position
		)
		if link_pos == Vector3.ZERO and link.start_position != Vector3.ZERO:
			link_pos = link.start_position
		if origin.distance_squared_to(link_pos) <= radius_sq:
			results.append(link)
	return results


## Applies a morale delta to [param squad_id] and triggers immediate re-auction if requested.
func apply_morale_event(squad_id: int, delta_morale: float, reauction: bool = false) -> void:
	var squad: SquadData = _squads.get(squad_id, null)
	if squad == null:
		return
	squad.morale = clampf(squad.morale + delta_morale, 0.0, 1.0)
	_update_squad_morale_and_mood(squad, 0.0)
	if reauction:
		squad.auction_timer = AUCTION_INTERVAL
		run_role_auction(squad)


## Returns the [SquadData] for [param squad_id], or null if not found.
func get_squad(squad_id: int) -> SquadData:
	return _squads.get(squad_id, null)


## Returns the [SquadData] containing [param agent], or null if unassigned.
func get_agent_squad(agent: TacticalAgent) -> SquadData:
	if not is_instance_valid(agent) or agent.squad_id == -1:
		return null
	return _squads.get(agent.squad_id, null)


## Returns the number of active squads.
func get_squad_count() -> int:
	return _squads.size()


## Computes effective_mood = clampf(squad_morale * (0.5 + 0.5 * hp_ratio), 0.0, 1.0).
static func compute_effective_mood(squad_morale: float, hp_ratio: float) -> float:
	return clampf(squad_morale * (0.5 + 0.5 * clampf(hp_ratio, 0.0, 1.0)), 0.0, 1.0)


## Maps effective mood scalar in [0.0, 1.0] to [enum TacticalTypes.MoodState].
static func mood_from_effective_value(value: float) -> TacticalTypes.MoodState:
	if value >= MOOD_PUSH_THRESHOLD:
		return TacticalTypes.MoodState.PUSH
	if value >= MOOD_FLEE_THRESHOLD:
		return TacticalTypes.MoodState.CONSERVATIVE
	return TacticalTypes.MoodState.FLEE


func _create_squad(members: Array[TacticalAgent]) -> void:
	var squad: SquadData = SquadData.new()
	squad.id = _next_squad_id
	_next_squad_id += 1
	squad.members = members.duplicate()
	squad.morale = DEFAULT_MORALE
	squad.auction_timer = float(squad.id % 5) * 0.2
	for member: TacticalAgent in squad.members:
		member.squad_id = squad.id
	_squads[squad.id] = squad
	_refresh_squad_kinematics(squad)
	_update_squad_morale_and_mood(squad, 0.0)
	print("SquadCoordinator: Formed squad ", squad.id, " size=", squad.members.size())
	squad_formed.emit(squad.id, squad.members.duplicate())
	run_role_auction(squad)


func _check_dissolutions() -> void:
	var to_dissolve: Array[int] = []
	for sid: int in _squads.keys():
		var squad: SquadData = _squads[sid]
		var living: Array[TacticalAgent] = []
		for member: TacticalAgent in squad.members:
			if is_instance_valid(member) and member.is_alive and member.is_aggroed:
				living.append(member)
			elif is_instance_valid(member):
				member.squad_id = -1
		squad.members = living

		if living.size() < SQUAD_MIN_MEMBERS:
			to_dissolve.append(sid)
			continue
		if _compute_max_spread_sq(living) > R_DISSOLVE_SQ:
			to_dissolve.append(sid)

	for sid: int in to_dissolve:
		var squad: SquadData = _squads[sid]
		for member: TacticalAgent in squad.members:
			if is_instance_valid(member):
				member.squad_id = -1
		_squads.erase(sid)
		print("SquadCoordinator: Dissolved squad ", sid)
		squad_dissolved.emit(sid)


func _compute_max_spread_sq(members: Array[TacticalAgent]) -> float:
	var max_sq: float = 0.0
	for i: int in range(members.size()):
		var pos_a: Vector3 = members[i].get_agent_position()
		for j: int in range(i + 1, members.size()):
			var d_sq: float = pos_a.distance_squared_to(members[j].get_agent_position())
			if d_sq > max_sq:
				max_sq = d_sq
	return max_sq


func _refresh_squad_kinematics(squad: SquadData) -> void:
	if squad.members.is_empty():
		return
	var sum_pos: Vector3 = Vector3.ZERO
	var count: int = 0
	for member: TacticalAgent in squad.members:
		if not is_instance_valid(member) or not member.is_alive:
			continue
		sum_pos += member.get_agent_position()
		count += 1
		if member.is_aggroed:
			squad.target_pos = member.last_known_target_pos
			squad.has_target = true
	if count > 0:
		squad.centroid = sum_pos / float(count)


func _update_squad_morale_and_mood(squad: SquadData, delta: float) -> void:
	var hp_sum: float = 0.0
	var count: int = 0
	var any_los: bool = false
	for member: TacticalAgent in squad.members:
		if not is_instance_valid(member) or not member.is_alive:
			continue
		hp_sum += member.get_hp_ratio()
		count += 1
		if member.has_los_to_target:
			any_los = true
	if count == 0:
		return
	if delta > 0.0 and not any_los:
		squad.morale = clampf(squad.morale + MORALE_LOS_RECOVERY_PER_SEC * delta, 0.0, 1.0)
	var avg_hp_ratio: float = hp_sum / float(count)
	squad.effective_mood_value = compute_effective_mood(squad.morale, avg_hp_ratio)
	squad.mood = mood_from_effective_value(squad.effective_mood_value)


func _can_trigger_stack_slam(squad: SquadData) -> bool:
	if squad.members.size() != SQUAD_HARD_CAP:
		return false
	if squad.mood != TacticalTypes.MoodState.PUSH or not squad.has_target:
		return false
	for member: TacticalAgent in squad.members:
		if not is_instance_valid(member) or not member.is_alive or member.is_downed:
			return false
		if member.get_agent_position().distance_squared_to(squad.centroid) > STACK_SLAM_RADIUS_SQ:
			return false
	return true


func _prune_invalid_agents() -> void:
	for i: int in range(_agents.size() - 1, -1, -1):
		if not is_instance_valid(_agents[i]):
			_agents.remove_at(i)


func _sort_bids_desc(a: Dictionary, b: Dictionary) -> bool:
	var raw_a: Variant = a.get("score", 0.0)
	var raw_b: Variant = b.get("score", 0.0)
	var score_a: float = raw_a if raw_a is float else 0.0
	var score_b: float = raw_b if raw_b is float else 0.0
	return score_a > score_b


func _on_agent_aggro_changed(_agent: TacticalAgent, active: bool) -> void:
	if active and is_inside_tree():
		set_process(true)


func _on_agent_died(agent: TacticalAgent) -> void:
	if not is_instance_valid(agent) or agent.squad_id == -1:
		return
	var sid: int = agent.squad_id
	agent.squad_id = -1
	var squad: SquadData = _squads.get(sid, null)
	if squad == null:
		return
	squad.members.erase(agent)
	apply_morale_event(sid, MORALE_ALLY_KILLED, true)


func _on_agent_downed(agent: TacticalAgent) -> void:
	if not is_instance_valid(agent) or agent.squad_id == -1:
		return
	apply_morale_event(agent.squad_id, MORALE_ALLY_DOWNED, true)


func _on_agent_link_blocked(agent: TacticalAgent, _link: NavigationLink3D) -> void:
	if not is_instance_valid(agent) or agent.squad_id == -1:
		return
	var squad: SquadData = _squads.get(agent.squad_id, null)
	if squad != null:
		squad.auction_timer = AUCTION_INTERVAL
		run_role_auction(squad)


func _on_agent_target_damaged(agent: TacticalAgent, _amount: float) -> void:
	if not is_instance_valid(agent) or agent.squad_id == -1:
		return
	apply_morale_event(agent.squad_id, MORALE_TARGET_DAMAGED, false)
