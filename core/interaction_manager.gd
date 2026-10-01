## Central manager for reticle raycast scanning, highlight focus, and HUD routing via [NodeQuery].
class_name InteractionManager
extends Node

## Emitted when [member current_target] gains focus, passing target node and prompt string.
signal focused(target: Node3D, prompt: String)

## Emitted when [member current_target] loses focus, passing previous target node payload.
signal unfocused(previous_target: Node3D)

## Emitted when [method try_interact] succeeds, passing interacted target and interactor node.
signal interacted(target: Node3D, interactor: Node3D)

## Default maximum distance in meters for [method scan_for_interactable] raycast queries.
const DEFAULT_MAX_DISTANCE: float = 3.0

## Method name invoked on valid interactive targets during [method try_interact].
const METHOD_INTERACT: StringName = &"interact"

## Method name queried on target to obtain HUD prompt string in [method _update_focus].
const METHOD_GET_PROMPT: StringName = &"get_interaction_prompt"

## Method name invoked on interactive targets to toggle visual highlight outlines.
const METHOD_SET_HIGHLIGHT: StringName = &"set_highlight"

## Fallback prompt text when focused interactable does not specify a custom prompt.
const DEFAULT_PROMPT: String = "Interact"

## Active [Camera3D] reference used as the ray origin for interaction scanning queries.
@export var source_camera: Camera3D

## Distance in meters raycast extends to discover interactive colliders in [CollisionLayers].
@export_range(0.5, 10.0, 0.1) var max_distance: float = DEFAULT_MAX_DISTANCE

## Currently focused interactive [Node3D] entity under the player reticle.
var current_target: Node3D = null

## Cached prompt string returned by the currently focused interactive object.
var current_prompt: String = ""

## Cached raycast exclusion array to avoid heap allocations during physics updates.
var _exclude_rids: Array[RID] = []

## Cached ray start position vector to prevent per-frame vector allocations.
var _ray_start: Vector3 = Vector3.ZERO

## Cached ray end position vector to prevent per-frame vector allocations.
var _ray_end: Vector3 = Vector3.ZERO


## Initializes exclusion arrays and verifies configuration in the active scene tree.
func _ready() -> void:
	print("[InteractionManager] Initializing interaction manager.")
	_setup_exclusions()


## Executes per-tick scan via [method scan_for_interactable] on physics frame updates.
func _physics_process(_delta: float) -> void:
	scan_for_interactable()


## Sets the active [member source_camera] and updates collision exclusion RIDs.
func set_source_camera(new_camera: Camera3D) -> void:
	print("[InteractionManager] Setting source camera: ", new_camera)
	source_camera = new_camera
	_setup_exclusions()


## Performs a zero-allocation raycast scan using [NodeQuery] along [member source_camera] view.
func scan_for_interactable() -> void:
	if source_camera == null or not is_inside_tree():
		if current_target != null:
			_update_focus(null)
		return
	var world_3d: World3D = source_camera.get_world_3d()
	if world_3d == null:
		return
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	if space_state == null:
		return
	var camera_transform: Transform3D = source_camera.global_transform
	_ray_start = camera_transform.origin
	_ray_end = _ray_start - camera_transform.basis.z * max_distance
	var hit: Dictionary = NodeQuery.cast_ray(
		space_state, _ray_start, _ray_end, CollisionLayers.MASK_INTERACTIVE, _exclude_rids
	)
	var new_target: Node3D = null
	if not hit.is_empty():
		var collider: Object = hit.get(&"collider")
		if collider is Node3D:
			var candidate: Node3D = NodeQuery.resolve_interactable_root(collider as Node3D)
			if is_instance_valid(candidate) and candidate.has_method(METHOD_INTERACT):
				new_target = candidate
	if new_target != current_target:
		_update_focus(new_target)


## Attempts interaction with [member current_target] initiated by [param interactor] node.
func try_interact(interactor: Node3D) -> bool:
	print("[InteractionManager] Player requested interaction with interactor: ", interactor)
	if not is_instance_valid(current_target):
		print("[InteractionManager] Interaction failed: No valid target focused.")
		return false
	if not current_target.has_method(METHOD_INTERACT):
		print("[InteractionManager] Interaction failed: Target lacks interact method.")
		return false
	print("[InteractionManager] Executing interact on target: ", current_target.name)
	current_target.call(METHOD_INTERACT, interactor)
	interacted.emit(current_target, interactor)
	Events.interacted.emit(current_target, interactor)
	return true


## Clears current target focus and disables active highlights on [member current_target].
func clear_focus() -> void:
	print("[InteractionManager] Clearing active focus manually.")
	_update_focus(null)


## Updates focused target state, toggles highlights, and dispatches focus events.
func _update_focus(new_target: Node3D) -> void:
	if current_target == new_target:
		return
	if is_instance_valid(current_target):
		print("[InteractionManager] Focus exited on target: ", current_target.name)
		if current_target.has_method(METHOD_SET_HIGHLIGHT):
			current_target.call(METHOD_SET_HIGHLIGHT, false)
		var previous_target: Node3D = current_target
		unfocused.emit(previous_target)
		Events.interaction_unfocused.emit(previous_target)
	current_target = new_target
	if is_instance_valid(current_target):
		print("[InteractionManager] Focus entered on target: ", current_target.name)
		if current_target.has_method(METHOD_SET_HIGHLIGHT):
			current_target.call(METHOD_SET_HIGHLIGHT, true)
		if current_target.has_method(METHOD_GET_PROMPT):
			current_prompt = str(current_target.call(METHOD_GET_PROMPT))
		else:
			current_prompt = DEFAULT_PROMPT
		focused.emit(current_target, current_prompt)
		Events.interaction_focused.emit(current_target, current_prompt)
	else:
		current_prompt = ""


## Rebuilds [member _exclude_rids] to ignore parent colliders of [member source_camera].
func _setup_exclusions() -> void:
	print("[InteractionManager] Configuring raycast exclusion RIDs.")
	_exclude_rids.clear()
	if source_camera == null:
		return
	var ancestor: Node = NodeQuery.find_ancestor_of_type(source_camera, CollisionObject3D)
	if ancestor is CollisionObject3D:
		_exclude_rids.append((ancestor as CollisionObject3D).get_rid())
