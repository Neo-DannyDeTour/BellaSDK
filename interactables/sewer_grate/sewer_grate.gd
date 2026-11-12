class_name SewerGrate
extends Node3D
## Runtime controller for circle_metal_fence.glb.
## Converts static GLB leaf meshes into kinematic [RigidBody3D] doors in [method _ready],
## providing [method set_open] for hinged swinging and [method detach_leaf] for physics breakaway.

## Emitted when both grate leaves finish swinging open or closed.
@warning_ignore("unused_signal")
signal grate_state_changed(is_open: bool)

## Emitted when both leaves finish swinging into the opened position.
@warning_ignore("unused_signal")
signal opened

## Emitted when both leaves finish swinging into the closed position.
@warning_ignore("unused_signal")
signal closed

## Emitted when a leaf is blasted or broken off its hinges.
@warning_ignore("unused_signal")
signal leaf_detached(is_left: bool, body: RigidBody3D)

## Bitmask matching interactive visual render pass.
const RENDER_MASK_INTERACTIVE: int = 1 << (CollisionLayers.RENDER_LAYER_INTERACTIVE_IDX - 1)
## Physics layer for interactive hinged leaves.
const PHY_LAYER_INTERACTIVE: int = CollisionLayers.MASK_INTERACTIVE
## Physics layer for detached debris leaves.
const PHY_LAYER_DEBRIS: int = CollisionLayers.MASK_DEBRIS
## Physics mask for hinged leaves colliding with environment, player, props, and enemies.
const PHY_MASK_HINGED: int = (
	CollisionLayers.MASK_ENVIRONMENT
	| CollisionLayers.MASK_PLAYER
	| CollisionLayers.MASK_INTERACTIVE
	| CollisionLayers.MASK_DEBRIS
	| CollisionLayers.MASK_ENEMIES
)
## Physics mask for detached debris leaves.
const PHY_MASK_DEBRIS: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS

## Node name for left grate leaf.
const NODE_LEFT: StringName = &"GrateLeft"
## Node name for right grate leaf.
const NODE_RIGHT: StringName = &"GrateRight"
## Shader parameter name for per-instance rust procedural seed.
const PARAM_RUST_SEED: StringName = &"rust_seed"

## Target swing angle in degrees when opening leaves.
@export var open_angle_deg: float = 105.0
## Duration of swing transition in seconds.
@export var swing_duration: float = 0.65
## Mass in kilograms applied to converted [RigidBody3D] leaf.
@export var leaf_mass: float = 45.0
## Toggles whether player direct interaction triggers door toggling.
@export var allow_player_interact: bool = true

## Whether both grate leaves are currently commanded open.
var is_open: bool = false
## Whether the left grate leaf has been blasted off hinges.
var is_left_detached: bool = false
## Whether the right grate leaf has been blasted off hinges.
var is_right_detached: bool = false

## Physics body created dynamically for left leaf.
var _body_left: RigidBody3D = null
## Physics body created dynamically for right leaf.
var _body_right: RigidBody3D = null
## Unified swing tween managing parallel leaf animations.
var _swing_tween: Tween = null

## Cached reference to imported left leaf [MeshInstance3D].
@onready var _mesh_left: MeshInstance3D = get_node_or_null(NodePath(NODE_LEFT)) as MeshInstance3D
## Cached reference to imported right leaf [MeshInstance3D].
@onready var _mesh_right: MeshInstance3D = get_node_or_null(NodePath(NODE_RIGHT)) as MeshInstance3D


## Validates imported GLB nodes, disables per-frame callbacks, and builds physics bodies.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(_mesh_left != null, "SewerGrate: Missing GrateLeft MeshInstance3D.")
	assert(_mesh_right != null, "SewerGrate: Missing GrateRight MeshInstance3D.")

	_mesh_left.set_instance_shader_parameter(PARAM_RUST_SEED, 0.0)
	_mesh_right.set_instance_shader_parameter(PARAM_RUST_SEED, 1.37)

	_body_left = _convert_leaf_to_rigidbody(_mesh_left, &"GrateBodyLeft")
	_body_right = _convert_leaf_to_rigidbody(_mesh_right, &"GrateBodyRight")


## Receives direct player interaction dispatched from [InteractComponent].
func interact_with(character: CharacterBody3D) -> void:
	if not allow_player_interact:
		return
	print("SewerGrate: Interacted with by ", character.name)
	toggle_open()


## Convenience parameterless helper for [EventSequenceTrigger] opening steps.
func open() -> void:
	set_open(true)


## Convenience parameterless helper for [EventSequenceTrigger] closing steps.
func close() -> void:
	set_open(false)


## Toggles current open/closed state.
func toggle_open() -> void:
	set_open(not is_open)


## Swings non-detached grate leaves to target angle and emits completion signals on finish.
func set_open(open_state: bool) -> void:
	if is_open == open_state:
		return
	is_open = open_state
	print("SewerGrate: state changed -> is_open=", is_open)

	var target_rad: float = deg_to_rad(open_angle_deg) if is_open else 0.0

	var can_swing_left: bool = not is_left_detached and is_instance_valid(_body_left)
	var can_swing_right: bool = not is_right_detached and is_instance_valid(_body_right)

	if not can_swing_left and not can_swing_right:
		_emit_completion_signals()
		return

	_swing_tween = Utilities.reset_tween_ext(self, _swing_tween, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	if _swing_tween == null:
		_emit_completion_signals()
		return

	_swing_tween.set_parallel(true)
	if can_swing_left:
		_swing_tween.tween_property(_body_left, ^"rotation:y", -target_rad, swing_duration)
	if can_swing_right:
		_swing_tween.tween_property(_body_right, ^"rotation:y", target_rad, swing_duration)

	_swing_tween.chain().tween_callback(_emit_completion_signals)


## Unfreezes the specified leaf, transitions it to Layer 4 (Debris), and applies impulse.
func detach_leaf(is_left: bool, impulse: Vector3, hit_global_pos: Vector3 = Vector3.ZERO) -> void:
	if is_instance_valid(_swing_tween) and _swing_tween.is_valid():
		_swing_tween.kill()

	if is_left:
		if is_left_detached or not is_instance_valid(_body_left):
			return
		is_left_detached = true
		print("SewerGrate: detached GrateLeft")
		_apply_detach_state.call_deferred(_body_left, true, impulse, hit_global_pos)
	else:
		if is_right_detached or not is_instance_valid(_body_right):
			return
		is_right_detached = true
		print("SewerGrate: detached GrateRight")
		_apply_detach_state.call_deferred(_body_right, false, impulse, hit_global_pos)


## Broadcasts completion signals when swing transition finishes.
func _emit_completion_signals() -> void:
	print("SewerGrate: swing animation completed -> is_open=", is_open)
	grate_state_changed.emit(is_open)
	if is_open:
		opened.emit()
	else:
		closed.emit()


## Extracts [CollisionShape3D] children from imported static wrappers into a [RigidBody3D].
func _convert_leaf_to_rigidbody(mesh_inst: MeshInstance3D, body_name: StringName) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	body.name = body_name
	body.transform = mesh_inst.transform
	body.mass = leaf_mass
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.collision_layer = PHY_LAYER_INTERACTIVE
	body.collision_mask = PHY_MASK_HINGED
	add_child(body)

	mesh_inst.layers = RENDER_MASK_INTERACTIVE

	var children: Array[Node] = mesh_inst.get_children()
	for child: Node in children:
		var static_body: StaticBody3D = child as StaticBody3D
		if static_body != null:
			var sb_xform: Transform3D = static_body.transform
			var sb_children: Array[Node] = static_body.get_children()
			for sb_child: Node in sb_children:
				var col_shape: CollisionShape3D = sb_child as CollisionShape3D
				if col_shape != null:
					var local_xform: Transform3D = sb_xform * col_shape.transform
					col_shape.owner = null
					static_body.remove_child(col_shape)
					body.add_child(col_shape)
					col_shape.transform = local_xform
			static_body.queue_free()

	mesh_inst.owner = null
	remove_child(mesh_inst)
	body.add_child(mesh_inst)
	mesh_inst.transform = Transform3D.IDENTITY

	return body


## Mutates physics body flags outside the physics step and applies world-space impulse.
func _apply_detach_state(
	body: RigidBody3D, is_left: bool, impulse: Vector3, hit_global_pos: Vector3
) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	body.collision_layer = PHY_LAYER_DEBRIS
	body.collision_mask = PHY_MASK_DEBRIS
	body.freeze = false

	var world_3d: World3D = body.get_world_3d()
	if is_instance_valid(world_3d) and world_3d.space.is_valid():
		var offset: Vector3 = Vector3.ZERO
		if hit_global_pos != Vector3.ZERO:
			offset = hit_global_pos - body.global_position
		body.apply_impulse(impulse, offset)
	leaf_detached.emit(is_left, body)
