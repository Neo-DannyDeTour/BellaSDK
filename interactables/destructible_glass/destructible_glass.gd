@tool
## Destructible glass pane with deferred procedural shard generation on impact.
class_name DestructibleGlass
extends RigidBody3D

## Emitted when glass receives breaking damage or high-speed impact.
signal glass_broken

@export_group("Dimensions & Shards")
## Total size dimensions of rectangular glass pane.
@export var glass_size: Vector2 = Vector2(2.0, 2.0):
	set(value):
		glass_size = value
		_apply_dimensions()
		_update_material()

## Thickness of glass pane along Z axis.
@export var glass_thickness: float = 0.1:
	set(value):
		glass_thickness = value
		_apply_dimensions()

## Number of vertical subdivision rows for shard generation.
@export var shard_rows: int = 3

## Number of horizontal subdivision columns for shard generation.
@export var shard_cols: int = 3

@export_group("Damage Properties")
## Toggles whether shards detach and explode or remain intact.
@export var can_break: bool = true:
	set(value):
		can_break = value
		_update_material()

## Distance radius around impact point where shards detach.
@export var shatter_radius: float = 0.8

## Minimum incoming damage required to shatter the pane.
@export var damage_threshold: float = 10.0

## Minimum relative collision speed required to shatter glass.
@export var impact_velocity_threshold: float = 5.0

## Time in seconds before detached shards scale down and despawn.
@export var shard_cleanup_time: float = 5.0

## Audio stream played when glass pane breaks.
@export var break_sound: AudioStream

@export_group("Shader Parameters")
## Base color tint assigned to glass material shader.
@export var glass_color: Color = Color(0.8, 0.9, 1.0, 0.4):
	set(value):
		glass_color = value
		_update_material()

## Grid wireframe color used for reinforced glass shading.
@export var net_color: Color = Color(0.1, 0.1, 0.1, 1.0):
	set(value):
		net_color = value
		_update_material()

## UV scale factor applied to reinforcement net shader.
@export var net_scale: float = 20.0:
	set(value):
		net_scale = value
		_update_material()

## Tracks whether primary intact sheet has shattered.
var _is_broken: bool = false

## Tracks whether shard rigid bodies have been generated.
var _shards_generated: bool = false

## Two-dimensional grid storing active [DestructibleGlassShard] instances.
var _shard_grid: Array[Array] = []

## Visual mesh instance of intact glass sheet.
@onready var intact_mesh: MeshInstance3D = $IntactMesh

## Collision shape of intact glass sheet.
@onready var intact_collision: CollisionShape3D = $IntactCollision

## Hierarchy parent node containing generated shard nodes.
@onready var shards_container: Node3D = $ShardsContainer


## Physics shard piece instantiated dynamically when glass shatters.
class DestructibleGlassShard:
	extends RigidBody3D

	## Reference to root [DestructibleGlass] controller.
	var main_glass: DestructibleGlass

	## Column index of shard within grid.
	var grid_x: int = -1

	## Row index of shard within grid.
	var grid_y: int = -1

	## Indicates whether this shard has detached.
	var is_destroyed: bool = false

	## Initializes contact reporting and signals for shard body.
	func _ready() -> void:
		print("GlassShard: Initializing shard at (", grid_x, ", ", grid_y, ").")
		contact_monitor = true
		max_contacts_reported = 1
		body_entered.connect(_on_shard_body_entered)

	## Relays damage impulses to [DestructibleGlass] or applies physics force.
	func take_damage(amount: float, hit_position: Vector3, hit_dir: Vector3) -> void:
		if main_glass == null:
			return

		print("GlassShard: take_damage registered. Relaying to root glass node.")
		if freeze and not is_destroyed:
			main_glass.chip_glass(hit_position, hit_dir)
		elif not freeze:
			var impulse: Vector3 = hit_dir * (amount * 0.5)
			var offset: Vector3 = hit_position - global_position
			apply_impulse(impulse, offset)

	## Evaluates impact speed on frozen shards to trigger further breakage.
	func _on_shard_body_entered(body: Node) -> void:
		if not freeze or is_destroyed or main_glass == null:
			return

		var speed: float = 0.0
		var rel_vel: Vector3 = Vector3.ZERO

		if body is RigidBody3D:
			var rb: RigidBody3D = body as RigidBody3D
			rel_vel = rb.linear_velocity - linear_velocity
			speed = rel_vel.length()
		elif body is CharacterBody3D:
			var cb: CharacterBody3D = body as CharacterBody3D
			rel_vel = cb.velocity
			speed = rel_vel.length()

		if speed >= main_glass.impact_velocity_threshold:
			print("GlassShard: Physical impact velocity met. Relaying to root.")
			main_glass.chip_glass(global_position, rel_vel.normalized())


## Validates dimensions, configures audio, and binds collision callbacks.
func _ready() -> void:
	print("DestructibleGlass: Initializing glass pane: ", name)
	_apply_dimensions()
	_update_material()

	if Engine.is_editor_hint():
		return

	if not scale.is_equal_approx(Vector3.ONE):
		glass_size = Vector2(glass_size.x * scale.x, glass_size.y * scale.y)
		glass_thickness *= scale.z
		scale = Vector3.ONE

	body_entered.connect(_on_body_entered)


## Updates intact mesh and collision shapes matching exported dimensions.
func _apply_dimensions() -> void:
	if not is_inside_tree():
		return

	var mesh_inst: MeshInstance3D = get_node_or_null("IntactMesh") as MeshInstance3D
	var coll: CollisionShape3D = get_node_or_null("IntactCollision") as CollisionShape3D
	var dimensions: Vector3 = Vector3(glass_size.x, glass_size.y, glass_thickness)

	if mesh_inst != null and mesh_inst.mesh is BoxMesh:
		(mesh_inst.mesh as BoxMesh).size = dimensions

	if coll != null and coll.shape is BoxShape3D:
		(coll.shape as BoxShape3D).size = dimensions


## Refreshes shader uniforms on intact mesh and instantiated shards.
func _update_material() -> void:
	if not is_inside_tree():
		return

	print("DestructibleGlass: Updating shader uniforms on: ", name)
	var mesh_inst: MeshInstance3D = get_node_or_null("IntactMesh") as MeshInstance3D
	if mesh_inst != null:
		_apply_instance_shader_parameters(mesh_inst)

	if not _shards_generated:
		return

	var container: Node3D = get_node_or_null("ShardsContainer") as Node3D
	if container != null:
		for child: Node in container.get_children():
			if child is RigidBody3D:
				for sub_child: Node in child.get_children():
					if sub_child is MeshInstance3D:
						_apply_instance_shader_parameters(sub_child as MeshInstance3D)


## Writes color, scale, and armor properties to mesh instance uniforms.
func _apply_instance_shader_parameters(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.set_instance_shader_parameter("is_armored", not can_break)
	mesh_instance.set_instance_shader_parameter("glass_scale", glass_size)
	mesh_instance.set_instance_shader_parameter("glass_color", glass_color)
	mesh_instance.set_instance_shader_parameter("net_color", net_color)
	mesh_instance.set_instance_shader_parameter("net_scale", net_scale)


## Processes damage taken, initiating glass shatter or localized chipping.
func take_damage(amount: float, hit_position: Vector3, hit_dir: Vector3) -> void:
	print("DestructibleGlass: take_damage registered: ", amount)
	if amount >= damage_threshold:
		if not _is_broken:
			_is_broken = true
			call_deferred("_break_initial", hit_position, hit_dir)
		else:
			call_deferred("chip_glass", hit_position, hit_dir)


## Inspects physical body velocities colliding with intact pane.
func _on_body_entered(body: Node) -> void:
	if _is_broken:
		return

	print("DestructibleGlass: Body impact detected.")
	var speed: float = 0.0
	var rel_vel: Vector3 = Vector3.ZERO
	var impact_pos: Vector3 = global_position

	if body is Node3D:
		impact_pos = (body as Node3D).global_position

	if body is RigidBody3D:
		var rb: RigidBody3D = body as RigidBody3D
		rel_vel = rb.linear_velocity - linear_velocity
		speed = rel_vel.length()
	elif body is CharacterBody3D:
		var cb: CharacterBody3D = body as CharacterBody3D
		rel_vel = cb.velocity
		speed = rel_vel.length()

	if speed >= impact_velocity_threshold:
		print("DestructibleGlass: Impact velocity met. Breaking.")
		_is_broken = true
		var hit_dir: Vector3 = rel_vel.normalized()
		call_deferred("_break_initial", impact_pos, hit_dir)


## Generates shard procedural meshes and rigid bodies lazily on break.
func _precalculate_shards() -> void:
	print("DestructibleGlass: Building shard grid lazily.")
	_shards_generated = true

	var size: Vector3 = Vector3(glass_size.x, glass_size.y, glass_thickness)
	var cell_width: float = size.x / float(shard_cols)
	var cell_height: float = size.y / float(shard_rows)
	var half_size_x: float = size.x / 2.0
	var half_size_y: float = size.y / 2.0
	var half_thickness: float = size.z / 2.0

	var grid_points: Array[Array] = []
	var offset_range_x: float = cell_width * 0.4
	var offset_range_y: float = cell_height * 0.4

	for row: int in range(shard_rows + 1):
		var row_points: Array[Vector2] = []
		for col: int in range(shard_cols + 1):
			var base_x: float = -half_size_x + col * cell_width
			var base_y: float = -half_size_y + row * cell_height
			var pt: Vector2 = Vector2(base_x, base_y)

			if col > 0 and col < shard_cols and row > 0 and row < shard_rows:
				pt.x += randf_range(-offset_range_x, offset_range_x)
				pt.y += randf_range(-offset_range_y, offset_range_y)

			row_points.append(pt)
		grid_points.append(row_points)

	var active_mat: Material = intact_mesh.material_override
	if active_mat == null:
		active_mat = intact_mesh.get_surface_override_material(0)

	_shard_grid.clear()

	for row: int in range(shard_rows):
		var row_arr: Array[DestructibleGlassShard] = []
		for col: int in range(shard_cols):
			var shard_body: DestructibleGlassShard = DestructibleGlassShard.new()
			shard_body.main_glass = self
			shard_body.grid_x = col
			shard_body.grid_y = row
			shard_body.collision_layer = CollisionLayers.MASK_DEBRIS
			shard_body.collision_mask = (
				CollisionLayers.MASK_ENVIRONMENT | CollisionLayers.MASK_PLAYER
			)

			var v1: Vector2 = grid_points[row][col]
			var v2: Vector2 = grid_points[row][col + 1]
			var v3: Vector2 = grid_points[row + 1][col + 1]
			var v4: Vector2 = grid_points[row + 1][col]

			var center_x: float = (v1.x + v2.x + v3.x + v4.x) / 4.0
			var center_y: float = (v1.y + v2.y + v3.y + v4.y) / 4.0
			var center: Vector3 = Vector3(center_x, center_y, 0)

			var lv1: Vector2 = v1 - Vector2(center.x, center.y)
			var lv2: Vector2 = v2 - Vector2(center.x, center.y)
			var lv3: Vector2 = v3 - Vector2(center.x, center.y)
			var lv4: Vector2 = v4 - Vector2(center.x, center.y)

			var shard_mesh_inst: MeshInstance3D = MeshInstance3D.new()
			var st: SurfaceTool = SurfaceTool.new()

			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_add_faces_to_surfacetool(
				st, lv1, lv2, lv3, lv4, v1, v2, v3, v4, half_thickness, Vector2(size.x, size.y)
			)
			shard_mesh_inst.mesh = st.commit()

			if active_mat != null:
				shard_mesh_inst.material_override = active_mat

			var shard_collision: CollisionShape3D = CollisionShape3D.new()
			var convex_shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()

			var points: PackedVector3Array = [
				Vector3(lv1.x, lv1.y, half_thickness),
				Vector3(lv2.x, lv2.y, half_thickness),
				Vector3(lv3.x, lv3.y, half_thickness),
				Vector3(lv4.x, lv4.y, half_thickness),
				Vector3(lv1.x, lv1.y, -half_thickness),
				Vector3(lv2.x, lv2.y, -half_thickness),
				Vector3(lv3.x, lv3.y, -half_thickness),
				Vector3(lv4.x, lv4.y, -half_thickness)
			]

			convex_shape.points = points
			shard_collision.shape = convex_shape

			shard_body.add_child(shard_mesh_inst)
			shard_body.add_child(shard_collision)

			shard_body.position = center
			shard_body.freeze = true
			shard_body.visible = true
			shard_collision.disabled = false

			shards_container.add_child(shard_body)
			row_arr.append(shard_body)

		_shard_grid.append(row_arr)

	_update_material()


## Constructs triangular faces and normals for a single shard wedge.
func _add_faces_to_surfacetool(
	st: SurfaceTool,
	lv1: Vector2,
	lv2: Vector2,
	lv3: Vector2,
	lv4: Vector2,
	gv1: Vector2,
	gv2: Vector2,
	gv3: Vector2,
	gv4: Vector2,
	ht: float,
	size: Vector2
) -> void:
	var uv1: Vector2 = Vector2(gv1.x / size.x + 0.5, 0.5 - (gv1.y / size.y))
	var uv2: Vector2 = Vector2(gv2.x / size.x + 0.5, 0.5 - (gv2.y / size.y))
	var uv3: Vector2 = Vector2(gv3.x / size.x + 0.5, 0.5 - (gv3.y / size.y))
	var uv4: Vector2 = Vector2(gv4.x / size.x + 0.5, 0.5 - (gv4.y / size.y))

	st.set_normal(Vector3(0, 0, 1))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, ht))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, ht))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, ht))

	st.set_normal(Vector3(0, 0, -1))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, -ht))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, -ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, -ht))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, -ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, -ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, -ht))

	st.set_normal(Vector3(0, 1, 0))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, -ht))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, -ht))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, -ht))

	st.set_normal(Vector3(0, -1, 0))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, -ht))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, -ht))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, -ht))

	st.set_normal(Vector3(1, 0, 0))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, ht))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, ht))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, -ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, ht))
	st.set_uv(uv2)
	st.add_vertex(Vector3(lv2.x, lv2.y, -ht))
	st.set_uv(uv3)
	st.add_vertex(Vector3(lv3.x, lv3.y, -ht))

	st.set_normal(Vector3(-1, 0, 0))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, ht))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, ht))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, -ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, ht))
	st.set_uv(uv4)
	st.add_vertex(Vector3(lv4.x, lv4.y, -ht))
	st.set_uv(uv1)
	st.add_vertex(Vector3(lv1.x, lv1.y, -ht))


## Deactivates intact collision and generates shard pieces on initial shatter.
func _break_initial(hit_position: Vector3, hit_dir: Vector3) -> void:
	print("DestructibleGlass: Initial shatter triggered.")
	glass_broken.emit()

	intact_mesh.hide()
	intact_collision.set_deferred("disabled", true)
	set_deferred("contact_monitor", false)

	if not _shards_generated:
		_precalculate_shards()

	chip_glass(hit_position, hit_dir)


## Detaches shards within impact radius and imparts outward velocity.
func chip_glass(hit_position: Vector3, hit_dir: Vector3) -> void:
	print("DestructibleGlass: Chipping shards at impact point.")
	if break_sound != null:
		var sfx: AudioStreamPlayer3D = AudioPool.play_sfx_3d(break_sound, hit_position)
		if is_instance_valid(sfx):
			sfx.pitch_scale = randf_range(0.85, 1.15)

	for child: Node in shards_container.get_children():
		if not (child is DestructibleGlassShard):
			continue

		var shard: DestructibleGlassShard = child as DestructibleGlassShard
		if not shard.freeze or shard.is_destroyed:
			continue

		var dist: float = shard.global_position.distance_to(hit_position)
		if dist <= shatter_radius:
			shard.is_destroyed = true

			if (
				shard.grid_y >= 0
				and shard.grid_y < shard_rows
				and shard.grid_x >= 0
				and shard.grid_x < shard_cols
			):
				_shard_grid[shard.grid_y][shard.grid_x] = null

			if can_break:
				shard.freeze = false
				var shard_pos: Vector3 = shard.global_position
				var exp_dir: Vector3 = (shard_pos - hit_position).normalized()
				var final_dir: Vector3 = (hit_dir + exp_dir * 0.5).normalized()
				var force_mag: float = randf_range(5.0, 15.0)

				shard.apply_impulse(final_dir * force_mag)
				_schedule_shard_cleanup(shard)

	if can_break:
		_update_shard_connectivity()


## Evaluates structural edge connectivity, dropping unsupported island shards.
func _update_shard_connectivity() -> void:
	print("DestructibleGlass: Checking shard connectivity graph.")
	var visited: Array[Array] = []

	for r: int in range(shard_rows):
		var row_vis: Array[bool] = []
		for c: int in range(shard_cols):
			row_vis.append(false)
		visited.append(row_vis)

	var queue: Array[DestructibleGlassShard] = []

	for r: int in range(shard_rows):
		for c: int in range(shard_cols):
			if r == 0 or r == shard_rows - 1 or c == 0 or c == shard_cols - 1:
				var shard: DestructibleGlassShard = _shard_grid[r][c]
				if is_instance_valid(shard) and shard.freeze and not shard.is_destroyed:
					queue.append(shard)
					visited[r][c] = true

	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
	]

	while queue.size() > 0:
		var current: DestructibleGlassShard = queue.pop_front()
		for dir: Vector2i in directions:
			var nx: int = current.grid_x + dir.x
			var ny: int = current.grid_y + dir.y

			if nx >= 0 and nx < shard_cols and ny >= 0 and ny < shard_rows:
				if not visited[ny][nx]:
					var neighbor: DestructibleGlassShard = _shard_grid[ny][nx]
					if (
						is_instance_valid(neighbor)
						and neighbor.freeze
						and not neighbor.is_destroyed
					):
						visited[ny][nx] = true
						queue.append(neighbor)

	for r: int in range(shard_rows):
		for c: int in range(shard_cols):
			if not visited[r][c]:
				var island_shard: DestructibleGlassShard = _shard_grid[r][c]
				if (
					is_instance_valid(island_shard)
					and island_shard.freeze
					and not island_shard.is_destroyed
				):
					print("DestructibleGlass: Island detected. Dropping floating shard.")
					island_shard.freeze = false
					island_shard.is_destroyed = true
					_shard_grid[r][c] = null

					var tumble: Vector3 = Vector3(
						randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)
					)
					island_shard.apply_torque_impulse(tumble)
					_schedule_shard_cleanup(island_shard)


## Tweens detached shard scale down after delay before queueing node free.
func _schedule_shard_cleanup(shard: RigidBody3D) -> void:
	var mesh_inst: MeshInstance3D = null

	for child: Node in shard.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", true)
		elif child is MeshInstance3D:
			mesh_inst = child as MeshInstance3D

	if mesh_inst != null:
		var tween: Tween = create_tween()
		var random_delay: float = randf_range(0.1, shard_cleanup_time * 0.8)

		tween.tween_interval(random_delay)
		tween.tween_property(mesh_inst, "scale", Vector3(0.01, 0.01, 0.01), 0.5).set_ease(
			Tween.EASE_IN
		)
		tween.tween_callback(shard.queue_free)
	else:
		shard.queue_free()
