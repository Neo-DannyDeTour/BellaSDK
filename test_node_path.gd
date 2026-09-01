extends SceneTree

func _init():
	var dummy_body = Node3D.new()
	var components_node = Node.new()
	components_node.name = "Components"
	dummy_body.add_child(components_node)

	var health_comp = Node.new()
	health_comp.name = "HealthComponent"
	components_node.add_child(health_comp)

	var res = dummy_body.get_node_or_null("Components/HealthComponent")
	print("Res: ", res)
	quit()
