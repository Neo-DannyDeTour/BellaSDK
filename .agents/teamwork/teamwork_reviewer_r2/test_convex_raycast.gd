extends MainLoop

var frame_count: int = 0
var sb: StaticBody3D


func _process(_delta: float) -> bool:
	frame_count += 1
	var tree: SceneTree = Engine.get_main_loop() as SceneTree

	if frame_count == 1:
		sb = StaticBody3D.new()
		sb.collision_layer = 1
		# Create root 3D node
		var root3d: Node3D = Node3D.new()
		var view: Viewport = tree.root
		view.add_child(root3d)
		root3d.add_child(sb)

		# Left Pillar
		var col_lp: CollisionShape3D = CollisionShape3D.new()
		var box_lp: BoxShape3D = BoxShape3D.new()
		box_lp.size = Vector3(0.6, 2.8, 0.8)
		col_lp.shape = box_lp
		col_lp.position = Vector3(-1.2, 1.4, 0.0)
		sb.add_child(col_lp)

		# Right Pillar
		var col_rp: CollisionShape3D = CollisionShape3D.new()
		var box_rp: BoxShape3D = BoxShape3D.new()
		box_rp.size = Vector3(0.6, 2.8, 0.8)
		col_rp.shape = box_rp
		col_rp.position = Vector3(1.2, 1.4, 0.0)
		sb.add_child(col_rp)

		# Top Lintel (above apex at 3.55)
		var col_tl: CollisionShape3D = CollisionShape3D.new()
		var box_tl: BoxShape3D = BoxShape3D.new()
		box_tl.size = Vector3(3.0, 0.45, 0.8)
		col_tl.shape = box_tl
		col_tl.position = Vector3(0.0, 3.775, 0.0)
		sb.add_child(col_tl)

		# Left Shoulder (convex)
		var col_ls: CollisionShape3D = CollisionShape3D.new()
		var cv_ls: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		cv_ls.points = PackedVector3Array(
			[
				Vector3(-1.5, 2.8, -0.4),
				Vector3(-1.5, 2.8, 0.4),
				Vector3(-1.5, 3.55, -0.4),
				Vector3(-1.5, 3.55, 0.4),
				Vector3(-0.9, 2.8, -0.4),
				Vector3(-0.9, 2.8, 0.4),
				Vector3(-0.6, 3.15, -0.4),
				Vector3(-0.6, 3.15, 0.4),
				Vector3(-0.25, 3.45, -0.4),
				Vector3(-0.25, 3.45, 0.4),
				Vector3(0.0, 3.55, -0.4),
				Vector3(0.0, 3.55, 0.4),
			]
		)
		col_ls.shape = cv_ls
		sb.add_child(col_ls)

		# Right Shoulder (convex)
		var col_rs: CollisionShape3D = CollisionShape3D.new()
		var cv_rs: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		cv_rs.points = PackedVector3Array(
			[
				Vector3(1.5, 2.8, -0.4),
				Vector3(1.5, 2.8, 0.4),
				Vector3(1.5, 3.55, -0.4),
				Vector3(1.5, 3.55, 0.4),
				Vector3(0.9, 2.8, -0.4),
				Vector3(0.9, 2.8, 0.4),
				Vector3(0.6, 3.15, -0.4),
				Vector3(0.6, 3.15, 0.4),
				Vector3(0.25, 3.45, -0.4),
				Vector3(0.25, 3.45, 0.4),
				Vector3(0.0, 3.55, -0.4),
				Vector3(0.0, 3.55, 0.4),
			]
		)
		col_rs.shape = cv_rs
		sb.add_child(col_rs)
		return false

	if frame_count == 3:
		var space: PhysicsDirectSpaceState3D = sb.get_world_3d().direct_space_state
		var heights: Array[float] = [1.0, 2.0, 2.8, 3.0, 3.2, 3.4, 3.5, 3.6, 3.8]
		for y: float in heights:
			var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				Vector3(0.0, float(y), -2.0), Vector3(0.0, float(y), 2.0), 1
			)
			var res: Dictionary = space.intersect_ray(q)
			print("Center X=0, Y=", y, ": hit = ", not res.is_empty())

		# Test raycast through pillar at X = -1.2, Y = 1.4:
		var q_pil: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			Vector3(-1.2, 1.4, -2.0), Vector3(-1.2, 1.4, 2.0), 1
		)
		var res_pil: Dictionary = space.intersect_ray(q_pil)
		print("Pillar X=-1.2, Y=1.4: hit = ", not res_pil.is_empty())

		# Test raycast through left shoulder at X = -0.8, Y = 3.2:
		var q_sh: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			Vector3(-0.8, 3.2, -2.0), Vector3(-0.8, 3.2, 2.0), 1
		)
		var res_sh: Dictionary = space.intersect_ray(q_sh)
		print("Shoulder X=-0.8, Y=3.2: hit = ", not res_sh.is_empty())

		sb.get_parent().free()
		return true

	return false
