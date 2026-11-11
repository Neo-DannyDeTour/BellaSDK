extends MainLoop


func _process(_delta: float) -> bool:
	print("=== REVIEWER TEST START ===")
	var tscn: PackedScene = (
		ResourceLoader.load("res://props/gothic_arch/gothic_arch.tscn") as PackedScene
	)
	assert(tscn != null, "Failed to load gothic_arch.tscn")
	var inst: Node = tscn.instantiate()
	assert(inst != null, "Failed to instantiate gothic_arch.tscn")

	print("Root class: ", inst.get_class())
	print("Root script: ", inst.get_script())
	if inst.get_script() != null:
		var scr: Script = inst.get_script() as Script
		print("Root script path: ", scr.resource_path)
		print("arch_mesh property: ", inst.get("arch_mesh"))
	else:
		print("WARNING: Root has NO SCRIPT attached!")

	var root_3d: Node3D = Node3D.new()
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(root_3d)
		root_3d.add_child(inst)
		print("Added inst to scene tree successfully.")

	print("Children of inst:")
	for child: Node in inst.get_children():
		print(" - ", child.name, " (", child.get_class(), ")")

	inst.free()
	if root_3d != null and is_instance_valid(root_3d):
		root_3d.free()
	print("=== REVIEWER TEST END ===")
	return true
