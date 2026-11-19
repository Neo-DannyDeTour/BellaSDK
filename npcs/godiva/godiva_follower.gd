## Player-following NPC extending [NpcActor] with [NavigationAgent3D] and obstacle traversal.
class_name GodivaFollower
extends NpcActor

## Emitted when follow mode starts or stops.
signal follow_state_changed(following: bool)

## Emitted when a [NavigationLink3D] traversal begins.
signal traversal_started(traversal_type: StringName)

## Emitted when a [NavigationLink3D] traversal completes.
signal traversal_finished(traversal_type: StringName)

## Emitted when doorway or narrow-corridor yield state starts or ends.
signal doorway_yield_changed(yielding: bool)

## Locomotion posture governing collision capsule height and stance animations.
enum Stance {
	STAND,
	CROUCH,
	PRONE,
}

## Interval in seconds between player navmesh target projection updates.
const REPATH_INTERVAL_SEC: float = 0.25
## Default standing and crouched capsule radius in meters.
const DEFAULT_CAPSULE_RADIUS: float = 0.24
## Reduced capsule radius in meters when prone so height 0.42m clears 0.50m tunnels.
const PRONE_CAPSULE_RADIUS: float = 0.20
## Standing capsule height in meters matching player scale.
const STAND_CAPSULE_HEIGHT: float = 1.64
## Crouched capsule height in meters for low window traversal.
const CROUCH_CAPSULE_HEIGHT: float = 1.05
## Prone capsule height in meters for low tunnel crawl traversal.
const PRONE_CAPSULE_HEIGHT: float = 0.42
## Duration in seconds for smooth capsule height transitions.
const STANCE_TRANSITION_TIME: float = 0.18
## Interval in seconds between overhead clearance queries while crouched or prone.
const HEADROOM_CHECK_INTERVAL: float = 0.15
## Maximum seconds allowed for a non-tween crouch/prone link crossing before forcing completion.
const STANCE_LINK_TIMEOUT_SEC: float = 5.0
## Horizontal distance squared (0.25m^2) considered arrived at crouch/prone link exit.
const LINK_EXIT_REACHED_SQ: float = 0.0625
## Maximum distance squared (1.5m^2) between player and navmesh before treating as unreachable.
const UNREACHABLE_PLAYER_DIST_SQ: float = 2.25
## Arrival threshold in meters when walking to closest reachable navmesh point.
const UNREACHABLE_STOP_DIST: float = 0.5
## Desired distance on [NavigationAgent3D] so pathing crosses links before stopping.
const REACHABLE_TARGET_DESIRED_DIST: float = 0.4
## Maximum vertical gap in meters treated as the same floor when evaluating stop_distance.
const SAME_LEVEL_MAX_VERT_GAP: float = 0.45
## Smooth root yaw interpolation speed in radians per second while navigating.
const MOVE_TURN_SPEED: float = 10.0
## Player group identifier used for target discovery.
const GROUP_PLAYER: StringName = &"player"
## Group identifier for doorway and narrow-corridor chokepoint [Area3D] sensors.
const GROUP_CHOKEPOINT: StringName = &"chokepoint"
## Metadata key on [NavigationLink3D] specifying traversal type.
const META_TRAVERSAL_TYPE: StringName = &"traversal_type"
## Optional metadata key on [NavigationLink3D] overriding downward traversal type.
const META_TRAVERSAL_TYPE_DOWN: StringName = &"traversal_type_down"
## Optional metadata key on [NavigationLink3D] pointing to an [InteractiveShelf] node.
const META_SHELF_NODE_PATH: StringName = &"shelf_node_path"

## Traversal identifier for low step-ups (<= 1.1m).
const TRAVERSAL_STEP_UP: StringName = &"step_up"
## Traversal identifier for mid-height climbs (1.1m - 1.8m).
const TRAVERSAL_CLIMB_MID: StringName = &"climb_mid"
## Traversal identifier for high pull-ups (> 1.8m).
const TRAVERSAL_PULL_UP_HIGH: StringName = &"pull_up_high"
## Traversal identifier for crouched obstacle crossings.
const TRAVERSAL_CROUCH_WALK: StringName = &"crouch_walk"
## Traversal identifier for prone tunnel crawls.
const TRAVERSAL_PRONE_CRAWL: StringName = &"prone_crawl"
## Traversal identifier for ledge drop-downs.
const TRAVERSAL_DROP_DOWN: StringName = &"drop_down"
## Traversal identifier for contextual warehouse shelf interaction links.
const TRAVERSAL_SHELF_INTERACT: StringName = &"shelf_interact"
## Traversal identifier for crawling through the lower shelf opening.
const TRAVERSAL_SHELF_CRAWL: StringName = &"shelf_crawl_through"
## Traversal identifier for climbing over a 2.2m warehouse shelf.
const TRAVERSAL_SHELF_CLIMB: StringName = &"shelf_climb_over"
## Traversal identifier for F.E.A.R.-style diving through the mid shelf opening.
const TRAVERSAL_SHELF_VAULT: StringName = &"shelf_vault_through"
## Traversal identifier for shoving a pushable shelf aside.
const TRAVERSAL_SHELF_PUSH: StringName = &"shelf_push_aside"
## Traversal identifier for toppling a pushable shelf onto the floor.
const TRAVERSAL_SHELF_TOPPLE: StringName = &"shelf_topple"

## Looping walk animation clip name.
const CLIP_WALK: StringName = &"walk"
## Looping run animation clip name.
const CLIP_RUN: StringName = &"run"
## Looping crouch idle animation clip name.
const CLIP_CROUCH_IDLE: StringName = &"crouch_idle"
## Looping crouch walk animation clip name.
const CLIP_CROUCH_WALK: StringName = &"crouch_walk"
## Looping prone idle animation clip name.
const CLIP_PRONE_IDLE: StringName = &"prone_idle"
## Looping prone crawl animation clip name.
const CLIP_PRONE_CRAWL: StringName = &"prone_crawl"
## Looping wall-hug idle animation clip played while yielding in a doorway.
const CLIP_WALL_HUG_IDLE: StringName = &"wall_hug_idle"
## Looping left sidestep animation clip played while yielding toward a left wall.
const CLIP_SIDESTEP_LEFT: StringName = &"sidestep_left"
## Looping right sidestep animation clip played while yielding toward a right wall.
const CLIP_SIDESTEP_RIGHT: StringName = &"sidestep_right"

## Interval in seconds between throttled chokepoint and narrow-corridor ray checks.
const CHOKEPOINT_CHECK_INTERVAL_SEC: float = 0.15
## Maximum combined lateral wall distance in meters treated as a narrow corridor.
const CHOKEPOINT_NARROW_WIDTH_M: float = 2.6
## Maximum lateral raycast length in meters for untagged narrow-corridor detection.
const CHOKEPOINT_RAY_RANGE_M: float = 2.6
## Squared player distance (3.5m^2) within which doorway yielding triggers.
const DOORWAY_YIELD_TRIGGER_DIST_SQ: float = 12.25
## Squared player distance (2.5m^2) required to end doorway yield after player passes.
const DOORWAY_YIELD_CLEAR_DIST_SQ: float = 6.25
## Maximum seconds Godiva holds doorway yield before resuming automatically.
const DOORWAY_YIELD_TIMEOUT_SEC: float = 4.0
## Cooldown seconds after ending doorway yield before re-triggering.
const DOORWAY_YIELD_COOLDOWN_SEC: float = 2.0
## Lateral sidestep speed in meters per second while clearing a doorway.
const DOORWAY_SIDESTEP_SPEED: float = 2.2
## Wall clearance margin in meters preserved when hugging a doorway wall.
const DOORWAY_WALL_MARGIN_M: float = 0.42
## Default off-center sidestep distance in meters when no lateral wall ray hits.
const DOORWAY_DEFAULT_SIDESTEP_M: float = 0.75
## Squared planar distance (0.15m^2) considered arrived at the wall-hug offset.
const DOORWAY_SIDESTEP_ARRIVED_SQ: float = 0.0225
## Vertical height in meters of a standard warehouse shelf top surface.
const SHELF_TOP_HEIGHT_M: float = 2.2
## Minimum overhead clearance in meters above shelf top needed for climbing over.
const SHELF_CLIMB_HEADROOM_M: float = 1.5
## Forward clearance in meters past shelf midpoint needed to topple instead of push.
const SHELF_TOPPLE_CLEARANCE_M: float = 2.6
## Exit offset in meters past shelf center when triggering traversal from slide collision.
const SHELF_COLLISION_EXIT_OFFSET_M: float = 1.35
## Cooldown seconds after a shelf traversal preventing immediate slide-collision re-trigger.
const SHELF_COLLISION_COOLDOWN_SEC: float = 0.6
## Planar acceleration rate in m/s^2 for smooth idle-walk-run velocity damping.
const LOCOMOTION_ACCEL: float = 12.0
## Stand-off distance in meters from a probed wall face to align flush without clipping.
const WALL_FLUSH_OFFSET_M: float = 0.30
## Lateral half-width in meters between left and right hand IK surface contact targets.
const HAND_IK_HALF_WIDTH_M: float = 0.24
## Default HandIK influence weight during climbs, vaults, shelf pushes, and wall hugs.
const HAND_IK_WEIGHT: float = 0.85
## Exact top deck height offset in meters for climbing over [InteractiveShelf].
const SHELF_DECK_CLIMB_Y: float = 1.975
## Exact middle deck height offset in meters for vaulting through or pushing [InteractiveShelf].
const SHELF_DECK_VAULT_Y: float = 1.175
## Exact lower deck height offset in meters for crawling under [InteractiveShelf].
const SHELF_DECK_CRAWL_Y: float = 0.295

## Anchor dictionary key indicating whether a front wall face was hit by the probe ray.
const ANCHOR_HAS_WALL: StringName = &"has_wall"
## Anchor dictionary key for the world-space wall contact hit position.
const ANCHOR_WALL_POS: StringName = &"wall_pos"
## Anchor dictionary key for the planar unit wall normal pointing back toward entry.
const ANCHOR_WALL_NORMAL: StringName = &"wall_normal"
## Anchor dictionary key for the probed ledge or shelf deck top Y coordinate.
const ANCHOR_LEDGE_Y: StringName = &"ledge_y"
## Anchor dictionary key for the probed landing floor Y coordinate at exit XZ.
const ANCHOR_FLOOR_Y: StringName = &"floor_y"
## Anchor dictionary key for the probed left-hand world IK target.
const ANCHOR_LEFT_HAND: StringName = &"left_hand"
## Anchor dictionary key for the probed right-hand world IK target.
const ANCHOR_RIGHT_HAND: StringName = &"right_hand"

## Scene references for navigation and capsule resizing.
@export_group("Follow Navigation")
## Child [NavigationAgent3D] computing paths toward the player.
@export var nav_agent: NavigationAgent3D = null
## Child [CollisionShape3D] holding the resizable [CapsuleShape3D].
@export var collision_shape: CollisionShape3D = null
## Optional [GodivaIKController] driving native [TwoBoneIK3D] foot and hand contact.
@export var ik_controller: GodivaIKController = null
## Distance in meters from reachable player at which follower stops in idle.
@export_range(0.5, 5.0, 0.1) var stop_distance: float = 2.0
## Distance threshold in meters switching from walk to run.
@export_range(2.0, 15.0, 0.5) var run_distance: float = 6.0
## Horizontal movement speed in meters per second while walking.
@export_range(0.5, 4.0, 0.1) var walk_speed: float = 1.5
## Horizontal movement speed in meters per second while running.
@export_range(1.5, 8.0, 0.1) var run_speed: float = 4.0
## Horizontal movement speed in meters per second while crouched.
@export_range(0.5, 3.0, 0.1) var crouch_speed: float = 1.2
## Horizontal movement speed in meters per second while prone.
@export_range(0.3, 2.0, 0.1) var prone_speed: float = 0.75
## Begins following the player automatically on [method _ready] when enabled.
@export var auto_start_following: bool = false
## Optional deterministic override forcing a specific shelf traversal mode during tests.
@export var shelf_mode_override: StringName = &""

## Active follow mode flag.
var _is_following: bool = false
## Cached player node discovered in [constant GROUP_PLAYER].
var _player_node: Node3D = null
## Repeating 0.25s timer projecting player position onto the navigation map.
var _repath_timer: Timer = null
## Per-instance duplicated [CapsuleShape3D] safely mutated across stances.
var _capsule_shape: CapsuleShape3D = null
## Current physical posture governing capsule dimensions and stance clips.
var _current_stance: Stance = Stance.STAND
## True when player is above or off the navmesh (> 1.5m from closest map point).
var _player_unreachable: bool = false
## True while actively crossing a [NavigationLink3D].
var _is_traversing_link: bool = false
## True while a multi-phase climb/drop [Tween] owns position and disables gravity.
var _is_tween_traversal: bool = false
## Active traversal identifier during a [NavigationLink3D] crossing.
var _active_link_traversal: StringName = &""
## World-space exit coordinate for the active [NavigationLink3D].
var _link_exit_pos: Vector3 = Vector3.ZERO
## Elapsed seconds spent inside an active crouch/prone link crossing.
var _stance_link_elapsed: float = 0.0
## Active [Tween] driving multi-phase climb/drop link movement.
var _link_tween: Tween = null
## Active [Tween] smoothly interpolating [CapsuleShape3D] dimensions.
var _stance_tween: Tween = null
## Accumulated seconds between periodic overhead clearance queries.
var _headroom_accum: float = 0.0
## Preserved inspector value of [member NpcActor.turn_body_when_behind].
var _base_turn_body_when_behind: bool = true
## Cached physics query parameters for zero-allocation headroom checks.
var _headroom_query: PhysicsShapeQueryParameters3D = null
## Cached cylinder shape used for overhead clearance queries.
var _headroom_shape: CylinderShape3D = null
## Cached world gravity magnitude read from project settings.
var _gravity: float = 9.8
## True while Godiva is sidestepping or hugging a wall to yield a doorway to the player.
var _is_yielding_doorway: bool = false
## Elapsed seconds spent in the active doorway yield state.
var _doorway_yield_elapsed: float = 0.0
## Remaining cooldown seconds preventing immediate doorway yield re-trigger after resume.
var _doorway_yield_cooldown: float = 0.0
## Accumulated seconds between throttled chokepoint and narrow-corridor queries.
var _chokepoint_check_accum: float = CHOKEPOINT_CHECK_INTERVAL_SEC
## True when the most recent throttled query placed Godiva in a chokepoint or narrow corridor.
var _in_chokepoint: bool = false
## Cached planar unit vector pointing toward the nearest wall in the active chokepoint.
var _chokepoint_wall_dir: Vector3 = Vector3.ZERO
## Cached distance in meters to the nearest wall in the active chokepoint.
var _chokepoint_wall_dist: float = 0.0
## World-space wall-hug offset position targeted during doorway yield.
var _yield_target_pos: Vector3 = Vector3.ZERO
## Lateral sidestep animation clip chosen for the active doorway yield direction.
var _yield_sidestep_clip: StringName = CLIP_SIDESTEP_RIGHT
## Minimum squared player distance observed during the current doorway yield.
var _yield_min_player_dist_sq: float = INF
## Previous frame squared player distance for zero-allocation approach detection.
var _prev_player_dist_sq: float = -1.0
## Cached ray query reused for zero-allocation lateral corridor and shelf checks.
var _cached_ray_query: PhysicsRayQueryParameters3D = null
## Reusable exclusion [RID] list for cached physics ray queries.
var _ray_exclude: Array[RID] = []
## Remaining cooldown seconds preventing immediate shelf collision traversal re-trigger.
var _shelf_collision_cooldown_sec: float = 0.0
## Smoothed horizontal locomotion speed in m/s fed into parametric [AnimationNodeBlendSpace1D].
var _current_planar_speed: float = 0.0
## Cached ray query reused for zero-allocation pre-traversal motion warping probes.
var _warp_ray_query: PhysicsRayQueryParameters3D = null
## Reusable exclusion [RID] list for motion warping ray queries.
var _warp_ray_exclude: Array[RID] = []


## Initializes [NpcActor], [NavigationAgent3D], duplicated capsule shape, and 0.25s repath timer.
func _ready() -> void:
	super._ready()
	_base_turn_body_when_behind = turn_body_when_behind
	var raw_grav: Variant = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	if raw_grav is float:
		_gravity = raw_grav
	elif raw_grav is int:
		_gravity = float(raw_grav)

	if not is_instance_valid(nav_agent):
		nav_agent = get_node_or_null(^"NavigationAgent3D") as NavigationAgent3D
	if not is_instance_valid(nav_agent):
		nav_agent = NodeQuery.find_first_child_of_type(self, NavigationAgent3D) as NavigationAgent3D
	assert(is_instance_valid(nav_agent), "GodivaFollower requires a NavigationAgent3D child.")

	nav_agent.radius = DEFAULT_CAPSULE_RADIUS
	nav_agent.height = STAND_CAPSULE_HEIGHT
	nav_agent.target_desired_distance = REACHABLE_TARGET_DESIRED_DIST

	if not is_instance_valid(collision_shape):
		collision_shape = get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	assert(is_instance_valid(collision_shape), "GodivaFollower requires CollisionShape3D.")
	assert(
		collision_shape.shape is CapsuleShape3D,
		"GodivaFollower CollisionShape3D must use CapsuleShape3D."
	)
	_capsule_shape = collision_shape.shape.duplicate() as CapsuleShape3D
	collision_shape.shape = _capsule_shape
	_apply_stance(Stance.STAND, true)

	if not is_instance_valid(ik_controller):
		ik_controller = get_node_or_null(^"GodivaIKController") as GodivaIKController
	if is_instance_valid(ik_controller):
		ik_controller.initialize(get_skeleton(), self, model_root)

	_repath_timer = Timer.new()
	_repath_timer.name = "FollowRepathTimer"
	_repath_timer.wait_time = REPATH_INTERVAL_SEC
	_repath_timer.one_shot = false
	_repath_timer.autostart = false
	add_child(_repath_timer)
	Utilities.safe_connect(_repath_timer.timeout, _on_repath_timer_timeout)
	Utilities.safe_connect(nav_agent.link_reached, _on_nav_link_reached)

	if auto_start_following:
		start_following()


## Cleans up active tweens and signal connections when leaving the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_link_tween)
	Utilities.safe_kill_tween(_stance_tween)
	super._exit_tree()


## Drives navigation locomotion, link traversal, gravity, and headroom stance recovery.
func _physics_process(delta: float) -> void:
	if _is_traversing_link and _is_tween_traversal:
		return

	if not _is_following:
		_process_idle_settling(delta)
		return

	if _shelf_collision_cooldown_sec > 0.0:
		_shelf_collision_cooldown_sec = maxf(0.0, _shelf_collision_cooldown_sec - delta)

	if _is_traversing_link:
		_process_stance_link(delta)
		return

	if _current_stance != Stance.STAND:
		_headroom_accum += delta
		if _headroom_accum >= HEADROOM_CHECK_INTERVAL:
			_headroom_accum = 0.0
			_try_recover_standing_stance()

	_apply_vertical_gravity(delta)

	if _is_yielding_doorway:
		_process_doorway_yield(delta)
		return

	_update_chokepoint_yield_trigger(delta)
	if _is_yielding_doorway:
		_process_doorway_yield(delta)
		return

	if _should_stop_following():
		_stop_motion_in_stance_idle()
		move_and_slide()
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	if _is_traversing_link:
		return

	var planar: Vector3 = next_pos - global_position
	planar.y = 0.0
	if planar.length_squared() < MIN_PLANAR_DIST_SQ:
		planar = nav_agent.target_position - global_position
		planar.y = 0.0
	if planar.length_squared() < MIN_PLANAR_DIST_SQ:
		_stop_motion_in_stance_idle()
		move_and_slide()
		return

	var dir: Vector3 = planar.normalized()
	var move_speed: float = _select_move_speed()
	var move_clip: StringName = _select_move_clip()
	_current_planar_speed = move_toward(_current_planar_speed, move_speed, LOCOMOTION_ACCEL * delta)
	velocity.x = dir.x * _current_planar_speed
	velocity.z = dir.z * _current_planar_speed
	_rotate_toward_direction(dir, delta)
	if _current_stance == Stance.STAND and has_locomotion_blend_space():
		turn_body_when_behind = false
		_is_scripted_clip_active = false
		set_locomotion_blend(_current_planar_speed / maxf(run_speed, 0.01))
	else:
		_set_locomotion_state(true, move_clip)
	move_and_slide()
	_try_trigger_shelf_from_slide_collisions()


## Enables player following, starts the 0.25s repath timer, and enables physics updates.
func start_following(_param: String = "") -> void:
	var was_following: bool = _is_following
	_is_following = true
	_resolve_player_node()
	if is_instance_valid(_repath_timer) and _repath_timer.is_stopped():
		_repath_timer.start()
	_update_follow_target()
	set_physics_process(true)
	if not was_following:
		follow_state_changed.emit(true)
	print("GodivaFollower: ", name, " -> start_following")


## Disables player following, stops repathing, settles stance safely, and idles processing.
func stop_following(_param: String = "") -> void:
	var was_following: bool = _is_following
	_is_following = false
	if is_instance_valid(_repath_timer) and not _repath_timer.is_stopped():
		_repath_timer.stop()

	if _is_traversing_link:
		Utilities.safe_kill_tween(_link_tween)
		_is_traversing_link = false
		_is_tween_traversal = false
		_active_link_traversal = &""

	if _is_yielding_doorway:
		_end_doorway_yield()
	_doorway_yield_cooldown = 0.0
	_shelf_collision_cooldown_sec = 0.0
	_in_chokepoint = false
	_prev_player_dist_sq = -1.0

	velocity.x = 0.0
	velocity.z = 0.0
	_current_planar_speed = 0.0
	if is_instance_valid(ik_controller):
		ik_controller.clear_hand_targets()
		ik_controller.set_foot_ik_suppressed(_current_stance == Stance.PRONE)
	_try_recover_standing_stance()
	_set_locomotion_state(false, _get_stance_idle_clip())

	if is_on_floor():
		velocity = Vector3.ZERO
		set_physics_process(false)
	else:
		set_physics_process(true)

	if was_following:
		follow_state_changed.emit(false)
	print("GodivaFollower: ", name, " -> stop_following")


## Returns true while actively following the player.
func is_following() -> bool:
	return _is_following


## Returns the active physical [enum Stance] governing capsule height.
func get_current_stance() -> Stance:
	return _current_stance


## Returns true while Godiva is yielding a doorway or narrow corridor to the player.
func is_yielding_doorway() -> bool:
	return _is_yielding_doorway


## Resolves link traversal type from [NavigationLink3D] metadata with vertical delta fallback.
func resolve_traversal_type(link_obj: Object, entry_pos: Vector3, exit_pos: Vector3) -> StringName:
	var dy: float = exit_pos.y - entry_pos.y
	var meta_type: StringName = _read_link_meta_name(link_obj, META_TRAVERSAL_TYPE)

	if (
		meta_type == TRAVERSAL_CROUCH_WALK
		or meta_type == TRAVERSAL_PRONE_CRAWL
		or meta_type == TRAVERSAL_SHELF_INTERACT
		or _is_shelf_mode(meta_type)
	):
		return meta_type

	if (
		meta_type == TRAVERSAL_STEP_UP
		or meta_type == TRAVERSAL_CLIMB_MID
		or meta_type == TRAVERSAL_PULL_UP_HIGH
	):
		if dy < -0.35:
			var down_meta: StringName = _read_link_meta_name(link_obj, META_TRAVERSAL_TYPE_DOWN)
			return down_meta if not down_meta.is_empty() else TRAVERSAL_DROP_DOWN
		return meta_type

	if meta_type == TRAVERSAL_DROP_DOWN:
		if dy > 0.35:
			return _fallback_traversal_by_delta(dy)
		return TRAVERSAL_DROP_DOWN

	return _fallback_traversal_by_delta(dy)


## Selects the contextual warehouse shelf traversal or manipulation mode for [param shelf].
func select_shelf_traversal(shelf: Node, entry_pos: Vector3, exit_pos: Vector3) -> StringName:
	var interactive_shelf: InteractiveShelf = shelf as InteractiveShelf
	if is_instance_valid(interactive_shelf) and interactive_shelf.is_cleared():
		return &""

	if not shelf_mode_override.is_empty():
		return shelf_mode_override

	var ref_pos: Vector3 = _get_distance_reference_pos()
	var dist_sq: float = global_position.distance_squared_to(ref_pos)
	var run_dist_sq: float = run_distance * run_distance

	if dist_sq >= run_dist_sq:
		var urgent_dist: float = run_distance * 1.5
		if (
			is_instance_valid(interactive_shelf)
			and interactive_shelf.can_manipulate()
			and dist_sq >= urgent_dist * urgent_dist
		):
			if _is_shelf_topple_cramped(interactive_shelf, entry_pos, exit_pos):
				return TRAVERSAL_SHELF_PUSH
			return TRAVERSAL_SHELF_TOPPLE
		return TRAVERSAL_SHELF_VAULT

	if _current_stance != Stance.STAND or not _has_shelf_top_clearance(shelf, entry_pos, exit_pos):
		return TRAVERSAL_SHELF_CRAWL
	return TRAVERSAL_SHELF_CLIMB


## Checks whether standing clearance above the current capsule is unobstructed.
func has_stand_headroom() -> bool:
	return _has_clearance_for_height(STAND_CAPSULE_HEIGHT)


## Checks whether crouched clearance above the current capsule is unobstructed.
func has_crouch_headroom() -> bool:
	return _has_clearance_for_height(CROUCH_CAPSULE_HEIGHT)


## Updates [member NavigationAgent3D.target_position] from projected player coordinates.
func _update_follow_target() -> void:
	var player: Node3D = _resolve_player_node()
	if not is_instance_valid(player) or not is_instance_valid(nav_agent):
		return

	var player_pos: Vector3 = player.global_position
	var nav_map: RID = nav_agent.get_navigation_map()
	var projected: Vector3 = Vector3.ZERO
	var has_navmesh: bool = false
	if (
		nav_map.is_valid()
		and NavigationServer3D.map_get_iteration_id(nav_map) > 0
		and not NavigationServer3D.map_get_regions(nav_map).is_empty()
	):
		var point_owner: RID = NavigationServer3D.map_get_closest_point_owner(nav_map, player_pos)
		if point_owner.is_valid():
			projected = NavigationServer3D.map_get_closest_point(nav_map, player_pos)
			has_navmesh = true

	if has_navmesh:
		_player_unreachable = player_pos.distance_squared_to(projected) > UNREACHABLE_PLAYER_DIST_SQ
		nav_agent.target_desired_distance = (
			UNREACHABLE_STOP_DIST if _player_unreachable else REACHABLE_TARGET_DESIRED_DIST
		)
		nav_agent.target_position = projected
	else:
		_player_unreachable = false
		nav_agent.target_desired_distance = REACHABLE_TARGET_DESIRED_DIST
		nav_agent.target_position = player_pos


## Locates and caches the active player node via [constant GROUP_PLAYER].
func _resolve_player_node() -> Node3D:
	if is_instance_valid(_player_node) and _player_node.is_inside_tree():
		return _player_node
	if not is_inside_tree():
		return null
	var candidate: Node = NodeQuery.get_single_node_in_group(get_tree(), GROUP_PLAYER)
	if candidate is Node3D:
		_player_node = candidate as Node3D
		return _player_node
	return null


## Applies gravity while airborne after [method stop_following] until grounded, then sleeps.
func _process_idle_settling(delta: float) -> void:
	if is_on_floor():
		velocity = Vector3.ZERO
		set_physics_process(false)
		return
	_apply_vertical_gravity(delta)
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()


## Moves Godiva across a crouched or prone [NavigationLink3D] using [method move_and_slide].
func _process_stance_link(delta: float) -> void:
	_stance_link_elapsed += delta
	_apply_vertical_gravity(delta)

	var to_exit: Vector3 = _link_exit_pos - global_position
	to_exit.y = 0.0
	if (
		to_exit.length_squared() <= LINK_EXIT_REACHED_SQ
		or _stance_link_elapsed >= STANCE_LINK_TIMEOUT_SEC
	):
		_finish_stance_link()
		return

	var dir: Vector3 = to_exit.normalized()
	var speed: float = prone_speed if _current_stance == Stance.PRONE else crouch_speed
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_rotate_toward_direction(dir, delta)
	var clip: StringName = CLIP_PRONE_CRAWL if _current_stance == Stance.PRONE else CLIP_CROUCH_WALK
	_set_locomotion_state(true, clip)
	move_and_slide()


## Ends a crouch/prone link crossing and recovers standing height only when headroom permits.
func _finish_stance_link() -> void:
	var finished_type: StringName = _active_link_traversal
	_is_traversing_link = false
	_active_link_traversal = &""
	_stance_link_elapsed = 0.0
	_try_recover_standing_stance()
	traversal_finished.emit(finished_type)
	print("GodivaFollower: ", name, " finished link -> ", finished_type)


## Evaluates whether Godiva has reached the player or closest reachable navmesh endpoint.
func _should_stop_following() -> bool:
	if not is_instance_valid(_player_node):
		return true

	if _player_unreachable:
		if nav_agent.is_navigation_finished():
			return true
		var dist_proj_sq: float = global_position.distance_squared_to(nav_agent.target_position)
		return dist_proj_sq <= UNREACHABLE_STOP_DIST * UNREACHABLE_STOP_DIST

	var vert_gap: float = absf(global_position.y - _player_node.global_position.y)
	if vert_gap <= SAME_LEVEL_MAX_VERT_GAP:
		var dist_player_sq: float = global_position.distance_squared_to(
			_player_node.global_position
		)
		if dist_player_sq <= stop_distance * stop_distance:
			return nav_agent.distance_to_target() <= stop_distance + 0.5
	return nav_agent.is_navigation_finished()


## Halts horizontal velocity and switches to the current stance idle clip.
func _stop_motion_in_stance_idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_current_planar_speed = 0.0
	_set_locomotion_state(false, _get_stance_idle_clip())


## Selects horizontal speed from active [enum Stance] and player distance.
func _select_move_speed() -> float:
	if _current_stance == Stance.PRONE:
		return prone_speed
	if _current_stance == Stance.CROUCH:
		return crouch_speed
	var dist_sq: float = global_position.distance_squared_to(_get_distance_reference_pos())
	if dist_sq >= run_distance * run_distance:
		return run_speed
	return walk_speed


## Selects locomotion animation clip from active [enum Stance] and player distance.
func _select_move_clip() -> StringName:
	if _current_stance == Stance.PRONE:
		return CLIP_PRONE_CRAWL
	if _current_stance == Stance.CROUCH:
		return CLIP_CROUCH_WALK
	var dist_sq: float = global_position.distance_squared_to(_get_distance_reference_pos())
	if dist_sq >= run_distance * run_distance:
		return CLIP_RUN
	return CLIP_WALK


## Returns the world reference position used to choose walk vs run speed.
func _get_distance_reference_pos() -> Vector3:
	if _player_unreachable or not is_instance_valid(_player_node):
		return nav_agent.target_position
	return _player_node.global_position


## Applies vertical gravity when not grounded.
func _apply_vertical_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


## Smoothly rotates character root yaw to face planar [param dir].
func _rotate_toward_direction(dir: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-dir.x, -dir.z)
	var yaw_diff: float = angle_difference(global_rotation.y, target_yaw)
	var alpha: float = 1.0 - exp(-MOVE_TURN_SPEED * delta)
	global_rotation.y = global_rotation.y + yaw_diff * alpha


## Coordinates moving vs idle state, body-turn suppression, and clip transitions.
func _set_locomotion_state(moving: bool, desired_clip: StringName) -> void:
	if moving:
		turn_body_when_behind = false
	else:
		turn_body_when_behind = _base_turn_body_when_behind

	if _current_clip == desired_clip:
		return
	if _registered_clips.has(desired_clip):
		play_animation(String(desired_clip))
	elif _registered_clips.has(default_animation) and _current_clip != default_animation:
		play_animation(String(default_animation))


## Returns the idle animation matching the active [enum Stance].
func _get_stance_idle_clip() -> StringName:
	if _current_stance == Stance.PRONE and _registered_clips.has(CLIP_PRONE_IDLE):
		return CLIP_PRONE_IDLE
	if _current_stance == Stance.CROUCH and _registered_clips.has(CLIP_CROUCH_IDLE):
		return CLIP_CROUCH_IDLE
	return default_animation


## Steps up from prone/crouch toward standing only when overhead clearance is verified.
func _try_recover_standing_stance() -> void:
	if _current_stance == Stance.STAND:
		return
	if has_stand_headroom():
		_apply_stance(Stance.STAND, false)
	elif _current_stance == Stance.PRONE and has_crouch_headroom():
		_apply_stance(Stance.CROUCH, false)


## Smoothly transitions [member _capsule_shape] height, radius, and offset for [param new_stance].
func _apply_stance(new_stance: Stance, immediate: bool) -> void:
	var target_height: float = STAND_CAPSULE_HEIGHT
	var target_radius: float = DEFAULT_CAPSULE_RADIUS
	if new_stance == Stance.CROUCH:
		target_height = CROUCH_CAPSULE_HEIGHT
	elif new_stance == Stance.PRONE:
		target_height = PRONE_CAPSULE_HEIGHT
		target_radius = PRONE_CAPSULE_RADIUS

	var changed: bool = _current_stance != new_stance
	_current_stance = new_stance
	if is_instance_valid(ik_controller):
		ik_controller.set_foot_ik_suppressed(new_stance == Stance.PRONE or _is_tween_traversal)

	if not is_instance_valid(_capsule_shape) or not is_instance_valid(collision_shape):
		return

	if immediate or not is_inside_tree():
		Utilities.safe_kill_tween(_stance_tween)
		if target_radius < _capsule_shape.radius:
			_capsule_shape.radius = target_radius
			_capsule_shape.height = target_height
		else:
			_capsule_shape.height = target_height
			_capsule_shape.radius = target_radius
		collision_shape.position.y = target_height * 0.5
		if changed:
			print("GodivaFollower: ", name, " stance -> ", Stance.keys()[new_stance])
		return

	# Shrink radius before height drops below 2*radius to keep CapsuleShape3D valid every frame.
	if target_radius < _capsule_shape.radius:
		_capsule_shape.radius = target_radius

	var tw: Tween = Utilities.reset_tween(self, _stance_tween)
	_stance_tween = tw
	if is_instance_valid(tw):
		tw.set_parallel(true)
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(_capsule_shape, "height", target_height, STANCE_TRANSITION_TIME)
		tw.tween_property(
			collision_shape, "position:y", target_height * 0.5, STANCE_TRANSITION_TIME
		)
		if target_radius > _capsule_shape.radius:
			tw.tween_property(_capsule_shape, "radius", target_radius, STANCE_TRANSITION_TIME)

	if changed:
		print("GodivaFollower: ", name, " stance -> ", Stance.keys()[new_stance])


## Tests vertical clearance above current capsule height using cached physics query objects.
func _has_clearance_for_height(target_height: float) -> bool:
	if not is_inside_tree():
		return true
	var current_h: float = _capsule_shape.height if is_instance_valid(_capsule_shape) else 0.0
	if target_height <= current_h + 0.02:
		return true
	var check_h: float = target_height - current_h - 0.04
	if check_h <= 0.02:
		return true

	var world_3d: World3D = get_world_3d()
	if not is_instance_valid(world_3d):
		return true
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if not is_instance_valid(space):
		return true

	if not is_instance_valid(_headroom_shape):
		_headroom_shape = CylinderShape3D.new()
		_headroom_shape.radius = 0.21
	if not is_instance_valid(_headroom_query):
		_headroom_query = PhysicsShapeQueryParameters3D.new()
		_headroom_query.collision_mask = CollisionLayers.MASK_SOLID_WORLD
		_headroom_query.collide_with_bodies = true
		_headroom_query.collide_with_areas = false

	_headroom_shape.height = check_h
	_headroom_query.shape = _headroom_shape
	_headroom_query.exclude = [get_rid()]
	var center_y: float = current_h + 0.04 + (check_h * 0.5)
	_headroom_query.transform = Transform3D(
		Basis.IDENTITY, global_position + Vector3(0.0, center_y, 0.0)
	)
	var hits: Array[Dictionary] = space.intersect_shape(_headroom_query, 1)
	return hits.is_empty()


## Starts a multi-phase [Tween] for climb, drop, or shelf links synced to clip length.
func _start_tween_traversal(
	traversal_type: StringName,
	entry_pos: Vector3,
	exit_pos: Vector3,
	shelf_node: Node = null,
) -> void:
	_is_traversing_link = true
	_is_tween_traversal = true
	_active_link_traversal = traversal_type
	_current_planar_speed = 0.0
	if traversal_type == TRAVERSAL_SHELF_CRAWL or traversal_type == TRAVERSAL_SHELF_VAULT:
		_apply_stance(Stance.PRONE, false)
	else:
		_apply_stance(Stance.STAND, false)
	if is_instance_valid(ik_controller):
		ik_controller.set_foot_ik_suppressed(true)

	var anchors: Dictionary[StringName, Variant] = _probe_traversal_anchors(
		traversal_type, entry_pos, exit_pos, shelf_node
	)
	var raw_floor_y: Variant = anchors.get(ANCHOR_FLOOR_Y, exit_pos.y)
	var floor_y: float = raw_floor_y if raw_floor_y is float else exit_pos.y
	var warped_exit: Vector3 = Vector3(exit_pos.x, floor_y, exit_pos.z)

	_link_exit_pos = warped_exit
	velocity = Vector3.ZERO
	turn_body_when_behind = false

	var raw_has_wall: Variant = anchors.get(ANCHOR_HAS_WALL, false)
	var has_wall: bool = raw_has_wall if raw_has_wall is bool else false
	var raw_wall_normal: Variant = anchors.get(ANCHOR_WALL_NORMAL, Vector3.ZERO)
	var wall_normal: Vector3 = raw_wall_normal if raw_wall_normal is Vector3 else Vector3.ZERO

	var planar: Vector3 = warped_exit - entry_pos
	planar.y = 0.0
	if (
		has_wall
		and traversal_type != TRAVERSAL_DROP_DOWN
		and wall_normal.length_squared() >= MIN_PLANAR_DIST_SQ
	):
		global_rotation.y = atan2(wall_normal.x, wall_normal.z)
	elif planar.length_squared() >= MIN_PLANAR_DIST_SQ:
		global_rotation.y = atan2(-planar.x, -planar.z)

	if is_instance_valid(ik_controller) and _traversal_uses_hand_ik(traversal_type):
		var raw_left: Variant = anchors.get(ANCHOR_LEFT_HAND, Vector3.ZERO)
		var raw_right: Variant = anchors.get(ANCHOR_RIGHT_HAND, Vector3.ZERO)
		if raw_left is Vector3 and raw_right is Vector3:
			ik_controller.set_hand_targets(raw_left, raw_right, HAND_IK_WEIGHT)

	var fallback_sec: float = _get_default_traversal_duration(traversal_type)
	var clip_len: float = _get_clip_duration(traversal_type, fallback_sec)
	if _registered_clips.has(traversal_type):
		play_animation_once(String(traversal_type))

	var tw: Tween = Utilities.reset_tween(self, _link_tween)
	_link_tween = tw
	if not is_instance_valid(tw):
		_trigger_shelf_action(traversal_type, shelf_node, planar, 0.0)
		global_position = warped_exit
		_on_link_tween_finished(traversal_type)
		return

	var start_pos: Vector3 = global_position
	if _is_shelf_mode(traversal_type):
		_build_shelf_link_tween(
			tw, traversal_type, start_pos, warped_exit, clip_len, shelf_node, planar, anchors
		)
	else:
		_build_multiphase_link_tween(tw, traversal_type, start_pos, warped_exit, clip_len, anchors)
	tw.finished.connect(_on_link_tween_finished.bind(traversal_type), Object.CONNECT_ONE_SHOT)
	traversal_started.emit(traversal_type)
	print("GodivaFollower: ", name, " started link -> ", traversal_type, " dur=", clip_len)


## Probes wall face, ledge/shelf top, landing floor, and hand targets using cached raycasts.
func _probe_traversal_anchors(
	traversal_type: StringName,
	entry_pos: Vector3,
	exit_pos: Vector3,
	shelf_node: Node = null,
) -> Dictionary[StringName, Variant]:
	var planar: Vector3 = Vector3(exit_pos.x - entry_pos.x, 0.0, exit_pos.z - entry_pos.z)
	var dir: Vector3 = (
		planar.normalized()
		if planar.length_squared() >= MIN_PLANAR_DIST_SQ
		else -global_transform.basis.z.normalized()
	)
	var right_vec: Vector3 = dir.cross(Vector3.UP)
	right_vec = (
		right_vec.normalized()
		if right_vec.length_squared() >= MIN_PLANAR_DIST_SQ
		else Vector3.RIGHT
	)

	var has_wall: bool = false
	var wall_pos: Vector3 = entry_pos.lerp(exit_pos, 0.35)
	var wall_normal: Vector3 = -dir
	if traversal_type != TRAVERSAL_DROP_DOWN:
		var chest_y: float = entry_pos.y + 0.95
		var wall_from: Vector3 = Vector3(entry_pos.x, chest_y, entry_pos.z) - dir * 0.15
		var wall_to: Vector3 = Vector3(exit_pos.x, chest_y, exit_pos.z)
		var wall_hit: Dictionary = _cast_warp_ray(
			wall_from, wall_to, CollisionLayers.MASK_SOLID_WORLD, null
		)
		if not wall_hit.is_empty():
			var raw_wpos: Variant = wall_hit.get("position", wall_pos)
			var raw_wnorm: Variant = wall_hit.get("normal", wall_normal)
			if raw_wpos is Vector3:
				wall_pos = raw_wpos
				has_wall = true
			if raw_wnorm is Vector3:
				var flat_norm: Vector3 = Vector3(raw_wnorm.x, 0.0, raw_wnorm.z)
				if flat_norm.length_squared() >= MIN_PLANAR_DIST_SQ:
					wall_normal = flat_norm.normalized()

	var ledge_y: float = maxf(entry_pos.y, exit_pos.y)
	if _is_shelf_mode(traversal_type) and is_instance_valid(shelf_node) and shelf_node is Node3D:
		var shelf_y: float = (shelf_node as Node3D).global_position.y
		if traversal_type == TRAVERSAL_SHELF_CLIMB:
			ledge_y = shelf_y + SHELF_DECK_CLIMB_Y
		elif traversal_type == TRAVERSAL_SHELF_CRAWL:
			ledge_y = shelf_y + SHELF_DECK_CRAWL_Y
		else:
			ledge_y = shelf_y + SHELF_DECK_VAULT_Y
	elif traversal_type != TRAVERSAL_DROP_DOWN:
		var lip_xz: Vector3 = (
			wall_pos - wall_normal * 0.20 if has_wall else entry_pos.lerp(exit_pos, 0.65)
		)
		var lip_from: Vector3 = Vector3(lip_xz.x, maxf(entry_pos.y, exit_pos.y) + 1.0, lip_xz.z)
		var lip_to: Vector3 = Vector3(lip_xz.x, minf(entry_pos.y, exit_pos.y) - 0.5, lip_xz.z)
		var lip_hit: Dictionary = _cast_warp_ray(
			lip_from, lip_to, CollisionLayers.MASK_SOLID_WORLD, null
		)
		if not lip_hit.is_empty():
			var raw_lpos: Variant = lip_hit.get("position", Vector3.ZERO)
			if raw_lpos is Vector3:
				ledge_y = raw_lpos.y

	var floor_y: float = exit_pos.y
	var floor_exclude: Node = shelf_node if _is_shelf_mode(traversal_type) else null
	var floor_from: Vector3 = Vector3(exit_pos.x, exit_pos.y + 0.8, exit_pos.z)
	var floor_to: Vector3 = Vector3(exit_pos.x, exit_pos.y - 1.2, exit_pos.z)
	var floor_hit: Dictionary = _cast_warp_ray(
		floor_from, floor_to, CollisionLayers.MASK_SOLID_WORLD, floor_exclude
	)
	if not floor_hit.is_empty():
		var raw_fpos: Variant = floor_hit.get("position", Vector3.ZERO)
		if raw_fpos is Vector3:
			floor_y = raw_fpos.y

	var contact_xz: Vector3 = wall_pos if has_wall else entry_pos.lerp(exit_pos, 0.50)
	var hand_y: float = (
		entry_pos.y + 1.15
		if (traversal_type == TRAVERSAL_SHELF_PUSH or traversal_type == TRAVERSAL_SHELF_TOPPLE)
		else ledge_y
	)
	var hand_center: Vector3 = Vector3(contact_xz.x, hand_y, contact_xz.z)
	var left_hand: Vector3 = hand_center - right_vec * HAND_IK_HALF_WIDTH_M
	var right_hand: Vector3 = hand_center + right_vec * HAND_IK_HALF_WIDTH_M

	var anchors: Dictionary[StringName, Variant] = {
		ANCHOR_HAS_WALL: has_wall,
		ANCHOR_WALL_POS: wall_pos,
		ANCHOR_WALL_NORMAL: wall_normal,
		ANCHOR_LEDGE_Y: ledge_y,
		ANCHOR_FLOOR_Y: floor_y,
		ANCHOR_LEFT_HAND: left_hand,
		ANCHOR_RIGHT_HAND: right_hand,
	}
	return anchors


## Executes a zero-allocation cached physics raycast dedicated to pre-traversal motion warping.
func _cast_warp_ray(
	from_pos: Vector3, to_pos: Vector3, mask: int, extra: Node = null
) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world_3d: World3D = get_world_3d()
	if not is_instance_valid(world_3d):
		return {}
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if not is_instance_valid(space):
		return {}

	if not is_instance_valid(_warp_ray_query):
		_warp_ray_query = PhysicsRayQueryParameters3D.new()
		_warp_ray_query.collide_with_bodies = true
		_warp_ray_query.collide_with_areas = false

	_warp_ray_exclude.clear()
	_warp_ray_exclude.append(get_rid())
	if extra is CollisionObject3D:
		_warp_ray_exclude.append((extra as CollisionObject3D).get_rid())

	_warp_ray_query.from = from_pos
	_warp_ray_query.to = to_pos
	_warp_ray_query.collision_mask = mask
	_warp_ray_query.exclude = _warp_ray_exclude
	return space.intersect_ray(_warp_ray_query)


## Returns true if [param traversal_type] pins hands onto a ledge, shelf rail, or wall.
func _traversal_uses_hand_ik(traversal_type: StringName) -> bool:
	return (
		traversal_type == TRAVERSAL_CLIMB_MID
		or traversal_type == TRAVERSAL_PULL_UP_HIGH
		or traversal_type == TRAVERSAL_SHELF_CLIMB
		or traversal_type == TRAVERSAL_SHELF_VAULT
		or traversal_type == TRAVERSAL_SHELF_PUSH
		or traversal_type == TRAVERSAL_SHELF_TOPPLE
	)


## Appends multi-phase keyframes and shelf manipulation triggers for warehouse shelf modes.
func _build_shelf_link_tween(
	tw: Tween,
	traversal_type: StringName,
	start_pos: Vector3,
	exit_pos: Vector3,
	clip_len: float,
	shelf_node: Node,
	push_dir: Vector3,
	anchors: Dictionary[StringName, Variant],
) -> void:
	var horiz: Vector3 = Vector3(exit_pos.x - start_pos.x, 0.0, exit_pos.z - start_pos.z)
	var base_y: float = maxf(start_pos.y, exit_pos.y)
	var raw_ledge_y: Variant = anchors.get(ANCHOR_LEDGE_Y, base_y + SHELF_DECK_CLIMB_Y)
	var ledge_y: float = raw_ledge_y if raw_ledge_y is float else base_y + SHELF_DECK_CLIMB_Y
	var raw_has_wall: Variant = anchors.get(ANCHOR_HAS_WALL, false)
	var has_wall: bool = raw_has_wall if raw_has_wall is bool else false
	var raw_wall_pos: Variant = anchors.get(ANCHOR_WALL_POS, start_pos + horiz * 0.20)
	var wall_pos: Vector3 = raw_wall_pos if raw_wall_pos is Vector3 else start_pos + horiz * 0.20
	var raw_wall_norm: Variant = anchors.get(ANCHOR_WALL_NORMAL, Vector3.ZERO)
	var wall_norm: Vector3 = raw_wall_norm if raw_wall_norm is Vector3 else Vector3.ZERO

	if traversal_type == TRAVERSAL_SHELF_CRAWL:
		var drop_pos: Vector3 = start_pos + horiz * 0.20
		drop_pos.y = base_y
		var under_pos: Vector3 = start_pos + horiz * 0.80
		under_pos.y = ledge_y
		(
			tw
			. tween_property(self, "global_position", drop_pos, clip_len * 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", under_pos, clip_len * 0.50)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
	elif traversal_type == TRAVERSAL_SHELF_CLIMB:
		var reach_xz: Vector3 = (
			wall_pos + wall_norm * WALL_FLUSH_OFFSET_M if has_wall else start_pos + horiz * 0.25
		)
		var reach_pos: Vector3 = Vector3(reach_xz.x, lerpf(base_y, ledge_y, 0.65), reach_xz.z)
		var crest_pos: Vector3 = start_pos + horiz * 0.50
		crest_pos.y = ledge_y
		var drop_edge: Vector3 = start_pos + horiz * 0.80
		drop_edge.y = lerpf(exit_pos.y, ledge_y, 0.60)
		(
			tw
			. tween_property(self, "global_position", reach_pos, clip_len * 0.30)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", crest_pos, clip_len * 0.30)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", drop_edge, clip_len * 0.20)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.20)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
	elif traversal_type == TRAVERSAL_SHELF_VAULT:
		var launch_pos: Vector3 = start_pos + horiz * 0.25
		launch_pos.y = ledge_y
		var mid_dive: Vector3 = start_pos + horiz * 0.78
		mid_dive.y = ledge_y
		(
			tw
			. tween_property(self, "global_position", launch_pos, clip_len * 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_property(self, "global_position", mid_dive, clip_len * 0.45).set_trans(
			Tween.TRANS_LINEAR
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.30)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
	else:
		var brace_xz: Vector3 = (
			wall_pos + wall_norm * WALL_FLUSH_OFFSET_M if has_wall else start_pos + horiz * 0.18
		)
		var brace_pos: Vector3 = Vector3(brace_xz.x, start_pos.y, brace_xz.z)
		var follow_ratio: float = 0.45 if traversal_type == TRAVERSAL_SHELF_PUSH else 0.40
		var shove_pos: Vector3 = start_pos + horiz * follow_ratio
		var shelf_dur: float = clip_len * 0.65
		(
			tw
			. tween_property(self, "global_position", brace_pos, clip_len * 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		tw.tween_callback(
			_trigger_shelf_action.bind(traversal_type, shelf_node, push_dir, shelf_dur)
		)
		(
			tw
			. tween_property(self, "global_position", shove_pos, clip_len * 0.40)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.35)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN_OUT)
		)


## Invokes [method InteractiveShelf.push_aside] or [method InteractiveShelf.topple] if valid.
func _trigger_shelf_action(
	traversal_type: StringName, shelf_node: Node, push_dir: Vector3, duration: float
) -> void:
	var interactive_shelf: InteractiveShelf = shelf_node as InteractiveShelf
	if not is_instance_valid(interactive_shelf) or not interactive_shelf.can_manipulate():
		return
	if traversal_type == TRAVERSAL_SHELF_PUSH:
		interactive_shelf.push_aside(push_dir, duration)
	elif traversal_type == TRAVERSAL_SHELF_TOPPLE:
		interactive_shelf.topple(push_dir, duration)


## Returns true if [param traversal_type] is one of the 5 warehouse shelf traversal modes.
func _is_shelf_mode(traversal_type: StringName) -> bool:
	return (
		traversal_type == TRAVERSAL_SHELF_CRAWL
		or traversal_type == TRAVERSAL_SHELF_CLIMB
		or traversal_type == TRAVERSAL_SHELF_VAULT
		or traversal_type == TRAVERSAL_SHELF_PUSH
		or traversal_type == TRAVERSAL_SHELF_TOPPLE
	)


## Resolves the target shelf [Node] from [constant META_SHELF_NODE_PATH] on [param link_obj].
func _resolve_shelf_node(link_obj: Object) -> Node:
	if not (link_obj is Node):
		return null
	var link_node: Node = link_obj as Node
	if not link_node.has_meta(META_SHELF_NODE_PATH):
		return null
	var raw_path: Variant = link_node.get_meta(META_SHELF_NODE_PATH)
	if raw_path is NodePath:
		var path_val: NodePath = raw_path
		return link_node.get_node_or_null(path_val)
	if raw_path is String:
		var path_str: String = raw_path
		return link_node.get_node_or_null(NodePath(path_str))
	return null


## Checks whether overhead clearance above a 2.2m shelf allows climbing over it.
func _has_shelf_top_clearance(shelf: Node, entry_pos: Vector3, exit_pos: Vector3) -> bool:
	var midpoint: Vector3 = (entry_pos + exit_pos) * 0.5
	var base_y: float = maxf(entry_pos.y, exit_pos.y)
	var ray_from: Vector3 = Vector3(midpoint.x, base_y + SHELF_TOP_HEIGHT_M + 0.15, midpoint.z)
	var ray_to: Vector3 = ray_from + Vector3(0.0, SHELF_CLIMB_HEADROOM_M, 0.0)
	var hit: Dictionary = _cast_cached_ray(
		ray_from, ray_to, CollisionLayers.MASK_SOLID_WORLD, shelf
	)
	return hit.is_empty()


## Checks whether forward space past [param exit_pos] is too cramped to topple the shelf.
func _is_shelf_topple_cramped(shelf: Node, entry_pos: Vector3, exit_pos: Vector3) -> bool:
	var planar: Vector3 = exit_pos - entry_pos
	planar.y = 0.0
	if planar.length_squared() < MIN_PLANAR_DIST_SQ:
		return false
	var dir: Vector3 = planar.normalized()
	var midpoint: Vector3 = (entry_pos + exit_pos) * 0.5
	var ray_from: Vector3 = Vector3(midpoint.x, maxf(entry_pos.y, exit_pos.y) + 1.0, midpoint.z)
	var ray_to: Vector3 = ray_from + dir * SHELF_TOPPLE_CLEARANCE_M
	var hit: Dictionary = _cast_cached_ray(
		ray_from, ray_to, CollisionLayers.MASK_SOLID_WORLD, shelf
	)
	return not hit.is_empty()


## Scans recent slide collisions for an uncleared [InteractiveShelf] and starts traversal.
func _try_trigger_shelf_from_slide_collisions() -> void:
	for idx: int in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(idx)
		var collider: Object = col.get_collider() if is_instance_valid(col) else null
		if collider is InteractiveShelf:
			if _try_trigger_shelf_collision(collider as InteractiveShelf):
				return


## Starts contextual shelf traversal when colliding directly with [param shelf].
func _try_trigger_shelf_collision(shelf: InteractiveShelf) -> bool:
	if (
		_shelf_collision_cooldown_sec > 0.0
		or _is_traversing_link
		or _is_yielding_doorway
		or not is_instance_valid(shelf)
		or shelf.is_cleared()
	):
		return false

	var entry_pos: Vector3 = global_position
	var cross_dir: Vector3 = shelf.global_transform.basis.z
	cross_dir.y = 0.0
	if cross_dir.length_squared() < MIN_PLANAR_DIST_SQ:
		cross_dir = Vector3.FORWARD
	else:
		cross_dir = cross_dir.normalized()

	var approach: Vector3 = shelf.global_position - global_position
	approach.y = 0.0
	if approach.length_squared() < MIN_PLANAR_DIST_SQ:
		approach = Vector3(velocity.x, 0.0, velocity.z)
	if approach.length_squared() >= MIN_PLANAR_DIST_SQ and cross_dir.dot(approach) < 0.0:
		cross_dir = -cross_dir

	var exit_pos: Vector3 = shelf.global_position + cross_dir * SHELF_COLLISION_EXIT_OFFSET_M
	exit_pos.y = entry_pos.y

	var mode: StringName = select_shelf_traversal(shelf, entry_pos, exit_pos)
	if mode.is_empty():
		return false

	_start_tween_traversal(mode, entry_pos, exit_pos, shelf)
	return true


## Executes a zero-allocation cached physics raycast excluding self and optional [param extra].
func _cast_cached_ray(
	from_pos: Vector3, to_pos: Vector3, mask: int, extra: Node = null
) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world_3d: World3D = get_world_3d()
	if not is_instance_valid(world_3d):
		return {}
	var space: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if not is_instance_valid(space):
		return {}

	if not is_instance_valid(_cached_ray_query):
		_cached_ray_query = PhysicsRayQueryParameters3D.new()
		_cached_ray_query.collide_with_bodies = true
		_cached_ray_query.collide_with_areas = false

	_ray_exclude.clear()
	_ray_exclude.append(get_rid())
	if extra is CollisionObject3D:
		_ray_exclude.append((extra as CollisionObject3D).get_rid())

	_cached_ray_query.from = from_pos
	_cached_ray_query.to = to_pos
	_cached_ray_query.collision_mask = mask
	_cached_ray_query.exclude = _ray_exclude
	return space.intersect_ray(_cached_ray_query)


## Updates throttled chokepoint detection and starts doorway yield if player approaches closely.
func _update_chokepoint_yield_trigger(delta: float) -> void:
	if _doorway_yield_cooldown > 0.0:
		_doorway_yield_cooldown = maxf(0.0, _doorway_yield_cooldown - delta)
		return

	var player: Node3D = _resolve_player_node()
	if not is_instance_valid(player):
		return

	var dist_sq: float = global_position.distance_squared_to(player.global_position)
	var approaching: bool = _is_player_approaching(player, dist_sq)
	_prev_player_dist_sq = dist_sq

	_chokepoint_check_accum += delta
	if _chokepoint_check_accum >= CHOKEPOINT_CHECK_INTERVAL_SEC:
		_chokepoint_check_accum = 0.0
		_refresh_chokepoint_state()

	if _in_chokepoint and dist_sq <= DOORWAY_YIELD_TRIGGER_DIST_SQ and approaching:
		_begin_doorway_yield(dist_sq)


## Returns true when [param player] is moving toward or closely facing Godiva.
func _is_player_approaching(player: Node3D, dist_sq: float) -> bool:
	var to_godiva: Vector3 = global_position - player.global_position
	to_godiva.y = 0.0
	if player is CharacterBody3D:
		var vel: Vector3 = (player as CharacterBody3D).velocity
		vel.y = 0.0
		if vel.length_squared() > 0.04:
			return vel.dot(to_godiva) > 0.1
	if _prev_player_dist_sq >= 0.0 and dist_sq < _prev_player_dist_sq - MIN_PLANAR_DIST_SQ:
		return true
	if _prev_player_dist_sq >= 0.0 and dist_sq > _prev_player_dist_sq + MIN_PLANAR_DIST_SQ:
		return false
	if to_godiva.length_squared() >= MIN_PLANAR_DIST_SQ:
		var player_fwd: Vector3 = -player.global_transform.basis.z
		player_fwd.y = 0.0
		if player_fwd.length_squared() >= MIN_PLANAR_DIST_SQ:
			return player_fwd.normalized().dot(to_godiva.normalized()) > 0.25
	return true


## Refreshes [member _in_chokepoint] via [constant GROUP_CHOKEPOINT] areas or 2-ray corridor check.
func _refresh_chokepoint_state() -> void:
	if not is_inside_tree():
		_in_chokepoint = false
		return

	var areas: Array[Node] = get_tree().get_nodes_in_group(GROUP_CHOKEPOINT)
	for node: Node in areas:
		if node is Area3D:
			var area: Area3D = node as Area3D
			if _is_inside_chokepoint_area(area):
				_in_chokepoint = true
				var door_right: Vector3 = area.global_transform.basis.x
				door_right.y = 0.0
				if door_right.length_squared() < MIN_PLANAR_DIST_SQ:
					door_right = Vector3.RIGHT
				else:
					door_right = door_right.normalized()
				if not _measure_lateral_walls(door_right, false):
					var local_pos: Vector3 = area.to_local(global_position)
					_chokepoint_wall_dir = door_right if local_pos.x >= 0.0 else -door_right
					_chokepoint_wall_dist = DOORWAY_DEFAULT_SIDESTEP_M + DOORWAY_WALL_MARGIN_M
				return

	var self_right: Vector3 = global_transform.basis.x
	self_right.y = 0.0
	if self_right.length_squared() < MIN_PLANAR_DIST_SQ:
		self_right = Vector3.RIGHT
	else:
		self_right = self_right.normalized()
	_in_chokepoint = _measure_lateral_walls(self_right, true)


## Returns true if Godiva overlaps [param area] or lies within its primary [BoxShape3D] bounds.
func _is_inside_chokepoint_area(area: Area3D) -> bool:
	if area.overlaps_body(self):
		return true
	for child: Node in area.get_children():
		if child is CollisionShape3D:
			var col: CollisionShape3D = child as CollisionShape3D
			if col.shape is BoxShape3D:
				var half: Vector3 = (col.shape as BoxShape3D).size * 0.5
				var rel: Vector3 = area.to_local(global_position) - col.position
				if absf(rel.x) <= half.x and absf(rel.y) <= half.y and absf(rel.z) <= half.z:
					return true
	return false


## Casts 2 lateral rays along [param lateral_axis] to detect narrow walls and nearest wall side.
func _measure_lateral_walls(lateral_axis: Vector3, require_narrow: bool) -> bool:
	var origin: Vector3 = global_position + Vector3(0.0, 1.0, 0.0)
	var right_hit: Dictionary = _cast_cached_ray(
		origin, origin + lateral_axis * CHOKEPOINT_RAY_RANGE_M, CollisionLayers.MASK_ENVIRONMENT
	)
	var left_hit: Dictionary = _cast_cached_ray(
		origin, origin - lateral_axis * CHOKEPOINT_RAY_RANGE_M, CollisionLayers.MASK_ENVIRONMENT
	)

	var has_right: bool = not right_hit.is_empty()
	var has_left: bool = not left_hit.is_empty()
	if not has_right and not has_left:
		return false

	var right_dist: float = CHOKEPOINT_RAY_RANGE_M
	if has_right:
		var r_pos: Variant = right_hit.get("position", origin)
		if r_pos is Vector3:
			right_dist = origin.distance_to(r_pos)
	var left_dist: float = CHOKEPOINT_RAY_RANGE_M
	if has_left:
		var l_pos: Variant = left_hit.get("position", origin)
		if l_pos is Vector3:
			left_dist = origin.distance_to(l_pos)

	if require_narrow:
		if not (has_right and has_left):
			return false
		if right_dist + left_dist >= CHOKEPOINT_NARROW_WIDTH_M:
			return false

	if left_dist <= right_dist:
		_chokepoint_wall_dir = -lateral_axis
		_chokepoint_wall_dist = left_dist
	else:
		_chokepoint_wall_dir = lateral_axis
		_chokepoint_wall_dist = right_dist
	return true


## Enters doorway yield mode, computing the wall-hug offset and lateral sidestep clip.
func _begin_doorway_yield(initial_dist_sq: float) -> void:
	_is_yielding_doorway = true
	_doorway_yield_elapsed = 0.0
	_yield_min_player_dist_sq = initial_dist_sq

	var step_dir: Vector3 = _chokepoint_wall_dir
	step_dir.y = 0.0
	if step_dir.length_squared() < MIN_PLANAR_DIST_SQ:
		step_dir = global_transform.basis.x
		step_dir.y = 0.0
	step_dir = (
		step_dir.normalized() if step_dir.length_squared() >= MIN_PLANAR_DIST_SQ else Vector3.RIGHT
	)

	var step_dist: float = clampf(
		_chokepoint_wall_dist - DOORWAY_WALL_MARGIN_M, 0.0, DOORWAY_DEFAULT_SIDESTEP_M
	)
	_yield_target_pos = global_position + step_dir * step_dist
	_yield_sidestep_clip = (
		CLIP_SIDESTEP_LEFT if global_transform.basis.x.dot(step_dir) < 0.0 else CLIP_SIDESTEP_RIGHT
	)
	doorway_yield_changed.emit(true)
	print("GodivaFollower: ", name, " -> doorway_yield start")


## Sidesteps toward the nearest wall and holds [constant CLIP_WALL_HUG_IDLE] until player clears.
func _process_doorway_yield(delta: float) -> void:
	_doorway_yield_elapsed += delta
	if _doorway_yield_elapsed >= DOORWAY_YIELD_TIMEOUT_SEC:
		_end_doorway_yield()
		return

	var player: Node3D = _resolve_player_node()
	if not is_instance_valid(player):
		_end_doorway_yield()
		return

	var dist_sq: float = global_position.distance_squared_to(player.global_position)
	_yield_min_player_dist_sq = minf(_yield_min_player_dist_sq, dist_sq)
	var approaching: bool = _is_player_approaching(player, dist_sq)
	_prev_player_dist_sq = dist_sq

	if dist_sq > DOORWAY_YIELD_CLEAR_DIST_SQ and not approaching:
		_end_doorway_yield()
		return

	var to_wall: Vector3 = _yield_target_pos - global_position
	to_wall.y = 0.0
	if to_wall.length_squared() > DOORWAY_SIDESTEP_ARRIVED_SQ:
		var dir: Vector3 = to_wall.normalized()
		velocity.x = dir.x * DOORWAY_SIDESTEP_SPEED
		velocity.z = dir.z * DOORWAY_SIDESTEP_SPEED
		_set_locomotion_state(true, _yield_sidestep_clip)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_set_locomotion_state(false, CLIP_WALL_HUG_IDLE)
		if is_instance_valid(ik_controller):
			var wall_dir: Vector3 = _chokepoint_wall_dir
			wall_dir.y = 0.0
			wall_dir = (
				wall_dir.normalized()
				if wall_dir.length_squared() >= MIN_PLANAR_DIST_SQ
				else global_transform.basis.x.normalized()
			)
			var wall_tangent: Vector3 = wall_dir.cross(Vector3.UP).normalized()
			var palm_center: Vector3 = (
				global_position + Vector3(0.0, 1.15, 0.0) + wall_dir * DOORWAY_WALL_MARGIN_M
			)
			(
				ik_controller
				. set_hand_targets(
					palm_center - wall_tangent * HAND_IK_HALF_WIDTH_M,
					palm_center + wall_tangent * HAND_IK_HALF_WIDTH_M,
					HAND_IK_WEIGHT,
				)
			)
	move_and_slide()


## Exits doorway yield mode and resumes normal player following.
func _end_doorway_yield() -> void:
	if not _is_yielding_doorway:
		return
	_is_yielding_doorway = false
	_doorway_yield_elapsed = 0.0
	_doorway_yield_cooldown = DOORWAY_YIELD_COOLDOWN_SEC
	_yield_min_player_dist_sq = INF
	if is_instance_valid(ik_controller):
		ik_controller.clear_hand_targets()
	doorway_yield_changed.emit(false)
	print("GodivaFollower: ", name, " -> doorway_yield resume")


## Appends multi-phase position keyframes to [param tw] snapped to probed [param anchors].
func _build_multiphase_link_tween(
	tw: Tween,
	traversal_type: StringName,
	start_pos: Vector3,
	exit_pos: Vector3,
	clip_len: float,
	anchors: Dictionary[StringName, Variant],
) -> void:
	var horiz: Vector3 = Vector3(exit_pos.x - start_pos.x, 0.0, exit_pos.z - start_pos.z)
	var raw_ledge_y: Variant = anchors.get(ANCHOR_LEDGE_Y, maxf(start_pos.y, exit_pos.y))
	var ledge_y: float = raw_ledge_y if raw_ledge_y is float else maxf(start_pos.y, exit_pos.y)
	var raw_has_wall: Variant = anchors.get(ANCHOR_HAS_WALL, false)
	var has_wall: bool = raw_has_wall if raw_has_wall is bool else false
	var raw_wall_pos: Variant = anchors.get(ANCHOR_WALL_POS, start_pos + horiz * 0.20)
	var wall_pos: Vector3 = raw_wall_pos if raw_wall_pos is Vector3 else start_pos + horiz * 0.20
	var raw_wall_norm: Variant = anchors.get(ANCHOR_WALL_NORMAL, Vector3.ZERO)
	var wall_norm: Vector3 = raw_wall_norm if raw_wall_norm is Vector3 else Vector3.ZERO
	var flush_xz: Vector3 = (
		wall_pos + wall_norm * WALL_FLUSH_OFFSET_M if has_wall else start_pos + horiz * 0.25
	)

	if traversal_type == TRAVERSAL_STEP_UP:
		var mid_step: Vector3 = start_pos + horiz * 0.35
		mid_step.y = ledge_y
		(
			tw
			. tween_property(self, "global_position", mid_step, clip_len * 0.45)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.55)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN_OUT)
		)
	elif traversal_type == TRAVERSAL_CLIMB_MID:
		var reach_pos: Vector3 = Vector3(flush_xz.x, lerpf(start_pos.y, ledge_y, 0.65), flush_xz.z)
		var mantle_pos: Vector3 = start_pos + horiz * 0.80
		mantle_pos.y = ledge_y
		(
			tw
			. tween_property(self, "global_position", reach_pos, clip_len * 0.30)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", mantle_pos, clip_len * 0.45)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
	elif traversal_type == TRAVERSAL_PULL_UP_HIGH:
		var grab_pos: Vector3 = Vector3(flush_xz.x, lerpf(start_pos.y, ledge_y, 0.60), flush_xz.z)
		var rim_pos: Vector3 = start_pos + horiz * 0.55
		rim_pos.y = ledge_y
		(
			tw
			. tween_property(self, "global_position", grab_pos, clip_len * 0.25)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", rim_pos, clip_len * 0.45)
			. set_trans(Tween.TRANS_CUBIC)
			. set_ease(Tween.EASE_IN_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.30)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
	else:
		var step_off: Vector3 = start_pos + horiz * 0.65
		step_off.y = lerpf(start_pos.y, exit_pos.y, 0.15)
		var land_pos: Vector3 = exit_pos
		(
			tw
			. tween_property(self, "global_position", step_off, clip_len * 0.35)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_OUT)
		)
		(
			tw
			. tween_property(self, "global_position", land_pos, clip_len * 0.45)
			. set_trans(Tween.TRANS_QUAD)
			. set_ease(Tween.EASE_IN)
		)
		(
			tw
			. tween_property(self, "global_position", exit_pos, clip_len * 0.20)
			. set_trans(Tween.TRANS_SINE)
			. set_ease(Tween.EASE_OUT)
		)


## Reads [param clip_sn] length from [member _anim_player] or falls back to [param default_sec].
func _get_clip_duration(clip_sn: StringName, default_sec: float) -> float:
	if is_instance_valid(_anim_player) and _anim_player.has_animation(clip_sn):
		var anim: Animation = _anim_player.get_animation(clip_sn)
		if is_instance_valid(anim) and anim.length > 0.05:
			return anim.length
	return default_sec


## Returns fallback duration in seconds matching 60 FPS clip lengths when clip is absent.
func _get_default_traversal_duration(traversal_type: StringName) -> float:
	if traversal_type == TRAVERSAL_STEP_UP:
		return 0.67
	if traversal_type == TRAVERSAL_CLIMB_MID:
		return 1.17
	if traversal_type == TRAVERSAL_PULL_UP_HIGH:
		return 1.83
	if traversal_type == TRAVERSAL_SHELF_CRAWL:
		return 1.20
	if traversal_type == TRAVERSAL_SHELF_CLIMB:
		return 1.60
	if traversal_type == TRAVERSAL_SHELF_VAULT:
		return 0.95
	if traversal_type == TRAVERSAL_SHELF_PUSH or traversal_type == TRAVERSAL_SHELF_TOPPLE:
		return 1.10
	return 0.75


## Safely reads a normalized [StringName] metadata tag from [param link_obj].
func _read_link_meta_name(link_obj: Object, key: StringName) -> StringName:
	if not is_instance_valid(link_obj) or not link_obj.has_meta(key):
		return &""
	var raw_val: Variant = link_obj.get_meta(key)
	if raw_val is StringName:
		var sn_str: String = String(raw_val)
		return StringName(sn_str.strip_edges().to_lower())
	if raw_val is String:
		var raw_str: String = raw_val
		return StringName(raw_str.strip_edges().to_lower())
	return &""


## Infers traversal clip name from vertical link height delta when metadata is missing.
func _fallback_traversal_by_delta(dy: float) -> StringName:
	if dy < -0.35:
		return TRAVERSAL_DROP_DOWN
	if dy <= 1.10:
		return TRAVERSAL_STEP_UP
	if dy <= 1.85:
		return TRAVERSAL_CLIMB_MID
	return TRAVERSAL_PULL_UP_HIGH


## Callback firing every 0.25s to project player position onto the navigation mesh.
func _on_repath_timer_timeout() -> void:
	if not _is_following:
		return
	_update_follow_target()


## Callback triggered when [member nav_agent] enters a [NavigationLink3D] segment.
func _on_nav_link_reached(details: Dictionary) -> void:
	if not _is_following or _is_traversing_link:
		return

	var raw_entry: Variant = details.get("link_entry_position", global_position)
	var raw_exit: Variant = details.get("link_exit_position", global_position)
	var entry_pos: Vector3 = raw_entry if raw_entry is Vector3 else global_position
	var exit_pos: Vector3 = raw_exit if raw_exit is Vector3 else global_position
	var raw_owner: Variant = details.get("owner", null)
	var link_obj: Object = raw_owner if raw_owner is Object else null

	var traversal_type: StringName = resolve_traversal_type(link_obj, entry_pos, exit_pos)
	if traversal_type == TRAVERSAL_SHELF_INTERACT:
		var shelf_node: Node = _resolve_shelf_node(link_obj)
		var chosen_mode: StringName = select_shelf_traversal(shelf_node, entry_pos, exit_pos)
		if chosen_mode.is_empty():
			return
		_start_tween_traversal(chosen_mode, entry_pos, exit_pos, shelf_node)
		return
	if _is_shelf_mode(traversal_type):
		var direct_shelf: Node = _resolve_shelf_node(link_obj)
		_start_tween_traversal(traversal_type, entry_pos, exit_pos, direct_shelf)
		return
	if traversal_type == TRAVERSAL_CROUCH_WALK or traversal_type == TRAVERSAL_PRONE_CRAWL:
		var target_stance: Stance = (
			Stance.PRONE if traversal_type == TRAVERSAL_PRONE_CRAWL else Stance.CROUCH
		)
		_apply_stance(target_stance, false)
		_is_traversing_link = true
		_is_tween_traversal = false
		_active_link_traversal = traversal_type
		_link_exit_pos = exit_pos
		_stance_link_elapsed = 0.0
		var move_clip: StringName = (
			CLIP_PRONE_CRAWL if target_stance == Stance.PRONE else CLIP_CROUCH_WALK
		)
		_set_locomotion_state(true, move_clip)
		traversal_started.emit(traversal_type)
		print("GodivaFollower: ", name, " started stance link -> ", traversal_type)
	else:
		_start_tween_traversal(traversal_type, entry_pos, exit_pos)


## Restores normal gravity and navigation steering once a climb/drop [Tween] finishes.
func _on_link_tween_finished(traversal_type: StringName) -> void:
	_is_traversing_link = false
	_is_tween_traversal = false
	_active_link_traversal = &""
	if is_instance_valid(ik_controller):
		ik_controller.clear_hand_targets()
		ik_controller.set_foot_ik_suppressed(_current_stance == Stance.PRONE)
	if _is_shelf_mode(traversal_type):
		_shelf_collision_cooldown_sec = SHELF_COLLISION_COOLDOWN_SEC
	velocity = Vector3.ZERO
	turn_body_when_behind = _base_turn_body_when_behind
	if _current_stance != Stance.STAND:
		_try_recover_standing_stance()
	if _is_following:
		_update_follow_target()
	traversal_finished.emit(traversal_type)
	print("GodivaFollower: ", name, " finished link -> ", traversal_type)


## Forwards screen-entered visibility state to [member ik_controller].
func _on_screen_entered() -> void:
	super._on_screen_entered()
	if is_instance_valid(ik_controller):
		ik_controller.set_visible_on_screen(true)


## Forwards screen-exited visibility state to sleep [member ik_controller] off-screen.
func _on_screen_exited() -> void:
	super._on_screen_exited()
	if is_instance_valid(ik_controller):
		ik_controller.set_visible_on_screen(false)
