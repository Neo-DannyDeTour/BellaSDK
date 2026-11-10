## Controls procedural collapsible scissor gate blend shapes and collision bounds.
## Attach to root [AnimatableBody3D] with [MeshInstance3D] and [CollisionShape3D].
# class_name ScissorGate
extends AnimatableBody3D

## Emitted when gate begins a state transition; [param open] is the new target state.
@warning_ignore("unused_signal")
signal state_changed(open: bool)

## Emitted when gate finishes opening transition and reaches fully collapsed state.
@warning_ignore("unused_signal")
signal opened

## Emitted when gate finishes closing transition and reaches fully expanded state.
@warning_ignore("unused_signal")
signal closed

## Blend shape name baked by Blender generator.
const BLEND_COLLAPSED: StringName = &"Collapsed"
## Closed gate total width in meters.
const WIDTH_CLOSED: float = 1.32
## Collapsed gate width in meters.
const WIDTH_OPEN: float = 0.21
## Gate height in meters.
const GATE_HEIGHT: float = 2.2
## Gate collision thickness in meters.
const GATE_DEPTH: float = 0.06

## Mesh carrying the [constant BLEND_COLLAPSED] blend shape.
@export var gate_mesh: MeshInstance3D
## Collision node holding a [BoxShape3D].
@export var collision_shape: CollisionShape3D
## Open/close transition time in seconds.
@export var anim_duration: float = 0.65
## Initial and current gate state.
@export var is_open: bool = false

## Active fold tween.
var _tween: Tween
## Cached blend shape index.
var _blend_idx: int = -1
## Cached collision box.
var _box_shape: BoxShape3D


## Validates nodes, configures layers, and sets initial gate state.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(gate_mesh != null, "ScissorGate: gate_mesh must be assigned.")
	assert(collision_shape != null, "ScissorGate: collision_shape must be assigned.")

	_box_shape = collision_shape.shape as BoxShape3D
	assert(_box_shape != null, "ScissorGate: collision_shape requires a BoxShape3D.")

	_blend_idx = gate_mesh.find_blend_shape_by_name(BLEND_COLLAPSED)
	assert(_blend_idx != -1, "ScissorGate: 'Collapsed' blend shape missing on mesh.")

	collision_layer = CollisionLayers.MASK_SOLID_WORLD
	collision_mask = CollisionLayers.MASK_NONE
	gate_mesh.layers = CollisionLayers.RENDER_MASK_INTERACTIVE

	_apply_fold(1.0 if is_open else 0.0)


## Parameterless helper to open gate for [EventSequenceTrigger] execution steps.
func open() -> void:
	set_open(true)


## Parameterless helper to close gate for [EventSequenceTrigger] execution steps.
func close() -> void:
	set_open(false)


## Toggles gate open/closed state via player interaction.
func interact() -> void:
	toggle()


## Switches [member is_open] and starts transition to the opposite state.
func toggle() -> void:
	set_open(not is_open)


## Initiates animated transition to [param target_open] if state changes or [param force] is set.
func set_open(target_open: bool, force: bool = false) -> void:
	if is_open == target_open and not force:
		return

	is_open = target_open
	print("ScissorGate state_changed -> is_open: ", is_open)
	state_changed.emit(is_open)

	var target: float = 1.0 if is_open else 0.0
	var current: float = gate_mesh.get_blend_shape_value(_blend_idx)

	_tween = Utilities.reset_tween(self, _tween)
	if _tween == null:
		return
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_apply_fold, current, target, anim_duration)
	_tween.finished.connect(_on_tween_finished)


## Emits completion signals when fold animation finishes.
func _on_tween_finished() -> void:
	if is_open:
		print("ScissorGate opened")
		opened.emit()
	else:
		print("ScissorGate closed")
		closed.emit()


## Updates blend shape weight and resizes/repositions [BoxShape3D] along -X.
func _apply_fold(weight: float) -> void:
	gate_mesh.set_blend_shape_value(_blend_idx, weight)
	var cur_w: float = lerpf(WIDTH_CLOSED, WIDTH_OPEN, weight)
	_box_shape.size = Vector3(cur_w, GATE_HEIGHT, GATE_DEPTH)
	collision_shape.position = Vector3(-cur_w * 0.5, GATE_HEIGHT * 0.5, 0.0)
