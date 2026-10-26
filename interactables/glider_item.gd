@tool
## A specialized physics object that restricts player movement when held and enables gliding.
##
## Differs from standard [PickableObject] by using a dedicated animation tween to pull the player
## towards an anchor point before pickup, rather than pulling the object to the player.
class_name GliderItem
extends RigidBody3D

## Physics bitmask for Layer 3 (Interactive) so the player walks through without stumbling.
const LAYER_INTERACTIVE_BIT: int = 4

## Duration in seconds for the player pull-in tween.
const PICKUP_TWEEN_DURATION: float = 0.4

## Duration in seconds for the detachment animation down to the floor.
const DETACH_ANIM_DURATION: float = 1.0

## Distance ahead of the player where the detached glider lands on the floor.
const DETACH_SPAWN_DISTANCE: float = 4.0

## Overall wingspan (X), thickness (Y), and chord length (Z) in meters.
const GLIDER_SIZE: Vector3 = Vector3(8.0, 0.2, 6.0)

## Half thickness of the glider along the vertical Y axis (total height: 0.2m).
const HALF_HEIGHT: float = 0.1

## Dark batwing albedo color preserving surface normal shading.
const BAT_BLACK_COLOR: Color = Color(0.08, 0.08, 0.08, 1.0)

## Method and property identifiers pre-allocated for performance.
const METHOD_SET_MACHINE_LOCK: StringName = &"set_machine_lock"
const METHOD_ATTACH_ITEM: StringName = &"attach_item_to_weapon_holder"
const METHOD_SET_DIRECTION: StringName = &"set_direction"
const PROP_INTERACTION_COMP: StringName = &"interaction_component"
const PROP_LOCOMOTION_COMP: StringName = &"locomotion_component"
const PROP_CAMERA_CTRL: StringName = &"camera_controller"
const PROP_CAN_SPRINT: StringName = &"can_sprint"
const PROP_POSITION: StringName = &"position"
const PROP_GLOBAL_POS: NodePath = ^"global_position"
const PROP_QUATERNION: NodePath = ^"quaternion"

## Caches the character currently carrying the glider to manipulate their movement states.
var current_holder: CharacterBody3D = null

## Active tween pulling the player to the anchor.
var _pickup_tween: Tween = null

## Active tween animating the glider down to the floor upon detachment.
var _detach_tween: Tween = null

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var player_anchor: Marker3D = $PlayerAnchor


## Initializes the procedural batwing mesh and configures physics state at runtime.
func _ready() -> void:
	_setup_batfleck_mesh()

	if Engine.is_editor_hint():
		return

	set_process(false)
	set_physics_process(false)
	assert(is_instance_valid(player_anchor), "GliderItem: Missing PlayerAnchor.")
	collision_layer = LAYER_INTERACTIVE_BIT
	collision_mask = CollisionLayers.MASK_ENVIRONMENT


## Generates the scaled Batfleck Batwing profile (8m span x 6m length) on [member mesh_instance].
func _setup_batfleck_mesh() -> void:
	if not is_instance_valid(mesh_instance):
		mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not is_instance_valid(mesh_instance):
		return

	if not is_instance_valid(collision_shape):
		collision_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if is_instance_valid(collision_shape):
		var box: BoxShape3D = collision_shape.shape as BoxShape3D
		if is_instance_valid(box):
			box.size = GLIDER_SIZE

	# Batfleck polygon profile scaled to 8.0m wingspan (X) and 6.0m chord length (Z).
	# Head/ears at -Z (forward nose), tail tip at +Z (rear).
	var outline: PackedVector2Array = PackedVector2Array(
		[
			Vector2(0.0, -1.9413),
			Vector2(-0.1811, -2.0472),
			Vector2(-0.2717, -3.0),
			Vector2(-0.4829, -2.0472),
			Vector2(-1.8112, -2.2941),
			Vector2(-3.6227, -2.4705),
			Vector2(-4.0, -1.0587),
			Vector2(-3.2453, 0.5295),
			Vector2(-2.6416, -0.5295),
			Vector2(-1.8112, 1.5882),
			Vector2(-1.132, 0.3528),
			Vector2(-0.4829, 2.0472),
			Vector2(0.0, 3.0),
			Vector2(0.4829, 2.0472),
			Vector2(1.132, 0.3528),
			Vector2(1.8112, 1.5882),
			Vector2(2.6416, -0.5295),
			Vector2(3.2453, 0.5295),
			Vector2(4.0, -1.0587),
			Vector2(3.6227, -2.4705),
			Vector2(1.8112, -2.2941),
			Vector2(0.4829, -2.0472),
			Vector2(0.2717, -3.0),
			Vector2(0.1811, -2.0472),
		]
	)

	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	if triangles.is_empty():
		push_error("GliderItem: Batfleck polygon triangulation failed.")
		return

	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = BAT_BLACK_COLOR
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	st.set_material(mat)

	# 1. Top face (+Y): Godot CW front-face from +Y requires cross-product Y < 0.0.
	st.set_normal(Vector3.UP)
	for t: int in range(0, triangles.size(), 3):
		var p0: Vector3 = Vector3(outline[triangles[t]].x, HALF_HEIGHT, outline[triangles[t]].y)
		var p1: Vector3 = Vector3(
			outline[triangles[t + 1]].x, HALF_HEIGHT, outline[triangles[t + 1]].y
		)
		var p2: Vector3 = Vector3(
			outline[triangles[t + 2]].x, HALF_HEIGHT, outline[triangles[t + 2]].y
		)
		var norm: Vector3 = (p1 - p0).cross(p2 - p0)
		if norm.y > 0.0:
			st.add_vertex(p0)
			st.add_vertex(p2)
			st.add_vertex(p1)
		else:
			st.add_vertex(p0)
			st.add_vertex(p1)
			st.add_vertex(p2)

	# 2. Bottom face (-Y): Godot CW front-face from -Y requires cross-product Y > 0.0.
	st.set_normal(Vector3.DOWN)
	for t: int in range(0, triangles.size(), 3):
		var p0: Vector3 = Vector3(outline[triangles[t]].x, -HALF_HEIGHT, outline[triangles[t]].y)
		var p1: Vector3 = Vector3(
			outline[triangles[t + 1]].x, -HALF_HEIGHT, outline[triangles[t + 1]].y
		)
		var p2: Vector3 = Vector3(
			outline[triangles[t + 2]].x, -HALF_HEIGHT, outline[triangles[t + 2]].y
		)
		var norm: Vector3 = (p1 - p0).cross(p2 - p0)
		if norm.y < 0.0:
			st.add_vertex(p0)
			st.add_vertex(p2)
			st.add_vertex(p1)
		else:
			st.add_vertex(p0)
			st.add_vertex(p1)
			st.add_vertex(p2)

	# 3. Perimeter side walls: outline is CW in XZ; wind CW from outside with flat normals.
	var count: int = outline.size()
	for i: int in range(count):
		var next_i: int = (i + 1) % count
		var t0: Vector3 = Vector3(outline[i].x, HALF_HEIGHT, outline[i].y)
		var t1: Vector3 = Vector3(outline[next_i].x, HALF_HEIGHT, outline[next_i].y)
		var b0: Vector3 = Vector3(outline[i].x, -HALF_HEIGHT, outline[i].y)
		var b1: Vector3 = Vector3(outline[next_i].x, -HALF_HEIGHT, outline[next_i].y)

		var edge_dir: Vector3 = (t1 - t0).normalized()
		var wall_normal: Vector3 = edge_dir.cross(Vector3.UP).normalized()
		st.set_normal(wall_normal)

		st.add_vertex(t0)
		st.add_vertex(t1)
		st.add_vertex(b0)

		st.add_vertex(t1)
		st.add_vertex(b1)
		st.add_vertex(b0)

	mesh_instance.mesh = st.commit()


## Toggles the visual rendering of the glider.
## [param p_is_visible]: Boolean state for mesh visibility.
func set_glider_mesh_visible(p_is_visible: bool) -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.visible = p_is_visible


## Locks the player and tweens them to the [member player_anchor] before attaching.
## [param hold_position]: The target socket on the player's weapon mount.
## [param player]: The player executing the interaction.
func pick_up(hold_position: Marker3D, player: CharacterBody3D) -> void:
	print("GliderItem: pick_up() called. Initiating tween sequence for player.")

	if is_instance_valid(_detach_tween):
		_detach_tween.kill()

	current_holder = player

	freeze = true
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_NONE

	if player.has_method(METHOD_SET_MACHINE_LOCK):
		player.call(METHOD_SET_MACHINE_LOCK, true)

	if is_instance_valid(_pickup_tween):
		_pickup_tween.kill()
	_pickup_tween = create_tween()

	var target_pos: Vector3 = Vector3(
		player_anchor.global_position.x, player.global_position.y, player_anchor.global_position.z
	)

	(
		_pickup_tween
		. tween_property(player, PROP_GLOBAL_POS, target_pos, PICKUP_TWEEN_DURATION)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN_OUT)
	)
	_pickup_tween.tween_callback(_on_player_reached_anchor.bind(player, hold_position))


## Restores player sprint ability, detaches glider, and applies throwing impulse.
## [param force]: The 3D directional vector representing throw strength.
## [param scene_root]: The root node to re-parent the glider into.
func throw_item(force: Vector3, scene_root: Node) -> void:
	print("GliderItem: throw_item() called. Releasing glider into the world.")

	if is_instance_valid(_pickup_tween):
		_pickup_tween.kill()
	if is_instance_valid(_detach_tween):
		_detach_tween.kill()

	var actor: CharacterBody3D = current_holder
	_restore_holder_sprint()
	Events.item_dropped.emit(self, actor)

	if is_instance_valid(scene_root):
		Utilities.reparent_keep_transform(self, scene_root)

	global_basis = global_basis.orthonormalized()
	set_glider_mesh_visible(true)
	freeze = false
	collision_layer = LAYER_INTERACTIVE_BIT
	collision_mask = CollisionLayers.MASK_ENVIRONMENT

	apply_central_impulse(force)


## Detaches glider, animates it to the floor 4m ahead over 1.0s, and freezes physics.
## [param scene_root]: The root node to re-parent the glider into.
## [param drop_pos]: Safe 3D coordinate to spawn glider at (usually player feet).
func drop_item(scene_root: Node, drop_pos: Vector3) -> void:
	print("GliderItem: drop_item() called. Detaching from player.")

	if is_instance_valid(_pickup_tween):
		_pickup_tween.kill()
	if is_instance_valid(_detach_tween):
		_detach_tween.kill()

	var actor: CharacterBody3D = current_holder
	_restore_holder_sprint()
	Events.item_dropped.emit(self, actor)

	if is_instance_valid(scene_root):
		Utilities.reparent_keep_transform(self, scene_root)

	# Strip any accumulated float drift before interpolating quaternion rotation.
	global_basis = global_basis.orthonormalized()
	set_glider_mesh_visible(true)

	var forward_dir: Vector3 = Vector3.FORWARD
	var base_pos: Vector3 = drop_pos
	if is_instance_valid(actor):
		base_pos = actor.global_position
		var cam_val: Variant = actor.get(PROP_CAMERA_CTRL)
		if cam_val is CameraController:
			var cam_ctrl: CameraController = cam_val
			if is_instance_valid(cam_ctrl.camera):
				forward_dir = -cam_ctrl.camera.global_transform.basis.z
		else:
			forward_dir = -actor.global_transform.basis.z

	forward_dir.y = 0.0
	if forward_dir.length_squared() < 0.001:
		forward_dir = Vector3.FORWARD
	else:
		forward_dir = forward_dir.normalized()

	var target_pos: Vector3 = base_pos + forward_dir * DETACH_SPAWN_DISTANCE
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_start: Vector3 = target_pos + Vector3(0.0, 1.5, 0.0)
	var ray_end: Vector3 = target_pos + Vector3(0.0, -4.0, 0.0)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_start, ray_end, CollisionLayers.MASK_ENVIRONMENT
	)
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var raw_pos: Variant = hit.get(PROP_POSITION)
		if raw_pos is Vector3:
			target_pos.y = raw_pos.y + HALF_HEIGHT
		else:
			target_pos.y = base_pos.y + HALF_HEIGHT
	else:
		target_pos.y = base_pos.y + HALF_HEIGHT

	# Align local -Z (bat head) with player forward direction.
	var target_basis: Basis = Basis.looking_at(forward_dir, Vector3.UP)
	var target_quat: Quaternion = target_basis.get_rotation_quaternion()

	freeze = true
	collision_layer = CollisionLayers.MASK_NONE
	collision_mask = CollisionLayers.MASK_ENVIRONMENT

	_detach_tween = create_tween().set_parallel(true)
	(
		_detach_tween
		. tween_property(self, PROP_GLOBAL_POS, target_pos, DETACH_ANIM_DURATION)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_detach_tween
		. tween_property(self, PROP_QUATERNION, target_quat, DETACH_ANIM_DURATION)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_OUT)
	)
	_detach_tween.chain().tween_callback(_on_detach_completed.bind(target_pos, target_basis))


## Finalizes glider landing by resetting interactive collision and enforcing frozen physics.
## [param target_pos]: Settled floor position for the glider.
## [param target_basis]: Settled horizontal basis for the glider.
func _on_detach_completed(target_pos: Vector3, target_basis: Basis) -> void:
	print("GliderItem: Detachment animation completed. Locking position on floor.")
	global_position = target_pos
	global_basis = target_basis.orthonormalized()
	freeze = true
	collision_layer = LAYER_INTERACTIVE_BIT
	collision_mask = CollisionLayers.MASK_ENVIRONMENT


## Callback after tween finishes. Attaches glider and zeros local offsets to prevent drift.
## [param player]: The character node that was moved.
## [param _unused_hold_position]: The weapon mount socket.
func _on_player_reached_anchor(player: CharacterBody3D, _unused_hold_position: Marker3D) -> void:
	print("GliderItem: Player reached anchor. Attaching glider to weapon holder.")

	var raw_interaction: Variant = player.get(PROP_INTERACTION_COMP)
	if raw_interaction is Node:
		var interaction_comp: Node = raw_interaction
		if interaction_comp.has_method(METHOD_ATTACH_ITEM):
			interaction_comp.call(METHOD_ATTACH_ITEM, self, player_anchor, player)
	else:
		transform.origin = Vector3.ZERO
		transform.basis = Basis.IDENTITY

	var raw_loco: Variant = player.get(PROP_LOCOMOTION_COMP)
	if raw_loco is Node:
		var loco_comp: Node = raw_loco
		loco_comp.set(PROP_CAN_SPRINT, false)

	if player.has_method(METHOD_SET_MACHINE_LOCK):
		player.call(METHOD_SET_MACHINE_LOCK, false)


## Restores sprint capability on the cached holder and clears the reference.
func _restore_holder_sprint() -> void:
	if is_instance_valid(current_holder):
		var raw_cam: Variant = current_holder.get(PROP_CAMERA_CTRL)
		if raw_cam is CameraController:
			var cam_ctrl: CameraController = raw_cam
			if is_instance_valid(cam_ctrl.head):
				cam_ctrl.head.rotation.y = 0.0

		var raw_loco: Variant = current_holder.get(PROP_LOCOMOTION_COMP)
		if raw_loco is Node:
			var loco_comp: Node = raw_loco
			loco_comp.set(PROP_CAN_SPRINT, true)
			if loco_comp.has_method(METHOD_SET_DIRECTION):
				loco_comp.call(METHOD_SET_DIRECTION, Vector3.ZERO)
	current_holder = null
