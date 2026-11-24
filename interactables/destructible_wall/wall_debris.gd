## Physical destructible wall chunk or compound island [RigidBody3D] with sleep despawn.
class_name WallDebris
extends RigidBody3D

## Concrete density in kg/m^3 used to derive chunk mass from mesh volume.
const CONCRETE_DENSITY_KG_PER_M3: float = 2400.0

## Minimum mass in kg preventing unstable featherweight Jolt bodies.
const MIN_MASS_KG: float = 2.0

## Default time in seconds debris remains asleep before shrinking out.
const DEFAULT_SLEEP_LIFETIME: float = 6.0

## Maximum lifetime in seconds before a safety timer forces despawn.
const SAFETY_LIFETIME_SEC: float = 25.0

## Duration in seconds for the scale-to-zero shrink despawn animation.
const DESPAWN_SHRINK_DURATION: float = 0.45

## Pre-allocated method name for registering split debris with [DebrisBudget].
const METHOD_REGISTER_DEBRIS: StringName = &"register_debris"

## Pre-allocated deferred method name for splitting an impacted island.
const METHOD_SPLIT_CHUNKS: StringName = &"_split_into_chunks"

## Pre-allocated property path used by [Tween] when shrinking child meshes.
const PROP_SCALE: NodePath = ^"scale"

## Shared fallback outer concrete [StandardMaterial3D] used when null is passed.
static var _fallback_outer_mat: StandardMaterial3D = null

## Shared fallback inner fractured concrete [StandardMaterial3D] used when null is passed.
static var _fallback_inner_mat: StandardMaterial3D = null

## True when this body represents a multi-chunk island capable of splitting on impact.
var _is_island: bool = false

## Guards against splitting a compound island more than once.
var _has_split: bool = false

## Guards against duplicate eviction or post-eviction deferred work.
var _is_evicted: bool = false

## Guards against restarting an active despawn shrink tween.
var _is_despawning: bool = false

## Reference to baked [WallPanelData] used by islands when splitting into single chunks.
var _data: WallPanelData = null

## Chunk indices bundled inside this compound island body.
var _chunk_indices: PackedInt32Array = PackedInt32Array()

## Local-space panel origin of this compound island used to compute chunk offsets.
var _island_center: Vector3 = Vector3.ZERO

## Shared outer concrete [Material] applied to surface 0 of debris meshes.
var _outer_mat: Material = null

## Shared inner concrete [Material] applied to surface 1 of debris meshes.
var _inner_mat: Material = null

## Squared speed threshold above which an island splits upon body contact.
var _split_speed_sq: float = 20.25

## Minimum chunk volume in m^3 spawned when splitting an island.
var _vol_threshold: float = 0.025

## Duration in seconds this body must stay asleep before despawning.
var _sleep_lifetime: float = DEFAULT_SLEEP_LIFETIME

## Linear speed squared sampled during the previous physics tick before impact resolution.
var _prev_speed_sq: float = 0.0

## Monotonic token invalidating stale sleep timers if the body wakes up early.
var _sleep_token: int = 0

## Active [Tween] shrinking child meshes to zero on despawn.
var _despawn_tween: Tween = null


## Configures debris layers, disables idle ticking, binds sleep state, and starts safety timer.
func _ready() -> void:
	collision_layer = CollisionLayers.MASK_DEBRIS
	collision_mask = CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_DEBRIS
	set_process(false)
	set_physics_process(_is_island and not _has_split)
	Utilities.safe_connect(sleeping_state_changed, _on_sleeping_state_changed)
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree):
		var safety_timer: SceneTreeTimer = tree.create_timer(SAFETY_LIFETIME_SEC, false)
		safety_timer.timeout.connect(_on_safety_timer_timeout, Object.CONNECT_ONE_SHOT)


## Cleans up any active despawn [Tween] when exiting the scene tree.
func _exit_tree() -> void:
	Utilities.safe_kill_tween(_despawn_tween)


## Samples pre-collision squared speed only on active, un-split island bodies.
func _physics_process(_delta: float) -> void:
	if _is_island and not _has_split:
		_prev_speed_sq = linear_velocity.length_squared()


## Initializes this body as a single fractured chunk with volume-proportional mass.
func setup_single(
	chunk_mesh: ArrayMesh,
	chunk_shape: ConvexPolygonShape3D,
	volume: float,
	outer_mat: Material,
	inner_mat: Material,
	sleep_lifetime: float = 6.0
) -> void:
	_is_island = false
	_has_split = false
	_sleep_lifetime = maxf(sleep_lifetime, 0.1)
	mass = maxf(volume * CONCRETE_DENSITY_KG_PER_M3, MIN_MASS_KG)
	set_physics_process(false)

	var resolved_outer: Material = _resolve_material(outer_mat, false)
	var resolved_inner: Material = _resolve_material(inner_mat, true)
	var mesh_inst: MeshInstance3D = _create_chunk_mesh_instance(
		chunk_mesh, resolved_outer, resolved_inner
	)
	add_child(mesh_inst)

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.shape = chunk_shape
	add_child(col_shape)


## Initializes this body as a compound island that fractures into single chunks on hard impact.
func setup_island(
	data: WallPanelData,
	chunk_indices: PackedInt32Array,
	island_center: Vector3,
	outer_mat: Material,
	inner_mat: Material,
	split_speed: float = 4.5,
	vol_threshold: float = 0.025,
	sleep_lifetime: float = 6.0
) -> void:
	if not is_instance_valid(data) or chunk_indices.is_empty():
		set_physics_process(false)
		return

	_is_island = true
	_has_split = false
	_data = data
	_chunk_indices = chunk_indices
	_island_center = island_center
	_outer_mat = _resolve_material(outer_mat, false)
	_inner_mat = _resolve_material(inner_mat, true)
	_split_speed_sq = split_speed * split_speed
	_vol_threshold = vol_threshold
	_sleep_lifetime = maxf(sleep_lifetime, 0.1)

	var total_volume: float = 0.0
	for idx: int in chunk_indices:
		if idx < 0 or idx >= data.chunk_centroids.size():
			continue
		var offset: Vector3 = data.chunk_centroids[idx] - island_center
		var chunk_mesh: ArrayMesh = (
			data.chunk_meshes[idx] if idx < data.chunk_meshes.size() else null
		)
		var mesh_inst: MeshInstance3D = _create_chunk_mesh_instance(
			chunk_mesh, _outer_mat, _inner_mat
		)
		mesh_inst.position = offset
		add_child(mesh_inst)

		if idx < data.chunk_shapes.size() and is_instance_valid(data.chunk_shapes[idx]):
			var col_shape: CollisionShape3D = CollisionShape3D.new()
			col_shape.position = offset
			col_shape.shape = data.chunk_shapes[idx]
			add_child(col_shape)

		if idx < data.chunk_volumes.size():
			total_volume += data.chunk_volumes[idx]

	mass = maxf(total_volume * CONCRETE_DENSITY_KG_PER_M3, MIN_MASS_KG)
	contact_monitor = true
	max_contacts_reported = 4
	Utilities.safe_connect(body_entered, _on_body_entered)
	set_physics_process(true)
	print(
		"WallDebris: Island configured (",
		chunk_indices.size(),
		" chunks, mass=",
		snappedf(mass, 0.1),
		"kg)."
	)


## Immediately stops despawn animations and queues this debris body for deletion.
func evict_now() -> void:
	if _is_evicted:
		return
	_is_evicted = true
	_is_despawning = true
	set_physics_process(false)
	Utilities.safe_kill_tween(_despawn_tween)
	if is_instance_valid(self) and not is_queued_for_deletion():
		queue_free()


## Checks impact speed when an un-split island hits geometry and defers splitting.
func _on_body_entered(_body: Node) -> void:
	if not _is_island or _has_split or _is_evicted:
		return
	var peak_speed_sq: float = maxf(linear_velocity.length_squared(), _prev_speed_sq)
	if peak_speed_sq >= _split_speed_sq:
		_has_split = true
		set_physics_process(false)
		print("WallDebris: Island impact triggered deferred split.")
		call_deferred(METHOD_SPLIT_CHUNKS)


## Splits an impacted island into single chunk [WallDebris] bodies and frees the island.
func _split_into_chunks() -> void:
	if _is_evicted or is_queued_for_deletion():
		return
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not is_instance_valid(_data):
		evict_now()
		return
	var parent_node: Node = get_parent()
	if not is_instance_valid(parent_node):
		evict_now()
		return

	var origin_xform: Transform3D = global_transform
	var clean_basis: Basis = origin_xform.basis.orthonormalized()
	var base_vel: Vector3 = linear_velocity
	var base_ang_vel: Vector3 = angular_velocity
	var budget: Node = get_node_or_null("/root/DebrisBudget")
	var parent_3d: Node3D = parent_node as Node3D

	# Free the parent island slot first so child registrations do not count it against budget.
	evict_now()

	var spawned_count: int = 0
	for idx: int in _chunk_indices:
		if idx < 0 or idx >= _data.chunk_volumes.size():
			continue
		var vol: float = _data.chunk_volumes[idx]
		if vol < _vol_threshold:
			continue
		if idx >= _data.chunk_meshes.size() or idx >= _data.chunk_shapes.size():
			continue

		var local_offset: Vector3 = _data.chunk_centroids[idx] - _island_center
		var piece_xform: Transform3D = Transform3D(clean_basis, origin_xform * local_offset)
		var piece: WallDebris = WallDebris.new()
		piece.setup_single(
			_data.chunk_meshes[idx],
			_data.chunk_shapes[idx],
			vol,
			_outer_mat,
			_inner_mat,
			_sleep_lifetime
		)
		if is_instance_valid(parent_3d):
			piece.transform = parent_3d.global_transform.affine_inverse() * piece_xform
		parent_node.add_child(piece)
		if not is_instance_valid(parent_3d):
			piece.global_transform = piece_xform

		var outward_dir: Vector3 = clean_basis * local_offset
		if outward_dir.length_squared() > 0.0001:
			outward_dir = outward_dir.normalized()
		else:
			outward_dir = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)).normalized()

		piece.linear_velocity = (
			base_vel + outward_dir * randf_range(1.2, 2.6) + Vector3.UP * randf_range(0.4, 1.1)
		)
		piece.angular_velocity = (
			base_ang_vel
			+ Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
		)

		if is_instance_valid(budget) and budget.has_method(METHOD_REGISTER_DEBRIS):
			budget.call(METHOD_REGISTER_DEBRIS, piece)
		spawned_count += 1

	print("WallDebris: Split island into ", spawned_count, " single chunks.")


## Starts a sleep-lifetime despawn timer on sleep and cancels pending timers if woken.
func _on_sleeping_state_changed() -> void:
	if _is_evicted or _is_despawning:
		return
	_sleep_token += 1
	if not sleeping:
		if _is_island and not _has_split:
			set_physics_process(true)
		return

	set_physics_process(false)
	var token: int = _sleep_token
	var tree: SceneTree = get_tree()
	if is_instance_valid(tree):
		var sleep_timer: SceneTreeTimer = tree.create_timer(_sleep_lifetime, false)
		sleep_timer.timeout.connect(_on_sleep_timer_timeout.bind(token), Object.CONNECT_ONE_SHOT)


## Despawns this body if it remained continuously asleep for [member _sleep_lifetime].
func _on_sleep_timer_timeout(token: int) -> void:
	if _is_evicted or _is_despawning:
		return
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not sleeping or token != _sleep_token:
		return
	_begin_despawn()


## Forces despawn when the 25-second safety fallback timer expires.
func _on_safety_timer_timeout() -> void:
	if _is_evicted or _is_despawning:
		return
	_begin_despawn()


## Shrinks all child [MeshInstance3D] nodes over 0.45s in parallel, then frees this body.
func _begin_despawn() -> void:
	if _is_evicted or _is_despawning:
		return
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_is_despawning = true
	set_physics_process(false)
	_despawn_tween = Utilities.reset_tween(self, _despawn_tween)
	if not is_instance_valid(_despawn_tween):
		queue_free()
		return

	var has_mesh: bool = false
	for child: Node in get_children():
		if child is MeshInstance3D:
			var mesh_node: MeshInstance3D = child as MeshInstance3D
			if not has_mesh:
				_despawn_tween.tween_property(
					mesh_node, PROP_SCALE, Vector3.ZERO, DESPAWN_SHRINK_DURATION
				)
				has_mesh = true
			else:
				_despawn_tween.parallel().tween_property(
					mesh_node, PROP_SCALE, Vector3.ZERO, DESPAWN_SHRINK_DURATION
				)

	if not has_mesh:
		Utilities.safe_kill_tween(_despawn_tween)
		queue_free()
		return
	_despawn_tween.tween_callback(queue_free)


## Creates a render-layer-1 [MeshInstance3D] with outer/inner surface concrete materials.
func _create_chunk_mesh_instance(
	chunk_mesh: ArrayMesh, outer_mat: Material, inner_mat: Material
) -> MeshInstance3D:
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.layers = CollisionLayers.RENDER_MASK_ENVIRONMENT
	mesh_inst.mesh = chunk_mesh
	if is_instance_valid(chunk_mesh):
		var surf_count: int = chunk_mesh.get_surface_count()
		if surf_count >= 1:
			mesh_inst.set_surface_override_material(0, outer_mat)
		if surf_count >= 2:
			mesh_inst.set_surface_override_material(1, inner_mat)
	return mesh_inst


## Returns [param mat] or a cached fallback concrete [StandardMaterial3D] for outer/inner sides.
static func _resolve_material(mat: Material, is_inner: bool) -> Material:
	if is_instance_valid(mat):
		return mat
	if is_inner:
		if not is_instance_valid(_fallback_inner_mat):
			_fallback_inner_mat = _create_fallback_material(Color(0.38, 0.37, 0.34), 0.95)
		return _fallback_inner_mat
	if not is_instance_valid(_fallback_outer_mat):
		_fallback_outer_mat = _create_fallback_material(Color(0.56, 0.56, 0.53), 0.9)
	return _fallback_outer_mat


## Builds a matte concrete [StandardMaterial3D] fallback with the given [param albedo] color.
static func _create_fallback_material(albedo: Color, roughness_val: float) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness_val
	return mat
