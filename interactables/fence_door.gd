## Articulated chain-link fence door with static frame, hinged leaf, lock, and touch rattle.
class_name FenceDoor
extends Node3D

## Emitted when the door opens or closes. Passes the new [member is_open] state.
signal state_changed(open_state: bool)

## Emitted when the door transitions to the open state.
signal opened

## Emitted when the door transitions to the closed state.
signal closed

## Emitted when player interaction is blocked because [member is_locked] is true.
signal door_locked

## Emitted when [member is_locked] transitions from true to false.
signal unlocked

## Emitted when [member is_locked] changes. Passes the new lock state.
signal locked_state_changed(locked_state: bool)

## Emitted when a body touches or rattles the fence door leaf.
signal fence_shaken(body: Node3D)

## Available swing opening directions for the hinged fence door leaf.
enum SwingMode {
	## Swings away from the approaching interactor's side.
	AWAY_FROM_PLAYER = 0,
	## Fixed inward swing toward negative Z space.
	INWARD_ONLY = 1,
	## Fixed outward swing toward positive Z space.
	OUTWARD_ONLY = 2,
	## Bidirectional swing dynamically opening away from player approach.
	BOTH_WAYS = 3,
}

## Group identifier used for locating the player entity in the scene tree.
const GROUP_PLAYER: StringName = &"player"

## Method identifier for 3D spatial sound playback on [AudioPool].
const METHOD_PLAY_SFX_3D: StringName = &"play_sfx_3d"

## Node name of the static outer frame mesh inside [code]fence_door.glb[/code].
const NODE_GLB_FRAME: String = "FenceDoor_Frame"

## Node name of the hinged door leaf mesh inside [code]fence_door.glb[/code].
const NODE_GLB_LEAF: String = "FenceDoor_Leaf"

## Local offset from the hinge pivot to the geometric center of the door leaf.
const LEAF_CENTER_OFFSET: Vector3 = Vector3(-0.46, 1.04, 0.0)

## Amplitude in degrees for the visual rattle tween when shaken or locked.
const RATTLE_ANGLE_DEG: float = 2.0

## Duration in seconds for each segment of the rattle tween oscillation.
const RATTLE_STEP_SEC: float = 0.045

## Preloaded dry mono SFX for opening the chain-link fence gate.
const DEFAULT_OPEN_SFX: AudioStream = preload("res://assets/audio/sfx/fence_door_open.wav")

## Preloaded dry mono SFX for closing and latching the chain-link fence gate.
const DEFAULT_CLOSE_SFX: AudioStream = preload("res://assets/audio/sfx/fence_door_close.wav")

## Preloaded dry mono SFX variation 1 for chain-link fence rattle.
const DEFAULT_SHAKE_SFX_1: AudioStream = preload("res://assets/audio/sfx/fence_door_shake_01.wav")

## Preloaded dry mono SFX variation 2 for chain-link fence rattle.
const DEFAULT_SHAKE_SFX_2: AudioStream = preload("res://assets/audio/sfx/fence_door_shake_02.wav")

## Preloaded dry mono SFX variation 3 for chain-link fence rattle.
const DEFAULT_SHAKE_SFX_3: AudioStream = preload("res://assets/audio/sfx/fence_door_shake_03.wav")

@export_group("Door State")
## Tracks whether the door leaf is currently open. Setting at runtime animates the leaf.
@export var is_open: bool = false:
	set = _set_is_open

## Locks the door in the inspector until unlocked via script or [EventSequenceTrigger].
@export var is_locked: bool = false:
	set = _set_is_locked

@export_group("Swing Settings")
## Governs directional swing behavior relative to player approach side.
@export var swing_mode: SwingMode = SwingMode.AWAY_FROM_PLAYER

## Maximum swing angle in degrees when opening the door leaf.
@export_range(15.0, 170.0, 1.0) var open_angle_deg: float = 90.0

## Duration in seconds of the opening and closing swing tween.
@export_range(0.1, 3.0, 0.05) var swing_duration: float = 0.6

@export_group("Touch Feedback")
## Enables playing fence shaking sound and rattle when a body touches the leaf.
@export var touch_shake_enabled: bool = true

## Minimum cooldown in seconds between touch-triggered fence shaking sounds.
@export_range(0.1, 3.0, 0.05) var touch_shake_cooldown: float = 0.65

@export_group("Audio")
## Audio stream played when the fence door swings open.
@export var open_sfx: AudioStream = DEFAULT_OPEN_SFX

## Audio stream played when the fence door swings closed.
@export var close_sfx: AudioStream = DEFAULT_CLOSE_SFX

## Audio stream variations randomly played when the fence door is touched or shaken.
@export var shake_sfx: Array[AudioStream] = [
	DEFAULT_SHAKE_SFX_1,
	DEFAULT_SHAKE_SFX_2,
	DEFAULT_SHAKE_SFX_3,
]

## Tracks whether [method _ready] has completed initialization.
var _is_ready: bool = false

## Prevents re-entrant setter dispatch while [method _apply_open_state] updates [member is_open].
var _suppress_open_setter: bool = false

## Tracks whether a swing tween is currently animating the door leaf.
var _is_swinging: bool = false

## Active tween driving door leaf open/close yaw interpolation.
var _swing_tween: Tween = null

## Active tween driving visual rattle oscillation when touched or locked.
var _rattle_tween: Tween = null

## Timestamp in milliseconds of the last fence shake feedback playback.
var _last_shake_msec: int = -10000

## Index of the last played shake variation to reduce consecutive repeats.
var _last_shake_idx: int = -1

## Static physics body enclosing the non-moving outer door frame.
@onready var _frame_body: StaticBody3D = $FrameBody

## Hinged kinematic body pivoted at the right barrel hinge axis.
@onready var _leaf_body: AnimatableBody3D = $DoorLeaf

## Proximity sensor on the leaf detecting physical player or debris touch.
@onready var _touch_area: Area3D = $DoorLeaf/TouchArea

## Instanced GLB scene containing [code]FenceDoor_Frame[/code] and [code]FenceDoor_Leaf[/code].
@onready var _model_root: Node3D = $FenceDoorModel

## Crosshair interaction component forwarding player interact events.
@onready var _interact_component: InteractComponent = $InteractComponent


## Initializes static frame, reparents hinged leaf mesh, wires touch sensor, and syncs state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(_frame_body), "FenceDoor: Missing FrameBody StaticBody3D.")
	assert(is_instance_valid(_leaf_body), "FenceDoor: Missing DoorLeaf AnimatableBody3D.")
	assert(is_instance_valid(_touch_area), "FenceDoor: Missing DoorLeaf/TouchArea Area3D.")
	assert(is_instance_valid(_model_root), "FenceDoor: Missing FenceDoorModel Node3D.")
	assert(
		is_instance_valid(_interact_component),
		"FenceDoor: Missing InteractComponent child.",
	)

	_bind_model_hierarchy()
	_configure_layers()
	Utilities.safe_connect(_touch_area.body_entered, _on_touch_area_body_entered)

	_is_ready = true
	if is_open:
		_leaf_body.rotation.y = _calculate_target_yaw(null)
	else:
		_leaf_body.rotation.y = 0.0


## Disconnects touch area listener cleanly when exiting the scene tree.
func _exit_tree() -> void:
	if is_instance_valid(_touch_area):
		if _touch_area.body_entered.is_connected(_on_touch_area_body_entered):
			_touch_area.body_entered.disconnect(_on_touch_area_body_entered)


## Primary interaction entry point. Obeys [member is_locked] and toggles open state.
func interact(caller: Node3D = null) -> void:
	if not is_instance_valid(_leaf_body) or not is_inside_tree():
		return

	if is_locked:
		print("FenceDoor: Interaction blocked on ", name, " -> door is locked.")
		_play_shake_feedback(caller, true)
		door_locked.emit()
		return

	_apply_open_state(not is_open, caller, true)


## Alias invoked by [InteractComponent] when the player presses interact.
func interact_with(player: Node3D) -> void:
	interact(player)


## Force-opens the door leaf, bypassing [member is_locked]. Callable from [EventSequenceTrigger].
func open_door() -> void:
	if not is_instance_valid(_leaf_body) or not is_inside_tree():
		return
	if is_open:
		return
	_apply_open_state(true, null, true)


## Closes the door leaf smoothly. Callable from [EventSequenceTrigger].
func close_door() -> void:
	if not is_instance_valid(_leaf_body) or not is_inside_tree():
		return
	if not is_open:
		return
	_apply_open_state(false, null, true)


## Toggles open/closed state regardless of [member is_locked]. Callable from [EventSequenceTrigger].
func toggle_door() -> void:
	if not is_instance_valid(_leaf_body) or not is_inside_tree():
		return
	_apply_open_state(not is_open, null, true)


## Locks the door against player interaction. Callable from [EventSequenceTrigger].
func lock_door() -> void:
	is_locked = true


## Unlocks the door for player interaction. Callable from [EventSequenceTrigger].
func unlock_door() -> void:
	is_locked = false


## Sets [member is_locked] from a boolean argument. Callable from [EventSequenceTrigger].
func set_locked(locked: bool) -> void:
	is_locked = locked


## Unlocks and immediately opens the door. Callable from [EventSequenceTrigger].
func unlock_and_open() -> void:
	is_locked = false
	open_door()


## Closes and immediately locks the door. Callable from [EventSequenceTrigger].
func close_and_lock() -> void:
	close_door()
	is_locked = true


## Plays the fence shaking sound and visual rattle on demand. Callable from [EventSequenceTrigger].
func shake_fence() -> void:
	_play_shake_feedback(null, true)


## Reparents [code]FenceDoor_Leaf[/code] under [member _leaf_body] so the outer frame stays static.
func _bind_model_hierarchy() -> void:
	var frame_mesh: MeshInstance3D = (
		_model_root.find_child(NODE_GLB_FRAME, true, false) as MeshInstance3D
	)
	if is_instance_valid(frame_mesh):
		frame_mesh.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT

	var leaf_mesh: MeshInstance3D = (
		_model_root.find_child(NODE_GLB_LEAF, true, false) as MeshInstance3D
	)
	if is_instance_valid(leaf_mesh) and leaf_mesh.get_parent() != _leaf_body:
		leaf_mesh.reparent(_leaf_body, true)
		leaf_mesh.layers = CollisionLayers.RENDER_MASK_INTERACTIVE


## Enforces project physics layer conventions on frame, leaf, and touch sensor.
func _configure_layers() -> void:
	_frame_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	_frame_body.collision_mask = CollisionLayers.MASK_NONE
	_leaf_body.collision_layer = CollisionLayers.MASK_INTERACTIVE
	_leaf_body.collision_mask = CollisionLayers.MASK_NONE
	_touch_area.collision_layer = CollisionLayers.MASK_NONE
	_touch_area.collision_mask = (
		CollisionLayers.MASK_PLAYER | CollisionLayers.MASK_INTERACTIVE | CollisionLayers.MASK_DEBRIS
	)


## Setter for [member is_open] supporting inspector defaults and [EventSequenceTrigger] sets.
func _set_is_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	if _suppress_open_setter:
		return
	if not _is_ready or not is_inside_tree() or not is_instance_valid(_leaf_body):
		return
	_apply_open_state(value, null, true)


## Setter for [member is_locked] emitting state signals when modified at runtime.
func _set_is_locked(value: bool) -> void:
	if is_locked == value:
		return
	is_locked = value
	if not _is_ready or not is_inside_tree():
		return
	print("FenceDoor: ", name, " is_locked -> ", is_locked)
	locked_state_changed.emit(is_locked)
	if not is_locked:
		unlocked.emit()


## Transitions [member is_open], tweens leaf yaw, plays open/close audio, and emits signals.
func _apply_open_state(target_open: bool, caller: Node3D, play_audio: bool) -> void:
	_suppress_open_setter = true
	is_open = target_open
	_suppress_open_setter = false
	var target_yaw: float = _calculate_target_yaw(caller) if target_open else 0.0

	if is_instance_valid(_rattle_tween) and _rattle_tween.is_valid():
		_rattle_tween.kill()

	_is_swinging = true
	_swing_tween = Utilities.reset_tween_ext(self, _swing_tween, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	if is_instance_valid(_swing_tween):
		_swing_tween.tween_property(_leaf_body, "rotation:y", target_yaw, swing_duration)
		_swing_tween.finished.connect(_on_swing_finished, Object.CONNECT_ONE_SHOT)
	else:
		_leaf_body.rotation.y = target_yaw
		_is_swinging = false

	if play_audio:
		var stream: AudioStream = open_sfx if target_open else close_sfx
		_play_3d_sfx(stream)

	print("FenceDoor: ", name, " state_changed -> is_open: ", is_open, " yaw: ", target_yaw)
	state_changed.emit(is_open)
	if is_open:
		opened.emit()
	else:
		closed.emit()


## Clears the active swing guard when the opening or closing tween finishes.
func _on_swing_finished() -> void:
	_is_swinging = false


## Resolves target opening yaw in radians based on [member swing_mode] and caller position.
func _calculate_target_yaw(caller: Node3D) -> float:
	var angle_rad: float = deg_to_rad(open_angle_deg)
	match swing_mode:
		SwingMode.INWARD_ONLY:
			return -angle_rad
		SwingMode.OUTWARD_ONLY:
			return angle_rad
		SwingMode.AWAY_FROM_PLAYER, SwingMode.BOTH_WAYS:
			var target_entity: Node3D = caller
			if not is_instance_valid(target_entity) and is_inside_tree():
				target_entity = get_tree().get_first_node_in_group(GROUP_PLAYER) as Node3D
			if is_instance_valid(target_entity):
				var local_pos: Vector3 = to_local(target_entity.global_position)
				if local_pos.z > 0.0:
					return -angle_rad
				return angle_rad
			return -angle_rad
	return -angle_rad


## Handles physical contact on [member _touch_area] to trigger chain-link rattle feedback.
func _on_touch_area_body_entered(body: Node3D) -> void:
	if not touch_shake_enabled or _is_swinging:
		return
	if not is_instance_valid(body) or body == _leaf_body or body == _frame_body:
		return
	_play_shake_feedback(body, false)


## Plays a random chain-link shake SFX variation and visual leaf rattle if cooldown allows.
func _play_shake_feedback(source_body: Node3D, force: bool) -> void:
	var now_msec: int = Time.get_ticks_msec()
	var cooldown_msec: int = int(touch_shake_cooldown * 1000.0)
	if not force and (now_msec - _last_shake_msec) < cooldown_msec:
		return
	_last_shake_msec = now_msec

	var stream: AudioStream = _pick_shake_stream()
	_play_3d_sfx(stream)

	if not _is_swinging and is_instance_valid(_leaf_body) and is_inside_tree():
		var base_yaw: float = _leaf_body.rotation.y
		var jitter_rad: float = deg_to_rad(RATTLE_ANGLE_DEG)
		_rattle_tween = Utilities.reset_tween_ext(
			self, _rattle_tween, Tween.TRANS_SINE, Tween.EASE_IN_OUT
		)
		if is_instance_valid(_rattle_tween):
			_rattle_tween.tween_property(
				_leaf_body, "rotation:y", base_yaw + jitter_rad, RATTLE_STEP_SEC
			)
			_rattle_tween.tween_property(
				_leaf_body, "rotation:y", base_yaw - jitter_rad, RATTLE_STEP_SEC
			)
			_rattle_tween.tween_property(
				_leaf_body, "rotation:y", base_yaw + jitter_rad * 0.45, RATTLE_STEP_SEC
			)
			_rattle_tween.tween_property(_leaf_body, "rotation:y", base_yaw, RATTLE_STEP_SEC)

	print("FenceDoor: ", name, " fence_shaken.")
	fence_shaken.emit(source_body)


## Selects a non-repeating random audio stream from [member shake_sfx].
func _pick_shake_stream() -> AudioStream:
	if shake_sfx.is_empty():
		return null
	var count: int = shake_sfx.size()
	if count == 1:
		return shake_sfx[0]
	var idx: int = randi() % count
	if idx == _last_shake_idx:
		idx = (idx + 1) % count
	_last_shake_idx = idx
	return shake_sfx[idx]


## Plays a 3D spatial sound effect at the door leaf center via [AudioPool].
func _play_3d_sfx(stream: AudioStream) -> void:
	if stream == null or not is_inside_tree():
		return
	var audio_pool: Node = get_node_or_null("/root/AudioPool")
	if not is_instance_valid(audio_pool):
		return
	var play_pos: Vector3 = (
		_leaf_body.to_global(LEAF_CENTER_OFFSET)
		if is_instance_valid(_leaf_body)
		else global_position
	)
	audio_pool.call(METHOD_PLAY_SFX_3D, stream, play_pos)
