extends SceneTree


func _init() -> void:
	var scn: PackedScene = (
		ResourceLoader.load("res://props/gothic_arch/gothic_arch.tscn") as PackedScene
	)
	var inst: Node = scn.instantiate()
	print("inst: ", inst)
	print("arch_mesh property on inst: ", inst.get(&"arch_mesh"))
	root.add_child(inst)
	print("arch_mesh property after add_child: ", inst.get(&"arch_mesh"))
	inst.free()
	quit(0)
