class_name Dumpster
extends Node3D
## Interactive industrial dumpster prop featuring toggleable lid and edge wear.
## Controls [MeshInstance3D] lid rotation and [HighlightComponent] integration.

## Emitted when the dumpster lid finishes swinging open or closed.
@warning_ignore("unused_signal")
signal state_changed(is_open: bool)

## Emitted when the dumpster lid finishes swinging into the opened position.
@warning_ignore("unused_signal")
signal opened

## Emitted when the dumpster lid finishes swinging into the closed position.
@warning_ignore("unused_signal")
signal closed

## Relative node path to the hinged lid mesh instance.
const NODE_LID: StringName = &"Dumpster_Body/Dumpster_Lid"
## Relative node path to the main container body mesh instance.
const NODE_BODY: StringName = &"Dumpster_Body"

## Preloaded default weathered shader material for body panels.
const DEFAULT_MAT_BODY: Material = preload("res://interactables/dumpster/mat_dumpster_body.tres")
## Preloaded default weathered shader material for composite lid.
const DEFAULT_MAT_LID: Material = preload("res://interactables/dumpster/mat_dumpster_lid.tres")

## Target swing angle in degrees around X-axis when opening the lid.
@export var open_angle_deg: float = -110.0
## Duration of the lid swing transition in seconds.
@export var swing_duration: float = 0.55
## Toggles whether direct player interactions cycle the open state.
@export var allow_player_interact: bool = true
## Optional audio stream played when the lid begins opening.
@export var open_sound: AudioStream = null
## Optional audio stream played when the lid begins closing.
@export var close_sound: AudioStream = null
## Material override applied to container body mesh.
@export var body_material: Material = DEFAULT_MAT_BODY
## Material override applied to container lid mesh.
@export var lid_material: Material = DEFAULT_MAT_LID

## Whether the dumpster lid is currently in the opened state.
var is_open: bool = false

## Unified swing tween managing the lid rotation animation.
var _lid_tween: Tween = null
## Resting local X rotation in radians of the lid when closed.
var _initial_lid_rot_x: float = 0.0

## Cached reference to imported body [MeshInstance3D].
@onready var _body_mesh: MeshInstance3D = _find_body_mesh()
## Cached reference to imported lid [MeshInstance3D].
@onready var _lid_mesh: MeshInstance3D = _find_lid_mesh()
## Child [InteractComponent] dispatching player crosshair raycast interactions.
@onready var _interact_comp: InteractComponent = _find_interact_component()
## Child [HighlightComponent] applying outline materials on focus.
@onready var _highlight_comp: HighlightComponent = _find_highlight_component()
## Child [Area3D] monitoring occupant bodies inside container interior.
@onready var _interior_area: Area3D = _find_interior_area()


## Disables frame processing, validates scene hierarchy, and configures collision layers.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)

	assert(_body_mesh != null, "Dumpster: Missing Dumpster_Body MeshInstance3D.")
	assert(_lid_mesh != null, "Dumpster: Missing Dumpster_Lid MeshInstance3D.")

	_initial_lid_rot_x = _lid_mesh.rotation.x
	_setup_materials()
	_setup_collision_layers()


## Receives direct player interaction dispatched from [InteractComponent].
func interact_with(character: CharacterBody3D) -> void:
	if not allow_player_interact:
		return
	print("Dumpster: Interacted with by ", character.name)
	toggle_open()


## Alias for [method toggle_open] satisfying standard interaction protocol.
func interact() -> void:
	toggle_open()


## Opens the dumpster lid if currently closed.
func open() -> void:
	set_open(true)


## Closes the dumpster lid if currently open.
func close() -> void:
	set_open(false)


## Toggles the current open/closed lid state.
func toggle_open() -> void:
	set_open(not is_open)


## Smoothly tweens the dumpster lid to target open or closed orientation.
func set_open(target_open: bool) -> void:
	if is_open == target_open:
		return
	if not target_open and is_character_standing_inside():
		print("Dumpster: Cannot close lid - character is standing inside.")
		return
	is_open = target_open
	print("Dumpster: state changed -> is_open=", is_open)

	var sfx: AudioStream = open_sound if is_open else close_sound
	if sfx != null:
		AudioPool.play_sfx_3d(sfx, global_position)

	var target_rot_x: float = (
		_initial_lid_rot_x + deg_to_rad(open_angle_deg) if is_open else _initial_lid_rot_x
	)
	_lid_tween = Utilities.reset_tween_ext(self, _lid_tween, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	if _lid_tween != null:
		_lid_tween.tween_property(_lid_mesh, "rotation:x", target_rot_x, swing_duration)
		_lid_tween.finished.connect(_on_swing_finished)


## Evaluates if any [CharacterBody3D] is actively standing inside container interior.
func is_character_standing_inside() -> bool:
	if not is_instance_valid(_interior_area):
		return false
	var bodies: Array[Node3D] = _interior_area.get_overlapping_bodies()
	for body: Node3D in bodies:
		var character: CharacterBody3D = body as CharacterBody3D
		if character == null:
			continue
		var loco: PlayerLocomotionComponent = (
			character.get_node_or_null(^"Components/LocomotionComponent")
			as PlayerLocomotionComponent
		)
		if loco != null:
			if not loco.crouching:
				return true
		elif "crouching" in character:
			if not bool(character.get("crouching")):
				return true
		else:
			return true
	return false


## Resolves reference to the main container body mesh instance.
func _find_body_mesh() -> MeshInstance3D:
	var body: MeshInstance3D = get_node_or_null(NodePath(NODE_BODY)) as MeshInstance3D
	if body == null:
		body = get_node_or_null(NodePath("dumpster/Dumpster_Body")) as MeshInstance3D
	if body == null:
		body = find_child("Dumpster_Body", true, false) as MeshInstance3D
	return body


## Resolves reference to the hinged lid mesh instance.
func _find_lid_mesh() -> MeshInstance3D:
	if _body_mesh != null:
		var lid: MeshInstance3D = (
			_body_mesh.get_node_or_null(NodePath("Dumpster_Lid")) as MeshInstance3D
		)
		if lid != null:
			return lid
	return find_child("Dumpster_Lid", true, false) as MeshInstance3D


## Resolves reference to the attached [InteractComponent].
func _find_interact_component() -> InteractComponent:
	var comp: InteractComponent = get_node_or_null(^"InteractComponent") as InteractComponent
	if comp == null:
		comp = get_node_or_null(^"InteractArea/InteractComponent") as InteractComponent
	if comp == null:
		comp = find_child("InteractComponent", true, false) as InteractComponent
	return comp


## Resolves reference to the attached [HighlightComponent].
func _find_highlight_component() -> HighlightComponent:
	var comp: HighlightComponent = get_node_or_null(^"HighlightComponent") as HighlightComponent
	if comp == null:
		comp = find_child("HighlightComponent", true, false) as HighlightComponent
	return comp


## Resolves reference to the attached [Area3D] monitoring occupant bodies.
func _find_interior_area() -> Area3D:
	var area: Area3D = get_node_or_null(^"InteriorArea") as Area3D
	if area == null:
		area = find_child("InteriorArea", true, false) as Area3D
	return area


## Assigns weathered shader materials to body and lid surfaces.
func _setup_materials() -> void:
	if body_material != null and _body_mesh != null:
		_body_mesh.set_surface_override_material(0, body_material)
	if lid_material != null and _lid_mesh != null:
		_lid_mesh.set_surface_override_material(0, lid_material)


## Handles completion of the lid swing tween and dispatches state signals.
func _on_swing_finished() -> void:
	state_changed.emit(is_open)
	if is_open:
		opened.emit()
	else:
		closed.emit()


## Sets standardized physics layers on imported static collision bodies.
func _setup_collision_layers() -> void:
	var body_mask: int = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_INTERACTIVE
	for child: Node in _body_mesh.get_children():
		var static_body: StaticBody3D = child as StaticBody3D
		if static_body != null and static_body != _lid_mesh:
			static_body.collision_layer = body_mask
			static_body.collision_mask = CollisionLayers.MASK_ALL

	for child: Node in _lid_mesh.get_children():
		var lid_static_body: StaticBody3D = child as StaticBody3D
		if lid_static_body != null:
			lid_static_body.collision_layer = CollisionLayers.MASK_INTERACTIVE
			lid_static_body.collision_mask = CollisionLayers.MASK_ALL
