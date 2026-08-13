@tool
class_name DestructibleGlass
extends RigidBody3D

signal glass_broken

@export_group("Dimensions & Shards")
## Glass size.
@export var glass_size: Vector2 = Vector2(2.0, 2.0):
	set(value):
		glass_size = value
		_apply_dimensions()
		_update_material()

## Glass thickness.
@export var glass_thickness: float = 0.1:
	set(value):
		glass_thickness = value
		_apply_dimensions()

## Shard rows.
@export var shard_rows: int = 3
## Shard cols.
@export var shard_cols: int = 3

@export_group("Damage Properties")
## Can break.
@export var can_break: bool = true:
	set(value):
		can_break = value
		_update_material()

## Shatter radius.
@export var shatter_radius: float = 0.8
## Damage threshold.
@export var damage_threshold: float = 10.0
## Impact velocity threshold.
@export var impact_velocity_threshold: float = 5.0
## Shard cleanup time.
@export var shard_cleanup_time: float = 5.0
## Break sound.
@export var break_sound: AudioStream

@export_group("Shader Parameters")
## Glass color.
@export var glass_color: Color = Color(0.8, 0.9, 1.0, 0.4):
	set(value):
		glass_color = value
		_update_material()

## Net color.
@export var net_color: Color = Color(0.1, 0.1, 0.1, 1.0):
	set(value):
		net_color = value
		_update_material()

## Net scale.
@export var net_scale: float = 20.0:
	set(value):
		net_scale = value
		_update_material()

## Is broken.
var _is_broken: bool = false
## Shard grid.
var _shard_grid: Array = []

## Intact mesh.
@onready var intact_mesh: MeshInstance3D = $IntactMesh
## Intact collision.
@onready var intact_collision: CollisionShape3D = $IntactCollision
## Break sound player.
@onready var break_sound_player: AudioStreamPlayer3D = $BreakSound
## Shards container.
@onready var shards_container: Node3D = $ShardsContainer


# ==========================================
# Inner Class: Intercepts damage on shards
# ==========================================
class GlassShard:
	extends RigidBody3D
	var main_glass: DestructibleGlass
	var grid_x: int = -1
	var grid_y: int = -1
	var is_destroyed: bool = false

	func _ready() -> void:
		contact_monitor = true
		max_contacts_reported = 1
		body_entered.connect(_on_shard_body_entered)

	func take_damage(amount: float, hit_position: Vector3, hit_dir: Vector3) -> void:
		if main_glass == null:
			return

		print("GlassShard: take_damage registered. Relaying to root glass node.")
		if freeze and not is_destroyed:
			main_glass.chip_glass(hit_position, hit_dir)
		elif not freeze:
			apply_impulse(hit_dir * (amount * 0.5), hit_position - global_position)

	func _on_shard_body_entered(body: Node) -> void:
		if not freeze or is_destroyed or main_glass == null:
			return

		var speed: float = 0.0
		var rel_vel: Vector3 = Vector3.ZERO

		if body is RigidBody3D:
			rel_vel = body.linear_velocity - linear_velocity
			speed = rel_vel.length()
		elif body is CharacterBody3D:
			rel_vel = body.velocity
			speed = rel_vel.length()

		if speed >= main_glass.impact_velocity_threshold:
			print("GlassShard: Physical impact velocity met. Relaying to root node.")
			main_glass.chip_glass(global_position, rel_vel.normalized())


# ==========================================
# Main Node Logic
# ==========================================
func _ready() -> void:
	_apply_dimensions()
	_update_material()

	if Engine.is_editor_hint():
		return

	if not scale.is_equal_approx(Vector3.ONE):
		print("DestructibleGlass (", name, "): Baking scale into dimensions.")
		# FIX 1: Assign the whole vector to guarantee the setter fires
		glass_size = Vector2(glass_size.x * scale.x, glass_size.y * scale.y)
		glass_thickness *= scale.z
		scale = Vector3.ONE

	body_entered.connect(_on_body_entered)

	if break_sound != null:
		break_sound_player.stream = break_sound

	_precalculate_shards()


func _apply_dimensions() -> void:
	if not is_inside_tree():
		return

	var mesh_inst: MeshInstance3D = get_node_or_null("IntactMesh") as MeshInstance3D
	var coll: CollisionShape3D = get_node_or_null("IntactCollision") as CollisionShape3D

	if mesh_inst != null and mesh_inst.mesh is BoxMesh:
		(mesh_inst.mesh as BoxMesh).size = Vector3(glass_size.x, glass_size.y, glass_thickness)

	if coll != null and coll.shape is BoxShape3D:
		(coll.shape as BoxShape3D).size = Vector3(glass_size.x, glass_size.y, glass_thickness)


func _update_material() -> void:
	if not is_inside_tree():
		return

	print("DestructibleGlass (", name, "): Updating material parameters on all meshes.")

	var mesh_inst: MeshInstance3D = get_node_or_null("IntactMesh") as MeshInstance3D
	if mesh_inst != null:
		_apply_instance_shader_parameters(mesh_inst)

	var container: Node3D = get_node_or_null("ShardsContainer") as Node3D
	if container != null:
		for child: Node in container.get_children():
			if child is RigidBody3D:
				for sub_child: Node in child.get_children():
					if sub_child is MeshInstance3D:
						_apply_instance_shader_parameters(sub_child)


func _apply_instance_shader_parameters(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.set_instance_shader_parameter("is_armored", not can_break)
	mesh_instance.set_instance_shader_parameter("glass_scale", glass_size)
	mesh_instance.set_instance_shader_parameter("glass_color", glass_color)
	mesh_instance.set_instance_shader_parameter("net_color", net_color)
	mesh_instance.set_instance_shader_parameter("net_scale", net_scale)


func take_damage(amount: float, hit_position: Vector3, hit_dir: Vector3) -> void:
	# Removed the early return that blocked damage when can_break was false.
	print("DestructibleGlass (", name, "): take_damage registered: ", amount)

	if amount >= damage_threshold:
		if not _is_broken:
			_is_broken = true
			call_deferred("_break_initial", hit_position, hit_dir)
		else:
			call_deferred("chip_glass", hit_position, hit_dir)


func _on_body_entered(body: Node) -> void:
	if _is_broken:
		return

	print("DestructibleGlass (", name, "): Checking body impact velocity.")
	var speed: float = 0.0
	var rel_vel: Vector3 = Vector3.ZERO

	if body is RigidBody3D:
		rel_vel = body.linear_velocity - linear_velocity
		speed = rel_vel.length()
	elif body is CharacterBody3D:
		rel_vel = body.velocity
		speed = rel_vel.length()

	if speed >= impact_velocity_threshold:
		# Removed the early return for armored glass here as well.
		print("DestructibleGlass (", name, "): Impact velocity met. Breaking.")
		_is_broken = true
		var hit_dir: Vector3 = rel_vel.normalized()
		call_deferred("_break_initial", body.global_position, hit_dir)


func _precalculate_shards() -> void:
	print("DestructibleGlass (", name, "): Building grid and shard vertices...")

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

	# ---------------------------------------------------------
	# MATERIAL EXTRACTION FIX
	# ---------------------------------------------------------
	var active_mat: Material = intact_mesh.material_override

	if active_mat == null:
		active_mat = intact_mesh.get_surface_override_material(0)

	if active_mat == null and intact_mesh.mesh != null:
		if intact_mesh.mesh is PrimitiveMesh:
			# Safely targets the BoxMesh material property
			active_mat = intact_mesh.mesh.material
		elif intact_mesh.mesh.get_surface_count() > 0:
			active_mat = intact_mesh.mesh.surface_get_material(0)

	if active_mat == null:
		print("DestructibleGlass (", name, "): WARNING - No material found on IntactMesh to copy!")
	else:
		print("DestructibleGlass (", name, "): Material successfully found. Applying to shards...")
	# ---------------------------------------------------------

	_shard_grid.clear()

	for row: int in range(shard_rows):
		var row_arr: Array = []
		for col: int in range(shard_cols):
			var shard_body: GlassShard = GlassShard.new()
			shard_body.main_glass = self
			shard_body.grid_x = col
			shard_body.grid_y = row
			shard_body.collision_layer = 8
			shard_body.collision_mask = (1 << 0) | (1 << 1)

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
			shard_body.visible = false
			shard_collision.disabled = true

			shards_container.add_child(shard_body)
			row_arr.append(shard_body)

		_shard_grid.append(row_arr)

	_update_material()


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

	# Front
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

	# Back
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

	# Edges
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


func _break_initial(hit_position: Vector3, hit_dir: Vector3) -> void:
	print("DestructibleGlass (", name, "): Initial shatter triggered.")
	glass_broken.emit()

	intact_mesh.hide()
	intact_collision.set_deferred("disabled", true)
	set_deferred("contact_monitor", false)

	for child: Node in shards_container.get_children():
		if child is GlassShard:
			child.visible = true
			_enable_shard_collision(child)

	chip_glass(hit_position, hit_dir)


func chip_glass(hit_position: Vector3, hit_dir: Vector3) -> void:
	print("DestructibleGlass (", name, "): Chipping shards at impact point.")

	if break_sound_player.stream != null:
		break_sound_player.pitch_scale = randf_range(0.85, 1.15)
		break_sound_player.play()

	for child: Node in shards_container.get_children():
		if child is GlassShard and child.freeze and not child.is_destroyed:
			var dist: float = child.global_position.distance_to(hit_position)

			if dist <= shatter_radius:
				child.is_destroyed = true

				# Erase the dead reference from the tracking grid
				if (
					child.grid_y >= 0
					and child.grid_y < shard_rows
					and child.grid_x >= 0
					and child.grid_x < shard_cols
				):
					_shard_grid[child.grid_y][child.grid_x] = null

				# Only unfreeze and explode the glass if it is breakable
				if can_break:
					child.freeze = false
					var shard_world_pos: Vector3 = child.global_position
					var explode_dir: Vector3 = (shard_world_pos - hit_position).normalized()
					var final_dir: Vector3 = (hit_dir + explode_dir * 0.5).normalized()
					var force_mag: float = randf_range(5.0, 15.0)

					child.apply_impulse(final_dir * force_mag)
					_schedule_shard_cleanup(child)

	# Only drop unconnected "island" shards if the glass is breakable
	if can_break:
		_update_shard_connectivity()


func _update_shard_connectivity() -> void:
	print("DestructibleGlass (", name, "): Checking shard graph connectivity...")
	var visited: Array = []

	for r: int in range(shard_rows):
		var row_vis: Array[bool] = []
		for c: int in range(shard_cols):
			row_vis.append(false)
		visited.append(row_vis)

	var queue: Array[GlassShard] = []

	# 1. Find the anchored shards along the edges of the frame
	for r: int in range(shard_rows):
		for c: int in range(shard_cols):
			if r == 0 or r == shard_rows - 1 or c == 0 or c == shard_cols - 1:
				# Explicitly typed as Variant to satisfy strict GDLint/Compiler constraints
				var cell: Variant = _shard_grid[r][c]
				if is_instance_valid(cell):
					var shard: GlassShard = cell as GlassShard
					if shard.freeze and not shard.is_destroyed:
						queue.append(shard)
						visited[r][c] = true

	# 2. Flood fill (BFS) inward to find all shards still supported by an edge
	var directions: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
	]

	while queue.size() > 0:
		var current: GlassShard = queue.pop_front()
		for dir: Vector2i in directions:
			var nx: int = current.grid_x + dir.x
			var ny: int = current.grid_y + dir.y

			if nx >= 0 and nx < shard_cols and ny >= 0 and ny < shard_rows:
				if not visited[ny][nx]:
					# Explicitly typed as Variant to satisfy strict constraints safely
					var cell: Variant = _shard_grid[ny][nx]
					if is_instance_valid(cell):
						var neighbor: GlassShard = cell as GlassShard
						if neighbor.freeze and not neighbor.is_destroyed:
							visited[ny][nx] = true
							queue.append(neighbor)

	# 3. Drop unvisited shards (the floating islands)
	for r: int in range(shard_rows):
		for c: int in range(shard_cols):
			if not visited[r][c]:
				var cell: Variant = _shard_grid[r][c]
				if is_instance_valid(cell):
					var shard: GlassShard = cell as GlassShard
					if shard.freeze and not shard.is_destroyed:
						print(
							"DestructibleGlass (",
							name,
							"): Island detected. Dropping floating shard."
						)
						shard.freeze = false
						shard.is_destroyed = true

						_shard_grid[r][c] = null

						var natural_tumble: Vector3 = Vector3(
							randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)
						)
						shard.apply_torque_impulse(natural_tumble)
						_schedule_shard_cleanup(shard)


func _enable_shard_collision(shard: RigidBody3D) -> void:
	for child_node: Node in shard.get_children():
		if child_node is CollisionShape3D:
			child_node.set_deferred("disabled", false)
			break


func _schedule_shard_cleanup(shard: RigidBody3D) -> void:
	var mesh_inst: MeshInstance3D = null

	for child: Node in shard.get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
		elif child is MeshInstance3D:
			mesh_inst = child

	if mesh_inst != null:
		var tween: Tween = get_tree().create_tween()
		var random_delay: float = randf_range(0.1, shard_cleanup_time * 0.8)

		tween.tween_interval(random_delay)
		tween.tween_property(mesh_inst, "scale", Vector3(0.01, 0.01, 0.01), 0.5).set_ease(
			Tween.EASE_IN
		)
		tween.tween_callback(shard.queue_free)
	else:
		shard.queue_free()
