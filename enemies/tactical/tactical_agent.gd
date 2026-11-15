## Component on [CharacterBody3D] executing utility curves, ActionQueue, and probes.
class_name TacticalAgent
extends Node

## Emitted when agent aggro state changes.
signal aggro_changed(agent: TacticalAgent, active: bool)

## Emitted when agent health reaches zero.
signal agent_died(agent: TacticalAgent)

## Emitted when agent enters downed state.
signal agent_downed(agent: TacticalAgent)

## Emitted when a claimed [NavigationLink3D] becomes blocked.
signal link_blocked(agent: TacticalAgent, link: NavigationLink3D)

## Emitted when agent damages its current target.
signal target_damaged(agent: TacticalAgent, amount: float)

## Emitted when [SquadCoordinator] assigns a new tactical role.
signal role_changed(agent: TacticalAgent, new_role: TacticalTypes.Role)

## Emitted when an [TacticalTypes.ActionItem] begins execution.
signal action_started(agent: TacticalAgent, action: TacticalTypes.ActionItem)

## Staggered AI think interval in seconds.
const THINK_INTERVAL: float = 0.25

## Default radius for 8-point dynamic cover ring around Layer 1 colliders.
const COVER_RING_RADIUS: float = 1.2

## Number of probe points around each cover collider.
const COVER_RING_POINTS: int = 8

## Radius in meters for throwable SmartObject physics shape query.
const THROWABLE_QUERY_RADIUS: float = 10.0

## Extra vertical clearance above obstacle Y for high-arc balcony throws.
const HIGH_ARC_CLEARANCE: float = 1.2

## Vertical aim offset above last known position for high-arc throws.
const HIGH_ARC_LKP_Y_OFFSET: float = 0.5

## Default throw speed in m/s for direct chest-level throws.
const DIRECT_THROW_SPEED: float = 16.0

## Default gravity magnitude used by the ballistic solver.
const DEFAULT_GRAVITY: float = 9.8

## Maximum aggro distance in meters before gating think updates.
@export var max_aggro_distance: float = 40.0

## Maximum health points for this agent.
@export var max_hp: float = 100.0

## Optional visibility notifier used to gate off-screen think cycles.
@export var visibility_notifier: VisibleOnScreenNotifier3D = null

## Current health points.
var current_hp: float = 100.0

## True while the agent is alive.
var is_alive: bool = true

## True while the agent is downed but not killed.
var is_downed: bool = false

## True when the agent has detected and engaged a target.
var is_aggroed: bool = false

## True when the agent is currently positioned in cover.
var is_in_cover: bool = false

## True when the agent is currently submerged in a water volume.
var is_in_water: bool = false

## True when the agent has unobstructed line-of-sight to its target.
var has_los_to_target: bool = false

## Last known world position of the target.
var last_known_target_pos: Vector3 = Vector3.ZERO

## Assigned tactical role from [SquadCoordinator].
var current_role: TacticalTypes.Role = TacticalTypes.Role.FLANK

## Current squad mood state.
var current_mood: TacticalTypes.MoodState = TacticalTypes.MoodState.PUSH

## Assigned squad ID (-1 when unassigned).
var squad_id: int = -1

## Sequential action steps generated from the active role.
var action_queue: Array[TacticalTypes.ActionItem] = []

## Currently held throwable prop, if any.
var held_prop: RigidBody3D = null

## Currently claimed [NavigationLink3D], if any.
var claimed_link: NavigationLink3D = null

## Cached parent [CharacterBody3D] owning this component.
var owner_body: CharacterBody3D = null

## Optional override position for headless unit testing without a scene tree.
var position_override: Vector3 = Vector3.ZERO

## Flag enabling [member position_override] when no [member owner_body] is attached.
var use_position_override: bool = false

var _think_timer: float = 0.0
var _claimed_objects: Array[Node] = []


## Initializes component state and disables per-frame processing until aggroed.
func _ready() -> void:
	owner_body = get_parent() as CharacterBody3D
	current_hp = max_hp
	add_to_group(TacticalTypes.GROUP_TACTICAL_AGENT)
	_think_timer = float(abs(get_instance_id()) % 10) * 0.025
	set_process(false)
	set_physics_process(false)


## Releases any SmartObject claims when leaving the scene tree.
func _exit_tree() -> void:
	release_all_claims()


## Runs staggered 0.25s think cycles while aggroed and within gating bounds.
func _process(delta: float) -> void:
	if not is_alive or not is_aggroed:
		set_process(false)
		return
	if not _is_update_gated_in():
		return
	_think_timer += delta
	if _think_timer < THINK_INTERVAL:
		return
	_think_timer = fmod(_think_timer, THINK_INTERVAL)
	think_step()


## Handles physics-rate movement when active and not idle or in cover.
func _physics_process(_delta: float) -> void:
	if not is_alive or not is_aggroed or is_in_cover or action_queue.is_empty():
		set_physics_process(false)


## Returns the agent's current world position.
func get_agent_position() -> Vector3:
	if is_instance_valid(owner_body):
		return owner_body.global_position
	if use_position_override:
		return position_override
	return Vector3.ZERO


## Sets aggro state and toggles staggered [method _process] execution.
func set_aggro(active: bool, target_pos: Vector3 = Vector3.ZERO) -> void:
	if active:
		last_known_target_pos = target_pos
	var changed: bool = is_aggroed != active
	is_aggroed = active
	if is_inside_tree():
		set_process(is_aggroed and is_alive)
	if not is_aggroed:
		set_physics_process(false)
	if changed:
		print("TacticalAgent: Aggro -> ", is_aggroed, " id=", get_instance_id())
		aggro_changed.emit(self, is_aggroed)


## Applies damage and emits [signal agent_died] or [signal agent_downed] as needed.
func apply_damage(amount: float, down_threshold: float = 0.0) -> void:
	if not is_alive or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	if current_hp <= 0.0:
		is_alive = false
		is_aggroed = false
		release_all_claims()
		set_process(false)
		set_physics_process(false)
		print("TacticalAgent: Died id=", get_instance_id())
		agent_died.emit(self)
	elif down_threshold > 0.0 and current_hp <= down_threshold and not is_downed:
		is_downed = true
		release_all_claims()
		set_physics_process(false)
		print("TacticalAgent: Downed id=", get_instance_id())
		agent_downed.emit(self)


## Returns normalized HP ratio in [0.0, 1.0].
func get_hp_ratio() -> float:
	if max_hp <= 0.0:
		return 0.0
	return clampf(current_hp / max_hp, 0.0, 1.0)


## Notifies listeners that this agent dealt damage to its target.
func report_target_damaged(amount: float) -> void:
	target_damaged.emit(self, amount)


## Notifies listeners that a claimed [NavigationLink3D] is blocked.
func report_link_blocked(link: NavigationLink3D) -> void:
	if claimed_link == link:
		release_smart_object(link)
		claimed_link = null
	link_blocked.emit(self, link)


## Assigns a new tactical role and rebuilds the [member action_queue].
func assign_role(new_role: TacticalTypes.Role, new_mood: TacticalTypes.MoodState) -> void:
	var role_updated: bool = current_role != new_role
	current_role = new_role
	current_mood = new_mood
	is_in_cover = (
		new_role == TacticalTypes.Role.HOLD_CHOKE or new_role == TacticalTypes.Role.RETREAT
	)
	if role_updated:
		print("TacticalAgent: Role -> ", new_role, " id=", get_instance_id())
		role_changed.emit(self, new_role)


## Executes one 0.25s tactical think step, refreshing ActionQueue if empty.
func think_step() -> void:
	if action_queue.is_empty():
		build_action_queue(current_role, last_known_target_pos)
	if not action_queue.is_empty() and not is_in_cover:
		if is_inside_tree():
			set_physics_process(true)
	else:
		if is_inside_tree():
			set_physics_process(false)


## Pops and returns the next [TacticalTypes.ActionItem] from [member action_queue].
func pop_next_action() -> TacticalTypes.ActionItem:
	if action_queue.is_empty():
		set_physics_process(false)
		return null
	var next_item: TacticalTypes.ActionItem = action_queue.pop_front()
	action_started.emit(self, next_item)
	return next_item


## Computes a continuous utility score in [0.0, 1.0] for [param role].
func evaluate_role_utility(
	role: TacticalTypes.Role,
	mood: TacticalTypes.MoodState,
	target_pos: Vector3,
	has_throwable: bool,
	has_climb_link: bool
) -> float:
	var agent_pos: Vector3 = get_agent_position()
	var dist_sq: float = agent_pos.distance_squared_to(target_pos)
	var hp_ratio: float = get_hp_ratio()
	var elev_diff: float = target_pos.y - agent_pos.y
	var raw_score: float = 0.0

	match role:
		TacticalTypes.Role.CLIMB:
			if has_climb_link and elev_diff > 2.0:
				var elev_factor: float = clampf((elev_diff - 2.0) / 6.0, 0.25, 1.0)
				raw_score = 0.55 + 0.45 * elev_factor
			else:
				raw_score = 0.05
		TacticalTypes.Role.SUPPRESS_THROW:
			var range_curve: float = clampf(1.0 - absf(sqrt(dist_sq) - 12.0) / 18.0, 0.0, 1.0)
			if has_throwable or is_instance_valid(held_prop):
				raw_score = 0.45 + 0.45 * range_curve
			else:
				raw_score = 0.1
		TacticalTypes.Role.FLANK:
			var push_bonus: float = 0.25 if mood == TacticalTypes.MoodState.PUSH else 0.0
			var dist_curve: float = clampf(1.0 - dist_sq / 900.0, 0.1, 1.0)
			raw_score = 0.35 + 0.35 * dist_curve * hp_ratio + push_bonus
		TacticalTypes.Role.HOLD_CHOKE:
			var conservative_bonus: float = (
				0.3 if mood == TacticalTypes.MoodState.CONSERVATIVE else 0.05
			)
			var cover_need: float = clampf(1.0 - hp_ratio * 0.5, 0.2, 0.9)
			raw_score = 0.25 + 0.4 * cover_need + conservative_bonus
		TacticalTypes.Role.RETREAT:
			var flee_bonus: float = 0.65 if mood == TacticalTypes.MoodState.FLEE else 0.0
			raw_score = flee_bonus + (1.0 - hp_ratio) * 0.35
		TacticalTypes.Role.STACK_SLAM:
			if mood == TacticalTypes.MoodState.PUSH and dist_sq <= 400.0:
				raw_score = 0.65 * hp_ratio
			else:
				raw_score = 0.0
		TacticalTypes.Role.WATER_DIVE:
			raw_score = 0.85 if is_in_water else 0.05

	return clampf(raw_score, 0.0, 1.0)


## Builds [member action_queue] for [param role] toward [param target_pos].
func build_action_queue(
	role: TacticalTypes.Role,
	target_pos: Vector3,
	cover_colliders: Array[Vector3] = [],
	climb_links: Array[NavigationLink3D] = []
) -> Array[TacticalTypes.ActionItem]:
	action_queue.clear()
	var agent_pos: Vector3 = get_agent_position()

	match role:
		TacticalTypes.Role.CLIMB:
			var link: NavigationLink3D = _pick_available_link(climb_links)
			if is_instance_valid(link) and claim_smart_object(link):
				claimed_link = link
				action_queue.append(
					TacticalTypes.ActionItem.new(
						TacticalTypes.ActionType.CLIMB_LINK, link.end_position, Vector3.ZERO, link
					)
				)
			action_queue.append(
				TacticalTypes.ActionItem.new(TacticalTypes.ActionType.MOVE_TO, target_pos)
			)
		TacticalTypes.Role.SUPPRESS_THROW:
			var prop: RigidBody3D = held_prop
			if not is_instance_valid(prop):
				var nearby: Array[RigidBody3D] = query_nearby_throwables(THROWABLE_QUERY_RADIUS)
				if not nearby.is_empty() and claim_smart_object(nearby[0]):
					prop = nearby[0]
					action_queue.append(
						TacticalTypes.ActionItem.new(
							TacticalTypes.ActionType.PICK_UP_PROP,
							prop.global_position,
							Vector3.ZERO,
							prop
						)
					)
			if is_instance_valid(prop):
				var sol: TacticalTypes.BallisticSolution = solve_ballistic_throw(
					agent_pos, target_pos, target_pos.y, has_los_to_target
				)
				action_queue.append(
					TacticalTypes.ActionItem.new(
						TacticalTypes.ActionType.THROW_PROP, target_pos, sol.velocity, prop
					)
				)
			else:
				action_queue.append(
					TacticalTypes.ActionItem.new(TacticalTypes.ActionType.MOVE_TO, target_pos)
				)
		TacticalTypes.Role.FLANK:
			var to_target: Vector3 = target_pos - agent_pos
			var side: Vector3 = Vector3(-to_target.z, 0.0, to_target.x).normalized()
			var flank_pos: Vector3 = target_pos + side * 4.0
			action_queue.append(
				TacticalTypes.ActionItem.new(TacticalTypes.ActionType.MOVE_TO, flank_pos)
			)
		TacticalTypes.Role.HOLD_CHOKE, TacticalTypes.Role.RETREAT:
			var cover_res: TacticalTypes.CoverProbeResult = probe_best_cover(
				agent_pos, target_pos, cover_colliders
			)
			var dest: Vector3 = (
				cover_res.position
				if cover_res.found
				else agent_pos + (agent_pos - target_pos).normalized() * 6.0
			)
			action_queue.append(
				TacticalTypes.ActionItem.new(TacticalTypes.ActionType.TAKE_COVER, dest)
			)
		TacticalTypes.Role.STACK_SLAM:
			action_queue.append(
				TacticalTypes.ActionItem.new(TacticalTypes.ActionType.STACK_SLAM, target_pos)
			)
		TacticalTypes.Role.WATER_DIVE:
			action_queue.append(
				TacticalTypes.ActionItem.new(TacticalTypes.ActionType.WATER_DIVE, target_pos)
			)

	return action_queue


## Claims [param obj] for this agent using [member TacticalTypes.META_CLAIMED_BY].
func claim_smart_object(obj: Node) -> bool:
	if not is_instance_valid(obj):
		return false
	if not is_smart_object_available(obj):
		return false
	obj.set_meta(TacticalTypes.META_CLAIMED_BY, get_instance_id())
	if not _claimed_objects.has(obj):
		_claimed_objects.append(obj)
	return true


## Releases [param obj] if currently claimed by this agent.
func release_smart_object(obj: Node) -> void:
	if not is_instance_valid(obj):
		return
	if obj.has_meta(TacticalTypes.META_CLAIMED_BY):
		var raw_owner: Variant = obj.get_meta(TacticalTypes.META_CLAIMED_BY)
		var owner_id: int = raw_owner if raw_owner is int else -1
		if owner_id == get_instance_id():
			obj.remove_meta(TacticalTypes.META_CLAIMED_BY)
	_claimed_objects.erase(obj)


## Releases all SmartObjects currently claimed by this agent.
func release_all_claims() -> void:
	for obj: Node in _claimed_objects:
		if is_instance_valid(obj) and obj.has_meta(TacticalTypes.META_CLAIMED_BY):
			var raw_owner: Variant = obj.get_meta(TacticalTypes.META_CLAIMED_BY)
			var owner_id: int = raw_owner if raw_owner is int else -1
			if owner_id == get_instance_id():
				obj.remove_meta(TacticalTypes.META_CLAIMED_BY)
	_claimed_objects.clear()
	claimed_link = null


## Returns true if [param obj] is unclaimed or already claimed by this agent.
func is_smart_object_available(obj: Node) -> bool:
	if not is_instance_valid(obj):
		return false
	if not obj.has_meta(TacticalTypes.META_CLAIMED_BY):
		return true
	var raw_owner: Variant = obj.get_meta(TacticalTypes.META_CLAIMED_BY)
	var owner_id: int = raw_owner if raw_owner is int else -1
	return owner_id == -1 or owner_id == get_instance_id()


## Queries nearby [RigidBody3D] throwables on Layer 3/4 within [param radius] meters.
func query_nearby_throwables(radius: float = THROWABLE_QUERY_RADIUS) -> Array[RigidBody3D]:
	var results: Array[RigidBody3D] = []
	if not is_inside_tree() or not is_instance_valid(owner_body):
		return results
	var world: World3D = owner_body.get_world_3d()
	if world == null:
		return results
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return results

	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, get_agent_position())
	query.collision_mask = TacticalTypes.MASK_THROWABLES
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var hits: Array[Dictionary] = space_state.intersect_shape(query, 16)
	for hit: Dictionary in hits:
		var raw_col: Variant = hit.get("collider", null)
		var body: RigidBody3D = raw_col as RigidBody3D
		if not is_instance_valid(body):
			continue
		if not body.is_in_group(TacticalTypes.GROUP_THROWABLE):
			continue
		if is_smart_object_available(body):
			results.append(body)
	return results


## Computes a dual-mode ballistic throw velocity (direct chest vs high-arc balcony clear).
static func solve_ballistic_throw(
	origin: Vector3,
	target: Vector3,
	max_obstacle_y: float,
	has_direct_los: bool,
	gravity: float = DEFAULT_GRAVITY,
	direct_speed: float = DIRECT_THROW_SPEED
) -> TacticalTypes.BallisticSolution:
	var solution: TacticalTypes.BallisticSolution = TacticalTypes.BallisticSolution.new()
	if gravity <= 0.0:
		return solution

	if has_direct_los:
		var delta_pos: Vector3 = target - origin
		var horiz: Vector3 = Vector3(delta_pos.x, 0.0, delta_pos.z)
		var horiz_dist: float = horiz.length()
		var speed: float = maxf(direct_speed, 1.0)
		var v2: float = speed * speed
		var v4: float = v2 * v2
		var disc: float = (
			v4 - gravity * (gravity * horiz_dist * horiz_dist + 2.0 * delta_pos.y * v2)
		)
		if disc >= 0.0 and horiz_dist > 0.001:
			var angle: float = atan2(v2 - sqrt(disc), gravity * horiz_dist)
			var dir_xz: Vector3 = horiz / horiz_dist
			var vx: float = speed * cos(angle)
			var vy: float = speed * sin(angle)
			solution.velocity = dir_xz * vx + Vector3(0.0, vy, 0.0)
			solution.flight_time = horiz_dist / maxf(vx, 0.001)
			solution.is_high_arc = false
			solution.apex_y = origin.y + (vy * vy) / (2.0 * gravity)
			solution.valid = true
			return solution

	# High-arc balcony-clearing trajectory: clear max_obstacle_y + 1.2m -> LKP + 0.5m
	var dest: Vector3 = target + Vector3(0.0, HIGH_ARC_LKP_Y_OFFSET, 0.0)
	var apex_y: float = maxf(max_obstacle_y, maxf(origin.y, dest.y)) + HIGH_ARC_CLEARANCE
	var vy_up: float = sqrt(2.0 * gravity * maxf(apex_y - origin.y, 0.01))
	var t_up: float = vy_up / gravity
	var t_down: float = sqrt(2.0 * maxf(apex_y - dest.y, 0.01) / gravity)
	var t_total: float = maxf(t_up + t_down, 0.05)
	var horiz_vec: Vector3 = Vector3(dest.x - origin.x, 0.0, dest.z - origin.z)
	var horiz_vel: Vector3 = horiz_vec / t_total

	solution.velocity = Vector3(horiz_vel.x, vy_up, horiz_vel.z)
	solution.flight_time = t_total
	solution.is_high_arc = true
	solution.apex_y = apex_y
	solution.valid = true
	return solution


## Generates 8 evenly spaced probe points on a [param radius] ring around [param center].
static func generate_cover_ring_points(
	center: Vector3, radius: float = COVER_RING_RADIUS
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for idx: int in range(COVER_RING_POINTS):
		var angle: float = (TAU / float(COVER_RING_POINTS)) * float(idx)
		var offset: Vector3 = Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		points.append(center + offset)
	return points


## Probes 8-point rings around Layer 1 colliders, snaps to navmesh, and scores !LoS + dist_sq.
static func probe_best_cover(
	agent_pos: Vector3,
	threat_pos: Vector3,
	collider_centers: Array[Vector3],
	space_state: PhysicsDirectSpaceState3D = null,
	nav_map: RID = RID(),
	exclude_rids: Array[RID] = []
) -> TacticalTypes.CoverProbeResult:
	var best: TacticalTypes.CoverProbeResult = TacticalTypes.CoverProbeResult.new()
	for center: Vector3 in collider_centers:
		var ring: Array[Vector3] = generate_cover_ring_points(center, COVER_RING_RADIUS)
		for candidate: Vector3 in ring:
			var snapped: Vector3 = candidate
			if nav_map.is_valid():
				snapped = NavigationServer3D.map_get_closest_point(nav_map, candidate)
			var breaks_los: bool = false
			if space_state != null:
				var eye_pos: Vector3 = snapped + Vector3(0.0, 1.0, 0.0)
				breaks_los = not raycast_has_los(
					space_state, eye_pos, threat_pos, TacticalTypes.MASK_ENV, exclude_rids
				)
			else:
				# Geometric fallback when no physics space is provided (e.g. unit tests)
				var to_threat: Vector3 = threat_pos - center
				var to_cand: Vector3 = snapped - center
				breaks_los = to_threat.dot(to_cand) < 0.0
			var dist_sq: float = agent_pos.distance_squared_to(snapped)
			var los_bonus: float = 1000.0 if breaks_los else 0.0
			var score: float = los_bonus - dist_sq
			if score > best.score:
				best.found = true
				best.position = snapped
				best.score = score
				best.breaks_los = breaks_los
				best.dist_sq = dist_sq
	return best


## Returns true if a raycast from [param from_pos] to [param to_pos] hits no occluders.
static func raycast_has_los(
	space_state: PhysicsDirectSpaceState3D,
	from_pos: Vector3,
	to_pos: Vector3,
	mask: int = TacticalTypes.MASK_LOS_BLOCKERS,
	exclude: Array[RID] = []
) -> bool:
	if space_state == null:
		return true
	var hit: Dictionary = Utilities.raycast_3d(space_state, from_pos, to_pos, mask, exclude)
	return hit.is_empty()


func _is_update_gated_in() -> bool:
	if is_instance_valid(visibility_notifier) and visibility_notifier.is_on_screen():
		return true
	var max_dist_sq: float = max_aggro_distance * max_aggro_distance
	return get_agent_position().distance_squared_to(last_known_target_pos) <= max_dist_sq


func _pick_available_link(climb_links: Array[NavigationLink3D]) -> NavigationLink3D:
	for link: NavigationLink3D in climb_links:
		if is_instance_valid(link) and link.enabled and is_smart_object_available(link):
			return link
	return null
