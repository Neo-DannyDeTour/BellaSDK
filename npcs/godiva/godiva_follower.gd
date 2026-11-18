## Player-following NPC extending [NpcActor] with [NavigationAgent3D] and obstacle traversal.
class_name GodivaFollower
extends NpcActor

## Emitted when follow mode starts or stops.
signal follow_state_changed(following: bool)

## Emitted when a [NavigationLink3D] traversal begins.
signal traversal_started(traversal_type: StringName)

## Emitted when a [NavigationLink3D] traversal completes.
signal traversal_finished(traversal_type: StringName)

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
## Metadata key on [NavigationLink3D] specifying traversal type.
const META_TRAVERSAL_TYPE: StringName = &"traversal_type"
## Optional metadata key on [NavigationLink3D] overriding downward traversal type.
const META_TRAVERSAL_TYPE_DOWN: StringName = &"traversal_type_down"

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

## Scene references for navigation and capsule resizing.
@export_group("Follow Navigation")
## Child [NavigationAgent3D] computing paths toward the player.
@export var nav_agent: NavigationAgent3D = null
## Child [CollisionShape3D] holding the resizable [CapsuleShape3D].
@export var collision_shape: CollisionShape3D = null
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

	if _is_traversing_link:
		_process_stance_link(delta)
		return

	if _current_stance != Stance.STAND:
		_headroom_accum += delta
		if _headroom_accum >= HEADROOM_CHECK_INTERVAL:
			_headroom_accum = 0.0
			_try_recover_standing_stance()

	_apply_vertical_gravity(delta)

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
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	_rotate_toward_direction(dir, delta)
	_set_locomotion_state(true, move_clip)
	move_and_slide()


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

	velocity.x = 0.0
	velocity.z = 0.0
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


## Resolves link traversal type from [NavigationLink3D] metadata with vertical delta fallback.
func resolve_traversal_type(link_obj: Object, entry_pos: Vector3, exit_pos: Vector3) -> StringName:
	var dy: float = exit_pos.y - entry_pos.y
	var meta_type: StringName = _read_link_meta_name(link_obj, META_TRAVERSAL_TYPE)

	if meta_type == TRAVERSAL_CROUCH_WALK or meta_type == TRAVERSAL_PRONE_CRAWL:
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


## Starts a multi-phase [Tween] for climb/drop links synced to [AnimationPlayer] clip length.
func _start_tween_traversal(
	traversal_type: StringName, entry_pos: Vector3, exit_pos: Vector3
) -> void:
	_apply_stance(Stance.STAND, false)
	_is_traversing_link = true
	_is_tween_traversal = true
	_active_link_traversal = traversal_type
	_link_exit_pos = exit_pos
	velocity = Vector3.ZERO
	turn_body_when_behind = false

	var planar: Vector3 = exit_pos - entry_pos
	planar.y = 0.0
	if planar.length_squared() >= MIN_PLANAR_DIST_SQ:
		global_rotation.y = atan2(-planar.x, -planar.z)

	var fallback_sec: float = _get_default_traversal_duration(traversal_type)
	var clip_len: float = _get_clip_duration(traversal_type, fallback_sec)
	if _registered_clips.has(traversal_type):
		play_animation_once(String(traversal_type))

	var tw: Tween = Utilities.reset_tween(self, _link_tween)
	_link_tween = tw
	if not is_instance_valid(tw):
		global_position = exit_pos
		_on_link_tween_finished(traversal_type)
		return

	var start_pos: Vector3 = global_position
	_build_multiphase_link_tween(tw, traversal_type, start_pos, exit_pos, clip_len)
	tw.finished.connect(_on_link_tween_finished.bind(traversal_type), Object.CONNECT_ONE_SHOT)
	traversal_started.emit(traversal_type)
	print("GodivaFollower: ", name, " started link -> ", traversal_type, " dur=", clip_len)


## Appends multi-phase position keyframes to [param tw] matching [param traversal_type].
func _build_multiphase_link_tween(
	tw: Tween,
	traversal_type: StringName,
	start_pos: Vector3,
	exit_pos: Vector3,
	clip_len: float,
) -> void:
	var horiz: Vector3 = Vector3(exit_pos.x - start_pos.x, 0.0, exit_pos.z - start_pos.z)
	var peak_y: float = maxf(start_pos.y, exit_pos.y)

	if traversal_type == TRAVERSAL_STEP_UP:
		var mid_step: Vector3 = start_pos + horiz * 0.35
		mid_step.y = exit_pos.y + 0.05
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
		var reach_pos: Vector3 = start_pos + horiz * 0.20
		reach_pos.y = lerpf(start_pos.y, exit_pos.y, 0.65)
		var mantle_pos: Vector3 = start_pos + horiz * 0.80
		mantle_pos.y = peak_y + 0.12
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
		var grab_pos: Vector3 = start_pos + horiz * 0.25
		grab_pos.y = lerpf(start_pos.y, exit_pos.y, 0.60)
		var rim_pos: Vector3 = start_pos + horiz * 0.55
		rim_pos.y = peak_y + 0.15
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
		land_pos.y = exit_pos.y + 0.04
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
	velocity = Vector3.ZERO
	turn_body_when_behind = _base_turn_body_when_behind
	if _is_following:
		_update_follow_target()
	traversal_finished.emit(traversal_type)
	print("GodivaFollower: ", name, " finished link -> ", traversal_type)
