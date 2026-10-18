@tool
## Climbable chain and swingable Verlet rope with analytic pendulum handoff.
class_name ClimbRope3D
extends Node3D

# --------------------------------------
# ENUMS
# --------------------------------------

## Operating mode determining visual geometry and player locomotion behavior.
enum Mode {
	CHAIN,
	SWING,
}

# --------------------------------------
# CONSTANTS
# --------------------------------------

## 3D Physics Layer 3 bitmask (Interactive) for crosshair shapecast detection.
const PHYS_LAYER_INTERACTIVE: int = 4

## 3D Physics Layer 2 bitmask (Player) for mid-air proximity detection.
const PHYS_MASK_PLAYER: int = 2

## Minimum grab distance in meters below the anchor to prevent head clipping.
const MIN_GRAB_OFFSET: float = 1.0

## Bottom margin in meters kept above the tip of the rope or chain.
const BOTTOM_GRAB_MARGIN: float = 0.25

## Default per-rope cooldown in seconds before the same rope can be re-grabbed.
const DEFAULT_REGRAB_COOLDOWN: float = 0.4

## Radius in meters of the proximity cylinder used for mid-air auto-grab.
const AIR_GRAB_RADIUS: float = 0.65

## Minimum horizontal approach speed (m/s) toward the rope axis for mid-air grab.
const AIR_APPROACH_MIN_SPEED: float = 0.35

## Radius in meters of the static cylinder used for crosshair raycast focus.
const GRAB_BODY_RADIUS: float = 0.14

## Vertical center-to-center pitch in meters between procedural chain links.
const CHAIN_LINK_PITCH: float = 0.12

## Outer vertical length in meters of a single procedural oval chain link.
const CHAIN_LINK_LENGTH: float = 0.20

## Outer horizontal width in meters of a single procedural oval chain link.
const CHAIN_LINK_WIDTH: float = 0.11

## Tube wire radius in meters of a single procedural oval chain link.
const CHAIN_WIRE_RADIUS: float = 0.020

## Rest length in meters between consecutive Verlet points in swing mode.
const ROPE_SEGMENT_LEN: float = 0.25

## Visual cylinder radius in meters of the swingable rope mesh.
const ROPE_RADIUS: float = 0.028

## Downward gravity acceleration (m/s^2) applied to free Verlet rope points.
const VERLET_GRAVITY: float = 18.0

## Velocity retention factor per frame when the Verlet rope swings freely.
const VERLET_DAMPING: float = 0.985

## Velocity retention factor per frame while pinned to the player's hands.
const VERLET_PINNED_DAMPING: float = 0.92

## Distance constraint relaxation iterations executed per frame in swing mode.
const VERLET_ITERATIONS: int = 8

## Squared displacement threshold below which a Verlet step counts as settled.
const VERLET_SLEEP_EPSILON_SQ: float = 0.000004

## Consecutive settled frames required before the Verlet strand goes to sleep.
const VERLET_SLEEP_FRAMES: int = 30

## Squared camera distance (30m) beyond which idle visual updates are skipped.
const CULL_DISTANCE_SQUARED: float = 900.0

## Horizontal camera-right offset in meters for the floating interaction prompt.
const LABEL_OFFSET_RIGHT: float = 0.35

## Vertical camera-up offset in meters for the floating interaction prompt.
const LABEL_OFFSET_UP: float = 0.10

## Minimum swing speed (m/s) required to make the swing whoosh loop audible.
const SWING_AUDIO_MIN_SPEED: float = 1.2

## Swing speed (m/s) at which the swing whoosh loop reaches maximum volume.
const SWING_AUDIO_MAX_SPEED: float = 10.0

## Minimum volume in decibels for the swing whoosh audio player.
const SWING_AUDIO_MIN_DB: float = -24.0

## Maximum volume in decibels for the swing whoosh audio player.
const SWING_AUDIO_MAX_DB: float = -2.0

## Target player state name entered when mounting a rope or chain.
const STATE_ROPE: StringName = &"Rope"

## Transition dictionary key holding the [ClimbRope3D] reference.
const KEY_ROPE: StringName = &"rope"

## Transition dictionary key holding the initial grab distance below the anchor.
const KEY_GRAB_DISTANCE: StringName = &"grab_distance"

## Input action name queried to format the interaction prompt label.
const ACTION_INTERACT: StringName = &"interact"

# --------------------------------------
# STATIC CACHES
# --------------------------------------

## Shared procedural oval chain link mesh built once across all instances.
static var _cached_chain_mesh: ArrayMesh = null

## Shared unit-height cylinder mesh built once for swing rope segments.
static var _cached_rope_mesh: CylinderMesh = null

## Shared fallback dark-iron material for chain links.
static var _default_chain_material: StandardMaterial3D = null

## Shared fallback braided-hemp material for swing ropes.
static var _default_rope_material: StandardMaterial3D = null

# --------------------------------------
# EXPORTS
# --------------------------------------

@export_category("Rope Configuration")

## Selects rigid procedural chain climbing or dynamic pendulum rope swinging.
@export var mode: Mode = Mode.CHAIN:
	set(value):
		mode = value
		if is_instance_valid(self) and is_inside_tree():
			_rebuild_rope()

## Total vertical length in meters hanging below the node origin anchor.
@export_range(2.0, 30.0, 0.1) var length: float = 6.0:
	set(value):
		length = clampf(value, 2.0, 30.0)
		if is_instance_valid(self) and is_inside_tree():
			_rebuild_rope()

@export_category("Visual Materials")

## Optional custom material applied to procedural chain links in CHAIN mode.
@export var chain_material: Material:
	set(value):
		chain_material = value
		if is_instance_valid(self) and is_inside_tree():
			_apply_active_material()

## Optional custom material applied to cylinder segments in SWING mode.
@export var rope_material: Material:
	set(value):
		rope_material = value
		if is_instance_valid(self) and is_inside_tree():
			_apply_active_material()

@export_category("Audio Streams")

## Looping sound effect played while actively climbing up or down.
@export var climb_stream: AudioStream:
	set(value):
		climb_stream = value
		if is_instance_valid(self) and is_inside_tree() and is_instance_valid(_climb_audio):
			_climb_audio.stream = climb_stream

## Looping sound effect played during fast downward sliding.
@export var slide_stream: AudioStream:
	set(value):
		slide_stream = value
		if is_instance_valid(self) and is_inside_tree() and is_instance_valid(_slide_audio):
			_slide_audio.stream = slide_stream

## Looping whoosh sound effect modulated by pendulum speed in SWING mode.
@export var swing_stream: AudioStream:
	set(value):
		swing_stream = value
		if is_instance_valid(self) and is_inside_tree() and is_instance_valid(_swing_audio):
			_swing_audio.stream = swing_stream

# --------------------------------------
# PUBLIC VARIABLES
# --------------------------------------

## Human-readable name announced by the interaction scanner on crosshair focus.
var display_name: String = "Climbable Rope"

# --------------------------------------
# PRIVATE VARIABLES
# --------------------------------------

## World-space current positions of the Verlet rope nodes in SWING mode.
var _verlet_pos: PackedVector3Array = PackedVector3Array()

## World-space previous positions of the Verlet rope nodes in SWING mode.
var _verlet_prev: PackedVector3Array = PackedVector3Array()

## True while a player is actively mounted on this rope instance.
var _is_player_attached: bool = false

## True while the Verlet strand has an active hand pin constraint.
var _has_hand_point: bool = false

## World-space position of the mounted player's hand grip point.
var _hand_world_pos: Vector3 = Vector3.ZERO

## Distance in meters along the rope from the anchor to the hand grip point.
var _hand_grab_distance: float = 2.0

## True while the Verlet strand is moving and requires per-frame simulation.
var _is_verlet_awake: bool = false

## Consecutive frames where Verlet point motion remained below sleep epsilon.
var _settled_frames: int = 0

## True while the player's crosshair is focusing this rope's interact component.
var _is_focused: bool = false

## Remaining cooldown time in seconds before re-attachment is permitted.
var _cooldown_remaining: float = 0.0

## Player bodies currently inside the proximity area for collision exception tracking.
var _overlapping_players: Array[CharacterBody3D] = []

## Cached active viewport camera used for distance culling and label placement.
var _cached_camera: Camera3D = null

## Reusable transition dictionary passed to the player's state machine on mount.
var _mount_msg: Dictionary = {}

# --------------------------------------
# ONREADY NODE REFERENCES
# --------------------------------------

## Batched MultiMesh instance rendering either chain links or rope cylinders.
@onready var _multimesh_instance: MultiMeshInstance3D = (
	get_node_or_null("VisualMultiMesh") as MultiMeshInstance3D
)

## Thin static body on Layer 3 enabling crosshair shapecast detection.
@onready var _grab_body: StaticBody3D = get_node_or_null("GrabBody") as StaticBody3D

## Cylinder collision shape inside [_grab_body].
@onready var _grab_collision: CollisionShape3D = (
	get_node_or_null("GrabBody/GrabCollision") as CollisionShape3D
)

## Proximity and mid-air grab trigger volume detecting Layer 2 (Player).
@onready var _proximity_area: Area3D = get_node_or_null("ProximityArea") as Area3D

## Cylinder collision shape inside [_proximity_area].
@onready var _proximity_collision: CollisionShape3D = (
	get_node_or_null("ProximityArea/ProximityCollision") as CollisionShape3D
)

## Crosshair focus and interaction dispatch component.
@onready var _interact_component: InteractComponent = (
	get_node_or_null("InteractComponent") as InteractComponent
)

## Outline highlight component managing focus shader parameters.
@onready var _highlight_component: HighlightComponent = (
	get_node_or_null("HighlightComponent") as HighlightComponent
)

## Floating 3D prompt label displayed when focused from the ground.
@onready var _prompt_label: Label3D = get_node_or_null("PromptLabel") as Label3D

## Looping 3D audio player for standard climbing.
@onready
var _climb_audio: AudioStreamPlayer3D = get_node_or_null("ClimbAudio") as AudioStreamPlayer3D

## Looping 3D audio player for fast downward sliding.
@onready
var _slide_audio: AudioStreamPlayer3D = get_node_or_null("SlideAudio") as AudioStreamPlayer3D

## Looping 3D audio player for pendulum swing whoosh.
@onready
var _swing_audio: AudioStreamPlayer3D = get_node_or_null("SwingAudio") as AudioStreamPlayer3D

# --------------------------------------
# LIFECYCLE METHODS
# --------------------------------------


## Validates child nodes, binds interaction signals, and builds initial geometry.
func _ready() -> void:
	_ensure_child_nodes()
	_rebuild_rope()

	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		return

	assert(is_instance_valid(_multimesh_instance), "ClimbRope3D: Missing VisualMultiMesh.")
	assert(is_instance_valid(_grab_body), "ClimbRope3D: Missing GrabBody.")
	assert(is_instance_valid(_proximity_area), "ClimbRope3D: Missing ProximityArea.")
	assert(is_instance_valid(_interact_component), "ClimbRope3D: Missing InteractComponent.")

	add_to_group(&"interactable")
	add_to_group(&"interactables")

	if is_instance_valid(_climb_audio) and climb_stream != null:
		_climb_audio.stream = climb_stream
	if is_instance_valid(_slide_audio) and slide_stream != null:
		_slide_audio.stream = slide_stream
	if is_instance_valid(_swing_audio) and swing_stream != null:
		_swing_audio.stream = swing_stream

	_configure_prompt_text()
	if is_instance_valid(_prompt_label):
		_prompt_label.hide()

	if is_instance_valid(_interact_component):
		if not _interact_component.focused.is_connected(_on_interact_focused):
			_interact_component.focused.connect(_on_interact_focused)
		if not _interact_component.unfocused.is_connected(_on_interact_unfocused):
			_interact_component.unfocused.connect(_on_interact_unfocused)

	if is_instance_valid(_proximity_area):
		if not _proximity_area.body_entered.is_connected(_on_proximity_body_entered):
			_proximity_area.body_entered.connect(_on_proximity_body_entered)
		if not _proximity_area.body_exited.is_connected(_on_proximity_body_exited):
			_proximity_area.body_exited.connect(_on_proximity_body_exited)

	set_physics_process(false)
	_update_process_state()


## Cleans up collision exceptions with any overlapping players when removed.
func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	if is_instance_valid(_grab_body):
		for p: CharacterBody3D in _overlapping_players:
			if is_instance_valid(p):
				_grab_body.remove_collision_exception_with(p)
	_overlapping_players.clear()


## Updates re-grab cooldown, mid-air auto-grab checks, prompt placement, and Verlet visuals.
func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return

	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
		if _cooldown_remaining <= 0.0:
			_update_process_state()

	if (
		not _is_player_attached
		and _cooldown_remaining <= 0.0
		and not _overlapping_players.is_empty()
	):
		for i: int in range(_overlapping_players.size()):
			var p: Player = _overlapping_players[i] as Player
			if is_instance_valid(p) and _should_air_grab(p):
				_mount_player(p)
				break

	if _is_focused and not _is_player_attached:
		_update_prompt_label()

	if mode == Mode.SWING and (_has_hand_point or _is_verlet_awake):
		if not _is_player_attached and _is_camera_culled():
			return
		_step_verlet(delta)
		_update_swing_multimesh()


# --------------------------------------
# PUBLIC METHODS
# --------------------------------------


## Handles ground crosshair interaction dispatched by [InteractComponent].
func interact_with(character: CharacterBody3D) -> void:
	if _is_player_attached or _cooldown_remaining > 0.0:
		return
	var p: Player = character as Player
	if not is_instance_valid(p) or p.is_dead:
		return
	if not p.is_on_floor():
		return
	print("ClimbRope3D: Ground interact mount triggered.")
	_mount_player(p)


## Clamps a grab distance in meters to the valid playable span of this rope.
func clamp_grab_distance(dist: float) -> float:
	var max_dist: float = maxf(MIN_GRAB_OFFSET, length - BOTTOM_GRAB_MARGIN)
	return clampf(dist, MIN_GRAB_OFFSET, max_dist)


## Pins the visual rope strand to [param world_pos] at [param grab_dist] below the anchor.
func set_hand_point(world_pos: Vector3, grab_dist: float) -> void:
	_is_player_attached = true
	_has_hand_point = true
	_hand_world_pos = world_pos
	_hand_grab_distance = clamp_grab_distance(grab_dist)

	if is_instance_valid(_prompt_label):
		_prompt_label.hide()
	_set_highlight_overlay(false)

	if mode == Mode.SWING:
		_is_verlet_awake = true
		_settled_frames = 0

	_update_process_state()


## Releases the player hand pin so the Verlet rope can settle back to vertical.
func clear_hand_point() -> void:
	_has_hand_point = false
	if mode == Mode.SWING:
		_is_verlet_awake = true
		_settled_frames = 0
	_update_process_state()


## Detaches the player, starts the per-rope cooldown, and halts audio loops.
func release(cooldown: float = DEFAULT_REGRAB_COOLDOWN) -> void:
	print("ClimbRope3D: Player released rope. Cooldown: ", cooldown)
	_is_player_attached = false
	_has_hand_point = false
	_cooldown_remaining = maxf(0.0, cooldown)
	set_audio(false, false, 0.0)
	if mode == Mode.SWING:
		_is_verlet_awake = true
		_settled_frames = 0
	_update_process_state()


## Updates looping climb, slide, and velocity-modulated swing audio streams.
func set_audio(is_climbing: bool, is_sliding: bool, swing_speed: float) -> void:
	if is_instance_valid(_climb_audio):
		var play_climb: bool = is_climbing and not is_sliding and _climb_audio.stream != null
		if play_climb and not _climb_audio.playing:
			_climb_audio.play()
		elif not play_climb and _climb_audio.playing:
			_climb_audio.stop()

	if is_instance_valid(_slide_audio):
		var play_slide: bool = is_sliding and _slide_audio.stream != null
		if play_slide and not _slide_audio.playing:
			_slide_audio.play()
		elif not play_slide and _slide_audio.playing:
			_slide_audio.stop()

	if is_instance_valid(_swing_audio):
		var play_swing: bool = (
			mode == Mode.SWING
			and swing_speed >= SWING_AUDIO_MIN_SPEED
			and _swing_audio.stream != null
		)
		if play_swing:
			var t: float = clampf(
				(
					(swing_speed - SWING_AUDIO_MIN_SPEED)
					/ (SWING_AUDIO_MAX_SPEED - SWING_AUDIO_MIN_SPEED)
				),
				0.0,
				1.0
			)
			_swing_audio.volume_db = lerpf(SWING_AUDIO_MIN_DB, SWING_AUDIO_MAX_DB, t)
			if not _swing_audio.playing:
				_swing_audio.play()
		elif _swing_audio.playing:
			_swing_audio.stop()


# --------------------------------------
# PRIVATE METHODS: MOUNTING & PROXIMITY
# --------------------------------------


## Transitions [param p] into [StateRope] at the closest valid grab height.
func _mount_player(p: Player) -> void:
	if not is_instance_valid(p) or not is_instance_valid(p.state_machine):
		return
	if p.state_machine.is_in_state(STATE_ROPE):
		return

	var raw_dist: float = global_position.y - (p.global_position.y + 1.35)
	var clamped_dist: float = clamp_grab_distance(raw_dist)

	_mount_msg.clear()
	_mount_msg[KEY_ROPE] = self
	_mount_msg[KEY_GRAB_DISTANCE] = clamped_dist

	if p.state_machine.transition_to(STATE_ROPE, _mount_msg):
		_is_player_attached = true
		if is_instance_valid(_prompt_label):
			_prompt_label.hide()
		_set_highlight_overlay(false)
		_update_process_state()


## Evaluates whether airborne player [param p] satisfies mid-air auto-grab rules.
func _should_air_grab(p: Player) -> bool:
	if p.is_dead or p.is_on_floor():
		return false
	if not is_instance_valid(p.state_machine) or p.state_machine.is_in_state(STATE_ROPE):
		return false

	var hand_y: float = p.global_position.y + 1.35
	var top_y: float = global_position.y - MIN_GRAB_OFFSET + 0.35
	var bottom_y: float = global_position.y - length - 0.25
	if hand_y > top_y or hand_y < bottom_y:
		return false

	var to_axis: Vector3 = Vector3(
		global_position.x - p.global_position.x, 0.0, global_position.z - p.global_position.z
	)
	var horiz_vel: Vector3 = Vector3(p.velocity.x, 0.0, p.velocity.z)
	if to_axis.length_squared() > 0.0004:
		var approach_speed: float = horiz_vel.dot(to_axis.normalized())
		if approach_speed < AIR_APPROACH_MIN_SPEED:
			return false
	elif horiz_vel.length_squared() < (AIR_APPROACH_MIN_SPEED * AIR_APPROACH_MIN_SPEED):
		return false

	return true


## Registers collision exception on proximity entry and schedules mid-air grab check.
func _on_proximity_body_entered(body: Node3D) -> void:
	var p: Player = body as Player
	if not is_instance_valid(p):
		return

	if is_instance_valid(_grab_body):
		_grab_body.add_collision_exception_with(p)

	if not _overlapping_players.has(p):
		_overlapping_players.append(p)

	if not _is_player_attached and _cooldown_remaining <= 0.0 and _should_air_grab(p):
		print("ClimbRope3D: Mid-air auto-grab triggered.")
		_mount_player.call_deferred(p)

	_update_process_state()


## Removes collision exception when the player leaves the proximity cylinder.
func _on_proximity_body_exited(body: Node3D) -> void:
	var p: Player = body as Player
	if not is_instance_valid(p):
		return

	if is_instance_valid(_grab_body):
		_grab_body.remove_collision_exception_with(p)

	_overlapping_players.erase(p)
	_update_process_state()


# --------------------------------------
# PRIVATE METHODS: FOCUS & UI PROMPT
# --------------------------------------


## Shows the interaction prompt and outline highlight when focused from the ground.
func _on_interact_focused() -> void:
	_is_focused = true
	if not _is_player_attached:
		_set_highlight_overlay(true)
		_update_prompt_label()
	_update_process_state()


## Hides the interaction prompt and removes outline highlight when focus is lost.
func _on_interact_unfocused() -> void:
	_is_focused = false
	if is_instance_valid(_prompt_label):
		_prompt_label.hide()
	_set_highlight_overlay(false)
	_update_process_state()


## Applies or clears the outline shader material as an overlay on the MultiMesh.
func _set_highlight_overlay(active: bool) -> void:
	if not is_instance_valid(_multimesh_instance):
		return
	if active and is_instance_valid(_highlight_component):
		_multimesh_instance.material_overlay = _highlight_component.outline_material
	else:
		_multimesh_instance.material_overlay = null


## Updates the floating prompt position and hides it when the player is airborne.
func _update_prompt_label() -> void:
	if not is_instance_valid(_prompt_label) or not is_instance_valid(_interact_component):
		return

	var grounded_hover: bool = false
	for hovered_key: Variant in _interact_component.characters_hovering.keys():
		var ch: CharacterBody3D = hovered_key as CharacterBody3D
		if is_instance_valid(ch) and ch.is_on_floor():
			grounded_hover = true
			break

	if not grounded_hover or _cooldown_remaining > 0.0:
		_prompt_label.hide()
		return

	if not is_instance_valid(_cached_camera):
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_cached_camera = vp.get_camera_3d()

	if not is_instance_valid(_cached_camera):
		return

	var hit_pos: Vector3 = _interact_component.last_hit_position
	if hit_pos.is_zero_approx():
		hit_pos = global_position + Vector3(0.0, -length * 0.5, 0.0)

	var cam_basis: Basis = _cached_camera.global_transform.basis
	_prompt_label.global_position = (
		hit_pos + (cam_basis.x * LABEL_OFFSET_RIGHT) + (cam_basis.y * LABEL_OFFSET_UP)
	)
	_prompt_label.show()


## Formats the prompt label text from the current [InputMap] binding for interact.
func _configure_prompt_text() -> void:
	if not is_instance_valid(_prompt_label):
		return
	var key_label: String = "E"
	if InputMap.has_action(ACTION_INTERACT):
		var events: Array[InputEvent] = InputMap.action_get_events(ACTION_INTERACT)
		if not events.is_empty():
			key_label = events[0].as_text().split(" ")[0]
	_prompt_label.text = "[" + key_label + "] CLIMB"


## Enables [_process] only when simulation, cooldown, focus, or proximity requires it.
func _update_process_state() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	var active: bool = (
		_is_player_attached
		or _cooldown_remaining > 0.0
		or _is_focused
		or not _overlapping_players.is_empty()
		or (mode == Mode.SWING and (_has_hand_point or _is_verlet_awake))
	)
	set_process(active)


## Returns true if the active camera is beyond [constant CULL_DISTANCE_SQUARED].
func _is_camera_culled() -> bool:
	if not is_instance_valid(_cached_camera):
		var vp: Viewport = get_viewport()
		if is_instance_valid(vp):
			_cached_camera = vp.get_camera_3d()
	if not is_instance_valid(_cached_camera):
		return false
	return (
		global_position.distance_squared_to(_cached_camera.global_position) > CULL_DISTANCE_SQUARED
	)


# --------------------------------------
# PRIVATE METHODS: GEOMETRY & VISUALS
# --------------------------------------


## Ensures required child nodes exist in both editor preview and runtime.
func _ensure_child_nodes() -> void:
	if not is_instance_valid(_multimesh_instance):
		_multimesh_instance = get_node_or_null("VisualMultiMesh") as MultiMeshInstance3D
	if not is_instance_valid(_grab_body):
		_grab_body = get_node_or_null("GrabBody") as StaticBody3D
	if not is_instance_valid(_grab_collision):
		_grab_collision = get_node_or_null("GrabBody/GrabCollision") as CollisionShape3D
	if not is_instance_valid(_proximity_area):
		_proximity_area = get_node_or_null("ProximityArea") as Area3D
	if not is_instance_valid(_proximity_collision):
		_proximity_collision = (
			get_node_or_null("ProximityArea/ProximityCollision") as CollisionShape3D
		)
	if not is_instance_valid(_interact_component):
		_interact_component = get_node_or_null("InteractComponent") as InteractComponent
	if not is_instance_valid(_highlight_component):
		_highlight_component = get_node_or_null("HighlightComponent") as HighlightComponent
	if not is_instance_valid(_prompt_label):
		_prompt_label = get_node_or_null("PromptLabel") as Label3D
	if not is_instance_valid(_climb_audio):
		_climb_audio = get_node_or_null("ClimbAudio") as AudioStreamPlayer3D
	if not is_instance_valid(_slide_audio):
		_slide_audio = get_node_or_null("SlideAudio") as AudioStreamPlayer3D
	if not is_instance_valid(_swing_audio):
		_swing_audio = get_node_or_null("SwingAudio") as AudioStreamPlayer3D


## Rebuilds collision shapes, MultiMesh instances, and Verlet arrays for current settings.
func _rebuild_rope() -> void:
	_ensure_child_nodes()
	display_name = "Climbable Chain" if mode == Mode.CHAIN else "Climbable Rope"

	if is_instance_valid(_grab_body):
		_grab_body.collision_layer = PHYS_LAYER_INTERACTIVE
		_grab_body.collision_mask = 0
	if is_instance_valid(_grab_collision):
		var grab_cyl: CylinderShape3D = _grab_collision.shape as CylinderShape3D
		if not is_instance_valid(grab_cyl):
			grab_cyl = CylinderShape3D.new()
			_grab_collision.shape = grab_cyl
		grab_cyl.radius = GRAB_BODY_RADIUS
		grab_cyl.height = length
		_grab_collision.position = Vector3(0.0, -length * 0.5, 0.0)

	if is_instance_valid(_proximity_area):
		_proximity_area.collision_layer = 0
		_proximity_area.collision_mask = PHYS_MASK_PLAYER
		_proximity_area.monitorable = false
	if is_instance_valid(_proximity_collision):
		var prox_cyl: CylinderShape3D = _proximity_collision.shape as CylinderShape3D
		if not is_instance_valid(prox_cyl):
			prox_cyl = CylinderShape3D.new()
			_proximity_collision.shape = prox_cyl
		prox_cyl.radius = AIR_GRAB_RADIUS
		prox_cyl.height = length
		_proximity_collision.position = Vector3(0.0, -length * 0.5, 0.0)

	if not is_instance_valid(_multimesh_instance):
		return

	var mm: MultiMesh = _multimesh_instance.multimesh
	if not is_instance_valid(mm):
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		_multimesh_instance.multimesh = mm
	elif mm.transform_format != MultiMesh.TRANSFORM_3D:
		mm.instance_count = 0
		mm.transform_format = MultiMesh.TRANSFORM_3D

	if mode == Mode.CHAIN:
		_build_chain_multimesh(mm)
		_is_verlet_awake = false
	else:
		_build_swing_rope(mm)

	_apply_active_material()
	_multimesh_instance.custom_aabb = AABB(
		Vector3(-length, -length - 1.0, -length), Vector3(length * 2.0, length + 2.0, length * 2.0)
	)


## Populates [param mm] with alternating 90-degree procedural oval chain links.
func _build_chain_multimesh(mm: MultiMesh) -> void:
	mm.mesh = _get_or_build_chain_mesh()
	var link_count: int = maxi(1, int(floor(length / CHAIN_LINK_PITCH)))
	mm.instance_count = link_count

	var rot_basis: Basis = Basis.from_euler(Vector3(0.0, PI * 0.5, 0.0))
	for i: int in range(link_count):
		var y_pos: float = -(float(i) + 0.5) * CHAIN_LINK_PITCH
		var link_basis: Basis = rot_basis if (i % 2 == 1) else Basis.IDENTITY
		mm.set_instance_transform(i, Transform3D(link_basis, Vector3(0.0, y_pos, 0.0)))


## Initializes Verlet strand points and populates [param mm] for SWING mode.
func _build_swing_rope(mm: MultiMesh) -> void:
	mm.mesh = _get_or_build_rope_mesh()
	var seg_count: int = maxi(2, int(round(length / ROPE_SEGMENT_LEN)))
	var point_count: int = seg_count + 1
	var step_len: float = length / float(seg_count)

	_verlet_pos.resize(point_count)
	_verlet_prev.resize(point_count)

	var anchor_pos: Vector3 = global_position if is_inside_tree() else Vector3.ZERO
	for i: int in range(point_count):
		var p: Vector3 = anchor_pos + Vector3(0.0, -float(i) * step_len, 0.0)
		_verlet_pos[i] = p
		_verlet_prev[i] = p

	mm.instance_count = seg_count
	_is_verlet_awake = false
	_settled_frames = 0
	_update_swing_multimesh()


## Advances Verlet integration and distance constraints by one frame step.
func _step_verlet(delta: float) -> void:
	var point_count: int = _verlet_pos.size()
	if point_count < 2:
		return

	var dt: float = minf(delta, 0.033)
	var grav_step: Vector3 = Vector3(0.0, -VERLET_GRAVITY * dt * dt, 0.0)
	var damp: float = VERLET_PINNED_DAMPING if _has_hand_point else VERLET_DAMPING
	var anchor_pos: Vector3 = global_position

	var seg_count: int = point_count - 1
	var rest_len: float = length / float(seg_count)
	var hand_idx: int = -1
	if _has_hand_point:
		hand_idx = clampi(int(round(_hand_grab_distance / rest_len)), 1, seg_count)

	for i: int in range(1, point_count):
		var cur: Vector3 = _verlet_pos[i]
		var vel: Vector3 = (cur - _verlet_prev[i]) * damp
		_verlet_prev[i] = cur
		_verlet_pos[i] = cur + vel + grav_step

	_verlet_pos[0] = anchor_pos
	_verlet_prev[0] = anchor_pos

	for _iter: int in range(VERLET_ITERATIONS):
		_verlet_pos[0] = anchor_pos
		if hand_idx > 0:
			_verlet_pos[hand_idx] = _hand_world_pos

		for i: int in range(seg_count):
			var p1: Vector3 = _verlet_pos[i]
			var p2: Vector3 = _verlet_pos[i + 1]
			var diff: Vector3 = p2 - p1
			var dist: float = diff.length()
			if dist < 0.00001:
				continue
			var corr: Vector3 = diff * ((dist - rest_len) / dist)
			var pin1: bool = (i == 0) or (i == hand_idx)
			var pin2: bool = i + 1 == hand_idx
			if pin1 and pin2:
				continue
			elif pin1:
				_verlet_pos[i + 1] = p2 - corr
			elif pin2:
				_verlet_pos[i] = p1 + corr
			else:
				var half_corr: Vector3 = corr * 0.5
				_verlet_pos[i] = p1 + half_corr
				_verlet_pos[i + 1] = p2 - half_corr

	if not _has_hand_point:
		var max_move_sq: float = 0.0
		for i: int in range(1, point_count):
			var move_sq: float = _verlet_pos[i].distance_squared_to(_verlet_prev[i])
			if move_sq > max_move_sq:
				max_move_sq = move_sq
		if max_move_sq < VERLET_SLEEP_EPSILON_SQ:
			_settled_frames += 1
			if _settled_frames >= VERLET_SLEEP_FRAMES:
				_is_verlet_awake = false
				_update_process_state()
		else:
			_settled_frames = 0


## Updates MultiMesh cylinder transforms to match current Verlet node positions.
func _update_swing_multimesh() -> void:
	if not is_instance_valid(_multimesh_instance):
		return
	var mm: MultiMesh = _multimesh_instance.multimesh
	if not is_instance_valid(mm):
		return

	var seg_count: int = _verlet_pos.size() - 1
	if seg_count <= 0 or mm.instance_count != seg_count:
		return

	var inv_xform: Transform3D = (
		global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	)

	for i: int in range(seg_count):
		var lp1: Vector3 = inv_xform * _verlet_pos[i]
		var lp2: Vector3 = inv_xform * _verlet_pos[i + 1]
		var delta_vec: Vector3 = lp2 - lp1
		var seg_len: float = delta_vec.length()
		var mid: Vector3 = (lp1 + lp2) * 0.5

		var seg_basis: Basis = Basis.IDENTITY
		if seg_len > 0.0001:
			var y_axis: Vector3 = delta_vec / seg_len
			var ref: Vector3 = Vector3.FORWARD if absf(y_axis.y) < 0.99 else Vector3.RIGHT
			var x_axis: Vector3 = y_axis.cross(ref).normalized()
			var z_axis: Vector3 = x_axis.cross(y_axis).normalized()
			seg_basis = Basis(x_axis, y_axis * seg_len, z_axis)

		mm.set_instance_transform(i, Transform3D(seg_basis, mid))


## Assigns either the custom export material or the cached default material.
func _apply_active_material() -> void:
	if not is_instance_valid(_multimesh_instance):
		return
	if mode == Mode.CHAIN:
		if chain_material != null:
			_multimesh_instance.material_override = chain_material
		else:
			if _default_chain_material == null:
				_default_chain_material = StandardMaterial3D.new()
				_default_chain_material.albedo_color = Color(0.22, 0.23, 0.25)
				_default_chain_material.metallic = 0.85
				_default_chain_material.roughness = 0.42
			_multimesh_instance.material_override = _default_chain_material
	else:
		if rope_material != null:
			_multimesh_instance.material_override = rope_material
		else:
			if _default_rope_material == null:
				_default_rope_material = StandardMaterial3D.new()
				_default_rope_material.albedo_color = Color(0.56, 0.44, 0.28)
				_default_rope_material.roughness = 0.88
			_multimesh_instance.material_override = _default_rope_material


## Builds and caches the procedural elongated stadium-oval chain link [ArrayMesh].
static func _get_or_build_chain_mesh() -> ArrayMesh:
	if _cached_chain_mesh != null:
		return _cached_chain_mesh

	var arc_steps: int = 8
	var side_steps: int = 2
	var ring_count: int = (arc_steps + side_steps) * 2
	var tube_segments: int = 8

	var arc_radius: float = (CHAIN_LINK_WIDTH * 0.5) - CHAIN_WIRE_RADIUS
	var half_straight: float = (CHAIN_LINK_LENGTH * 0.5) - CHAIN_WIRE_RADIUS - arc_radius

	var centers: PackedVector3Array = PackedVector3Array()
	var normals_xy: PackedVector3Array = PackedVector3Array()
	centers.resize(ring_count)
	normals_xy.resize(ring_count)

	var idx: int = 0
	for i: int in range(arc_steps):
		var theta: float = PI * float(i) / float(arc_steps)
		var n: Vector3 = Vector3(cos(theta), sin(theta), 0.0)
		normals_xy[idx] = n
		centers[idx] = Vector3(0.0, half_straight, 0.0) + n * arc_radius
		idx += 1

	for i: int in range(side_steps):
		var t: float = float(i) / float(side_steps)
		normals_xy[idx] = Vector3(-1.0, 0.0, 0.0)
		centers[idx] = Vector3(-arc_radius, lerpf(half_straight, -half_straight, t), 0.0)
		idx += 1

	for i: int in range(arc_steps):
		var theta: float = PI + (PI * float(i) / float(arc_steps))
		var n: Vector3 = Vector3(cos(theta), sin(theta), 0.0)
		normals_xy[idx] = n
		centers[idx] = Vector3(0.0, -half_straight, 0.0) + n * arc_radius
		idx += 1

	for i: int in range(side_steps):
		var t: float = float(i) / float(side_steps)
		normals_xy[idx] = Vector3(1.0, 0.0, 0.0)
		centers[idx] = Vector3(arc_radius, lerpf(-half_straight, half_straight, t), 0.0)
		idx += 1

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for r: int in range(ring_count):
		var r_next: int = (r + 1) % ring_count
		var c0: Vector3 = centers[r]
		var c1: Vector3 = centers[r_next]
		var n0: Vector3 = normals_xy[r]
		var n1: Vector3 = normals_xy[r_next]

		for s: int in range(tube_segments):
			var s_next: int = (s + 1) % tube_segments
			var phi0: float = TAU * float(s) / float(tube_segments)
			var phi1: float = TAU * float(s_next) / float(tube_segments)

			var vn00: Vector3 = (n0 * cos(phi0) + Vector3(0.0, 0.0, sin(phi0))).normalized()
			var vn01: Vector3 = (n0 * cos(phi1) + Vector3(0.0, 0.0, sin(phi1))).normalized()
			var vn10: Vector3 = (n1 * cos(phi0) + Vector3(0.0, 0.0, sin(phi0))).normalized()
			var vn11: Vector3 = (n1 * cos(phi1) + Vector3(0.0, 0.0, sin(phi1))).normalized()

			var p00: Vector3 = c0 + vn00 * CHAIN_WIRE_RADIUS
			var p01: Vector3 = c0 + vn01 * CHAIN_WIRE_RADIUS
			var p10: Vector3 = c1 + vn10 * CHAIN_WIRE_RADIUS
			var p11: Vector3 = c1 + vn11 * CHAIN_WIRE_RADIUS

			st.set_normal(vn00)
			st.add_vertex(p00)
			st.set_normal(vn01)
			st.add_vertex(p01)
			st.set_normal(vn10)
			st.add_vertex(p10)

			st.set_normal(vn01)
			st.add_vertex(p01)
			st.set_normal(vn11)
			st.add_vertex(p11)
			st.set_normal(vn10)
			st.add_vertex(p10)

	_cached_chain_mesh = st.commit()
	return _cached_chain_mesh


## Builds and caches the shared unit-height [CylinderMesh] for swing rope segments.
static func _get_or_build_rope_mesh() -> CylinderMesh:
	if _cached_rope_mesh != null:
		return _cached_rope_mesh

	_cached_rope_mesh = CylinderMesh.new()
	_cached_rope_mesh.top_radius = ROPE_RADIUS
	_cached_rope_mesh.bottom_radius = ROPE_RADIUS
	_cached_rope_mesh.height = 1.0
	_cached_rope_mesh.radial_segments = 8
	_cached_rope_mesh.rings = 1
	return _cached_rope_mesh
