class_name DestructibleGlass
extends RigidBody3D

signal glass_broken

@export var damage_threshold: float = 10.0
@export var impact_velocity_threshold: float = 5.0
@export var shard_cleanup_time: float = 5.0
@export var break_sound: AudioStream

var _is_broken: bool = false
@onready var intact_mesh: MeshInstance3D = $IntactMesh
@onready var intact_collision: CollisionShape3D = $IntactCollision
@onready var break_sound_player: AudioStreamPlayer3D = $BreakSound
@onready var shards_container: Node3D = $ShardsContainer


func _ready() -> void:
	print("DestructibleGlass: _ready called. Setting up...")
	body_entered.connect(_on_body_entered)
	if break_sound:
		break_sound_player.stream = break_sound
	_precalculate_shards()


func _precalculate_shards() -> void:
	print("DestructibleGlass: precalculating shards...")
	var size: Vector3 = Vector3(2.0, 2.0, 0.1)
	if intact_mesh.mesh is BoxMesh:
		size = intact_mesh.mesh.size

	var rows: int = 3
	var cols: int = 3
	var cell_width: float = size.x / float(cols)
	var cell_height: float = size.y / float(rows)
	var half_size_x: float = size.x / 2.0
	var half_size_y: float = size.y / 2.0
	var half_thickness: float = size.z / 2.0

	# 1. Generate shared vertices for the grid
	var grid_points := []
	var offset_range_x: float = cell_width * 0.4
	var offset_range_y: float = cell_height * 0.4

	for row in range(rows + 1):
		var row_points := []
		for col in range(cols + 1):
			var base_x: float = -half_size_x + col * cell_width
			var base_y: float = -half_size_y + row * cell_height

			var pt := Vector2(base_x, base_y)

			# Add randomness only to inner points
			if col > 0 and col < cols and row > 0 and row < rows:
				pt.x += randf_range(-offset_range_x, offset_range_x)
				pt.y += randf_range(-offset_range_y, offset_range_y)

			row_points.append(pt)
		grid_points.append(row_points)

	# 2. Build shards using the shared vertices
	for row in range(rows):
		for col in range(cols):
			var shard_body := RigidBody3D.new()
			shard_body.collision_layer = 8  # Debris layer based on project.godot
			shard_body.collision_mask = (1 << 0) | (1 << 1)  # Environment | Player

			# Get the 4 corners of this cell from the shared grid
			var v1: Vector2 = grid_points[row][col]
			var v2: Vector2 = grid_points[row][col + 1]
			var v3: Vector2 = grid_points[row + 1][col + 1]
			var v4: Vector2 = grid_points[row + 1][col]

			# Calculate the center point for the physics body origin
			var center_x := (v1.x + v2.x + v3.x + v4.x) / 4.0
			var center_y := (v1.y + v2.y + v3.y + v4.y) / 4.0
			var center := Vector3(center_x, center_y, 0)

			# Shift vertices so they are relative to the center
			var lv1 := v1 - Vector2(center.x, center.y)
			var lv2 := v2 - Vector2(center.x, center.y)
			var lv3 := v3 - Vector2(center.x, center.y)
			var lv4 := v4 - Vector2(center.x, center.y)

			var shard_mesh_inst := MeshInstance3D.new()
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)

			# Front face
			st.set_normal(Vector3(0, 0, 1))
			st.add_vertex(Vector3(lv1.x, lv1.y, half_thickness))
			st.add_vertex(Vector3(lv2.x, lv2.y, half_thickness))
			st.add_vertex(Vector3(lv3.x, lv3.y, half_thickness))

			st.add_vertex(Vector3(lv1.x, lv1.y, half_thickness))
			st.add_vertex(Vector3(lv3.x, lv3.y, half_thickness))
			st.add_vertex(Vector3(lv4.x, lv4.y, half_thickness))

			# Back face
			st.set_normal(Vector3(0, 0, -1))
			st.add_vertex(Vector3(lv3.x, lv3.y, -half_thickness))
			st.add_vertex(Vector3(lv2.x, lv2.y, -half_thickness))
			st.add_vertex(Vector3(lv1.x, lv1.y, -half_thickness))

			st.add_vertex(Vector3(lv4.x, lv4.y, -half_thickness))
			st.add_vertex(Vector3(lv3.x, lv3.y, -half_thickness))
			st.add_vertex(Vector3(lv1.x, lv1.y, -half_thickness))

			# Top face
			st.set_normal(Vector3(0, 1, 0))
			st.add_vertex(Vector3(lv4.x, lv4.y, half_thickness))
			st.add_vertex(Vector3(lv3.x, lv3.y, half_thickness))
			st.add_vertex(Vector3(lv3.x, lv3.y, -half_thickness))

			st.add_vertex(Vector3(lv4.x, lv4.y, half_thickness))
			st.add_vertex(Vector3(lv3.x, lv3.y, -half_thickness))
			st.add_vertex(Vector3(lv4.x, lv4.y, -half_thickness))

			# Bottom face
			st.set_normal(Vector3(0, -1, 0))
			st.add_vertex(Vector3(lv2.x, lv2.y, half_thickness))
			st.add_vertex(Vector3(lv1.x, lv1.y, half_thickness))
			st.add_vertex(Vector3(lv1.x, lv1.y, -half_thickness))

			st.add_vertex(Vector3(lv2.x, lv2.y, half_thickness))
			st.add_vertex(Vector3(lv1.x, lv1.y, -half_thickness))
			st.add_vertex(Vector3(lv2.x, lv2.y, -half_thickness))

			# Right face
			st.set_normal(Vector3(1, 0, 0))
			st.add_vertex(Vector3(lv3.x, lv3.y, half_thickness))
			st.add_vertex(Vector3(lv2.x, lv2.y, half_thickness))
			st.add_vertex(Vector3(lv2.x, lv2.y, -half_thickness))

			st.add_vertex(Vector3(lv3.x, lv3.y, half_thickness))
			st.add_vertex(Vector3(lv2.x, lv2.y, -half_thickness))
			st.add_vertex(Vector3(lv3.x, lv3.y, -half_thickness))

			# Left face
			st.set_normal(Vector3(-1, 0, 0))
			st.add_vertex(Vector3(lv1.x, lv1.y, half_thickness))
			st.add_vertex(Vector3(lv4.x, lv4.y, half_thickness))
			st.add_vertex(Vector3(lv4.x, lv4.y, -half_thickness))

			st.add_vertex(Vector3(lv1.x, lv1.y, half_thickness))
			st.add_vertex(Vector3(lv4.x, lv4.y, -half_thickness))
			st.add_vertex(Vector3(lv1.x, lv1.y, -half_thickness))

			shard_mesh_inst.mesh = st.commit()
			if intact_mesh.mesh and intact_mesh.mesh.material:
				shard_mesh_inst.material_override = intact_mesh.mesh.material

			var shard_collision := CollisionShape3D.new()
			var convex_shape := ConvexPolygonShape3D.new()

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


func _on_body_entered(body: Node) -> void:
	if _is_broken:
		return

	print("DestructibleGlass: body_entered called. Body: ", body.name)

	if body is RigidBody3D:
		# Calculate relative velocity
		var rel_vel: Vector3 = body.linear_velocity - linear_velocity
		var speed: float = rel_vel.length()

		if speed >= impact_velocity_threshold:
			print(
				"DestructibleGlass: Impact velocity threshold met (",
				speed,
				" >= ",
				impact_velocity_threshold,
				")"
			)
			var hit_dir: Vector3 = rel_vel.normalized()
			break_glass(body.global_position, hit_dir)


func take_damage(amount: float, hit_position: Vector3, hit_dir: Vector3) -> void:
	if _is_broken:
		return

	print("DestructibleGlass: take_damage called. Amount: ", amount)
	if amount >= damage_threshold:
		print("DestructibleGlass: Damage threshold met (", amount, " >= ", damage_threshold, ")")
		break_glass(hit_position, hit_dir)


func break_glass(hit_position: Vector3, hit_dir: Vector3) -> void:
	if _is_broken:
		return
	_is_broken = true
	print("DestructibleGlass: break_glass called. Emitting glass_broken signal.")

	glass_broken.emit()

	if break_sound_player.stream:
		break_sound_player.play()

	intact_mesh.hide()
	intact_collision.set_deferred("disabled", true)

	# Disable the main body contact monitor so it stops registering impacts
	contact_monitor = false

	# Spawn shards
	for child in shards_container.get_children():
		if child is RigidBody3D:
			child.visible = true
			child.freeze = false

			var shard_col := child.get_child(1) as CollisionShape3D
			if shard_col:
				shard_col.set_deferred("disabled", false)

			# Apply impact force. Calculate distance from hit position
			# Since shards are at origin, we use their bounds/center to approximate position.
			# But for simplicity, we just apply a general impulse in the hit_dir.
			# A more accurate Half-Life feel applies an explosive force from hit pos.
			var shard_world_pos: Vector3 = child.global_position
			var explode_dir: Vector3 = (shard_world_pos - hit_position).normalized()

			# Blend the impact direction and the explosive direction
			var final_dir: Vector3 = (hit_dir + explode_dir * 0.5).normalized()

			var force_magnitude: float = randf_range(5.0, 15.0)
			child.apply_impulse(final_dir * force_magnitude)

	# Cleanup timer
	var timer := get_tree().create_timer(shard_cleanup_time)
	timer.timeout.connect(_on_cleanup_timeout)


func _on_cleanup_timeout() -> void:
	print("DestructibleGlass: cleanup timeout. Removing shards.")
	queue_free()
