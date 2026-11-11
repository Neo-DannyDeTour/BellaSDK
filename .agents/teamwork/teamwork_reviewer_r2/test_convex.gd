extends SceneTree


func _init() -> void:
	var shape: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	var points: PackedVector3Array = PackedVector3Array(
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
	shape.points = points
	print("ConvexPolygonShape3D points count: ", shape.points.size())
	quit(0)
