## Shared enums, constants, masks, and typed data structs for Two-Tier Tactical AI.
class_name TacticalTypes
extends Object

## High-level squad tactical roles assigned by [SquadCoordinator].
enum Role {
	CLIMB,
	SUPPRESS_THROW,
	FLANK,
	HOLD_CHOKE,
	RETREAT,
	STACK_SLAM,
	WATER_DIVE,
}

## Squad morale-driven behavioral mood states.
enum MoodState {
	PUSH,
	CONSERVATIVE,
	FLEE,
}

## Atomic action primitives executed sequentially by [TacticalAgent] ActionQueue.
enum ActionType {
	MOVE_TO,
	CLIMB_LINK,
	PICK_UP_PROP,
	THROW_PROP,
	TAKE_COVER,
	STACK_SLAM,
	WATER_DIVE,
}

## Group name for throwable [RigidBody3D] props.
const GROUP_THROWABLE: StringName = &"throwable"

## Group name for [TacticalAgent] components.
const GROUP_TACTICAL_AGENT: StringName = &"tactical_agent"

## Group name for water volume triggers.
const GROUP_WATER_VOLUME: StringName = &"water_volume"

## Metadata key storing the claiming instance ID on SmartObjects.
const META_CLAIMED_BY: StringName = &"claimed_by"

## Physics layer 1 mask for static environment geometry.
const MASK_ENV: int = CollisionLayers.MASK_ENVIRONMENT

## Physics layer 3 mask for interactive props.
const MASK_INTERACTIVE: int = CollisionLayers.MASK_INTERACTIVE

## Physics layer 4 mask for debris objects.
const MASK_DEBRIS: int = CollisionLayers.MASK_DEBRIS

## Physics layer 5 mask for enemy entities.
const MASK_ENEMIES: int = CollisionLayers.MASK_ENEMIES

## Composite mask for throwable prop queries (Layer 3 Interactive | Layer 4 Debris).
const MASK_THROWABLES: int = MASK_INTERACTIVE | MASK_DEBRIS

## Composite mask for line-of-sight occlusion checks (Layer 1 Env | Layer 3 Interactive).
const MASK_LOS_BLOCKERS: int = CollisionLayers.MASK_SOLID_WORLD


## Typed action step queued inside [TacticalAgent] ActionQueue.
class ActionItem:
	extends RefCounted

	## Action primitive type.
	var type: ActionType = ActionType.MOVE_TO
	## Target world position for movement, cover, slam, or dive.
	var target_pos: Vector3 = Vector3.ZERO
	## Launch velocity vector for [member ActionType.THROW_PROP].
	var velocity: Vector3 = Vector3.ZERO
	## Target node reference (e.g. [NavigationLink3D] or [RigidBody3D]).
	var target_node: Node = null

	## Initializes a typed [ActionItem].
	func _init(
		p_type: ActionType = ActionType.MOVE_TO,
		p_pos: Vector3 = Vector3.ZERO,
		p_vel: Vector3 = Vector3.ZERO,
		p_node: Node = null
	) -> void:
		type = p_type
		target_pos = p_pos
		velocity = p_vel
		target_node = p_node


## Result of a dual-mode ballistic trajectory calculation.
class BallisticSolution:
	extends RefCounted

	## True when a valid trajectory was computed.
	var valid: bool = false
	## Initial launch velocity in world space.
	var velocity: Vector3 = Vector3.ZERO
	## Estimated time of flight in seconds.
	var flight_time: float = 0.0
	## True when using high-arc balcony-clearing trajectory.
	var is_high_arc: bool = false
	## Peak Y altitude reached along the arc.
	var apex_y: float = 0.0


## Result of an 8-point dynamic cover probe.
class CoverProbeResult:
	extends RefCounted

	## True when a valid cover point was found.
	var found: bool = false
	## Best cover world position snapped to navigation mesh.
	var position: Vector3 = Vector3.ZERO
	## Selection score (higher is better).
	var score: float = -INF
	## True when the cover point breaks line-of-sight to the threat.
	var breaks_los: bool = false
	## Squared distance from agent to cover position.
	var dist_sq: float = INF
