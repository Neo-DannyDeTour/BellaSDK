extends SceneTree


func _init() -> void:
	var tscn: PackedScene = (
		ResourceLoader.load("res://props/gothic_arch/gothic_arch.tscn") as PackedScene
	)
	var inst: StaticBody3D = tscn.instantiate() as StaticBody3D
	root.add_child(inst)

	# In physics, we need a physics step to update the space state
	# Or test directly with direct collision test against the colliders:
	var left_col: CollisionShape3D = inst.get_node("LeftPillarCol") as CollisionShape3D
	var right_col: CollisionShape3D = inst.get_node("RightPillarCol") as CollisionShape3D
	var top_col: CollisionShape3D = inst.get_node("TopLintelCol") as CollisionShape3D

	var top_box: BoxShape3D = top_col.shape as BoxShape3D
	print("TopLintelCol pos: ", top_col.position, " size: ", top_box.size)
	var top_min_y: float = top_col.position.y - top_box.size.y * 0.5
	var top_max_y: float = top_col.position.y + top_box.size.y * 0.5
	var top_min_x: float = top_col.position.x - top_box.size.x * 0.5
	var top_max_x: float = top_col.position.x + top_box.size.x * 0.5
	print(
		"TopLintel bounds: X in [",
		top_min_x,
		", ",
		top_max_x,
		"], Y in [",
		top_min_y,
		", ",
		top_max_y,
		"]"
	)

	# Center arch vault opening extends up to ~3.55m
	# If someone is at X=0, Y=3.0, Z=0:
	var test_pt: Vector3 = Vector3(0.0, 3.0, 0.0)
	var is_inside_top_lintel: bool = (
		test_pt.x >= top_min_x
		and test_pt.x <= top_max_x
		and test_pt.y >= top_min_y
		and test_pt.y <= top_max_y
	)
	print("Point (0, 3.0, 0) inside TopLintelCol: ", is_inside_top_lintel)

	inst.free()
	quit(0)
