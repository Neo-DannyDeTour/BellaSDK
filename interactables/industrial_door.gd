@tool
class_name IndustrialDoor
extends Node3D

## Procedural industrial louvered door and frame assembly.
## Builds static frame on Layer 1 and hinged interactive door leaf on Layer 3.

## Emitted when the door finishes or starts toggling its open state.
signal state_changed(is_open: bool)

## Emitted when interaction is attempted while the door is locked.
signal door_locked

## Available swing opening directions for the hinged door leaf.
enum SwingMode {
	## Swings away from the approaching interactor's side.
	AWAY_FROM_PLAYER = 0,
	## Fixed inward swing toward negative Z space (-90 degrees).
	INWARD_ONLY = 1,
	## Fixed outward swing toward positive Z space (+90 degrees).
	OUTWARD_ONLY = 2,
	## Bidirectional swing dynamically opening away from player approach.
	BOTH_WAYS = 3,
}

## Width of the door slab in meters.
const DOOR_WIDTH: float = 0.9
## Height of the door opening and frame in meters.
const DOOR_HEIGHT: float = 2.0
## Thickness of the door slab in meters.
const DOOR_DEPTH: float = 0.045
## Profile thickness of the surrounding door jamb frame.
const FRAME_THICKNESS: float = 0.06
## Depth extrusion of the frame structure in meters.
const FRAME_DEPTH: float = 0.08
## Yaw opening angle for inward swing in radians (-90 degrees).
const SWING_ANGLE_INWARD_RAD: float = -1.57079632679
## Yaw opening angle for outward swing in radians (+90 degrees).
const SWING_ANGLE_OUTWARD_RAD: float = 1.57079632679
## Duration of the opening/closing tween transition in seconds.
const SWING_DURATION: float = 0.6
## Base pitch rotation in radians for the deadbolt cylinder mesh.
const KNOB_BASE_PITCH_RAD: float = 1.57079632679

## Shader parameter identifier for per-instance color tint.
const PARAM_TINT: StringName = &"tint"
## Shader parameter identifier for per-instance UV scaling.
const PARAM_UV_SCALE: StringName = &"uv_scale"
## Shader parameter identifier for albedo texture sampler.
const PARAM_ALBEDO_TEX: StringName = &"albedo_texture"
## Shader parameter identifier for packed ORM texture sampler.
const PARAM_ORM_TEX: StringName = &"orm_texture"
## Shader parameter identifier for normal texture sampler.
const PARAM_NORMAL_TEX: StringName = &"normal_texture"
## Group identifier used for finding player entity in scene tree.
const GROUP_PLAYER: StringName = &"player"

## Compiled spatial surface shader for door visuals.
const SHADER_MAIN: Shader = preload("res://shaders/industrial_door.gdshader")
## Generated albedo texture map for industrial door.
const TEX_ALBEDO: Texture2D = preload("res://assets/textures/door/door_albedo.png")
## Generated packed ORM texture map (R: AO, G: Roughness, B: Metallic).
const TEX_ORM: Texture2D = preload("res://assets/textures/door/door_orm.png")
## Generated normal texture map for industrial door surface.
const TEX_NORMAL: Texture2D = preload("res://assets/textures/door/door_normal.png")

## Tracks whether the door leaf is currently in an opened state.
@export var is_open: bool = false
## Locks the door in the inspector, rejecting interactions with feedback.
@export var is_locked: bool = false
## Governs directional swing behavior relative to player approach angle.
@export var swing_mode: SwingMode = SwingMode.AWAY_FROM_PLAYER
## Audio stream played when attempting to interact with a locked door.
@export var locked_sfx: AudioStream = preload("res://assets/sounds/18_LightSwitch.wav")
## Audio stream played when the door swings open or closed.
@export var open_sfx: AudioStream = preload("res://assets/sounds/7_Door.wav")

## Active tween handling door swing interpolation.
var _tween: Tween = null
## Active tween handling locked deadbolt rattle effect.
var _rattle_tween: Tween = null
## Cached material instance shared across frame and door meshes.
var _shared_material: ShaderMaterial = null
## Reference to the hinged physics body representing the swinging door leaf.
var _leaf_body: AnimatableBody3D = null
## Reference to the deadbolt knob mesh for rattle feedback.
var _deadbolt_knob: MeshInstance3D = null


## Initializes hierarchy, disables per-frame polling, and validates setup.
func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	_ensure_material()
	_rebuild_hierarchy()
	assert(_leaf_body != null, "DoorLeaf AnimatableBody3D failed to initialize.")


## Toggles the door open/closed state or triggers locked feedback.
func interact(caller: Node3D = null) -> void:
	if not is_instance_valid(_leaf_body) or not is_inside_tree():
		return

	if is_locked:
		_play_locked_feedback()
		door_locked.emit()
		return

	is_open = not is_open
	var target_yaw: float = 0.0
	if is_open:
		target_yaw = _calculate_target_yaw(caller)

	_tween = Utilities.reset_tween_ext(self, _tween, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	_tween.tween_property(_leaf_body, "rotation:y", target_yaw, SWING_DURATION)

	var audio_pool: Node = get_node_or_null("/root/AudioPool")
	if is_instance_valid(audio_pool) and open_sfx != null:
		audio_pool.call(&"play_sfx_3d", open_sfx, global_position)

	print("IndustrialDoor: state_changed -> is_open: ", is_open, " yaw: ", target_yaw)
	state_changed.emit(is_open)


## Interactor callable alias for player interaction system dispatch.
func interact_with(player: Node3D) -> void:
	interact(player)


## Locks the door, preventing subsequent interaction openings.
func lock_door() -> void:
	is_locked = true
	print("IndustrialDoor: Door locked.")


## Unlocks the door, restoring normal interaction capability.
func unlock_door() -> void:
	is_locked = false
	print("IndustrialDoor: Door unlocked.")


## Resolves target yaw angle in radians according to [member swing_mode].
func _calculate_target_yaw(caller: Node3D) -> float:
	match swing_mode:
		SwingMode.INWARD_ONLY:
			return SWING_ANGLE_INWARD_RAD
		SwingMode.OUTWARD_ONLY:
			return SWING_ANGLE_OUTWARD_RAD
		SwingMode.AWAY_FROM_PLAYER, SwingMode.BOTH_WAYS:
			var target_entity: Node3D = caller
			if not is_instance_valid(target_entity) and is_inside_tree():
				target_entity = get_tree().get_first_node_in_group(GROUP_PLAYER) as Node3D
			if is_instance_valid(target_entity):
				var local_pos: Vector3 = to_local(target_entity.global_position)
				if local_pos.z > 0.0:
					return SWING_ANGLE_INWARD_RAD
				return SWING_ANGLE_OUTWARD_RAD
			return SWING_ANGLE_INWARD_RAD
	return SWING_ANGLE_INWARD_RAD


## Plays audio cue and animates rapid deadbolt knob rattle on locked rejection.
func _play_locked_feedback() -> void:
	print("IndustrialDoor: Interaction rejected -> Door is locked.")
	var audio_pool: Node = get_node_or_null("/root/AudioPool")
	if is_instance_valid(audio_pool) and locked_sfx != null:
		audio_pool.call(&"play_sfx_3d", locked_sfx, global_position)

	if not is_instance_valid(_deadbolt_knob):
		return

	_rattle_tween = Utilities.reset_tween_ext(
		self, _rattle_tween, Tween.TRANS_SINE, Tween.EASE_IN_OUT
	)
	var rattle_offset: float = deg_to_rad(14.0)
	_rattle_tween.tween_property(
		_deadbolt_knob, "rotation:x", KNOB_BASE_PITCH_RAD + rattle_offset, 0.04
	)
	_rattle_tween.tween_property(
		_deadbolt_knob, "rotation:x", KNOB_BASE_PITCH_RAD - rattle_offset, 0.04
	)
	_rattle_tween.tween_property(
		_deadbolt_knob, "rotation:x", KNOB_BASE_PITCH_RAD + rattle_offset * 0.5, 0.04
	)
	_rattle_tween.tween_property(_deadbolt_knob, "rotation:x", KNOB_BASE_PITCH_RAD, 0.04)


## Creates the shared [ShaderMaterial] bound to the generated PBR textures.
func _ensure_material() -> void:
	if _shared_material != null:
		return
	_shared_material = ShaderMaterial.new()
	_shared_material.shader = SHADER_MAIN
	_shared_material.set_shader_parameter(PARAM_ALBEDO_TEX, TEX_ALBEDO)
	_shared_material.set_shader_parameter(PARAM_ORM_TEX, TEX_ORM)
	_shared_material.set_shader_parameter(PARAM_NORMAL_TEX, TEX_NORMAL)


## Builds or locates the Frame and Hinged Leaf nodes cleanly.
func _rebuild_hierarchy() -> void:
	var existing_frame: StaticBody3D = get_node_or_null("FrameBody") as StaticBody3D
	if existing_frame == null:
		_build_frame()
	var existing_leaf: AnimatableBody3D = get_node_or_null("DoorLeaf") as AnimatableBody3D
	if existing_leaf == null:
		_build_door_leaf()
	else:
		_leaf_body = existing_leaf
		_deadbolt_knob = _leaf_body.get_node_or_null("DeadboltKnob") as MeshInstance3D


## Constructs the 3-piece jamb [StaticBody3D] on Environment Layer 1.
func _build_frame() -> void:
	var frame_body: StaticBody3D = StaticBody3D.new()
	frame_body.name = "FrameBody"
	frame_body.collision_layer = CollisionLayers.MASK_ENVIRONMENT
	frame_body.collision_mask = CollisionLayers.MASK_NONE
	add_child(frame_body)

	var half_w: float = (DOOR_WIDTH + FRAME_THICKNESS) * 0.5
	var jamb_h: float = DOOR_HEIGHT + FRAME_THICKNESS
	var side_size: Vector3 = Vector3(FRAME_THICKNESS, jamb_h, FRAME_DEPTH)
	var top_size: Vector3 = Vector3(
		DOOR_WIDTH + FRAME_THICKNESS * 2.0, FRAME_THICKNESS, FRAME_DEPTH
	)

	_add_frame_piece(frame_body, "LeftJamb", side_size, Vector3(-half_w, jamb_h * 0.5, 0.0))
	_add_frame_piece(frame_body, "RightJamb", side_size, Vector3(half_w, jamb_h * 0.5, 0.0))
	_add_frame_piece(
		frame_body, "TopHeader", top_size, Vector3(0.0, DOOR_HEIGHT + FRAME_THICKNESS * 0.5, 0.0)
	)


## Adds a single frame mesh + collider child to the frame body.
func _add_frame_piece(
	parent: StaticBody3D, piece_name: String, size: Vector3, pos: Vector3
) -> void:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.name = piece_name
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.material_override = _shared_material
	mesh_inst.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	mesh_inst.position = pos
	mesh_inst.set_instance_shader_parameter(PARAM_TINT, Color(0.82, 0.85, 0.86, 1.0))
	mesh_inst.set_instance_shader_parameter(PARAM_UV_SCALE, Vector2(0.15, 0.15))
	parent.add_child(mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = piece_name + "Col"
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	parent.add_child(col)


## Constructs the right-hinged [AnimatableBody3D] door slab, hinges, and knob on Layer 3.
func _build_door_leaf() -> void:
	var leaf: AnimatableBody3D = AnimatableBody3D.new()
	leaf.name = "DoorLeaf"
	leaf.collision_layer = CollisionLayers.MASK_INTERACTIVE
	leaf.collision_mask = CollisionLayers.MASK_NONE
	leaf.sync_to_physics = false
	# Pivot placed at right-edge hinge line (+X)
	leaf.position = Vector3(DOOR_WIDTH * 0.5, 0.0, 0.0)
	add_child(leaf)
	_leaf_body = leaf

	var offset_center: Vector3 = Vector3(-DOOR_WIDTH * 0.5, DOOR_HEIGHT * 0.5, 0.0)

	var slab_mesh_inst: MeshInstance3D = MeshInstance3D.new()
	slab_mesh_inst.name = "SlabMesh"
	slab_mesh_inst.mesh = _build_slab_array_mesh(Vector3(DOOR_WIDTH, DOOR_HEIGHT, DOOR_DEPTH))
	slab_mesh_inst.material_override = _shared_material
	slab_mesh_inst.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	slab_mesh_inst.position = offset_center
	slab_mesh_inst.set_instance_shader_parameter(PARAM_TINT, Color.WHITE)
	slab_mesh_inst.set_instance_shader_parameter(PARAM_UV_SCALE, Vector2.ONE)
	leaf.add_child(slab_mesh_inst)

	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "SlabCollider"
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(DOOR_WIDTH, DOOR_HEIGHT, DOOR_DEPTH)
	col.shape = box_shape
	col.position = offset_center
	leaf.add_child(col)

	# 3 Brass/Steel Hinges on right edge (local X = 0.0)
	var hinge_heights: Array[float] = [0.28, 1.02, 1.74]
	for i: int in range(hinge_heights.size()):
		var hinge: MeshInstance3D = MeshInstance3D.new()
		hinge.name = "Hinge_" + str(i)
		var cyl: CylinderMesh = CylinderMesh.new()
		cyl.top_radius = 0.009
		cyl.bottom_radius = 0.009
		cyl.height = 0.09
		cyl.radial_segments = 8
		hinge.mesh = cyl
		hinge.material_override = _shared_material
		hinge.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
		hinge.position = Vector3(0.0, hinge_heights[i], DOOR_DEPTH * 0.5 + 0.004)
		hinge.set_instance_shader_parameter(PARAM_TINT, Color(0.75, 0.68, 0.42, 1.0))
		hinge.set_instance_shader_parameter(PARAM_UV_SCALE, Vector2(0.05, 0.05))
		leaf.add_child(hinge)

	# Left-side circular deadbolt/knob (reference image position)
	var knob: MeshInstance3D = MeshInstance3D.new()
	knob.name = "DeadboltKnob"
	var knob_cyl: CylinderMesh = CylinderMesh.new()
	knob_cyl.top_radius = 0.022
	knob_cyl.bottom_radius = 0.026
	knob_cyl.height = 0.025
	knob_cyl.radial_segments = 12
	knob.mesh = knob_cyl
	knob.material_override = _shared_material
	knob.layers = CollisionLayers.RENDER_MASK_INTERACTIVE
	knob.rotation.x = KNOB_BASE_PITCH_RAD
	knob.position = Vector3(-DOOR_WIDTH + 0.065, 1.03, DOOR_DEPTH * 0.5 + 0.012)
	knob.set_instance_shader_parameter(PARAM_TINT, Color(0.68, 0.64, 0.48, 1.0))
	knob.set_instance_shader_parameter(PARAM_UV_SCALE, Vector2(0.05, 0.05))
	leaf.add_child(knob)
	_deadbolt_knob = knob


## Builds a custom [ArrayMesh] box so Front/Back faces map 0..1 UVs directly to the atlas.
func _build_slab_array_mesh(size: Vector3) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5

	# Front face (+Z) mapped 1:1 with texture
	_add_quad(
		st,
		Vector3(-hx, hy, hz),
		Vector3(hx, hy, hz),
		Vector3(hx, -hy, hz),
		Vector3(-hx, -hy, hz),
		Vector3.BACK,
		Rect2(0.0, 0.0, 1.0, 1.0)
	)
	# Back face (-Z)
	_add_quad(
		st,
		Vector3(hx, hy, -hz),
		Vector3(-hx, hy, -hz),
		Vector3(-hx, -hy, -hz),
		Vector3(hx, -hy, -hz),
		Vector3.FORWARD,
		Rect2(0.0, 0.0, 1.0, 1.0)
	)
	# Thin edge strip UVs (sample solid metal border region)
	var edge_uv: Rect2 = Rect2(0.02, 0.02, 0.06, 0.96)
	# Left (-X)
	_add_quad(
		st,
		Vector3(-hx, hy, -hz),
		Vector3(-hx, hy, hz),
		Vector3(-hx, -hy, hz),
		Vector3(-hx, -hy, -hz),
		Vector3.LEFT,
		edge_uv
	)
	# Right (+X)
	_add_quad(
		st,
		Vector3(hx, hy, hz),
		Vector3(hx, hy, -hz),
		Vector3(hx, -hy, -hz),
		Vector3(hx, -hy, hz),
		Vector3.RIGHT,
		edge_uv
	)
	# Top (+Y)
	_add_quad(
		st,
		Vector3(-hx, hy, -hz),
		Vector3(hx, hy, -hz),
		Vector3(hx, hy, hz),
		Vector3(-hx, hy, hz),
		Vector3.UP,
		edge_uv
	)
	# Bottom (-Y)
	_add_quad(
		st,
		Vector3(-hx, -hy, hz),
		Vector3(hx, -hy, hz),
		Vector3(hx, -hy, -hz),
		Vector3(-hx, -hy, -hz),
		Vector3.DOWN,
		edge_uv
	)

	st.generate_tangents()
	return st.commit()


## Appends a two-triangle quad with explicit normal and UV bounds to [SurfaceTool].
func _add_quad(
	st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, n: Vector3, uv_rect: Rect2
) -> void:
	var uv0: Vector2 = uv_rect.position
	var uv1: Vector2 = Vector2(uv_rect.end.x, uv_rect.position.y)
	var uv2: Vector2 = uv_rect.end
	var uv3: Vector2 = Vector2(uv_rect.position.x, uv_rect.end.y)

	st.set_normal(n)
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_normal(n)
	st.set_uv(uv1)
	st.add_vertex(v1)
	st.set_normal(n)
	st.set_uv(uv2)
	st.add_vertex(v2)

	st.set_normal(n)
	st.set_uv(uv0)
	st.add_vertex(v0)
	st.set_normal(n)
	st.set_uv(uv2)
	st.add_vertex(v2)
	st.set_normal(n)
	st.set_uv(uv3)
	st.add_vertex(v3)
