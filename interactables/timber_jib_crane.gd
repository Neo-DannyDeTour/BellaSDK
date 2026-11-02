@tool
## Rotating timber jib crane with base capstan push-handles and overhead swing/traverse bar.
class_name TimberJibCrane
extends StaticBody3D

# --------------------------------------
# SIGNALS
# --------------------------------------

## Emitted when the crane's yaw angle changes, passing angle in degrees and normalized progress.
signal angle_changed(angle_deg: float, normalized_progress: float)

## Emitted when the crane reaches 100% of its clamped rotation arc (`max_angle_deg`).
signal powered_on

## Emitted when the crane leaves 100% of its clamped rotation arc.
signal powered_off

## Emitted when a player attaches to the overhead jib grab rail.
signal jib_player_mounted(player: CharacterBody3D)

## Emitted when a player dismounts from the overhead jib grab rail.
signal jib_player_dismounted(player: CharacterBody3D)

# --------------------------------------
# CONSTANTS
# --------------------------------------

## Group identifier for interactable objects scanned by [InteractionScanner].
const GROUP_INTERACTABLE: StringName = &"interactable"

## Secondary plural group identifier for interactable objects.
const GROUP_INTERACTABLES: StringName = &"interactables"

## Group identifier preventing [VaultController] from ledge-climbing onto capstan/rail colliders.
const GROUP_NOT_CLIMBABLE: StringName = &"not_climbable"

## Player state name for base capstan rotation via [PushWheelState].
const STATE_PUSH_WHEEL: StringName = &"PushWheel"

## Player state name for overhead jib hanging, swinging, and traversal via [StateJibCrane].
const STATE_JIB_CRANE: StringName = &"JibCrane"

## Player state name for vertical rope/chain climbing via [StateRope].
const STATE_ROPE: StringName = &"Rope"

## State transition dictionary key passing the crane reference to [PushWheelState].
const KEY_WHEEL: StringName = &"wheel"

## State transition dictionary key passing the mount [Transform3D] to [PushWheelState].
const KEY_TARGET_TRANSFORM: StringName = &"target_transform"

## State transition dictionary key passing the crane reference to [StateJibCrane].
const KEY_CRANE: StringName = &"crane"

## State transition dictionary key passing the initial 1D rail offset to [StateJibCrane].
const KEY_RAIL_OFFSET: StringName = &"rail_offset"

## Top surface Y height in meters of the single-circle stone base platform.
const BASE_SURFACE_Y: float = 0.20

## Outline shader preloaded for focus highlighting on the capstan and jib grab rail.
const OUTLINE_SHADER: Shader = preload("res://vfx/unlit_outline_material.gdshader")

# --------------------------------------
# EXPORTS: ROTATION & AUTO-RETURN
# --------------------------------------
@export_group("Rotation & Return")

## Resting yaw angle in degrees (around local Y) initialized on startup and targeted by auto-return.
@export var initial_angle_deg: float = 0.0:
	set(value):
		initial_angle_deg = value
		if not is_inside_tree():
			return
		if Engine.is_editor_hint() or not _is_base_pushed:
			current_angle_deg = _sanitize_angle_deg(initial_angle_deg)
			_apply_current_angle_to_visuals()

## When true, clamps crane rotation between [member min_angle_deg] and [member max_angle_deg].
@export var limit_rotation: bool = true:
	set(value):
		limit_rotation = value
		if is_inside_tree():
			current_angle_deg = _sanitize_angle_deg(current_angle_deg)
			_sync_progress_from_angle()
			_apply_current_angle_to_visuals()

## Minimum allowed yaw angle in degrees when [member limit_rotation] is enabled.
@export var min_angle_deg: float = -90.0:
	set(value):
		min_angle_deg = value
		if is_inside_tree():
			current_angle_deg = _sanitize_angle_deg(current_angle_deg)
			_sync_progress_from_angle()
			_apply_current_angle_to_visuals()

## Maximum allowed yaw angle in degrees when [member limit_rotation] is enabled.
@export var max_angle_deg: float = 90.0:
	set(value):
		max_angle_deg = value
		if is_inside_tree():
			current_angle_deg = _sanitize_angle_deg(current_angle_deg)
			_sync_progress_from_angle()
			_apply_current_angle_to_visuals()

## Seconds required to push the crane through a full 360-degree turn from the base capstan.
@export_range(0.5, 60.0, 0.1) var seconds_for_full_rotation: float = 12.0

## When true, pushing at the base rotates clockwise around Y; when false, counter-clockwise.
@export var turn_clockwise: bool = true

## When true, the crane automatically rotates back to [member initial_angle_deg] after base release.
@export var auto_return: bool = false:
	set(value):
		auto_return = value
		if is_inside_tree() and not Engine.is_editor_hint():
			_update_process_state()

## Angular return speed in degrees per second when [member auto_return] is active.
@export_range(1.0, 360.0, 0.5) var return_speed_deg: float = 25.0

## Delay in seconds after releasing the base before [member auto_return] begins rotating back.
@export_range(0.0, 10.0, 0.05) var return_delay: float = 0.5

## Locks the crane at its maximum angle once 100% progress is reached.
@export var lock_on_complete: bool = false

# --------------------------------------
# EXPORTS: OVERHEAD JIB RAIL
# --------------------------------------
@export_group("Overhead Jib Rail")

## Start offset in meters from the mast center along the jib arm (+Z) where player can hang.
@export var rail_start_offset: float = 4.95:
	set(value):
		rail_start_offset = value
		if is_inside_tree():
			_rebuild_jib_colliders()

## End offset in meters from the mast center along the jib arm (+Z) where player can hang.
@export var rail_end_offset: float = 13.85:
	set(value):
		rail_end_offset = value
		if is_inside_tree():
			_rebuild_jib_colliders()

## Local Y height in meters of the under-slung iron grab rail relative to the rotating pivot.
@export var rail_height: float = 9.75:
	set(value):
		rail_height = value
		if is_inside_tree():
			_rebuild_jib_colliders()

## Vertical offset in meters from the iron grab rail down to the hanging player's origin.
@export var hang_vertical_offset: float = -1.95

## Player traversal speed in meters per second along the overhead jib rail.
@export_range(0.5, 10.0, 0.1) var jib_traverse_speed: float = 3.2

## When true, airborne players entering the jib rail proximity volume auto-grab the bar.
@export var auto_grab_in_air: bool = true

# --------------------------------------
# EXPORTS: BASE CAPSTAN HANDLES
# --------------------------------------
@export_group("Base Capstan Handles")

## Number of radial capstan push-bars around the base of the mast.
@export_range(1, 8, 1) var stick_count: int = 4:
	set(value):
		stick_count = value
		if is_inside_tree():
			_rebuild_capstan_collisions()

## Local Y height in meters of the capstan push-bars relative to the crane origin.
@export var stick_y_offset: float = 1.15:
	set(value):
		stick_y_offset = value
		if is_inside_tree():
			_rebuild_capstan_collisions()

## Radial distance in meters from mast axis to the center of each capstan push-bar collider.
@export var stick_center_distance: float = 1.15:
	set(value):
		stick_center_distance = value
		if is_inside_tree():
			_rebuild_capstan_collisions()

## Length in meters of each capstan push-bar collision box.
@export var stick_radius: float = 1.60:
	set(value):
		stick_radius = value
		if is_inside_tree():
			_rebuild_capstan_collisions()

## Thickness in meters of each capstan push-bar collision box.
@export var stick_thickness: float = 0.22:
	set(value):
		stick_thickness = value
		if is_inside_tree():
			_rebuild_capstan_collisions()

## Radial distance from the mast axis where the player's hands grip a capstan bar.
@export var player_grab_distance: float = 1.35

## Radial distance from the mast axis where the player's body stands while pushing.
@export var player_stand_distance: float = 1.65

## Maximum horizontal distance (m) from the mast axis allowed to attach to the base pushwheel.
@export var max_base_interact_distance: float = 3.20

## Maximum vertical distance (m) from [member stick_y_offset] allowed to attach to the pushwheel.
@export var max_base_vertical_offset: float = 1.50

# --------------------------------------
# EXPORTS: CONNECTIONS & NODES
# --------------------------------------
@export_group("Connections")

## Optional downstream puzzle nodes receiving `power_on`, `power_off`, and `set_progress`.
@export var transmitter_targets: Array[Node3D] = []:
	set(value):
		transmitter_targets = value
		_update_transmitter_targets()

## Optional global event name broadcast via [signal Events.level_event_triggered] at 100% progress.
@export var global_event_name: String = ""

## Child [OutputTransmitter3D] component routing puzzle progress to downstream targets.
@export var transmitter: OutputTransmitter3D

@export_group("Internal Nodes")

## Rotating [AnimatableBody3D] assembly containing the mast, capstan, and jib boom.
@export var wheel: Node3D

## Local rotation axis used by [PushWheelState] (always `Vector3.UP` for vertical-mast crane).
@export var spin_axis: Vector3 = Vector3.UP

# --------------------------------------
# PUBLIC VARIABLES
# --------------------------------------

## Compatibility flag required by [PushWheelState] so the base can be operated immediately.
var is_installed: bool = true

## Compatibility flag tracking whether the crane has locked at 100% completion.
var is_locked: bool = false

## Current yaw angle in degrees around the local Y axis (`spin_axis`).
var current_angle_deg: float = 0.0

## Normalized progress `[0.0, 1.0]` across the clamped angle range `[min_angle_deg, max_angle_deg]`.
var progress: float = 0.0

## Instantaneous angular velocity around Y in radians per second (for player momentum inheritance).
var current_angular_velocity_rad: float = 0.0

## Active [Marker3D] player anchor parented to [member wheel] for [PushWheelState] synchronization.
var current_active_anchor: Marker3D = null

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------

## True while a player is actively pushing the base capstan in [PushWheelState].
var _is_base_pushed: bool = false

## True while a player is actively hanging from the overhead jib in [StateJibCrane].
var _is_jib_mounted: bool = false

## True while the player's interaction scanner is focusing the overhead jib grab rail.
var _is_jib_focused: bool = false

## Countdown timer in seconds before [member auto_return] engages after base release.
var _return_delay_timer: float = 0.0

## Cooldown timer in seconds preventing immediate mid-air re-grab after dismounting the jib.
var _jib_regrab_cooldown: float = 0.0

## Tracks whether the downstream transmitter is currently energized at 100% progress.
var _was_powered_on: bool = false

## Generated capstan stick [CollisionShape3D] instances attached to [_capstan_body].
var _stick_collisions: Array[CollisionShape3D] = []

## Player bodies currently overlapping [_jib_proximity_area] for mid-air auto-grab.
var _overlapping_jib_players: Array[CharacterBody3D] = []

## Cached active viewport [Camera3D] used to orient the floating jib prompt label.
var _cached_camera: Camera3D = null

## Reusable dictionary passed to [PlayerStateMachine] when mounting the base or jib.
var _mount_msg: Dictionary = {}

# --------------------------------------
# ONREADY NODE REFERENCES
# --------------------------------------

## Static base visual [MeshInstance3D] (stone pedestal, never highlighted).
@onready var _base_visual: MeshInstance3D = get_node_or_null("BaseVisual") as MeshInstance3D

## Rotating timber structure visual [MeshInstance3D] (mast, boom, struts; never highlighted).
@onready var _structure_visual: MeshInstance3D = (
	get_node_or_null("PivotBody/CraneStructureVisual") as MeshInstance3D
)

## Rotating capstan handles visual [MeshInstance3D] (highlighted only when focusing pushwheel).
@onready
var _capstan_visual: MeshInstance3D = get_node_or_null("PivotBody/CapstanVisual") as MeshInstance3D

## Rotating iron grab bar visual [MeshInstance3D] (highlighted only when focusing jib bar).
@onready
var _jib_rail_visual: MeshInstance3D = get_node_or_null("PivotBody/JibRailVisual") as MeshInstance3D

## Child [StaticBody3D] carrying the 4 capstan stick collision shapes on Layer 3.
@onready
var _capstan_body: StaticBody3D = get_node_or_null("PivotBody/CapstanGrabBody") as StaticBody3D

## Base [InteractComponent] parented to [_capstan_body] for capstan handle interaction.
@onready var _base_interact: InteractComponent = (
	get_node_or_null("PivotBody/CapstanGrabBody/InteractComponent") as InteractComponent
)

## Base [HighlightComponent] parented to [_capstan_body] highlighting only [_capstan_visual].
@onready var _base_highlight: HighlightComponent = (
	get_node_or_null("PivotBody/CapstanGrabBody/HighlightComponent") as HighlightComponent
)

## Child [StaticBody3D] carrying the overhead jib grab rail collider on Layer 3.
@onready var _jib_grab_body: StaticBody3D = get_node("PivotBody/JibGrabBody") as StaticBody3D

## [CollisionShape3D] spanning the overhead jib grab rail inside [_jib_grab_body].
@onready var _jib_grab_collision: CollisionShape3D = (
	get_node_or_null("PivotBody/JibGrabBody/GrabCollision") as CollisionShape3D
)

## [InteractComponent] attached to [_jib_grab_body] for `[E] GRAB CRANE` focus.
@onready var _jib_interact: InteractComponent = (
	get_node_or_null("PivotBody/JibGrabBody/InteractComponent") as InteractComponent
)

## [HighlightComponent] attached to [_jib_grab_body] highlighting only [_jib_rail_visual].
@onready var _jib_highlight: HighlightComponent = (
	get_node_or_null("PivotBody/JibGrabBody/HighlightComponent") as HighlightComponent
)

## [Area3D] volume along the jib grab rail detecting Layer 2 (Player) mid-air grabs.
@onready var _jib_proximity_area: Area3D = get_node_or_null("PivotBody/JibProximityArea") as Area3D

## [CollisionShape3D] inside [_jib_proximity_area].
@onready var _jib_proximity_collision: CollisionShape3D = (
	get_node_or_null("PivotBody/JibProximityArea/ProximityCollision") as CollisionShape3D
)

## Floating 3D prompt label displayed when focusing the jib grab rail.
@onready var _jib_prompt_label: Label3D = get_node_or_null("PivotBody/JibPromptLabel") as Label3D

## Looping 3D audio player for timber creaking while rotating the crane.
@onready var _rotate_audio: AudioStreamPlayer3D = (
	get_node_or_null("PivotBody/RotateAudio") as AudioStreamPlayer3D
)

## Looping 3D audio player for hand shimmying along the iron jib rail.
@onready var _shimmy_audio: AudioStreamPlayer3D = (
	get_node_or_null("PivotBody/ShimmyAudio") as AudioStreamPlayer3D
)

# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------


## Configures collision masks, scoped highlight targets, anti-climb groups, and signals.
func _ready() -> void:
	_ensure_node_references()
	_rebuild_capstan_collisions()
	_rebuild_jib_colliders()
	_update_transmitter_targets()

	current_angle_deg = _sanitize_angle_deg(initial_angle_deg)
	_sync_progress_from_angle()
	_apply_current_angle_to_visuals()

	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		return

	assert(is_instance_valid(wheel), "TimberJibCrane: Missing 'wheel' (PivotBody) reference.")
	assert(is_instance_valid(_capstan_body), "TimberJibCrane: Missing CapstanGrabBody.")
	assert(is_instance_valid(_base_interact), "TimberJibCrane: Missing base InteractComponent.")
	assert(is_instance_valid(_jib_grab_body), "TimberJibCrane: Missing JibGrabBody.")
	assert(is_instance_valid(_jib_proximity_area), "TimberJibCrane: Missing JibProximityArea.")

	# Allow VaultController to mantle onto the wide top boom while keeping root non-interactable
	if is_in_group(GROUP_NOT_CLIMBABLE):
		remove_from_group(GROUP_NOT_CLIMBABLE)
	if is_in_group(GROUP_INTERACTABLE):
		remove_from_group(GROUP_INTERACTABLE)
	if is_in_group(GROUP_INTERACTABLES):
		remove_from_group(GROUP_INTERACTABLES)

	collision_layer = CollisionLayers.MASK_ENVIRONMENT
	collision_mask = CollisionLayers.MASK_PLAYER

	if wheel.is_in_group(GROUP_NOT_CLIMBABLE):
		wheel.remove_from_group(GROUP_NOT_CLIMBABLE)
	var wheel_col: CollisionObject3D = wheel as CollisionObject3D
	if is_instance_valid(wheel_col):
		wheel_col.collision_layer = CollisionLayers.MASK_ENVIRONMENT
		wheel_col.collision_mask = CollisionLayers.MASK_PLAYER

	if is_instance_valid(_capstan_body):
		_capstan_body.add_to_group(GROUP_INTERACTABLE)
		_capstan_body.add_to_group(GROUP_INTERACTABLES)
		_capstan_body.add_to_group(GROUP_NOT_CLIMBABLE)
		_capstan_body.collision_layer = (
			CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_INTERACTIVE
		)
		_capstan_body.collision_mask = CollisionLayers.MASK_PLAYER
		_capstan_body.set_meta(&"display_name", "Crane Capstan Wheel")

	if is_instance_valid(_jib_grab_body):
		_jib_grab_body.add_to_group(GROUP_INTERACTABLE)
		_jib_grab_body.add_to_group(GROUP_INTERACTABLES)
		_jib_grab_body.add_to_group(GROUP_NOT_CLIMBABLE)
		_jib_grab_body.collision_layer = CollisionLayers.MASK_INTERACTIVE
		_jib_grab_body.collision_mask = CollisionLayers.MASK_NONE
		_jib_grab_body.set_meta(&"display_name", "Crane Jib Bar")

	_configure_scoped_highlights()

	if is_instance_valid(_jib_proximity_area):
		_jib_proximity_area.collision_layer = CollisionLayers.MASK_NONE
		_jib_proximity_area.collision_mask = CollisionLayers.MASK_PLAYER
		_jib_proximity_area.monitorable = false

	_configure_jib_prompt_text()
	if is_instance_valid(_jib_prompt_label):
		_jib_prompt_label.hide()

	if is_instance_valid(_base_interact):
		Utilities.safe_connect(_base_interact.focused, _on_base_focused)
		Utilities.safe_connect(_base_interact.unfocused, _on_base_unfocused)
		Utilities.safe_connect(_base_interact.interacted, _on_base_interacted)

	if is_instance_valid(_jib_interact):
		Utilities.safe_connect(_jib_interact.focused, _on_jib_focused)
		Utilities.safe_connect(_jib_interact.unfocused, _on_jib_unfocused)
		Utilities.safe_connect(_jib_interact.interacted, _on_jib_interacted)

	if is_instance_valid(_jib_proximity_area):
		Utilities.safe_connect(_jib_proximity_area.body_entered, _on_jib_proximity_body_entered)
		Utilities.safe_connect(_jib_proximity_area.body_exited, _on_jib_proximity_body_exited)

	set_physics_process(false)
	_update_process_state()


## Clears collision exceptions when removed from the scene tree.
func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(_jib_grab_body):
		for p: CharacterBody3D in _overlapping_jib_players:
			if is_instance_valid(p):
				_jib_grab_body.remove_collision_exception_with(p)
	_overlapping_jib_players.clear()


## Processes auto-return rotation, mid-air jib auto-grab, and prompt placement.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return

	var prev_angle: float = current_angle_deg

	if _jib_regrab_cooldown > 0.0:
		_jib_regrab_cooldown = maxf(0.0, _jib_regrab_cooldown - delta)

	if (
		auto_return
		and not _is_base_pushed
		and not is_locked
		and not is_equal_approx(current_angle_deg, initial_angle_deg)
	):
		if _return_delay_timer > 0.0:
			_return_delay_timer = maxf(0.0, _return_delay_timer - delta)
		else:
			current_angle_deg = move_toward(
				current_angle_deg, initial_angle_deg, return_speed_deg * delta
			)
			current_angle_deg = _sanitize_angle_deg(current_angle_deg)
			_sync_progress_from_angle()
			_apply_current_angle_to_visuals()
			_emit_angle_and_power_updates()

	var deg_delta: float = current_angle_deg - prev_angle
	var dir_sign: float = -1.0 if turn_clockwise else 1.0
	if delta > 0.0001 and not is_zero_approx(deg_delta):
		current_angular_velocity_rad = deg_to_rad(deg_delta * dir_sign) / delta
		_set_rotate_audio_playing(true)
	else:
		current_angular_velocity_rad = 0.0
		if not _is_base_pushed:
			_set_rotate_audio_playing(false)

	if auto_grab_in_air and not _is_jib_mounted and _jib_regrab_cooldown <= 0.0:
		_poll_overlapping_air_grab()

	if _is_jib_focused and not _is_jib_mounted:
		_update_jib_prompt_position()

	_update_process_state()


# --------------------------------------
# PUBLIC API: BASE CAPSTAN (PushWheelState)
# --------------------------------------


## Checks whether [param player_node] is close enough to the base capstan handles to operate them.
func is_player_near_capstan(player_node: Node3D) -> bool:
	if not is_instance_valid(player_node):
		return false
	var pivot_pos: Vector3 = wheel.global_position if is_instance_valid(wheel) else global_position
	var player_pos: Vector3 = player_node.global_position
	var dx: float = player_pos.x - pivot_pos.x
	var dz: float = player_pos.z - pivot_pos.z
	var horiz_dist_sq: float = (dx * dx) + (dz * dz)
	if horiz_dist_sq > (max_base_interact_distance * max_base_interact_distance):
		return false
	var capstan_world_y: float = pivot_pos.y + stick_y_offset
	var player_waist_y: float = player_pos.y + 0.9
	if absf(player_waist_y - capstan_world_y) > max_base_vertical_offset:
		return false
	return true


## Called by [PushWheelState] when [param _player] attaches to a base capstan handle.
func on_push_started(_player: Node3D = null) -> void:
	print("TimberJibCrane: Base capstan push started.")
	_is_base_pushed = true
	_return_delay_timer = return_delay
	if is_instance_valid(_base_highlight):
		_base_highlight.suppress(true)
	_update_process_state()


## Called by [PushWheelState] when [param _player] releases the base capstan handle.
func on_push_ended(_player: Node3D = null) -> void:
	print("TimberJibCrane: Base capstan push ended.")
	_is_base_pushed = false
	_return_delay_timer = return_delay
	current_angular_velocity_rad = 0.0
	_set_rotate_audio_playing(false)
	if is_instance_valid(_base_highlight):
		_base_highlight.suppress(false)
	_update_process_state()


## Advances the crane rotation when pushed from the base for [param delta] seconds.
func push(delta: float) -> void:
	if is_locked or seconds_for_full_rotation <= 0.0:
		current_angular_velocity_rad = 0.0
		return

	var prev_angle: float = current_angle_deg
	var deg_per_sec: float = 360.0 / seconds_for_full_rotation
	current_angle_deg = _sanitize_angle_deg(current_angle_deg + (deg_per_sec * delta))
	_return_delay_timer = return_delay

	var actual_deg_delta: float = current_angle_deg - prev_angle
	var dir_sign: float = -1.0 if turn_clockwise else 1.0
	if delta > 0.0001 and not is_zero_approx(actual_deg_delta):
		current_angular_velocity_rad = deg_to_rad(actual_deg_delta * dir_sign) / delta
		_set_rotate_audio_playing(true)
	else:
		current_angular_velocity_rad = 0.0
		_set_rotate_audio_playing(false)

	_sync_progress_from_angle()
	_apply_current_angle_to_visuals()
	_emit_angle_and_power_updates()

	if limit_rotation and is_equal_approx(progress, 1.0) and lock_on_complete:
		_lock_crane()


# --------------------------------------
# PUBLIC API: OVERHEAD JIB RAIL (StateJibCrane)
# --------------------------------------


## Clamps a 1D offset in meters to `[rail_start_offset, rail_end_offset]`.
func clamp_rail_offset(offset: float) -> float:
	var low: float = minf(rail_start_offset, rail_end_offset)
	var high: float = maxf(rail_start_offset, rail_end_offset)
	return clampf(offset, low, high)


## Projects a world-space position onto the jib grab rail and returns clamped offset.
func project_world_pos_to_rail_offset(world_pos: Vector3) -> float:
	if not is_instance_valid(wheel):
		return clamp_rail_offset(rail_start_offset)
	var local_pt: Vector3 = wheel.to_local(world_pos)
	return clamp_rail_offset(local_pt.z)


## Returns the world-space position on the jib grab rail at [param offset] meters.
func get_rail_world_position(offset: float) -> Vector3:
	var clamped: float = clamp_rail_offset(offset)
	var local_pt: Vector3 = Vector3(0.0, rail_height, clamped)
	if is_instance_valid(wheel):
		return wheel.to_global(local_pt)
	return to_global(local_pt)


## Returns the horizontal world-space unit vector pointing from mast toward jib tip.
func get_rail_world_direction() -> Vector3:
	if is_instance_valid(wheel):
		var dir: Vector3 = wheel.global_transform.basis.z
		var flat: Vector3 = Vector3(dir.x, 0.0, dir.z)
		if flat.length_squared() > 0.0001:
			return flat.normalized()
	return global_transform.basis.z.normalized()


## Returns the instantaneous tangential world velocity (m/s) at [param offset] on the rail.
func get_rail_point_velocity(offset: float) -> Vector3:
	if is_zero_approx(current_angular_velocity_rad) or not is_instance_valid(wheel):
		return Vector3.ZERO
	var world_pt: Vector3 = get_rail_world_position(offset)
	var radial_vec: Vector3 = world_pt - wheel.global_position
	radial_vec.y = 0.0
	var omega_vec: Vector3 = Vector3.UP * current_angular_velocity_rad
	return omega_vec.cross(radial_vec)


## Returns the current global yaw angle in radians of the rotating pivot body.
func get_pivot_global_yaw_rad() -> float:
	if is_instance_valid(wheel):
		return wheel.global_rotation.y
	return global_rotation.y


## Registers that [param p_player] has mounted the overhead jib grab rail.
func notify_jib_player_mounted(p_player: CharacterBody3D) -> void:
	_is_jib_mounted = true
	if is_instance_valid(_jib_prompt_label):
		_jib_prompt_label.hide()
	if is_instance_valid(_jib_highlight):
		_jib_highlight.suppress(true)
	_update_process_state()
	jib_player_mounted.emit(p_player)


## Registers that [param p_player] has dismounted from the overhead jib grab rail.
func notify_jib_player_dismounted(p_player: CharacterBody3D, cooldown: float = 0.45) -> void:
	_is_jib_mounted = false
	_jib_regrab_cooldown = maxf(0.0, cooldown)
	set_shimmy_audio(false)
	if is_instance_valid(_jib_highlight):
		_jib_highlight.suppress(false)
	_update_process_state()
	jib_player_dismounted.emit(p_player)


## Toggles looping hand-shimmy audio playback while traversing the jib rail.
func set_shimmy_audio(is_shimmying: bool) -> void:
	if not is_instance_valid(_shimmy_audio) or _shimmy_audio.stream == null:
		return
	if is_shimmying and not _shimmy_audio.playing:
		_shimmy_audio.play()
	elif not is_shimmying and _shimmy_audio.playing:
		_shimmy_audio.stop()


# --------------------------------------
# PRIVATE METHODS: COLLIDERS & VISUALS
# --------------------------------------


## Resolves child node references required in both editor and runtime.
func _ensure_node_references() -> void:
	if not is_instance_valid(wheel):
		wheel = get_node_or_null("PivotBody") as AnimatableBody3D
	if not is_instance_valid(_base_visual):
		_base_visual = get_node_or_null("BaseVisual") as MeshInstance3D
	if not is_instance_valid(_structure_visual):
		_structure_visual = get_node_or_null("PivotBody/CraneStructureVisual") as MeshInstance3D
	if not is_instance_valid(_capstan_visual):
		_capstan_visual = get_node_or_null("PivotBody/CapstanVisual") as MeshInstance3D
	if not is_instance_valid(_jib_rail_visual):
		_jib_rail_visual = get_node_or_null("PivotBody/JibRailVisual") as MeshInstance3D
	if not is_instance_valid(_capstan_body):
		_capstan_body = get_node_or_null("PivotBody/CapstanGrabBody") as StaticBody3D
	if not is_instance_valid(_base_interact):
		_base_interact = (
			get_node_or_null("PivotBody/CapstanGrabBody/InteractComponent") as InteractComponent
		)
	if not is_instance_valid(_base_highlight):
		_base_highlight = (
			get_node_or_null("PivotBody/CapstanGrabBody/HighlightComponent") as HighlightComponent
		)
	if not is_instance_valid(_jib_grab_body):
		_jib_grab_body = get_node_or_null("PivotBody/JibGrabBody") as StaticBody3D
	if not is_instance_valid(_jib_grab_collision):
		_jib_grab_collision = (
			get_node_or_null("PivotBody/JibGrabBody/GrabCollision") as CollisionShape3D
		)
	if not is_instance_valid(_jib_interact):
		_jib_interact = (
			get_node_or_null("PivotBody/JibGrabBody/InteractComponent") as InteractComponent
		)
	if not is_instance_valid(_jib_highlight):
		_jib_highlight = (
			get_node_or_null("PivotBody/JibGrabBody/HighlightComponent") as HighlightComponent
		)
	if not is_instance_valid(_jib_proximity_area):
		_jib_proximity_area = get_node_or_null("PivotBody/JibProximityArea") as Area3D
	if not is_instance_valid(_jib_proximity_collision):
		_jib_proximity_collision = (
			get_node_or_null("PivotBody/JibProximityArea/ProximityCollision") as CollisionShape3D
		)
	if not is_instance_valid(_jib_prompt_label):
		_jib_prompt_label = get_node_or_null("PivotBody/JibPromptLabel") as Label3D
	if not is_instance_valid(_rotate_audio):
		_rotate_audio = get_node_or_null("PivotBody/RotateAudio") as AudioStreamPlayer3D
	if not is_instance_valid(_shimmy_audio):
		_shimmy_audio = get_node_or_null("PivotBody/ShimmyAudio") as AudioStreamPlayer3D


## Restricts [HighlightComponent] target meshes strictly to capstan handles and jib grab bar.
func _configure_scoped_highlights() -> void:
	if is_instance_valid(_base_highlight) and is_instance_valid(_capstan_visual):
		var capstan_targets: Array[GeometryInstance3D] = [_capstan_visual]
		_base_highlight.target_meshes = capstan_targets
		_base_highlight._cache_target_meshes()

	if is_instance_valid(_jib_highlight) and is_instance_valid(_jib_rail_visual):
		var rail_targets: Array[GeometryInstance3D] = [_jib_rail_visual]
		_jib_highlight.target_meshes = rail_targets
		_jib_highlight._cache_target_meshes()


## Generates box collision shapes for the radial capstan handles at the mast base.
func _rebuild_capstan_collisions() -> void:
	_ensure_node_references()
	var parent_body: Node3D = _capstan_body if is_instance_valid(_capstan_body) else wheel
	if not is_instance_valid(parent_body):
		return

	for col: CollisionShape3D in _stick_collisions:
		if is_instance_valid(col):
			col.queue_free()
	_stick_collisions.clear()

	if Engine.is_editor_hint():
		return

	var count_bound: int = maxi(1, stick_count)
	var angle_step: float = TAU / float(count_bound)

	for i: int in range(count_bound):
		var col: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(stick_radius, stick_thickness, stick_thickness)
		col.shape = box

		var angle: float = float(i) * angle_step
		var stick_dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		col.position = stick_dir * stick_center_distance
		col.position.y = stick_y_offset
		col.rotation.y = -angle

		parent_body.add_child(col)
		_stick_collisions.append(col)


## Updates the overhead jib grab rail and proximity trigger collision shapes.
func _rebuild_jib_colliders() -> void:
	_ensure_node_references()
	var low: float = minf(rail_start_offset, rail_end_offset)
	var high: float = maxf(rail_start_offset, rail_end_offset)
	var span: float = maxf(0.5, high - low)
	var mid_z: float = (low + high) * 0.5

	if is_instance_valid(_jib_grab_collision):
		var grab_box: BoxShape3D = _jib_grab_collision.shape as BoxShape3D
		if not is_instance_valid(grab_box):
			grab_box = BoxShape3D.new()
			_jib_grab_collision.shape = grab_box
		grab_box.size = Vector3(0.65, 0.85, span)
		_jib_grab_collision.position = Vector3(0.0, rail_height - 0.15, mid_z)

	if is_instance_valid(_jib_proximity_collision):
		var prox_box: BoxShape3D = _jib_proximity_collision.shape as BoxShape3D
		if not is_instance_valid(prox_box):
			prox_box = BoxShape3D.new()
			_jib_proximity_collision.shape = prox_box
		prox_box.size = Vector3(1.50, 1.75, span + 0.40)
		_jib_proximity_collision.position = Vector3(0.0, rail_height - 0.55, mid_z)


## Applies [member current_angle_deg] to the rotating pivot assembly (`wheel`).
func _apply_current_angle_to_visuals() -> void:
	if not is_instance_valid(wheel):
		return
	var dir_sign: float = -1.0 if turn_clockwise else 1.0
	wheel.rotation_degrees = Vector3(0.0, current_angle_deg * dir_sign, 0.0)


## Clamps or normalizes [param raw_deg] according to [member limit_rotation].
func _sanitize_angle_deg(raw_deg: float) -> float:
	if limit_rotation:
		var low: float = minf(min_angle_deg, max_angle_deg)
		var high: float = maxf(min_angle_deg, max_angle_deg)
		return clampf(raw_deg, low, high)
	return raw_deg


## Computes normalized [member progress] in `[0.0, 1.0]` from [member current_angle_deg].
func _sync_progress_from_angle() -> void:
	if limit_rotation:
		var span: float = max_angle_deg - min_angle_deg
		if absf(span) > 0.001:
			progress = clampf((current_angle_deg - min_angle_deg) / span, 0.0, 1.0)
		else:
			progress = 0.0
	else:
		progress = fposmod(current_angle_deg, 360.0) / 360.0


## Emits [signal angle_changed], updates [member transmitter], and broadcasts power state.
func _emit_angle_and_power_updates() -> void:
	angle_changed.emit(current_angle_deg, progress)

	for target: Node3D in transmitter_targets:
		if is_instance_valid(target) and target.has_method(&"set_progress"):
			target.call(&"set_progress", progress)

	if not limit_rotation:
		return

	var is_now_powered: bool = is_equal_approx(progress, 1.0)
	if is_now_powered and not _was_powered_on:
		_was_powered_on = true
		powered_on.emit()
		if is_instance_valid(transmitter):
			transmitter.power_on()
		if not global_event_name.is_empty() and is_instance_valid(Events):
			Events.level_event_triggered.emit(global_event_name, true)
	elif not is_now_powered and _was_powered_on:
		_was_powered_on = false
		powered_off.emit()
		if is_instance_valid(transmitter):
			transmitter.power_off()
		if not global_event_name.is_empty() and is_instance_valid(Events):
			Events.level_event_triggered.emit(global_event_name, false)


## Permanently locks the crane at 100% completion when [member lock_on_complete] is enabled.
func _lock_crane() -> void:
	is_locked = true
	if is_instance_valid(_base_interact):
		_base_interact.is_enabled = false
	if is_instance_valid(_base_highlight):
		_base_highlight.suppress(true)


## Syncs [member transmitter_targets] into the child [OutputTransmitter3D].
func _update_transmitter_targets() -> void:
	if not is_instance_valid(transmitter):
		transmitter = get_node_or_null("OutputTransmitter3D") as OutputTransmitter3D
	if is_instance_valid(transmitter):
		transmitter.targets = transmitter_targets


# --------------------------------------
# PRIVATE METHODS: INTERACTION & GATING
# --------------------------------------


## Enables or disables `_process` based on active return, focus, or overlap state.
func _update_process_state() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return

	var needs_auto_return: bool = (
		auto_return
		and not _is_base_pushed
		and not is_locked
		and not is_equal_approx(current_angle_deg, initial_angle_deg)
	)
	var needs_air_grab: bool = (
		auto_grab_in_air and not _is_jib_mounted and not _overlapping_jib_players.is_empty()
	)
	var needs_prompt_follow: bool = _is_jib_focused and not _is_jib_mounted
	var needs_cooldown: bool = _jib_regrab_cooldown > 0.0
	var needs_velocity_decay: bool = not is_zero_approx(current_angular_velocity_rad)

	set_process(
		(
			needs_auto_return
			or needs_air_grab
			or needs_prompt_follow
			or needs_cooldown
			or needs_velocity_decay
		)
	)


## Handles focus on the base capstan handles, suppressing highlight if player is out of reach.
func _on_base_focused() -> void:
	if not is_instance_valid(_base_highlight):
		return
	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if not players.is_empty() and players[0] is Node3D:
		var p_node: Node3D = players[0] as Node3D
		_base_highlight.suppress(_is_base_pushed or not is_player_near_capstan(p_node))


## Restores base highlight state on unfocus.
func _on_base_unfocused() -> void:
	if is_instance_valid(_base_highlight):
		_base_highlight.suppress(_is_base_pushed)


## Handles player `[E]` interaction with the base capstan handles to enter [PushWheelState].
func _on_base_interacted(player_node: Node3D) -> void:
	if is_locked or not is_instance_valid(player_node):
		return
	if not is_player_near_capstan(player_node):
		print("TimberJibCrane: Player too far from base capstan handles to attach.")
		return

	var sm: Node = player_node.get_node_or_null("StateMachine")
	if not is_instance_valid(sm) or not sm.has_method(&"transition_to"):
		return

	var stand_marker: Marker3D = _get_dynamic_closest_capstan_anchor(player_node.global_position)
	if not is_instance_valid(stand_marker):
		return

	current_active_anchor = stand_marker
	_mount_msg.clear()
	_mount_msg[KEY_WHEEL] = self
	_mount_msg[KEY_TARGET_TRANSFORM] = stand_marker.global_transform
	sm.call(&"transition_to", STATE_PUSH_WHEEL, _mount_msg)


## Dynamically creates/updates the player [Marker3D] anchor on the closest capstan bar.
func _get_dynamic_closest_capstan_anchor(player_pos: Vector3) -> Marker3D:
	if not is_instance_valid(wheel):
		return null

	var count_bound: int = maxi(1, stick_count)
	var angle_step: float = TAU / float(count_bound)
	var best_idx: int = 0
	var min_dist_sq: float = INF

	for i: int in range(count_bound):
		var angle: float = float(i) * angle_step
		var local_dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var local_pt: Vector3 = (
			(local_dir * player_grab_distance) + Vector3(0.0, stick_y_offset, 0.0)
		)
		var world_pt: Vector3 = wheel.to_global(local_pt)
		var dist_sq: float = player_pos.distance_squared_to(world_pt)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			best_idx = i

	var best_angle: float = float(best_idx) * angle_step
	var stick_dir: Vector3 = Vector3(cos(best_angle), 0.0, sin(best_angle))
	var push_tangent: Vector3 = stick_dir.cross(Vector3.UP).normalized()
	if not turn_clockwise:
		push_tangent = -push_tangent

	var grab_marker: Marker3D = wheel.get_node_or_null("CapstanGrabMarker") as Marker3D
	if not is_instance_valid(grab_marker):
		grab_marker = Marker3D.new()
		grab_marker.name = "CapstanGrabMarker"
		wheel.add_child(grab_marker)

	var stand_marker: Marker3D = wheel.get_node_or_null("CapstanStandMarker") as Marker3D
	if not is_instance_valid(stand_marker):
		stand_marker = Marker3D.new()
		stand_marker.name = "CapstanStandMarker"
		wheel.add_child(stand_marker)

	grab_marker.position = (stick_dir * player_grab_distance) + Vector3(0.0, stick_y_offset, 0.0)
	var stand_offset: Vector3 = (
		(stick_dir * player_stand_distance)
		- (push_tangent * 0.55)
		+ Vector3(0.0, BASE_SURFACE_Y, 0.0)
	)
	stand_marker.position = stand_offset
	stand_marker.basis = Basis.looking_at(push_tangent, Vector3.UP)

	return stand_marker


## Shows the floating `[E] GRAB CRANE` prompt when focusing the overhead jib grab rail.
func _on_jib_focused() -> void:
	if _is_jib_mounted:
		return
	_is_jib_focused = true
	_configure_jib_prompt_text()
	_update_jib_prompt_position()
	if is_instance_valid(_jib_prompt_label):
		_jib_prompt_label.show()
	_update_process_state()


## Hides the floating `[E] GRAB CRANE` prompt when unfocusing the overhead jib grab rail.
func _on_jib_unfocused() -> void:
	_is_jib_focused = false
	if is_instance_valid(_jib_prompt_label):
		_jib_prompt_label.hide()
	_update_process_state()


## Mounts the player onto the overhead jib grab rail when `[E]` is pressed on [_jib_grab_body].
func _on_jib_interacted(player_node: Node3D) -> void:
	if _is_jib_mounted or not (player_node is CharacterBody3D):
		return
	_mount_player_on_jib(player_node as CharacterBody3D)


## Tracks player bodies entering the jib rail proximity volume for mid-air auto-grab.
func _on_jib_proximity_body_entered(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	var p: CharacterBody3D = body as CharacterBody3D
	if not _overlapping_jib_players.has(p):
		_overlapping_jib_players.append(p)
		if is_instance_valid(_jib_grab_body):
			_jib_grab_body.add_collision_exception_with(p)

	if auto_grab_in_air and not _is_jib_mounted and _jib_regrab_cooldown <= 0.0:
		if _should_air_grab_jib(p):
			_mount_player_on_jib(p)
			return

	_update_process_state()


## Removes player bodies exiting the jib rail proximity volume.
func _on_jib_proximity_body_exited(body: Node3D) -> void:
	if not (body is CharacterBody3D):
		return
	var p: CharacterBody3D = body as CharacterBody3D
	_overlapping_jib_players.erase(p)
	if is_instance_valid(_jib_grab_body):
		_jib_grab_body.remove_collision_exception_with(p)
	_update_process_state()


## Polls overlapping players in the jib proximity volume to trigger mid-air auto-grab.
func _poll_overlapping_air_grab() -> void:
	for i: int in range(_overlapping_jib_players.size() - 1, -1, -1):
		var p: CharacterBody3D = _overlapping_jib_players[i]
		if not is_instance_valid(p):
			_overlapping_jib_players.remove_at(i)
			continue
		if _should_air_grab_jib(p):
			_mount_player_on_jib(p)
			return


## Returns true if [param p] is airborne below the bar and eligible to auto-grab the jib rail.
func _should_air_grab_jib(p: CharacterBody3D) -> bool:
	if not is_instance_valid(p) or p.is_on_floor():
		return false
	if p is Player:
		var pl: Player = p as Player
		if pl.is_dead or not is_instance_valid(pl.state_machine):
			return false
		if (
			pl.state_machine.is_in_state(STATE_JIB_CRANE)
			or pl.state_machine.is_in_state(STATE_PUSH_WHEEL)
			or pl.state_machine.is_in_state(STATE_ROPE)
		):
			return false

	var offset: float = project_world_pos_to_rail_offset(p.global_position)
	var rail_pt: Vector3 = get_rail_world_position(offset)
	# Reject grab if player feet are above the rail so player never climbs on top of boom
	if p.global_position.y > rail_pt.y - 0.35:
		return false
	var hand_pos: Vector3 = p.global_position + Vector3(0.0, 1.35, 0.0)
	return hand_pos.distance_squared_to(rail_pt) <= 1.55


## Transitions [param p] into [StateJibCrane] at the closest projected point on the jib rail.
func _mount_player_on_jib(p: CharacterBody3D) -> void:
	var sm: Node = p.get_node_or_null("StateMachine")
	if not is_instance_valid(sm) or not sm.has_method(&"transition_to"):
		return

	var offset: float = project_world_pos_to_rail_offset(p.global_position)
	_mount_msg.clear()
	_mount_msg[KEY_CRANE] = self
	_mount_msg[KEY_RAIL_OFFSET] = offset
	sm.call(&"transition_to", STATE_JIB_CRANE, _mount_msg)


## Positions the floating `[E] GRAB CRANE` prompt along the jib rail near the camera look point.
func _update_jib_prompt_position() -> void:
	if not is_instance_valid(_jib_prompt_label):
		return
	if not is_instance_valid(_cached_camera) or not _cached_camera.is_current():
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_cached_camera = vp.get_camera_3d()
	if not is_instance_valid(_cached_camera):
		return

	var cam_pos: Vector3 = _cached_camera.global_position
	var offset: float = project_world_pos_to_rail_offset(cam_pos)
	var rail_pt: Vector3 = get_rail_world_position(offset)
	var to_cam: Vector3 = cam_pos - rail_pt
	var pull_dir: Vector3 = to_cam.normalized() if to_cam.length_squared() > 0.001 else Vector3.UP
	_jib_prompt_label.global_position = (rail_pt + (pull_dir * 0.35) + Vector3(0.0, -0.18, 0.0))


## Formats the floating jib prompt label with the current bound key for `interact`.
func _configure_jib_prompt_text() -> void:
	if not is_instance_valid(_jib_prompt_label):
		return
	var key_str: String = "E"
	var events: Array[InputEvent] = InputMap.action_get_events(&"interact")
	for ev: InputEvent in events:
		if ev is InputEventKey:
			var key_ev: InputEventKey = ev as InputEventKey
			var code: Key = (
				key_ev.physical_keycode if key_ev.physical_keycode != KEY_NONE else key_ev.keycode
			)
			var label: String = OS.get_keycode_string(code)
			if not label.is_empty():
				key_str = label.to_upper()
				break
	_jib_prompt_label.text = "[" + key_str + "] GRAB CRANE"


## Controls looping timber creak audio playback during rotation.
func _set_rotate_audio_playing(should_play: bool) -> void:
	if not is_instance_valid(_rotate_audio) or _rotate_audio.stream == null:
		return
	if should_play and not _rotate_audio.playing:
		_rotate_audio.play()
	elif not should_play and _rotate_audio.playing:
		_rotate_audio.stop()
