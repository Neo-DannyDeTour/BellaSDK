extends SceneTree

func _init():
	var rd = RenderingServer.get_rendering_device()
	var methods = rd.get_method_list()
	for m in methods:
		if "barrier" in m.name.to_lower():
			print(m.name)
	quit()
